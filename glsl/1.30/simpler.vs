#version 130
/* Simpler vertex shader */

uniform mat4 viewMatrix, projMatrix;

in vec4 positionV;
in vec3 colorV;
in vec2 uvV;

out vec3 colorF;
out vec2 uvF;

void main()
{
  gl_Position = projMatrix * (viewMatrix * positionV);
  colorF = colorV;
  uvF = uvV;
}
