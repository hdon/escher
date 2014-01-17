module ants.material;
import ants.texture;
import derelict.opengl3.gl3;

enum TextureApplication
{
  Color,
  Normal
}

class MaterialTexture
{
  GLuint texture;
  TextureApplication application;
}

class Material
{
  MaterialTexture[]     texes;
  void use()
  {
    // TODO
  }
}

