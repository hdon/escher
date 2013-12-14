module display;

import ants.md5 : MD5Model, MD5Animation;
import ants.escher : World, Camera, Entity, playerEntity, playerModel, playerAnimation;
import ants.doglconsole;
import std.stdio : writeln, writefln;
import std.string : toStringz, strlen, format;
import derelict.sdl2.sdl;
import derelict.sdl2.image;
import derelict.opengl3.gl3;
import gl3n.linalg : Vector, Matrix, Quaternion, dot, cross;
import std.math : PI;
import std.exception : enforce;
import std.conv : to;
import file = std.file;

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
    World world;
    Camera camera;
    DoglConsole console;

    GLuint glprogram;

    void setupGL()
    {
      //glMatrixMode(GL_PROJECTION);
      //glLoadIdentity();
      //gluPerspective(fov, cast(float)width/height, znear, zfar);
      //glOrtho(-1, 1, -1, 1, -1, 1);
      //glMatrixMode(GL_MODELVIEW);
      //glLoadIdentity();
      glDisable(GL_DEPTH_TEST);
      glDisable(GL_BLEND);
    }

    SDL_Window* displayWindow;
    SDL_Renderer* displayRenderer;
    SDL_GLContext displayContext;

    void init()
    {
      SDL_RendererInfo displayRendererInfo;
      GLenum err;
      GLint iresult;
      GLboolean bresult;

      DerelictSDL2.load();
      DerelictSDL2Image.load();
      DerelictGL3.load();
      assert(SDL_Init(SDL_INIT_VIDEO|SDL_INIT_TIMER) == 0);

      /* Code from: https://gist.github.com/exavolt/2360410 */
      SDL_CreateWindowAndRenderer(800, 600, SDL_WINDOW_OPENGL, &displayWindow, &displayRenderer);
      SDL_GetRendererInfo(displayRenderer, &displayRendererInfo);
      /*TODO: Check that we have OpenGL */
      if ((displayRendererInfo.flags & SDL_RENDERER_ACCELERATED) == 0 ||
          (displayRendererInfo.flags & SDL_RENDERER_TARGETTEXTURE) == 0) {
        /*TODO: Handle this. We have no render surface and not accelerated. */
      }

      displayContext = SDL_GL_CreateContext(displayWindow);
      SDL_GL_MakeCurrent(displayWindow, displayContext);

      DerelictGL3.reload();

      displayContext = SDL_GL_CreateContext(displayWindow);
      SDL_GL_MakeCurrent(displayWindow, displayContext);

      const char *glVersion = glGetString(GL_VERSION);
      writeln("OpenGL version: ", to!string(glVersion));

      const char *glslVersion = glGetString(GL_SHADING_LANGUAGE_VERSION);
      writeln("Shader version: ", to!string(glslVersion));

      SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 0);
      SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 8);
      //SDL_WM_SetCaption(toStringz("D is the best"), null);

      world = new World(mapfilename);
      camera = new Camera(world, 0, vec3(0,0,0));
      playerModel = new MD5Model("res/md5/arms-anim0.md5mesh");
      playerAnimation = new MD5Animation(playerModel, "res/md5/arms-anim0.md5anim");
      playerEntity = new Entity();

      setupGL();

      console = new DoglConsole(width/16, height/16);
      console.handleCommand = &command;
    }
  }

  void command(DoglConsole console, string cmd)
  {
    writefln("display.d got command from console: %s\n", cmd);
    console.print(format("display.d got command from console: %s\n", cmd));
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
    DerelictGL3.unload();
    DerelictSDL2.unload();
  }

  uint lastFrame;

  void drawGLFrame()
  {
    uint t = SDL_GetTicks();
    uint delta = t - lastFrame;

    SDL_GL_MakeCurrent(displayWindow, displayContext);
    setupGL();

    camera.update(delta);
    camera.draw();

    console.draw();

    SDL_RenderPresent(displayRenderer);
    SDL_GL_SwapWindow(displayWindow);

    lastFrame = t;
  }

  bool event()
  {
    bool isRunning = true;
    SDL_Event event;
    while (SDL_PollEvent(&event))
    {
      if (console.handleSDLEvent(&event))
      switch (event.type)
      {
        case SDL_QUIT:
          isRunning = false;
          break;
        case SDL_KEYDOWN:
          if (event.key.keysym.sym == 'p' || event.key.keysym.sym == 'o')
          {
            if (event.type == SDL_KEYDOWN)
            {
              int delta = event.key.keysym.sym == 'p' ? 1 : -1;
              int oldSpaceID = camera.spaceID;
              camera.spaceID = cast(int)((camera.spaceID + world.spaces.length + delta) % world.spaces.length);
              camera.pos = vec3(0,0,0);
              writefln("[warp] %d to %d", oldSpaceID, camera.spaceID);
            }
            break;
          }

          if (event.key.repeat == 0)
            camera.key(event.key.keysym.sym, event.key.state != 0);
          break;

        case SDL_KEYUP:
          if (event.key.keysym.sym == SDLK_ESCAPE)
          {
            isRunning = false;
            break;
          }

          if (event.key.keysym.sym == SDLK_p && event.type == SDL_KEYDOWN)
          {
            writeln("position: ", camera.pos);
            break;
          }

          if (event.key.repeat == 0)
            camera.key(event.key.keysym.sym, event.key.state != 0);
          break;

        default:
          break;
      }
    }

    // mouse look update
    int x, y;
    int w = width;
    int h = height;
    SDL_ShowCursor(false);
    SDL_GetMouseState(&x,&y);
    SDL_EventState(SDL_MOUSEMOTION, SDL_IGNORE);
    SDL_WarpMouseInWindow(displayWindow, cast(ushort)(width/2),cast(ushort)(height/2));
    SDL_EventState(SDL_MOUSEMOTION, SDL_ENABLE);

    double deltaYaw = (x-w/2)*-0.002;
    double deltaPitch = (y-h/2)*-0.002;
    //writefln("[MOUSE LOOK] %x %x %f %f", x, y, deltaYaw, deltaPitch);

    camera.camYaw += deltaYaw;
    camera.camPitch += deltaPitch;

    return isRunning;
  }
}
