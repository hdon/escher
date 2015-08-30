/* Copyright 2014 Donny Viszneki. All rights reserved.
 * You are not authorized to distribute this source code.
 */
module ants.doglconsole;
import std.stdio;
import std.algorithm : min, max;
import derelict.opengl3.gl3;
import derelict.sdl2.sdl;
import ants.texture;
import ants.shader;
import ants.ascii : holdShift, capsLocked;
import ants.util;
import ants.glutil;
import client = ants.client;

import gl3n.linalg : Vector;
private alias Vector!(float, 2) vec2;
private alias Vector!(float, 3) vec3;

private struct Vert {
  vec2 pos;
  vec2 uv;
  vec3 color;
}

enum DoglConsoleBackend
{
  None
, OpenGL
, SDLRenderer
}
pure nothrow bool isOpenGL     (DoglConsoleBackend backend) { return backend == DoglConsoleBackend.OpenGL;      }
pure nothrow bool isSDLRenderer(DoglConsoleBackend backend) { return backend == DoglConsoleBackend.SDLRenderer; }
pure nothrow bool isNone       (DoglConsoleBackend backend) { return backend == DoglConsoleBackend.None;        }

interface DoglConsole
{
  alias CommandHandler = void delegate(DoglConsole console, string cmd);

  void printErrorMessage(string text);
  void printWarningMessage(string text);
  void printlnc(vec3 color, string text);
  void printc(vec3 color, string text);
  void println(string text);
  void print(string text);
  void setCommandHandler(CommandHandler dg);
  void draw();
  void setCursorPosition(int x, int y);
  bool handleSDLEvent(SDL_Event* event);
  @property void alpha(float f);
  @property void visible(bool b);
  @property bool visible();
  @property void color(vec3 color);
  @property vec3 color();
  void setConsoleToggleKey(int key);
}

alias DoglConsoleOpenGL = CDoglConsole!(DoglConsoleBackend.OpenGL);
alias DoglConsoleSDLRenderer = CDoglConsole!(DoglConsoleBackend.SDLRenderer);
alias DoglConsoleNone = CDoglConsole!(DoglConsoleBackend.None);

class CDoglConsole(DoglConsoleBackend backend) : DoglConsole
{
  immutable bool noScrolling;
  immutable bool noEntry;

  bool _visible;
  @property void visible(bool b) { _visible = b; }
  @property bool visible() { return _visible; }

  bool stdoutEcho;
  CommandHandler handleCommand;

  static if (backend.isOpenGL)
  {
    GLuint font;
    ShaderProgram shaderProgram;
  }
  static if (backend.isSDLRenderer)
  {
    SDL_Renderer* sdlRenderer;
    SDL_Texture* font;
  }

  uint charsWide, charsTall, front, inbufCursor;
  private @property uint bufRows() { return noEntry ? charsTall : charsTall - 1; }
  uint screenX, screenY, screenW, screenH;

  char[] buf;
  vec3[] cbuf;
  char[] inbuf;
  Vert[] verts;

  vec3 _color;
  @property void color(vec3 color) { _color = color; }
  @property vec3 color() { return color; }

  float _alpha;
  bool fullAlpha;
  @property void alpha(float f) { _alpha = f; }
  float getCurrentAlpha() { return fullAlpha ? 1f : _alpha; }

  static if (backend.isOpenGL)
  {
    this(uint charsWide, uint charsTall, uint screenX, uint screenY, uint screenW, uint screenH,
         string fontFilename, bool noScrolling = false, bool noEntry = false)
    {
      this.noScrolling = noScrolling;
      this.noEntry   = noEntry;
      _alpha = 0.75;

      _color = vec3(.7f,.7f,.7f);

      shaderProgram = new ShaderProgram("vert-doglconsole.glsl", "frag-doglconsole.glsl");
      font = getTexture(fontFilename);
      // TODO this is bullshit and should be done elsewhere but for now it's easy to do here
      glBindTexture(GL_TEXTURE_2D, font);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
      glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAX_ANISOTROPY_EXT, 1);
      glBindTexture(GL_TEXTURE_2D, 0);

      constructorCommon(charsWide, charsTall, screenX, screenY, screenW, screenH);
    }
  }

  static if (backend.isSDLRenderer)
  {
    this(uint charsWide, uint charsTall, uint screenX, uint screenY, uint screenW, uint screenH,
         string fontFilename, SDL_Renderer* sdlRenderer, bool noScrolling = false, bool noEntry = false)
    {
      this.noScrolling = noScrolling;
      this.noEntry   = noEntry;
      _alpha = 0.75;

      _color = vec3(.7f,.7f,.7f);

      this.sdlRenderer = sdlRenderer;
      auto fontSurface = loadImage(fontFilename);

      font = SDL_CreateTexture(
        sdlRenderer,
        SDL_PIXELFORMAT_ABGR8888,
        SDL_TEXTUREACCESS_STREAMING,
        128, 128);

      if (font is null)
      {
        writefln("error: SDL_CreateTexture: %s", to!string(SDL_GetError()));
        assert(0);
      }

      SDL_UpdateTexture(font, null, cast(void*) fontSurface.pixels, fontSurface.pitch);

      SDL_FreeSurface(fontSurface);

      constructorCommon(charsWide, charsTall, screenX, screenY, screenW, screenH);
    }
  }

  static if (backend.isNone)
  {
    this(bool stdoutEcho = true)
    {
      this.stdoutEcho = stdoutEcho;
      noScrolling = true;
      noEntry = true;
    }
  }

  private void constructorCommon(
    uint charsWide, uint charsTall, uint screenX, uint screenY, uint screenW, uint screenH)
  {
    /* By default, if entry is disabled, we're visible */
    if (noEntry)
      _visible = true;

    /* idk */
    //if (noScrolling)
      //front = 1;

    this.screenX   = screenX;
    this.screenY   = screenY;
    this.screenW   = screenW;
    this.screenH   = screenH;

    toggleKey = '`';

    redimension(charsWide, charsTall);
  }

  void setConsoleToggleKey(int key)
  {
    toggleKey = key;
  }

  void setCommandHandler(CommandHandler handler)
  {
    handleCommand = handler;
  }

  void setCursorPosition(int x, int y)
  {
    front = y * bufRows + x;
  }

  void redimension(uint charsWide, uint charsTall)
  {
    this.charsWide = charsWide;
    this.charsTall = charsTall;

    buf.length = 0;
    buf.length = charsWide*(bufRows);

    cbuf.length = 0;
    cbuf.length = charsWide*(bufRows);

    if (!noEntry)
    {
      inbuf.length = 0;
      inbuf.length = charsWide;
      inbufCursor = 0;
    }

    // TODO optimize this out with explicit initialization or something
    verts.length = 0;
    verts.length = charsWide*charsTall*6;

    static if (backend.isOpenGL)
    {
      float minX = screenX / cast(float) client.width;
      float minY = screenY / cast(float) client.height;
      float rW = 8f / client.width;
      float rH = 8f / client.height;
      float y0, y1, x0, x1;
      y1 = -minY;
      for (uint y=0; y<charsTall; y++)
      {
        y0 = y1;
        y1 = -rH * (y+1) - minY;
        x1 = minX;
        for (uint x=0; x<charsWide; x++)
        {
          x0 = x1;
          x1 = rW * (x+1) + minX;
          uint n = (y*charsWide+x)*6;

          verts[n+0].pos = vec2(x0, y0);
          verts[n+1].pos = vec2(x1, y0);
          verts[n+2].pos = vec2(x0, y1);

          verts[n+3].pos = verts[n+2].pos;
          verts[n+4].pos = verts[n+1].pos;
          verts[n+5].pos = vec2(x1, y1);
        }
      }
    }
  }

  void printlnc(vec3 _color, string text)
  {
    auto save = this._color;
    this._color = _color;
    println(text);
    this._color = save;
  }

  void println(string text)
  {
    _color = vec3(1,1,1);
    print(text);
    print("\n");
    if (stdoutEcho)
      writeln();
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

  void printc(vec3 _color, string text)
  {
    auto save = this._color;
    this._color = _color;
    print(text);
    this._color = save;
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

    if (backend.isNone)
      return;

    uint cursor = front;
    foreach (char c; text)
    {
      /* TODO there is a bug in here. When the cursor gets to the end of a line, 
       * a newline at that point will cause a line to be skiped. Worse, it doesn't
       * even clear the skipped line.
       */
      if (c == '\0')
        {}
      else if (c == '\n') {
        if (cursor % charsWide == 0)
          clearToEndOfLine(cursor);
        cursor = (cursor / charsWide + 1) * charsWide;
      } else {
        if (cursor % charsWide == 0)
          clearToEndOfLine(cursor);
        buf[cursor] = c;
        cbuf[cursor] = _color;
        cursor++;
      }
      if (cursor >= buf.length)
        cursor = 0;
    }
    front = cursor;
  }

  void clearToEndOfLine() { clearToEndOfLine(front); }
  void clearToEndOfLine(uint cursor)
  {
    foreach (i; cursor .. (cursor / charsWide + 1) * charsWide)
    {
      buf[i] = '\0';
    }
  }

  static if (backend.isNone)
  {
    void draw() { }
  }

  static if (backend.isOpenGL)
  {
    void draw()
    {
      if (!_visible)
        return;

      float r = 1f/16f;
      uint frontY = noScrolling ? 0 : front/charsWide;
      uint Y=frontY;
      for (uint y=0; y<charsTall; y++)
      {
        if (Y >= bufRows)
          Y = 0;

        for (uint x=0; x<charsWide; x++)
        {
          vec3 color;
          char c;
          if (y == bufRows)
          {
            c = inbuf[x];
            color = vec3(.5f, 1f, .5f);
          }
          else
          {
            c = buf[Y*charsWide+x];
            color = cbuf[Y*charsWide+x];
          }
          char cx = c%16;
          char cy = c/16;
          float x0 = r *  cx;
          float x1 = r * (cx+1);
          float y0 = r *  cy;
          float y1 = r * (cy+1);

          uint n = (y*charsWide+x)*6;
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

      GLint fontTexUniformLocation;
      GLint alphaUL;

      shaderProgram.use();

      /* Get uniform locations */
      fontTexUniformLocation = shaderProgram.getUniformLocation("font");
      alphaUL                = shaderProgram.getUniformLocation("alpha");

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

      /* Send alpha uniform */
      glUniform1f(alphaUL, getCurrentAlpha);

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
      glDrawArrays(GL_TRIANGLES, 0, charsWide*charsTall*3*2);

      /* Release GL resources */
      glDeleteVertexArrays(1, &vertexArrayObject);
      glDeleteBuffers(1, &vbo);

      glErrorCheck();
    }
  }

  static if (backend.isSDLRenderer)
  {
    void draw()
    {
      if (!_visible)
        return;

      SDL_SetTextureBlendMode(font, SDL_BLENDMODE_BLEND);
      SDL_SetTextureAlphaMod(font, cast(ubyte)(255 * getCurrentAlpha));

      int screenY = this.screenY;
      int screenXDelta = screenW / this.charsWide;
      int screenYDelta = screenH / this.charsTall;
      auto dstRect = SDL_Rect(0, 0, cast(int)screenXDelta, cast(int)screenYDelta);
      auto srcRect = SDL_Rect(0, 0, 8, 8);
      int actualY = noScrolling ? 0 : front / charsWide;
      vec3 lastColor;
      foreach (charY; 0 .. charsTall)
      {
        dstRect.y = cast(int)(charY * screenYDelta) + this.screenY;
        foreach (charX; 0 .. charsWide)
        {
          if (actualY >= bufRows)
            actualY = 0;

          dstRect.x = cast(int)(charX * screenXDelta) + this.screenX;

          char ch;
          vec3 color;

          if (charY == bufRows)
          {
            ch    = inbuf[charX];
            color = vec3(.5f, 1f, .5f);
          }
          else
          {
            ch    = buf [actualY * charsWide + charX];
            color = cbuf[actualY * charsWide + charX];
          }

          srcRect.x = ch % 16 * 8;
          srcRect.y = ch / 16 * 8;
          if (lastColor != color)
          {
            SDL_SetTextureColorMod(font,
              cast(ubyte) (min(255f, max(0f, color.r * 255f)))
            , cast(ubyte) (min(255f, max(0f, color.g * 255f)))
            , cast(ubyte) (min(255f, max(0f, color.b * 255f)))
            );
            lastColor = color;
          }
          SDL_RenderCopy(sdlRenderer, font, &srcRect, &dstRect);
        }

        ++actualY;
      }
    }
  }

  /* Returns true if event requires further processing outside the scope of DoglConsole */
  int toggleKey;
  bool handleSDLEvent(SDL_Event* event)
  {
    if (noEntry)
      return true;

    if (event.type == SDL_KEYUP && _visible)
      return false;

    if (event.type != SDL_KEYDOWN)
      return true;

    if (_visible && (event.key.keysym.mod & KMOD_CTRL) != 0 && event.key.keysym.sym == 'o')
    {
      fullAlpha = ! fullAlpha;
      return false;
    }

    if ((event.key.keysym.mod & (KMOD_CTRL | KMOD_ALT | KMOD_GUI)) != 0)
      return true;

    int key = event.key.keysym.sym;
    
    if (!_visible)
    {
      if (key == toggleKey)
      {
        _visible = true;
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

    if (key == toggleKey)
    {
      _visible = false;
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
