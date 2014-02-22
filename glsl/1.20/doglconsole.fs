#version 120
/* Doglconsole fragment shader */

uniform sampler2D font;

varying vec2 uvF;
varying vec3 colorF;

void main()
{
  gl_FragColor = texture2D(font, uvF) * vec4(colorF, 1f);
}
