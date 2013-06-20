module ants.escher;
import derelict.opengl.gl;
import gl3n.linalg : vec2, vec3, vec4, mat4, quat, dot, cross;
import std.conv;
import gl3n.interpolate : lerp;
import std.math : sqrt, PI, sin, cos;
import std.exception : enforce;
import std.string : splitLines, split;
import file = std.file;
import std.typecons : Tuple;
import std.algorithm : sort;
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

vec3 getTriangleNormal(vec3 a, vec3 b, vec3 c)
{
  // TODO is order correct?
  return cross(b-a, c-a);
}

mat4 getRotationBetweenVecs(vec3 a, vec3 b)
{
  mat4 r = mat4.identity; // TODO necessary?

  return r;
}

/* XXX I am now using code that I don't understand
 *     need to brush up and see exactly how it works.
 */
bool linePlaneIntersect(vec3 lineStart, vec3 lineEnd, vec3 planeOrigin, vec3 axisA, vec3 axisB)
{
  vec3 originToaxisA = axisA - planeOrigin;
  vec3 originToaxisB = axisB - planeOrigin;

  vec3 planeX = axisA;

  vec3 planeNormal = cross(originToaxisA, originToaxisB).normalized;

  vec3 planeY = cross(planeNormal, originToaxisB).normalized;
  planeY = planeY * dot(originToaxisB, planeY);


  // line Info
  vec3 lineOrigin = lineStart;

  vec3 lineSegment = lineEnd - lineStart;
  vec3 lineNormal = (lineEnd - lineStart).normalized;

  // This finds the distance along the orginal line, where line and plane meet, multiply with the lines normal vector to get position 
  float distance = dot(planeOrigin - lineOrigin, planeNormal) / dot(lineNormal, planeNormal);
  vec3 linePlaneIntersection = lineStart + lineNormal * distance;

  // line before lineStart no collision
  if (distance < 0)
    return false;

  // line after lineEnd no collision
  if (distance > lineSegment.magnitude)
    return false;

  // Line segment collides with plane but is it in plane bounds
  float xOnPlane = dot(linePlaneIntersection - planeOrigin, planeX.normalized);
  float yOnPlane = dot(linePlaneIntersection - planeOrigin, planeY.normalized);

  if (xOnPlane < 0)
    return false;

  if (xOnPlane > planeX.magnitude)
    return false;

  if (yOnPlane < 0)
    return false;

  if (yOnPlane > planeY.magnitude)
    return false;

  // linePlaneIntersection lies inside the plane x and plane y
  return true;
}

class Camera
{
  World world;
  int spaceID;

  vec3 pos;
  vec3 orient;
  float angle;

  float vel;
  float turnRate;

  this(World world, int spaceID, vec3 pos)
  {
    this.world = world;
    this.spaceID = spaceID;
    this.pos = pos;
    this.vel = 0f;
    this.angle = 0f;
    this.orient = vec3(0,0,0);
    this.turnRate = 0f;
  }

  void update(ulong delta)
  {
    vec3 oldpos = pos;

    float deltaf = delta/1000f;
    angle += turnRate * deltaf;
    orient = vec3(-sin(angle), 0, cos(angle));
    pos += orient * (vel * deltaf);

    while (angle < 0.0)
      angle += PI*2f;
    while (angle >= PI*2f)
      angle -= PI*2f;

    /* Intersect space faces */
    Space space = world.spaces[spaceID];
    foreach (faceIndex, face; space.faces)
    {
      if (linePlaneIntersect(oldpos, pos, space.verts[face.indices[0]], space.verts[face.indices[1]], space.verts[face.indices[3]]))
      {
        writefln("intersected face %d", faceIndex);
        if (face.data.type == FaceType.Remote && face.data.remote.v.spaceID >= 0)
        {
          spaceID = face.data.remote.v.spaceID;
          this.pos += face.data.remote.v.remoteReferenceRay.pos; // TODO orientation/scaling
          writefln("entered space %d", spaceID);
        }
      }
    }
  }

  void draw()
  {
    glEnable(GL_DEPTH_TEST);
    glEnable(GL_CULL_FACE);

    glMatrixMode(GL_MODELVIEW);
    glPushMatrix();
    glLoadIdentity();
    glRotatef(angle/PI*180f, 0, 1, 0);
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
