/* Copyright 2014 Donny Viszneki. All rights reserved.
 * You are not authorized to distribute this source code.
 */
module ants.gametime;
import std.datetime : Clock;

struct GameTime
{
  static
  {
    private
    {
      ulong _gt;    /* game time */
      ulong _gtd;   /* game time delta */
      ulong _t;     /* ungame time */
      ulong _td;    /* ungame time delta */

      ulong _timePaused; /* when the game was paused, or 0 if not paused */
      ulong _gameTimeBase; /* time when game starts */
    }

    @property ulong  gt() { return _gt;  }
    @property ulong gtd() { return _gtd; }
    @property ulong   t() { return _t;  }
    @property ulong  td() { return _td;  }

    @property bool paused() { return _timePaused != 0; }

    static this()
    {
      _t = Clock.currStdTime()-10_000/60;
      start();
    }

    void start()
    {
      update();
      _gameTimeBase = _t;
      _timePaused = 0;
    }

    void pause()
    {
      if (paused())
        return;

      _timePaused = _t;
    }

    void unpause()
    {
      if (!paused())
        return;

      _gameTimeBase += _t - _timePaused;
      _timePaused = 0;
    }

    void update()
    {
      ulong t = Clock.currStdTime();
      _td = t - _t;
      _t = t;

      if (!paused())
      {
        _gt = _t - _gameTimeBase;
        _gtd = _td;
      }
    }
  }
}
