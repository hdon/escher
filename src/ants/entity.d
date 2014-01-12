module ants.entity;
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

class EntityPlayer : EntityMD5
{
  float angle;
  this(int spaceID, vec3 pos, float angle=0f)
  {
    super(spaceID, pos);
    this.angle = angle;
  }
}
