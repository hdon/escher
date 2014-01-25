#version 150

uniform mat4 viewMatrix, projMatrix;

in vec4 positionV;

out vec3 colorF;

void main()
{
  gl_Position = projMatrix * viewMatrix * positionV;
}
