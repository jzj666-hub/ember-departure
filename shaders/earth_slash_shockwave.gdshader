shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Pure Procedural Shockwave & Ground Impact Ring Shader (Zero Texture Dependencies)

uniform vec4 ring_color : source_color = vec4(1.4, 0.70, 0.18, 0.95);
uniform vec4 core_color : source_color = vec4(2.2, 2.0, 1.5, 1.0);
uniform float expansion : hint_range(0.0, 1.0) = 0.0;
uniform float thickness : hint_range(0.02, 0.5) = 0.15;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

float hash(vec2 p) {
	p = fract(p * vec2(234.34, 435.34));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
	           mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 center = UV - vec2(0.5);
	float dist = length(center) * 2.0; // 0.0 at center, 1.0 at edge

	// Expanding ring radius
	float target_r = expansion * 0.95;
	float ring_dist = abs(dist - target_r);

	// Procedural ray/noise distortion around ring perimeter
	float angle = atan(center.y, center.x);
	float n = noise(vec2(angle * 4.0, dist * 8.0 - TIME * 3.0));
	float dynamic_thick = thickness * (0.8 + 0.4 * n);

	float ring_val = 1.0 - smoothstep(0.0, dynamic_thick, ring_dist);
	float core_val = 1.0 - smoothstep(0.0, dynamic_thick * 0.35, ring_dist);

	vec3 col = mix(ring_color.rgb, core_color.rgb, core_val);

	// Radial edge fade
	float edge_fade = 1.0 - smoothstep(0.85, 1.0, dist);
	float alpha = clamp(ring_val * edge_fade * fade, 0.0, 1.0);

	ALBEDO = col;
	ALPHA = alpha;
}
