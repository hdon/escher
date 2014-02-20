/* Copyright 2014 Donny Viszneki. All rights reserved.
 * You are not authorized to distribute this source code.
 */
module ants.vbo;
//import derelict.opengl3.gl3;
import glad.gl.all;
import ants.glutil;
import ants.shader;
import ants.vertexer : mat4d, mat4f;

void glErrorCheck(string source)
{
  GLenum err = glGetError();
  if (err)
  {
    writefln("error @ %s: opengl: %s", source, err);
  }
}

private const float[] vertData = [
  -10, -10, 0,
   0,   10, 0,
   1,0 -10, 0
];

private const uint[] indexData = [
  0, 1, 2
];

class VBO
{
  GLuint posBuf;
  GLuint indBuf;
  static ShaderProgram shaderProgram;

  GLint posAttloc;
  GLint mvmatUniloc;
  GLint pmatUniloc;

  this()
  {
    shaderProgram = new ShaderProgram("simple-red.vs", "simple-red.fs");

    posAttloc = shaderProgram.getAttribLocation("positionV");

    mvmatUniloc = shaderProgram.getUniformLocation("viewMatrix");
    pmatUniloc = shaderProgram.getUniformLocation("projMatrix");

    glGenBuffers(2, &posBuf);
    glBindBuffer(GL_ARRAY_BUFFER, posBuf);
    glBufferData(GL_ARRAY_BUFFER, vertData.length * float.sizeof, vertData.ptr, GL_STATIC_DRAW);

    glBindBuffer(GL_ARRAY_BUFFER, 0);

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, indBuf);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, indexData.length * uint.sizeof, indexData.ptr, GL_STATIC_DRAW);

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);

    writefln("%d %d %d %d %d",
      posBuf, indBuf, posAttloc, mvmatUniloc, pmatUniloc);
  }

  ~this()
  {
    glDeleteBuffers(2, &posBuf);
  }

  void draw(mat4d mvMatd, mat4d pMatd)
  {
    mat4f mvMat = mat4f(mvMatd);
    mat4f pMat = mat4f(pMatd);

    shaderProgram.use();

    glUniformMatrix4fv(mvmatUniloc, 1, GL_TRUE, mvMat.value_ptr);
    glUniformMatrix4fv(pmatUniloc, 1, GL_TRUE, pMat.value_ptr);

    glBindBuffer(GL_ARRAY_BUFFER, posBuf);
    glEnableVertexAttribArray(posAttloc);
    glVertexAttribPointer(posAttloc, 3, GL_FLOAT, GL_FALSE, 0, cast(void*)0);

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, indBuf);

    glDisable(GL_BLEND);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);
    glDrawElements(GL_TRIANGLES, 3, GL_UNSIGNED_INT, cast(void*)0);

    glErrorCheck("8");
  }
}
