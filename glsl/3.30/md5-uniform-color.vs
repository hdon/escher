#version 150
/* Simple vertex skinning shader for MD5. Only supports a single
 * uniform color, no lighting or texturing.
 */

uniform mat4 viewMatrix, projMatrix;
uniform mat4 boneMatrices[32];

in vec2 uvV;
in vec4 boneIndices[4];
in vec4 weightBiases;
in vec4 weightPos[4];

out vec2 uvF;
out vec3 colorF;

void main()
{
  vec4 positionObjectSpace = 
    boneMatrices[int(boneIndices[0])] * weightPos[0] * weightBiases[0] + 
    boneMatrices[int(boneIndices[1])] * weightPos[1] * weightBiases[1] + 
    boneMatrices[int(boneIndices[2])] * weightPos[2] * weightBiases[2] + 
    boneMatrices[int(boneIndices[3])] * weightPos[3] * weightBiases[3];

  gl_Position = projMatrix * (viewMatrix * positionObjectSpace);
  uvF = uvV;
  colorF = vec3(1,1,1);
}
