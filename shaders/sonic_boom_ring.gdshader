shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Sonic boom shock ring & vapor expansion disc.
uniform vec4 ring_color : source_color = vec4(0.7, 0.92, 1.0, 0.85);
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float thickness : hint_range(0.01, 0.5) = 0.12;

// Painted ring sheet. tex_mix stays 0 until a caller binds a texture.
uniform sampler2D ring_tex : source_color, hint_default_black, filter_linear_mipmap;
uniform float tex_mix : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D color_ramp : source_color, hint_default_white;
uniform float ramp_mix : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);

	float ring = 1.0 - abs(r - 0.72) / thickness;
	ring = clamp(ring, 0.0, 1.0);
	ring = pow(ring, 2.2);

	float angle = atan(p.y, p.x);
	float radial_noise = sin(angle * 32.0) * 0.15 + 0.85;

	float core_glow = pow(clamp(1.0 - abs(r - 0.72) / (thickness * 0.4), 0.0, 1.0), 3.0);

	// The sheet is already a centred ring, so it is sampled straight and replaces the
	// analytic band rather than modulating it.
	float sheet = texture(ring_tex, UV).r;
	float mask = clamp(mix(ring * radial_noise, sheet, tex_mix), 0.0, 1.0);

	vec3 base = mix(ring_color.rgb, texture(color_ramp, vec2(mask, 0.5)).rgb, ramp_mix);
	vec3 final_color = mix(base, vec3(1.0), core_glow);

	ALBEDO = final_color * 1.6;
	ALPHA = mask * ring_color.a * fade;
}
