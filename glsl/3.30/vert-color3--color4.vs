#version 150
/* Vertex shader for drawing with opaque color only */

in vec3 positionV;
in vec3 colorV;

out vec4 colorF;

void main()
{
  gl_Position = vec4(positionV, 1.0);
  colorF = vec4(colorV, 1.0);
}
