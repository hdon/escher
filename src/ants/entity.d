module ants.entity;
import std.stdio;
import gl3n.interpolate : lerp;
import ants.escher : vec3, mat4;
import ants.md5 : MD5Model, MD5Animation;

class Entity
{
  int spaceID;
  vec3 pos;

  this(int spaceID, vec3 pos)
  {
    this.spaceID = spaceID;
    this.pos = pos;
  }

  version (escherClient)
  abstract void draw(mat4 mvmat, mat4 pmat);

  void update(float deltaf)
  {
  }
}

alias Entity delegate() Spawner;

class EntityMD5 : Entity
{
  enum mixme = q{
    static {
      MD5Model model;
      MD5Animation anim;
    }

    override
    void draw(mat4 mvmat, mat4 pmat)
    {
      anim.draw(mvmat * mat4.translation(pos.x, pos.y, pos.z), pmat);
    }
  };

  this(int spaceID, vec3 pos)
  {
    super(spaceID, pos);
  }
}

class EntityPlayer : Entity
{
  float angle;
  this(int spaceID, vec3 pos, float angle=0f)
  {
    super(spaceID, pos);
    this.angle = angle;
  }

  override void draw(mat4 mvmat, mat4 pmat) {}

  static Spawner spawner(int spaceID, vec3 pos, float angle=0f)
  {
    Entity spawn() { return new EntityPlayer(spaceID, pos, angle); };
    return &spawn;
  }
}

class EntityEnemy : EntityMD5
{
  vec3[] path;
  size_t pathCurrentStep;
  float pathCurrentStepDistance;

  bool dead;

  this(int spaceID, vec3 pos, vec3[] path=null)
  {
    super(spaceID, pos);
    this.path = path;
    this.pathCurrentStepDistance = 0f;
  }

  float getPathSpeed() { return 1f; }

  override
  void update(float deltaf)
  {
    if (path !is null)
    {
      float motionLength = getPathSpeed() * deltaf;
      pathCurrentStepDistance += motionLength;

      vec3 stepVector;
      float stepLength;
      while (1)
      {
        stepVector = (path[(pathCurrentStep+1)%$] - path[pathCurrentStep]);
        stepLength = stepVector.magnitude;
        if (pathCurrentStepDistance < stepLength)
          break;

        /* Advance current step, first by subtracting the length of the step
         * we've surpassed from the distance we've traveled.
         */
        pathCurrentStepDistance -= stepLength;
        /* Advance current step counter */
        if (++pathCurrentStep == path.length)
          pathCurrentStep = 0;
      }

      /* Calculate our position along our current step */
      stepVector = stepVector.normalized;
      pos = path[pathCurrentStep] + stepVector * pathCurrentStepDistance;
      /* TODO calculate orientation from stepVector! */
    }
  }

  /* This function will adjust the EntityEnemy's step-in-path as well as
   * their step-of-path using my shitty primitive path system. It's used
   * at spawn time so that you can stagger enemy positions within their
   * paths in the map itself without adding extra info.
   */
  void getIntoPath(size_t pathStep=0)
  {
    /* Set steo-of-path */
    pathCurrentStep = pathStep;

    /* Calculate our progress within this path step, starting with calculating
     * the direction of movement for this step.
     */
    vec3 pathDir = (path[(pathCurrentStep+1)%$] - path[pathCurrentStep]).normalized;
    /* Calculate how far along we are in this direction from the position of the
     * beginning of this step. Assuming 'pathStep' is correct this should work...
     */
    pathCurrentStepDistance = (path[pathCurrentStep] - pos).magnitude;
  }
}

class EntitySpikey : EntityEnemy
{
  mixin(mixme);

  this(int spaceID, vec3 pos, vec3 orient)
  {
    // TODO orient!
    super(spaceID, pos);
  }

  static Spawner spawner(int spaceID, vec3 pos, vec3 orient, vec3[] path=null)
  {
    Entity spawn() {
      auto e = new EntitySpikey(spaceID, pos, orient);
      e.path = path;
      e.getIntoPath(0); // XXX 0 is probably wrong!
      return e;
    }
    return &spawn;
  }
}

class EntityDragonfly : EntityEnemy
{
  mixin(mixme);

  this(int spaceID, vec3 pos, vec3 orient)
  {
    // TODO orient!
    super(spaceID, pos);
  }

  static Spawner spawner(int spaceID, vec3 pos, vec3 orient, vec3[] path=null)
  {
    Entity spawn() {
      auto e = new EntityDragonfly(spaceID, pos, orient);
      e.path = path;
      e.getIntoPath(0); // XXX 0 is probably wrong!
      return e;
    }
    return &spawn;
  }
}

/* Shittiest easiest way to do this... */
void loadEntityAssets()
{
  EntitySpikey.model = new MD5Model("res/md5/spikey.md5mesh");
  EntitySpikey.anim = new MD5Animation(EntitySpikey.model, "res/md5/spikey.md5anim");

  EntityDragonfly.model = new MD5Model("res/md5/dragonfly-walk.md5mesh");
  EntityDragonfly.anim = new MD5Animation(EntityDragonfly.model, "res/md5/dragonfly-walk.md5anim");
}

