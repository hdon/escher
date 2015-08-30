/* Copyright 2014 Donny Viszneki. All rights reserved.
 * You are not authorized to distribute this source code.
 */
module ants.shader;
import derelict.opengl3.gl3;
import file = std.file;
import std.exception : enforce;
import std.stdio : writeln, writefln;
import std.string : format, toStringz;
import std.traits : isPointer, PointerTarget;
import std.conv : to;
import std.path : baseName;
import std.traits : isSigned;
import std.algorithm : sort;
import ants.glutil;

private int[][string] availableShaders;

private bool isnum(char c) { return c >= '0' && c <= '9'; }
private int unstrVersion(string s)
{
  return s.length == 4 && s[1] == '.' && isnum(s[0]) && isnum(s[2]) && isnum(s[3]) ?
    (s[0]-'0')*100 + (s[2]-'0')*10 + (s[3]-'0') : -1;
}
private void scan()
{
  size_t numShaders;
  foreach (string d; file.dirEntries("glsl", file.SpanMode.shallow))
  {
    int v = unstrVersion(d[5..$]);
    if (v >= 0)
      foreach (string s; file.dirEntries(d, file.SpanMode.shallow))
      {
        if (s[$-5..$] == ".glsl")
        {
          numShaders++;
          availableShaders[s[d.length+1..$]] ~= v;
        }
      }
  }
  foreach (versions; availableShaders)
    sort!"b < a"(versions);
  writefln("scanned %d *.glsl files", numShaders);
}
private int glslVersion;
private string findBestShader(string shaderName)
{
  if (glslVersion == 0)
  {
    const(char)*a = glGetString(GL_SHADING_LANGUAGE_VERSION);
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
  shaderObject = glCreateShader(type);
  enforce(shaderObject != 0, "glCreateShader() failed");

  // Read shader source into memory
  auto exactName = findBestShader(filename);
  writefln("[shader] loading \"%s\"", exactName);
  source = cast(char[])file.read(exactName);

  // Send shader source to the GL
  sourcePtr = source.ptr;
  souceLen = cast(int)source.length;
  glShaderSource(shaderObject, 1, &sourcePtr, &souceLen);

  // Compile shaderObject
  glCompileShader(shaderObject);

  // Check compile result
  glGetShaderiv(shaderObject, GL_COMPILE_STATUS, &iresult);
  if (iresult == GL_FALSE)
  {
    glGetShaderiv(shaderObject, GL_INFO_LOG_LENGTH, &iresult);
    if (iresult <= 1)
    {
      writefln("error: glCompileShader() failed with no error message");
    }
    else
    {
      char[] log = new char[iresult];
      glGetShaderInfoLog(shaderObject, iresult, null, log.ptr);
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
    glDeleteShader(shaderObject);
  }
}

alias Shader!GL_VERTEX_SHADER VertexShader;
alias Shader!GL_FRAGMENT_SHADER FragmentShader;

GLuint linkProgram(VertexShader vs, FragmentShader fs)
{
  GLuint programObject;
  GLint iresult;

  // Create program object
  programObject = glCreateProgram();
  enforce(programObject != 0, "error: glCreateProgram() failed");

  // Link
  glAttachShader(programObject, vs.shaderObject);
  glAttachShader(programObject, fs.shaderObject);
  glLinkProgram(programObject);

  // Handle link errors
  glGetProgramiv(programObject, GL_LINK_STATUS, &iresult);
  if (iresult == GL_FALSE)
  {
    glGetProgramiv(programObject, GL_INFO_LOG_LENGTH, &iresult);
    if (iresult <= 1)
    {
      writefln("error: glCompileShader() failed with no error message");
    }
    else
    {
      char[] log = new char[iresult];
      glGetProgramInfoLog(programObject, iresult, null, log.ptr);
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

    glErrorCheck();
  }
  this(string vsFilename, string fsFilename)
  {
    glErrorCheck();
    this(new VertexShader(vsFilename), new FragmentShader(fsFilename));
  }

  ~this()
  {
    glDeleteProgram(programObject);
  }

  GLint getUniformLocation(string name)
  {
    return glGetUniformLocation(programObject, name.toStringz());
  }

  GLint getAttribLocation(string name)
  {
    return glGetAttribLocation(programObject, name.toStringz());
  }

  GLuint getUniformLocationz(const char* name)
  {
    return glGetUniformLocation(programObject, name);
  }

  GLint getAttribLocationz(const char* name)
  {
    return glGetAttribLocation(programObject, name);
  }

  void use()
  {
    glUseProgram(programObject);
    glErrorCheck();
  }
}
