module ants.client;

import std.stdio;
import std.string : splitLines, split, toStringz, format, strlen;
import std.conv : to;
import std.algorithm : startsWith;
import std.process : getenv;
import std.functional : toDelegate;
import file = std.file;
import std.math : PI;
import std.exception : enforce;
import core.memory : GC;
import ants.md5 : MD5Model, MD5Animation;
import ants.escher : World, Camera, playerEntity;
import ants.entity : EntityPlayer, EntityBendingBar, loadEntityAssets;
import ants.doglconsole;
import ants.commands;
import ants.hudtext : HUDText;
import ants.screen;
import ants.gametime;
import ants.glutil;
import derelict.util.exception : DerelictShouldThrow = ShouldThrow;
import derelict.sdl2.sdl;
import derelict.sdl2.image;
import derelict.opengl3.gl3;
import gl3n.linalg : Vector, Matrix, Quaternion, dot, cross;
version (Windows) import core.sys.windows.windows : MessageBoxA;

alias Vector!(double, 2) vec2;
alias Vector!(double, 3) vec3;
alias Vector!(double, 4) vec4;
alias Matrix!(double, 4, 4) mat4;
alias Quaternion!(double) quat;

void message(string message)
{
  version (Windows)
  {
    MessageBoxA(null, message.toStringz(), "Escher Game Engine".toStringz(), 0x00000000L);
  }
  else
  {
    writeln(message);
  }
}

World world;
Camera camera;
DoglConsole console;
PauseScreen pauseScreen;
uint height;
uint width;
string mapfilename;
uint bpp;
float fov;
float znear;
float zfar;
HUDText profileHUD;
HUDText crosshairHUD;
SDL_Window* displayWindow;
SDL_GLContext displayContext;

DerelictShouldThrow derelictMissingSymbolCallback(string sym)
{
  return DerelictShouldThrow.No;
}

int main(string[] args)
{
  version (Windows)
  {
    stdout.open("stdout.txt", "w");
    stderr.open("stderr.txt", "w");
  }

  if (args.length > 2)
  {
    message("Please invoke with zero or one arguments");
    return 1;
  }

  try
  {
    GLenum err;
    GLint iresult;
    GLboolean bresult;

    width = 800;
    height = 600;
    bpp = 24;
    znear = 0.1f;
    zfar = 100.0f;
    fov = 90.0f;

    /* Load some libraries at runtime */
    DerelictSDL2.missingSymbolCallback = &derelictMissingSymbolCallback;
    DerelictSDL2.load();
    scope(exit) DerelictSDL2.unload();

    DerelictSDL2Image.missingSymbolCallback = &derelictMissingSymbolCallback;
    DerelictSDL2Image.load();
    scope(exit) DerelictSDL2Image.unload();

    DerelictGL3.load();
    scope(exit) DerelictGL3.unload();

    assert(SDL_Init(SDL_INIT_VIDEO|SDL_INIT_TIMER) == 0);
    scope(exit) SDL_Quit();


    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
    SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24);
    SDL_GL_SetAttribute(SDL_GL_RED_SIZE, 8);
    SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, 8);
    SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, 8);
    SDL_GL_SetAttribute(SDL_GL_ALPHA_SIZE, 8);
    SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 8);
    //SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);

    displayWindow = SDL_CreateWindow("Escher Game Engine".toStringz(),
      SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, 800, 600, SDL_WINDOW_OPENGL);
    displayContext = SDL_GL_CreateContext(displayWindow);
    SDL_GL_SetSwapInterval(0); // disable vsync
    //SDL_GL_MakeCurrent(displayWindow, displayContext);

    DerelictGL3.reload();

    GLint res;
    glGetFramebufferAttachmentParameteriv(GL_FRAMEBUFFER, GL_STENCIL, GL_FRAMEBUFFER_ATTACHMENT_STENCIL_SIZE, &res);
    writefln("stencil bits: %d", res);

    displayContext = SDL_GL_CreateContext(displayWindow);
    SDL_GL_MakeCurrent(displayWindow, displayContext);

    const char *glVersion = glGetString(GL_VERSION);
    writeln("OpenGL version: ", to!string(glVersion));

    const char *glslVersion = glGetString(GL_SHADING_LANGUAGE_VERSION);
    writeln("Shader version: ", to!string(glslVersion));

    loadEntityAssets();

    glDisable(GL_DEPTH_TEST);
    glDisable(GL_BLEND);

    console = new DoglConsole(width/8, height/8);
    console.handleCommand = toDelegate(&doCommand);

    profileHUD = new HUDText(45, 8, 0, 0, 45f*16f/width, 8f*16f/height);
    profileHUD.print("Hello!");

    float pw = 1f * 16f;
    float ph = 1f * 16f;
    float sw = pw/width;
    float sh = ph/height;
    float x = ((width  - pw) /  2f) / width;
    float y = ((height - ph) / -2f) / height;

    crosshairHUD = new HUDText(1, 1, x, y, sw, sh);
    crosshairHUD.print("\xc5");

    pauseScreen = new PauseScreen();

    if (args.length == 1)
    {
      doCommandFile(console, "init.txt");
    }
    else
    {
      auto filename = args[1];
      auto fileContent = cast(char[])file.read(filename);
      if (fileContent.startsWith("escher script version 2\n"))
        doCommandFile(console, filename, to!string(fileContent[24..$]), 2);
      // TODO instead invoke some load map command that can use the already
      //      read-in content of the map file.
      else if (fileContent.startsWith("escher version"))
        doCommand(console, "map " ~ filename);
    }

    /* Load user's settings */
    auto rcPath = getenv("HOME") ~ "/.escherrc";
    try
    {
      doCommandFile(console, rcPath, "");
    }
    catch (file.FileException e)
    {
      console.print(format("Error loading user config script \"%s\": %s\n", rcPath, e.msg));
    }

    GC.collect();
    GC.disable();
    bool isRunning = true;
    while (isRunning)
    {
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
        int mx, my;
        int w = width;
        int h = height;
        SDL_ShowCursor(false);
        SDL_GetMouseState(&mx,&my);
        SDL_EventState(SDL_MOUSEMOTION, SDL_IGNORE);
        SDL_WarpMouseInWindow(displayWindow, cast(ushort)(width/2),cast(ushort)(height/2));
        SDL_EventState(SDL_MOUSEMOTION, SDL_ENABLE);

        camera.camYaw += camera.mousef * -(mx-w/2);
        camera.camPitch += camera.mousef * -(my-h/2);
      }

      GameTime.update();

      SDL_GL_MakeCurrent(displayWindow, displayContext);
        glDisable(GL_DEPTH_TEST);
        glDisable(GL_BLEND);

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
      GC.collect();
    }
    GC.enable();
    GC.collect();
  }
  catch (Throwable e)
  {
    stdout.write(to!string(e));
    stdout.writeln("\ncrashed!");
    message("Sorry, we've crashed! Please send the files \"stdout.txt\" and \"stderr.txt\" to don@codebad.com");
    return 1;
  }

  return 0;
}

