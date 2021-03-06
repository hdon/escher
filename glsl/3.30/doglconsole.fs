#version 150
/* Doglconsole fragment shader */

uniform sampler2D font;

in vec2 uvF;
in vec3 colorF;

out vec4 outputF;

void main()
{
  gl_FragColor = texture(font, uvF) * vec4(colorF, 1f);
}
