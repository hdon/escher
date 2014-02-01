#version 130
/* Simpler fragment shader */

uniform sampler2D colorMap;

in vec2 uvF;

out vec4 outputF;

void main()
{
  outputF = texture(colorMap, uvF);
}
