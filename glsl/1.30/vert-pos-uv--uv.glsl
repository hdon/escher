#version 130
/* Simpler vertex shader */

uniform mat4 viewMatrix, projMatrix;

in vec4 positionV;
in vec2 uvV;

out vec2 uvF;

void main()
{
  gl_Position = projMatrix * (viewMatrix * positionV);
  uvF = uvV;
}
