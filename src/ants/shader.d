module ants.shader;
import derelict.opengl3.gl3;
import file = std.file;
import std.exception : enforce;
import std.stdio : writeln, writefln;
import std.string : format, toStringz;
import std.traits : isPointer, PointerTarget;
import std.conv : to;

private void glErrorCheck()
{
  GLenum err = glGetError();
  if (err)
  {
    writefln("error: opengl: %s", err);
    assert(0);
  }
}

private string glslPath;
private string getPath() {
  if (glslPath.length == 0) {
    const(char)*a = glGetString(GL_SHADING_LANGUAGE_VERSION);
    const(char)*b = a;
    while (*b != ' ' && *b != '\0')
      b++;
    glslPath = "glsl/" ~ to!string(a[0..b-a]) ~ "/";
  }
  return glslPath;
}

GLuint loadShader(GLenum type, string filename)
{
  getPath();
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
  source = cast(char[])file.read(getPath() ~ filename);

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

    // XXX
    glBindAttribLocation(programObject, 1, "ucolor");
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
    return glGetUniformLocation(programObject, name.toStringz());
  }

  GLint getAttribLocation(string name)
  {
    return glGetAttribLocation(programObject, name.toStringz());
  }

  void use()
  {
    glUseProgram(programObject);
    glErrorCheck();
  }
}
