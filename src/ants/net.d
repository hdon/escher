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
   *
   * I did some more research into the source code for std.concurrency. Ultimately, we're
   * going to be waiting in core.sync.condition.Condition.wait(Duration). The Condition is
   * called std.concurrency.MessageBox.m_putMsg, and the MessageBox instance is the TLS
   * variable std.concurrency.mbox, which IIRC is instantiated when thisTid() is called.
   * So I should ask the #dlang freenode crowd about how to combine this with other types
   * of i/o.
   */
  struct MessageSetNetTimeout
  {
    uint timeout;
  }
  struct MessageError
  {
    string errorMessage;
  }
  struct MessageDisconnect { }

  private
  {
    ENetHost *host;
    ENetAddress remoteAddr;
    ENetPeer *peer;
    uint enetServiceTimeout;

    shared static this()
    {
      DerelictENet.missingSymbolCallback = &derelictMissingSymbolCallback;
      DerelictENet.load();
      assert(enet_initialize() == 0);
    }

    void netThread(string remoteHostname)
    {
      if (host is null)
        host = enet_host_create(null, 1, 2, 57600/8, 14400/8);
      assert(host !is null);

      enet_address_set_host(&remoteAddr, remoteHostname.toStringz);
      remoteAddr.port = 13667;

      peer = enet_host_connect(host, &remoteAddr, 2, 0);
      if (peer is null)
      {
        writeln("[net] error: enet_host_connect() failed");
        send(ownerTid, MessageError("error: enet_host_connect() failed"));
        return;
      }

      /* Network reactor */
      writeln("[net] Starting reactor");
      while (peer !is null)
      {
        /* Receive messages from main thread */
        receiveTimeout(dur!"msecs"(0),
          (MessageDisconnect msg)
          {
            enet_peer_disconnect(peer, 0xc0debad);
            peer = null;
          }
        );

        /* Transact network i/o */
        ENetEvent event;
        auto serviceStatus = enet_host_service(host, &event, enetServiceTimeout);
        assert(serviceStatus >= 0);
        if (serviceStatus > 0)
        {
          /* We got an event */
          writeln("[net] enet_host_service() > 0 -- we got an event!");
          switch (event.type)
          {
            case ENET_EVENT_TYPE_CONNECT:
              writeln("[net] connected");
              send(ownerTid, MessageConnectionStatusChange(true));
              break;
            case ENET_EVENT_TYPE_DISCONNECT:
              writeln("[net] disconnect");
              send(ownerTid, MessageConnectionStatusChange(false));
              break;
            case ENET_EVENT_TYPE_RECEIVE:
              writeln("[net] received data");
              enet_packet_destroy(event.packet);
              break;
          }
        }
      }
    }
  }

  /* Another thread is responsible for receiving data from the net thread. This function is
   * responsible for doing that.
   */
  void pump()
  {
    receiveTimeout(dur!"msecs"(0),
      (LinkTerminated msg)
      {
        writeln("\"LinkTerminated\"");
        assert(msg.tid == netTid);
        netTid = netTid.init;
      },
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

  Tid netTid;
  void connect(string remoteHostname)
  {
    /* TODO check if we already have a net thread running! */
    writeln("spawning net thread");
    netTid = spawnLinked(&netThread, "127.0.0.1");
  }

  void disconnect()
  {
    /* TODO check if netTid is valid */
    send(netTid, MessageDisconnect());
  }

  void shutdown()
  {
    writeln("asking net thread to disconnect...");
    prioritySend(netTid, MessageDisconnect());
    writeln("joining net thread...");
    receive((LinkTerminated msg){
      writeln("\"LinkTerminated\"");
      assert(msg.tid == netTid);
      netTid = netTid.init;
    });
    netTid = netTid.init;
    writeln("joined!");
  }
}
