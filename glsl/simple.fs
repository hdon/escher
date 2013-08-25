#version 150

uniform sampler2D tex;
in vec3 colorF;
in vec2 uvF;

out vec4 outputF;

void main() {
  outputF = vec4(colorF, 1.0) * texture(tex, uvF);
}
