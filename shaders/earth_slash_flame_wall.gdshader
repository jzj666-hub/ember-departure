shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Pure Procedural Rising Fissure Flame Shader (Zero Texture Dependencies)
// Replicates the roaring, volumetric vertical flames rising from earth fissures.

uniform vec4 core_color : source_color = vec4(2.2, 1.9, 1.2, 1.0);     // Incandescent white-gold base
uniform vec4 mid_color : source_color = vec4(1.5, 0.65, 0.08, 1.0);     // Searing bright orange-amber flame
uniform vec4 edge_color : source_color = vec4(0.85, 0.18, 0.02, 0.90);  // Volcanic deep red rim
uniform vec4 soot_color : source_color = vec4(0.12, 0.02, 0.01, 0.85);  // Scorched smoky tips

uniform float intensity : hint_range(0.0, 4.0) = 1.4;
uniform float flame_density : hint_range(1.0, 16.0) = 4.5;
uniform float rise_speed : hint_range(0.0, 10.0) = 4.2;
uniform float tip_dissipate : hint_range(0.5, 4.0) = 1.6;
uniform float grow_progress : hint_range(0.0, 1.0) = 1.0; // Grows forward along Y (0 root -> 1 tip)
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
	// UV.x runs lateral across flame quad (0 to 1)
	// UV.y: 1.0 = ground base, 0.0 = flame top
	float height_t = 1.0 - clamp(UV.y, 0.0, 1.0); // 0 at ground, 1 at top

	// Forward growth along fissure line
	// Note: UV coordinate can be mapped along the fissure length
	float forward_t = UV.x; // along length if oriented along length

	// Upward roaring flame noise
	vec2 sc = vec2(UV.x * flame_density, height_t * flame_density * 0.8 - TIME * rise_speed);
	float n = fbm2(sc);
	float n_detail = vnoise2(sc * 2.5 + vec2(0.0, -TIME * rise_speed * 1.5));

	// Flame core body & licking tongue shapes
	float flame_body = (1.0 - height_t) + (n - 0.45) * 0.85 + (n_detail - 0.5) * 0.35;
	flame_body = clamp(flame_body, 0.0, 1.0);
	flame_body = pow(flame_body, mix(0.9, 2.4, tip_dissipate * 0.35));

	// Smooth curved lateral edge fade
	float side_fade = pow(max(sin(clamp(UV.x, 0.0, 1.0) * 3.1415926), 0.0), 0.45);

	// Color gradient: White-gold root -> Bright amber body -> Crimson tongues -> Soot tip
	vec3 col = mix(edge_color.rgb, mid_color.rgb, smoothstep(0.15, 0.55, flame_body));
	col = mix(col, core_color.rgb, smoothstep(0.65, 0.95, flame_body) * (1.0 - height_t * 0.7));

	// Ground root glow boost
	float root_boost = (1.0 - smoothstep(0.0, 0.25, height_t)) * 0.5;
	col += core_color.rgb * root_boost;

	float alpha = clamp(flame_body * side_fade * fade * intensity, 0.0, 1.0);

	ALBEDO = col;
	ALPHA = alpha;
}
