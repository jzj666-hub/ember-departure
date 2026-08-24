shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_disabled;

// Ground Rune Sigil & Binding Magic Circle
uniform vec4 sigil_color : source_color = vec4(0.1, 1.0, 0.45, 0.85);
uniform float spin_speed = 1.5;
uniform float fade = 1.0;

// Painted sigil sheet. tex_mix stays 0 until a caller binds a texture, so an unbound
// material renders exactly the procedural rings it always did.
uniform sampler2D sigil_tex : source_color, hint_default_black, filter_linear_mipmap;
uniform float tex_mix : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D color_ramp : source_color, hint_default_white;
uniform float ramp_mix : hint_range(0.0, 1.0) = 0.0;

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

	// The sheet spins as a whole, so the UV rotates about the centre rather than the mesh.
	float sa = sin(TIME * spin_speed * 0.35);
	float ca = cos(TIME * spin_speed * 0.35);
	vec2 ruv = vec2(center.x * ca - center.y * sa, center.x * sa + center.y * ca) + vec2(0.5);
	float sheet = texture(sigil_tex, ruv).r;

	float mask = clamp(mix(combined, sheet, tex_mix), 0.0, 1.0);

	// Ramp maps mask intensity to colour; at ramp_mix 0 the flat tint is kept.
	vec3 tint = mix(sigil_color.rgb, texture(color_ramp, vec2(mask, 0.5)).rgb, ramp_mix);

	ALBEDO = tint;
	EMISSION = tint * 2.0;
	ALPHA = mask * fade * smoothstep(1.0, 0.8, dist);
}
