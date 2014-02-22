#version 120
/* Doglconsole fragment shader */

uniform sampler2D font;

varying vec2 uvF;

void main()
{
  gl_FragColor = texture2D(font, uvF);
}
