#version 130
/* Simple varying-color fragment shader */

uniform sampler2D colorMap;

in vec3 colorF;

out vec4 outputF;

void main()
{
  outputF = vec4(colorF, 1);
}
