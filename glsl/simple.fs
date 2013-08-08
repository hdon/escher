#version 150

uniform sampler2D tex;
in vec3 Color;
in vec2 uvF;

out vec4 outputF;

void main() {
  outputF = vec4(Color, 1.0) * texture(tex, uvF);
}
