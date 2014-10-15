module ants.calcbsp;
import std.algorithm : uniq, max;
import std.array : array;
import ants.escher;
import ants.util;

private enum EPSILON = 0.00001;

private struct Plane
{
  /* Planar equation ax + by + cz + d = 0 */
  vec3 n;
  double d;

  /* Is this plane degenerate? */
  bool degenerate;
}
private struct Triangle
{
  size_t iFace;
  size_t iVerts[3];
}

void calcBSP(Space space)
{
  /* Calculate all planes of all faces in space */
  Plane[] planes;
  planes.length = space.faces.length;
  foreach (iFace, face; space.faces)
  {
    //assert(face.indices.length == 3); // XXX temporary! until more thoughts i guess!
    planes[iFace].n = cross(space.verts[face.indices[0]] - space.verts[face.indices[1]],
                            space.verts[face.indices[0]] - space.verts[face.indices[2]]).normalized;
    if (planes[iFace].n.magnitude_squared < EPSILON)
      planes[iFace].degenerate = true;
    planes[iFace].d = dot(planes[iFace].n, space.verts[face.indices[0]]);
  }

  /* Triangulate all faces */
  size_t iTri;
  foreach (face; space.faces)
    iTri += face.indices.length - 2;

  Triangle[] triangles;
  triangles.length = iTri;
  iTri = 0;
  foreach (iFace, face; space.faces)
  {
    foreach (iVert; face.indices[2..$])
    {
      triangles[iTri].iFace = iFace;
      triangles[iTri].iVerts[0] = face.indices[0];
      triangles[iTri].iVerts[1] = face.indices[1];
      triangles[iTri].iVerts[2] = iVert;
    }
  }

  uint indentation;
  void trace(Char, A...)(in Char[] fmt, A args)
  {
    for (size_t i = 0, j = indentation * 2; i < j; i++)
      write(' ');
    writefln(fmt, args);
  }

  /* Begin partitioning */
  void partition(size_t[] remainingFaces)
  {
    indentation++;
    scope(exit) --indentation;
    trace("partitioning %d faces", remainingFaces.length);
    
    /* Score all remaining planes */
    auto bestScore = ptrdiff_t.max;
    auto iBestPlane = size_t.max;
    //foreach (iPlane, plane; planes)
    foreach (iPlane; remainingFaces)
    {
      auto plane = planes[iPlane];
      /* Score plane as a partition */
      /* Each face in the set of faces we're currently partitioning must
       * be compared against this plane.
       */
      size_t scoreCats[3];
      foreach (iFace; remainingFaces)
      {
        auto face = space.faces[iFace];
        /* Each vertex in the face must be checked */
        byte sign;
        foreach (iVert; face.indices)
        {
          /* Project vertex onto planar normal */
          double d = plane.d - dot(plane.n, space.verts[iVert]);
          /* Determine to which side of our plane the vetex lies */
          if (d < -EPSILON)
          {
            if (sign == 1)
            {
              sign = 0;
              break;
            }
            sign = -1;
          }
          else if (d > EPSILON)
          {
            if (sign == -1)
            {
              sign = 0;
              break;
            }
            sign = 1;
          }
        }
        /* Result obtained: 'sign' will be either:
         * -1     entire face is <= our plane
         * +1     entire face is >= our plane
         *  0     face is either coplanar with our plane, or bisected by our plane
         */
        scoreCats[sign+1]++;
      }
      /* Final partitioning score for the plane is the greater of two sums */
      ptrdiff_t score = max(scoreCats[0] + scoreCats[1], scoreCats[1] + scoreCats[2]);
      /* Did we score better (lower) than the previous best? */
      if (score < bestScore)
      {
        bestScore = score;
        iBestPlane = iPlane;
      }
    }
    /* We now have chosen our best partitioning plane.
     * Now we'll have to reevaluate all our space's faces, splitting them into
     * two groups, and recursing into any group that is non-empty.
     */
    auto bestPlane = planes[iBestPlane];
    size_t[][2] groups;
    foreach (iFace; remainingFaces)
    {
      auto face = space.faces[iFace];
      /* Each vertex in the face must be checked */
      byte sign;
      foreach (iVert; face.indices)
      {
        /* Project vertex onto planar normal */
        double d = bestPlane.d - dot(bestPlane.n, space.verts[iVert]);
        /* Determine to which side of our plane the vetex lies */
        if (d < -EPSILON)
        {
          if (sign == 1)
          {
            groups[0] ~= iFace;
            groups[1] ~= iFace;
            break;
          }
          sign = -1;
        }
        else if (d > EPSILON)
        {
          if (sign == -1)
          {
            groups[0] ~= iFace;
            groups[1] ~= iFace;
            break;
          }
          sign = 1;
        }
      }
      if (sign == -1)
        groups[0] ~= iFace;
      if (sign ==  1)
        groups[1] ~= iFace;
    }
    /* Now recurse into either non-empty group */
    if (groups[0].length != 0)
      partition(groups[0]);
    if (groups[1].length != 0)
      partition(groups[1]);
  }
  
  /* Make a list of all faces' indices */
  size_t[] iAllFaces;
  foreach (iPlane, plane; planes)
  {
    if (plane.degenerate)
      continue;
    iAllFaces ~= iPlane;
  }
  partition(iAllFaces);
}
