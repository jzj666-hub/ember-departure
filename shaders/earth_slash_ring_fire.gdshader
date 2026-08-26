shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Pure Procedural Ground Ring Fire & Flame Burst Shader (Zero Texture Dependencies)
// Uses blend_mix for non-glare, grounded earthen combustion.

uniform vec4 core_color : source_color = vec4(1.05, 0.95, 0.75, 1.0);
uniform vec4 mid_color : source_color = vec4(0.92, 0.44, 0.06, 0.90);
uniform vec4 edge_color : source_color = vec4(0.46, 0.09, 0.02, 0.85);
uniform vec4 crust_color : source_color = vec4(0.08, 0.04, 0.02, 0.95);

uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform float ring_radius : hint_range(0.1, 1.0) = 0.52;
uniform float ring_thickness : hint_range(0.05, 0.4) = 0.16;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * vnoise2(p);
		p = p * 2.17 + vec2(11.3, 7.1);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 center = UV - vec2(0.5);
	float dist = length(center) * 2.0; // 0 at center, 1 at quad edge
	float ang = atan(center.y, center.x);

	// Ring distance profile
	float ring_dist = abs(dist - ring_radius * 1.35);

	// High frequency flame tongues radiating outward and upward
	float n = fbm2(vec2(ang * 4.0, dist * 5.0 - TIME * 3.5));
	float dynamic_thick = ring_thickness * (0.75 + 0.5 * n);

	float flame = (1.0 - smoothstep(0.0, dynamic_thick, ring_dist)) * (0.6 + 0.6 * n);
	flame = clamp(flame, 0.0, 1.0);

	// Outer scorched border
	float is_crust = 1.0 - smoothstep(0.0, dynamic_thick * 1.5, ring_dist);

	// Color gradient without blinding glare
	vec3 col = mix(crust_color.rgb, edge_color.rgb, smoothstep(0.1, 0.4, flame));
	col = mix(col, mid_color.rgb, smoothstep(0.4, 0.75, flame));
	col = mix(col, core_color.rgb, smoothstep(0.85, 0.98, flame) * 0.8);

	float alpha = clamp(max(flame, is_crust * 0.75) * fade * intensity, 0.0, 1.0);

	ALBEDO = col;
	ALPHA = alpha;
}
