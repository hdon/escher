/* Copyright 2014 Donny Viszneki. All rights reserved.
 * You are not authorized to distribute this source code.
 */
module ants.shader;
//import derelict.opengl3.gl3;
import ants.glutil;
import glad.gl.all;
import file = std.file;
import std.exception : enforce;
import std.stdio : writeln, writefln;
import std.string : format, toStringz;
import std.traits : isPointer, PointerTarget;
import std.conv : to;
import std.path : baseName;
import std.algorithm : sort;

private int[][string] availableShaders;

private bool isnum(char c) { return c >= '0' && c <= '9'; }
private int unstrVersion(string s)
{
  return s.length == 4 && s[1] == '.' && isnum(s[0]) && isnum(s[2]) && isnum(s[3]) ?
    (s[0]-'0')*100 + (s[2]-'0')*10 + (s[3]-'0') : -1;
}
private void scan()
{
  foreach (string d; file.dirEntries("glsl", file.SpanMode.shallow))
  {
    int v = unstrVersion(d[5..$]);
    if (v >= 0)
      foreach (string s; file.dirEntries(d, file.SpanMode.shallow))
        if (s[$-3..$] == ".vs" || s[$-3..$] == ".fs")
          availableShaders[s[d.length+1..$]] ~= v;
  }
  foreach (versions; availableShaders)
    sort!"b < a"(versions);
}
private int glslVersion;
private string findBestShader(string shaderName)
{
  if (glslVersion == 0)
  {
    const(char)*a = cast(const char *)glGetString(GL_SHADING_LANGUAGE_VERSION);
    glslVersion = unstrVersion(to!string(a[0..4]));
    scan();
  }

  if (shaderName !in availableShaders)
    throw new Exception(format("could not find your shader named \"%s\"", shaderName));

  foreach (v; availableShaders[shaderName])
    if (v <= glslVersion)
      return format("glsl/%01d.%02d/%s", v/100, v%100, shaderName);

  throw new Exception(format("could not find shader \"%s\" in any compatible version", shaderName));
}

GLuint loadShader(GLenum type, string filename)
{
  GLenum err;
  GLuint shaderObject;
  GLint iresult;
  char[] source;
  char*  sourcePtr;
  int souceLen;

  // Create GL shader object
  glErrorCheck();
  shaderObject = glCreateShaderObjectARB(type);
  glErrorCheck();
  enforce(shaderObject != 0, "glCreateShader() failed");

  // Read shader source into memory
  auto exactName = findBestShader(filename);
  glErrorCheck();
  version (debugShaders) writefln("[shader] loading \"%s\"", exactName);
  source = cast(char[])file.read(exactName);

  // Send shader source to the GL
  sourcePtr = source.ptr;
  souceLen = cast(int)source.length;
  glShaderSourceARB(shaderObject, 1, cast(const(byte *)*)&sourcePtr, &souceLen);
  glErrorCheck();

  // Compile shaderObject
  glCompileShaderARB(shaderObject);
  glErrorCheck();

  // Check compile result
  glGetObjectParameterivARB(shaderObject, GL_OBJECT_COMPILE_STATUS_ARB, &iresult);
  glErrorCheck();
  if (iresult == GL_FALSE)
  {
    glGetObjectParameterivARB(shaderObject, GL_INFO_LOG_LENGTH, &iresult);
    if (iresult <= 1)
    {
      writefln("error: glCompileShader() failed with no error message");
    }
    else
    {
      char[] log = new char[iresult];
      glGetInfoLogARB(shaderObject, iresult, cast(int *)null, cast(byte *)log.ptr);
      writeln("error: glCompileShader() failed:\n", log);
    }
    writeln("shader source:\n", source);

    assert(0);
  }

  glErrorCheck();
  return shaderObject;
}

class Shader(GLenum type)
{
  GLuint shaderObject;
  string filename;
  this(string filename)
  {
    this.filename = filename;
    shaderObject = loadShader(type, filename);
    //writeln("Shader() ", shaderObject);
  }

  ~this()
  {
    //writeln("glDeleteShader() ", shaderObject);
    glDeleteObjectARB(shaderObject);
  }
}

alias Shader!GL_VERTEX_SHADER_ARB VertexShader;
alias Shader!GL_FRAGMENT_SHADER_ARB FragmentShader;

GLuint linkProgram(VertexShader vs, FragmentShader fs)
{
  GLuint programObject;
  GLint iresult;

  // Create program object
  programObject = glCreateProgramObjectARB();
  enforce(programObject != 0, "error: glCreateProgram() failed");

  // Link
  glAttachObjectARB(programObject, vs.shaderObject);
  glAttachObjectARB(programObject, fs.shaderObject);
  glLinkProgramARB(programObject);

  // Handle link errors
  glGetObjectParameterivARB(programObject, GL_OBJECT_LINK_STATUS_ARB, &iresult);
  if (iresult == GL_FALSE)
  {
    glGetObjectParameterivARB(programObject, GL_INFO_LOG_LENGTH, &iresult);
    if (iresult <= 1)
    {
      writefln("error: glCompileShader() failed with no error message");
    }
    else
    {
      char[] log = new char[iresult];
      glGetInfoLogARB(programObject, iresult, cast(int *)null, cast(byte *)log.ptr);
      writeln("error: glCompileShader() failed:\n", log);
    }
    writefln("could not link vertex shader %s and fragment shader %s", vs, fs);

    assert(0);
  }

  return programObject;
}

class ShaderProgram
{
  GLuint programObject;
  VertexShader vs;
  FragmentShader fs;

  this(VertexShader vs, FragmentShader fs)
  {
    this.vs = vs;
    this.fs = fs;
    programObject = linkProgram(vs, fs);

    // XXX
    //glBindAttribLocation(programObject, 1, "ucolor");
    glErrorCheck();
  }
  this(string vsFilename, string fsFilename)
  {
    this(new VertexShader(vsFilename), new FragmentShader(fsFilename));
  }

  ~this()
  {
    glDeleteProgram(programObject);
  }

  GLuint getUniformLocation(string name)
  {
    return glGetUniformLocationARB(programObject, cast(const(byte)*)name.toStringz());
  }

  GLint getAttribLocation(string name)
  {
    return glGetAttribLocationARB(programObject, cast(const(byte)*)name.toStringz());
  }

  GLuint getUniformLocationz(const char* name)
  {
    return glGetUniformLocationARB(programObject, cast(const(byte)*)name);
  }

  GLint getAttribLocationz(const char* name)
  {
    return glGetAttribLocationARB(programObject, cast(const(byte)*)name);
  }

  void use()
  {
    glUseProgramObjectARB(programObject);
    glErrorCheck();
  }
}

