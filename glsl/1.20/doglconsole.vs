#version 120
/* Vertex shader for DoglConsole */

attribute vec2 uvV;
attribute vec2 positionV;
attribute vec3 colorV;

varying vec2 uvF;
varying vec3 colorF;

void main()
{
  gl_Position = vec4((positionV + vec2(-0.5, 0.5))*2, 0.0, 1.0);
  uvF = uvV;
  colorF = colorV;
}
