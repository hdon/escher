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
private alias Vector!(float, 3) vec3;

private struct Vert {
  vec2 pos;
  vec2 uv;
  vec3 color;
}

class DoglConsole
{
  bool visible;
  bool stdoutEcho;
  GLuint font;
  ShaderProgram shaderProgram;
  void delegate(DoglConsole console, string cmd) handleCommand;

  uint w, h, front, inbufCursor;
  char[] buf;
  vec3[] cbuf;
  char[] inbuf;
  Vert[] verts;
  vec3 color;

  this(uint w, uint h)
  {
    color = vec3(.7f,.7f,.7f);
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

    cbuf.length = 0;
    cbuf.length = w*(h-1);

    inbuf.length = 0;
    inbuf.length = w;
    inbufCursor = 0;

    // TODO optimize this out with explicit initialization or something
    verts.length = 0;
    verts.length = w*h*6;

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

        verts[n+0].pos = vec2(x0, y0);
        verts[n+1].pos = vec2(x1, y0);
        verts[n+2].pos = vec2(x0, y1);

        verts[n+3].pos = verts[n+2].pos;
        verts[n+4].pos = verts[n+1].pos;
        verts[n+5].pos = vec2(x1, y1);
      }
    }
  }

  void printlnc(vec3 color, string text)
  {
    auto save = this.color;
    this.color = color;
    println(text);
    this.color = save;
  }

  void println(string text)
  {
    print(text);
    front = (front / w + 1) * w;
    if (front >= buf.length)
      front = 0;
    clearToEndOfLine();
    if (stdoutEcho)
      write('\n');
  }

  void printErrorMessage(string text)
  {
    printc(vec3(1, .5, .5), "ERROR\x13 ");
    printlnc(vec3(.7, .45, .45), text);
  }

  void printWarningMessage(string text)
  {
    printc(vec3(.7, .7, .4), "WARNING\x13 ");
    printlnc(vec3(.6, .6, .35), text);
  }

  void printc(vec3 color, string text)
  {
    auto save = this.color;
    this.color = color;
    print(text);
    this.color = save;
  }

  string cleanupText(string text)
  {
    char[] s = text.dup;
    foreach (ref c; s)
    {
      switch (c)
      {
        default:
          break;
        case '\x13':
          c = '!';
          break;
        case '\xaf':
          c = '>';
          break;
      }
    }
    return to!string(s);
  }

  void print(string text)
  {
    if (stdoutEcho)
    {
      version (Windows)
        write("[console] ", text);
      else
        write("[console] ", cleanupText(text));
    }

    uint cursor = front;
    foreach (char c; text)
    {
      if (c == '\0')
        {}
      else if (c == '\n') {
        cursor = (cursor / w + 1) * w;
        clearToEndOfLine();
      } else {
        buf[cursor] = c;
        cbuf[cursor] = color;
        cursor++;
      }
      if (cursor >= buf.length)
        cursor = 0;
    }
    front = cursor;
  }

  void clearToEndOfLine()
  {
    foreach (i; front .. (front / w + 1) * w)
    {
      buf[i] = '\0';
    }
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
        vec3 color;
        char c;
        if (y == h-1)
        {
          c = inbuf[x];
          color = vec3(.5f, 1f, .5f);
        }
        else
        {
          c = buf[Y*w+x];
          color = cbuf[Y*w+x];
        }
        char cx = c%16;
        char cy = c/16;
        float x0 = r *  cx;
        float x1 = r * (cx+1);
        float y0 = r *  cy;
        float y1 = r * (cy+1);

        uint n = (y*w+x)*6;
        verts[n+0].uv = vec2(x0, y0);
        verts[n+1].uv = vec2(x1, y0);
        verts[n+2].uv = vec2(x0, y1);

        verts[n+3].uv = verts[n+2].uv;
        verts[n+4].uv = verts[n+1].uv;
        verts[n+5].uv = vec2(x1, y1);

        verts[n+0].color = color;
        verts[n+1].color = color;
        verts[n+2].color = color;
        verts[n+3].color = color;
        verts[n+4].color = color;
        verts[n+5].color = color;
      }

      ++Y;
    }

    GLuint vertexArrayObject;
    GLuint vbo;

    /* Vertex Attribute Locations */
    GLint positionVAL;
    GLint uvVAL;
    GLint colorVAL;

    GLuint fontTexUniformLocation;

    shaderProgram.use();

    /* Get uniform locations */
    fontTexUniformLocation = shaderProgram.getUniformLocation("font");

    /* Get vertex attribute locations */
    positionVAL = shaderProgram.getAttribLocation("positionV");
    uvVAL = shaderProgram.getAttribLocation("uvV");
    colorVAL = shaderProgram.getAttribLocation("colorV");

    /* Generate arrays/buffers to send vertex data */
    glGenVertexArrays(1, &vertexArrayObject);
    glGenBuffers(1, &vbo);

    /* Send vertex data */
    glBindVertexArray(vertexArrayObject);

    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    /* TODO send buffer data only when there's been a change! */
    glBufferData(GL_ARRAY_BUFFER, verts.length * verts[0].sizeof, verts.ptr, GL_STREAM_DRAW);

    glEnableVertexAttribArray(positionVAL);
    glEnableVertexAttribArray(uvVAL);
    glEnableVertexAttribArray(colorVAL);

    glVertexAttribPointer(positionVAL, 2, GL_FLOAT, GL_FALSE, verts[0].sizeof, cast(void*) verts[0].pos.offsetof);
    glVertexAttribPointer(uvVAL,       2, GL_FLOAT, GL_FALSE, verts[0].sizeof, cast(void*) verts[0].uv.offsetof);
    glVertexAttribPointer(colorVAL,    3, GL_FLOAT, GL_FALSE, verts[0].sizeof, cast(void*) verts[0].color.offsetof);

    /* Bind texture */
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, font);
    glUniform1i(fontTexUniformLocation, 0);

    /* Draw */
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_STENCIL_TEST);
    glDisable(GL_CULL_FACE);
    glDrawArrays(GL_TRIANGLES, 0, w*h*3*2);

    /* Release GL resources */
    glDeleteVertexArrays(1, &vertexArrayObject);
    glDeleteBuffers(1, &vbo);
  }

  /* Returns true if event requires further processing outside the scope of DoglConsole */
  bool handleSDLEvent(SDL_Event* event)
  {
    if (event.type == SDL_KEYUP && visible)
      return false;

    if (event.type != SDL_KEYDOWN)
      return true;

    if ((event.key.keysym.mod & (KMOD_CTRL | KMOD_ALT | KMOD_GUI)) != 0)
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
