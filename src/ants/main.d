import display;
import std.stdio;
import std.string : splitLines, split, toStringz, format;
import core.memory : GC;
import file = std.file;
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

int main(string[] args)
{
  version (Windows)
  {
    stdout.open("stdout.txt", "w");
    stderr.open("stderr.txt", "w");
  }

  try
  {
    string mapfilename;
    if (args.length == 2)
    {
      mapfilename = args[1];
    }
    else
    {
      string initText;
      try
      {
        initText = to!string(cast(char[])file.read("init.txt"));
      }
      catch (file.FileException e)
      {
        message(e.msg);
        return 1;
      }

      foreach (lineNo, line; splitLines(initText))
      {
        if (lineNo == 0)
        {
          if (line != "escher engine init script version 1")
          {
            message("Could not find Escher engine initialization script!");
            return 1;
          }
          continue;
        }

        auto words = split(line);
        if (words.length == 0)
          continue;
        switch (words[0])
        {
          case "map":
            mapfilename = words[1];
            break;
          default:
            message(format("error: init.txt: unknown command \"%s\"", words[0]));
            return 1;
        }
      }
    }

    bool isRunning = true;
    Display display = new Display(mapfilename);
    scope(exit) display.cleanup();

    GC.disable();
    while (isRunning)
    {
      isRunning = display.event();
      display.drawGLFrame();
      GC.collect();
    }
    GC.enable();
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
