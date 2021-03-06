/* Copyright 2014 Donny Viszneki. All rights reserved.
 * You are not authorized to distribute this source code.
 */
module ants.main;
import std.stdio;
import std.string : splitLines, split, toStringz, fromStringz, format;
import std.conv : to;
import std.algorithm : startsWith;
import std.process : environment;
import file = std.file;
import core.memory : GC;
import ants.display : Display;
import ants.commands;

version (Windows) import core.sys.windows.windows : MessageBoxA;

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

Display display;
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
    display = new Display();
    display.init();
    scope(exit) display.cleanup();

    if (args.length == 1)
    {
      doCommandFile(display.console, "init.txt");
    }
    else
    {
      auto filename = args[1];
      auto fileContent = cast(char[])file.read(filename);
      if (fileContent.startsWith("escher script version 2\n"))
        doCommandFile(display.console, filename, to!string(fileContent[24..$]), 2);
      // TODO instead invoke some load map command that can use the already
      //      read-in content of the map file.
      else if (fileContent.startsWith("escher version"))
        doCommand(display.console, "map " ~ filename);
    }

    /* Load user's settings */
    auto rcPath = environment["HOME"] ~ "/.escherrc";
    try
    {
      doCommandFile(display.console, rcPath, "");
    }
    catch (file.FileException e)
    {
      display.console.print(format("Error loading user config script \"%s\": %s\n", rcPath, e.msg));
    }

    GC.collect();
    GC.disable();
    bool isRunning = true;
    while (isRunning)
    {
      isRunning = display.event();
      display.drawGLFrame();
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
