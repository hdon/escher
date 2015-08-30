module ants.entityplayer;
import std.stdio;
import ants.entity;

class EntityPlayer : Entity
{
  vec3 vel;
  int spaceID;
  double camYaw;
  double camPitch;
  bool keyForward;
  bool keyBackward;
  bool keyLeft;
  bool keyRight;
  bool keyUp;
  bool keyDown;
  bool fly;
  bool grounded;
  bool noclip;
  this(int spaceID, vec3 pos)
  {
    super(spaceID, pos);
    this.spaceID = spaceID;
    this.pos = pos;
    this.camYaw = 0.0;
    this.camPitch = 0.0;
    this.vel = vec3(0,0,0);
    this.grounded = true;
  }

  override void draw(mat4 mvmat, mat4 pmat) {}

  static Spawner spawner(int spaceID, vec3 pos)
  {
    Entity spawn() { return new EntityPlayer(spaceID, pos); }
    return &spawn;
  }

  static struct IntegrationInputState
  {
  }

  version (escherClient)
  void doNetStuff()
  {
    
  }

  float profileCollision;
  override void update(float deltaf)
  {
    vec3 accel;
    const double EPSILON = 0.000001;
    const double speed = 10.0;
    const double startSpeed = 0.08;
    const double jumpVel = 25.0;
    const double mass = 1.0;

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
      foreach (tryEdges; 0..2)
      //enum tryEdges = false;
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
          // XXX
          // TODO i believe normalizing the operands is USELESS
          // XXX
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
          /*const double hitSphereRadius = 0.25;
          const double hitSphereScaleY = 1.0;
          vec3 hitSphereDelta = n * vec3(hitSphereRadius, hitSphereScaleY+hitSphereRadius, hitSphereRadius),
               hitSphereStartPos = oldpos + hitSphereDelta,
               hitSphereEndPos = pos + hitSphereDelta;*/
          const double hitSphereRadius = 0.25;
          vec3 hitSphereDelta = hitSphereRadius * n,
               hitSphereStartPos = oldpos + hitSphereDelta,
               hitSphereEndPos = pos + hitSphereDelta;

          /* Has the hitpoint passed through this triangle in this space face? */
          bool hit =
            !tryEdges &&
            face.indices.length == 3 &&
            passThruTest(hitSphereStartPos, movement.normalized, fv[0], fv[1], fv[2], movement.length);

          if (!hit)
          {
            if (!tryEdges)
              continue;

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
              double u = dot(p3-p1, p2_p1) / p2_p1.magnitude_squared;

              //writefln("@@ attempting segment-sphere intersection: %f", u);
              if (u >= 0 && u <= 1)
              {
                //writeln("@@ WINRAR WINRAR WINRAR WINRAR WINRAR WIN: ^^^^^^^");
                /* Find the exact position of the point */
                vec3 p = lerp(p1, p2, u);
                vec3 dp = p - p3;
                if (dp.magnitude_squared < hitSphereRadius * hitSphereRadius)
                {
                  writeln("@@ segment-sphere hit!");
                  writefln("@@ segment %s %s belongs to face %s %s %s",
                    p1, p2, fv[0], fv[1], fv[2]);

                  /* TODO The pseudo-plane technique accelerates your movement around a bend.
                   *      This is undesirable and should be addressed!
                   */

                  /* Calculate the pseudo-plane normal by subtracting 'p' from 'pos.' */
                  vec3 pseudon = (pos - p).normalized;

                  //writeln("@@ pseudo normal: ", n);

                  /* Solve planar equation for 'd' of plane containing the edge we hit */
                  double p0d = -dot(p, n);

                  //writeln("@@   wall plane 0 d = ", p0d);

                  /* Solve planar equation for 'd' of plane p1 */
                  double p1d = -dot(n, hitSphereEndPos);
                  //writeln("@@   wall plane 1 d = ", p1d);

                  /* Compute new position projected onto the plane containing map face */
                  if (p1d < p0d)
                    pos = pos + (p1d-p0d) * PHYSPUSH * n;
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
             * v' = v + n * f
             */

            //writeln("@@   wall normal: ", n);

            /* Solve planar equation for 'd' of plane containing map face */
            double p0d = -dot(fv[0], n);

            //writeln("@@   wall plane 0 d = ", p0d);

            /* Solve planar equation for 'd' of plane p1 */
            double p1d = -dot(n, hitSphereEndPos);
            //writeln("@@   wall plane 1 d = ", p1d);

            /* Compute new position projected onto the plane containing map face */
            if (p1d < p0d)
              pos = pos + (p1d-p0d) * PHYSPUSH * n;
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
            debug writefln("entering space %d remoteID=%d num space #remotes=%d #faces=%d",
              spaceID, face.data.remote.remoteID, space.remotes.length, space.faces.length);

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
      // TODO do all of this collision elsewhere!
      profileCollision = stopWatch.peek.to!("msecs", float)();
    }

    // XXX shitty way to move entities into a new space so that they can be found by-space
    /* TODO entities need to be able to move between Spaces via portals */
    static if (0)
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

    //playerEntity.pos = pos;
    //playerEntity.angle = camYaw;
  }
}


