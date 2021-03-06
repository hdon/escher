#version 150
/* Vertex shader for DoglConsole */

in vec2 uvV;
in vec2 positionV;
in vec3 colorV;

out vec2 uvF;
out vec3 colorF;

void main()
{
  gl_Position = vec4((positionV + vec2(-0.5, 0.5))*2, 0.0, 1.0);
  uvF = uvV;
  colorF = colorV;
}
