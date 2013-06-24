import display;
import std.stdio;

int main(string[] args)
{
  if (args.length != 2)
  {
    writefln("usage: %s <map.esc>", args[0]);
    return 1;
  }

  bool isRunning = true;
  Display display = new Display(args[1]);
  scope(exit) display.cleanup();

  while (isRunning)
  {
    isRunning = display.event();
    display.clear();
    display.drawGLFrame();
  }

  return 0;
}
