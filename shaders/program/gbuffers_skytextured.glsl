/*
Complementary Shaders by EminGT, based on BSL Shaders by Capt Tatsu
*/

//Common//
#include "/lib/common.glsl"

//Varyings//
#if defined END || (defined OVERWORLD && defined VANILLA_SKYBOX)
varying vec2 texCoord;

varying vec4 color;
#endif

#if defined OVERWORLD && defined VANILLA_SKYBOX
varying vec3 upVec, sunVec;
#endif

//////////Fragment Shader//////////Fragment Shader//////////Fragment Shader//////////
#ifdef FSH

//Uniforms//
uniform float isEyeInCave;
uniform float screenBrightness;

uniform vec3 skyColor;
uniform vec3 fogColor;

uniform sampler2D texture;

#if defined OVERWORLD && defined VANILLA_SKYBOX
	uniform int worldDay;
	uniform int moonPhase;

	uniform float nightVision;
	uniform float rainStrengthS;
	uniform float viewWidth, viewHeight;
	uniform float eyeAltitude;

	uniform ivec2 eyeBrightnessSmooth;

	uniform mat4 gbufferProjectionInverse;
#endif

#ifdef END
	uniform float frameTimeCounter;

	uniform vec3 cameraPosition;

	uniform mat4 gbufferModelViewInverse;

	uniform sampler2D noisetex;
#endif

#if MC_VERSION >= 11700 && defined OVERWORLD && defined VANILLA_SKYBOX && defined SUN_MOON_HORIZON
	uniform int renderStage;
#endif

//Common Variables//
float vsBrightness = clamp(screenBrightness, 0.0, 1.0);

#if defined OVERWORLD && defined VANILLA_SKYBOX
	float eBS = eyeBrightnessSmooth.y / 240.0;
	float sunVisibility = clamp(dot( sunVec,upVec) + 0.0625, 0.0, 0.125) * 8.0;
#endif

//Common Functions//

//Includes//
#if defined OVERWORLD && defined VANILLA_SKYBOX
	#include "/lib/color/lightColor.glsl"
#endif
#ifdef END
	#include "/lib/color/endColor.glsl"
#endif

//Program//
void main() {
	#if defined OVERWORLD && defined VANILLA_SKYBOX
		vec4 albedo = texture2D(texture, texCoord.xy);
		
		vec4 screenPos = vec4(gl_FragCoord.xy / vec2(viewWidth, viewHeight), gl_FragCoord.z, 1.0);
		vec4 viewPos = gbufferProjectionInverse * (screenPos * 2.0 - 1.0);
		viewPos /= viewPos.w;
		vec3 nViewPos = normalize(viewPos.xyz);

		float VdotU = dot(nViewPos, upVec);
		float VdotS = dot(nViewPos, sunVec);
		float noonFactorM = pow2(pow2(sunVisibility));

		albedo *= color;

		// Reimagined style (SUN_MOON_STYLE 1): recolor the vanilla sun/moon discs, ported from Complementary Reimagined r5.9.3
		if (VdotS > 0.9) { // Sun
			albedo.rgb = vec3(pow(dot(albedo.rgb, albedo.rgb) * 0.45, 6.0 - 5.0 * rainStrengthS));
			albedo.rgb *= mix(vec3(1.1, 0.55, 0.0), vec3(0.35), rainStrengthS * 0.75) * 4.5;
			albedo.rgb *= 0.25 + 0.75 * (sunVisibility * sunVisibility) + 0.5 * noonFactorM;
			albedo.rgb *= GetHorizonFactor(VdotU) * albedo.a;
		} else if (VdotS < -0.9) { // Moon
			albedo.rgb *= smoothstep1(min1(length(albedo.rgb))) * 1.3;
			#if BLOOD_MOON > 0
				float moonLum = dot(albedo.rgb, vec3(0.299, 0.587, 0.114));
				albedo.rgb = mix(albedo.rgb, pow2(moonLum) * vec3(0.702, 0.0, 0.0) * 1.7, getBloodMoonVisibility(sunVisibility, worldDay, moonPhase));
			#endif
			albedo.rgb *= GetHorizonFactor(VdotU) * albedo.a;
		} else { // Custom resource-pack sky / overlays
			albedo.rgb = pow(albedo.rgb, vec3(2.2 + sunVisibility * 2.2)) * (1.0 + sunVisibility * 4.0) * SKYBOX_BRIGHTNESS * albedo.a;
		}
	#else
		vec4 albedo = vec4(0.0);
	#endif

	#ifdef END
		albedo = vec4(endCol * (0.035 + 0.02 * vsBrightness), 1.0);
	#endif

	#ifdef TWO
		albedo = vec4(0.0, 0.0, 0.0, 1.0);
	#endif

	#ifdef GBUFFER_CODING
		albedo.rgb = vec3(255.0, 255.0, 85.0) / 255.0;
		albedo.rgb = pow(albedo.rgb, vec3(2.2)) * 0.5;
	#endif
	
	#if defined CAVE_SKY_FIX && defined OVERWORLD
		albedo.rgb *= 1.0 - isEyeInCave;
	#endif
	
    /* DRAWBUFFERS:0 */
	gl_FragData[0] = albedo;
}

#endif

//////////Vertex Shader//////////Vertex Shader//////////Vertex Shader//////////
#ifdef VSH

//Uniforms//
#if defined OVERWORLD && defined VANILLA_SKYBOX
	uniform mat4 gbufferModelView;

	#if AA == 2 || AA == 3
		uniform int frameCounter;

		uniform float viewWidth;
		uniform float viewHeight;
		#include "/lib/util/jitter.glsl"
	#endif
	#if AA == 4
		uniform int frameCounter;

		uniform float viewWidth;
		uniform float viewHeight;
		#include "/lib/util/jitter2.glsl"
	#endif
#endif

//Common Variables//
#if defined END || (defined OVERWORLD && defined VANILLA_SKYBOX)
	#ifdef OVERWORLD
		float timeAngleM = timeAngle;
	#else
		#if !defined SEVEN && !defined SEVEN_2
			float timeAngleM = 0.25;
		#else
			float timeAngleM = 0.5;
		#endif
	#endif
#endif

//Program//
void main() {
	#if defined END || (defined OVERWORLD && defined VANILLA_SKYBOX)
		texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
		color = gl_Color;
		
		gl_Position = ftransform();
	#endif
	
	#if defined OVERWORLD && defined VANILLA_SKYBOX
		const vec2 sunRotationData = vec2(cos(sunPathRotation * 0.01745329251994), -sin(sunPathRotation * 0.01745329251994));
		float ang = fract(timeAngleM - 0.25);
		ang = (ang + (cos(ang * 3.14159265358979) * -0.5 + 0.5 - ang) / 3.0) * 6.28318530717959;
		sunVec = normalize((gbufferModelView * vec4(vec3(-sin(ang), cos(ang) * sunRotationData) * 2000.0, 1.0)).xyz);

		upVec = normalize(gbufferModelView[1].xyz);
		
		#if AA > 1
			gl_Position.xy = TAAJitter(gl_Position.xy, gl_Position.w);
		#endif
	#else	
		#if !defined END
			vec4 color = vec4(0.0);
			gl_Position = color;
		#endif	
	#endif
}

#endif