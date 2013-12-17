#version 150
/* Simple vertex shader */

struct LightSource
{
  vec3 pos;
  vec4 diffuse;
  vec4 specular;
};

uniform mat4 viewMatrix, projMatrix;
uniform mat3 normalMatrix;

uniform LightSource lightSource;

in vec3 normalV;
in vec4 positionV;
in vec3 colorV;
in vec2 uvV;

out vec3 positionF;
out vec3 colorF;
out vec2 uvF;
out vec3 eyeVecF;
out vec3 lightDirF;
out vec3 normalF;
out vec3 halfVecF;

void main()
{
  vec3 vertexEyeSpace = vec3(viewMatrix * positionV).xyz;
  gl_Position = projMatrix * vec4(vertexEyeSpace, 1);
  eyeVecF = -vertexEyeSpace;
  lightDirF = normalize((viewMatrix * vec4(lightSource.pos,1)).xyz - vertexEyeSpace);
  halfVecF = normalize((normalize(eyeVecF) + lightDirF));

  normalF = normalMatrix * normalV;
  colorF = colorV;
  uvF = uvV;
  positionF = positionV.xyz;
}
