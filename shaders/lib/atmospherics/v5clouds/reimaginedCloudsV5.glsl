// Ported from Complementary V5 lib/atmospherics/clouds/reimaginedClouds.glsl
// Reimagined-style volumetric clouds (2.5D coverage-texture raymarch).
// Stripped deps: SHADOW_QUALITY/shadowtex, AURORA_INFLUENCE, SAVE_SKYBOX_DATA,
// ATM_COLOR_MULTS, DOUBLE_REIM_CLOUDS, RAIN_ATMOSPHERE (lightning), IRIS int cam.
// Blood moon uses V4's getBloodMoonVisibility(sunVisibility, worldDay, moonPhase).
// Requires: noisetex, gaux1 (cloud coverage texture bound via texture.gbuffers.gaux1
//           or texture.deferred.gaux1), V4 helpers (pow2, clamp01, min1, max0,
//           InterleavedGradientNoiseForCloudsV5, cloud color globals).

const float cloudStretchV5 = V5_CLOUD_STRETCH * 4.2;
const float cloudTallnessV5 = cloudStretchV5 * 2.0;
const float cloudRoundnessV5 = V5_CLOUD_ROUNDNESS;

bool GetCloudNoiseV5R(vec3 tracePos, inout vec3 tracePosM, int cloudAltitude, float cloudStretchParam) {
    tracePosM = ModifyTracePosV5(tracePos, cloudAltitude);
    vec2 coord = GetRoundedCloudCoordV5(tracePosM.xz, cloudRoundnessV5);

    float noise = texture2D(gaux1, coord).b;

    float threshold = clamp(abs(cloudAltitude - tracePos.y) / cloudStretchParam, 0.001, 0.999);
    threshold = pow2(pow2(pow2(threshold)));
    return noise > threshold * 0.5 + 0.25;
}

float Get2DCloudSampleV5(vec2 pos) {
    return texture2D(gaux1, GetRoundedCloudCoordV5(pos, cloudRoundnessV5)).b;
}

vec4 GetVolumetricCloudsV5R(int cloudAltitude, float distanceThreshold, inout float cloudLinearDepth, float skyFade, float skyMult0, vec3 cameraPos, vec3 nPlayerPos, float lViewPosM, float VdotS, float VdotU, float dither, vec3 sunVec, vec3 viewPos) {
    vec4 volumetricClouds = vec4(0.0);

    float higherPlaneAltitude = cloudAltitude + cloudStretchV5;
    float lowerPlaneAltitude  = cloudAltitude - cloudStretchV5;

    float lowerPlaneDistance  = (lowerPlaneAltitude - cameraPos.y) / nPlayerPos.y;
    float higherPlaneDistance = (higherPlaneAltitude - cameraPos.y) / nPlayerPos.y;
    float minPlaneDistance = min(lowerPlaneDistance, higherPlaneDistance);
          minPlaneDistance = max(minPlaneDistance, 0.0);
    float maxPlaneDistance = max(lowerPlaneDistance, higherPlaneDistance);
    if (maxPlaneDistance < 0.0) return vec4(0.0);
    float planeDistanceDif = maxPlaneDistance - minPlaneDistance;

    float aboveClouds = clamp01((cameraPos.y - lowerPlaneAltitude) * 0.05);
    float skyFadeM = mix(skyFade, 1.0, mix(0.4 * max(aboveClouds, rainFactor2), 1.0, clamp01(V5_CLOUD_TRANSPARENCY - 1.0)));
    float min1CloudTransparency = min1(V5_CLOUD_TRANSPARENCY);

    #if V5_CLOUD_QUALITY_INTERNAL == 1 || defined V5_CLOUD_REFLECTION
        int sampleCount = max(int(planeDistanceDif) / 16, 6);
    #elif V5_CLOUD_QUALITY_INTERNAL == 2
        int sampleCount = max(int(planeDistanceDif) / 8, 12);
    #elif V5_CLOUD_QUALITY_INTERNAL == 3 || V5_CLOUD_QUALITY_INTERNAL == 4
        int sampleCount = max(int(planeDistanceDif), 12);
    #endif

    float stepMult = planeDistanceDif / sampleCount;
    vec3 traceAdd = nPlayerPos * stepMult;
    vec3 tracePos = cameraPos + minPlaneDistance * nPlayerPos;
    tracePos += traceAdd * dither;
    tracePos.y -= traceAdd.y;

    for (int i = 0; i < sampleCount; i++) {
        tracePos += traceAdd;

        vec3 cloudPlayerPos = tracePos - cameraPos;
        float lTracePos = length(cloudPlayerPos);
        float lTracePosXZ = length(cloudPlayerPos.xz);
        float cloudMult = 1.0;
        if (lTracePosXZ > distanceThreshold) break;
        if (lTracePos > lViewPosM) {
            if (skyFade < 0.7) continue;
            else cloudMult = skyMult0;
        }

        vec3 tracePosM;
        if (GetCloudNoiseV5R(tracePos, tracePosM, cloudAltitude, cloudStretchV5)) {
            float lightMult = 1.0;

            float cloudShading = 1.0 - (higherPlaneAltitude - tracePos.y) / cloudTallnessV5;
            cloudShading = pow(max0(cloudShading), max0(V5_CLOUD_SHADING_AMOUNT * 0.1 - 0.2));
            float VdotSM1 = max0(sunVisibility > 0.5 ? VdotS : - VdotS);

            #if V5_CLOUD_QUALITY_INTERNAL >= 2 && !defined V5_CLOUD_REFLECTION
                float cloudShadingM = 1.0 - pow2(cloudShading);

                float gradientNoise = InterleavedGradientNoiseForCloudsV5();

                vec3 cLightPos = tracePosM;
                #if V5_REIMAGINED_CLOUDS_OUTLINE > 0
                    vec3 cLightPosAdd = nPlayerPos * V5_REIMAGINED_CLOUDS_OUTLINE * cloudTallnessV5 * 0.01;
                    float tempCloudOutlineThickness = 0.0;
                #else
                    vec3 cLightPosAdd = normalize(ViewToPlayerV5(lightVec * 1000000000.0)) * vec3(0.08) * shadowTime;
                    float tempCloudOutlineThickness = 1.0;
                #endif

                float light = 2.0;
                cLightPos += (tempCloudOutlineThickness + gradientNoise) * cLightPosAdd;
                    light -= Get2DCloudSampleV5(cLightPos.xz) * cloudShadingM;
                cLightPos += gradientNoise * cLightPosAdd;
                    light -= Get2DCloudSampleV5(cLightPos.xz) * cloudShadingM;

                float VdotSM2 = VdotSM1 * shadowTime * 0.25;
                      VdotSM2 += 0.5 * cloudShading + 0.08;
                cloudShading = VdotSM2 * light * lightMult;
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

                    float aboveFade = 1.0 - smoothstep(-20.0, 0.0, cameraPos.y - cloudAltitude);
                    float sunPlaneIntersect = (cloudAltitude - cameraPos.y) / worldLightVec.y;
                    vec2 posVector = cameraPos.xz + worldLightVec.xz * sunPlaneIntersect - tracePos.xz;

                    float moonVisibility = abs(1.0 - moonPhase / 4.0);
                    float sunMult = mix(moonVisibility, 0.75, sunVisibility);
                    float falloff = exp((1.0 - max0(1.0 - length(posVector) / cloudLightRadius)) * -6.0) * aboveFade * sunMult;

                    float sunCloudMult = clamp01(falloff * 2.5 * mix(1.0, (lTracePos - minPlaneDistance) / (maxPlaneDistance - minPlaneDistance), 0.6));

                    vec3 bloodMoonCloudColor = vec3(1.0);
                    #if BLOOD_MOON > 0
                        bloodMoonCloudColor = mix(bloodMoonCloudColor, vec3(0.302, 0.0078, 0.0078) * 5, getBloodMoonVisibility(sunVisibility, worldDay, moonPhase));
                    #endif

                    cloudLightColorV5 += bloodMoonCloudColor * sunCloudMult * 0.11 * visibilityFactor;
                    cloudShading += sunCloudMult * 1.5 * visibilityFactor;
                }
            #endif

            #if BLOOD_MOON > 0
                float v5BloodMoon = getBloodMoonVisibility(sunVisibility, worldDay, moonPhase);
                vec3 hsvCloudLightColor = rgb2hsvV5(cloudLightColorV5);
                cloudLightColorV5 = mix(cloudLightColorV5, hsv2rgbV5(vec3(0.0, max(0.66, hsvCloudLightColor.y), hsvCloudLightColor.z)), v5BloodMoon);
            #endif

            vec3 colorSample = cloudAmbientColorV5 * 0.95 * (1.0 - 0.35 * cloudShading) + cloudLightColorV5 * 0.9 * (0.1 + cloudShading);

            float distanceRatio = (distanceThreshold - lTracePosXZ) / distanceThreshold;
            float cloudFogFactor = pow2(clamp(distanceRatio, 0.0, 1.0)) * 0.707;
            cloudFogFactor = mix(1.0, cloudFogFactor, skyFadeM);
            float nightCloudRemove = V5_NIGHT_CLOUD_UNBOUND_REMOVE * (1.0 - sunVisibility) * -1 + 1.0; // mapped to 1 to 0 range

            vec3 cloudSkyColor = GetSkyColor(lightCol, VdotU, normalize(viewPos), false);

            cloudMult *= min1CloudTransparency * nightCloudRemove;

            colorSample *= 1.0 - 0.2 * (1.0 - skyFadeM) * max(sunVisibility2V5, nightFactorV5);
            colorSample = mix(cloudSkyColor, colorSample, cloudFogFactor * 0.707);
            colorSample *= pow2(1.0 - maxBlindnessDarknessV5);

            float cloudDistanceFactor = clamp(distanceRatio, 0.0, 0.75);

            volumetricClouds.a = sqrt(cloudDistanceFactor * 1.33333) * cloudMult;
            volumetricClouds.rgb = colorSample;

            cloudLinearDepth = sqrt(lTracePos / renderDistanceV5);
            break;
        }
    }

    volumetricClouds.a *= 0.5 + 0.5 * skyFadeM;

    return volumetricClouds;
}
