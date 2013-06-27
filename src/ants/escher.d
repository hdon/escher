module ants.escher;
import derelict.opengl.gl;
import gl3n.linalg : vec2d, vec3d, vec4d, Matrix, quat, dot, cross;
import std.conv;
import gl3n.interpolate : lerp;
import std.math : sqrt, PI, sin, cos, atan2, isNaN, abs;
import std.exception : enforce;
import std.string : splitLines, split;
import file = std.file;
import std.typecons : Tuple;
import std.algorithm : sort;
debug import std.stdio : writeln, writefln;
alias Matrix!(double, 4, 4) mat4;

private struct Ray
{
  vec3d pos;
  vec4d orient;

  /*this(vec3d pos, quat orient)
  {
    this.pos = pos;
    this.orient = orient;
  }

  this(float px, float py, float pz, float ow, float ox, float oy, float oz)
  {
    this.pos = vec3d(px, py, pz);
    this.orient = quat(ow, ox, oy, oz);
  }

  this(float px, float py, float pz, float ox, float oy, float oz)
  {
    this.pos = vec3d(px, py, pz);
    this.orient = quat(0, ox, oy, oz);
  }*/
}

struct Remote
{
  int       spaceID;
  mat4      transform;
  mat4      untransform;
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
  vec3d[]    verts;
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

          space.verts ~= vec3d(
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
              vec3d translation;

              bool hasRotation = false;
              vec3d rotationAxis;
              float rotationAngle;

              // TODO scaling

              translation = vec3d(
                to!float(words[8]),
                to!float(words[9]),
                to!float(words[10]));

              if (words.length >= 16)
              {
                enforce(words[11] == "orientation", "expected orientation");

                hasRotation = true;

                rotationAngle = to!float(words[12]) / 180f * PI;
                rotationAxis = vec3d(to!float(words[13]),
                                    to!float(words[14]),
                                    to!float(words[15]));
              }

              mat4 transform = mat4.identity;
              mat4 untransform = mat4.identity;

              if (hasRotation)
              {
                transform.rotate(rotationAngle, rotationAxis);
                untransform.rotate(-rotationAngle, rotationAxis);
              }

              transform.translate(translation.x, translation.y, translation.z);
              untransform.translate(-translation.x, -translation.y, -translation.z);

              writeln("space transform\n", transform);

              face.data.remote.v.transform = transform;
              face.data.remote.v.untransform = untransform;
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

  bool showRemoteFaces = false;

  // TODO TODO TODO TODO TODO TODO 
  // What I am working on right now:
  // I am about to turn the transform argument of drawSpace() into a mat4.
  // I will need to use the orient field of the face.data.remote.v.remoteReferenceRay.
  // The orient field has been changed to a vec4d. It is actually an xyz vector and
  // an angle (radians?) In the file format, I want to load degrees, so I should translate
  // them to radians at load time.
  // I am exploring how to create the matrix properly using the gl3n source code.
  // There is also an example on line 681 of how to load a matrix from gl3n into opengl.
  // I'm not sure I need to do that yet, but it might be nice for when I have models
  // and shit to draw, and not just a handful of polygons per space.
  void drawSpace(int spaceID, mat4 transform, size_t maxDepth, int prevSpaceID)
  {
    Space space = spaces[spaceID];
    //writefln("[draw space]\t#%d d:%d", spaceID, maxDepth);
    maxDepth--;
    bool descend = maxDepth > 0;

    foreach (faceID, face; space.faces)
    {
      if (face.data.type == FaceType.SolidColor)
      {
        glColor3ub(
          face.data.solidColor.v[0],
          face.data.solidColor.v[1],
          face.data.solidColor.v[2]);

        foreach (vi; face.indices)
        {
          vec3d v = space.verts[vi];
          vec4d V = vec4d(v.x, v.y, v.z, 1f);
          V = V * transform;
          //V = V.normalized;
          glVertex3f(V.x/V.w, V.y/V.w, V.z/V.w);
        }
      }
      else if (face.data.type == FaceType.Remote)
      {
        // This is awful, but i can fix this later, it's just debug code
        if (showRemoteFaces)
        {
          glEnd();
          glEnable(GL_BLEND);
          glDisable(GL_DEPTH_TEST);
          glDepthMask(GL_FALSE);
          glBlendFunc(GL_ONE, GL_ONE);
          glColor3f(.3, 0, .3);
          glBegin(GL_QUADS);

          foreach (vi; face.indices)
          {
            vec3d v = space.verts[vi];
            vec4d V = vec4d(v.x, v.y, v.z, 1f);
            V = V * transform;
            glVertex3f(V.x/V.w, V.y/V.w, V.z/V.w);
          }

          glEnd();
          glDepthMask(GL_TRUE);
          glDisable(GL_BLEND);
          glBegin(GL_QUADS);
        }

        int nextSpaceID = face.data.remote.v.spaceID;
        if (descend && nextSpaceID != size_t.max && nextSpaceID != prevSpaceID)
        {
          //writefln("concatenating:\n%s", face.data.remote.v.transform);
          //writefln("            \tentering face: %d", faceID);
          drawSpace(
            nextSpaceID,
            transform * face.data.remote.v.transform,
            maxDepth,
            spaceID);
        }
      }
    }
  }
}

vec3d getTriangleNormal(vec3d a, vec3d b, vec3d c)
{
  // TODO is order correct?
  return cross(b-a, c-a);
}

void SUB(ref vec3d dest, ref vec3d v1, ref vec3d v2)
{
  dest.x=v1.x-v2.x;
  dest.y=v1.y-v2.y;
  dest.z=v1.z-v2.z; 
}
void CROSS(ref vec3d dest, ref vec3d v1, ref vec3d v2)
{
  dest.x=v1.y*v2.z-v1.z*v2.y;
  dest.y=v1.z*v2.x-v1.x*v2.z;
  dest.z=v1.x*v2.y-v1.y*v2.x;
}
double DOT(ref vec3d v1, ref vec3d v2)
{
  return v1.x*v2.x+v1.y*v2.y+v1.z*v2.z;
}
bool rayTriangleIntersect(vec3d orig, vec3d dir, vec3d vert0, vec3d vert1, vec3d vert2, ref vec3d rval)
{
  const double EPSILON = 0.000001;

  vec3d edge1, edge2, tvec, pvec, qvec, res;
  double det,inv_det;

  /* find vectors for two edges sharing vert0 */
  SUB(edge1, vert1, vert0);
  SUB(edge2, vert2, vert0);

  /* begin calculating determinant - also used to calculate U parameter */
  CROSS(pvec, dir, edge2);

  /* if determinant is near zero, ray lies in plane of triangle */
  det = DOT(edge1, pvec);

  /* calculate distance from vert0 to ray origin */
  SUB(tvec, orig, vert0);
  inv_det = 1.0 / det;

  CROSS(qvec, tvec, edge1);

  if (det > EPSILON)
  {
    res.u = DOT(tvec, pvec);
    if (res.u < 0.0 || res.u > det)
      return false;

    /* calculate V parameter and test bounds */
    res.v = DOT(dir, qvec);
    if (res.v < 0.0 || res.u + res.v > det)
      return false;

  }
  else if(det < -EPSILON)
  {
    /* calculate U parameter and test bounds */
    res.u = DOT(tvec, pvec);
    if (res.u > 0.0 || res.u < det)
      return false;

    /* calculate V parameter and test bounds */
    res.v = DOT(dir, qvec) ;
    if (res.v > 0.0 || res.u + res.v < det)
      return false;
  }
  else return false;  /* ray is parallell to the plane of the triangle */

  res.t = DOT(edge2, qvec) * inv_det;
  res.u = res.u * inv_det;
  res.v = res.v * inv_det;

  rval = res;
  writefln("rayTriangleIntersect() success: d:%f (%f, %f)", res.t, res.u, res.v);
  return 1;
}

bool passThruTest(vec3d orig, vec3d dir, vec3d vert0, vec3d vert1, vec3d vert2, double d)
{
  vec3d triix;
  if (!rayTriangleIntersect(orig, dir, vert0, vert1, vert2, triix))
    return false;

  // XXX not really sure that this works...
  return triix.t > 0f && triix.t < d;
}

/* XXX I am now using code that I don't understand
 *     need to brush up and see exactly how it works.
 */
bool linePlaneIntersect(vec3d lineStart, vec3d lineEnd, vec3d planeOrigin, vec3d axisA, vec3d axisB)
{
  vec3d originToaxisA = axisA - planeOrigin;
  vec3d originToaxisB = axisB - planeOrigin;

  vec3d planeNormal = cross(originToaxisA, originToaxisB).normalized;

  vec3d planeX = cross(planeNormal, originToaxisA).normalized;
  vec3d planeY = cross(planeNormal, originToaxisB).normalized;
  planeY = planeY * dot(originToaxisB, planeY);

  // line Info
  vec3d lineOrigin = lineStart;

  vec3d lineSegment = lineEnd - lineStart;
  vec3d lineNormal = (lineEnd - lineStart).normalized;

  // This finds the distance along the orginal line, where line and plane meet, multiply with the lines normal vector to get position 
  float distance = dot(planeOrigin - lineOrigin, planeNormal) / dot(lineNormal, planeNormal);
  vec3d linePlaneIntersection = lineStart + lineNormal * distance;

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

  vec3d pos;
  vec3d orient;
  float angle;

  float vel;
  float turnRate;

  this(World world, int spaceID, vec3d pos)
  {
    this.world = world;
    this.spaceID = spaceID;
    this.pos = pos;
    this.vel = 0f;
    this.angle = 0f;
    this.orient = vec3d(0,0,0);
    this.turnRate = 0f;
  }

  void update(ulong delta)
  {
    //writeln("position:", pos);
    // Remember old position for intersection tests
    vec3d oldpos = pos;

    // Nudge position and orientation
    float deltaf = delta/1000f;
    angle += turnRate * deltaf;
    orient = vec3d(-sin(angle), 0, cos(angle));
    vec3d movement = orient * (vel * deltaf);
    pos += movement;

    // Keep orientation inside 0-2pi
    while (angle < 0.0)
      angle += PI*2f;
    while (angle >= PI*2f)
      angle -= PI*2f;

    /* Intersect space faces */
    if (oldpos != pos)
    {
      //writefln("[intersections] op:%s d:%f", oldpos, movement.length);
      Space space = world.spaces[spaceID];
      foreach (faceIndex, face; space.faces)
      {
        /* TODO support arbitrary polygon faces */
        /* TODO XXX i have inverted pos and oldpos here because it fixes some polarity problem
         *          SOMEWHERE but i have no idea where. For now I will leave it like this but
         *          this problem needs to be solved!
         */
        vec3d intersection;
        int tris = 0;

        if (passThruTest(oldpos, movement.normalized, space.verts[face.indices[0]], space.verts[face.indices[1]], space.verts[face.indices[3]], movement.length))
        {
          tris += 1;
        }
        if (passThruTest(oldpos, movement.normalized, space.verts[face.indices[2]], space.verts[face.indices[3]], space.verts[face.indices[1]], movement.length))
        {
          tris += 10;
        }
        //writefln("intersection: face %d tris: %02d", faceIndex, tris);

        if (tris)
        {
          writefln("intersected face %d", faceIndex);
          if (face.data.type == FaceType.Remote && face.data.remote.v.spaceID >= 0)
          {
            // Move to the space we're entering
            spaceID = face.data.remote.v.spaceID;

            /* Scene coordinates are now relative to the space we've entered.
             * We must adjust our own coordinates so that we enter the space
             * at the correct position. We also need to adjust our orientation.
             */
            vec4d preTransformPos4 = vec4d(this.pos.x, this.pos.y, this.pos.z, 1f);
            vec4d pos = preTransformPos4 * face.data.remote.v.transform;
            pos.x = pos.x / pos.w;
            pos.y = pos.y / pos.w;
            pos.z = pos.z / pos.w;
            this.pos.x = pos.x;
            this.pos.y = pos.y;
            this.pos.z = pos.z;

            vec4d lookPos = vec4d(sin(angle), 0, cos(angle), 0f) + preTransformPos4;
            writeln("old  vec: ", oldpos);
            writeln("look vec: ", lookPos);
            lookPos = lookPos * face.data.remote.v.transform;
            writeln("new  vec: ", lookPos);
            lookPos.x = lookPos.x / lookPos.w;
            lookPos.y = lookPos.y / lookPos.w;
            lookPos.z = lookPos.z / lookPos.w;
            writeln("/w   vec: ", lookPos);
            lookPos = lookPos - pos;
            writeln("-op  vec: ", lookPos);
            writeln("transform: ", face.data.remote.v.transform);
            writefln("angle: %f", angle);
            angle = atan2(lookPos.x, lookPos.z);
            writefln("angle: %f new", angle);

            writefln("entered space %d", spaceID);
            break;
          }
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

    /*
    glBegin(GL_TRIANGLES);
    glColor3f (1, 0, 0); glVertex3f(-1, -1, -2);
    glColor3f (0, 1, 0); glVertex3f( 1, -1, -2);
    glColor3f (0, 0, 1); glVertex3f( 0,  1, -2);
    glEnd();
    */

    glBegin(GL_QUADS);
    world.drawSpace(spaceID, mat4.identity, 3, -1);
    glEnd();

    glMatrixMode(GL_MODELVIEW);
    glPopMatrix();
  }
}
