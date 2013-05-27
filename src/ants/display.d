module display;

import ants.md5 : MD5Model, MD5Animation;
import std.stdio : writeln;
import std.string : toStringz;
import derelict.sdl.sdl;
import derelict.opengl.gl;
import derelict.opengl.glu;

class Display
{
  private {
    uint height;
    uint width;
    uint bpp;
    float fov;
    float znear;
    float zfar;
    MD5Model model;
    MD5Animation anim;

    void setupGL()
    {
      glMatrixMode(GL_PROJECTION);
      glLoadIdentity();
      gluPerspective(fov, cast(float)width/height, znear, zfar);
      glMatrixMode(GL_MODELVIEW);
      glLoadIdentity();
      glDisable(GL_DEPTH_TEST);
      glDisable(GL_BLEND);
    }

    void init()
    {
      DerelictSDL.load();
      DerelictGL.load();
      DerelictGLU.load();
      assert(SDL_Init(SDL_INIT_VIDEO|SDL_INIT_TIMER) == 0);
      SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
      assert(SDL_SetVideoMode(width, height, bpp, SDL_OPENGL | SDL_DOUBLEBUF) !is null);
      SDL_WM_SetCaption(toStringz("D is the best"), null);

      model = new MD5Model("/home/donny/test-md5/test.md5mesh");
      anim = new MD5Animation(model, "/home/donny/test-md5/test.md5anim");

      setupGL();
    }
  }

  this()
  {
    width = 800;
    height = 600;
    bpp = 24;
    znear = 0.1f;
    zfar = 100.0f;
    fov = 90.0f;
    init();
  }

  ~this()
  {
    //cleanup();
  }

  static void cleanup()
  {
    SDL_Quit();
    DerelictGLU.unload();
    DerelictGL.unload();
    DerelictSDL.unload();
  }

  void clear()
  {
    glClear(GL_COLOR_BUFFER_BIT);
  }

  void drawGLFrame()
  {
    setupGL();

    anim.draw();

    SDL_GL_SwapBuffers();

    GLenum err = glGetError();
    assert(err == 0);
  }

  bool event()
  {
    bool isRunning = true;
    SDL_Event event;
    while (SDL_PollEvent(&event))
    {
      switch (event.type)
      {
        case SDL_QUIT:
          isRunning = false;
          break;
        default:
          break;
      }
    }
    return isRunning;
  }
}
