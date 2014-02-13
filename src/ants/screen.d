module ants.screen;
import ants.hudtext : HUDText;
import ants.main : display;
import ants.gametime;
import derelict.sdl2.sdl;
import derelict.opengl3.gl3;
import gl3n.linalg : Vector;

import std.stdio : writefln;

private alias Vector!(float, 2) vec2;

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
    if (ev.type == SDL_KEYDOWN && ev.key.keysym.sym == SDLK_ESCAPE)
    {
      hide();
      return false;
    }
    return true;
  }
}
