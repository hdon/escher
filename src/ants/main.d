import display;
import std.stdio;
import std.string : splitLines, split;
import file = std.file;

int main(string[] args)
{
  string mapfilename;
  if (args.length == 2)
  {
    mapfilename = args[1];
  }
  else
  {
    foreach (lineNo, line; splitLines(to!string(cast(char[])file.read("init.txt"))))
    {
      if (lineNo == 0)
      {
        if (line != "escher engine init script version 1")
        {
          writeln("Could not find Escher engine initialization script!");
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
          writefln("error: init.txt: unknown command \"%s\"", words[0]);
          return 1;
      }
    }
  }

  bool isRunning = true;
  Display display = new Display(mapfilename);
  scope(exit) display.cleanup();

  while (isRunning)
  {
    isRunning = display.event();
    display.drawGLFrame();
  }

  return 0;
}
