/* Copyright 2014 Donny Viszneki. All rights reserved.
 * You are not authorized to distribute this source code.
 */
module ants.hudtext;
import derelict.opengl3.gl3;
import ants.texture;
import ants.shader;

import gl3n.linalg : Vector;
private alias Vector!(float, 2) vec2;

void glErrorCheck(string source)
{
  GLenum err = glGetError();
  if (err)
  {
    writefln("error @ %s: opengl: %s", source, err);
    assert(0);
  }
}

ShaderProgram shaderProgram;

class HUDText
{
  bool visible;
  GLuint font;
  char[] buf;
  
  uint w, h;
  vec2[] vertexPositions;
  vec2[] vertexUVs;

  this(uint w, uint h, float sx, float sy, float sw, float sh)
  {
    redimension(w, h, sx, sy, sw, sh);

    // TODO texture/sample parameters are currently being set in doglconsole, lol
    font = getTexture("font850.png");

    glBindTexture(GL_TEXTURE_2D, font);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAX_ANISOTROPY_EXT, 1);

    visible = true;
  }

  void redimension(uint w, uint h, float sx, float sy, float sw, float sh)
  {
    this.w = w;
    this.h = h;

    buf.length = w*h;

    vertexUVs.length = 0;
    vertexUVs.length = w*h*6;

    vertexPositions.length = 0;
    vertexPositions.length = w*h*6;

    float rH = sh/h;
    float rW = sw/w;
    float y0, y1, x0, x1;
    float sx_sw = sx;
    float sy_sh = sy;
    y1 = sy_sh;
    for (uint y=0; y<h; y++)
    {
      y0 = y1;
      y1 = -rH*(y+1) + sy_sh;
      x1 = sx_sw;
      for (uint x=0; x<w; x++)
      {
        x0 = x1;
        x1 = rW*(x+1) + sx_sw;
        uint n = (y*w+x)*6;

        vertexPositions[n+0] = vec2(x0, y0);
        vertexPositions[n+1] = vec2(x1, y0);
        vertexPositions[n+2] = vec2(x0, y1);

        vertexPositions[n+3] = vertexPositions[n+2];
        vertexPositions[n+4] = vertexPositions[n+1];
        vertexPositions[n+5] = vec2(x1, y1);
      }
    }
  }

  void print(string text)
  {
    uint cursor = 0;
    foreach (char c; text)
    {
      if (c == '\0')
        {}
      if (c == '\n')
        while (cursor % w != 0)
          buf[cursor++] = ' ';
      else
        buf[cursor++] = c;
      if (cursor >= buf.length)
        return;
    }
  }

  void draw()
  {
    if (!visible)
      return;

    if (shaderProgram is null)
      shaderProgram = new ShaderProgram("doglconsole.vs", "doglconsole.fs");

    float r = 1f/16f;
    for (uint y=0; y<h; y++)
    {
      for (uint x=0; x<w; x++)
      {
        char c = buf[y*w+x];
        char cx = c%16;
        char cy = c/16;
        float x0 = r *  cx;
        float x1 = r * (cx+1);
        float y0 = r *  cy;
        float y1 = r * (cy+1);

        uint n = (y*w+x)*6;
        vertexUVs[n+0] = vec2(x0, y0);
        vertexUVs[n+1] = vec2(x1, y0);
        vertexUVs[n+2] = vec2(x0, y1);

        vertexUVs[n+3] = vertexUVs[n+2];
        vertexUVs[n+4] = vertexUVs[n+1];
        vertexUVs[n+5] = vec2(x1, y1);
      }
    }

    GLuint vertexArrayObject;

    GLuint positionBufferObject;
    GLuint uvBufferObject;

    GLint positionVertexAttribLocation;
    GLint uvVertexAttribLocation;

    GLuint fontTexUniformLocation;

    shaderProgram.use();

    /* Get uniform locations */
    fontTexUniformLocation = shaderProgram.getUniformLocation("font");

    /* Get vertex attribute locations */
    positionVertexAttribLocation = shaderProgram.getAttribLocation("positionV");
    uvVertexAttribLocation = shaderProgram.getAttribLocation("uvV");

    /* Generate arrays/buffers to send vertex data */
    glGenVertexArrays(1, &vertexArrayObject);
    glGenBuffers(1, &positionBufferObject);
    glGenBuffers(1, &uvBufferObject);

    /* Send vertex data */
    glBindVertexArray(vertexArrayObject);

    glBindBuffer(GL_ARRAY_BUFFER, positionBufferObject);
    glBufferData(GL_ARRAY_BUFFER, vertexPositions.length * vertexPositions[0].sizeof, vertexPositions.ptr, GL_STREAM_DRAW);
    glEnableVertexAttribArray(positionVertexAttribLocation);
    glVertexAttribPointer(positionVertexAttribLocation, 2, GL_FLOAT, 0, 0, null);

    glBindBuffer(GL_ARRAY_BUFFER, uvBufferObject);
    glBufferData(GL_ARRAY_BUFFER, vertexUVs.length * vertexUVs[0].sizeof, vertexUVs.ptr, GL_STREAM_DRAW);
    glEnableVertexAttribArray(uvVertexAttribLocation);
    glVertexAttribPointer(uvVertexAttribLocation, 2, GL_FLOAT, 0, 0, null);

    /* Bind texture */
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, font);
    glUniform1i(fontTexUniformLocation, 0);

    /* Draw */
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_STENCIL_TEST);
    glEnable(GL_BLEND);
    glDisable(GL_CULL_FACE);
    glBlendFunc(GL_ONE, GL_ONE);
    glDrawArrays(GL_TRIANGLES, 0, w*h*3*2);

    /* Release GL resources */
    glDeleteVertexArrays(1, &vertexArrayObject);
    glDeleteBuffers(1, &positionBufferObject);
    glDeleteBuffers(1, &uvBufferObject);
  }
}
