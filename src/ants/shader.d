module ants.shader;
import derelict.opengl3.gl3;
import file = std.file;
import std.exception : enforce;
import std.stdio : writeln, writefln;
import std.string : format, toStringz;
import std.traits : isPointer, PointerTarget;

private void glErrorCheck()
{
  GLenum err = glGetError();
  if (err)
  {
    writefln("error: opengl: %s", err);
    assert(0);
  }
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
    writeln("Shader() ", shaderObject);
  }

  ~this()
  {
    writeln("glDeleteShader() ", shaderObject);
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
    writeln("glDeleteProgram()");
    glDeleteProgram(programObject);
  }

  version (mixin_gl_apis)
  {
    private static pure string gen_glUniform(T)(int n)
    {
      enum bool ptr = isPointer!T;

      static if (ptr)
      {
        alias PointerTarget!T U;
        enum string typeStrV = "v";
      }
      else
      {
        alias T U;
        enum string typeStrV = "";
      }

      static if (is(U == float))      enum string typeStr = "f";
      else static if (is(U == uint))  enum string typeStr = "ui";
      else static if (is(U == int))   enum string typeStr = "i";
      else static assert(0, "unsupprted type");

      string myArgs = "GLint location";
      string glArgs = "location";
      char argName = 'a';

      static if (isPointer!T)
      {
        myArgs ~= ", GLsizei count, " ~ T.stringof ~ " ptr";
        glArgs ~= ", count, ptr";
      }
      else
      {
        foreach (i; 0..n)
        {
          myArgs ~= ", " ~ T.stringof ~ ' ' ~ argName;
          glArgs ~= ", " ~ argName;
          argName++;
        }
      }

      return "void setUniform"
             ~ "("
             ~ myArgs
             ~ ") { glUniform"
             ~ cast(char)(n + '0') // WTF
             ~ typeStr
             ~ typeStrV
             ~ "("
             ~ glArgs
             ~ "); }";
    }

    static pure string gen_glUniformAll()
    {
      string rval = "";
      foreach (n; 1..5)
      {
        rval ~= '\n' ~ gen_glUniform!int(n);
        rval ~= '\n' ~ gen_glUniform!uint(n);
        rval ~= '\n' ~ gen_glUniform!float(n);
        rval ~= '\n' ~ gen_glUniform!(int*)(n);
        rval ~= '\n' ~ gen_glUniform!(uint*)(n);
        rval ~= '\n' ~ gen_glUniform!(float*)(n);
      }
      return rval;
    }

    mixin(gen_glUniformAll());
  }
  else
  {
    void glUniform(string name, float a, float b, float c)
    {
      GLint location = glGetUniformLocation(programObject, name.toStringz());
      glUniform3f(location, a, b, c);
    }

    void sendVertexAttribute(string name, float a, float b, float c)
    {
      glVertexAttrib3f(1, a, b, c);
    }

    GLuint getUniformLocation(string name)
    {
      return glGetUniformLocation(programObject, name.toStringz());
    }

    GLuint getAttribLocation(string name)
    {
      return glGetAttribLocation(programObject, name.toStringz());
    }
  }

  void use()
  {
    glUseProgram(programObject);
    glErrorCheck();
  }
}
