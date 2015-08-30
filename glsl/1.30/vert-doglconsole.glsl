#version 130
/* Vertex shader for DoglConsole */

in vec2 uvV;
in vec2 positionV;

out vec2 uvF;

void main()
{
  gl_Position = vec4((positionV + vec2(-0.5, 0.5))*2, 0.0, 1.0);
  uvF = uvV;
}
