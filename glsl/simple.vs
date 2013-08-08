#version 150

uniform mat4 viewMatrix, projMatrix;

in vec4 position;
in vec3 color;
in vec2 uvV;

out vec3 Color;
out vec2 uvF;

void main()
{
  Color = color;
  gl_Position = projMatrix * viewMatrix * position;
  uvF = uvV;
}
