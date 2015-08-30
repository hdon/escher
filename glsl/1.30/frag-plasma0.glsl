#version 130
// http://glsl.heroku.com/e#12967.2

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;
in vec3 positionF;
out vec4 outputF;

void main( void ) {

	vec2 position = gl_FragCoord.xy / resolution.xy;

	float color = 0.0;
	color += sin( position.x * cos( time / 15.0 ) * 80.0 ) + cos( position.y * cos( time / 15.0 ) * 10.0 );
	color += sin( position.y * cos( time / 10.0 ) * 40.0 ) + cos( position.x * cos( time / 25.0 ) * 40.0 );
	color += sin( position.x * sin( time / 5.0 ) * 10.0 ) + sin( position.y * sin( time / 35.0 ) * 80.0 );
	color *= sin( time / 10.0 ) * 0.5;

	outputF = vec4( vec3( color, color * 0.5, sin( color + time / 3.0 ) * 0.75 ), 1.0 );

}
