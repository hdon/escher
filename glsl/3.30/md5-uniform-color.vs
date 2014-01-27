#version 150
/* Simple vertex skinning shader for MD5. Only supports a single
 * uniform color, no lighting or texturing.
 */

uniform mat4 viewMatrix, projMatrix;
uniform mat4 boneMatrices[32];

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
    boneMatrices[int(boneIndices.x+0.1)] * weightPos[0] * weightBiases[0] + 
    boneMatrices[int(boneIndices.y+0.1)] * weightPos[1] * weightBiases[1] + 
    boneMatrices[int(boneIndices.z+0.1)] * weightPos[2] * weightBiases[2] + 
    boneMatrices[int(boneIndices.w+0.1)] * weightPos[3] * weightBiases[3];

  gl_Position = projMatrix * (viewMatrix * positionObjectSpace);
  uvF = uvV;

  vec3 color;

  /* If the product of the first and second weight bias is zero, then there is only one weight.
   *
   * If there is only one weight, there is only one joint.
   *
   * If there is only one joint, color.r = 0
   *
   * Therefore:
   * 1 Joint  = no red
   * 2 Joints = has red
   */
  color.r =  (weightBiases.x * weightBiases.y == 0) ? 0 : 1;

  /* If there are two joints, color.g and color.b are 0.
   *
   * 2 joints:
   * No blue, no green
   * 1 joint:
   * maybe
   *
   * If there is only one joint
   * -AND-
   * the first joint index (boneIndices.x) is 0,
   * color.g = 1
   *
   * If there is only one joint
   * -AND-
   * the first joint index (boneIndices.x) is 1,
   * color.b = 1
   *
   * Therefore:
   * If the only joint is joint 0:
   * has green
   * Else, if the only joint is joint 1:
   * has blue
   */
  color.g = ((weightBiases.x * weightBiases.y == 0) && (boneIndices.x == 0)) ? 1 : 0;
  color.b = ((weightBiases.x * weightBiases.y == 0) && (boneIndices.x == 1)) ? 1 : 0;
  colorF = color;
  //colorF = vec3(1,1,1);
}
