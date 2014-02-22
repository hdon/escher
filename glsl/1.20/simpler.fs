#version 120
/* Simpler fragment shader */

uniform sampler2D colorMap;

varying vec3 colorF;
varying vec2 uvF;

void main()
{
  gl_FragColor = texture2D(colorMap, uvF) * vec4(colorF, 1);
}
