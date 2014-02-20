/* Copyright 2014 Donny Viszneki. All rights reserved.
 * You are not authorized to distribute this source code.
 */
module ants.material;
import ants.texture;
//import derelict.opengl3.gl3;
import glad.gl.all;
import ants.glutil;

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

