shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Pure Procedural Earth Slash Fissure Shader (Zero Texture Dependencies)
// Deep-Black Abyss Core Fissure with warm magma flanks and scorched crust borders.

uniform vec4 glow_core : source_color = vec4(1.05, 0.95, 0.78, 1.0);     // Soft warm-white magma core
uniform vec4 glow_amber : source_color = vec4(0.92, 0.44, 0.06, 1.0);    // Warm molten amber
uniform vec4 glow_crimson : source_color = vec4(0.46, 0.09, 0.02, 1.0);  // Basalt deep crimson
uniform vec4 crust_color : source_color = vec4(0.10, 0.05, 0.03, 0.95);  // Scorched earth border
uniform vec4 abyss_black : source_color = vec4(0.012, 0.008, 0.008, 1.0);// Pitch-black abyss center rift

uniform float tear_progress : hint_range(0.0, 1.0) = 1.0;  // Forward propagation (0.0 root -> 1.0 tip)
uniform float heat_intensity : hint_range(0.0, 2.5) = 1.0;
uniform float fissure_width : hint_range(0.1, 2.0) = 1.0;
uniform float abyss_width : hint_range(0.02, 0.5) = 0.14;   // Width of the deep black center rift
uniform float branch_intensity : hint_range(0.0, 2.0) = 0.85;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

// 2D Pseudo-random hash
float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// 2D Value Noise with smooth hermite interpolation
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);

	float a = hash(i + vec2(0.0, 0.0));
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Fractal Brownian Motion (FBM) with 5 octaves
float fbm(vec2 p) {
	float val = 0.0;
	float amp = 0.5;
	mat2 rot = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));
	for (int i = 0; i < 5; i++) {
		val += amp * value_noise(p);
		p = rot * p * 2.02;
		amp *= 0.5;
	}
	return val;
}

// Ridge / Crack noise for sharp jagged lines
float ridge_noise(vec2 p) {
	float n = fbm(p);
	return 1.0 - abs(n * 2.0 - 1.0);
}

// Domain Warping for organic, erratic fracture paths
float fracture_map(vec2 p) {
	vec2 q = vec2(fbm(p + vec2(0.0, 0.0)), fbm(p + vec2(5.2, 1.3)));
	vec2 r = vec2(fbm(p + 3.0 * q + vec2(1.7, 9.2)), fbm(p + 3.0 * q + vec2(8.3, 2.8)));
	return fbm(p + 3.5 * r);
}

void fragment() {
	// UV.y runs 0.0 (near caster root) to 1.0 (far tip)
	// UV.x runs 0.0 (left) to 1.0 (right)
	float forward_t = UV.y;
	float lateral = (UV.x - 0.5) * 2.0; // -1.0 to +1.0

	// 1. Forward propagation tear wave
	float tip_front = smoothstep(tear_progress + 0.02, tear_progress - 0.06, forward_t);

	// 2. Procedural Meandering Main Trunk Fissure
	float meander = (fbm(vec2(forward_t * 8.0, 2.4)) - 0.5) * 0.42;
	float dist_to_center = abs(lateral - meander);
	float trunk_dist = dist_to_center / fissure_width;

	// High frequency jagged domain-warped fracture texture
	vec2 noise_uv = vec2(lateral * 6.0, forward_t * 26.0);
	float detail_fracture = fracture_map(noise_uv);
	float jagged_ridge = ridge_noise(noise_uv * 1.5);

	// Deep-Black Abyss Core Fissure down the very center line
	// Slightly modulated by jagged noise for realistic rough stone edges
	float abyss_edge_noise = detail_fracture * 0.04;
	float is_deep_black = 1.0 - smoothstep(0.0, abyss_width + abyss_edge_noise, dist_to_center);

	// Secondary branching cracks spreading to sides
	float branches = ridge_noise(vec2(lateral * 10.0 + forward_t * 12.0, forward_t * 18.0));
	branches *= smoothstep(0.8, 0.1, trunk_dist) * branch_intensity;

	// Magma glow intensity profile (brightest along abyss trench walls)
	float crack_intensity = (1.0 - smoothstep(0.02, 0.35, trunk_dist)) * (0.65 + 0.50 * jagged_ridge);
	crack_intensity = max(crack_intensity, branches * 0.70);
	crack_intensity += detail_fracture * 0.20 * (1.0 - smoothstep(0.0, 0.6, trunk_dist));

	// 3. Subtle subterranean magma breathing flow
	float flow = sin(TIME * 4.0 - forward_t * 10.0) * 0.06 + 0.94;

	// Multi-tier Color Layering:
	// Deep Black Trench -> Magma Wall Flanks -> Soft Magma Core -> Scorched Crust Border
	float is_crust = smoothstep(0.06, 0.45, crack_intensity);
	float is_molten = smoothstep(0.35, 0.70, crack_intensity);
	float is_core = smoothstep(0.70, 0.95, crack_intensity);

	vec3 magma_col = mix(glow_crimson.rgb, glow_amber.rgb, is_molten);
	magma_col = mix(magma_col, glow_core.rgb, is_core * 0.70);
	magma_col *= heat_intensity * flow;

	vec3 wall_color = mix(crust_color.rgb, magma_col, is_molten);

	// Carve the pitch-black abyss fissure right down the middle
	vec3 final_color = mix(wall_color, abyss_black.rgb, is_deep_black * 0.92);

	// Outer boundary smooth fades
	float lateral_fade = smoothstep(1.0, 0.60, abs(lateral));
	float tip_fade = smoothstep(1.0, 0.90, forward_t);
	float root_fade = smoothstep(0.0, 0.04, forward_t);

	float alpha_base = max(is_crust, is_deep_black);
	float alpha = clamp(alpha_base * tip_front * lateral_fade * tip_fade * root_fade * fade, 0.0, 1.0);

	ALBEDO = final_color;
	ALPHA = alpha;
}
