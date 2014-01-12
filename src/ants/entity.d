module ants.entity;
import std.stdio;
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
  void draw(mat4 mvmat, mat4 pmat)
  {
  }

  void update(float deltaf)
  {
  }
}

class EntityMD5 : Entity
{
  static
  {
    MD5Model md5Model;
  }
  MD5Animation currentAnimation;

  override
  void draw(mat4 mvmat, mat4 pmat)
  {
  }

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
}

class EntitySpikey : EntityMD5
{
  static MD5Model model;
  static MD5Animation anim;

  this(int spaceID, vec3 pos)
  {
    super(spaceID, pos);
  }

  override
  void draw(mat4 mvmat, mat4 pmat)
  {
    anim.draw(mvmat * mat4.translation(pos.x, pos.y, pos.z), pmat);
  }
}

/* Shittiest easiest way to do this... */
void loadEntityAssets()
{
  EntitySpikey.model = new MD5Model("res/md5/spikey.md5mesh");
  EntitySpikey.anim = new MD5Animation(EntitySpikey.model, "res/md5/spikey.md5anim");
}
