module ants.rescache;

mixin template ResourceCacheMixin(T, KT=string)
{
  /* TODO this kind of pointer obfuscation is WRONG. It should work
   *      for now BUT it may not work forever. D says that some day
   *      there may be a copying/moving garbage collector that defrags
   *      the heap. One of the responsibilities of such a GC is to
   *      adjust pointers to the new addresses, but it can't do that
   *      if it can't see them!
   *  XXX */
  union ResourcePtr
  {
    Resource r;
    size_t p;
  }

  struct ResourcePionter
  {
    ResourcePtr u;
    bool dead;

    this(Resource r)
    {
      u.r = r;
      u.p ^= cast(size_t)-1;
      dead = false;
    }

    Resource get()
    {
      if (dead)
        return null;
      auto rp = u;
      rp.p ^= cast(size_t)-1;
      return rp.r;
    }
  }

  protected static ResourcePionter[KT] arr;

  static Resource get(KT k)
  {
    /* TODO don't remove then iterate again;
            mleise in #d told me that will
            invalidate the iterator
     */
    foreach (k2, v; arr)
    {
      if (v.dead)
      {
        arr.remove(k2);
        freeResource(v.get());
      }
    }

    if (!(k in arr))
      arr[k] = ResourcePionter(loadResource(k));
    return arr[k].get();
  }

  static void forget(KT k)
  {
    arr[k].dead = true;
  }

  mixin template ResourceMixin(T=T,KT=KT)
  {
    T v;
    KT k;

    alias v this;

    this(KT k, T v)
    {
      this.k = k;
      this.v = v;
    }

    ~this()
    {
      debug writefln("[debug] rescache.ResourceMixin dtor: k/v = %x/%v", k, v);
      forget(this.k);
    }
  }
}
