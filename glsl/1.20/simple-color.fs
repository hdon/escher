#version 120
/* Simple varying-color fragment shader */

uniform sampler2D colorMap;

varying vec3 colorF;

void main()
{
  gl_FragColor = vec4(colorF, 1);
}
