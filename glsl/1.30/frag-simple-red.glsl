#version 130

uniform sampler2D tex;
in vec3 colorF;
in vec2 uvF;

void main() {
  gl_FragColor = vec4(colorF, 1.0);
}
