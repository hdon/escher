#version 130
// http://glsl.heroku.com/e#12944.0
#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 resolution;
in vec3 positionF;
in vec3 normalF;
in vec2 uvF;
out vec4 outputF;

// Fractal Soup - @P_Malin

vec2 CircleInversion(vec2 vPos, vec2 vOrigin, float fRadius)
{
	vec2 vOP = vPos - vOrigin;

	vOrigin = vOrigin - vOP * fRadius * fRadius / dot(vOP, vOP);
	vOrigin.x += sin(vOrigin.x * 0.01);
	vOrigin.y -= cos(vOrigin.y* 0.01);

	return vOrigin;
}

float Parabola( float x, float n )
{
	return pow( 2.0*x*(1.0-x), n );
}

float classifyUnitVec3(vec3 v)
{
  if (v.y > 0.72 || v.y < -0.72)
    return 1.0;
  if (v.x > 0.72 || v.x < -0.72)
    return 1.2;
  if (v.z > 0.72 || v.z < -0.72)
    return 1.4;
  return 1.5;
}

void main(void)
{
  float roughDir = classifyUnitVec3(normalF);
  float time2 = time * roughDir;
	//vec2 vPos = vec2(
    //gl_FragCoord.x / resolution.x,
    //gl_FragCoord.y / resolution.y);
  vec2 vPos = uvF;
	vPos = vPos - 0.5;

	vPos.x *= resolution.x / resolution.y;

	vec2 vScale = vec2(1.2);
	vec2 vOffset = vec2( sin(time2 * 0.123), atan(time2 * 0.0567));

	float l = 0.0;
	float minl = 10000.0;

	for(int i=0; i<48; i++)
	{
		vPos.x = abs(vPos.x);
		vPos = vPos * vScale + vOffset;

		vPos = CircleInversion(vPos, vec2(0.5, 0.5), 0.9);

		l = length(vPos);
		minl = min(l, minl);
	}


	float t = 4.1 + time2 * 0.055;
	vec3 vBaseColour = normalize(vec3(sin(t * 1.790), sin(t * 1.345), sin(t * 1.123)) * 0.5 + 0.5);

	//vBaseColour = vec3(1.0, 0.15, 0.05);

	float fBrightness = 11.0;

	vec3 vColour = vBaseColour * l * l * fBrightness;

	minl = Parabola(minl, 5.0);

	vColour *= minl + 0.1;

	vColour = 1.0 - exp(-vColour);
	outputF = vec4(vColour,1.0);
}

