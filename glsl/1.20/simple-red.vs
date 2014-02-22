#version 120

uniform mat4 viewMatrix, projMatrix;

attribute vec4 positionV;
attribute vec3 colorV;
attribute vec2 uvV;

varying vec3 colorF;
varying vec2 uvF;

void main()
{
  colorF = colorV;
  gl_Position = projMatrix * viewMatrix * positionV;
  uvF = uvV;
}
