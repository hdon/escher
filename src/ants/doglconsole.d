/* Copyright 2014 Donny Viszneki. All rights reserved.
 * You are not authorized to distribute this source code.
 */
module ants.doglconsole;
import std.stdio : write;
import derelict.opengl3.gl3;
import derelict.sdl2.sdl;
import ants.texture;
import ants.shader;
import ants.ascii : holdShift, capsLocked;

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

class DoglConsole
{
  bool visible;
  GLuint font;
  ShaderProgram shaderProgram;
  void delegate(DoglConsole console, string cmd) handleCommand;

  uint w, h, front, inbufCursor;
  char[] buf;
  char[] inbuf;
  vec2[] vertexPositions;
  vec2[] vertexUVs;

  this(uint w, uint h)
  {
    shaderProgram = new ShaderProgram("doglconsole.vs", "doglconsole.fs");
    redimension(w, h);

    font = getTexture("font850.png");
    // TODO this is bullshit and should be done elsewhere but for now it's easy to do here
    glBindTexture(GL_TEXTURE_2D, font);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAX_ANISOTROPY_EXT, 1);
  }

  void redimension(uint w, uint h)
  {
    this.w = w;
    this.h = h;

    buf.length = 0;
    buf.length = w*(h-1);

    inbuf.length = 0;
    inbuf.length = w;
    inbufCursor = 0;

    vertexUVs.length = 0;
    vertexUVs.length = w*h*6;

    vertexPositions.length = 0;
    vertexPositions.length = w*h*6;

    float rH = 1f/h;
    float rW = 1f/w;
    float y0, y1, x0, x1;
    y1 = 0f;
    for (uint y=0; y<h; y++)
    {
      y0 = y1;
      y1 = -rH*(y+1);
      x1 = 0f;
      for (uint x=0; x<w; x++)
      {
        x0 = x1;
        x1 = rW*(x+1);
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
    write("[console] ", text);
    uint cursor = front;
    foreach (char c; text)
    {
      if (c == '\0')
        {}
      if (c == '\n')
        cursor = (cursor / w + 1) * w;
      else
        buf[cursor++] = c;
      if (cursor >= buf.length)
        cursor = 0;
    }
    front = cursor;
  }

  void draw()
  {
    if (!visible)
      return;

    float r = 1f/16f;
    uint frontY = front/w;
    uint Y=frontY;
    for (uint y=0; y<h; y++)
    {
      if (Y >= (h-1))
        Y = 0;

      for (uint x=0; x<w; x++)
      {
        char c;
        if (y == h-1)
          c = inbuf[x];
        else
          c = buf[Y*w+x];
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

      ++Y;
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
    glDisable(GL_BLEND);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_STENCIL_TEST);
    glDisable(GL_CULL_FACE);
    glDrawArrays(GL_TRIANGLES, 0, w*h*3*2);

    /* Release GL resources */
    glDeleteVertexArrays(1, &vertexArrayObject);
    glDeleteBuffers(1, &positionBufferObject);
    glDeleteBuffers(1, &uvBufferObject);
  }

  /* Returns true if event requires further processing outside the scope of DoglConsole */
  bool handleSDLEvent(SDL_Event* event)
  {
    if (event.type != SDL_KEYDOWN)
      return true;

    int key = event.key.keysym.sym;
    
    if (!visible)
    {
      if (key == '`')
      {
        visible = true;
        return false;
      }
      return true;
    }

    if (key == SDLK_RETURN)
    {
      if (inbufCursor != 0)
      {
        handleCommand(this, inbuf[0..inbufCursor].idup);
        for (auto i=0; i<inbufCursor; i++)
          inbuf[i] = '\0';
        inbufCursor = 0;
      }
      return false;
    }

    if (key == SDLK_BACKSPACE)
    {
      if (inbufCursor != 0)
        inbuf[--inbufCursor] = '\0';
      return false;
    }

    if (key == '`')
    {
      visible = false;
      return false;
    }

    if (key >= ' ' && key <= '~')
    {
      //print(format("You pressed %c\n", cast(char)key));
      if (event.key.keysym.mod & KMOD_SHIFT)
        key = holdShift(cast(char)key);
      else if (event.key.keysym.mod & KMOD_CAPS)
        key = capsLocked(cast(char)key);
      inputInsertChar(cast(char)key);
    }
    return false;
  }

  void inputInsertChar(char c)
  {
    inbuf[inbufCursor++] = c;
  }
}
