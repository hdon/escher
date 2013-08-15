module ants.material;
import ants.texture;

enum TextureApplication
{
  Color,
  Normal
}

class MaterialTexture
{
  Texture texture;
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

