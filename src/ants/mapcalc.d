module ants.mapcalc;
import std.algorithm : uniq;
import std.array : array;
import ants.escher;
import ants.util;

private enum FLAG_HULL = 1;
private enum EPSILON = 0.00001;
private struct Plane { vec3 n; double d; }

struct OBB
{
  mat3 orientation;
  vec3 dimensions;
  /* verts are expressed in "Space"-space */
  vec3[8] verts;
}

size_t[] vertsFoundInHull;
ubyte[] vertFlags;

vec3[8] obbVerts;

vec3[] calcHull(vec3[] V, int numAngles)
{
  assert(V.length > 3);
  vertsFoundInHull.length = 0;
  vertFlags.length = 0;
  vertFlags.length = V.length;

  foreach (i; 0..V.length)
  {
    foreach (j; i+1..V.length)
    {
      tryAPlane:
      foreach (k; j+1..V.length)
      {
        /* Solve planar equation for three vertices, starting with the planar normal */
        vec3 n = cross(V[i] - V[j], V[i] - V[k]);
        /* If the three vertices we've chosen construct a degenerate triangle, we cannot use
         * them to construct a plane. I *think* in this case our normal will be the zero
         * vector.
         */
        if (-EPSILON <= n.x && n.x <= EPSILON
        &&  -EPSILON <= n.y && n.y <= EPSILON
        &&  -EPSILON <= n.z && n.z <= EPSILON)
        {
          //writeln("Rejecting degenerate plane");
          continue tryAPlane;
        }
        /* Find 'd' of planar equation by projecting one point of plane onto planar normal */
        double d = dot(V[i], n);
        //writeln("New Plane");
        //writefln("Vertex indices: %d %d %d", i, j, k);
        //writefln("Vertexes: %s %s %s", V[i], V[j], V[k]);
        //writefln("Planar equation: %sx + %sy + %sz + %s = 0", n.x, n.y, n.z, d);
        /* Compare all other vertices against this plane. If we find any point that lies to
         * one side of the plane, and then any other point that lies to the opposite side of
         * the plane, then this plane bisects our 'V', rather than bounds it.
         */
        byte sign;
        foreach (l; 0..V.length)
        {
          /* We know these three points lie in our plane already. */
          if (l == i || l == j || l == k)
          {
            continue;
          }
          /* Calculate signed distance of point from plane by projecting point onto planar
           * normal, then calculating the difference from 'd' of planar equation.
           */
          double t = d - dot(V[l], n);
          //writeln("  New Vertex");
          //writefln("    index %d", l);
          //writefln("    coords: %s", V[l]);
          //writefln("    planar distance: %s", t);
          /* Test point vs. plane */
          byte sign1;
          if (t < -EPSILON)
            sign1 = -1;
          else if (t > EPSILON)
            sign1 =  1;
          else
          {
            /* planar coincidence */
            //vertsFoundInHull ~= l;
            //writeln("    planar coincidence");
            //writeln("    vertex passed");
            continue; 
          }
          //writefln("    planar sign: %s", sign1);
          /* No planar coincidence. Compare against previous findings */
          if (sign == 0)
            sign = sign1;
          else if (sign != sign1)
          {
            /* Give up on this plane! It bisects 'V'!
             * First, erase any vertices we added to our hull in the process of examining
             * this plane.
             */
            //writeln("    vertex failure");
            //writeln("  planar failure");
            /* Then exit the foreach 'k' loop, to try a new plane. */
            continue tryAPlane;
          }
          //writeln("    vertex passed");
          //vertsFoundInHull ~= l;
        }
        //writeln("  Planar Success");
        /* All vertices have been tested against this plane. If 'sign' is 0, then V is
         * degenerate (all vertices coplanar,) and we should bail I guess. Otherwise,
         * we should catalogue this plane!
         */
        if (sign == 0)
        {
          writeln("  calcHull() found degenerate hull (all vertices coplanar)");
          //foreach (vi, v; V)
            //writefln("vert #%d = %s", vi, v);
          return null;
        }

        vertFlags[i] |= FLAG_HULL;
        vertFlags[j] |= FLAG_HULL;
        vertFlags[k] |= FLAG_HULL;
      }
    }
  }

  foreach (vi, flags; vertFlags)
    if ((flags & FLAG_HULL) != 0)
      vertsFoundInHull ~= vi;

  foreach (vi; uniq(vertsFoundInHull))
  {
    writeln(vi, ' ', V[vi]);
  }
  writefln("From %d verts, %d hull verts", V.length, vertsFoundInHull.length);

  /* Now we'll try a bunch of different orientations and just the smallest box. */

  /* First identify one axis among numAngles^3 axes, which are evenly distributed
   * by angle around the three axes. TODO identify another distribution? This one
   * 
   * TODO some of these rotations are redundant! fix that!
   */
  vec3 bestXAxis;
  double bestXLength = double.max;
  double bestXLow, bestXHigh;
  for (int iz = 0; iz < numAngles; iz++)
  {
    mat3 rz = mat3.rotation(PI/(numAngles+1)*iz, vec3(0, 0, 1));
    for (int iy = 0; iy < numAngles; iy++)
    {
      mat3 ryz = rz * mat3.rotation(PI/(numAngles+1)*iy, vec3(0, 1, 0));
      for (int ix = 0; ix < numAngles; ix++)
      {
        mat3 rxyz = ryz * mat3.rotation(PI/(numAngles+1)*ix, vec3(1, 0, 0));
        vec3 axis = vec3(0, 0, 1) * rxyz;
        //writefln("axis: mag=%s vec=%s", axis.magnitude, axis);
        /* Now evaluate this axis */
        double aMin = double.max;
        double aMax = double.min;
        foreach (vi; vertsFoundInHull)
        {
          auto va = dot(V[vi], axis);
          if (va < aMin) aMin = va;
          if (va > aMax) aMax = va;
        }
        double dev = aMax - aMin;
        if (dev < bestXLength)
        {
          bestXLength = dev;
          bestXAxis = axis;
          bestXLow = aMin;
          bestXHigh = aMax;
        }
      }
    }
  }

  writefln("best axis %s has deviation of %s", bestXAxis, bestXLength);

  /* Now that we have one really good axis, we'll examine the other two axes,
   * and find the orientation that gives our box the best volume.
   */
  vec3 bestYAxis, bestZAxis;
  double bestYZArea = double.max;
  double bestYLow, bestYHigh, bestZLow, bestZHigh;
  /* Calculate two complimentary orthogonal axes */
  vec3 someAxis = bestXAxis.anyPerpendicularVec.normalized;
  for (int iAngle = 0; iAngle < numAngles; iAngle++)
  {
    vec3 yAxis = someAxis * mat3.rotation(PI/(numAngles+1)*iAngle, bestXAxis);
    vec3 zAxis = cross(bestXAxis, yAxis).normalized;
    double yMin = double.max;
    double yMax = double.min;
    double zMin = double.max;
    double zMax = double.min;
    foreach (vi; vertsFoundInHull)
    {
      auto vya = dot(V[vi], yAxis);
      if (vya < yMin) yMin = vya;
      if (vya > yMax) yMax = vya;
      auto vza = dot(V[vi], zAxis);
      if (vza < zMin) zMin = vza;
      if (vza > zMax) zMax = vza;
    }
    auto yzArea = (yMax - yMin) * (zMax - zMin);
    if (yzArea < bestYZArea)
    {
      bestYZArea = yzArea;
      bestYAxis = yAxis;
      bestZAxis = zAxis;
      bestYLow = yMin;
      bestYHigh = yMax;
      bestZLow = zMin;
      bestZHigh = zMax;
    }
  }

  auto orientation = mat3(
    bestXAxis.x, bestXAxis.y, bestXAxis.z,
    bestYAxis.x, bestYAxis.y, bestYAxis.z,
    bestZAxis.x, bestZAxis.y, bestZAxis.z
  );
  orientation.invert;

  obbVerts[0] = vec3(bestXLow , bestYLow , bestZLow ) * orientation;
  obbVerts[1] = vec3(bestXHigh, bestYLow , bestZLow ) * orientation;
  obbVerts[2] = vec3(bestXLow , bestYHigh, bestZLow ) * orientation;
  obbVerts[3] = vec3(bestXHigh, bestYHigh, bestZLow ) * orientation;
  obbVerts[4] = vec3(bestXLow , bestYLow , bestZHigh) * orientation;
  obbVerts[5] = vec3(bestXHigh, bestYLow , bestZHigh) * orientation;
  obbVerts[6] = vec3(bestXLow , bestYHigh, bestZHigh) * orientation;
  obbVerts[7] = vec3(bestXHigh, bestYHigh, bestZHigh) * orientation;

  writefln("best orthonormal basis:
  volume=%s
  dims=%s, %s, %s
  bounds=%s-%s, %s-%s, %s-%s
  basis=%s, %s, %s",
    bestXLength * bestYZArea,
    bestXLength, bestYHigh - bestYLow, bestZHigh - bestZLow,
    bestXLow, bestXHigh, bestYLow, bestYHigh, bestZLow, bestZHigh,
    bestXAxis, bestYAxis, bestZAxis);
  
  return null;
}

