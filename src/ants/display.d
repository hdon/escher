/* Copyright 2014 Donny Viszneki. All rights reserved.
 * You are not authorized to distribute this source code.
 */
module ants.display;

import ants.glutil;
import std.functional : toDelegate;
import ants.md5 : MD5Model, MD5Animation;
import ants.escher : World, Camera, playerEntity;
import ants.entity : EntityPlayer, EntityBendingBar, loadEntityAssets;
import ants.doglconsole;
import std.stdio : writeln, writefln;
import std.string : toStringz, strlen, format;
import derelict.sdl2.sdl;
import derelict.sdl2.image;
//import derelict.opengl3.gl3;
import glad.gl.all;
import glad.gl.loader;
import gl3n.linalg : Vector, Matrix, Quaternion, dot, cross;
import std.math : PI;
import std.exception : enforce;
import std.conv : to;
import file = std.file;
import ants.hudtext : HUDText;
import ants.commands : doCommand;
import ants.screen;
import ants.gametime;
import ants.glutil;

alias Vector!(double, 2) vec2;
alias Vector!(double, 3) vec3;
alias Vector!(double, 4) vec4;
alias Matrix!(double, 4, 4) mat4;
alias Quaternion!(double) quat;

class Display
{
  World world;
  Camera camera;
  DoglConsole console;
  PauseScreen pauseScreen;

  uint height;
  uint width;

  private {
    string mapfilename;
    uint bpp;
    float fov;
    float znear;
    float zfar;
    HUDText profileHUD;
    HUDText crosshairHUD;

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
    SDL_GLContext displayContext;

  }

  void init()
  {
    GLenum err;
    GLint iresult;
    GLboolean bresult;

    DerelictSDL2.load();
    DerelictSDL2Image.load();
    //DerelictGL3.load();
    assert(SDL_Init(SDL_INIT_VIDEO|SDL_INIT_TIMER) == 0);

//	glErrorCheck();
    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
    SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24);
    SDL_GL_SetAttribute(SDL_GL_RED_SIZE, 8);
    SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, 8);
    SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, 8);
    SDL_GL_SetAttribute(SDL_GL_ALPHA_SIZE, 8);
    SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 8);
    //SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);

//	glErrorCheck();
    displayWindow = SDL_CreateWindow("Escher Game Engine".toStringz(),
      SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, 800, 600, SDL_WINDOW_OPENGL);
    displayContext = SDL_GL_CreateContext(displayWindow);
    gladLoadGL(x => SDL_GL_GetProcAddress(x));
//	glErrorCheck();
    SDL_GL_SetSwapInterval(0); // disable vsync
    //SDL_GL_MakeCurrent(displayWindow, displayContext);

    //DerelictGL3.reload();

    GLint res;
//    glGetFramebufferAttachmentParameteriv(GL_FRAMEBUFFER, GL_STENCIL, GL_FRAMEBUFFER_ATTACHMENT_STENCIL_SIZE, &res);
//    writefln("stencil bits: %d", res);

	glErrorCheck();
    displayContext = SDL_GL_CreateContext(displayWindow);
    SDL_GL_MakeCurrent(displayWindow, displayContext);

	glErrorCheck();
    const char *glVersion = cast(const char *)glGetString(GL_VERSION);
    writeln("OpenGL version: ", to!string(glVersion));

	glErrorCheck();
    const char *glslVersion = cast(const char *)glGetString(GL_SHADING_LANGUAGE_VERSION);
    writeln("Shader version: ", to!string(glslVersion));

	glErrorCheck();
    loadEntityAssets();

	glErrorCheck();
    setupGL();

    console = new DoglConsole(width/8, height/8);
    console.handleCommand = toDelegate(&doCommand);

    profileHUD = new HUDText(45, 8, 0, 0, 45f*16f/width, 8f*16f/height);
    profileHUD.print("Hello!");

    float pw = 1f * 16f;
    float ph = 1f * 16f;
    float sw = pw/display.width;
    float sh = ph/display.height;
    float x = ((display.width  - pw) /  2f) / display.width;
    float y = ((display.height - ph) / -2f) / display.height;

    crosshairHUD = new HUDText(1, 1, x, y, sw, sh);
    crosshairHUD.print("\xc5");

    pauseScreen = new PauseScreen();
  }

  this()
  {
    width = 800;
    height = 600;
    bpp = 24;
    znear = 0.1f;
    zfar = 100.0f;
    fov = 90.0f;
  }

  ~this()
  {
    //cleanup();
  }

  static void cleanup()
  {
    SDL_Quit();
    //DerelictGL3.unload();
    DerelictSDL2.unload();
  }

  void drawGLFrame()
  {
    GameTime.update();

    SDL_GL_MakeCurrent(displayWindow, displayContext);
    setupGL();

    //anim.draw();
    //world.draw();
    profileHUD.print(format(
`fps: %3.3s
dt: %2.4s ms
w: %2.4s ms
a: %2.4s ms
c: %2.4s ms
x: %3.3s
y: %3.3s
z: %3.3s
`,
      10_000_000.0 / GameTime.td,
      GameTime.td / 10_000.0,
      camera.profileDrawWorld,
      camera.profileDrawArms,
      camera.profileCollision,
      camera.pos.x,
      camera.pos.y,
      camera.pos.z
      ));

    if (Screen.current !is null)
    {
      Screen.current.draw();
    }
    else
    {
      camera.update();
      camera.draw();
      profileHUD.draw();
      crosshairHUD.draw();
    }
    console.draw();

    SDL_GL_SwapWindow(displayWindow);
  }

  bool event()
  {
    bool isRunning = true;
    SDL_Event event;
    while (SDL_PollEvent(&event))
    {
      if (console.handleSDLEvent(&event) && (Screen.current is null || Screen.current.handleEvent(&event)))
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
          else if (event.key.keysym.sym == '5')
          {
            MD5Animation.optRenderSoftware = ! MD5Animation.optRenderSoftware;
            console.print(format("MD5 Rendering mode: %sware\n",
              MD5Animation.optRenderSoftware?"soft":"hard"));
            break;
          }
          else if (event.key.keysym.sym == SDLK_ESCAPE)
          {
            pauseScreen.show();
            SDL_ShowCursor(true);
            break;
          }
          else if (event.key.keysym.sym == 'q' && (event.key.keysym.mod & KMOD_CTRL))
          {
            isRunning = false;
            break;
          }
          /* LOL XXX * /
          else if (event.key.keysym.sym == SDLK_KP_PLUS)
          {
            if (world.entities.length > 0 && world.entities[0].length > 0)
            {
              auto e = cast(EntityBendingBar)world.entities[0][0];
              if (e !is null)
                e.anim.frameNumber = (e.anim.frameNumber+1)%e.anim.numFrames;
            }
          }
          /* LOL XXX * /
          else if (event.key.keysym.sym == SDLK_KP_MINUS)
          {
            if (world.entities.length > 0 && world.entities[0].length > 0)
            {
              auto e = cast(EntityBendingBar)world.entities[0][0];
              if (e !is null)
                e.anim.frameNumber = (e.anim.frameNumber-1+e.anim.numFrames)%e.anim.numFrames;
            }
          }*/
          if (event.key.repeat == 0)
            camera.key(event.key.keysym.sym, event.key.state != 0);
          break;

        case SDL_KEYUP:
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
    if (Screen.current is null)
    {
      int x, y;
      int w = width;
      int h = height;
      SDL_ShowCursor(false);
      SDL_GetMouseState(&x,&y);
      SDL_EventState(SDL_MOUSEMOTION, SDL_IGNORE);
      SDL_WarpMouseInWindow(displayWindow, cast(ushort)(width/2),cast(ushort)(height/2));
      SDL_EventState(SDL_MOUSEMOTION, SDL_ENABLE);

      camera.camYaw += camera.mousef * -(x-w/2);
      camera.camPitch += camera.mousef * -(y-h/2);
    }

    return isRunning;
  }
}
