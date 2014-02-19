/* Copyright 2014 Donny Viszneki. All rights reserved.
 * You are not authorized to distribute this source code.
 */
module rescache2;
import std.stdio : writeln, writefln;
import std.typecons : Tuple, tuple;
import std.traits : ReturnType, ParameterTypeTuple, isPointer, isCallable;
import std.conv : to;

private void* xorptr(void* p)
{
  return cast(void*)(size_t.max ^ cast(size_t)p);
}

class Cache(alias Get, alias Del) if (isCallable!Get && isCallable!Del)
{
  private alias VT = ReturnType!Get;
  private alias KT = Tuple!(ParameterTypeTuple!Get);

  /* Cache record */
  static private class CR
  {
    bool unreachable;
    void* _h;
    VT _v;
    @property
    {
      Cache handle()         { return cast(Cache) xorptr(_h); }
      Cache handle(Cache h) { _h = xorptr(cast(void*) h); return h; }
    }
    this(VT v) { this._v = v; }
    this() {}
  }

  /* Where the cache lives */
  static private CR[KT] cache;

  /* The instance destructor marks the corresponding Cache Record
   * for clean up, and cleanup() calls the "underlying dtor" Del(),
   *
   * TODO Right now this mechanism is a little inefficient. It can
   *      be easily improved, though, which could ameliorate any
   *      problems with extra calls to cleanup().
   */
  private static bool needCleanup;
  ~this() { cr.unreachable = true; needCleanup = true; }
  static void cleanup()
  {
    if (needCleanup == false)
      return;

    KT[] keysToRemove;
    foreach (k, cr; cache)
    {
      if (cr.unreachable)
      {
        Del(cr._v);
        keysToRemove ~= k;
      }
    }
    foreach (k; keysToRemove)
      cache.remove(k);

    needCleanup = false;
  }

  static dumpCache()
  {
    writefln("dumping cache");
    if (cache.length == 0)
      writefln("  empty");
    foreach (k, cr; cache)
      writefln("  cache[%s] = CR(%s, %s, %s)",
        k, cr.unreachable, cr._h, cr._v);
  }

  /* What the user is mainly concerned with */
  static Cache get(KT.Types a...) {
    //writeln("get() ", tuple(a) in cache ? "hit ":"fault ", a);
    Cache handle;
    CR cr;

    if (tuple(a) in cache)
    {
      cr = cache[tuple(a)];
      handle = cr.unreachable ? new Cache(cr) : cr.handle;
      cleanup();
    }
    else
    {
      cleanup();
      VT v = Get(a);
      cr = new CR(v);
      handle = new Cache(cr);
      cache[tuple(a)] = cr;
    }

    return handle;
  }

  private CR cr;
  private VT _v; // trade a little memory for a little perf
  @property VT v() { return _v; }

  private this(CR cr)
  {
    cr.unreachable = false;
    this.cr = cr;
    this._v = cr._v;
    cr.handle = this;
  }
}
