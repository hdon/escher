module ants.texture;

import std.conv;
import std.string : toStringz;
import std.format : appender;
import ants.rescache;
import derelict.sdl2.sdl;
import derelict.sdl2.image;
import derelict.opengl3.gl3;
debug import std.stdio : writefln;

mixin ResourceCacheMixin!GLuint;

private Resource loadResource(string k)
{
  GLuint v = loadTexture(k);
  if (v == 0)
    return null;
  return new Resource(k, v);
}

private void freeResource(GLuint v)
{
  debug writefln("texture.freeResource(%x)", v);
  if (v != 0)
    glDeleteTextures(1, &v);
}

private class Resource
{
  mixin ResourceMixin;
}

alias get getTexture;
alias Resource Texture;

/// load a texture resource from the specified path
GLuint loadTexture(string filename) {
    filename = "res/images/" ~ filename;

    debug writefln("[texture] loading \"%s\"", filename);

    SDL_Surface *surface;

    scope(exit) { if (surface) SDL_FreeSurface(surface); surface = null; }

    /* Use SDL_Image lib to load the image into an SDL_Surface */
    debug writefln("[texture] IMG_Load()");
    surface = IMG_Load(toStringz(filename));

    debug writefln("[texture] surface = %x", surface);
    if (!surface)
      return 0;

    debug writefln("[texture] image dimensions: %dx%d", surface.w, surface.h);

    /* Convert SDL_Surface to OpenGL texture */
    GLuint texture;

    glEnable(GL_TEXTURE_2D);
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    //glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    //glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    GLenum format;
    switch (surface.format.BytesPerPixel) {
      case 4:
        format = (surface.format.Rmask == 0x000000ff) ? GL_RGBA : GL_BGRA;
        break;
      case 3:
        format = (surface.format.Rmask == 0x000000ff) ? GL_RGB : GL_BGR;
        break;
      default:
        assert(0, "can only handle 3 or 4 bytes per pixel");
    }

    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, surface.w, surface.h,
        0, format, GL_UNSIGNED_BYTE, surface.pixels);

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glGenerateMipmap(GL_TEXTURE_2D);

    return texture;
}
