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

import std.stdio : writefln;

private alias Vector!(double, 2) vec2d;
private alias Vector!(double, 3) vec3d;

private alias Vector!(float,  3) vec3f;

private alias Matrix!(double, 4, 4) mat4;

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
    return true;
  }
}
