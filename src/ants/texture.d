module ants.texture;

import std.conv;
import std.string : toStringz;
import std.format : appender;
import ants.rescache;

struct TextureKey
{
  string filename;
  int frameNumber;
  
  this(string filename, int frameNumber)
  {
    this.filename = filename.idup;
    this.frameNumber = frameNumber;
  }

  const hash_t opHash()
  {
    return typeid(filename).getHash(&filename) ^ cast(hash_t)frameNumber;
  }

  const bool opEquals(ref const TextureKey other)
  {
    return std.string.cmp(filename, other.filename) == 0
        && frameNumber == other.frameNumber;
  }

  const int opCmp(ref const TextureKey other)
  {
    int r;
    r = std.string.cmp(filename, other.filename);
    if (r)
      return r;
    return frameNumber - other.frameNumber;
  }
}

mixin ResourceCacheMixin!(SDL_Texture*, TextureKey);

private Resource loadResource(TextureKey k)
{
  SDL_Texture* v = loadTexture(getGraphics(), k.filename, k.frameNumber);
  if (v is null)
    return null;
  return new Resource(k, v);
}

private void freeResource(SDL_Texture* v)
{
  debug writefln("texture.freeResource(%x)", v);
  if (v !is null)
    SDL_DestroyTexture(v);
}

private class Resource
{
  mixin ResourceMixin;
}

//alias get getTexture;
alias Resource TextureResource;

auto getTexture(Graphics graphicsContext, string filename, int frameNumber=0)
{
  return get(TextureKey(filename, frameNumber));
}

/// load a texture resource from the specified path
auto loadTexture(Graphics graphicsContext, string filename, int gifFrame=0) {
    // TODO Graphics is a struct and not a ref type
    //if (graphicsContext == null)
      graphicsContext = getGraphics();

    filename = "res/images/" ~ filename;

    /* Is the texture already loaded? */
    string textureName;
    if (gifFrame > 0) {
            auto writer = appender!string;
            formattedWrite(writer, "%s:%d", filename, gifFrame);
            textureName = writer.data;
    } else {
            textureName = filename;
    }

    debug writefln("[texture] loading \"%s\"", filename);

    SDL_Surface *surface;
    SDL_RWops *f;
    SDL_Texture* texture;

    scope(exit) { if (surface) SDL_FreeSurface(surface); surface = null; }
    scope(exit) { if (f) SDL_RWclose(f); f = null; }

    if (gifFrame > 0) {
            f = SDL_RWFromFile(toStringz(filename), "rb");
            enforce(f, "SDL_RWFromFile(\"%s\") failed", filename);
    }

    do {
            if (gifFrame > 0) {
                    debug writefln("[texture] IMG_LoadGIFFrame_RW()");

                    if (surface)
                            SDL_FreeSurface(surface);
                    surface = IMG_LoadGIFFrame_RW(f, gifFrame);

                    auto writer = appender!string();
                    formattedWrite(writer, "%s:%d", filename, gifFrame);
                    textureName = writer.data;
            } else {
                    /* Use SDL_Image lib to load the image into an SDL_Surface */
                    debug writefln("[texture] IMG_Load()");
                    surface = IMG_Load(toStringz(filename));
                    textureName = filename;
            }

            debug writefln("[texture] surface = %x", surface);
            if (!surface)
                    return null;

            debug writefln("[texture] image dimensions: %dx%d", surface.w, surface.h);

            /* Convert SDL_Surface to SDL_Texture */
            SDL_Texture* sdlTexture = SDL_CreateTextureFromSurface(graphicsContext.renderer, surface);

            // TODO this whole function needs reorganized
            return sdlTexture;

            debug writefln("[texture] storing frame %d from \"%s\" as \"%s\"", gifFrame, filename, textureName);
            texture = sdlTexture;

    } while (gifFrame > 0 && surface);

    return texture;
}
