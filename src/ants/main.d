import display;

int main(string[] args)
{
  bool isRunning = true;
  Display display = new Display();
  scope(exit) display.cleanup();

  while (isRunning)
  {
    isRunning = display.event();
    display.clear();
    display.drawGLFrame();
  }

  return 0;
}
