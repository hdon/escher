#version 130
/* Simple vertex skinning shader for MD5. Only supports a single
 * uniform color, no lighting or texturing.
 */

uniform mat4 viewMatrix, projMatrix;
uniform mat4 boneMatrices[32];
uniform vec4 colorU;

in vec2 uvV;
in vec4 boneIndices;
in vec4 weightBiases;
in vec4 weightPos[4];

out vec2 uvF;
out vec3 colorF;

void main()
{
  vec4 positionObjectSpace;

  positionObjectSpace = 
    boneMatrices[int(boneIndices.x)] * weightPos[0] * weightBiases[0] + 
    boneMatrices[int(boneIndices.y)] * weightPos[1] * weightBiases[1] + 
    boneMatrices[int(boneIndices.z)] * weightPos[2] * weightBiases[2] + 
    boneMatrices[int(boneIndices.w)] * weightPos[3] * weightBiases[3];

  gl_Position = projMatrix * (viewMatrix * positionObjectSpace);
  uvF = uvV;

  colorF = colorU.rgb;
}

