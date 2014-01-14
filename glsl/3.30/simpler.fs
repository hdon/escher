#version 150
/* Simpler fragment shader */

uniform sampler2D colorMap;

in vec3 colorF;
in vec2 uvF;

out vec4 outputF;

void main()
{
  outputF = texture(colorMap, uvF) * vec4(colorF, 1);
}
