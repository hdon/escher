#version 130

in vec3 positionV;
in vec3 colorV;
in vec2 uvV;

out vec3 colorF;
out vec2 uvF;

void main()
{
  gl_Position = vec4(positionV, 1.0);
  colorF = colorV;
  uvF = uvV;
}
