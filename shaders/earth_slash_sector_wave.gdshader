shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Pure Procedural Sector Shockwave Shader (Zero Texture Dependencies)
// Displays a radiant ground sector heatwave matching the skill's attack cone.

uniform vec4 sector_color : source_color = vec4(1.2, 0.45, 0.08, 0.45);
uniform vec4 rim_color : source_color = vec4(2.0, 1.4, 0.6, 0.85);
uniform float sector_angle_deg : hint_range(10.0, 90.0) = 40.0;
uniform float expansion : hint_range(0.0, 1.0) = 1.0;
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

void fragment() {
	// Root is at UV (0.5, 0.0), pointing toward +Y (UV.y = 1.0)
	vec2 dir = UV - vec2(0.5, 0.0);
	float dist = length(dir) * 2.0; // 0.0 at root, 2.0 at outer boundary

	// Angle from forward direction (+Y)
	float ang_rad = atan(abs(dir.x), dir.y);
	float half_ang_rad = radians(sector_angle_deg);

	// Sector mask
	float angular_mask = 1.0 - smoothstep(half_ang_rad * 0.85, half_ang_rad, ang_rad);
	if (dir.y < 0.0) {
		angular_mask = 0.0;
	}

	// Forward shockwave expansion wavefront
	float wave_front = exp(-abs(dist - expansion * 1.8) * 12.0);
	float inner_fill = smoothstep(expansion * 1.8, 0.0, dist) * 0.4;

	// Procedural ground heat turbulence
	float n = noise(vec2(ang_rad * 6.0, dist * 8.0 - TIME * 4.0));
	float heat = (wave_front + inner_fill) * (0.8 + 0.3 * n);

	vec3 col = mix(sector_color.rgb, rim_color.rgb, wave_front * 1.2);
	float edge_fade = 1.0 - smoothstep(1.7, 2.0, dist);
	float alpha = clamp(heat * angular_mask * edge_fade * fade, 0.0, 1.0);

	ALBEDO = col;
	ALPHA = alpha;
}
