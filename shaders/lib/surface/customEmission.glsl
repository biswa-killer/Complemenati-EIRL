#ifndef INCLUDE_CUSTOM_EMISSION
#define INCLUDE_CUSTOM_EMISSION

#if IPBR_EMISSIVE_MODE != 1
float GetCustomEmissionForIPBR(vec2 coord, float curEmissive) {
    #ifdef MC_SPECULAR_MAP
        vec4 specularMap = texture2D(specular, coord);

        #if IPBR_EMISSIVE_MODE == 2 // seuspbr > IPBR+
            if (specularMap.b > 0.0) {
                return specularMap.b * EMISSIVE_MULTIPLIER;
            }
        #elif IPBR_EMISSIVE_MODE == 3 // labPBR > IPBR+
            if (specularMap.a > 0.0 && specularMap.a < 1.0) {
                vec4 specularMapL0 = texture2DLod(specular, coord, 0);
                float emissionL0 = specularMapL0.a < 1.0 ? specularMapL0.a : 0.0;
                return min(specularMap.a, emissionL0) * EMISSIVE_MULTIPLIER;
            }
        #endif
    #endif

    return curEmissive;
}
#else
float GetCustomEmissionForIPBR(vec2 coord, float curEmissive) {
    return curEmissive;
}
#endif

#endif // INCLUDE_CUSTOM_EMISSION
