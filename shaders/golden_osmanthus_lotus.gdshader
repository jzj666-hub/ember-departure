shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Pure Radiant Golden Osmanthus Blooming Lotus Shader (蟾宫金莲)
// Pure golden yellow hues, molten gold veins, crystalline moonlit edges.

uniform vec4 color_pure_gold : source_color = vec4(1.0, 0.76, 0.05, 0.95);    // Imperial Pure Gold
uniform vec4 color_bright_sun : source_color = vec4(1.0, 0.92, 0.40, 0.95);   // Luminous Sun Gold
uniform vec4 color_moon_halo : source_color = vec4(1.0, 0.98, 0.80, 0.90);    // Sacred Moonlight White-Gold

uniform float pulse_speed : hint_range(0.0, 10.0) = 3.0;
uniform float growth_progress : hint_range(0.0, 1.0) = 1.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	if (UV.y > growth_progress) {
		discard;
	}

	float center_dist = abs(UV.x - 0.5) * 2.0;
	float edge_glow = pow(clamp(center_dist, 0.0, 1.0), 2.5);
	
	// Golden radial leaf vein
	float vein = sin(UV.x * 24.0 + (UV.y - 0.5) * 4.0) * 0.5 + 0.5;
	float center_vein = smoothstep(0.12, 0.0, center_dist);
	float vein_pattern = pow(mix(vein, 1.0, center_vein), 2.2);
	
	float y = UV.y;
	vec3 base_col = mix(color_pure_gold.rgb, color_bright_sun.rgb, smoothstep(0.1, 0.7, y));
	base_col = mix(base_col, color_moon_halo.rgb, clamp(vein_pattern * 0.45 + edge_glow * 0.5, 0.0, 1.0));
	
	float fresnel = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	base_col += color_moon_halo.rgb * (fresnel * 0.5);
	
	float tip_fade = sin(clamp(UV.y / max(growth_progress, 0.001), 0.0, 1.0) * 3.1415926);
	tip_fade = pow(tip_fade, 0.35);
	
	float alpha = (0.6 + edge_glow * 0.4 + vein_pattern * 0.4 + fresnel * 0.4) * tip_fade * fade * color_pure_gold.a;
	
	ALBEDO = base_col * 1.25;
	ALPHA = clamp(alpha, 0.0, 0.98);
}
