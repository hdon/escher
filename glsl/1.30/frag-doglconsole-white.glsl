#version 130
/* Doglconsole fragment shader */

uniform sampler2D font;

in vec2 uvF;

out vec4 outputF;

void main()
{
  gl_FragColor = texture(font, uvF);
}
