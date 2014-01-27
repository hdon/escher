module ants.commands;
import std.string : splitLines, split, format;
import std.conv : to;
import std.algorithm : startsWith;
import file = std.file;
import ants.main : display;
import ants.escher : World, Camera, EntityPlayer, vec3, playerEntity;
import ants.doglconsole : DoglConsole;
import ants.md5 : MD5Animation;

void doCommand(DoglConsole console, string cmd)
{
  try
  {
    string[1] cmds = [cmd];
    doCommands(console, cmds, "<console>");
  }
  catch (Throwable e)
  {
    console.print(format("%s:%d: error: %s\n", e.file, e.line, e.msg));
  }
}

void doCommands(DoglConsole console, string[] commandText, string filename, size_t firstLineNo=1)
{
  foreach (lineNo, line; commandText)
  {
    version (debugCommands)
    console.print(format("[commands] evaluating: %s\n", line));

    try
    {
      if (line.length == 0)
        continue;
      auto words = split(line);
      bool b;
      switch (words[0])
      {
        case "fly":
          assert(words.length <= 2, "invalid number of arguments");
          if (words.length == 1)
            b = ! display.camera.fly;
          else
            b = to!bool(words[1]);
          display.camera.fly = b;
          console.print(format("fly %sabled\n", b ? "en" : "dis"));
          break;

        case "noclip":
          if (words.length == 1)
            b = ! display.camera.noclip;
          else
            b = to!bool(words[1]);
          assert(words.length <= 2, "invalid number of arguments");
          display.camera.noclip = b;
          console.print(format("noclip %sabled\n", b ? "en" : "dis"));
          break;

        case "nobody":
          if (words.length == 1)
            b = ! display.camera.noBody;
          else
            b = to!bool(words[1]);
          assert(words.length <= 2, "invalid number of arguments");
          display.camera.noBody = b;
          console.print(format("nobody %sabled\n", b ? "en" : "dis"));
          break;

        case "noent":
          if (words.length == 1)
            b = ! display.world.noDrawEntities;
          else
            b = to!bool(words[1]);
          assert(words.length <= 2, "invalid number of arguments");
          display.world.noDrawEntities = b;
          console.print(format("noent %sabled\n", b ? "en" : "dis"));
          break;

        case "map":
          assert(words.length == 2, "invalid number of arguments");
          console.print(format("loading map file \"%s\"\n", words[1]));
          display.world = new World(words[1]);
          display.camera = new Camera(display.world, 0, vec3(0,0,0));
          playerEntity = new EntityPlayer(0, vec3(0,0,0));
          break;

        case "exec":
          assert(words.length == 2, "invalid number of arguments");
          console.print(format("evaluating script file \"%s\"\n", words[1]));
          doCommandFile(console, words[1]);
          break;

        case "md5drawfull":
          if (words.length == 1)
            b = ! MD5Animation.optRenderFull;
          else
            b = to!bool(words[1]);
          assert(words.length <= 2, "invalid number of arguments");
          MD5Animation.optRenderFull = b;
          console.print(format("md5drawfull %sabled\n", b ? "en" : "dis"));
          break;

        case "md5drawweights":
          if (words.length == 1)
            b = ! MD5Animation.optRenderWeights;
          else
            b = to!bool(words[1]);
          assert(words.length <= 2, "invalid number of arguments");
          MD5Animation.optRenderWeights = b;
          console.print(format("md5drawweights %sabled\n", b ? "en" : "dis"));
          break;

        case "md5drawframe":
          if (words.length == 1)
            b = ! MD5Animation.optRenderWireframe;
          else
            b = to!bool(words[1]);
          assert(words.length <= 2, "invalid number of arguments");
          MD5Animation.optRenderWireframe = b;
          console.print(format("md5drawframe %sabled\n", b ? "en" : "dis"));
          break;

        case "md5drawverts":
          if (words.length == 1)
            b = ! MD5Animation.optRenderVerts;
          else
            b = to!bool(words[1]);
          assert(words.length <= 2, "invalid number of arguments");
          MD5Animation.optRenderVerts = b;
          console.print(format("md5drawframe %sabled\n", b ? "en" : "dis"));
          break;
          
        default:
          console.print(format("unknown command: %s\n", words[0]));
      }
    }
    catch (Throwable e)
    {
      throw new Exception(e.msg, filename, firstLineNo+lineNo, e);
    }
  }
}

/* Do not supply commandText argument without considering firstLineNo argument, and vice versa.
 * If commandText.length == 0 and you supply it, just don't call doCommandFile(). Yeah, this is
 * lame.
 */
void doCommandFile(DoglConsole console, string filename, string commandText="", size_t firstLineNo=1)
{
  if (commandText.length == 0)
  {
    commandText = to!string(cast(char[])file.read(filename));

    if (!commandText.startsWith("escher script version 2\n"))
    {
      throw new Exception("expected \"escher script version 2\"");
    }

    commandText = commandText[24..$];
  }

  doCommands(console, splitLines(commandText), filename, firstLineNo);
}
