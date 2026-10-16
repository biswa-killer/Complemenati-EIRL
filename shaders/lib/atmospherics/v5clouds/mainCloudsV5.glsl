// Ported from Complementary V5 lib/atmospherics/clouds/mainClouds.glsl
// Dispatcher + shared helpers for V5-style clouds inside ShaderV4.
// Environment expectations (program must provide before including):
//   varyings/uniforms : sunVec, upVec, cameraPosition, gbufferModelViewInverse,
//                       frameTimeCounter, frameCounter, noisetex, isEyeInWater,
//                       blindFactor (or darkness), moonPhase, worldDay (BLOOD_MOON > 0)
//   V4 colors         : lightCol, ambientCol, skyColor, weatherCol
//   V4 vars           : sunVisibility, timeBrightness, moonBrightness, rainStrengthS
//   V4 funcs          : pow2, pow1_5, pow5, min1, max0, clamp01, sqrt1, sqrt3,
//                       GetSkyColor(lightCol, NdotU, dir, isReflection),
//                       getBloodMoonVisibility (BLOOD_MOON > 0), ViewToWorld
//   cloudtime         : world-time-synced clock (same boilerplate as other programs)
// Define V5_CLOUD_REFLECTION before include when calling from reflection paths
// (lower quality, matches V5's !DEFERRED1 branch behaviour).

#ifndef MAIN_CLOUDS_V5
#define MAIN_CLOUDS_V5

//----- derived state (V5 names -> V4 sources) -----//
#if V5_CLOUD_UNBOUND_SIZE_MULT != 100
    #define V5_CLOUD_UNBOUND_SIZE_MULT_M V5_CLOUD_UNBOUND_SIZE_MULT * 0.01
#endif

#if V5_CLOUD_QUALITY_DEFINE <= 0
    #define V5_CLOUD_QUALITY_INTERNAL 1
#else
    #define V5_CLOUD_QUALITY_INTERNAL V5_CLOUD_QUALITY_DEFINE
#endif

float renderDistanceV5 = far;
// ponytail: V5 offsets altitude by the vanilla cloudHeight uniform. Optifine <1.20
// lacks cloudHeight on some versions; V5_CLOUD_ALT1 alone is authoritative here.
int cloudAlt1iV5 = V5_CLOUD_ALT1;

float rainFactor = rainStrengthS;
float rainFactor2 = rainFactor * rainFactor;
float invRainFactor = 1.0 - rainFactor;
float sunVisibility2V5 = sunVisibility * sunVisibility;
float nightFactorV5 = 1.0 - sunVisibility;
float noonFactorV5 = sqrt(max(timeBrightness, 0.0));
float shadowTimeRaw = abs(sunVisibility - 0.5) * 2.0;
float shadowTime = shadowTimeRaw * shadowTimeRaw;
float maxBlindnessDarknessV5 = clamp(blindFactor, 0.0, 1.0);

//----- helpers -----//
float InterleavedGradientNoiseForCloudsV5() {
    float n = 52.9829189 * fract(0.06711056 * gl_FragCoord.x + 0.00583715 * gl_FragCoord.y);
    #if AA > 1
        return fract(n + 1.61803398875 * mod(float(frameCounter), 3600.0));
    #else
        return fract(n);
    #endif
}

// 3D noise via 2D noisetex slices (V5 commonFunctions.glsl:80)
float Noise3DV5(vec3 p) {
    p.z = fract(p.z) * 128.0;
    float iz = floor(p.z);
    float fz = fract(p.z);
    vec2 a_off = vec2(23.0, 29.0) * (iz) / 128.0;
    vec2 b_off = vec2(23.0, 29.0) * (iz + 1.0) / 128.0;
    float a = texture2DLod(noisetex, p.xy + a_off, 0.0).r;
    float b = texture2DLod(noisetex, p.xy + b_off, 0.0).r;
    return mix(a, b, fz);
}

vec3 ViewToPlayerV5(vec3 viewSpaceVec) {
    return mat3(gbufferModelViewInverse) * viewSpaceVec;
}

#if BLOOD_MOON > 0
// minimal rgb<->hsv for the blood-moon cloud tint
vec3 rgb2hsvV5(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}
vec3 hsv2rgbV5(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
#endif

//----- cloud colors (V5 cloudColors.glsl mapped to V4 color globals) -----//
// V4 lacks dayMiddleSkyColor/nightMiddleSkyColor; approximate from skyColor/ambientCol.
vec3 dayMiddleSkyColorV5 = skyColor * skyColor;
vec3 nightMiddleSkyColorV5 = ambientCol * ambientCol * 4.0;
vec3 cloudRainColorV5 = mix(nightMiddleSkyColorV5, dayMiddleSkyColorV5, sunVisibility);

vec3 cloudAmbientColorV5 = mix(ambientCol * (sunVisibility2V5 * (0.55 + vec3(0.2, 0.1, 0.0) * noonFactorV5) + 0.35), cloudRainColorV5 * 0.5, rainFactor) * mix(V5_CLOUD_NIGHT_AMBIENT_MULTIPLIER, V5_CLOUD_AMBIENT_MULTIPLIER, sunVisibility2V5);

vec3 cloudLightColorV5 = mix(
    lightCol * (
        1.3
        #ifdef V5_CLOUDS_UNBOUND
            + vec3(0.1, -0.1, -0.3) * noonFactorV5
        #endif
    ),
    cloudRainColorV5 * 0.45,
    noonFactorV5 * rainFactor
) * mix(V5_CLOUD_NIGHT_LIGHT_MULTIPLIER, V5_CLOUD_LIGHT_MULTIPLIER, sunVisibility2V5);

#ifdef V5_CLOUDS_REIMAGINED
    #include "/lib/atmospherics/v5clouds/reimaginedCloudsV5.glsl"
#endif
#ifdef V5_CLOUDS_UNBOUND
    #include "/lib/atmospherics/v5clouds/unboundCloudsV5.glsl"
#endif

vec4 GetCloudsV5(inout float cloudLinearDepth, float skyFade, vec3 cameraPosOffset, vec3 playerPos, vec3 viewPos,
               float lViewPos, float VdotS, float VdotU, float dither, vec3 sunVec) {
    vec4 clouds = vec4(0.0);

    vec3 nPlayerPos = normalize(playerPos);
    float lViewPosM = lViewPos < renderDistanceV5 * 1.5 ? lViewPos - 1.0 : 1000000000.0;
    float skyMult0 = pow2(skyFade * 3.333333 - 2.333333);

    vec3 cameraPos = cameraPosition + cameraPosOffset;

    float thresholdF = 4000.0;
    thresholdF *= V5_CLOUD_RENDER_DISTANCE;

    #ifdef V5_CLOUDS_REIMAGINED
        cloudAmbientColorV5 *= 1.0 - 0.25 * rainFactor;
    #endif

    vec3 cloudColorMult = vec3(1.0);
    #if V5_CLOUD_R != 100 || V5_CLOUD_G != 100 || V5_CLOUD_B != 100
        cloudColorMult *= vec3(V5_CLOUD_R, V5_CLOUD_G, V5_CLOUD_B) * 0.01;
    #endif
    cloudAmbientColorV5 *= cloudColorMult;
    cloudLightColorV5 *= cloudColorMult;

    #ifdef V5_CLOUDS_REIMAGINED
        clouds = GetVolumetricCloudsV5R(cloudAlt1iV5, thresholdF, cloudLinearDepth, skyFade, skyMult0,
                                        cameraPos, nPlayerPos, lViewPosM, VdotS, VdotU, dither, sunVec, viewPos);
    #elif defined V5_CLOUDS_UNBOUND
        clouds = GetVolumetricCloudsV5U(cloudAlt1iV5, thresholdF, cloudLinearDepth, skyFade, skyMult0,
                                        cameraPos, nPlayerPos, lViewPosM, VdotS, VdotU, dither, sunVec, viewPos);
    #endif

    return clouds;
}

#endif
