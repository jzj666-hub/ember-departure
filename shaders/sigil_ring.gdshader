shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled;

// Ground Rune Sigil & Binding Magic Circle
uniform vec4 sigil_color : source_color = vec4(0.1, 1.0, 0.45, 0.85);
uniform float spin_speed = 1.5;
uniform float fade = 1.0;

void fragment() {
	vec2 center = UV - vec2(0.5);
	float dist = length(center) * 2.0;
	float angle = atan(center.y, center.x);

	// Ring bands
	float ring1 = smoothstep(0.04, 0.0, abs(dist - 0.85));
	float ring2 = smoothstep(0.02, 0.0, abs(dist - 0.55));
	float inner_ring = smoothstep(0.03, 0.0, abs(dist - 0.25));

	// Rune radial teeth
	float teeth = sin(angle * 12.0 + TIME * spin_speed) * 0.5 + 0.5;
	float rune_pattern = smoothstep(0.3, 0.0, abs(dist - 0.70)) * teeth;

	float combined = clamp(ring1 * 1.5 + ring2 + inner_ring + rune_pattern * 1.2, 0.0, 1.0);

	ALBEDO = sigil_color.rgb;
	EMISSION = sigil_color.rgb * 2.0;
	ALPHA = combined * fade * smoothstep(1.0, 0.8, dist);
}
