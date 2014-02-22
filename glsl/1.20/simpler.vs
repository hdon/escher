#version 120
/* Simpler vertex shader */

uniform mat4 viewMatrix, projMatrix;

attribute vec4 positionV;
attribute vec3 colorV;
attribute vec2 uvV;

varying vec3 colorF;
varying vec2 uvF;

void main()
{
  gl_Position = projMatrix * (viewMatrix * positionV);
  colorF = colorV;
  uvF = uvV;
}
