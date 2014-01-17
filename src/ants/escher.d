module ants.escher;

import derelict.sdl2.sdl;
import derelict.sdl2.image;
import derelict.opengl3.gl3;
import gl3n.linalg : Vector, Matrix, Quaternion, dot, cross;
import std.conv;
import gl3n.interpolate : lerp;
import std.math : sqrt, PI, sin, cos, atan2, isNaN, abs;
import std.exception : enforce;
import std.string : splitLines, split;
import file = std.file;
import std.typecons : Tuple;
import std.algorithm : sort, map;
import std.range : chunks;
import ants.shader;
import ants.md5 : MD5Model, MD5Animation;
import ants.texture;
import ants.vertexer;
import ants.material;
import ants.entity;
import std.datetime : StopWatch;
import core.time : TickDuration;
debug import std.stdio : writeln, writefln;

/*version(customTransform) {pragma(msg, "rendering all polygons with CUSTOM transforms");}
else{ pragma(msg, "rendering with OPENGL transforms"); }*/

version(escherClient) { pragma(msg, "Building Escher client"); }
else version(escherServer) { pragma(msg, "Building Escher server"); }
else { static assert(0, "Version must be either escherClient or escherServer!"); }

version(stencil) {pragma(msg, "Stencils enabled");}
else{ pragma(msg, "Stencils disabled"); }

version (lighting) {pragma(msg, "Lighting enabled"); }
else{ pragma(msg, "Lighting disabled"); }

bool portalDiagnosticMode;

void explode()
{
  static bool explosion;
  explosion = true;
}

void glErrorCheck(string source)
{
  GLenum err = glGetError();
  if (err)
  {
    writefln("error @ %s: opengl: %s", source, err);
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
alias Matrix!(double, 2, 2) mat2;
alias Matrix!(double, 3, 3) mat3;
alias Matrix!(double, 4, 4) mat4;
alias Quaternion!(double) quat;

alias Vector!(float, 3) vec3f;
alias Vector!(float, 3) ColorVec;

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
  size_t a, b;
  bool visible;

  this(size_t a, size_t b)
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
    size_t i = 0;
    size_t j = edges.length;
    size_t k = edges.length;
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

  version (triangulation) void drawTriangles()
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
  float[3]  v;
  int       materialID;
}

struct FaceDataRemote
{
  FaceType type;
  int remoteID;
}

union FaceData
{
  FaceType  type;
  FaceDataSolidColor solidColor;
  FaceDataRemote remote;
}

class Face
{
  size_t[]  indices;
  vec2[]    UVs;
  vec3[]    normals;
  FaceData  data;

  override
  string toString()
  {
    return to!string(indices);
  }
}

bool compareFacesByRenderType(Face a, Face b)
{
  return
    a.data.type != b.data.type ?
    a.data.type <  b.data.type :
      a.data.type == FaceType.SolidColor ?
      a.data.solidColor.materialID < b.data.solidColor.materialID :
        a.data.remote.remoteID < b.data.remote.remoteID;
}

class Space
{
  int       id;
  Remote[]  remotes;
  vec3[]    verts;
  Face[]    faces;
  Spawner[] spawns;

  override
  string toString()
  {
    return to!string(faces);
  }
}

private enum ParserMode
{
  expectNumMaterials,
  expectMaterial,
  expectTexture,
  expectNumSpaces,
  expectSpace,
  expectRemote,
  expectSpawn,
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
  if (v.w+v.z < 0)
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
        //t = (a.z) / (a.z-b.z);
        t = (a.w+a.z) / (a.w+a.z-b.w-b.z);
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

void processSomeVerts(ref vec4[4] outVerts, vec3[] verts, int[] indices, mat4 mvmat, mat4 pmat)
{
  enforce(verts.length == 4, "lol only 4 verts allowed");
  foreach (i, vi; indices)
  {
    vec3 v3 = verts[vi];
    vec4 v4 = vec4(v3.x, v3.y, v3.z, 1);
    v4 = v4 * mvmat;
    v4 = v4 * pmat;
    outVerts[i] = v4;
  }
}

bool drawFace(Space space, Face face, mat4 mvmat, mat4 pmat)
{
  size_t nverts = face.indices.length;
  if (nverts != 3 && nverts != 4)
  {
    writefln("skipping face because it has %d verts", nverts);
    return false;
  }

  // XXX support n-gons
  //writeln("drawFace() ", face);
  vec4[] verts;
  vec3[] inverts;
  vec2[] UVs;
  vec3[] normals;
  verts.length = nverts;
  inverts.length = nverts;
  UVs.length = nverts;
  normals.length = nverts;
  foreach (i, vi; face.indices)
  {
    inverts[i] = space.verts[vi];
    UVs[i] = face.UVs[i];
    normals[i] = face.normals[i];
    vec3 v3 = space.verts[vi];
    vec4 v4 = vec4(v3.x, v3.y, v3.z, 1);
    v4 = v4 * mvmat;
    v4 = v4 * pmat;
    verts[i] = v4;
  }

  auto polygon = new Polygon4(verts[]);
  //writeln("num verts: ", nverts);
  //writeln("polygon: ", polygon.points);

  if (!polygon.clip())
    return false;
  //writefln("polygon passed clipping");

  double signedArea = polygon.signedArea();
  //writefln("signed area: %f", signedArea);
  if (signedArea < 0.0)
    return false;

  ColorVec color;

  if (face.data.type == FaceType.SolidColor)
  {
    /*writefln("drawing solid color face %f %f %f",
        face.data.solidColor.v[0],
        face.data.solidColor.v[1],
        face.data.solidColor.v[2]);*/
    color = ColorVec(
        face.data.solidColor.v[0],
        face.data.solidColor.v[1],
        face.data.solidColor.v[2]);
  }
  else
  {
    color = ColorVec(1, 0, 1);
  }

  if (nverts == 4)
  {
    vertexer.add(inverts[0], UVs[0], normals[0], color);
    vertexer.add(inverts[1], UVs[1], normals[1], color);
    vertexer.add(inverts[2], UVs[2], normals[2], color);

    vertexer.add(inverts[2], UVs[2], normals[2], color);
    vertexer.add(inverts[3], UVs[3], normals[3], color);
    vertexer.add(inverts[0], UVs[0], normals[0], color);
  }
  else if (nverts == 3)
  {
    vertexer.add(inverts[0], UVs[0], normals[0], color);
    vertexer.add(inverts[1], UVs[1], normals[1], color);
    vertexer.add(inverts[2], UVs[2], normals[2], color);
  }
  else
  {
    writefln("unsupported number of verts: %d\n", nverts);
    assert(0, "unsupported number of verts");
  }

  return true;
}

class World
{
  Material[] materials;
  Space[] spaces;
  Entity[][] entities;

  this(string filename)
  {
    ParserMode mode = ParserMode.expectNumMaterials;

    // Convenient reference to the Space we're currently loading
    Space space;

    // Used to check for file sanity
    int spaceID, remoteID, materialID;
    size_t numSpaces, numVerts, numFaces, numRemotes, numMaterials, numTextures, numSpawns;

    foreach (lineNo, line; splitLines(to!string(cast(char[])file.read(filename))))
    {
      auto words = split(line);

      version (debugEscherFiles)
        writefln("processing line #%d: %s", lineNo+1, line);
      if (lineNo == 0)
      {
        enforce(line == "escher version 6", "first line of map must be: escher version 6");
        continue;
      }

      if (words.length)
      switch (mode)
      {
        case ParserMode.expectNumMaterials:
          enforce(words[0] == "nummaterials", "expected nummaterials");
          numMaterials = to!size_t(words[1]);
          materials.reserve(numMaterials);
          if (numMaterials > 0)
            mode = ParserMode.expectMaterial;
          else
            mode = ParserMode.expectNumSpaces;
          break;

        case ParserMode.expectNumSpaces:
          enforce(words[0] == "numspaces", "expected numspaces");
          numSpaces = to!size_t(words[1]);
          spaces.reserve(numSpaces);
          mode = ParserMode.expectSpace;
          break;

        case ParserMode.expectMaterial:
          enforce(words[0] == "material", "expected material");
          materialID = to!int(words[1]);
          enforce(materialID == materials.length, "materials disorganized");
          enforce(words[3] == "numtex", "expected numtex");
          numTextures = to!int(words[4]);
          materials ~= new Material();

          if (numTextures == 0)
          {
            if (materials.length == numMaterials)
              mode = ParserMode.expectNumSpaces;
            else
              mode = ParserMode.expectMaterial;
          }
          else
          {
            mode = ParserMode.expectTexture;
          }
          break;

        case ParserMode.expectTexture:
          auto materialTexture = new MaterialTexture();
          enforce(words[0] == "texture", "expected texture");
          if (words[1] == "COLOR")
          {
            materialTexture.application = TextureApplication.Color;
          }
          else if (words[1] == "NORMAL")
          {
            materialTexture.application = TextureApplication.Normal;
          }
          else
          {
            assert(0, "unknown texture application");
          }
          materialTexture.texture = loadTexture(words[2]);
          materials[materialID].texes ~= materialTexture;
          // XXX
          if (materials[materialID].texes.length == numTextures)
          {
            if (materials.length == numMaterials)
              mode = ParserMode.expectNumSpaces;
            else
              mode = ParserMode.expectMaterial;
          }
          break;

        case ParserMode.expectSpace:
          enforce(words[0] == "space", "expected space");
          enforce(words[2] == "numverts", "expected numverts");
          enforce(words[4] == "numfaces", "expected numfaces");
          enforce(words[6] == "numremotes", "expected numremotes");
          enforce(words[8] == "numspawns", "expected numspawns");
          spaceID = to!int(words[1]);
          enforce(spaceID == spaces.length, "spaces disorganized");

          numVerts = to!size_t(words[3]);
          numFaces = to!size_t(words[5]);
          numRemotes = to!size_t(words[7]);
          numSpawns = to!size_t(words[9]);

          space = new Space();
          space.id = spaceID;
          space.verts.reserve(numVerts);
          space.faces.reserve(numFaces);
          space.remotes.reserve(numRemotes);
          space.spawns.reserve(numSpawns);
          spaces ~= space;

          if (numRemotes > 0)
            mode = ParserMode.expectRemote;
          else if (numSpawns > 0)
            mode = ParserMode.expectSpawn;
          else
            mode = ParserMode.expectVert;
          break;

        case ParserMode.expectRemote:
          enforce(words[0] == "remote", "expected remote");
          enforce(to!size_t(words[1]) == space.remotes.length, "remotes disorganized");

          Remote remote;

          enforce(words[2] == "space", "expected space while parsing remote");
          remote.spaceID = to!int(words[3]); // not size_t because -1 special value

          /* -1 is a special case where we don't care about anything else. It's not
           * a real remote face anyhow.
           */
          if (remote.spaceID >= 0)
          {
            enforce(words[4] == "translation", "expected translation");
            vec3 translation;

            double[3] rotationEuler;

            // TODO scaling

            translation = vec3(
              to!double(words[5]),
              to!double(words[6]),
              to!double(words[7]));

            if (words.length > 8)
            {
              enforce(words[8] == "orientation", "expected orientation");

              rotationEuler[0] = to!double(words[9]);
              rotationEuler[1] = to!double(words[10]);
              rotationEuler[2] = to!double(words[11]);
            }

            mat4 transform = mat4.identity;
            mat4 untransform = mat4.identity;

            untransform.translate(-translation.x, -translation.y, -translation.z);

            // TODO clean this up with the new unit vectors you got dav1d to include
            /*foreach (i; 0..3)
            {
              transform.rotate(rotationEuler[i], rotationAxis);
              untransform.rotate(-rotationEuler[i], rotationAxis);
            }*/
            transform.rotate  ( rotationEuler[0], vec3(1, 0, 0));
            untransform.rotate(-rotationEuler[0], vec3(1, 0, 0));
            transform.rotate  ( rotationEuler[1], vec3(0, 1, 0));
            untransform.rotate(-rotationEuler[1], vec3(0, 1, 0));
            transform.rotate  ( rotationEuler[2], vec3(0, 0, 1));
            untransform.rotate(-rotationEuler[2], vec3(0, 0, 1));

            transform.translate(translation.x, translation.y, translation.z);

            //writeln("space transform\n", transform);

            remote.transform = transform;
            remote.untransform = untransform;
          }

          space.remotes ~= remote;

          if (space.remotes.length == numRemotes)
            mode = numSpawns != 0 ? ParserMode.expectSpawn : ParserMode.expectVert;
          break;

        case ParserMode.expectSpawn:
          enforce(words[0] == "spawn", "expected spawn");
          enforce(to!size_t(words[1]) == space.spawns.length, "spawns disorganized");
          enforce(words[2] == "translation", "expected translation");
          enforce(words[6] == "orientation", "expected orientation");
          enforce(words[10] == "params", "expected params");

          static if (1)
          {
            vec3 translation = vec3(
              to!float(words[3]),
              to!float(words[4]),
              to!float(words[5]));
            vec3 orientation = vec3(
              to!float(words[7]),
              to!float(words[8]),
              to!float(words[9]));

            vec3[] path;

            /* Look for a path for the spawner */
            if (words.length > 12)
            {
              enforce(words[12] == "path", "expected path");
              enforce((words.length-13)%3==0, "malformed path"); // -13 lol
              path.reserve((words.length-13)/3);
              foreach (vs; chunks(words[13..$], 3))
                path ~= vec3(to!double(vs[0]),
                             to!double(vs[1]),
                             to!double(vs[2]));
              // maybe something more like this?
              // map!(to!vec3)(chunks( map!(to!float)(words[13..$]), 3 ));
            }

            switch (words[11])
            {
              case "player":
                space.spawns ~= EntityPlayer.spawner(spaceID, translation, 0);
                break;
              case "spikey":
                space.spawns ~= EntitySpikey.spawner(spaceID, translation, orientation, path);
                break;
              case "dragonfly":
                space.spawns ~= EntityDragonfly.spawner(spaceID, translation, orientation, path);
                break;
              default:
                assert(0, "unknown spawn type " ~ words[11]);
            }
          }

          if (space.spawns.length == numSpawns)
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

          if (words[2] == "remote")
          {
            face.data.type = FaceType.Remote;
            face.data.remote.remoteID = to!int(words[3]);
          }
          else if (words[2] == "mat")
          {
            int faceMaterialID = to!int(words[3]);
            face.data.solidColor.materialID = faceMaterialID;

            // XXX i should probably get rid of this
            face.data.type = FaceType.SolidColor;
            face.data.solidColor.v[0] = 1.0;
            face.data.solidColor.v[1] = 1.0;
            face.data.solidColor.v[2] = 1.0;
          }
          else
          {
            assert(0, "expected either \"mat\" or \"remote\"");
          }

          enforce(words[4] == "vdata", "expected vdata");
          size_t n = to!size_t(words[5]);
          version (debugEscherFiles)
            writefln("face has %d indices", n);

          const size_t dataSize = 6;

          face.indices.reserve(n);
          face.UVs.reserve(n);
          foreach (i; 0..n)
          {
            version (debugEscherFiles)
              writefln("  processing face vertex %d/%d: %s", i, n, words[6+i*dataSize]);
            face.indices ~= to!size_t(words[6+i*dataSize]);
            face.UVs ~= vec2(to!double(words[7+i*dataSize]), to!double(words[8+i*dataSize]));
            face.normals ~= vec3(to!double(words[ 9+i*dataSize]),
                                 to!double(words[10+i*dataSize]),
                                 to!double(words[11+i*dataSize]));
          }

          space.faces ~= face;

          if (space.faces.length == numFaces)
            mode = ParserMode.expectSpace;
          break;

        default:
          assert(0, "internal error 0");
      }
    }

    /* Organizes ordinary visible faces in each space by their material ID */
    foreach (spacei; spaces)
      sort!compareFacesByRenderType(spacei.faces);

    //foreach (spacei; spaces)
      //foreach (face; spacei.faces)
        //writeln(face);

    /* 'entities' is an array of arrays. The first key is the spaceID. The second key is sequential
     * otherwise and meaningless.
     */
    entities.length = spaces.length;

    /* Now we will visit spawners TODO This should happen per-Space, and it should set a timeout or
     * something for the next time this is allowed to happen, which should be based on visibility
     * of the space, which means that when we render Spaces, we should mark them with a timestamp
     * of the last time they were rendered...? Needs some thought...
     */
    foreach (spacei, spaceb; spaces)
      foreach (spawn; spaceb.spawns)
        entities[spacei] ~= spawn();

    version (debugEscherFiles)
    {
      writeln("ESCHER WORLD LOADED");
      writeln(spaces);
    }
  }

  ~this()
  {
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
  mat4 pmatWorld = mat4.perspective(800, 600, 90, 0.1, 10000);
  //XXX ShaderProgram shaderProgram;

  bool drawMapVertices;
  bool drawMapNormals;

  void drawSpace(int spaceID, mat4 transform, ubyte portalDepth, int dmode)
  {
    Space space = spaces[spaceID];

    /* First we'll draw solid faces. This requires a stencil test, but does not
     * draw to the stencil.
     */
    version (stencil) {
      glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
      glDepthMask(GL_TRUE);
      glStencilMask(0);
      glStencilFunc(GL_EQUAL, portalDepth, 0xFF);
      glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE);
    }
    
    // Draw some triangles
    int lastMaterialID = -1;
    foreach (faceID, face; space.faces)
    {
      // TODO faces are sorted, so this could be changed..
      if (face.data.type != FaceType.SolidColor)
        continue;

      drawFace(space, face, transform, pmatWorld);
      if (lastMaterialID > 0 && lastMaterialID != face.data.solidColor.materialID)
        vertexer.draw(shaderProgram, transform, pmatWorld, materials[lastMaterialID]);
      lastMaterialID = face.data.solidColor.materialID;
    }
    vertexer.draw(shaderProgram, transform, pmatWorld, materials[lastMaterialID]);

    /* Now we'll draw our entities.
     */
    foreach (entity; entities[spaceID])
    {
      entity.draw(transform, pmatWorld);
    }


    if (portalDiagnosticMode)
    {
      foreach (faceID, face; space.faces)
      {
        if (face.data.type == FaceType.Remote)
          drawFace(space, face, transform, pmatPortal);
      }
      vertexer.draw(portalDiagnosticProgram, transform, pmatPortal, null);
    }
    else
    {
      /* Now we'll draw remote spaces. This requires identifying visible faces which are
       * connected to each remote space, and drawing them onto the stencil buffer. Then
       * we can render the remote face through this stencil. When rendering of the remote
       * space is done, we'll "undraw" the stencil we drew. We still respect the previous
       * stencil rules when we make this draw.
       */
      if (portalDepth > 0)
      foreach (remoteID, remote; space.remotes)
      {
        version (stencil) {
          glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
          glDepthMask(GL_FALSE);
          glStencilMask(0xFF);
          glStencilFunc(GL_EQUAL, portalDepth, 0xFF);
          glStencilOp(GL_KEEP, GL_KEEP, GL_DECR);
        }

        bool drawRemote = false;
        // Draw some triangles
        foreach (faceID, face; space.faces)
        {
          if (face.data.type != FaceType.Remote || face.data.remote.remoteID != remoteID)
            continue;
          if (drawFace(space, face, transform, pmatPortal))
            drawRemote = true;
        }
        vertexer.draw(shaderProgram, transform, pmatPortal, null);

        /* We'll draw the remote space now, but only if one of the remote faces to this
         * remote was visible.
         */
        if (!drawRemote)
          continue;

        drawSpace(
            remote.spaceID,
            transform * spaces[spaceID].remotes[remoteID].transform,
            cast(ubyte)(portalDepth-1),
            dmode);

        /* Now we must undraw the stencils we drew for this remote
         */
        version (stencil) {
          glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
          glDepthMask(GL_FALSE);
          glStencilMask(0xFF);
          glStencilFunc(GL_LEQUAL, portalDepth-1, 0xFF);
          glStencilOp(GL_KEEP, GL_KEEP, GL_INCR);
        }
        // Draw some triangles
        foreach (faceID, face; space.faces)
        {
          if (face.data.type != FaceType.Remote && face.data.remote.remoteID != remoteID)
            continue;
          if (drawFace(space, face, transform, pmatPortal))
            drawRemote = true;
        }
        vertexer.draw(shaderProgram, transform, pmatPortal, null);
      }

      version (stencil) {
        glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
        glDepthMask(GL_TRUE);
        glStencilMask(0);
        glStencilFunc(GL_EQUAL, portalDepth, 0xFF);
        glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE);
      }
    }

    /* Draw diagnosic shit */
    if (drawMapVertices)
    {
      glDisable(GL_DEPTH_TEST);
      ColorVec color = ColorVec(0, 1, 0);
      foreach (faceID, face; space.faces)
      {
        foreach (i, vi; face.indices)
        {
          vertexer.add(space.verts[vi], vec2(0,0), face.normals[i], color);
        }

        vertexer.draw(portalDiagnosticProgram, transform, pmatPortal, materials[0], GL_LINE_LOOP);
      }
      glEnable(GL_DEPTH_TEST);
    }
    if (drawMapNormals)
    {
      glDisable(GL_DEPTH_TEST);
      ColorVec color = ColorVec(0, 1, 1);
      foreach (faceID, face; space.faces)
      {
        foreach (i, vi; face.indices)
        {
          vertexer.add(space.verts[vi], vec2(0,0), vec3(0,0,0), color);
          vertexer.add(space.verts[vi] + face.normals[i], vec2(0,0), vec3(0,0,0), color);
        }

        vertexer.draw(portalDiagnosticProgram, transform, pmatPortal, materials[0], GL_LINES);
      }
      glEnable(GL_DEPTH_TEST);
    }
  }
}

EntityPlayer playerEntity;
ShaderProgram shaderProgram;
ShaderProgram portalDiagnosticProgram;

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

mat4 orientMat4(mat3 m)
{
  return mat4(
    m.matrix[0][0], m.matrix[0][1], m.matrix[0][2], 0,
    m.matrix[1][0], m.matrix[1][1], m.matrix[1][2], 0,
    m.matrix[2][0], m.matrix[2][1], m.matrix[2][2], 0,
    0, 0, 0, 1
  );
}

mat3 mat3orientation(mat4 m)
{
  return mat3(
    m.matrix[0][0], m.matrix[0][1], m.matrix[0][2],
    m.matrix[1][0], m.matrix[1][1], m.matrix[1][2],
    m.matrix[2][0], m.matrix[2][1], m.matrix[2][2]
  );
}

vec3 vec3translation(mat4 m)
{
  return vec3(
    m.matrix[0][3],
    m.matrix[1][3],
    m.matrix[2][3]
  );
}

/* Weapons */
enum Weap {
  None,
  Gun
};
MD5Model playerModel;
MD5Animation playerAnimation;

class Camera
{
  World world;
  int spaceID;
  vec3 pos;
  double camYaw;
  double camPitch;

  float turnRate;

  bool keyForward;
  bool keyBackward;
  bool keyLeft;
  bool keyRight;
  bool keyUp;
  bool keyDown;

  this(World world, int spaceID, vec3 pos)
  {
    this.world = world;
    this.spaceID = spaceID;
    this.pos = pos;
    this.turnRate = 0f;
    this.camYaw = 0.0;
    this.camPitch = 0.0;
    this.vel = vec3(0,0,0);
    this.grounded = true; // TODO for debugging no falling until jump
  }

  void key(int keysym, bool down)
  {
    switch (keysym)
    {
      case 's':
        keyForward = down;
        break;

      case 'w':
        keyBackward = down;
        break;

      case 'a':
        keyLeft = down;
        break;
      
      case 'd':
        keyRight = down;
        break;

      case ' ':
        keyUp = down;
        break;

      case 'c':
        keyDown = down;
        break;

      case 'm':
        if (down)
          portalDiagnosticMode = ! portalDiagnosticMode;
        break;

      case 'v':
        if (down)
          world.drawMapVertices = ! world.drawMapVertices;
        break;

      case 'n':
        if (down)
          world.drawMapNormals = ! world.drawMapNormals;
        break;

      case 'l':
        if (down)
          vertexer.lightPos = vec3f(this.pos.x, this.pos.y, this.pos.z);
        break;

      /*case '0':
        if (down)
        {
          auto e = new EntitySpikey(spaceID, pos);
          world.entities[spaceID] ~= e;
          writefln("[entity] dropped spikey!");
        }
        break;*/

      default:
        break;
    }
  }

  bool noclip;
  bool fly;
  bool grounded;
  vec3 vel;
  void update(ulong delta)
  {
    vec3 accel;
    const double EPSILON = 0.000001;
    const double speed = 10.0;
    const double startSpeed = 0.08;
    const double jumpVel = 25.0;
    const double mass = 1.0;
    float deltaf = delta/10_000_000f;

    // Remember old position for intersection tests
    vec3 oldpos = pos;

    // Keep orientation inside 0-2pi
    while (camYaw < 0.0)
      camYaw += PI*2f;
    while (camYaw >= PI*2f)
      camYaw -= PI*2f;

    /* Calculate a rotation matrix for WASD keys */
    mat2 wasdMat = mat2(
      cos(camYaw),  sin(camYaw),
      -sin(camYaw), cos(camYaw));
    mat2 wasdMatInv = mat2(
      cos(-camYaw),  sin(-camYaw),
      -sin(-camYaw), cos(-camYaw));

    /* Calculate WASD vector representing the movement implied by WASD keys */
    vec2 wasdVec  = vec2(
      keyRight   == keyLeft     ? 0 :
      keyRight   ? 1 : -1,
      keyForward == keyBackward ? 0 :
      keyForward ? 1 : -1) * speed;

    if (fly)
    {
      wasdVec = wasdMat * wasdVec;
      vel = vec3(
        wasdVec.x,
        keyUp == keyDown ? 0 : keyUp ? 23 : -23,
        wasdVec.y);
    }
    else
    {
      /* We'll mix previous WASD velocity with new WASD velocity based on a "friction"
       * coefficient. First calculate that coefficient. */
      double frictionCoef = (grounded ? 12.99 : 5.0) * deltaf;
      double frictionCoefY = frictionCoef * 0.2;

      /* Calculate previous velocity in camYaw space */
      vec2 oldWasdVec = wasdMatInv * vec2(vel.xz);

      /* Mix WASD velocity with previous velocity, giving more influence to
       * forward/backward movement than left/right movement.
       */
      vec2 totalWasdVec = vec2(
        oldWasdVec.x * (1.0-frictionCoefY) + wasdVec.x * frictionCoefY,
        oldWasdVec.y * (1.0-frictionCoef ) + wasdVec.y * frictionCoef );

      /* Apply slow-down friction */
      if (grounded)
      {
        const double slowdown = 0.001;
        auto mag = totalWasdVec.magnitude;
        if (mag < slowdown)
          totalWasdVec = vec2(0, 0);
        else
          totalWasdVec *= 1.0 - slowdown/mag;
      }

      /* Rotate by camYaw matrix to gain our final velocity vector */
      vec2 vel2 = wasdMat * totalWasdVec;

      vel.x = vel2.x;
      vel.z = vel2.y;

      /* Apply gravity */
      if (grounded && keyUp) { grounded=false; vel.y = jumpVel; }
      else vel.y = vel.y - 50.0 * deltaf;
    }

    pos += vel * deltaf;

    if (noclip)
      return;

    if (portalDiagnosticMode)
      return;

    vec3 movement = pos - oldpos;
    vec3 orient = vec3(sin(camYaw), 0, cos(camYaw));

    /* Intersect space faces */
    if (oldpos != pos && !noclip)
    {
      /* Profile collision code */
      StopWatch stopWatch;
      stopWatch.start();

      bool landed;

      //writeln("movement.length = ", movement.length, " but also = ", (pos-oldpos).length);
      Space space = world.spaces[spaceID];

      /* Collide with solid Space Faces */
      foreach (faceIndex, face; space.faces)
      {
        if (face.data.type == FaceType.SolidColor)
        {
          /* Grab the three points making up the map face */
          vec3[3] fv;
          fv[0] = space.verts[face.indices[0]];
          fv[1] = space.verts[face.indices[1]];
          fv[2] = space.verts[face.indices[2]];

          /* Calculate normal of plane containing map face*/
          vec3 n = cross(
              (fv[2] - fv[0]).normalized,
              (fv[1] - fv[2]).normalized).normalized;

          /* For the purposes of using the following shitty "passThruTest" code, I'm going to
           * use a hitsphere and the point on it nearest the plane of the wall triangle
           * instead of the center of the hitsphere.
           *
           * The relevant point on the hitsphere is calculated using the planar normal times
           * the negation of the hitsphere radius.
           */
          /*const float hitSphereRadius = 0.25;
          const float hitSphereScaleY = 1.0;
          vec3 hitSphereDelta = n * vec3(hitSphereRadius, hitSphereScaleY+hitSphereRadius, hitSphereRadius),
               hitSphereStartPos = oldpos + hitSphereDelta,
               hitSphereEndPos = pos + hitSphereDelta;*/
          const float hitSphereRadius = 0.25;
          vec3 hitSphereDelta = hitSphereRadius * n,
               hitSphereStartPos = oldpos + hitSphereDelta,
               hitSphereEndPos = pos + hitSphereDelta;

          /* Has the hitpoint passed through this triangle in this space face? */
          bool hit =
            face.indices.length == 3 &&
            passThruTest(hitSphereStartPos, movement.normalized, fv[0], fv[1], fv[2], movement.length);

          if (!hit)
          {
            //writefln("@@ attempting segment-sphere intersection___________");

            /* We have determined that the motion of the "hitpoint" on the hitsphere has not
             * intersected the wall. We'll now test for the sphere intersecting with the edge.
             * TODO investigate better ways?
             */

            foreach (si0; 0..3)
            {
              /* Reference:
               * http://portal.ku.edu.tr/~cbasdogan/Courses/Robotics/projects/IntersectionLineSphere.pdf
               * (Last section titled "Line Segment")
               */
              auto si1 = (si0==2)?0:si0+1;

              vec3 p1 = fv[si0];
              vec3 p2 = fv[si1];
              vec3 p3 = pos;

              vec3 p2_p1 = p2-p1;
              float u = dot(p3-p1, p2_p1) / p2_p1.magnitude_squared;

              //writefln("@@ attempting segment-sphere intersection: %f", u);
              if (u >= 0 && u <= 1)
              {
                //writeln("@@ WINRAR WINRAR WINRAR WINRAR WINRAR WIN: ^^^^^^^");
                /* Find the exact position of the point */
                vec3 p = lerp(p1, p2, u);
                vec3 dp = p - p3;
                if (dp.magnitude_squared < hitSphereRadius * hitSphereRadius)
                {
                  //writeln("@@ segment-sphere hit!");

                  /* TODO The pseudo-plane technique accelerates your movement around a bend.
                   *      This is undesirable and should be addressed!
                   */

                  /* Calculate the pseudo-plane normal by subtracting 'p' from 'pos.' */
                  vec3 pseudon = (pos - p).normalized;

                  //writeln("@@ pseudo normal: ", n);

                  /* Solve planar equation for 'd' of plane containing the edge we hit */
                  float p0d = -dot(p, n);

                  //writeln("@@   wall plane 0 d = ", p0d);

                  /* Solve planar equation for 'd' of plane p1 */
                  float p1d = -dot(n, hitSphereEndPos);
                  //writeln("@@   wall plane 1 d = ", p1d);

                  /* Compute new position projected onto the plane containing map face */
                  pos = pos + (p1d-p0d) * 1.01 * n;
                  //writeln("@@   wall nudge: ", n * (p1d-p0d));

                  /* Check for floor or ceiling */
                  //if (dot(vec3(0,1,0), n.normalized) < 0.5)
                    //landed = true;
                  break;
                }
              }
            }
          }

          else
          {
            /* The hitpoint on the hitsphere has traveled through the wall. */

            //writefln("@@ Colliding with a wall");
            /* Either the hitpoint on the hitsphere has traveled through the wall or we have
             * created a pseudo-plane through which the hitpoint has traveled.
             *
             * Since we are running into a wall, we want to project our presumed destination
             * point onto the plane of the wall we are running into.
             *
             * To do this, we first solve for 'd' in the planar equation ax+by+cz+d=0
             * for a new plane that is parallel to the plane we are projecting onto, and in
             * which the hitpoint is located.
             *
             * Parallel planes have the same planar normal, and the planar normal's
             * components are equal to the coefficients 'a' 'b' and 'c' in the planar
             * equation. The only difference is 'd'.
             *
             * To calculate a new plane parallel to the first, we solve for 'd' when
             * using the known planar normal and assumed point on the new plane.
             *
             * The difference in d from the plane we wish to project onto and the new
             * plane containing our point is the coefficient f for the translation
             * v' = v * n * f
             */

            //writeln("@@   wall normal: ", n);

            /* Solve planar equation for 'd' of plane containing map face */
            float p0d = -dot(fv[0], n);

            //writeln("@@   wall plane 0 d = ", p0d);

            /* Solve planar equation for 'd' of plane p1 */
            float p1d = -dot(n, hitSphereEndPos);
            //writeln("@@   wall plane 1 d = ", p1d);

            /* Compute new position projected onto the plane containing map face */
            pos = pos + (p1d-p0d) * 1.01 * n;
            //writeln("@@   wall nudge: ", n * (p1d-p0d));

            /* Check for floor */
            auto f = dot(vec3(0,-1,0), n.normalized);
            //writeln("@@ f: ", f);
            if (f > 0.5)
              landed = true;
            //else
              //writeln("@@   wall!ceiling");
          }
        }

        /* Recalculate movement vector */
        movement = pos - oldpos;
      }

      foreach (faceIndex, face; space.faces)
      {
        /* Copied and pasted from above, lol XXX */

        /* Grab the three points making up the map face */
        vec3[3] fv;
        fv[0] = space.verts[face.indices[0]];
        fv[1] = space.verts[face.indices[1]];
        fv[2] = space.verts[face.indices[2]];

        /* Calculate normal of plane containing map face*/
        vec3 n = cross(
            (fv[2] - fv[0]).normalized,
            (fv[1] - fv[2]).normalized).normalized;

        int tris = 0;
        /* TODO support arbitrary polygon faces */
        /* TODO XXX i have inverted pos and oldpos here because it fixes some polarity problem
         *          SOMEWHERE but i have no idea where. For now I will leave it like this but
         *          this problem needs to be solved!
         */
        if (face.indices.length == 4 && passThruTest(oldpos, movement.normalized, space.verts[face.indices[0]], space.verts[face.indices[1]], space.verts[face.indices[3]], movement.length))
        {
          tris += 1;
        }
        if (face.indices.length == 4 && passThruTest(oldpos, movement.normalized, space.verts[face.indices[2]], space.verts[face.indices[3]], space.verts[face.indices[1]], movement.length))
        {
          tris += 10;
        }
        if (face.indices.length == 3 && passThruTest(oldpos, movement.normalized, space.verts[face.indices[0]], space.verts[face.indices[1]], space.verts[face.indices[2]], movement.length))
        {
          tris += 1;
        }

        if (tris)
        {
          //writefln("intersected face %d", faceIndex);
          if (face.data.type == FaceType.Remote && face.data.remote.remoteID >= 0)
          {
            writefln("trying to crash spaceID=%d remoteID=%d num space remotes=%d",
              spaceID, face.data.remote.remoteID, space.remotes.length);

            Remote remote = world.spaces[spaceID].remotes[face.data.remote.remoteID];
            if (FaceType.Remote && remote.spaceID >= 0)
            {
              // Move to the space we're entering
              spaceID = remote.spaceID;

              /* Scene coordinates are now relative to the space we've entered.
               * We must adjust our own coordinates so that we enter the space
               * at the correct position. We also need to adjust our orientation.
               */
              vec4 preTransformPos4 = vec4(this.pos.x, this.pos.y, this.pos.z, 1f);
              vec4 pos = preTransformPos4 * remote.untransform;
              pos.x = pos.x / pos.w;
              pos.y = pos.y / pos.w;
              pos.z = pos.z / pos.w;
              this.pos.x = pos.x;
              this.pos.y = pos.y;
              this.pos.z = pos.z;

              vec4 lookPos = vec4(orient.x, orient.y, orient.z, 0f) + preTransformPos4;
              //writeln("old  vec: ", oldpos);
              //writeln("look vec: ", lookPos);
              lookPos = lookPos * remote.untransform;
              //writeln("new  vec: ", lookPos);
              lookPos.x = lookPos.x / lookPos.w;
              lookPos.y = lookPos.y / lookPos.w;
              lookPos.z = lookPos.z / lookPos.w;
              //writeln("/w   vec: ", lookPos);
              lookPos = lookPos - pos;
              //writeln("-op  vec: ", lookPos);
              //writeln("transform: ", remote.transform);
              //writefln("camYaw: %f", camYaw);
              camYaw = atan2(lookPos.x, lookPos.z);
              //writefln("camYaw: %f new", camYaw);

              //writefln("entered space %d", spaceID);
              break;
            }
          }
        }
      }

      if (landed)
      {
        //writeln("@@ landed");
        grounded = true;
        vel.vector[1] = 0;
      }

      stopWatch.stop();
      profileCollision = stopWatch.peek.to!("msecs", float)();
    }

    // XXX shitty way to move entities into a new space so that they can be found by-space
    if (playerEntity.spaceID != spaceID)
    {
      auto entities = world.entities[playerEntity.spaceID];
      foreach (i, e; entities)
      {
        if (e is playerEntity)
        {
          if (i < entities.length-1)
            entities[i] = entities[$-1];
          --entities.length;
          break;
        }
      }

      playerEntity.spaceID = spaceID;
      world.entities[spaceID] ~= playerEntity;
    }

    /* Update entities TODO currently I just do this in the current space */
    foreach (e; world.entities[spaceID])
      e.update(deltaf);

    playerEntity.pos = pos;
    playerEntity.angle = camYaw;
  }

  bool noBody;
  int frame = 0;
  float profileDrawWorld;
  float profileDrawArms;
  float profileCollision;
  void draw(ulong t)
  {
    vertexer.setFrameTime(t/10_000_000.0);
    ubyte portalDepth = 2;

    if (shaderProgram is null)
    {
      portalDiagnosticProgram = new ShaderProgram("simple-red.vs", "simple-red.fs");
      shaderProgram = new ShaderProgram("simpler.vs", "simpler.fs");
      playerModel = new MD5Model("res/md5/arms-run.md5mesh");
      playerAnimation = new MD5Animation(playerModel, "res/md5/arms-run.md5anim");
      vertexer.setResolution(800, 600);
    }
    if (vertexer is null)
    {
      vertexer = new Vertexer();
    }

    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);

    glDepthMask(GL_TRUE);
    glClearDepth(1);
    glClear(GL_DEPTH_BUFFER_BIT);

    version (stencil) {
      glStencilMask(255);
      glClearStencil(portalDepth);
      glClear(GL_STENCIL_BUFFER_BIT);
    }

    glDepthFunc(GL_LESS);

    version (lighting) {
      glEnable(GL_LIGHTING);
      glEnable(GL_LIGHT0);
    }

    glEnable(GL_DEPTH_TEST);
    version (stencil) glEnable(GL_STENCIL_TEST);

    mat4 mvmat = mat4.identity
      * mat4.rotation(camPitch, vec3(1,0,0))
      * mat4.rotation(camYaw, vec3(0,1,0))
      * mat4.translation(-pos.x, -pos.y, -pos.z);

    glDisable(GL_BLEND);
    glEnable(GL_DEPTH_TEST);

    /* Profile world draw code */
    StopWatch stopWatch;
    stopWatch.start();

    glErrorCheck("before drawSpace()");
    world.drawSpace(spaceID, mvmat, portalDepth, 0);
    glErrorCheck("after drawSpace()");

    stopWatch.stop();
    profileDrawWorld = stopWatch.peek.to!("msecs", float);

    if (noBody)
    {
      profileDrawArms = 0;
      return;
    }

    stopWatch.reset();
    stopWatch.start();

    mat4 playerMat = mat4.identity
      .rotate(PI*0.5, vec3(1,0,0))
      .rotate(PI, vec3(0,1,0))
      .translate(-3, 1, 2)
      .scale(1.0/24, 1.0/24, 1.0/24)
      ;
    glClear(GL_DEPTH_BUFFER_BIT);
    mat4 pmatPlayer = mat4.perspective(800, 600, 90, 0.000001, 10);
    playerAnimation.draw(playerMat, pmatPlayer);
    frame++;

    stopWatch.stop();
    profileDrawArms = stopWatch.peek.to!("msecs", float)();
  }
}
