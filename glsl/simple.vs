#version 150

uniform mat4 viewMatrix, projMatrix;
uniform mat3 normalMatrix;

in vec3 normalV;
in vec4 positionV;
in vec3 colorV;
in vec2 uvV;

out vec3 colorF;
out vec2 uvF;

void main()
{
  colorF = (normalV + vec3(1,1,1)) * 0.5;
  gl_Position = projMatrix * viewMatrix * positionV;
  uvF = uvV;
}
