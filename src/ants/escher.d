module ants.escher;
import derelict.opengl.gl;
import gl3n.linalg : vec2, vec3, vec4, mat4, quat;
import std.conv;
import gl3n.interpolate : lerp;
import std.math : sqrt, PI;
import std.exception : enforce;
import std.string : splitLines, split;
import file = std.file;
debug import std.stdio : writeln, writefln;

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

struct Remote
{
  int       spaceID;
  Ray       remoteReferenceRay;
}

enum FaceType
{
  SolidColor,
  Remote
}

struct FaceDataSolidColor
{
  FaceType  type;
  ubyte[3]  v;
}
struct FaceDataRemote
{
  FaceType  type;
  Remote    v;
}

union FaceData
{
  FaceType  type;
  FaceDataSolidColor solidColor;
  FaceDataRemote remote;
}

class Face
{
  size_t[4] indices;
  FaceData  data;
}

class Space
{
  int       id;
  vec3[]    verts;
  Face[]    faces;
}

private enum ParserMode
{
  expectNumSpaces,
  expectSpace,
  expectVert,
  expectFace
}

class World
{
  Space[] spaces;

  this(string filename)
  {
    ParserMode mode = ParserMode.expectNumSpaces;

    // Convenient reference to the Space we're currently loading
    Space space;

    // Used to check for file sanity
    int spaceID;
    size_t numSpaces, numVerts, numFaces;

    foreach (lineNo, line; splitLines(to!string(cast(char[])file.read(filename))))
    {
      auto words = split(line);

      writeln("processing: ", line);
      if (words.length)
      switch (mode)
      {
        case ParserMode.expectNumSpaces:
          enforce(words[0] == "numspaces", "expected numspaces");
          numSpaces = to!size_t(words[1]);
          spaces.reserve(numSpaces);
          mode = ParserMode.expectSpace;
          break;

        case ParserMode.expectSpace:
          enforce(words[0] == "space", "expected space");
          enforce(words[2] == "numverts", "expected numverts");
          enforce(words[4] == "numfaces", "expected numfaces");
          spaceID = to!int(words[1]);
          enforce(spaceID == spaces.length, "spaces disorganized");

          numVerts = to!size_t(words[3]);
          numFaces = to!size_t(words[5]);

          space = new Space();
          space.id = spaceID;
          space.verts.reserve(numVerts);
          space.faces.reserve(numFaces);
          spaces ~= space;

          mode = ParserMode.expectVert;
          break;

        case ParserMode.expectVert:
          enforce(words[0] == "vert", "expected vert");
          enforce(to!size_t(words[1]) == space.verts.length, "verts disorganized");

          space.verts ~= vec3(
            to!float(words[2]),
            to!float(words[3]),
            to!float(words[4]));

          if (space.verts.length == numVerts)
            mode = ParserMode.expectFace;
          break;

        case ParserMode.expectFace:
          enforce(words[0] == "face", "expected face");
          enforce(to!size_t(words[1]) == space.faces.length, "faces disorganized");

          Face face = new Face();
          face.indices[0] = to!size_t(words[2]);
          face.indices[1] = to!size_t(words[3]);
          face.indices[2] = to!size_t(words[4]);
          face.indices[3] = to!size_t(words[5]);

          if (words[6] == "rgb")
          {
            face.data.type = FaceType.SolidColor;
            face.data.solidColor.v[0] = to!ubyte(words[7]);
            face.data.solidColor.v[1] = to!ubyte(words[8]);
            face.data.solidColor.v[2] = to!ubyte(words[9]);
          }
          else if (words[6] == "remote")
          {
            face.data.type = FaceType.Remote;
            int remoteSpaceID = to!int(words[7]); // not size_t because -1 special value
            face.data.remote.v.spaceID = remoteSpaceID;
            if (remoteSpaceID >= 0)
            {
              face.data.remote.v.remoteReferenceRay.pos = vec3(
                to!float(words[8]),
                to!float(words[9]),
                to!float(words[10]));
              // TODO orientation
            }
          }
          else
          {
            assert(0, "unknown face type");
          }

          space.faces ~= face;

          if (space.faces.length == numFaces)
            mode = ParserMode.expectSpace;
          break;

        default:
          assert(0, "internal error 0");
      }
    }

    debug
    {
      writeln("ESCHER WORLD LOADED");
      writeln(spaces);
    }

    // XXX
    spin = 0f;
  }

  // bs drawing method
  float spin;
  void draw()
  {
    //writeln("World.draw()");
    glEnable(GL_DEPTH_TEST);

    glMatrixMode(GL_MODELVIEW);
    glPushMatrix();
    glLoadIdentity();
    glTranslatef(0, 0, -7);
    glRotatef(spin, 0, 1, 0);
    glRotatef(spin, 0.9701425001453318, 0.24253562503633294, 0);
    spin += 0.5;

    glBegin(GL_TRIANGLES);
    glColor3f (1, 0, 0); glVertex3f(-1, -1, -2);
    glColor3f (0, 1, 0); glVertex3f( 1, -1, -2);
    glColor3f (0, 0, 1); glVertex3f( 0,  1, -2);
    glEnd();

    Space space = spaces[0];

    glBegin(GL_QUADS);
    drawSpace(space, vec3(0,0,0), 3);
    glEnd();

    glMatrixMode(GL_MODELVIEW);
    glPopMatrix();
  }

  void drawSpace(Space space, vec3 transform, size_t maxDepth)
  {
    maxDepth--;
    bool descend = maxDepth > 0;

    foreach (face; space.faces)
    {
      if (face.data.type == FaceType.SolidColor)
      {
        glColor3ub(
          face.data.solidColor.v[0],
          face.data.solidColor.v[1],
          face.data.solidColor.v[2]);

        foreach (vi; face.indices)
        {
          vec3 v = space.verts[vi] + transform;
          glVertex3f(v.x, v.y, v.z);
        }
      }
      else if (face.data.type == FaceType.Remote)
      {
        if (descend && face.data.remote.v.spaceID != size_t.max)
        {
          drawSpace(
            spaces[face.data.remote.v.spaceID],
            face.data.remote.v.remoteReferenceRay.pos + transform,
            maxDepth);
        }
      }
    }
  }
}

class Camera
{
  World world;
  int spaceID;

  vec3 pos;
  float angle;

  vec3 vel;
  float turnRate;

  this(World world, int spaceID, vec3 pos)
  {
    this.world = world;
    this.spaceID = spaceID;
    this.pos = pos;
    this.vel = vec3(0,0,0);
    this.angle = 0f;
    this.turnRate = 0f;
  }

  void update(ulong delta)
  {
    float deltaf = delta/1000f;
    pos += vel * deltaf;
    angle += turnRate * deltaf;
    /*
    while (angle < 0.0)
      angle += PI*2f;
    while (angle >= PI*2f)
      angle -= PI*2f;
    */
    while (angle < 0.0)
      angle += 360f;
    while (angle >= 360f)
      angle -= 360f;
  }

  void draw()
  {
    glEnable(GL_DEPTH_TEST);

    glMatrixMode(GL_MODELVIEW);
    glPushMatrix();
    glLoadIdentity();
    glRotatef(angle, 0, 1, 0);
    glTranslatef(pos.x, pos.y, pos.z);
    //glRotatef(spin, 0, 1, 0);
    //glRotatef(spin, 0.9701425001453318, 0.24253562503633294, 0);

    glBegin(GL_TRIANGLES);
    glColor3f (1, 0, 0); glVertex3f(-1, -1, -2);
    glColor3f (0, 1, 0); glVertex3f( 1, -1, -2);
    glColor3f (0, 0, 1); glVertex3f( 0,  1, -2);
    glEnd();

    glBegin(GL_QUADS);
    world.drawSpace(world.spaces[spaceID], vec3(0,0,0), 3);
    glEnd();

    glMatrixMode(GL_MODELVIEW);
    glPopMatrix();
  }
}
