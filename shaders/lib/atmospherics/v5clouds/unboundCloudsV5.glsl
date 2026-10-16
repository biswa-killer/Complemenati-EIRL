// Ported from Complementary V5 lib/atmospherics/clouds/unboundClouds.glsl
// Unbound-style volumetric clouds (3D-noise raymarched slab).
// Stripped deps: SHADOW_QUALITY/shadowtex, AURORA_INFLUENCE, SAVE_SKYBOX_DATA,
// ATM_COLOR_MULTS, DOUBLE_UNBOUND_CLOUDS, RAIN_ATMOSPHERE (lightning), SEASONS,
// IRIS int cam, closed-area check (needs eyeBrightness uniform — kept off).
// Blood moon uses V4's getBloodMoonVisibility(sunVisibility, worldDay, moonPhase).
// Requires: noisetex, V4 helpers (pow2, pow1_5, pow5, clamp01, min1, max0),
//           InterleavedGradientNoiseForCloudsV5, Noise3DV5, cloud color globals.

const float cloudStretchModifiedV5 = max(0.25, float(V5_CLOUD_STRETCH) * 1.9 - 0.9);
#if V5_CLOUD_QUALITY_INTERNAL == 1 || defined V5_CLOUD_REFLECTION
    const float cloudStretchRawV5 = 11.0 * cloudStretchModifiedV5;
#elif V5_CLOUD_QUALITY_INTERNAL == 2
    const float cloudStretchRawV5 = 16.0 * cloudStretchModifiedV5;
#elif V5_CLOUD_QUALITY_INTERNAL == 3
    const float cloudStretchRawV5 = 18.0 * cloudStretchModifiedV5;
#elif V5_CLOUD_QUALITY_INTERNAL == 4
    const float cloudStretchRawV5 = 20.0 * cloudStretchModifiedV5;
#endif

#if V5_CLOUD_UNBOUND_SIZE_MULT <= 100
    const float cloudStretchV5U = cloudStretchRawV5;
#else
    const float cloudStretchV5U = cloudStretchRawV5 / float(V5_CLOUD_UNBOUND_SIZE_MULT_M);
#endif
const float cloudTallnessV5U = cloudStretchV5U * 2.0;

#if V5_CLOUD_QUALITY_INTERNAL > 1
    const float cloudNarrownessU = 0.00012;
#else
    const float cloudNarrownessU = 0.00006;
#endif

#if V5_PIXELATED_UNBOUND_CLOUDS > 0
const float pixelatedUnboundWindSpeedMultV5 = 0.2;

vec3 PixelateUnboundCloudPosV5(vec3 tracePos, float pixelStep) {
    return (floor(tracePos / pixelStep) + 0.5) * pixelStep;
}

vec2 PixelateUnboundCloudPosV5(vec2 tracePos, float pixelStep) {
    return (floor(tracePos / pixelStep) + 0.5) * pixelStep;
}

float QuantizeCloudValueV5(float value, float levels) {
    return floor(value * levels + 0.5) / levels;
}

float GetVoxelCloudVariationV5(vec3 cloudTracePos, float pixelStep) {
    vec3 voxelCoord = floor(cloudTracePos / pixelStep + 0.5);
    return fract(sin(dot(voxelCoord, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}
#endif

float GetCloudNoiseV5U(vec3 tracePos, int cloudAltitude, float lTracePosXZ, float cloudPlayerPosY) {
    vec3 tracePosM = tracePos.xyz * cloudNarrownessU;
    float wind = 0.0006;
    float noise = 0.0;
    float currentPersist = 1.0;
    float total = 0.0;

    #if V5_CLOUD_SPEED_MULT == 100
        wind *= cloudtime; // V4 world-time-synced clock
    #else
        wind *= frameTimeCounter * (V5_CLOUD_SPEED_MULT * 0.01);
    #endif

    #if V5_CLOUD_UNBOUND_SIZE_MULT != 100
        tracePosM *= V5_CLOUD_UNBOUND_SIZE_MULT_M;
        wind *= V5_CLOUD_UNBOUND_SIZE_MULT_M;
    #endif

    #if V5_PIXELATED_UNBOUND_CLOUDS > 0
        float pixelStepM = V5_PIXELATED_UNBOUND_CLOUDS * cloudNarrownessU;

        #if V5_CLOUD_UNBOUND_SIZE_MULT != 100
            pixelStepM *= V5_CLOUD_UNBOUND_SIZE_MULT_M;
        #endif
    #endif

    #if V5_PIXELATED_UNBOUND_CLOUDS > 0
        int sampleCount = 5;
        float persistance = 0.43;
        float noiseMult = 0.92;
        wind *= pixelatedUnboundWindSpeedMultV5;
    #elif V5_CLOUD_QUALITY_INTERNAL == 1 && !defined V5_CLOUD_REFLECTION
        int sampleCount = 2;
        float persistance = 0.6;
        float noiseMult = 0.95;
        wind *= 0.5;
    #elif V5_CLOUD_QUALITY_INTERNAL == 2 || defined V5_CLOUD_REFLECTION
        int sampleCount = 4;
        float persistance = 0.5;
        float noiseMult = 1.14;
    #elif V5_CLOUD_QUALITY_INTERNAL == 3
        int sampleCount = 4;
        float persistance = 0.5;
        float noiseMult = 1.0;
    #elif V5_CLOUD_QUALITY_INTERNAL == 4
        int sampleCount = 5;
        float persistance = 0.5;
        float noiseMult = 1.05;
    #endif

    #ifdef V5_CLOUD_REFLECTION
        noiseMult *= 1.2;
    #endif

    #if V5_CLOUD_DIRECTION == 1
        tracePosM.xz = tracePosM.zx;
    #endif

    for (int i = 0; i < sampleCount; i++) {
        vec3 windOffset = vec3(0.0, 0.0, wind);
        #if V5_PIXELATED_UNBOUND_CLOUDS > 0
            vec3 pos = PixelateUnboundCloudPosV5(tracePosM - windOffset, pixelStepM);
        #else
            vec3 pos = tracePosM - windOffset;
        #endif

        #if V5_CLOUD_QUALITY_INTERNAL >= 2
            noise += Noise3DV5(pos) * currentPersist;
        #else
            noise += texture2DLod(noisetex, pos.xz, 0.0).b * currentPersist;
        #endif
        total += currentPersist;

        float octaveOffset = 3.0;
        tracePosM *= octaveOffset;
        #if V5_PIXELATED_UNBOUND_CLOUDS > 0
            pixelStepM *= octaveOffset;
            wind *= octaveOffset; // normalize wind speed across octaves to prevent different speed voxel grids
        #else
            wind *= 0.5;
        #endif
        currentPersist *= persistance;
    }
    noise = pow2(noise / total);

    #define V5_CLOUD_BASE_ADD 0.8
    #define V5_CLOUD_ABOVE_ADD 0.1

    float nightCloudRemove = V5_NIGHT_CLOUD_UNBOUND_REMOVE * (1.0 - sunVisibility) * -0.65 + 1.0; // mapped to 1 to 0.65 range

    noiseMult *= V5_CLOUD_BASE_ADD
                + V5_CLOUD_ABOVE_ADD * clamp01(-cloudPlayerPosY / cloudTallnessV5U) // more clouds when camera is above them
                + V5_CLOUD_UNBOUND_RAIN_ADD * rainFactor; // more clouds during rain

    noise *= noiseMult * V5_CLOUD_UNBOUND_AMOUNT * nightCloudRemove;

    float threshold = clamp(abs(cloudAltitude - tracePos.y) / cloudStretchV5U, 0.001, 0.999);
    threshold = pow2(pow2(pow2(threshold)));
    return noise - (threshold * 0.2 + 0.25);
}

vec4 GetVolumetricCloudsV5U(int cloudAltitude, float distanceThreshold, inout float cloudLinearDepth, float skyFade, float skyMult0, vec3 cameraPos, vec3 nPlayerPos, float lViewPosM, float VdotS, float VdotU, float dither, vec3 sunVec, vec3 viewPos) {
    vec4 volumetricClouds = vec4(0.0);

    float higherPlaneAltitude = cloudAltitude + cloudStretchV5U;
    float lowerPlaneAltitude  = cloudAltitude - cloudStretchV5U;

    float lowerPlaneDistance  = (lowerPlaneAltitude - cameraPos.y) / nPlayerPos.y;
    float higherPlaneDistance = (higherPlaneAltitude - cameraPos.y) / nPlayerPos.y;
    float minPlaneDistance = min(lowerPlaneDistance, higherPlaneDistance);
          minPlaneDistance = max(minPlaneDistance, 0.0);
    float maxPlaneDistance = max(lowerPlaneDistance, higherPlaneDistance);
    if (maxPlaneDistance < 0.0) return vec4(0.0);
    float planeDistanceDif = maxPlaneDistance - minPlaneDistance;

    float aboveClouds = clamp01((cameraPos.y - lowerPlaneAltitude) * 0.01);
    float skyFadeM = mix(skyFade, 1.0, mix(0.4 * max(aboveClouds, rainFactor2), 1.0, clamp01(V5_CLOUD_TRANSPARENCY - 1.0)));
    float min1CloudTransparency = min1(V5_CLOUD_TRANSPARENCY);

    #ifdef V5_CLOUD_REFLECTION
        float stepMult = 64.0;
    #elif V5_PIXELATED_UNBOUND_CLOUDS > 0
        float stepMult = 3.0;
    #elif V5_CLOUD_QUALITY_INTERNAL == 1
        float stepMult = 16.0;
    #elif V5_CLOUD_QUALITY_INTERNAL == 2
        float stepMult = 32.0;
    #elif V5_CLOUD_QUALITY_INTERNAL == 3
        float stepMult = 16.0;
    #elif V5_CLOUD_QUALITY_INTERNAL == 4
        float stepMult = 24.0;
    #endif

    #if V5_CLOUD_UNBOUND_SIZE_MULT > 100
        stepMult = stepMult / sqrt(float(V5_CLOUD_UNBOUND_SIZE_MULT_M));
    #endif

    int sampleCount = int(planeDistanceDif / stepMult + dither + 1);
    vec3 traceAdd = nPlayerPos * stepMult;
    vec3 tracePos = cameraPos + minPlaneDistance * nPlayerPos;
    tracePos += traceAdd * dither;
    tracePos.y -= traceAdd.y;

    float firstHitPos = 0.0;
    float VdotSM1 = max0(sunVisibility > 0.5 ? VdotS : - VdotS);
    float VdotSM1M = VdotSM1 * invRainFactor;
    float VdotSM2 = pow2(VdotSM1) * abs(sunVisibility - 0.5) * 2.0;
    float VdotSM3 = VdotSM2 * (2.5 + rainFactor) + 1.5 * rainFactor;
    float VdotSM4 = pow(VdotSM1M, 100.0) * sunVisibility;

    for (int i = 0; i < sampleCount; i++) {
        tracePos += traceAdd;

        if (abs(tracePos.y - cloudAltitude) > cloudStretchV5U) break;

        vec3 cloudPlayerPos = tracePos - cameraPos;
        float lTracePos = length(cloudPlayerPos);
        float lTracePosXZ = length(cloudPlayerPos.xz);
        float cloudMult = 1.0;
        if (lTracePosXZ > distanceThreshold) break;
        if (lTracePos > lViewPosM) {
            if (skyFade < 0.7) continue;
            else cloudMult = skyMult0;
        }

        #if V5_PIXELATED_UNBOUND_CLOUDS > 0
            float cloudWind = 0.0006;
            #if V5_CLOUD_SPEED_MULT == 100
                cloudWind *= cloudtime;
            #else
                cloudWind *= frameTimeCounter * (V5_CLOUD_SPEED_MULT * 0.01);
            #endif

            float cloudTraceScale = cloudNarrownessU;

            #if V5_CLOUD_UNBOUND_SIZE_MULT != 100
                cloudWind *= V5_CLOUD_UNBOUND_SIZE_MULT_M;
                cloudTraceScale *= V5_CLOUD_UNBOUND_SIZE_MULT_M;
            #endif

            vec3 cloudWindOffset = vec3(0.0, 0.0, (cloudWind / cloudTraceScale) * pixelatedUnboundWindSpeedMultV5);
            #if V5_CLOUD_DIRECTION == 1
                cloudWindOffset.xz = cloudWindOffset.zx;
            #endif

            vec3 cloudTracePos = PixelateUnboundCloudPosV5(tracePos - cloudWindOffset, V5_PIXELATED_UNBOUND_CLOUDS);
        #else
            vec3 cloudTracePos = tracePos;
        #endif

        float cloudNoise = GetCloudNoiseV5U(tracePos, cloudAltitude, lTracePosXZ, cloudPlayerPos.y);

        if (cloudNoise > 0.00001) {
            if (firstHitPos < 1.0) {
                firstHitPos = lTracePos;
                #if V5_CLOUD_QUALITY_INTERNAL == 1 && !defined V5_CLOUD_REFLECTION
                    tracePos.y += 4.0 * (texture2DLod(noisetex, tracePos.xz * cloudNarrownessU * 16.0, 0.0).r - 0.5);
                #endif
            }

            float opacityFactor = min1(cloudNoise * 8.0);

            #if V5_PIXELATED_UNBOUND_CLOUDS > 0
                opacityFactor = QuantizeCloudValueV5(opacityFactor, 4.0);
                float pixelStep = V5_PIXELATED_UNBOUND_CLOUDS;
                float hitDepth = max0(lTracePos - firstHitPos);
                float depthFade = exp(-hitDepth / (pixelStep * 2.6));
                opacityFactor *= mix(0.62, 1.0, depthFade);
            #endif

            float cloudTransparency = opacityFactor * min1CloudTransparency;

            opacityFactor *= cloudTransparency;

            float cloudSampleY = tracePos.y;
            #if V5_PIXELATED_UNBOUND_CLOUDS > 0
                cloudSampleY = mix(cloudTracePos.y, tracePos.y, 0.66);
            #endif

            float cloudShading = 1.0 - (higherPlaneAltitude - cloudSampleY) / cloudTallnessV5U;

            cloudShading *= 1.0 + 0.2 * VdotSM3 * (1.0 - opacityFactor) + VdotSM4;
            #if V5_CLOUD_SHADING_AMOUNT != 10
                cloudShading = pow(max0(cloudShading), V5_CLOUD_SHADING_AMOUNT * 0.1);
            #endif
            #if V5_PIXELATED_UNBOUND_CLOUDS > 0
                cloudShading *= 0.9;

                float voxelVariation = GetVoxelCloudVariationV5(cloudTracePos, pixelStep);
                float voxelShade = mix(0.85, 1.2, voxelVariation);
                float cloudHeight01 = clamp01((tracePos.y - lowerPlaneAltitude) / cloudTallnessV5U);
                float reverseHeight01 = 1.0 - cloudHeight01;
                float undersideLift = reverseHeight01 * mix(0.05, 0.10, sunVisibility);

                cloudShading *= voxelShade;
                cloudShading += undersideLift;
            #endif

            #if V5_CLOUD_SUN_MOON_SHADING > 0
                float visibilityFactor = 1.0;
                #if V5_CLOUD_SUN_MOON_SHADING == 1
                    visibilityFactor = 1.0 - sunVisibility;
                #elif V5_CLOUD_SUN_MOON_SHADING == 2
                    visibilityFactor = sunVisibility;
                #endif

                if (visibilityFactor > 0.0) {
                    vec3 worldLightVec = mat3(gbufferModelViewInverse) * sunVec;
                    float cloudLightRadius = 375.0;

                    float aboveFade = clamp01(1.0 - (cameraPos.y - cloudAltitude) / (cloudTallnessV5U * 3.0));
                    float radiusFactor = mix(cloudLightRadius * 8.0, cloudLightRadius, aboveFade);
                    float moonVisibility = abs(1.0 - moonPhase / 4.0);
                    float sunMult = mix(moonVisibility, 0.85, sunVisibility);

                    float sunPlaneIntersect = (cloudAltitude - cameraPos.y) / worldLightVec.y;
                    vec2 posVector = cameraPos.xz + worldLightVec.xz * sunPlaneIntersect - tracePos.xz;
                    float falloff = exp((1.0 - max0(1.0 - length(posVector) / radiusFactor)) * -6.0) * aboveFade * sunMult;

                    float sunShadingFactor = clamp01(falloff * mix(1.0, 2.0, aboveFade) * mix(1.0, (lTracePos - minPlaneDistance) / (maxPlaneDistance - minPlaneDistance), 0.75));

                    vec3 bloodMoonCloudColor = vec3(1.0);
                    #if BLOOD_MOON > 0
                        bloodMoonCloudColor = mix(bloodMoonCloudColor, vec3(0.302, 0.0078, 0.0078) * 5, getBloodMoonVisibility(sunVisibility, worldDay, moonPhase));
                    #endif

                    #if V5_PIXELATED_UNBOUND_CLOUDS > 0
                        visibilityFactor *= 0.2;
                    #endif

                    cloudLightColorV5 += bloodMoonCloudColor * sunShadingFactor * 0.3 * visibilityFactor;
                    cloudShading += sunShadingFactor * 0.45 * visibilityFactor;
                }
            #endif

            #if BLOOD_MOON > 0
                float v5BloodMoonU = getBloodMoonVisibility(sunVisibility, worldDay, moonPhase);
                vec3 hsvCloudLightColor = rgb2hsvV5(cloudLightColorV5);
                cloudLightColorV5 = mix(cloudLightColorV5, hsv2rgbV5(vec3(0.0, max(0.66, hsvCloudLightColor.y), hsvCloudLightColor.z)), v5BloodMoonU);
            #endif

            vec3 colorSample = cloudAmbientColorV5 * (0.4 + 0.6 * cloudShading) + cloudLightColorV5 * cloudShading;

            float distanceRatio = (distanceThreshold - lTracePosXZ) / distanceThreshold;
            float cloudDistanceFactor = clamp(distanceRatio, 0.0, 0.8) * 1.25;
            float cloudFogFactor = pow2(pow1_5(clamp(distanceRatio, 0.0, 1.0))) * 0.69;
            cloudFogFactor = mix(1.0, cloudFogFactor, skyFadeM);

            vec3 cloudSkyColor = GetSkyColor(lightCol, VdotU, normalize(viewPos), false);
            colorSample *= 1.0 - 0.2 * (1.0 - skyFadeM) * max(sunVisibility2V5, nightFactorV5);
            colorSample = mix(cloudSkyColor, colorSample, cloudFogFactor * 0.69);
            colorSample *= pow2(1.0 - maxBlindnessDarknessV5);

            volumetricClouds.rgb = mix(volumetricClouds.rgb, colorSample, 1.0 - min1(volumetricClouds.a));
            volumetricClouds.a += opacityFactor * pow(cloudDistanceFactor, 0.5 + 10.0 * pow(abs(VdotSM1M), 90.0)) * cloudMult;
            #if V5_PIXELATED_UNBOUND_CLOUDS > 0
                volumetricClouds.a += mix(0.0, min(1.0 - pow5(distanceRatio * 0.99), 0.2), cloudTransparency * (1.0 - min1(15 * pow(abs(VdotSM1M), 130.0))));
            #endif

            if (volumetricClouds.a > 0.9) {
                volumetricClouds.a = 1.0;
                break;
            }
        }
    }

    if (volumetricClouds.a > 0.5) { cloudLinearDepth = sqrt(firstHitPos / renderDistanceV5); }

    volumetricClouds.a *= 0.5 + 0.5 * skyFadeM;

    return volumetricClouds;
}
