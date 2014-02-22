#version 120
/* Simpler vertex shader */

uniform mat4 viewMatrix, projMatrix;

attribute vec4 positionV;
attribute vec2 uvV;

varying vec2 uvF;

void main()
{
  gl_Position = projMatrix * (viewMatrix * positionV);
  uvF = uvV;
}
