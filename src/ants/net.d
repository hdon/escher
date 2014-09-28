/* Copyright 2014 Donny Viszneki. All rights reserved.
 * You are not authorized to distribute this source code.
 */
module ants.net;
import std.stdio;
import std.string;
import std.concurrency;
import core.thread : thread_attachThis, thread_detachThis;
import core.time : dur;
import derelict.enet.enet;
import derelict.util.exception : DerelictShouldThrow = ShouldThrow;

DerelictShouldThrow derelictMissingSymbolCallback(string sym)
{
  return DerelictShouldThrow.No;
}

version (escherClient)
{
  __gshared Tid netTid;
  struct MessageConnect
  {
    string remoteHostname;
  }
  struct MessageConnectionStatusChange
  {
    bool connected;
  }
  struct MessageChat
  {
    string chat;
  }
  /* Ideally both receive() and enet_host_service() could be coupled and we could wait on
   * i/o from either in the same thread. Because the information we receive from the server
   * is primarily important for updating what will be rendered to the screen, we prioritize
   * receiving updates from the server, but we will let the main thread (responsible for
   * rendering) provide us an interval on which check for messages from it.
   * TODO: Fix proposal 1: make this interval a setting the user can change.
   * TODO: Fix proposal 2: couple the i/o of receive() and enet_host_service().
   * dlang.org seems to imply that such a coupling might be a good target.
   * Quoting from http://dlang.org/phobos/std_concurrency.html
   * This is a low-level messaging API upon which more structured or restrictive APIs may be
   * built. The general idea is that every messageable entity is represented by a common
   * handle type (called a Cid in this implementation), which allows messages to be sent to
   * in-process threads, on-host processes, and foreign-host processes using the same
   * interface.
   * TODO: Fix proposal 3: replace enet with a different solution that allows this coupling.
   */
  struct MessageSetNetTimeout
  {
    ulong timeout;
  }

  private
  {
    __gshared
    {
      ENetHost *host;
      ENetAddress addr;
      ENetPeer *peer;
      ulong enetServiceTimeout;
    }

    shared static this()
    {
      DerelictENet.missingSymbolCallback = &derelictMissingSymbolCallback;
      DerelictENet.load();
      assert(enet_initialize() == 0);
    }

    void netThread()
    {
      if (netTid != thisTid)
      {
        assert(netTid == Tid.init);
        netTid = thisTid;
      }

      receive(
        (MessageConnect msg)
        {
          connect(msg.remoteHostname);
        },
        (MessageSetNetTimeout msg)
        {
          enetServiceTimeout = msg.timeout;
        }
      );
    }

    void connect(string remoteHostname)
    {
      host = enet_host_create(null, 1, 2, 57600/8, 14400/8);
      assert(host !is null);

      enet_address_set_host(&addr, remoteHostname.toStringz);
      addr.port = 13667;

      peer = enet_host_connect(host, &addr, 2, 0);
      if (peer is null)
      {
        writeln("error: enet_host_connect() failed\n");
      }
      else
      {
        writeln("connected.");
      }
    }
  }

  /* Another thread is responsible for receiving data from the net thread. This function is
   * responsible for doing that.
   */
  void idk()
  {
    receiveTimeout(dur!"msecs"(0),
      (MessageConnectionStatusChange msg)
      {
        writeln(msg.connected ? "connected!" : "disconnected!");
      },
      (MessageChat msg)
      {
        writeln("chat: ", msg.chat);
      }
    );
  }
}
