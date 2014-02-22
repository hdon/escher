#version 120
/* Simpler fragment shader */

uniform sampler2D colorMap;

varying vec2 uvF;

void main()
{
  gl_FragColor = texture2D(colorMap, uvF);
}
