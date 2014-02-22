#version 120

uniform sampler2D tex;
varying vec3 colorF;
varying vec2 uvF;

void main() {
  gl_FragColor = vec4(colorF, 1.0);
}
