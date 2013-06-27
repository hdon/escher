module display;

import ants.md5 : MD5Model, MD5Animation;
import ants.escher : World, Camera;
import std.stdio : writeln, writefln;
import std.string : toStringz;
import derelict.sdl.sdl;
import derelict.opengl.gl;
import derelict.opengl.glu;
import gl3n.linalg : vec2d, vec3d, vec4d;
import std.math : PI, sin, cos;

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

    int viewMode;
    int actMode;
    Camera camera1, camera3;

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
      camera1 = new Camera(world, 0, vec3d(0,0,0));
      camera3 = new Camera(world, 0, vec3d(0,0,0));
      viewMode = 1;
      actMode = 1;

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
    camera1.update(delta);
    camera3.update(delta);

    Camera otherCamera;
    Camera currentCamera;
    if (viewMode == 1)
    {
      currentCamera = camera1;
      otherCamera = camera3;
    }
    else
    {
      currentCamera = camera3;
      otherCamera = camera1;
    }
    currentCamera.draw();

    glMatrixMode(GL_MODELVIEW);
    glPushMatrix();
    glLoadIdentity();
    glRotatef(currentCamera.angle/PI*-180f, 0, 1, 0);
    glTranslatef(-currentCamera.pos.x, -currentCamera.pos.y, -currentCamera.pos.z);

    glDisable(GL_BLEND);
    glDisable(GL_DEPTH_TEST);
    glBegin(GL_LINES);

    glColor3f(1, 0, 0);
    vec3d v = otherCamera.pos;
    glVertex3f(v.x, v.y, v.z);
    v += vec3d(sin(otherCamera.angle), 0, cos(otherCamera.angle));
    glColor3f(1, 1, 0);
    glVertex3f(v.x, v.y, v.z);

    glEnd();
    glEnable(GL_DEPTH_TEST);

    glMatrixMode(GL_MODELVIEW);
    glPopMatrix();

    SDL_GL_SwapBuffers();

    GLenum err = glGetError();
    assert(err == 0);

    lastFrame = t;
  }

  bool event()
  {
    Camera vcamera;
    if (actMode == 1)
      vcamera = camera1;
    else
      vcamera = camera3;

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
          switch (event.key.keysym.sym)
          {
            default:break;
            case SDLK_q:
            case SDLK_ESCAPE:
              isRunning = false;
              break;
            case SDLK_w:
            case SDLK_s:
            case SDLK_a:
            case SDLK_d:
              float f = 0f;
              if (event.key.keysym.sym == SDLK_w)
                f = -3f;
              else if (event.key.keysym.sym == SDLK_s)
                f = 3f;
              if (f != 0f)
              {
                vcamera.vel += event.type == SDL_KEYDOWN ? f : -f;
              }

              f = 0f;
              if (event.key.keysym.sym == SDLK_a)
                f = PI;
              else if (event.key.keysym.sym == SDLK_d)
                f = -PI;
              if (f != 0f)
              {
                vcamera.turnRate += event.type == SDL_KEYDOWN ? f : -f;
              }
              break;
            case SDLK_v:
              if (event.type == SDL_KEYUP)
                break;
              if (viewMode == 1)
                viewMode = 3;
              else
                viewMode = 1;
              writefln("[camera] view mode set to %d", viewMode);
              break;
            case SDLK_b:
              if (event.type == SDL_KEYUP)
                break;
              if (actMode == 1)
                actMode = 3;
              else
                actMode = 1;
              writefln("[camera] act mode set to %d", actMode);
              break;
          }
        default:
          break;
      }
    }
    return isRunning;
  }
}
