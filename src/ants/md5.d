/* Copyright 2014 Donny Viszneki. All rights reserved.
 * You are not authorized to distribute this source code.
 */
module ants.md5;
import file = std.file;
import std.string;
import std.conv;
import std.algorithm : map, appender;
import std.exception : enforce;
import std.path : dirName;
//import derelict.opengl3.gl3;
import glad.gl.all;
import gl3n.linalg : Matrix, Vector, Quaternion, cross;
import gl3n.interpolate : lerp;
import ants.vertexer;
import ants.material;
import ants.shader;
import ants.texture;
import ants.gametime;
import ants.glutil;
import std.math : sqrt;
import std.stdio : writeln, writefln;

private alias Vector!(double, 3) vec3;
private alias Vector!(double, 2) vec2;
private alias Vector!(float, 2) vec2f;
private alias Vector!(float, 3) vec3f;
private alias Vector!(float, 4) vec4f;
alias Matrix!(double, 3, 3) mat3;
alias Matrix!(double, 4, 4) mat4;
alias Quaternion!(double) quat;

private Vertexer vertexer;
private Material emptyMaterial;
private ShaderProgram shaderProgram;
private ShaderProgram shaderProgram1;
private ShaderProgram md5ShaderProgram;
private ShaderProgram varyingColorShaderProgram;

private struct Ray
{
  vec3 pos;
  quat orient;

  this(vec3 pos, quat orient)
  {
    this.pos = pos;
    this.orient = orient;
  }

  this(float px, float py, float pz, float ow, float ox, float oy, float oz)
  {
    this.pos = vec3(px, py, pz);
    this.orient = quat(ow, ox, oy, oz);
  }

  this(float px, float py, float pz, float ox, float oy, float oz)
  {
    this.pos = vec3(px, py, pz);
    this.orient = quat(0, ox, oy, oz);
  }
}

private struct Joint
{
  int parentIndex;
  Ray ray;

  this(int parentIndex, float px, float py, float pz, float ox, float oy, float oz)
  {
    this.parentIndex = parentIndex;
    this.ray = Ray(vec3(px, py, pz), quat(0.0, ox, oy, oz));
  }

  this(int parentIndex, vec3 pos, quat orient)
  {
    this.parentIndex = parentIndex;
    this.ray.pos = pos;
    this.ray.orient = orient;
  }
}

struct Vert
{
  vec2 uv;
  uint weightIndex;
  uint numWeights;
}

/* This layout should eventually replace Vert I think. Right now I will just copy a mesh's Verts
 * into a GPUVert[] and send the data to a GL Buffer Object.
 */
struct GPUVert
{
  vec4f[4]  weightPos;
  float[4]  weightBiases;
  vec4f     weightIndices;
  vec2f     uv;
  vec2f     pad;
}

struct Tri
{
  uint[3] vi; // verts
  this(int a, int b, int c)
  {
    this.vi[0] = a;
    this.vi[1] = b;
    this.vi[2] = c;
  }
}

struct Weight
{
  size_t jointIndex;
  float weightBias;
  vec3 pos;
  this(size_t jointIndex, float weightBias, float posx, float posy, float posz)
  {
    this.jointIndex = jointIndex;
    this.weightBias = weightBias;
    this.pos.x = posx;
    this.pos.y = posy;
    this.pos.z = posz;
  }
}

struct Mesh
{
  size_t numVerts;
  Material material;
  Vert[] verts;
  size_t numTris;
  Tri[] tris;
  size_t numWeights;
  Weight[] weights;
}

private enum ParserMode
{
  open,
  joints,
  meshes,
  bounds,
  baseframe,
  frame
}

/*  Changes q.w so that the quaternion is a unit quaternion.
 *  If the other three components do not represent a unit
 *  vector, q.w will be set to 0.
 */
void computeUnitQuatW(ref quat q)
{
  float t = 1f - q.x.sq() - q.y.sq() - q.z.sq();
  if (t<=0f)
    q.w = 0;
  else
    q.w = -sqrt(t);
}

class MD5Model
{
  Joint[] joints;
  size_t[string] namedJoints;
  Mesh[] meshes;

  float spin;

  /* Generates a frequency distribution of vertex weight counts */
  uint[] getWeightingInfo()
  {
    uint[] rval;
    foreach (mesh; meshes)
    {
      foreach (vert; mesh.verts)
      {
        auto nw = vert.numWeights;
        if (nw >= rval.length)
          rval.length = nw+1;
        rval[nw]++;
      }
    }
    return rval;
  }

  void draw()
  {
    /* THIS DOESN'T EVEN MATTER */
    assert(0, "NOT DONE");
    foreach (mesh; meshes)
    {
      foreach (tri; mesh.tris)
      {
        foreach (vi; tri.vi)
        {
          Vert vert = mesh.verts[vi];
          assert(vert.numWeights == 1, "only one weight per vertex is currently supported");
          Weight weight = mesh.weights[vert.weightIndex];
          assert(weight.weightBias == 1.0, "weight bias is wrong!");
          Joint joint = joints[weight.jointIndex];

          vec3 p = joint.ray.pos + weight.pos;

          vertexer.add(p,
            vec2(0, 0),     /* UVs */ 
            vec3(1, 0, 0),  /* normal */
            vec3f(.7, .7, .7) /* color */
            );
        }
      }
    }
  }

  this(string filename)
  {
    spin = 0.0f;

    int mode = ParserMode.open;
    size_t nJoints;
    size_t nMeshes;
    //string dir = dirName(filename) ~ "/";

    foreach (lineNo, line; splitLines(to!string(cast(char[])file.read(filename))))
    {
      auto words = split(line);

      if (words.length > 0)
      switch (mode)
      {
        case ParserMode.open:
          if (words[0] == "MD5Version")
          {
            assert(to!int(words[1]) == 10);
          }
          else if (words[0] == "commandline")
          {
            // do nothing
          }
          else if (words[0] == "numJoints")
          {
            nJoints = to!int(words[1]);
            joints.reserve(nJoints);
          }
          else if (words[0] == "numMeshes")
          {
            nMeshes = to!int(words[1]);
            meshes.reserve(nMeshes);
          }
          else if (words[0] == "joints")
          {
            // TODO this parser is bullshit
            enforce(words[1] == "{");
            mode = ParserMode.joints;
          }
          else if (words[0] == "mesh")
          {
            enforce(words[1] == "{");
            meshes ~= Mesh();
            mode = ParserMode.meshes;
          }
          break;
        
        case ParserMode.joints:
          if (words[0] == "}")
          {
            enforce(joints.length == nJoints, "wrong number of joints");
            mode = ParserMode.open;
          }
          else
          {
            enforce(words[0][0] == '"', "joint syntax error 0");
            enforce(words[0][$-1] == '"', "joint syntax error 1");
            enforce(words[2] == "(", "joint syntax error 2");
            enforce(words[6] == ")", "joint syntax error 3");
            enforce(words[7] == "(", "joint syntax error 4");
            enforce(words[11] == ")", "joint syntax error 5");

            quat orient = quat(
              0f,
              to!float(words[8]),
              to!float(words[9]),
              to!float(words[10]));
            orient.computeUnitQuatW();

            vec3 pos = vec3(
              to!float(words[3]),
              to!float(words[4]),
              to!float(words[5]));

            Joint joint = Joint(to!int(words[1]), pos, orient);

            namedJoints[words[0]] = joints.length; // TODO strip quotes
            joints ~= joint;
          }
          break;

        case ParserMode.meshes:
          if (words[0] == "}")
          {
            //enforce(meshes.length == nMeshes, "wrong number of meshes");
            mode = ParserMode.open;
          }
          else if (words[0] == "shader")
          {
            //string textureFilename = dir ~ words[1][1..$-1];
            string textureFilename = words[1][1..$-1];
            //writefln("[md5] shader \"%s\"", textureFilename);
            auto materialTexture = new MaterialTexture();
            materialTexture.application = TextureApplication.Color;
            materialTexture.texture = getTexture(textureFilename);
            auto material = new Material();
            material.texes ~= materialTexture;
            meshes[$-1].material = material;
          }
          else if (words[0] == "numverts")
          {
            meshes[$-1].numVerts = to!uint(words[1]);
            meshes[$-1].verts.reserve(meshes[$-1].numVerts);
          }
          else if (words[0] == "vert")
          {
            enforce(to!int(words[1]) == meshes[$-1].verts.length, "mesh vertices out of order");
            enforce(words[2] == "(", "vert syntax error 0");
            enforce(words[5] == ")", "vert syntax error 1");

            Vert vert = Vert(
              vec2(to!double(words[3]),
                   to!double(words[4])),  // uv
              to!uint(words[6]),          // Vert.weightIndex
              to!uint(words[7]));         // Vert.numWeights

            meshes[$-1].verts ~= vert;
          }
          else if (words[0] == "numtris")
          {
            meshes[$-1].numTris = to!size_t(words[1]);
            meshes[$-1].tris.reserve(meshes[$-1].numTris);
          }
          else if (words[0] == "tri")
          {
            enforce(to!size_t(words[1]) == meshes[$-1].tris.length, "mesh tris out of order");
            Tri tri = Tri(to!uint(words[2]),
                          to!uint(words[3]),
                          to!uint(words[4]));
            meshes[$-1].tris ~= tri;
          }
          else if (words[0] == "numweights")
          {
            meshes[$-1].numWeights = to!size_t(words[1]);
            meshes[$-1].weights.reserve(meshes[$-1].numWeights);
          }
          else if (words[0] == "weight")
          {
            enforce(to!size_t(words[1]) == meshes[$-1].weights.length, "mesh weights out of order");
            enforce(words[4] == "(", "mesh weight syntax error 0");
            enforce(words[8] == ")", "mesh weight syntax error 1");

            Weight weight = Weight(to!size_t(words[2]),
                                   to!float(words[3]),
                                   to!float(words[5]),
                                   to!float(words[6]),
                                   to!float(words[7]));

            meshes[$-1].weights ~= weight;
          }

          break;

        default:
          assert(0, "internal error");
      }
    }
    debug
    {
      //writeln(joints);
      //writeln(meshes);
    }

    auto weightInfo = getWeightingInfo();
    if (weightInfo.length > 4)
      writeln("[warning] some vertices have too many weights: ", filename, ": ", getWeightingInfo());
  }
}

T sq(T)(T v)
{
  return v*v;
}

private struct LoadingBone
{
  int   parentIndex;
  uint  componentBits;
  int   firstComponentIndex;
}

class MD5Animation
{
  MD5Model model;
  size_t numFrames;
  uint frameRate; // frames per second
  size_t frameStride; // number of joints in animation
  Joint[] animation;
  float spin;
  size_t numJoints;

  static bool optRenderFull = true;
  static bool optRenderSoftware;
  static bool optRenderWireframe;
  static bool optRenderJoints;
  static bool optRenderVerts;
  static bool optRenderWeights;

  /* t is provided in hecto-nano seconds */
  void calculateFrame(ulong t, ref size_t frameNumber0, ref size_t frameNumber1, ref float tween)
  {
    frameNumber0 = (t * cast(ulong)frameRate / 10_000_000) % numFrames;
    frameNumber1 = (frameNumber0 + 1) % numFrames;
    tween = t * frameRate % 10_000_000 / 10_000_000f;
  }

  // Bone/joint position+orientation for the "base frame." The "base frame" contains all the default
  // values for each component in the position and orientation of any bone in any frame. Which components
  // are derived from these default values and which are animated, or derived from frame{} block data,
  // is specified in the "flags" field, called LoadingBone.componentBits here.
  Ray[] baseframeBones;

  // These are the position+orientation for each bone in each frame. This information is derived both
  // from frame{} blocks and even sometimes the baseframe{} block. See baseframeBones for more.
  Ray[] frameBones;

  this(MD5Model model, string filename)
  {
    LoadingBone[] loadingBones;
    float[] frameAnimatedComponents;
    size_t numAnimatedComponents;
    size_t loadingFrameNumber;
    this.spin = 0.0f;
    this.model = model;

    int mode = 0;

    //auto animationAppender = appender(animation);

    foreach (lineNo, line; splitLines(to!string(cast(char[])file.read(filename))))
    {
      auto words = split(line);

      if (words.length > 0)
      switch (mode)
      {
        case ParserMode.open:
          if (words[0] == "MD5Version")
          {
            assert(to!int(words[1]) == 10);
          }
          else if (words[0] == "commandline")
          {
            // do nothing
          }
          else if (words[0] == "numFrames")
          {
            numFrames = to!size_t(words[1]);
          }
          else if (words[0] == "numJoints")
          {
            numJoints = to!size_t(words[1]);
            enforce(numJoints == model.joints.length, "animation joint count does not equal model joint count");
            baseframeBones.reserve(numJoints);
          }
          else if (words[0] == "frameRate")
          {
            frameRate = to!uint(words[1]);
          }
          else if (words[0] == "numAnimatedComponents")
          {
            numAnimatedComponents = to!size_t(words[1]);

            // TODO FIXME
            enforce(numAnimatedComponents % 6 == 0, "numAnimatedComponents: only multiples of 6 supported");

            // XXX this seems like a good time to reserve
            //     some memory though it may not be ideal
            //     for all MD5 files

            loadingBones.reserve(numJoints);
            frameAnimatedComponents.reserve(numJoints * numAnimatedComponents);
          }
          else if (words[0] == "hierarchy")
          {
            enforce(words[1] == "{");
            mode = ParserMode.joints;
          }
          else if (words[0] == "bounds")
          {
            enforce(words[1] == "{");
            mode = ParserMode.bounds;
          }
          else if (words[0] == "baseframe")
          {
            enforce(words[1] == "{");
            mode = ParserMode.baseframe;
          }
          else if (words[0] == "frame")
          {
            //writefln("animation.length: %d, frame # %d", animation.length, to!size_t(words[1]));
            //enforce(to!size_t(words[1]) == animation.length, "frames out of order");

            enforce(words[2] == "{");

            loadingFrameNumber = to!int(words[1]);
            frameAnimatedComponents.length = 0;
            mode = ParserMode.frame;
          }
          break;

        case ParserMode.joints:
          if (words[0] == "}")
          {
            enforce(loadingBones.length == numJoints, "numJoints and hierarchy mismatch");
            mode = ParserMode.open;
          }
          else
          {
            loadingBones ~= LoadingBone(
              to!int(words[1]),
              to!uint(words[2]),
              to!int(words[3]));
          }
          break;

        case ParserMode.bounds:
          if (words[0] == "}")
          {
            // TODO sanity check
            mode = ParserMode.open;
          }
          break;

        case ParserMode.baseframe:
          if (words[0] == "}")
          {
            // TODO sanity check
            mode = ParserMode.open;
          }
          else
          {
            enforce(words[0] == "(", "baseframe syntax error 0");
            enforce(words[4] == ")", "baseframe syntax error 1");
            enforce(words[5] == "(", "baseframe syntax error 2");
            enforce(words[9] == ")", "baseframe syntax error 3");

            baseframeBones ~= Ray(
              to!float(words[1]),
              to!float(words[2]),
              to!float(words[3]),
              to!float(words[6]),
              to!float(words[7]),
              to!float(words[8]));
          }
          break;

        case ParserMode.frame:
          if (words[0] == "}")
          {
            enforce(frameAnimatedComponents.length == numAnimatedComponents,
              "frame{} block has wrong number of elements");

            foreach (boneIndex, loadingBone; loadingBones)
            {
              size_t animatedComponentIndex = 0;
              //enforce(animatedComponentIndex == loadingBone.firstComponentIndex,
              //  "got bad animated component ordering data from hierarchy{} block");

              Ray bone = baseframeBones[boneIndex];

              if (loadingBone.componentBits & 1)
                bone.pos.x = frameAnimatedComponents[loadingBone.firstComponentIndex + animatedComponentIndex++];
              if (loadingBone.componentBits & 2)
                bone.pos.y = frameAnimatedComponents[loadingBone.firstComponentIndex + animatedComponentIndex++];
              if (loadingBone.componentBits & 4)
                bone.pos.x = frameAnimatedComponents[loadingBone.firstComponentIndex + animatedComponentIndex++];
              if (loadingBone.componentBits & 8)
                bone.orient.x = frameAnimatedComponents[loadingBone.firstComponentIndex + animatedComponentIndex++];
              if (loadingBone.componentBits & 16)
                bone.orient.y = frameAnimatedComponents[loadingBone.firstComponentIndex + animatedComponentIndex++];
              if (loadingBone.componentBits & 32)
                bone.orient.z = frameAnimatedComponents[loadingBone.firstComponentIndex + animatedComponentIndex++];

              // Normalize orientation quaternion
              computeUnitQuatW(bone.orient);

              // Reposition and reorient bone relative to its parent, unless it is the root bone
              if (loadingBone.parentIndex >= 0)
              {
                Ray parentBone = frameBones[loadingFrameNumber*numJoints + loadingBone.parentIndex];
                bone.pos = parentBone.pos + (parentBone.orient * bone.pos);
                bone.orient = parentBone.orient * bone.orient;
                bone.orient.normalize();
              }

              // Add bone to the animation
              frameBones ~= bone;
            }

            mode = ParserMode.open;
          }
          else
          {
            //writeln("animationAppender.put()");
            //animationAppender.put(map!(to!float)(words));

            // TODO FIXME
            enforce(words.length == 6, "only 6 components per frame{} block lines supported");
            frameAnimatedComponents ~= to!float(words[0]);
            frameAnimatedComponents ~= to!float(words[1]);
            frameAnimatedComponents ~= to!float(words[2]);
            frameAnimatedComponents ~= to!float(words[3]);
            frameAnimatedComponents ~= to!float(words[4]);
            frameAnimatedComponents ~= to!float(words[5]);
          }
          break;

        default:
          writefln("internal error: unknown parse mode: %d", mode);
          assert(0, "internal error");
      }
    }

    debug
    {
      //writeln(animation);
    }
  }

  void renderSkeleton(mat4 mvmat, mat4 pmat, ulong t)
  {
    size_t frameNumber, frameNumber1;
    float tween;
    calculateFrame(t, frameNumber, frameNumber1, tween);

    // bones in current frame
    auto bones = frameBones[frameNumber*numJoints .. (frameNumber+1)*numJoints];

    // Draw joint positions
    foreach (bone; bones)
    {
      vertexer.add(bone.pos, vec2(0,0), vec3(1,0,0), vec3f(1,0,0));
    }
    vertexer.draw(shaderProgram, mvmat, pmat, emptyMaterial, GL_POINTS);

    // Draw bones
    foreach(boneIndex, bone; bones)
    {
      auto parentIndex = model.joints[boneIndex].parentIndex;
      if (parentIndex != -1)
      {
        vertexer.add(bone.pos, vec2(0,0), vec3(1,0,0), vec3f(0,1,0));
        Ray parentBone = bones[parentIndex];
        vertexer.add(parentBone.pos, vec2(0,0), vec3(1,0,0), vec3f(0,1,0));
      }
    }
    vertexer.draw(shaderProgram, mvmat, pmat, emptyMaterial, GL_LINES);
    //writefln("frame # %d/%d", frameNumber, numFrames);
    spin += 0.5;
  }

  // render()
  static vec3[] vertPosBuf;
  static vec3[] vertNorBuf;
  static vec3f[] vertColBuf;
  void render(mat4 mvmat, mat4 pmat, ulong t)
  {
    size_t frameNumber, frameNumber1;
    float tween;
    calculateFrame(t, frameNumber, frameNumber1, tween);

    //vec3[] vertsNormals;

    foreach (mesh; model.meshes)
    {
      if (vertPosBuf.length < mesh.verts.length)
      {
        vertPosBuf.length = mesh.verts.length;
        vertNorBuf.length = mesh.verts.length;
        vertColBuf.length = mesh.verts.length;
      }

      /* Calculate mesh vertex positions from animation weight positions */
      foreach (vi; 0..mesh.verts.length)
      {
        Vert vert = mesh.verts[vi];
        Weight[] weights = mesh.weights[vert.weightIndex .. vert.weightIndex + vert.numWeights];
        vec3 pos = vec3(0,0,0);
        foreach (weight; weights)
        {
          auto joint = frameBones[frameNumber * numJoints + weight.jointIndex];
          pos += (joint.orient * weight.pos + joint.pos) * weight.weightBias;
        }
        vertPosBuf[vi] = pos;
        vertNorBuf[vi] = vec3(0,0,0);
        vertColBuf[vi] = vec3f(
          vert.numWeights == 2 ? 1f : 0f,
          vert.numWeights == 1 && mesh.weights[vert.weightIndex].jointIndex == 0 ? 1f : 0f,
          vert.numWeights == 1 && mesh.weights[vert.weightIndex].jointIndex == 1 ? 1f : 0f);
      }

      /* Calculate and accumulate triangle normals */
      foreach (ti, tri; mesh.tris)
      {
        auto vi0 = tri.vi[0],
             vi1 = tri.vi[1],
             vi2 = tri.vi[2];

        auto v0 = vertPosBuf[vi0],
             v1 = vertPosBuf[vi1],
             v2 = vertPosBuf[vi2];

        /* Calculate triangle's normal */
        auto normal = cross(v2-v0, v1-v0);

        vertNorBuf[vi0] += normal;
        vertNorBuf[vi1] += normal;
        vertNorBuf[vi2] += normal;
      }

      /* Send all vertex data to vertexer */
      /* TODO either integrate with vertexer more intimately, or send the vertex data to the
       *      GL by hand here!
       */
      foreach (tri; mesh.tris)
      {
        foreach (vi; tri.vi)
        {
          vertexer.add(
            vertPosBuf[vi],
            mesh.verts[vi].uv, 
            vertNorBuf[vi].normalized,
            vertColBuf[vi]);
        }
      }

      /* Draw vertexer contents */
      vertexer.draw(shaderProgram1, mvmat, pmat, mesh.material, GL_TRIANGLES);
    }
  }
  void renderWeights(mat4 mvmat, mat4 pmat, ulong t)
  {
    size_t frameNumber, frameNumber1;
    float tween;
    calculateFrame(t, frameNumber, frameNumber1, tween);

    foreach (mesh; model.meshes)
    {
      /* Calculate mesh vertex positions from animation weight positions */
      foreach (vi; 0..mesh.verts.length)
      {
        Vert vert = mesh.verts[vi];
        Weight[] weights = mesh.weights[vert.weightIndex .. vert.weightIndex + vert.numWeights];
        vec3 pos = vec3(0,0,0);
        foreach (weight; weights)
        {
          auto joint = frameBones[frameNumber * numJoints + weight.jointIndex];
          auto weightPos = joint.orient * weight.pos + joint.pos;
          vertexer.add(weightPos, vec2(0,0), vec3(1,0,0), vec3f(1,1,1));
        }
      }

      /* Draw vertexer contents */
      vertexer.draw(varyingColorShaderProgram, mvmat, pmat, null, GL_POINTS);
    }
  }

  // renderGPU()
  mat4f[] boneMatrices;
  bool gpuInitialized;
  GLint mvmatUniloc;
  GLint pmatUniloc;
  GLint boneMatricesUniloc;
  GLint colorMapUniloc;
  GLint colorUniloc;
  GLint uvAttloc;
  GLint boneIndicesAttloc;
  GLint weightBiasesAttloc;
  GLint weightPosAttloc;
  GLint indBuf;
  /* GL Buffer Objects to hold vertex attributes and face indices. One per mesh. */
  GLuint[] vbo;
  GLuint[] ibo;
  void renderGPU(mat4 mvmat, mat4 pmat, vec4f color=vec4f(1,1,1,1))
  {
    initGPU();

    /* Create our array of bone matrices describing the armature/skeleton */
    /* Resize if necessary the array we reuse for storing bone matrices */
    if (boneMatrices.length < numJoints)
      boneMatrices.length = numJoints;
    /* Calculate the value of each bone matrix */
    foreach (iBone, bone; interpolatedSkeleton[0..numJoints])
    {
      vec3f[3] v0 = [
        vec3f(bone.orient * vec3(1,0,0)),
        vec3f(bone.orient * vec3(0,1,0)),
        vec3f(bone.orient * vec3(0,0,1)),
      ];
      /* Create a rotation matrix representing the orientation of this joint/bone */
      mat4f m0 = mat4f( //bone.orient.to_matrix!(4,4);
        v0[0].x, v0[0].y, v0[0].z, bone.pos.x,
        v0[1].x, v0[1].y, v0[1].z, bone.pos.y,
        v0[2].x, v0[2].y, v0[2].z, bone.pos.z,
        0f, 0f, 0f, 1f);

      mat4f m1 = bone.orient.to_matrix!(4,4);
      //writeln("quat.to_matrix: ", m1);
      //writeln("quat.meeeeeeee: ", m0);

      /* Factor in translation of this joint/bone */
      mat4f boneMatrix = m1.translate(bone.pos.x, bone.pos.y, bone.pos.z);
      /* Assign the bone matrix to the array */
      boneMatrices[iBone] = boneMatrix;
      //writefln("bone %d matrix: %s", iBone, boneMatrix.as_pretty_string);
    }
    //writeln("BONE MATRICES ******** ", boneMatrices);
    //writeln("mvmat         ******** ", mvmat);

    /* Select our shader program */
    md5ShaderProgram.use();

    /* Send our uniforms to the GL shader program */
    /* Send our bone matrices  */
    glUniformMatrix4fv(boneMatricesUniloc, cast(GLint)numJoints, GL_TRUE, cast(float*)boneMatrices.ptr);
    glErrorCheck("sent bone matrices");

    /* TODO stop using doubles EVERYWHERE wtf is wrong with you */
    mat4f tempMatrix;

    /* Send model-view matrix TODO merge MVP! */
    tempMatrix = mat4f(mvmat);
    glUniformMatrix4fv(mvmatUniloc, 1, GL_TRUE, tempMatrix.value_ptr);
    glErrorCheck("sent mvmat uniform");

    /* Send projection matrix */
    tempMatrix = mat4f(pmat);
    glUniformMatrix4fv(pmatUniloc, 1, GL_TRUE, tempMatrix.value_ptr);
    glErrorCheck("sent pmat uniform");

    /* Send draw command for each mesh! */
    foreach (iMesh, mesh; model.meshes)
    {
      /* Select our GL buffer object containing our vertex data */
      glBindBuffer(GL_ARRAY_BUFFER, vbo[iMesh]);
      glErrorCheck("md5 1");

      /* Enable our vertex attributes */
      static if (0) writefln(`
        attribute location: boneIndices:  %d
        attribute location: weightBiases: %d
        attribute location: weightPos:    %d
        attribute location: uv:           %d`,
        boneIndicesAttloc,
        weightBiasesAttloc,
        weightPosAttloc,
        uvAttloc);

      glEnableVertexAttribArray(uvAttloc);
      glEnableVertexAttribArray(boneIndicesAttloc+0);
      glEnableVertexAttribArray(weightBiasesAttloc);
      glEnableVertexAttribArray(weightPosAttloc+0);
      glEnableVertexAttribArray(weightPosAttloc+1);
      glEnableVertexAttribArray(weightPosAttloc+2);
      glEnableVertexAttribArray(weightPosAttloc+3);

      /* Specify our vertex attribute layout (actual data in VBO already) */
      foreach (i; 0..4)
        glVertexAttribPointer(weightPosAttloc+i, 4, GL_FLOAT, GL_FALSE, GPUVert.sizeof, cast(void*)(4*4*i));
      glVertexAttribPointer(weightBiasesAttloc, 4, GL_FLOAT, GL_FALSE, GPUVert.sizeof, cast(void*)64);
      glVertexAttribPointer(boneIndicesAttloc, 4, GL_FLOAT, GL_FALSE, GPUVert.sizeof, cast(void*)(80));
      glVertexAttribPointer(uvAttloc, 2, GL_FLOAT, GL_FALSE, GPUVert.sizeof, cast(void*)96);

      /* Set texture sampler for color map TODO use Material better! */
      glActiveTexture(GL_TEXTURE0);
      glBindTexture(GL_TEXTURE_2D, mesh.material.texes[0].texture);
      glUniform1i(colorMapUniloc, 0);
      glErrorCheck("md5 9.1");

      glUniform4fv(colorUniloc, 1, color.value_ptr);
      glErrorCheck("md5 9.1.1");

      /* Draw! */
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo[iMesh]);
      glErrorCheck("md5 9");

      glDrawElements(GL_TRIANGLES, cast(int)(mesh.numTris*3), GL_UNSIGNED_INT, cast(void*)0);
      glErrorCheck("md5 10");
    }

    /* Release XXX */
    /* Release vert attributes */
    glDisableVertexAttribArray(uvAttloc);
    glDisableVertexAttribArray(boneIndicesAttloc);
    glDisableVertexAttribArray(weightBiasesAttloc);
    glDisableVertexAttribArray(weightPosAttloc+0);
    glDisableVertexAttribArray(weightPosAttloc+1);
    glDisableVertexAttribArray(weightPosAttloc+2);
    glDisableVertexAttribArray(weightPosAttloc+3);
    
    /* Disable the buffer objects we've used */
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);

    /* Unset texture samplers TODO use Material better! */
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, 0);

    glErrorCheck("renderGPU finished");
  }
  bool initGPUDone;
  void initGPU()
  {
    if (initGPUDone)
      return;

    /* Generate needed buffers */
    /* Vertex buffer objects for each mesh */
    vbo.length = model.meshes.length;
    /* Index buffer objects for face indices */
    ibo.length = vbo.length;
    /* Create buffer objects for both vertex data and face data */
    glGenBuffers(cast(GLint)vbo.length, vbo.ptr);
    glGenBuffers(cast(GLint)ibo.length, ibo.ptr);
    glErrorCheck("glGenBuffers()");

    GPUVert[] data;
    foreach (iMesh, mesh; model.meshes)
    {
      if (data.length < mesh.verts.length)
        data.length = mesh.verts.length;

      foreach (iVert, vert; mesh.verts)
      {
        GPUVert v;
        v.uv = vec2f(vert.uv.x, vert.uv.y);
        foreach (iWeight; 0..4)
        {
          if (iWeight < vert.numWeights)
          {
            auto weight = mesh.weights[vert.weightIndex + iWeight];
            //writefln("vert %d weight %d joint %d", iVert, iWeight, weight.jointIndex);
            v.weightIndices.vector[iWeight] = cast(uint)weight.jointIndex;
            v.weightBiases [iWeight] = cast(float)weight.weightBias;
            v.weightPos    [iWeight] = vec4f(weight.pos.x, weight.pos.y, weight.pos.z, 1f);
          }
          else
          {
            v.weightIndices.vector[iWeight] = 0f;
            v.weightBiases [iWeight] = 0f;
            v.weightPos    [iWeight] = vec4f(0,0,0,0);
          }
          v.pad = vec2f(666f, 666f);
        }
        if (vert.numWeights == 2 &&
            mesh.weights[vert.weightIndex].jointIndex < mesh.weights[vert.weightIndex+1].jointIndex)
          v.pad.x = 1f;
        data[iVert] = v;
      }

      /* Send vertex attributes to its GL Buffer Object */
      /* Create the buffer object in the GL */
      glBindBuffer(GL_ARRAY_BUFFER, vbo[iMesh]);
      /* Fill the buffer object with our data */
      //writeln("vbo data: ");
      version (debugMD5)
      {
        foreach(v; data) if (v.pad.x == 1f) writefln(`
          weight 0 pos: %s
          weight 1 pos: %s
          weight 2 pos: %s
          weight 3 pos: %s
          weight biases: %s
          weight indices: %s
          uv: %s
          pad: %s`,
          v.weightPos[0],
          v.weightPos[1],
          v.weightPos[2],
          v.weightPos[3],
          v.weightBiases,
          v.weightIndices,
          v.uv, v.pad);

        GLint maxVA;
        glGetIntegerv(GL_MAX_VERTEX_ATTRIBS, &maxVA);
        writefln("%d %d-byte triangles %d bytes tota (%d max!): %s",
          mesh.tris.length, Tri.sizeof, Tri.sizeof * mesh.tris.length, maxVA, mesh.tris);
      }

      glBufferData(GL_ARRAY_BUFFER, GPUVert.sizeof * data.length, data.ptr, GL_STATIC_DRAW);
      /* Finish using this buffer object */
      glBindBuffer(GL_ARRAY_BUFFER, 0);

      /* Send face index data to its GL Buffer Object */
      /* Create the buffer object in the GL */
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo[iMesh]);
      /* Fill the buffer object with our data */
      glBufferData(GL_ELEMENT_ARRAY_BUFFER, Tri.sizeof * mesh.tris.length, mesh.tris.ptr, GL_STATIC_DRAW);
      /* Finish using this buffer object */
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);

      glErrorCheck("md5 end of initGPU()");
    }

    /* Grab shader variable locations */
    mvmatUniloc        = md5ShaderProgram.getUniformLocation("viewMatrix");
    pmatUniloc         = md5ShaderProgram.getUniformLocation("projMatrix");
    boneMatricesUniloc = md5ShaderProgram.getUniformLocation("boneMatrices");
    colorMapUniloc     = md5ShaderProgram.getUniformLocation("colorMap");
    colorUniloc        = md5ShaderProgram.getUniformLocation("colorU");
    uvAttloc           = md5ShaderProgram.getAttribLocation ("uvV");
    boneIndicesAttloc  = md5ShaderProgram.getAttribLocation ("boneIndices");
    weightBiasesAttloc = md5ShaderProgram.getAttribLocation ("weightBiases");
    weightPosAttloc    = md5ShaderProgram.getAttribLocation ("weightPos[0]");

    glErrorCheck("initGPU finished");

    initGPUDone = true;
  }

  void renderVerts(mat4 mvmat, mat4 pmat, ulong t)
  {
    size_t frameNumber, frameNumber1;
    float tween;
    calculateFrame(t, frameNumber, frameNumber1, tween);

    foreach (mesh; model.meshes)
    {
      foreach (tri; mesh.tris)
      {
        vec3[3] outVerts;
        foreach (outVertI, vi; tri.vi)
        {
          outVerts[outVertI] = vec3(0, 0, 0);

          Vert vert = mesh.verts[vi];
          Weight[] weights = mesh.weights[vert.weightIndex .. vert.weightIndex + vert.numWeights];
          foreach (weight; weights)
          {
            auto joint = frameBones[frameNumber * numJoints + weight.jointIndex];
            outVerts[outVertI] += (joint.orient * weight.pos + joint.pos) * weight.weightBias;
          }
        }

        vertexer.add(outVerts[0], vec2(0,0), vec3(0,0,0), vec3f(.2,.2,1));
        vertexer.add(outVerts[1], vec2(1,1), vec3(1,1,1), vec3f(.2,.2,1));
        vertexer.add(outVerts[2], vec2(2,2), vec3(2,2,2), vec3f(.2,.2,1));
        vertexer.add(outVerts[0], vec2(0,0), vec3(0,0,0), vec3f(.2,.2,1));
      }
      vertexer.draw(shaderProgram, mvmat, pmat, mesh.material, GL_LINES);
    }
  }

  void draw(mat4 mvmat, mat4 pmat, ulong t, vec4f color=vec4f(1,1,1,1))
  {
    if (vertexer is null)
    {
      vertexer = new Vertexer();
      emptyMaterial = new Material();
      shaderProgram = new ShaderProgram("simple-red.vs", "simple-red.fs");
      shaderProgram1 = new ShaderProgram("simpler.vs", "simpler.fs");
      //md5ShaderProgram = new ShaderProgram("md5-color--uv--uv-color.vs", "simpler.fs");
      varyingColorShaderProgram = new ShaderProgram("simpler.vs", "simple-color.fs");
    }

    calculateInterpolatedSkeleton(t);

    if (optRenderFull)
    {
      glEnable(GL_CULL_FACE);
      if (optRenderSoftware)
        render(mvmat, pmat, t);
      else
        renderGPU(mvmat, pmat, color);
    }
    if (optRenderWeights)
    {
      glDisable(GL_DEPTH_TEST);
      glPointSize(5f);
      renderWeights(mvmat, pmat, t);
      glPointSize(1f);
      glEnable(GL_DEPTH_TEST);
    }
    if (optRenderWireframe)
      renderSkeleton(mvmat, pmat, t);
    if (optRenderVerts)
      renderVerts(mvmat, pmat, t);
  }

  /* We can store an interpolated skeleton (a slice of frameBones) here, allowing us to
   * avoid recalculating a given skeleton, and also providing a place in memory to store
   * it, sans alloca.
   */
  static Ray[] interpolatedSkeleton;
  void calculateInterpolatedSkeleton(ulong t)
  {
    size_t f0, f1;
    float f01;
    calculateFrame(t, f0, f1, f01);

    if (interpolatedSkeleton.length < numJoints)
      interpolatedSkeleton.length = numJoints;

    foreach (iBone; 0..numJoints)
    {
      auto b0 = frameBones[f0 * numJoints + iBone];
      auto b1 = frameBones[f1 * numJoints + iBone];
      interpolatedSkeleton[iBone].pos = lerp(b0.pos, b1.pos, f01);
      interpolatedSkeleton[iBone].orient = lerp(b0.orient, b1.orient, f01);
    }
  }
}

class MD5Animator
{
  MD5Animation anim;
  ulong start; // hnsecs!

  /* TODO allowing 'now' to have a default value is only useful in the world of everything
   * just being a single stupid looping animation. i should refactor a bit and make this
   * better.
   */
  this(MD5Animation anim)
  {
    this.anim = anim;
    this.start = GameTime.gt;
  }

  /* now = current time
   */
  void draw(mat4 mvmat, mat4 pmat, vec4f color=vec4f(1,1,1,1))
  {
    /* TODO animation sequences instead of just looping the same animation */
    anim.draw(mvmat, pmat, GameTime.gt-start, color);
  }
}

void stop() {
  writeln("STOP");
}

void glErrorCheck(string source)
{
  GLenum err = glGetError();
  if (err)
  {
    writefln("error @ %s: opengl: %s", source, err);
    stop();
  }
}
