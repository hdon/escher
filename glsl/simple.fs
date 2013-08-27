#version 150
/* Simple fragment shader */

struct LightSource
{
  vec3 pos;
  vec4 diffuse;
  vec4 specular;
};

uniform sampler2D colorMap;
uniform sampler2D normalMap;
uniform LightSource lightSource;

in vec3 colorF;
in vec2 uvF;
in vec3 eyeVecF;
in vec3 lightDirF;
in vec3 halfVecF;
in vec3 normalF;
in vec3 positionF;

out vec4 outputF;

void main()
{
  /*
    Material.EmissiveColor +
    Material.AmbientColor * AmbientLight.AmbientColor +
    (atten[i] * (diff[i] + spec[i]))

    diff[i] = dot(L[i], N) * Light.DiffuseColor * Material.DiffuseColor
    spec[i] = dot(S[i], N) ^Material.Shininess * Light.DiffuseColor * Material.DiffuseColor
    atten[i] = 1 / (Kc[i] + Kl[i] * d[i] + Kq[i] * d[i]^2)

    L[i] = direction from vertex to light
    d[i] = distance from vertex to light
    S[i] = Specular half-vector = || (Li + E) || 
    N = normal

    Kc[i] = "constant" light attenuation
    Kl[i] = linear light attenuation
    Kq[i] = quadratic light attenuation
  */

  vec3 normal = normalize(normalF);// + texture(normalMap, uvF).rgb);
  vec3 halfVec = normalize(halfVecF);
  vec3 lightDir = normalize(lightDirF);
  float lightDistance = distance(lightSource.pos, positionF);
  float lightAttenuated = 1.0 / lightDistance;
  vec4 diffuse = dot(lightDir, normal) * lightSource.diffuse;
  vec4 specular = pow(dot(halfVec, normal), 10.0) * lightSource.specular;
  vec4 light = 0.1 + lightAttenuated * (diffuse + specular);

  gl_FragColor = light * texture(colorMap, uvF);
}
