// Ported from Complementary V5 lib/atmospherics/clouds/cloudCoord.glsl
#ifndef INCLUDE_CLOUD_COORD_V5
    #define INCLUDE_CLOUD_COORD_V5

    const float cloudNarrownessV5 = V5_CLOUD_NARROWNESS;

    // Thanks to SixthSurge
    vec2 GetRoundedCloudCoordV5(vec2 pos, float cloudRoundness) { // cloudRoundness is meant to be 0.125 for clouds and 0.35 for cloud shadows
        vec2 coord = pos.yx + 0.5;
        vec2 signCoord = sign(coord);
        coord = abs(coord) + 1.0;
        vec2 i, f = modf(coord, i);
        f = smoothstep(0.5 - cloudRoundness, 0.5 + cloudRoundness, f);
        coord = i + f;
        return (coord - 0.5) * signCoord / 256.0;
    }

    vec3 ModifyTracePosV5(vec3 tracePos, int cloudAltitude) {
        // V4: cloudtime is the world-time-synced clock (WORLD_TIME_ANIMATION aware).
        // V5 used syncedTimeDynamic (world age) at CLOUD_SPEED_MULT==100.
        #if V5_CLOUD_SPEED_MULT == 100
            float wind = cloudtime;
        #else
            float wind = frameTimeCounter * (V5_CLOUD_SPEED_MULT * 0.01);
        #endif

        #if V5_CLOUD_DIRECTION == 1
            tracePos.x -= wind;
            tracePos.z += cloudAltitude * 64.0;
        #else
            tracePos.z -= wind;
            tracePos.x += cloudAltitude * 64.0;
        #endif

        tracePos.xz *= cloudNarrownessV5;
        return tracePos.xyz;
    }

#endif
