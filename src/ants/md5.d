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
import derelict.opengl3.gl3;
import gl3n.linalg;
import gl3n.interpolate : lerp;
import ants.material;
import ants.shader;
import ants.texture;
import ants.gametime;
import ants.glutil;
import std.math : sqrt;
import std.stdio : writeln, writefln;

alias sum = reduce!"a + b";

private
{
  Material emptyMaterial;
  ShaderProgram shaderProgram;
  ShaderProgram shaderProgram1;
  ShaderProgram md5ShaderProgram;

  ShaderProgram shaderProgram2;
  /* Attribute locations */
  GLint sp2_Aposition;
  GLint sp2_Anormal;
  GLint sp2_Auv;
  GLint sp2_UviewMatrix;
  GLint sp2_UprojMatrix;
  GLint sp2_UnormalMatrix;
  GLint sp2_UcolorMap;
}

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
  vec3 normal;
  uint weightIndex;
  uint numWeights;
  this(vec2 uv, uint weightIndex, uint numWeights)
  {
    this.uv = uv;
    this.weightIndex = weightIndex;
    this.numWeights = numWeights;
  }
}

/* This layout should eventually replace Vert I think. Right now I will just copy a mesh's Verts
 * into a GPUVert[] and send the data to a GL Buffer Object.
 */
struct GPUVert
{
  vec4[4]   weightPos;
  float[4]  weightBiases;
  float[4]  boneIndices;
  vec2      uv;
  vec3      normal;
}

struct Tri
{
  uint[3] vi; // verts
  this(uint a, uint b, uint c)
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

class Mesh
{
  size_t numVerts;
  Material material;
  Vert[] verts;
  size_t numTris;
  Tri[] tris;
  size_t numWeights;
  Weight[] weights;

  this() {}
  /* Renderers of mesh may consolidate all mesh data into a single vertex buffer.
   * This may help with that.
   */
  size_t firstVertexIndex;
  size_t firstElementIndex;
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
  string filename;

  /* Generate bone-space weight normals */
  static struct BindPoseVert
  {
    vec3 pos;
    vec3 normal;
    vec2 uv;
  }

  static BindPoseVert[] bindPoseVerts;

  void generateBindPose(size_t iMesh, bool inBoneSpace=false)
  {
    auto mesh = meshes[iMesh];
    if (bindPoseVerts.length < mesh.verts.length)
      bindPoseVerts.length = mesh.verts.length;
    
    foreach (iVert, vert; mesh.verts)
    {
      Weight[] weights = mesh.weights[vert.weightIndex .. vert.weightIndex + vert.numWeights];
      auto pos = vec3(0, 0, 0);
      foreach (weight; weights)
      {
        auto joint = joints[weight.jointIndex].ray;
        pos += weight.weightBias *
      //(joint.orient * weight.pos + joint.pos) * weight.weightBias
      //weight.pos * weight.weightBias
      //(joint.pos + joint.orient * weight.pos)
        (joint.orient * weight.pos + joint.pos)
      //weight.pos
        
        ;
      }
      bindPoseVerts[iVert] = BindPoseVert(pos, vec3(0,0,0), vert.uv);
      //writefln("mesh %d vert %d = %s", iMesh, iVert, pos);
    }

    foreach (iTri, tri; mesh.tris)
    {
      auto a = bindPoseVerts[tri.vi[0]].pos;
      auto b = bindPoseVerts[tri.vi[1]].pos;
      auto c = bindPoseVerts[tri.vi[2]].pos;
      auto normal = cross((b-a).normalized, (b-c).normalized).normalized;
      bindPoseVerts[tri.vi[0]].normal += normal;
      bindPoseVerts[tri.vi[1]].normal += normal;
      bindPoseVerts[tri.vi[2]].normal += normal;
    }

    foreach (iVert; 0..mesh.verts.length)
    {
      auto meshVert = mesh.verts[iVert];
      auto n = bindPoseVerts[iVert].normal.normalized;
      if (inBoneSpace)
      {
        auto n2 = vec3(0,0,0);
        foreach (iWeight, weight; mesh.weights[meshVert.weightIndex .. meshVert.weightIndex + meshVert.numWeights])
          n2 += joints[weight.jointIndex].ray.orient.inverse * n * weight.weightBias;
        bindPoseVerts[iVert].normal = n2;
      }
      else
        bindPoseVerts[iVert].normal = n;
    }
  }

  /* Vertex Array Object, and Buffer Objects */
  GLuint vao, vbo, ibo;
  static Tri[] triBuf;
  void render(mat4 viewMatrix, mat4 projMatrix)
  {
    if (shaderProgram2 is null)
    {
      shaderProgram2 = new ShaderProgram("vert-uv-norm--uv-norm.glsl", "frag-colorMap--uv-normal--uv-normal.glsl");
      glGenBuffers(2, &vbo);
      glGenVertexArrays(1, &vao);

      shaderProgram2.use;
      glBindVertexArray(vao);
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo);
      glBindBuffer(GL_ARRAY_BUFFER, vbo);

      auto numTris = sum(map!"a.tris.length"(meshes));
      writeln("numTris=", numTris);
      glBufferData(GL_ELEMENT_ARRAY_BUFFER, numTris * Tri.sizeof, null, GL_STREAM_DRAW);

      auto numVerts = sum(map!"a.verts.length"(meshes));
      glBufferData(GL_ARRAY_BUFFER, numVerts * BindPoseVert.sizeof, null, GL_STREAM_DRAW);

      size_t vboWriteCursor, iboWriteCursor;
      int vertexCounter, triCounter;
      auto maxTris = reduce!"a>b?a:b"(map!"a.tris.length"(meshes));
      if (triBuf.length < maxTris)
        triBuf.length = maxTris;

      foreach (iMesh, mesh; meshes)
      {
        mesh.firstVertexIndex = vertexCounter;
        mesh.firstElementIndex = triCounter * 3;
        writefln("mesh[%d].firstElementIndex = %d", iMesh, mesh.firstElementIndex);

        generateBindPose(iMesh);
        auto vboWriteLen = mesh.verts.length * BindPoseVert.sizeof;
        glBufferSubData(GL_ARRAY_BUFFER, vboWriteCursor, vboWriteLen, bindPoseVerts.ptr);
        writefln("mesh %d writing %d vertices starting at index %d (%d bytes): %s",
          iMesh, mesh.verts.length, vertexCounter, vboWriteCursor, bindPoseVerts[0..mesh.verts.length]);

        foreach (iTri, tri; mesh.tris)
        {
          triBuf[iTri] = Tri(
            vertexCounter + tri.vi[0]
          , vertexCounter + tri.vi[1]
          , vertexCounter + tri.vi[2]
          );
        }

        auto iboWriteLen = mesh.tris.length * triBuf[0].sizeof;
        glBufferSubData(GL_ELEMENT_ARRAY_BUFFER, iboWriteCursor, iboWriteLen, triBuf.ptr);
        writefln("mesh %d writing %d triangles / %d elements / %d bytes starting at tri index %d / element index %d (%d bytes): %s",
          iMesh, mesh.tris.length, mesh.tris.length * 3, iboWriteLen, triCounter, triCounter * 3, iboWriteCursor,
          triBuf[0..mesh.tris.length]);

        vboWriteCursor += vboWriteLen;
        iboWriteCursor += iboWriteLen;
        vertexCounter += mesh.verts.length;
        triCounter += mesh.tris.length;

        glFinish();
      }

      assert(triCounter == numTris);
      assert(vertexCounter == numVerts);

      sp2_UviewMatrix    = shaderProgram2.getUniformLocation("viewMatrix");
      sp2_UprojMatrix    = shaderProgram2.getUniformLocation("projMatrix");
      sp2_UnormalMatrix  = shaderProgram2.getUniformLocation("normalMatrix");
      sp2_UcolorMap      = shaderProgram2.getUniformLocation("colorMap");
      sp2_Aposition      = shaderProgram2.getAttribLocation ("positionV");
      sp2_Anormal        = shaderProgram2.getAttribLocation ("normalV");
      sp2_Auv            = shaderProgram2.getAttribLocation ("uvV");
      assert(sp2_UviewMatrix >= 0);
      assert(sp2_UprojMatrix >= 0);
      assert(sp2_Aposition   >= 0);

      BindPoseVert VT;
      glEnableVertexAttribArray(sp2_Aposition);
      glVertexAttribPointer(sp2_Aposition, 3, GL_FLOAT, GL_FALSE,
        VT.sizeof, cast(void*) VT.pos.offsetof);
      if (sp2_Anormal >= 0)
      {
        glEnableVertexAttribArray(sp2_Anormal);
        glVertexAttribPointer(sp2_Anormal, 3, GL_FLOAT, GL_FALSE,
          VT.sizeof, cast(void*) VT.normal.offsetof);
      }
      if (sp2_Auv >= 0)
      {
        glEnableVertexAttribArray(sp2_Auv);
        glVertexAttribPointer(sp2_Auv, 3, GL_FLOAT, GL_FALSE,
          VT.sizeof, cast(void*) VT.uv.offsetof);
      }
    }
    else
    {
      shaderProgram2.use;
      glBindVertexArray(vao);
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo);
      glBindBuffer(GL_ARRAY_BUFFER, vbo);
    }

    glUniformMatrix4fv(sp2_UviewMatrix, 1, GL_TRUE, viewMatrix.value_ptr);
    glUniformMatrix4fv(sp2_UprojMatrix, 1, GL_TRUE, projMatrix.value_ptr);
    static if (0)
    if (sp2_UnormalMatrix >= 0)
    {
      mat3 normalMatrix = viewMatrix.get_rotation;
      glUniformMatrix3fv(sp2_UnormalMatrix, 1, GL_TRUE, normalMatrix.value_ptr);
    }

  //auto buf = new float[1536/float.sizeof];
  //glGetBufferSubData(GL_ARRAY_BUFFER, 0, buf.length * buf[0].sizeof, buf.ptr);
  //writeln("got: ", buf);

    foreach (iMesh, mesh; meshes)
    {
      if (sp2_UcolorMap >= 0)
      {
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, mesh.material.texes[0].texture);
        glUniform1i(sp2_UcolorMap, 0);
      }

      GLint start = cast(GLint) mesh.firstElementIndex;
      GLint count = cast(GLint) mesh.tris.length * 3;
      GLint end = start + count;
    //writefln("mesh[%d].firstElementIndex == %d", iMesh, mesh.firstElementIndex);
    //writefln("meshes[%d] glDrawRangeElements(GL_TRIANGLES, %s, %s, %s, GL_UNSIGNED_INT, null)", iMesh, start, end, count);
      glDrawRangeElements(GL_TRIANGLES, start, end, count, GL_UNSIGNED_INT, cast(void*) (start * uint.sizeof));
    }

    if (sp2_UcolorMap >= 0)
      glBindTexture(GL_TEXTURE_2D, 0);

    glBindVertexArray(0);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
  }

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

  this(string filename)
  {
    this.filename = filename;
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
            meshes ~= new Mesh();
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

            if (joint.parentIndex >= 0)
            {
              Ray parentBone = joints[joint.parentIndex].ray;
              // I used to do this, because you do it for md5anim, but looking at io_scene_md5.py
              // MD5 exporter for blender, it looks like the joints{} block in the .md5mesh, providing
              // the "bind pose," each bone is already expressed in object space, so there is no reason
              // to compose it with the transform of its parent, down to the root bone.
              // joint.ray.pos = parentBone.pos + (parentBone.orient * joint.ray.pos);
              // joint.ray.orient = parentBone.orient * joint.ray.orient;
              // joint.ray.orient.normalize();
            }

            namedJoints[words[0][1..$-1]] = joints.length;
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
            auto materialTexture = new MaterialTexture();
            materialTexture.application = TextureApplication.Color;
            auto material = new Material();
            materialTexture.texture = getTexture(textureFilename);
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
              vec2(to!float(words[3]),
                   to!float(words[4])),  // uv
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

  static vec3[] vertPosBuf;
  static const(const(vec4)[]) someColors = [
    vec4(1,0,0,1)
  , vec4(0,1,0,1)
  , vec4(0,0,1,1)
  , vec4(1,1,0,1)
  , vec4(1,0,1,1)
  , vec4(0,1,1,1)
  ];
  void render(mat4 mvmat, mat4 pmat, Ray[] skeleton, vec4 color=vec4(1,1,1,1))
  {
    throw new Error("unimplemented");
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
  size_t numJoints;
  static ulong interpolatedSkeletonTime;
  static MD5Model interpolatedSkeletonModel;
  static Ray[] interpolatedSkeleton;

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

  string filename;
  this(MD5Model model, string filename)
  {
    this.filename = filename;
    LoadingBone[] loadingBones;
    float[] frameAnimatedComponents;
    size_t numAnimatedComponents;
    size_t loadingFrameNumber;
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

  void renderSkeleton(mat4 mvmat, mat4 pmat)
  {
    //throw new Error("Unimplemented");
  }

  /* Right now, render() just renders the outline of each triangle, and will draw
   * them in up to six different colors, one for each mesh.
   */
  static vec3[] vertPosBuf;
  static const(const(vec4)[]) someColors = [
    vec4(1,0,0,1)
  , vec4(0,1,0,1)
  , vec4(0,0,1,1)
  , vec4(1,1,0,1)
  , vec4(1,0,1,1)
  , vec4(0,1,1,1)
  ];
  void render(mat4 mvmat, mat4 pmat, Ray[] skeleton, vec4 color=vec4(1,1,1,1))
  {
    //throw new Error("Unimplemented");
  }

  mat4[] boneMatrices;
  bool gpuInitialized;
  GLint mvmatUniloc;
  GLint pmatUniloc;
  GLint boneMatricesUniloc;
  GLint colorMapUniloc;
  GLint uvAttloc;
  GLint normalAttloc;
  GLint boneIndicesAttloc;
  GLint weightBiasesAttloc;
  GLint weightPosAttloc;
  GLint indBuf;
  /* GL Buffer Objects to hold vertex attributes and face indices. One per mesh. */
  GLuint[] vbo;
  GLuint[] ibo;
  void renderGPU(mat4 mvmat, mat4 pmat, vec4 color=vec4(1,1,1,1))
  {
    initGPU();

    /* Create our array of bone matrices describing the armature/skeleton */
    /* Resize if necessary the array we reuse for storing bone matrices */
    if (boneMatrices.length < numJoints)
      boneMatrices.length = numJoints;
    /* Calculate the value of each bone matrix */
    //writefln("renderGPU() looking for MD5Animation(\"%s\") == %d joints in interpolatedSkeleton.length = %d", filename, numJoints, interpolatedSkeleton.length);
    foreach (iBone, bone; interpolatedSkeleton[0..numJoints])
      boneMatrices[iBone] = bone.orient.to_matrix!(4,4).translate(bone.pos.x, bone.pos.y, bone.pos.z);

    /* Select our shader program */
    if (md5ShaderProgram is null)
    {
      md5ShaderProgram = new ShaderProgram("vert-md5.glsl", "frag-md5.glsl");
    }
    md5ShaderProgram.use();

    /* Send our uniforms to the GL shader program */
    /* Send our bone matrices  */
    glUniformMatrix4fv(boneMatricesUniloc, cast(GLint)numJoints, GL_TRUE, cast(float*)boneMatrices.ptr);
    glErrorCheck("sent bone matrices");

    /* Send model-view matrix */
    glUniformMatrix4fv(mvmatUniloc, 1, GL_TRUE, mvmat.value_ptr);
    glErrorCheck("sent mvmat uniform");
    /* Send projection matrix */
    glUniformMatrix4fv(pmatUniloc, 1, GL_TRUE, pmat.value_ptr);
    glErrorCheck("sent pmat uniform");

    /* Send draw command for each mesh! */
    foreach (iMesh, mesh; model.meshes)
    {
      /* Select our GL buffer object containing our vertex data */
      glBindBuffer(GL_ARRAY_BUFFER, vbo[iMesh]);
      glErrorCheck("md5 1");

      /* Enable our vertex attributes */
      // TODO Use VAO
      if (uvAttloc >= 0)
      glEnableVertexAttribArray(uvAttloc);
      if (normalAttloc >= 0)
      glEnableVertexAttribArray(normalAttloc);
      glEnableVertexAttribArray(boneIndicesAttloc+0);
      glEnableVertexAttribArray(weightBiasesAttloc);
      glEnableVertexAttribArray(weightPosAttloc+0);
      glEnableVertexAttribArray(weightPosAttloc+1);
      glEnableVertexAttribArray(weightPosAttloc+2);
      glEnableVertexAttribArray(weightPosAttloc+3);

      GPUVert VT;
      /* Specify our vertex attribute layout (actual data in VBO already) */
      foreach (i; 0..4)
        glVertexAttribPointer(weightPosAttloc+i, 4, GL_FLOAT, GL_FALSE, VT.sizeof,
          cast(void*) (VT.weightPos.offsetof + (i * VT.weightPos[0].sizeof)));

      glVertexAttribPointer(weightBiasesAttloc, 4, GL_FLOAT, GL_FALSE, VT.sizeof,
        cast(void*) VT.weightBiases.offsetof);

      glVertexAttribPointer(boneIndicesAttloc, 4, GL_FLOAT, GL_FALSE, VT.sizeof,
        cast(void*) VT.boneIndices.offsetof);

      if (uvAttloc >= 0)
      glVertexAttribPointer(uvAttloc, 2, GL_FLOAT, GL_FALSE, VT.sizeof,
        cast(void*) VT.uv.offsetof);

      if (normalAttloc >= 0)
      glVertexAttribPointer(normalAttloc, 3, GL_FLOAT, GL_FALSE, VT.sizeof,
        cast(void*) VT.normal.offsetof);

      /* Set texture sampler for color map TODO use Material better! */
      if (colorMapUniloc >= 0)
      {
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, mesh.material.texes[0].texture);
        glUniform1i(colorMapUniloc, 0);
      }
      glErrorCheck("md5 9.1");

      /* Draw! */
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo[iMesh]);
      glErrorCheck("md5 9");

      glDrawElements(GL_TRIANGLES, cast(int)(mesh.numTris*3), GL_UNSIGNED_INT, cast(void*)0);
      glErrorCheck("md5 10");
    }

    /* Release XXX */
    /* Release vert attributes */
    if (uvAttloc >= 0)
    glDisableVertexAttribArray(uvAttloc);
    if (normalAttloc >= 0)
    glDisableVertexAttribArray(normalAttloc);
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

    /* Calculate normals for each weight. A "weight" in MD5 parlance is a bone-space
     * vertex. To calculate the position of a vertex in the mesh, we must calculate
     * a bone space for each bone, transform each weight into this space, and then
     * calculated a weighted average of each weight corresponding to a given vertex.
     * I'm going to try to do the same now with vertex normals.
     */
    
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

      /* TODO Calculate weight normals */

      model.generateBindPose(iMesh, true);
      foreach (iVert, vert; mesh.verts)
      {
        GPUVert v;
        v.uv = vec2(vert.uv.x, vert.uv.y);
        v.normal = MD5Model.bindPoseVerts[iVert].normal;
        foreach (iWeight; 0..4)
        {
          if (iWeight < vert.numWeights)
          {
            auto weight = mesh.weights[vert.weightIndex + iWeight];
            //writefln("vert %d weight %d joint %d", iVert, iWeight, weight.jointIndex);
            v.boneIndices [iWeight] = cast(uint)weight.jointIndex;
            v.weightBiases[iWeight] = cast(float)weight.weightBias;
            v.weightPos   [iWeight] = vec4(weight.pos.x, weight.pos.y, weight.pos.z, 1f);
          }
          else
          {
            v.boneIndices [iWeight] = 0f;
            v.weightBiases[iWeight] = 0f;
            v.weightPos   [iWeight] = vec4(0,0,0,0);
          }
        }
        data[iVert] = v;
      }

      /* Send vertex attributes to its GL Buffer Object */
      /* Create the buffer object in the GL */
      glBindBuffer(GL_ARRAY_BUFFER, vbo[iMesh]);
      /* Fill the buffer object with our data */
      //writeln("vbo data: ");
      version (debugMD5)
      {
        static if (0)
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
          v.boneIndices,
          v.uv, v.pad);

        GLint maxVA;
        glGetIntegerv(GL_MAX_VERTEX_ATTRIBS, &maxVA);
        writefln("%d %d-byte triangles %d bytes tota (%d max!): %s",
          mesh.tris.length, Tri.sizeof, Tri.sizeof * mesh.tris.length, maxVA, mesh.tris);
      }

      glBufferData(GL_ARRAY_BUFFER, mesh.verts.length * data[0].sizeof, data.ptr, GL_STATIC_DRAW);

      /* Send face index data to its GL Buffer Object */
      /* Create the buffer object in the GL */
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo[iMesh]);
      /* Fill the buffer object with our data */
      glBufferData(GL_ELEMENT_ARRAY_BUFFER, Tri.sizeof * mesh.tris.length, mesh.tris.ptr, GL_STATIC_DRAW);

      glErrorCheck("md5 end of initGPU()");
    }

    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);

    /* Grab shader variable locations */
    mvmatUniloc        = md5ShaderProgram.getUniformLocation("viewMatrix");
    pmatUniloc         = md5ShaderProgram.getUniformLocation("projMatrix");
    boneMatricesUniloc = md5ShaderProgram.getUniformLocation("boneMatrices");
    colorMapUniloc     = md5ShaderProgram.getUniformLocation("colorMap");
    uvAttloc           = md5ShaderProgram.getAttribLocation ("uvV");
    normalAttloc       = md5ShaderProgram.getAttribLocation ("normalV");
    boneIndicesAttloc  = md5ShaderProgram.getAttribLocation ("boneIndices");
    weightBiasesAttloc = md5ShaderProgram.getAttribLocation ("weightBiases");
    weightPosAttloc    = md5ShaderProgram.getAttribLocation ("weightPos[0]");
    assert(mvmatUniloc        >= 0);
    assert(pmatUniloc         >= 0);
    assert(boneMatricesUniloc >= 0);
  //assert(colorMapUniloc     >= 0);
  //assert(uvAttloc           >= 0);
    assert(boneIndicesAttloc  >= 0);
    assert(weightBiasesAttloc >= 0);
    assert(weightPosAttloc    >= 0);

    glErrorCheck("initGPU finished");

    initGPUDone = true;
  }

  void renderVerts(mat4 mvmat, mat4 pmat)
  {
    //throw new Error("Unimplemented");
  }

  void draw(mat4 mvmat, mat4 pmat, ulong t, vec4 color=vec4(1,1,1,1))
  {
    if (shaderProgram is null)
    {
      emptyMaterial = new Material();
      shaderProgram = new ShaderProgram("vert-simple.glsl", "frag-simple-red.glsl");
      shaderProgram1 = new ShaderProgram("vert-color3-uv2--color3-uv2.glsl", "frag-color3-uv2.glsl");
    }

    calculateInterpolatedSkeleton(t);

    if (optRenderFull)
    {
      if (optRenderSoftware)
        render(mvmat, pmat, interpolatedSkeleton, color);
      else
        renderGPU(mvmat, pmat, color);
    }
    static if (0)
    if (optRenderWeights)
    {
      glDisable(GL_DEPTH_TEST);
      glPointSize(5f);
      renderWeights(mvmat, pmat);
      glPointSize(1f);
      glEnable(GL_DEPTH_TEST);
    }
    if (optRenderWireframe)
      renderSkeleton(mvmat, pmat);
    if (optRenderVerts)
      renderVerts(mvmat, pmat);
  }

  /* We can store an interpolated skeleton (a slice of frameBones) here, allowing us to
   * avoid recalculating a given skeleton, and also providing a place in memory to store
   * it, sans alloca.
   */
  void calculateInterpolatedSkeleton(ulong t)
  {
    if (interpolatedSkeletonTime == t && interpolatedSkeletonModel is model)
      return;

    size_t f0, f1;
    float f01;
    calculateFrame(t, f0, f1, f01);

    if (interpolatedSkeleton.length < numJoints)
      interpolatedSkeleton.length = numJoints;
    //writefln("calculateInterpolatedSkeleton() sets interpolatedSkeleton.length = MD5Animation(\"%s\").numJoints == %d", filename, numJoints);

    foreach (iBone; 0..numJoints)
    {
      auto b0 = frameBones[f0 * numJoints + iBone];
      auto b1 = frameBones[f1 * numJoints + iBone];
      interpolatedSkeleton[iBone].pos = lerp(b0.pos, b1.pos, f01);
      interpolatedSkeleton[iBone].orient = lerp(b0.orient, b1.orient, f01); // TODO use slerp!
    }
    
    interpolatedSkeletonTime = t;
    interpolatedSkeletonModel = model;
  }
}

/* TODO animation sequences instead of just looping the same animation */
class MD5Animator
{
  MD5Animation anim;
  ulong start; // hnsecs!

  this(MD5Animation anim)
  {
    this.anim = anim;
    this.start = GameTime.gt;
  }

  void draw(mat4 mvmat, mat4 pmat, vec4 color=vec4(1,1,1,1))
  {
    anim.draw(mvmat, pmat, GameTime.gt-start, color);
  }

  /* This is a little bypass that allows us to calculate an interpolated skeleton
   * without skinning or rendering the model. This is convenient if we need to
   * get something from the skeleton before rendering, for instance a camera bone
   * position.
   */
  void calculateInterpolatedSkeleton()
  {
    anim.calculateInterpolatedSkeleton(GameTime.gt-start);
  }
}

void stop() {
  writeln("STOP");
}
