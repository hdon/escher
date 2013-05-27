module ants.md5;
import file = std.file;
import std.string;
import std.conv;
import std.algorithm : map, appender;
import std.exception : enforce;
import derelict.opengl.gl;

debug
{
  import std.stdio : writeln, writefln;
}

struct Joint
{
  int parentIndex;
  float x, y, z;
  float a0, a1, a2;
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
  float x, y, z; // offset from joint
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

class MD5Model
{
  Joint[] joints;
  Joint[string] namedJoints;
  Mesh[] meshes;

  float spin;
  void draw()
  {
    glMatrixMode(GL_MODELVIEW);
    glPushMatrix();
    glLoadIdentity();
    glTranslatef(0, 0, -20);
    glRotatef(spin, 0, 1, 0);
    spin += 0.1;
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

          float x, y, z;
          x = joint.x + weight.x;
          y = joint.y + weight.y;
          z = joint.z + weight.z;

          glVertex3f(x, y, z);
        }
      }
    }
    glEnd();
    glMatrixMode(GL_MODELVIEW);
    glPopMatrix();
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

            Joint joint = Joint(
              to!int(words[1]),
              to!float(words[3]),
              to!float(words[4]),
              to!float(words[5]),
              to!float(words[8]),
              to!float(words[9]),
              to!float(words[10]));

            joints ~= joint;
            namedJoints[words[0]] = joint; // TODO strip quotes
          }
          break;

        case ParserMode.meshes:
          if (words[0] == "}")
          {
            enforce(meshes.length == nMeshes, "wrong number of meshes");
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
      writeln(joints);
      writeln(meshes);
    }
  }
}

class MD5Animation
{
  MD5Model model;
  size_t numAnimatedComponents;
  size_t numFrames;
  uint frameRate;
  float[] animation;
  float spin;
  size_t frameNumber;
  
  void draw()
  {
    glMatrixMode(GL_MODELVIEW);
    glPushMatrix();
    glLoadIdentity();
    glTranslatef(0, 0, -20);
    glRotatef(spin, 0, 1, 0);
    spin += 0.1;
    glBegin(GL_TRIANGLES);
    glColor3f (1, 0, 0); glVertex3f(-1, -1, -2);
    glColor3f (0, 1, 0); glVertex3f( 1, -1, -2);
    glColor3f (0, 0, 1); glVertex3f( 0,  1, -2);
    glColor3f(1, 1, 1);
    foreach (mesh; model.meshes)
    {
      foreach (tri; mesh.tris)
      {
        foreach (vi; tri.vi)
        {
          Vert vert = mesh.verts[vi];
          assert(vert.numWeights == 1, "only one weight per vertex is currently supported");
          Weight weight = mesh.weights[vert.weightIndex];
          assert(weight.weightBias == 1.0, "weight bias is wrong!");

          Joint joint = model.joints[weight.jointIndex];

          size_t base = numAnimatedComponents * frameNumber + weight.jointIndex * 3;
          float x, y, z;

          x = animation[base+0] + weight.x;
          y = animation[base+1] + weight.y;
          z = animation[base+2] + weight.z;

          glVertex3f(x, y, z);
        }
      }
    }
    glEnd();
    glMatrixMode(GL_MODELVIEW);
    glPopMatrix();

    frameNumber = (frameNumber+1) % numFrames;
  }

  this(MD5Model model, string filename)
  {
    this.spin = 0.0f;
    this.model = model;

    int mode = 0;
    size_t numJoints;

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
          }
          else if (words[0] == "frameRate")
          {
            frameRate = to!uint(words[1]);
          }
          else if (words[0] == "numAnimatedComponents")
          {
            numAnimatedComponents = to!size_t(words[1]);
            enforce(numAnimatedComponents == model.joints.length * 6, "unsupported numAnimatedComponents value");
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

            // TODO this is a bullshit place to do this, but using the
            //      export script i'm currently using, it works.
            //animationAppender.reserve(numAnimatedComponents * numFrames);
            animation.reserve(numAnimatedComponents * numFrames);
          }
          else if (words[0] == "frame")
          {
            writefln("animation.length: %d, frame # %d", animation.length, to!size_t(words[1]));
            //enforce(to!size_t(words[1]) == animation.length, "frames out of order");
            enforce(words[2] == "{");
            mode = ParserMode.frame;
          }
          break;

        case ParserMode.joints:
          if (words[0] == "}")
          {
            // TODO sanity check
            mode = ParserMode.open;
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

            // TODO get baseframe?
          }
          break;

        case ParserMode.frame:
          if (words[0] == "}")
          {
            // TODO sanity check
            mode = ParserMode.open;
          }
          else
          {
            //writeln("animationAppender.put()");
            //animationAppender.put(map!(to!float)(words));
            animation ~= to!float(words[0]);
            animation ~= to!float(words[1]);
            animation ~= to!float(words[2]);
            animation ~= to!float(words[3]);
            animation ~= to!float(words[4]);
            animation ~= to!float(words[5]);
          }
          break;

        default:
          writefln("internal error: unknown parse mode: %d", mode);
          assert(0, "internal error");
      }
    }

    debug
    {
      writeln(animation);
    }
  }
}
