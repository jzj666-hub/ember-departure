shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

// Bioluminescent Thorny Vine Shader with Pulsing Sap Veins & Growth Clip
uniform vec4 bark_color : source_color = vec4(0.08, 0.35, 0.15, 1.0);
uniform vec4 thorn_color : source_color = vec4(0.25, 0.95, 0.40, 1.0);
uniform vec4 vein_glow : source_color = vec4(0.5, 1.0, 0.6, 1.0);
uniform float pulse_speed = 3.0;
uniform float growth_progress : hint_range(0.0, 1.0) = 1.0;
uniform float fade = 1.0;

void fragment() {
	// Growth clipping along length (UV.y represents length from ground to tip)
	if (UV.y > growth_progress) {
		discard;
	}

	// Longitudinal bark ridges & sap vein pulse
	float ridge = sin(UV.x * 20.0 + UV.y * 30.0) * 0.15 + 0.85;
	float sap_pulse = sin(UV.y * 18.0 - TIME * pulse_speed) * 0.5 + 0.5;
	sap_pulse = pow(sap_pulse, 3.0);

	// Blend bark and glowing thorns
	vec3 base_col = mix(bark_color.rgb, thorn_color.rgb, clamp(UV.y * 0.4, 0.0, 0.6)) * ridge;
	vec3 emissive = vein_glow.rgb * sap_pulse * 1.8;

	// Fresnel edge highlight for lush organic definition
	float fresnel = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.5);
	emissive += thorn_color.rgb * fresnel * 0.8;

	ALBEDO = base_col;
	ROUGHNESS = 0.45;
	EMISSION = emissive * fade;
	ALPHA = fade;
}
