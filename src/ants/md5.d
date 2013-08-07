module ants.md5;
import file = std.file;
import std.string;
import std.conv;
import std.algorithm : map, appender;
import std.exception : enforce;
import derelict.opengl3.gl3;
import gl3n.linalg : vec2, vec3, vec4, mat4, quat;
import gl3n.interpolate : lerp;
import std.math : sqrt;

debug
{
  import std.stdio : writeln, writefln;
}

private void glVertex3f(float a, float b, float c)
{
}

private void glColor3f(float a, float b, float c)
{
}

private void glBegin(GLenum a)
{
}

private void glEnd()
{
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
  float u, v;
  uint weightIndex;
  uint numWeights;
}

struct Tri
{
  size_t[3] vi; // verts
  this(size_t a, size_t b, size_t c)
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
  string shader;
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
  void draw()
  {
    glBegin(GL_TRIANGLES);
    glColor3f (1, 0, 0); glVertex3f(-1, -1, -2);
    glColor3f (0, 1, 0); glVertex3f( 1, -1, -2);
    glColor3f (0, 0, 1); glVertex3f( 0,  1, -2);
    glColor3f(1, 1, 1);
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

          glVertex3f(p.x, p.y, p.z);
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
            meshes[$-1].shader = words[1];
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
              to!float(words[3]),
              to!float(words[4]),
              to!uint(words[6]),
              to!uint(words[7]));

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
            Tri tri = Tri(to!size_t(words[2]),
                          to!size_t(words[3]),
                          to!size_t(words[4]));
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
  uint frameRate;
  size_t frameStride; // number of joints in animation
  Joint[] animation;
  float spin;
  int frameDelay;
  size_t frameNumber;
  size_t numJoints;

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

  // TODO WHAT I'M DOING RIGHT NOW IS UPDATING THIS FUNCTION
  void renderSkeleton()
  {
    glPointSize(5);
    glColor3f(1, 0, 0);
    
    // bones in current frame
    auto bones = frameBones[frameNumber*numJoints .. (frameNumber+1)*numJoints];

    // Draw joint positions
    glBegin(GL_POINTS);
    foreach (bone; bones)
    {
      glVertex3f(bone.pos.x, bone.pos.y, bone.pos.z);
    }
    glEnd();

    // Draw bones
    glColor3f(0, 1, 0);
    glBegin(GL_LINES);
    foreach(boneIndex, bone; bones)
    {
      auto parentIndex = model.joints[boneIndex].parentIndex;
      if (parentIndex != -1)
      {
        glVertex3f(bone.pos.x, bone.pos.y, bone.pos.z);
        Ray parentBone = bones[parentIndex];
        glVertex3f(parentBone.pos.x, parentBone.pos.y, parentBone.pos.z);
      }
    }
    glEnd();

    if (++frameDelay >= 1)
    {
      frameDelay = 0;
      if (++frameNumber >= numFrames)
        frameNumber = 0;
    }
    //writefln("frame # %d/%d", frameNumber, numFrames);
    spin += 0.5;
  }

  void renderVerts()
  {
    glBegin(GL_LINES);
    glColor3f(0.2, 0.2, 1);
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

        glVertex3f(outVerts[0].x, outVerts[0].y, outVerts[0].z);
        glVertex3f(outVerts[1].x, outVerts[1].y, outVerts[1].z);
        glVertex3f(outVerts[2].x, outVerts[2].y, outVerts[2].z);
        glVertex3f(outVerts[0].x, outVerts[0].y, outVerts[0].z);
      }
    }
    glEnd();
  }

  void draw()
  {
    // bs
    renderSkeleton();
    renderVerts();
  }

}
