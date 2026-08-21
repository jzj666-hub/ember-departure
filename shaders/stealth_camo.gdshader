shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back;

// Optical Camouflage / Stealth Translucent Cloak
uniform vec4 camo_color : source_color = vec4(0.35, 0.85, 1.0, 0.30);
uniform vec4 rim_color : source_color = vec4(0.70, 0.95, 1.0, 0.85);
uniform float rim_power : hint_range(0.5, 6.0) = 2.5;
uniform float scan_speed : hint_range(0.0, 10.0) = 2.0;
uniform float camo_alpha : hint_range(0.0, 1.0) = 0.30;

void fragment() {
	// Fresnel rim highlight for holographic boundary definition
	float fresnel = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), rim_power);

	// Subtle optical shimmer scan wave
	float scan = sin(UV.y * 28.0 - TIME * scan_speed) * 0.12 + 0.88;

	vec3 col = mix(camo_color.rgb, rim_color.rgb, fresnel * 0.7);
	float alpha = clamp((camo_alpha + fresnel * 0.4) * scan, 0.0, 1.0);

	ALBEDO = col;
	EMISSION = rim_color.rgb * fresnel * 0.75;
	ALPHA = alpha;
}
