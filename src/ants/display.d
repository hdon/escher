module display;

import ants.md5 : MD5Model, MD5Animation;
import ants.escher : World, Camera;
import std.stdio : writeln;
import std.string : toStringz;
import derelict.sdl.sdl;
import derelict.opengl.gl;
import derelict.opengl.glu;
import gl3n.linalg : Vector, Matrix, Quaternion, dot, cross;
import std.math : PI;

alias Vector!(double, 2) vec2;
alias Vector!(double, 3) vec3;
alias Vector!(double, 4) vec4;
alias Matrix!(double, 4, 4) mat4;
alias Quaternion!(double) quat;

class Display
{
  private {
    string mapfilename;
    uint height;
    uint width;
    uint bpp;
    float fov;
    float znear;
    float zfar;
    MD5Model model;
    MD5Animation anim;
    World world;
    Camera camera;

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

      //model = new MD5Model("monkey.md5mesh");
      //anim = new MD5Animation(model, "monkey.md5anim");

      world = new World(mapfilename);
      camera = new Camera(world, 0, vec3(0,0,0));

      //model = new MD5Model("/home/donny/test-md5/test4.md5mesh");
      //anim = new MD5Animation(model, "/home/donny/test-md5/test4.md5anim");
      //model = new MD5Model("/home/donny/Downloads/MD5ModelLoader/MD5ModelLoader/data/Boblamp/boblampclean.md5mesh");
      //anim = new MD5Animation(model, "/home/donny/Downloads/MD5ModelLoader/MD5ModelLoader/data/Boblamp/boblampclean.md5anim");

      setupGL();
    }
  }

  this(string filename)
  {
    this.mapfilename = filename;
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
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
  }

  uint lastFrame;

  void drawGLFrame()
  {
    uint t = SDL_GetTicks();
    uint delta = t - lastFrame;
    setupGL();

    //anim.draw();
    //world.draw();
    camera.update(delta);
    camera.draw();

    SDL_GL_SwapBuffers();

    GLenum err = glGetError();
    assert(err == 0);

    lastFrame = t;
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
        case SDL_KEYDOWN:
        case SDL_KEYUP:
          if (event.key.keysym.sym == SDLK_ESCAPE)
          {
            isRunning = false;
            break;
          }

          float f = 0f;
          // right-handed system means forward = -z
          if (event.key.keysym.sym == SDLK_w)
            f = -3f;
          else if (event.key.keysym.sym == SDLK_s)
            f = 3f;
          if (f != 0f)
          {
            camera.vel += event.type == SDL_KEYDOWN ? f : -f;
          }

          f = 0f;
          if (event.key.keysym.sym == SDLK_a)
            f = PI;
          else if (event.key.keysym.sym == SDLK_d)
            f = -PI;
          if (f != 0f)
          {
            camera.turnRate += event.type == SDL_KEYDOWN ? f : -f;
          }
          
          if (event.key.keysym.sym == SDLK_p && event.type == SDL_KEYDOWN)
          {
            writeln("position: ", camera.pos);
          }
        default:
          break;
      }
    }
    return isRunning;
  }
}
