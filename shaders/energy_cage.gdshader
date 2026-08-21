shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled;

// Sci-Fi Energy Binding Plasma Cage
uniform vec4 cage_color : source_color = vec4(0.1, 0.95, 0.5, 0.9);
uniform vec4 rim_color : source_color = vec4(0.8, 1.0, 0.6, 1.0);
uniform float speed = 4.0;
uniform float lattice_freq = 18.0;
uniform float fade = 1.0;

void fragment() {
	float vertical_wave = sin(UV.y * lattice_freq - TIME * speed) * 0.5 + 0.5;
	float horiz_wave = sin(UV.x * 24.0 + TIME * (speed * 0.5)) * 0.5 + 0.5;
	float lattice = clamp(pow(vertical_wave * horiz_wave, 0.6) * 2.0, 0.0, 1.0);

	float fresnel = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);

	vec3 col = mix(cage_color.rgb, rim_color.rgb, fresnel);
	float alpha = clamp((lattice * 0.75 + fresnel * 0.8) * fade, 0.0, 1.0);

	ALBEDO = col;
	EMISSION = col * (1.5 + fresnel * 2.0);
	ALPHA = alpha;
}
