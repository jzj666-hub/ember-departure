shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Pure Procedural 3D Roaring Volumetric Flame Shader (Zero Textures)
// High-intensity, organic roaring flames with multi-frequency vertex noise displacement.

uniform vec4 core_color : source_color = vec4(1.45, 1.25, 0.85, 1.0);     // Incandescent white-gold core
uniform vec4 mid_color : source_color = vec4(1.20, 0.52, 0.05, 1.0);      // Searing intense orange-amber
uniform vec4 edge_color : source_color = vec4(0.75, 0.14, 0.02, 0.90);    // Deep volcanic red
uniform vec4 smoke_color : source_color = vec4(0.12, 0.04, 0.02, 0.40);   // Dark smoky wisps

uniform float intensity : hint_range(0.5, 3.0) = 1.35;
uniform float rise_speed : hint_range(1.0, 12.0) = 5.0;
uniform float flame_wobble : hint_range(0.0, 0.5) = 0.22;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
	           mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.18 + vec2(13.1, 7.3);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	// Multi-frequency 3D Organic Vertex Displacement
	float h = clamp(VERTEX.y, 0.0, 4.0);
	float sway_x = sin(TIME * rise_speed * 1.6 + VERTEX.y * 3.5) * flame_wobble * h;
	float sway_z = cos(TIME * rise_speed * 1.3 + VERTEX.y * 2.8) * flame_wobble * h;
	
	// Expanding flame billows
	float pulse = 1.0 + sin(TIME * 8.0 - VERTEX.y * 4.0) * 0.12 * h;
	VERTEX.xz *= pulse;
	VERTEX.x += sway_x;
	VERTEX.z += sway_z;
}

void fragment() {
	// Height factor: 0 at base, 1 at top tip
	float h = 1.0 - clamp(UV.y, 0.0, 1.0);

	// Multi-scale procedural roaring flames
	vec2 uv_sc = vec2(UV.x * 5.0, h * 4.0 - TIME * rise_speed);
	float n_main = fbm(uv_sc);
	float n_fast = noise(uv_sc * 2.2 + vec2(sin(TIME * 6.0) * 0.2, -TIME * rise_speed * 1.5));

	// Fiery tongue profile
	float flame_shape = (1.0 - h * 0.85) + (n_main - 0.45) * 0.75 + (n_fast - 0.5) * 0.35;
	flame_shape = clamp(flame_shape, 0.0, 1.0);

	// Color gradient: Core -> Searing Amber -> Volcanic Crimson -> Smoke
	vec3 col = mix(edge_color.rgb, mid_color.rgb, smoothstep(0.18, 0.55, flame_shape));
	col = mix(col, core_color.rgb, smoothstep(0.62, 0.92, flame_shape) * (1.0 - h * 0.5));
	col = mix(col, smoke_color.rgb, smoothstep(0.80, 1.0, h));

	// Root heat boost
	float root_boost = (1.0 - smoothstep(0.0, 0.3, h)) * 0.35;
	col += core_color.rgb * root_boost;

	float alpha = clamp(flame_shape * fade * intensity * smoothstep(0.0, 0.12, h) * (1.0 - smoothstep(0.88, 1.0, h)), 0.0, 1.0);

	ALBEDO = col;
	ALPHA = alpha;
}
