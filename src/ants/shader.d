module ants.shader;
import derelict.opengl.gl;
import derelict.opengl.glu;
import file = std.file;
import std.exception : enforce;
import std.stdio : writeln, writefln;

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
  source = cast(char[])file.read("glsl/" ~ filename);

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

  this(VertexShader vs, FragmentShader fs)
  {
    programObject = linkProgram(vs, fs);
  }
  this(string vsFilename, string fsFilename)
  {
    programObject = linkProgram(
      new VertexShader(vsFilename),
      new FragmentShader(fsFilename));
  }

  void use()
  {
    glUseProgram(programObject);
  }
}
