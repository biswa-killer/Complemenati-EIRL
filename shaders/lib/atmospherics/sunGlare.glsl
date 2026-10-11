vec3 SunGlare(vec3 color, vec3 nViewPos, vec3 lightCol) {
	// Sun/Moon glare. lightVec points toward the current celestial light (sun by day, moon by night).
	// Tight falloff tuned for this pack's tonemap/exposure so the sun/moon disc stays visible,
	// controlled by SUN_GLARE_AMOUNT / MOON_GLARE_AMOUNT. Blood Moon tint ported from Complementary Reimagined.
	float cosSp = dot(nViewPos, lightVec);

	#if SUN_GLARE_AMOUNT > 0 || MOON_GLARE_AMOUNT > 0
	if (cosSp > 0.0) {
		float cosS = cosSp;
		cosS *= cosS;
		cosS *= cosS;
		cosS *= cosS;
		float visfactor = 0.075;

		float sunGlare = cosS;
		sunGlare = visfactor / (1.0 - (1.0 - visfactor) * sunGlare) - visfactor;
		sunGlare *= cosSp;

		float rainMult = 1.0 - rainStrengthS;
		#ifdef SUN_MOON_DURING_RAIN
			rainMult = 1.0 - 0.5 * rainStrengthS;
		#endif
		sunGlare *= 0.025 * mix(MOON_GLARE_AMOUNT, SUN_GLARE_AMOUNT, sunVisibility) * rainMult;

		float shadowTime = abs(sunVisibility - 0.5) * 2.0;
		shadowTime *= shadowTime;
		sunGlare *= shadowTime * shadowTime;

		vec3 glareColor = lightCol;
		#if BLOOD_MOON > 0 && defined ALLOW_BLOOD_MOON_GLARE
			glareColor = mix(glareColor, vec3(0.9, 0.1, 0.1) * length(lightCol), getBloodMoonVisibility(sunVisibility, worldDay, moonPhase));
		#endif

		vec3 finalSunGlare = glareColor * sunGlare;

		if (isEyeInWater == 1) finalSunGlare *= underwaterColor.rgb * underwaterColor.rgb * 200.0;

		color += finalSunGlare;
	}
	#endif

	return color;
}
