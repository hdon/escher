module ants.util;
import derelict.sdl2.sdl;
import derelict.sdl2.image;
import std.stdio;
import std.string;
import gl3n.linalg : Vector, cross;

alias vec3f = Vector!(float, 3);
alias vec4f = Vector!(float, 4);
alias vec4ub = Vector!(ubyte, 4);

vec4ub toVec4ub(vec4f v)
{
  return vec4ub(
    cast(ubyte)(v.r * 255)
  , cast(ubyte)(v.g * 255)
  , cast(ubyte)(v.b * 255)
  , cast(ubyte)(v.a * 255)
  );
}
vec4f toVec4f(vec4ub v)
{
  return vec4f(
    v.r / 255f
  , v.g / 255f
  , v.b / 255f
  , v.a / 255f
  );
}

SDL_Surface* loadImage(string filename)
{
  filename = "res/images/" ~ filename;
  writefln("loading image: \"%s\"", filename);
  auto res = IMG_Load(filename.toStringz);
  if (res is null)
    throw new Exception(format("failed to load image \"%s\"", filename));
  writefln("  found %d-bit color", res.format.BitsPerPixel);
  if (res.format.BitsPerPixel == 8)
    writefln("  found %d-color palette", res.format.palette.ncolors);
  return res;
}

T mod(T)(T n, T m) if (is(T == float) || is(T == double) || is(T == real))
{
  auto nm = n % m;
  return nm < cast(T) 0 ? nm + m : nm;
}

T clamp(T)(T l, T r, T v)
{
  return v < l ? l : v > r ? r : v;
}

T clamp(T)(T v) if (is(T == float))
{
  return clamp(0f, 1f, v);
}

bool sameTriangle(T)(T a0, T b0, T c0, T a1, T b1, T c1)
{
  if (a0 == a1)
    return b0 == b1 && c0 == c1;
  if (a0 == b1)
    return b0 == c1 && c0 == a1;
  if (a0 == c1)
    return b0 == a1 && c0 == b1;
  return false;
}

T anyPerpendicularVec(T)(T v)
{
  auto w = v;
  if (v.x != 0)
    w.y += 1;
  else if (v.y != 0)
    w.z += 1;
  else if (v.z != 0)
    w.x += 1;
  else return T();
  return cross(w, v);
}
