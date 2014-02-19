/* Copyright 2014 Donny Viszneki. All rights reserved.
 * You are not authorized to distribute this source code.
 */
module ants.glutil;
import derelict.opengl3.gl3;
import std.stdio : writefln;
import std.string : format;

private string[int] errors;

static this() {
  errors = [
    0x0500:  "GL_INVALID_ENUM",
    0x0501:  "GL_INVALID_VALUE",
    0x0502:  "GL_INVALID_OPERATION",
    0x0505:  "GL_OUT_OF_MEMORY"
  ];
}

void glErrorCheck(string label="", string file=__FILE__, int line=__LINE__)
{
  GLenum err = glGetError();
  if (err)
    writefln("error: %s%s%s:%d: %s", label, label.length?": ":"", file, line, errors[err]);
}
