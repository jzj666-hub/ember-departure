shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Grand Spectacular Atomic / Volcanic Black-Red Billowing Flame Column
// Towering 6m+ height, expansive mushroom plume crown, searing blood-crimson lava swirls & dark volcanic smoke.

uniform vec4 flame_blood_crimson : source_color = vec4(0.95, 0.02, 0.10, 0.96);
uniform vec4 smoke_dark_charcoal : source_color = vec4(0.05, 0.00, 0.01, 0.94);
uniform vec4 vein_carmine_glow : source_color = vec4(1.0, 0.35, 0.15, 0.98);
uniform vec4 base_blue_plasma : source_color = vec4(0.02, 0.85, 1.60, 0.95);

uniform float speed : hint_range(0.0, 20.0) = 5.6;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	// h: 0.0 at base of lotus, 1.0 at sky top
	float h = 1.0 - UV.y;
	
	// Expansive atomic mushroom expansion crown: slender lower pillar -> dramatic wide billowing crown
	float expansion = 0.38 + 0.15 * h + 0.65 * smoothstep(0.48, 0.95, h);
	float dist_from_stem = abs(UV.x - 0.5) * 2.0 / max(expansion, 0.01);
	if (dist_from_stem > 1.0) {
		discard;
	}
	
	// 1. Multi-harmonic rolling volcanic smoke eddies (高密度黑红翻滚巨浪)
	vec2 uv_move = vec2(UV.x * 4.2, h * 6.0 - TIME * speed);
	float n1 = sin(uv_move.x * 4.5 + sin(uv_move.y * 6.0));
	float n2 = cos(uv_move.x * 8.0 - uv_move.y * 7.5 + 1.57);
	float n3 = sin(uv_move.x * 14.0 + uv_move.y * 12.0);
	float n4 = cos(uv_move.x * 22.0 - uv_move.y * 18.0);
	float billow = (n1 * 0.40 + n2 * 0.30 + n3 * 0.20 + n4 * 0.10) * 0.5 + 0.5;
	billow = pow(billow, 1.3);
	
	// 2. Lateral & Top Soft Edge
	float side_fade = smoothstep(1.0, 0.18, dist_from_stem);
	float top_fade = smoothstep(1.0, 0.72, h) * smoothstep(0.0, 0.04, h);
	
	// 3. Incandescent Blood Crimson Core with Black Volcanic Smoke Mantle
	float core_intensity = clamp((1.0 - dist_from_stem * 0.75) * (billow * 0.85 + 0.35), 0.0, 1.0);
	
	vec3 col = mix(smoke_dark_charcoal.rgb, flame_blood_crimson.rgb, smoothstep(0.20, 0.68, core_intensity));
	col = mix(col, vein_carmine_glow.rgb, smoothstep(0.65, 0.92, core_intensity));
	col = mix(col, vec3(1.2, 0.8, 0.4), smoothstep(0.90, 1.0, core_intensity)); // White-hot lava core
	
	// High-energy azure plasma eruption at lotus base
	float blue_mask = smoothstep(0.30, 0.0, h) * (1.0 - dist_from_stem * 0.5);
	col = mix(col, base_blue_plasma.rgb, blue_mask * 0.90);
	
	float alpha = (0.40 + billow * 0.60) * side_fade * top_fade * fade;
	
	ALBEDO = col * 1.15;
	ALPHA = clamp(alpha, 0.0, 0.98);
}
