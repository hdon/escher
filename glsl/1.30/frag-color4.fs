#version 130
/* Fragment shader for drawing with opaque color only */

in vec4 colorF;

void main()
{
  gl_FragColor = colorF;
}
