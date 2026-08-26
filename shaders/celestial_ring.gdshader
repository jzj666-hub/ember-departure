shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Celestial Thunder Ring (头顶高空天轨外环 - 紫金白三色与柔和发光)
uniform vec4 ring_violet : source_color = vec4(0.62, 0.20, 0.95, 0.80); // Plasma violet
uniform vec4 ring_gold : source_color = vec4(0.95, 0.78, 0.30, 0.85);    // Radiant gold
uniform vec4 ring_core : source_color = vec4(1.30, 1.25, 1.40, 0.85);   // Soft white core
uniform float spin_speed : hint_range(-10.0, 10.0) = 1.0;
uniform float thickness : hint_range(0.01, 0.4) = 0.07;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float brightness : hint_range(0.1, 3.0) = 1.15;

uniform sampler2D ring_tex : source_color, hint_default_black, filter_linear_mipmap;
uniform float tex_mix : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float angle = atan(p.y, p.x);

	// Thin, sharp celestial ring profile
	float ring = 1.0 - abs(r - 0.85) / thickness;
	ring = clamp(ring, 0.0, 1.0);
	ring = pow(ring, 2.0);

	// Rotating electric tooth pulsations
	float teeth = sin(angle * 16.0 + TIME * spin_speed * 3.5) * 0.20 + 0.80;
	float core_spark = pow(clamp(1.0 - abs(r - 0.85) / (thickness * 0.35), 0.0, 1.0), 2.5);

	float mask = ring * teeth;
	if (tex_mix > 0.0) {
		float sheet = texture(ring_tex, UV).r;
		mask = mix(mask, sheet, tex_mix);
	}

	vec3 col = mix(ring_violet.rgb, ring_gold.rgb, clamp(mask * 1.2, 0.0, 1.0));
	col = mix(col, ring_core.rgb, core_spark * 0.7);

	ALBEDO = col * brightness;
	ALPHA = clamp(mask * fade * ring_violet.a, 0.0, 1.0);
}
