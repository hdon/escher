module ants.escher;
import derelict.opengl.gl;
import gl3n.linalg : Vector, Matrix, Quaternion, dot, cross;
import std.conv;
import gl3n.interpolate : lerp;
import std.math : sqrt, PI, sin, cos, atan2, isNaN, abs;
import std.exception : enforce;
import std.string : splitLines, split;
import file = std.file;
import std.typecons : Tuple;
import std.algorithm : sort;
import ants.shader;
debug import std.stdio : writeln, writefln;

void explode()
{
  static bool explosion;
  explosion = true;
}

void glErrorCheck()
{
  GLenum err = glGetError();
  if (err)
  {
    writefln("error: opengl: %s", err);
    explode();
    //assert(0);
  }
}

// TODO look this up
// http://www.opengl.org/registry/specs/ARB/depth_clamp.txt
// this might help deal with the issue of portal rendering when the portal face
// intersects the near viewing plane

alias Vector!(double, 2) vec2;
alias Vector!(double, 3) vec3;
alias Vector!(double, 4) vec4;
alias Matrix!(double, 4, 4) mat4;
alias Quaternion!(double) quat;

struct Tri
{
  vec3 a;
  vec3 b;
  vec3 c;
}

struct ClipVert4
{
  vec4 v;
  bool visible;
  float distance;
  int occurs;
}

struct ClipPlane4
{
  vec4 normal;
  double c;
}

version (never)
{
  private struct Polygon4
  {
    vec4 points[];
    Segment edges[];

    /* Constructor argument is an ordered list of points in the
     * polygon. Edges are inferred from this data.
     */
    this(vec4[] data)
    {
      points.reserve(data.length);
      edges.reserve(data.length);
      foreach (i, v; data)
      {
        points ~= v;
        edges ~= Segment(i, (i+1) % data.length);
      }
    }

    /* Clips against default view frustum.
     */
    bool clip()
    {
    }

    /* David Eberly "Clipping a Mesh Against a Plane"
     */
    bool planeClip(ClipPlane4 clipPlane)
    {
      ClipVert[points.length] verts;
      int negative;
      int positive;

      foreach (i, v; points)
      {
        verts[i].v = v;
        verts[i].visible = true;
      }

      foreach (vi, ref v; points)
      {
        if (v.visible)
        {
          double distance = dot(clipPlane.normal, v.v,) - clipPlane.c;
          if (distance >= epsilon)
          {
            positive++;
          }
          else if (distance <= -epsilon)
          {
            negative++;
            v.visible = false;
          }
          else
          {
            v.distance = 0.0;
          }
        }
      }

      if (negative == 0)
      {
        // no vertices clipped
        return true;
      }

      if (positive == 0)
      {
        // all vertices clipped
        return false;
      }

      foreach (e; edges)
      {
        if (e.visible)
        {
          vec4 v0 = verts[e.a];
          vec4 v1 = verts[e.b];
          double d0 = v0.distance;
          double d1 = v1.distance;
          
          if (d0 <= 0 && d1 <= 0)
          {
            e.visible = false;
          }

          if (d0 >= 0 && d1 >= 0)
          {
            continue;
          }

          double t = d0/(d0-d1);
          vec4 intersect = (1-t) * v0.v + t * v1.v;
          auto index = verts.length;
          verts ~= intersect;
          if (d0 > 0)
            e.b = index;
          else
            e.a = index;
        }
      }
    }
  }
}

private struct Segment
{
  ulong a, b;
  bool visible;

  this(ulong a, ulong b)
  {
    this.a = a;
    this.b = b;
    this.visible = true;
  }
}

private struct Polygon4
{
  vec4 points[];
  Segment edges[];

  /* Constructor argument is an ordered list of points in the
   * polygon. Edges are inferred from this data.
   */
  this(vec4[] data)
  {
    points.reserve(data.length);
    edges.reserve(data.length);
    foreach (i, v; data)
    {
      points ~= v;
      edges ~= Segment(i, (i+1) % data.length);
    }
  }

  // clips this polygon
  // returns false if polygon is completely clipped
  bool clip()
  {
    //writefln("Polygon4.clip() edges: %s", edges);
    //writefln("Polygon4.clip() points: %s", points);
    //foreach (i, p; points)
      //writefln("Polygon4.clip() point %d boundbits %d vec %s", i, clipClassifyVertex(p), p);

    foreach (plane; 0..6)
    {
      bool visible = false;
      bool needRepair = false;
      foreach (i, ref edge; edges)
      {
        vec4 a = points[edge.a];
        vec4 b = points[edge.b];
        auto clipCode = clipSegment(a, b, plane);
        //writefln("Polygon4.clip() calling clipSegment() on segment %d %s result=%d", i, edge, clipCode);
        if (clipCode == 0)
        {
          edge.visible = false;
          needRepair = true;
          continue;
        }

        visible = true;

        if (clipCode == 1)
          continue;

        needRepair = true;

        if (a != points[edge.a])
        {
          edge.a = points.length;
          points ~= a;
        }
        if (b != points[edge.b])
        {
          edge.b = points.length;
          points ~= b;
        }
      }
      if (!visible)
        return false;
      if (needRepair)
        repair();
    }

    return true;
  }

  void repair()
  {
    // fill in missing pieces
    Segment[] resultEdges;

    /* We'll have to iterate over all edges, filtering out invisible
     * edges, and making one last loop to connect the last edge to the
     * first edge.
     *
     * 'i' is the edge we're currently examining; this may
     * not be visible, and it may also be edges.length, which indicates
     * we are in the "columbus" run of the loop.
     *
     * 'j' is the previous visible edge we've encountered. we initialize
     * it to the special value "edges.length" to indicate that we haven't
     * yet come across our first visible edge.
     *
     * 'k' is the first visible edge we encounter. we initialize it to
     * the special value edges.length to indicate that we are not yet
     * in the "columbus" run of the loop. we want to check this before
     * the meat of the loop so we can .. maybe
     */
    ulong i = 0;
    ulong j = edges.length;
    ulong k = edges.length;
    while (1)
    {
      //writefln("[REPAIR] examining edge %d/%d", i, edges.length);

      // If we've overrun our list of edges, we now use the last
      // and first visible edge as our edge pair. We'll exit the
      // loop after this
      if (i == edges.length)
      {
        //writefln("[REPAIR] no more visible edges, using first visible edge %d", k);
        i = k;
      }

      //writefln("[REPAIR] edge[i] = %s", edges[i]);
      if (edges[i].visible)
      {
        // Is this our first visible edge?
        if (j == edges.length)
        {
          //writefln("[REPAIR] cataloguing first visible edge %d", i);
          // We don't need to do much if this is our first visible edge,
          // we just remember it so we can connect it to the last visible
          // edge
          k = i;
        }
        // We now have two visible edges to work with
        else
        {
          //writefln("[REPAIR] examining edge pair %d, %d", j, i);
          // does the previous edge 'j' connect to the current edge 'i'?
          if (edges[j].b != edges[i].a)
          {
            //writefln("[REPAIR] synthesizing edge", edges[j].b, edges[i].a);
            // it doesn't connect. we must connect them with a new segment
            resultEdges ~= Segment(edges[j].b, edges[i].a);
          }

          // If this was our last run, we're done.
          if (i == k)
            break;
        }

        // Now that we've had an opportunity to join disconnected edges,
        // we can append this edge.
        resultEdges ~= edges[i];

        // Remember the previous visible edge
        j = i;
      }
      // Examine the next edge
      i++;
    }

    // Store new edges
    edges = resultEdges;
    //writefln("Polygon4.clip() result\npoints: %s\nedges: %s", points, edges);
  }

  /* Calculate and return the signed area of this polygon.
   * Assumes a closed ("repaired") polygon.
   */
  double signedArea()
  {
    enforce(edges.length >= 3, "polygons with less than 3 sides is no polygons");

    /* Perform perspective divide, discard zw components */
    vec2 verts[];
    foreach (i, p; points)
    {
      verts ~= vec2(p.x/p.w, p.y/p.w);
    }

    double area = 0.0;
    foreach (edge; edges)
    {
      vec2 a = verts[edge.a];
      vec2 b = verts[edge.b];
      area += a.x * b.y - a.y * b.x;
    }

    return area;
  }

  void drawTriangles()
  {
    // TODO arbitrary polygon triangulation!
    enforce(edges.length >= 3, "polygons with less than 3 sides is not polygons!");
    if (edges.length == 3)
    {
      foreach (edge; edges)
      {
        vec4 v = points[edge.a];
        glVertex4d(v.x, v.y, v.z, v.w);
      }
    }
    else if (edges.length == 4)
    {
      foreach (i; 0..3)
      {
        vec4 v = points[edges[i].a];
        glVertex4d(v.x, v.y, v.z, v.w);
      }
      foreach (i; [2,3,0])
      {
        vec4 v = points[edges[i].a];
        glVertex4d(v.x, v.y, v.z, v.w);
      }
    }
    else
    {
      writefln("Polygon4.drawTriangles() skipping because %d sides", edges.length);
    }
  }
}

private struct Ray
{
  vec3 pos;
  vec4 orient;

  /*this(vec3 pos, quat orient)
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

vec3 xformVec(vec3 v, mat4 m)
{
  vec4 t = vec4(v.x, v.y, v.z, 1) * m;
  return vec3(t.x/t.w, t.y/t.w, t.z/t.w);
}

struct ClippingVertex
{
  vec3  v;
  bool  clipped;
}

// THANKS GENA
enum BoundaryBits {
  NONE = 0,
  BL = (1 << 0),
  BR = (1 << 1),
  BT = (1 << 2),
  BB = (1 << 3),
  BN = (1 << 4),
  BF = (1 << 5),
}

BoundaryBits clipClassifyVertex(vec4 v)
{
  //writeln("classifying vector ", v);
  BoundaryBits r;
  if (v.w+v.x < 0)
  {
    //writeln("w+x < 0");
    r |= BoundaryBits.BL;
  }
  if (v.w-v.x < 0)
  {
    //writeln("w-x < 0");
    r |= BoundaryBits.BR;
  }
  if (v.w+v.y < 0)
  {
    //writeln("w+y < 0");
    r |= BoundaryBits.BT;
  }
  if (v.w-v.y < 0)
  {
    //writeln("w-y < 0");
    r |= BoundaryBits.BB;
  }
  if (v.z < 0)
  {
    //writeln("z < 0");
    r |= BoundaryBits.BN;
  }
  if (v.w-v.z < 0)
  {
    //writeln("w-z < 0");
    r |= BoundaryBits.BF;
  }
  return r;
}

// returns false if the segment is completely clipped (invisible)
// returns
//  0: completely clipped
//  1: not clipped
//  2: partly clipped
int clipSegment(ref vec4 a, ref vec4 b, int plane)
{
  BoundaryBits ac, bc;

  //writeln("CLIPPING SEGMENT", a, b);

  double t;

  ac = clipClassifyVertex(a);
  bc = clipClassifyVertex(b);

  // Line segment completely visible
  if (((ac | bc) & (1<<plane)) == 0)
    return 1;

  // Line segment trivially invisible
  if (((ac & bc) & (1<<plane)) != 0)
    return 0;

  switch (plane)
  {
    case 0:
      // plane w+x = 0
      if (((ac | bc) & BoundaryBits.BL) != 0)
      {
        t = (a.w+a.x) / (a.w+a.x-b.w-b.x);
        if (ac & BoundaryBits.BL)
          a = (1-t)*a + t*b;
        else
          b = (1-t)*a + t*b;
      }
      break;

    case 1:
      // plane w-x = 0
      if (((ac | bc) & BoundaryBits.BR) != 0)
      {
        t = (a.w-a.x) / (a.w-a.x-b.w+b.x);
        if (ac & BoundaryBits.BR)
          a = (1-t)*a + t*b;
        else
          b = (1-t)*a + t*b;
      }
      break;

    case 2:
      // plane w+y = 0
      if (((ac | bc) & BoundaryBits.BT) != 0)
      {
        t = (a.w+a.y) / (a.w+a.y-b.w-b.y);
        if (ac & BoundaryBits.BT)
          a = (1-t)*a + t*b;
        else
          b = (1-t)*a + t*b;
      }
      break;

    case 3:
      // plane w-y = 0
      if (((ac | bc) & BoundaryBits.BB) != 0)
      {
        t = (a.w-a.y) / (a.w-a.y-b.w+b.y);
        if (ac & BoundaryBits.BB)
          a = (1-t)*a + t*b;
        else
          b = (1-t)*a + t*b;
      }
      break;

    case 4:
      // plane z = 0
      if (((ac | bc) & BoundaryBits.BN) != 0)
      {
        t = (a.z) / (a.z-b.z);
        if (ac & BoundaryBits.BN)
          a = (1-t)*a + t*b;
        else
          b = (1-t)*a + t*b;
      }
      break;

    case 5:
      // plane w-z = 0
      if (((ac | bc) & BoundaryBits.BF) != 0)
      {
        t = (a.w-a.z) / (a.w-a.z-b.w+b.z);
        if (ac & BoundaryBits.BF)
          a = (1-t)*a + t*b;
        else
          b = (1-t)*a + t*b;
      }
      break;

    default:
      enforce(0, "unknown clipping plane");
  }

  //writeln("CLIPPED  SEGMENT", a, b);

  return 2;
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
              vec3 translation;

              bool hasRotation = false;
              vec3 rotationAxis;
              float rotationAngle;

              // TODO scaling

              translation = vec3(
                to!float(words[8]),
                to!float(words[9]),
                to!float(words[10]));

              if (words.length >= 16)
              {
                enforce(words[11] == "orientation", "expected orientation");

                hasRotation = true;

                rotationAngle = to!float(words[12]) / 180f * PI;
                rotationAxis = vec3(to!float(words[13]),
                                    to!float(words[14]),
                                    to!float(words[15]));
              }

              mat4 transform = mat4.identity;
              mat4 untransform = mat4.identity;

              untransform.translate(-translation.x, -translation.y, -translation.z);

              if (hasRotation)
              {
                transform.rotate(rotationAngle, rotationAxis);
                untransform.rotate(-rotationAngle, rotationAxis);
              }

              transform.translate(translation.x, translation.y, translation.z);

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

  ~this()
  {
    writeln("~World() - DESTRUCTED");
  }

  // TODO TODO TODO TODO TODO TODO 
  // What I am working on right now:
  // I am about to turn the transform argument of drawSpace() into a mat4.
  // I will need to use the orient field of the face.data.remote.v.remoteReferenceRay.
  // The orient field has been changed to a vec4. It is actually an xyz vector and
  // an angle (radians?) In the file format, I want to load degrees, so I should translate
  // them to radians at load time.
  // I am exploring how to create the matrix properly using the gl3n source code.
  // There is also an example on line 681 of how to load a matrix from gl3n into opengl.
  // I'm not sure I need to do that yet, but it might be nice for when I have models
  // and shit to draw, and not just a handful of polygons per space.
  mat4 pmatPortal  = mat4.perspective(800, 600, 90, 0.00001, 100);
  mat4 pmatWorld = mat4.perspective(800, 600, 90, 0.1, 100);
  ShaderProgram shaderProgram;

  void drawSpace(int spaceID, mat4 transform, size_t maxDepth, int prevSpaceID, int dmode)
  {
    //writeln("[DRAW SPACE]");
    //writeln("[DRAW SPACE]");
    //writeln("[DRAW SPACE]");
    Space space = spaces[spaceID];
    //writefln("[draw space]\t#%d d:%d", spaceID, maxDepth);
    maxDepth--;
    bool descend = maxDepth > 0;
    vec3 lookVec = vec3(0.0, 0.0, 1.0);

    foreach (faceID, face; space.faces)
    {
      vec4[4] verts;
      vec3[4] inverts;
      foreach (i, vi; face.indices)
      {
        inverts[i] = space.verts[vi];
        vec3 v3 = space.verts[vi];
        vec4 v4 = vec4(v3.x, v3.y, v3.z, 1);
        //writeln("vert s0: ", v4);
        v4 = v4 * transform;
        //writeln("vert s1: ", v4);
        if (face.data.type == FaceType.Remote)
          v4 = v4 * pmatPortal;
        else
          v4 = v4 * pmatWorld;
        //writeln("vert s2: ", v4);
        //v4 = v4 * (1.0 / v4.w);
        //writeln("vert s3: ", v4);
        verts[i] = v4;
      }
      //writeln("modelview: ", transform);
      //writeln("in  verts: ", inverts);
      //writeln("out verts: ", verts);

      if (face.data.type == FaceType.SolidColor)
      {
        if (dmode == 0)
        {
          auto polygon = new Polygon4(verts[]);

          if (polygon.clip())
          {
            if (polygon.signedArea() < 0.0)
              continue;

            glColor3ub(
              face.data.solidColor.v[0],
              face.data.solidColor.v[1],
              face.data.solidColor.v[2]);

            version (lighting) {
              GLfloat[4] ambient;
              ambient[0] = face.data.solidColor.v[0]/127.0;
              ambient[1] = face.data.solidColor.v[1]/127.0;
              ambient[2] = face.data.solidColor.v[2]/127.0;
              ambient[3] = 1;

              GLfloat[4] diffuse = ambient;
              GLfloat[4] specular = [1,1,1,1];
              glMaterialfv(GL_FRONT, GL_AMBIENT, ambient);
              glMaterialfv(GL_FRONT, GL_DIFFUSE, diffuse);
              glMaterialfv(GL_FRONT, GL_SPECULAR, specular);

              glMateriali(GL_FRONT, GL_SHININESS, 127);
            }

            // TODO precompute normals? bump map?
            vec3 faceNorm = getTriangleNormal(
              xformVec(space.verts[face.indices[0]], transform),
              xformVec(space.verts[face.indices[1]], transform),
              xformVec(space.verts[face.indices[2]], transform)).normalized;
            //writefln("face normal: %s", faceNorm);
            glNormal3d(faceNorm.x, faceNorm.y, faceNorm.z);

            glVertex4f(verts[0].x, verts[0].y, verts[0].z, verts[0].w);
            glVertex4f(verts[1].x, verts[1].y, verts[1].z, verts[1].w);
            glVertex4f(verts[2].x, verts[2].y, verts[2].z, verts[2].w);

            glVertex4f(verts[2].x, verts[2].y, verts[2].z, verts[2].w);
            glVertex4f(verts[3].x, verts[3].y, verts[3].z, verts[3].w);
            glVertex4f(verts[0].x, verts[0].y, verts[0].z, verts[0].w);
          }
        }
      }
      else if (face.data.type == FaceType.Remote)
      {
        auto polygon = new Polygon4(verts[]);

        if (polygon.clip())
        {
          if (polygon.signedArea() > 0.0)
          {
            if (dmode == 1)
            {
              glColor3ub(255, 0, 0);
              foreach (edge; polygon.edges)
              {
                vec4 a = polygon.points[edge.a];
                vec4 b = polygon.points[edge.b];
                a = a * (1.0 / a.w);
                b = b * (1.0 / b.w);
                a *= 0.9;
                b *= 0.9;
                glVertex2d(a.x, a.y);
                glVertex2d(b.x, b.y);
              }
            }

            /* We want to calculate visibility of this portal. We may draw a
             * blended quad here for debugging purposes, or we may use this
             * data to determine visibility of this and subsequent spaces.
             */
            //Polygon3 polygon = Polygon3(verts);

            int nextSpaceID = face.data.remote.v.spaceID;
            if (descend && nextSpaceID != size_t.max)
            {
              //writefln("concatenating:\n%s", face.data.remote.v.transform);
              //writefln("            \tentering face: %d", faceID);

              version (stencil) {
              // We'll now want to draw to the stencil buffer a polygon representing
              // our portal
              glEnd();

              // Draw our portal stencil
              glEnable(GL_STENCIL_TEST);
              glClearStencil(0);
              glClear(GL_STENCIL_BUFFER_BIT);
              glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
              glDepthMask(GL_FALSE);
              glStencilFunc(GL_NEVER, 1, 0xFF);
              glStencilOp(GL_REPLACE, GL_KEEP, GL_KEEP);
              glStencilMask(0xFF);
              glBegin(GL_TRIANGLES);
              //polygon.drawTriangles();
              glVertex4f(verts[0].x, verts[0].y, verts[0].z, verts[0].w);
              glVertex4f(verts[1].x, verts[1].y, verts[1].z, verts[1].w);
              glVertex4f(verts[2].x, verts[2].y, verts[2].z, verts[2].w);

              glVertex4f(verts[2].x, verts[2].y, verts[2].z, verts[2].w);
              glVertex4f(verts[3].x, verts[3].y, verts[3].z, verts[3].w);
              glVertex4f(verts[0].x, verts[0].y, verts[0].z, verts[0].w);
              glEnd();

              // Draw space beyond the portal
              glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
              glDepthMask(GL_TRUE);
              glStencilMask(0);
              glStencilFunc(GL_EQUAL, 1, 0xFF);
              glBegin(GL_TRIANGLES);
              }

              //glColor3f(1,0,0);
              //polygon.drawTriangles();
              drawSpace(
                nextSpaceID,
                transform * face.data.remote.v.transform,
                maxDepth,
                spaceID,
                dmode);

              version (stencil) {
              glEnd();
              glDisable(GL_STENCIL_TEST);
              glBegin(GL_TRIANGLES);
              }
            }
          }
        }
      }
    }
  }
}

vec3 getTriangleNormal(vec3 a, vec3 b, vec3 c)
{
  // TODO is order correct?
  return cross(a-b, a-c);
}
bool cullFace(vec3 look, Tri tri)
{
  auto theta = dot(look.normalized, cross((tri.b - tri.a).normalized, (tri.b - tri.c).normalized).normalized);
  writefln("cullFace() tri=%s theta=%s", tri, theta);
  return theta >= 0.0;
}
bool cullFace2(vec4 a, vec4 b, vec4 c)
{
  writeln("culling vert 0: ", a);
  writeln("culling vert 1: ", b);
  writeln("culling vert 2: ", c);

  auto f=a.x * b.y - a.y * b.x +
         b.x * c.y - b.y * c.x +
         c.x * a.y - c.y * a.x;
  writefln("cullFace2() sez %s", f);
  return f < 0;
}

version (fuckyou) {
alias Tuple!(size_t,size_t) IndexPair;
/* This function clips a polygon by a particular plane.
 * Arguments:
 *  P - the vertices of the polygon, in order. this will be modified by
 *      clipping
 * Returns false if the polygon is entirely clipped
 */
bool clipPolygon(vec3[] P, vec3 pn, vec3 pd)
{
  foreach (i, p; P)
  {
  }
}

/* Determines where a vector lies relative to the volume
 * (-1, -1, -1), (1, 1, 0)
 * a = vector
 */
ubyte vectorVsVolume(vec3 v)
{
  ubyte rval = 0;
  if (v.x < -1)     rval |= 1;
  else if (v.x > 1) rval |= 2;
  if (v.y < -1)     rval |= 4;
  else if (v.y > 1) rval |= 8;
  if (v.z < -1)     rval |= 16;
  else if (v.z > 1) rval |= 32;
  return rval;
}
/* Clips a line segment to the volume (-1, -1, -1), (1, 1, 0)
 */
bool clipLineSegment(ref vec3 a, ref vec3 b)
{
  // Calculate slopes
  vec3 m;
  m.x = (a.x-b.x)
  = vec3(a.x-b.x, a.y-b.y, a.z-b.z);

  // Clip to plane x=-1
  if (a.x < -1)
  {
    if (b.x < -1)
      return false;
    a.x = -1;
  }
  if (a.x < -1 && b.x < -1)
    return false;
  //if (a.x <
}
/* Clips a triangle to the volume (-1, -1, -1), (1, 1, 0)
 * Returns the number of triangles that result from the clipping.
 * 0 if the entire triangle is outside of clip space.
 * 1 if the entire triangle was inside clip space.
 * 1 if two vertices of the triangle were outside clip space.
 * 2 if one vertex of the triangle was outside clip space.
 *
 * Arguments:
 *  t0 is the input triangle
 *  t1 is a second triangle that my be generated by the function
 *  c is the numeric index of the component to be tested (0, 1, 2)
 *  lt is true if the plane clips vertexes less than it, false if greater than
 */
int planeClipsTriangle(ref vec3[3] t0, ref vec3[3] t1, int c, bool lt)
{
  bool clipped[3];
  int nclipped = 0;
  foreach (i, v; t0)
  {
    float x = t0[i].vector[c];
    if (lt)
    {
      if (x < -1)
      {
        clipped[i] = true;
        nclipped++;
      }
    }
    else
    {
      if (x > 1)
      {
        clipped[i] = true;
        nclipped++;
      }
    }
  }
}
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
bool rayTriangleIntersect(vec3 orig, vec3 dir, vec3 vert0, vec3 vert1, vec3 vert2, ref vec3 rval)
{
  const double EPSILON = 0.000001;

  vec3 edge1, edge2, tvec, pvec, qvec, res;
  double det,inv_det;

  /* find vectors for two edges sharing vert0 */
  edge1 = vert1 - vert0;
  edge2 = vert2 - vert0;

  /* begin calculating determinant - also used to calculate U parameter */
  pvec = cross(dir, edge2);

  /* if determinant is near zero, ray lies in plane of triangle */
  det = dot(edge1, pvec);

  /* calculate distance from vert0 to ray origin */
  tvec = orig - vert0;
  inv_det = 1.0 / det;

  qvec = cross(tvec, edge1);

  if (det > EPSILON)
  {
    res.u = dot(tvec, pvec);
    if (res.u < 0.0 || res.u > det)
      return false;

    /* calculate V parameter and test bounds */
    res.v = dot(dir, qvec);
    if (res.v < 0.0 || res.u + res.v > det)
      return false;

  }
  else if(det < -EPSILON)
  {
    /* calculate U parameter and test bounds */
    res.u = dot(tvec, pvec);
    if (res.u > 0.0 || res.u < det)
      return false;

    /* calculate V parameter and test bounds */
    res.v = dot(dir, qvec) ;
    if (res.v > 0.0 || res.u + res.v < det)
      return false;
  }
  else return false;  /* ray is parallell to the plane of the triangle */

  // NOTE this dot product appears to be the world-space distance that i want
  //      from the ray's intersection point with the plane of the triangle.
  //      i'm not sure what purpose the inv_det multiplication serves.
  //res.t = dot(edge2, qvec) * inv_det;
  res.t = dot(edge2, qvec);
  res.u = res.u * inv_det;
  res.v = res.v * inv_det;

  rval = res;
  //writefln("rayTriangleIntersect() success: d:%f (%f, %f)", res.t, res.u, res.v);
  return 1;
}

bool passThruTest(vec3 orig, vec3 dir, vec3 vert0, vec3 vert1, vec3 vert2, double d)
{
  vec3 triix;
  if (!rayTriangleIntersect(orig, dir, vert0, vert1, vert2, triix))
    return false;

  // XXX not really sure that this works...
  return triix.t > 0f && triix.t < d;
}

class Camera
{
  World world;
  int spaceID;

  vec3 pos;
  vec3 orient;
  double camYaw;
  double camPitch;

  float vel;
  float turnRate;

  this(World world, int spaceID, vec3 pos)
  {
    this.world = world;
    this.spaceID = spaceID;
    this.pos = pos;
    this.vel = 0f;
    this.orient = vec3(0,0,0);
    this.turnRate = 0f;
    this.camYaw = 0.0;
    this.camPitch = 0.0;
  }

  void update(ulong delta)
  {
    //writeln("position:", pos);
    // Remember old position for intersection tests
    vec3 oldpos = pos;

    // Keep orientation inside 0-2pi
    while (camYaw < 0.0)
      camYaw += PI*2f;
    while (camYaw >= PI*2f)
      camYaw -= PI*2f;

    // Nudge position and orientation
    float deltaf = delta/1000f;
    orient = vec3(sin(camYaw), 0, cos(camYaw));
    vec3 movement = orient * (vel * deltaf);
    pos += movement;

    //writefln("vel: %s turn: %s", vel, turnRate);
    /* Intersect space faces */
    if (oldpos != pos)
    {
      //writeln("movement.length = ", movement.length, " but also = ", (pos-oldpos).length);
      Space space = world.spaces[spaceID];
      foreach (faceIndex, face; space.faces)
      {
        int tris = 0;
        /* TODO support arbitrary polygon faces */
        /* TODO XXX i have inverted pos and oldpos here because it fixes some polarity problem
         *          SOMEWHERE but i have no idea where. For now I will leave it like this but
         *          this problem needs to be solved!
         */
        if (passThruTest(oldpos, movement.normalized, space.verts[face.indices[0]], space.verts[face.indices[1]], space.verts[face.indices[3]], movement.length))
        {
          tris += 1;
        }
        if (passThruTest(oldpos, movement.normalized, space.verts[face.indices[2]], space.verts[face.indices[3]], space.verts[face.indices[1]], movement.length))
        {
          tris += 10;
        }

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
            vec4 preTransformPos4 = vec4(this.pos.x, this.pos.y, this.pos.z, 1f);
            vec4 pos = preTransformPos4 * face.data.remote.v.untransform;
            pos.x = pos.x / pos.w;
            pos.y = pos.y / pos.w;
            pos.z = pos.z / pos.w;
            this.pos.x = pos.x;
            this.pos.y = pos.y;
            this.pos.z = pos.z;

            vec4 lookPos = vec4(orient.x, orient.y, orient.z, 0f) + preTransformPos4;
            writeln("old  vec: ", oldpos);
            writeln("look vec: ", lookPos);
            lookPos = lookPos * face.data.remote.v.untransform;
            writeln("new  vec: ", lookPos);
            lookPos.x = lookPos.x / lookPos.w;
            lookPos.y = lookPos.y / lookPos.w;
            lookPos.z = lookPos.z / lookPos.w;
            writeln("/w   vec: ", lookPos);
            lookPos = lookPos - pos;
            writeln("-op  vec: ", lookPos);
            writeln("transform: ", face.data.remote.v.transform);
            writefln("camYaw: %f", camYaw);
            camYaw = atan2(lookPos.x, lookPos.z);
            writefln("camYaw: %f new", camYaw);

            writefln("entered space %d", spaceID);
            break;
          }
        }
      }
    }
  }

  void draw()
  {
    //glEnable(GL_CULL_FACE);

    //glRotatef(-angle/PI*180f, 0, 1, 0);
    //glTranslatef(-pos.x, -pos.y, -pos.z);
    //glRotatef(spin, 0, 1, 0);
    //glRotatef(spin, 0.9701425001453318, 0.24253562503633294, 0);

    /*
    glBegin(GL_TRIANGLES);
    glColor3f (1, 0, 0); glVertex3f(-1, -1, -2);
    glColor3f (0, 1, 0); glVertex3f( 1, -1, -2);
    glColor3f (0, 0, 1); glVertex3f( 0,  1, -2);
    glEnd();
    */

    if (world.shaderProgram is null)
    {
      world.shaderProgram = new ShaderProgram("simple.vs", "simple.fs");
      world.shaderProgram.use();
    }
    glErrorCheck();

    glMatrixMode(GL_PROJECTION);
    glOrtho(-1, 1, -1, 1, -1, 0);

    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    glDisable(GL_BLEND);

    glEnable(GL_DEPTH_TEST);
    glClearDepth(1);
    glDepthFunc(GL_LESS);

    version (lighting) {
      glEnable(GL_LIGHTING);
      glEnable(GL_LIGHT0);
    }

    mat4 mvmat = mat4.translation(-pos.x, -pos.y, -pos.z);
    mvmat.rotate(camYaw, vec3(0,1,0));
    mvmat.rotate(camPitch, vec3(1,0,0));

    glErrorCheck();
    glBegin(GL_TRIANGLES);
    world.drawSpace(spaceID, mvmat, 18, -1, 0);
    glEnd();
    glErrorCheck();

    /*glDisable(GL_DEPTH_TEST);
    glBegin(GL_LINES);
    world.drawSpace(spaceID, mvmat, 18, -1, 1);
    glEnd();*/
  }
}
