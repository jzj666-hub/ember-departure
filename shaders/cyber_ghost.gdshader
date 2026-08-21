shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled, unshaded;

// Cyberpunk Hologram Afterimage with Glitch Jitter and Scanline Dissolve.

uniform vec4 neon_color : source_color = vec4(0.0, 0.94, 1.0, 0.85);
uniform vec4 secondary_color : source_color = vec4(1.0, 0.05, 0.55, 0.9);
uniform float glitch_intensity : hint_range(0.0, 1.0) = 0.35;
uniform float dissolve_progress : hint_range(0.0, 1.0) = 0.0;
uniform float scanline_density : hint_range(5.0, 100.0) = 45.0;
uniform float fresnel_power : hint_range(0.5, 6.0) = 2.2;

// Pseudo-random generator
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void vertex() {
	// High-frequency cyber glitch vertex displacement
	if (glitch_intensity > 0.001) {
		float t = floor(TIME * 45.0);
		float slice = floor(VERTEX.y * 12.0 + t);
		float rnd = hash(vec2(slice, t)) - 0.5;
		if (abs(rnd) > 0.32) {
			VERTEX.x += rnd * glitch_intensity * 0.18;
			VERTEX.z += (hash(vec2(t, slice)) - 0.5) * glitch_intensity * 0.12;
		}
	}
}

void fragment() {
	// Fresnel rim glow
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
	
	// Scanlines scrolling vertically
	float scanline = sin((VERTEX.y + TIME * 3.5) * scanline_density) * 0.5 + 0.5;
	scanline = smoothstep(0.2, 0.8, scanline);

	// Digital noise dissolve
	vec2 noise_uv = UV * 18.0 + vec2(floor(TIME * 20.0) * 0.1, 0.0);
	float digital_noise = hash(floor(noise_uv));
	
	if (digital_noise < dissolve_progress) {
		discard;
	}

	// Mix dual neon colors based on fresnel and height
	vec3 color = mix(neon_color.rgb, secondary_color.rgb, fresnel * 0.7);
	float alpha = mix(neon_color.a * 0.35, 1.0, fresnel);
	alpha *= mix(0.4, 1.0, scanline);
	alpha *= (1.0 - dissolve_progress * 0.85);

	ALBEDO = color * (1.2 + fresnel * 1.5);
	ALPHA = clamp(alpha, 0.0, 1.0);
}
