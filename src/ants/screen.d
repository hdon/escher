/* Copyright 2014 Donny Viszneki. All rights reserved.
 * You are not authorized to distribute this source code.
 */
module ants.screen;
import ants.hudtext : HUDText;
import ants.main : display;
import ants.vertexer : vertexer;
import ants.shader : ShaderProgram;
import ants.gametime;
import ants.glutil;
import derelict.sdl2.sdl;
import derelict.opengl3.gl3;
import gl3n.linalg : Vector, Matrix;
import std.math : PI;
import std.algorithm : min, max;

import std.stdio : writeln;

private alias Vector!(double, 2) vec2d;
private alias Vector!(double, 3) vec3d;

private alias Vector!(float,  3) vec3f;

private alias Matrix!(double, 4, 4) mat4;

private alias Matrix!(float,  3, 3) mat3f;
private alias Matrix!(float,  4, 4) mat4f;

private template SingletonPattern(T)
{
  private static T singleton;
  public static @property T a()
  {
    if (singleton is null)
      singleton = new T();
    return singleton;
  }
}

class Screen
{
  Screen previous;
  static Screen current;
  void show() {
    if (current is null)
      GameTime.pause();
    this.previous = current;
    current = this;
  }
  void hide() {
    current = this.previous;
    if (current is null)
      GameTime.unpause();
  }
  abstract void draw();
  abstract bool handleEvent(SDL_Event* ev);
}

class PauseScreen : Screen
{
  HUDText[1] texts;

  this()
  {
    float pw = 7f * 16f;
    float ph = 1f * 16f;
    float sw = pw/display.width;
    float sh = ph/display.height;
    float x = ((display.width  - pw) /  2f) / display.width;
    float y = ((display.height - ph) / -2f) / display.height;
    texts[0] = new HUDText(7, 1, x, y, sw, sh);
    texts[0].print("Paused.");
  }

  override
  void draw()
  {
    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    glClearColor(.5, .5, .5, 1);
    glClear(GL_COLOR_BUFFER_BIT);

    glDisable(GL_DEPTH_TEST);
    glDisable(GL_BLEND);

    foreach (text; texts)
      text.draw();
  }

  override
  bool handleEvent(SDL_Event* ev)
  {
    if (ev.type == SDL_KEYDOWN)
    switch (ev.key.keysym.sym)
    {
      case SDLK_ESCAPE:
        hide();
        return false;
      case SDLK_s:
        StencilTestScreen.a.show();
        return false;
      case SDLK_c:
        CodebadLeadScreen.a.show();
        return false;
      default:
        return true;
    }
    return true;
  }
}

class StencilTestScreen : Screen
{
  mixin SingletonPattern!StencilTestScreen;

  ShaderProgram shaderProgram;
  this()
  {
    shaderProgram = new ShaderProgram("vert-color3--color4.vs", "frag-color4.fs");
  }

  override
  void draw()
  {
    int res;
    glErrorCheck();

    /*glGetFramebufferAttachmentParameteriv(
      GL_DRAW_FRAMEBUFFER,
      GL_DEPTH_STENCIL_ATTACHMENT,
      GL_FRAMEBUFFER_ATTACHMENT_STENCIL_SIZE,
      &res);*/
    //glGetFramebufferAttachmentParameteriv(GL_FRAMEBUFFER, GL_STENCIL, GL_FRAMEBUFFER_ATTACHMENT_STENCIL_SIZE, &res);
    glErrorCheck();
    //writefln("stencil bits: %d", res);

    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    glStencilMask(255);

    glClearColor(1, .5, .5, 1);
    glClearStencil(0);
    glClear(GL_COLOR_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);

    glDisable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);

    glEnable(GL_STENCIL_TEST);

    glStencilFunc(GL_NEVER, 0, 1);
    glStencilOp(GL_INCR, GL_INCR, GL_INCR);

    vertexer.add(vec3d(0, 0, 0), vec2d(0, 0), vec3d(0, 0, 0), vec3f(0, 1, 0));
    vertexer.add(vec3d(1, 0, 0), vec2d(0, 0), vec3d(0, 0, 0), vec3f(0, 1, 0));
    vertexer.add(vec3d(0, 1, 0), vec2d(0, 0), vec3d(0, 0, 0), vec3f(0, 1, 0));
    vertexer.draw(shaderProgram, mat4.identity, mat4.identity, null);

    glStencilFunc(GL_NOTEQUAL, 1, 1);
    glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP);

    vertexer.add(vec3d(-0.5, -0.5, 0), vec2d(0, 0), vec3d(0, 0, 0), vec3f(0, 0, 1));
    vertexer.add(vec3d( 0.5, -0.5, 0), vec2d(0, 0), vec3d(0, 0, 0), vec3f(0, 0, 1));
    vertexer.add(vec3d( 0.5,  0.5, 0), vec2d(0, 0), vec3d(0, 0, 0), vec3f(0, 0, 1));
    vertexer.draw(shaderProgram, mat4.identity, mat4.identity, null);
  }

  override
  bool handleEvent(SDL_Event* ev)
  {
    /* Ignore all events but keydown */
    if (ev.type != SDL_KEYDOWN)
      return true;

    switch (ev.key.keysym.sym)
    {
      case SDLK_ESCAPE:
        hide();
        return false;
      default:
        return true;
    }
  }
}

class CodebadLeadScreen : Screen
{
  alias LineSegment = uint[2];
  struct Vert { vec3f pos, col; }

  mixin SingletonPattern!CodebadLeadScreen;

  size_t radialSegments = 50;
  size_t strataSegments = 2;
  static Vert[] verts;
  static LineSegment[] lines;
  ShaderProgram shaderProgram;
  GLuint vbo;
  GLuint ibo;
  ulong startTime;

  this()
  {
    shaderProgram = new ShaderProgram("vert-color3--color4.vs", "frag-color4.fs");
  }

  override void show()
  {
    super.show();

    radialSegments = 50;
    strataSegments = 2;
    startTime = GameTime.t;

    glGenBuffers(2, &vbo);
  }

  override void hide()
  {
    super.hide();

    glDeleteBuffers(2, &vbo);
  }

  override bool handleEvent(SDL_Event* ev)
  {
    /* Ignore all events but keydown */
    if (ev.type != SDL_KEYDOWN)
      return true;

    switch (ev.key.keysym.sym)
    {
      case SDLK_ESCAPE:
        hide();
        return false;
      default:
        return true;
    }
  }

  enum radialSegmentsMax = 50;
  enum radialsPerSecond = 7.0 / 10_000_000.0;

  ulong oldRadialSegments;
  override void draw()
  {
    /* Do some calculation regarding timing and the animation sequence */
    auto now = GameTime.t - startTime;

    auto radialTime = min(46.0, now * radialsPerSecond);
    radialTime = 47.0; // XXX debug
    radialSegments = 50 - (~1 & cast(int)radialTime);
    if (radialSegments != oldRadialSegments)
      writeln("radial segments: %d", (oldRadialSegments=radialSegments));

    auto strataPerSecond = 7.0 / 4.0 / 10_000_000.0;
    auto strataTime = max(2.0, now * strataPerSecond) + 2.0;
    strataSegments = cast(int)strataTime;

    /* First create vertices */
    size_t nVerts = radialSegments * strataSegments;
    size_t iVert;
    size_t nIndices;

    /* Generate vertices (nVerts == nLines) */
    if (verts.length < nVerts)
    {
      verts.length = nVerts;
      lines.length = nVerts;
    }

    auto angleAll = 0.142 * radialsPerSecond * now;
    foreach (radial; 0..radialSegments)
    {
      auto angle = PI * radial * 2.0 / (50.0 - radialTime);// + angleAll;
      mat3f m = mat3f.identity;
      m.rotatez(angle);
      m.scale(.75, 1, 1);
      vec3f radialDirection = m * vec3f(0, 1, 0);

      float strataReciprocal = 1f / (strataSegments);
      foreach (strata; 0..strataSegments)
        verts[iVert++] = Vert(
          radialDirection * ((strata+1) * strataReciprocal),
          vec3f(0, 1, 0));
    }

    /* Generate primitives (line segments) */
    size_t iLine;
    foreach (radial; 0..radialSegments)
    {
      uint a = cast(uint)((radial+1) * strataSegments);
      uint b = cast(uint)(radial < radialSegments-1 ? a : 0);
      foreach (strata; 0..strataSegments)
        lines[iLine++] = [--a, b++];
    }

    //writefln("\ncodebad: radials=%d strata=%d", radialSegments, strataSegments);
    //foreach (v; verts)
      //writeln("codebad: vert: ", v);
    //foreach (l; lines)
      //writeln("codebad: line: ", l);

    /* Send data to GPU (nVerts is also number of lines) */
    glErrorCheck();
    glBindBuffer(GL_ARRAY_BUFFER, vbo);
    glBufferData(GL_ARRAY_BUFFER, nVerts * verts[0].sizeof, verts.ptr, GL_STREAM_DRAW);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, nVerts * lines[0].sizeof, lines.ptr, GL_STREAM_DRAW);
    glErrorCheck();

    /* Draw */
    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    glClearColor(0, .2, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    glErrorCheck();

    glDisable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);
    glErrorCheck();

    /* Activate shader program and parameterize our data */
    glErrorCheck();
    shaderProgram.use();

    auto posAL= shaderProgram.getAttribLocation("positionV");
    assert(posAL >= 0);
    glEnableVertexAttribArray(posAL);
    glVertexAttribPointer(posAL, 3, GL_FLOAT, GL_FALSE, verts[0].sizeof, cast(void*)verts[0].pos.offsetof);

    auto colAL = shaderProgram.getAttribLocation("colorV");
    assert(colAL >= 0);
    glEnableVertexAttribArray(colAL);
    glVertexAttribPointer(colAL, 3, GL_FLOAT, GL_FALSE, verts[0].sizeof, cast(void*)verts[0].col.offsetof);

    glDrawElements(GL_LINES, cast(GLsizei)(nVerts*2), GL_UNSIGNED_INT, cast(void*)0);

    glDisableVertexAttribArray(posAL);
    glDisableVertexAttribArray(colAL);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
    glUseProgram(0);
    glErrorCheck();
  }
}

