/* Copyright 2014 Donny Viszneki. All rights reserved.
 * You are not authorized to distribute this source code.
 */
module ants.texture;

import std.conv;
import std.string : toStringz;
import std.format : appender;
import derelict.sdl2.sdl;
import derelict.sdl2.image;
//import derelict.opengl3.gl3;
import glad.gl.all;
import ants.glutil;
import std.stdio : writefln;

alias loadTexture getTexture;

/// load a texture resource from the specified path
GLuint loadTexture(string filename) {
    filename = "res/images/" ~ filename;

    SDL_Surface *surface;

    scope(exit) { if (surface) SDL_FreeSurface(surface); surface = null; }

    /* Use SDL_Image lib to load the image into an SDL_Surface */
    surface = IMG_Load(toStringz(filename));

    if (!surface) {
      writefln("[texture] IMG_Load(\"%s\") failed", filename);
      return 0;
    }

    debug writefln("[texture] %dx%d \"%s\"", surface.w, surface.h, filename);

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

    GLfloat largest_supported_anisotropy;
    glGetFloatv(GL_MAX_TEXTURE_MAX_ANISOTROPY_EXT, &largest_supported_anisotropy);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAX_ANISOTROPY_EXT, largest_supported_anisotropy);

    glGenerateMipmapEXT(GL_TEXTURE_2D);

    return texture;
}
