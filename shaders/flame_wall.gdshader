shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Volumetric Deep Blood-Crimson & Clear Vibrant Azure Plasma Barrier
// Blend_mix preserves rich contrast: electric cyan-blue streams never wash out into white.

uniform vec4 flame_azure_blue : source_color = vec4(0.02, 0.72, 1.25, 0.95);  // Crisp Vibrant Cyan-Blue Plasma
uniform vec4 flame_blood_crimson : source_color = vec4(0.85, 0.02, 0.10, 0.92); // Visceral Deep Blood Red
uniform vec4 flame_dark_soot : source_color = vec4(0.10, 0.00, 0.02, 0.92);    // Dark Crimson Shadow
uniform vec4 flame_gold_wisp : source_color = vec4(1.0, 0.55, 0.12, 0.85);     // Golden Heat Sparks

uniform float speed : hint_range(0.0, 20.0) = 4.2;
uniform float flame_density : hint_range(2.0, 30.0) = 14.0;
uniform float blue_dominance : hint_range(0.0, 2.0) = 1.2;
uniform float thickness_wave : hint_range(0.0, 0.5) = 0.18;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	// Volumetric thickness undulation along the single mesh
	float wave_z = sin(UV.y * 10.0 - TIME * speed * 0.9 + UV.x * 6.0) * cos(UV.x * 8.0);
	VERTEX.z += wave_z * thickness_wave * (1.0 - UV.y * 0.3);
}

void fragment() {
	float height_ratio = 1.0 - UV.y; // 0.0 at ground, 1.0 at top
	
	// 1. Turbulent Multi-Harmonic Flame Tongues
	float f1 = sin(UV.x * flame_density + TIME * speed * 0.9) * 0.5 + 0.5;
	float f2 = sin(UV.x * (flame_density * 2.2) - TIME * speed * 1.4 + height_ratio * 6.0) * 0.5 + 0.5;
	float f3 = sin(UV.x * (flame_density * 0.7) + height_ratio * 14.0 - TIME * speed * 2.5) * 0.5 + 0.5;
	float flame_pattern = (f1 * 0.35 + f2 * 0.40 + f3 * 0.25);
	
	// Flame height dissipation
	float flame_mask = 1.0 - height_ratio;
	flame_mask += (flame_pattern - 0.5) * 0.45 * (1.0 - height_ratio * 0.35);
	flame_mask = clamp(flame_mask * 1.35, 0.0, 1.0);
	flame_mask = pow(flame_mask, 1.4);
	
	// Lateral soft border fade
	float side_fade = sin(clamp(UV.x, 0.0, 1.0) * 3.1415926);
	side_fade = pow(side_fade, 0.40);
	
	// 2. Distinct Electric Azure Blue Plasma Streams (清晰显眼的幽蓝能量流)
	float blue_stream1 = sin(UV.x * 18.0 - TIME * (speed * 1.6) + height_ratio * 8.0) * 0.5 + 0.5;
	float blue_stream2 = cos(UV.x * 10.0 + TIME * (speed * 1.1) - height_ratio * 5.0) * 0.5 + 0.5;
	float blue_flow = pow(blue_stream1 * 0.6 + blue_stream2 * 0.4, 2.2);
	
	// Ground root plasma + mid-height energy channels
	float blue_mask = (smoothstep(0.7, 0.0, height_ratio) * 0.75 + blue_flow * 0.85) * blue_dominance;
	blue_mask = clamp(blue_mask * flame_mask, 0.0, 1.0);
	
	// 3. Contrast Color Layering (深黑血红为体，极寒幽蓝为脉)
	vec3 base_blood = mix(flame_dark_soot.rgb, flame_blood_crimson.rgb, clamp(flame_mask * 1.4, 0.0, 1.0));
	base_blood = mix(base_blood, flame_gold_wisp.rgb, clamp(pow(flame_mask, 2.5) * 0.6, 0.0, 1.0));
	
	// Inject crisp, saturated Azure Blue Plasma
	vec3 col = mix(base_blood, flame_azure_blue.rgb, blue_mask);
	
	float alpha = (flame_mask * 0.75 + blue_mask * 0.25) * side_fade * fade * flame_blood_crimson.a;
	
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 0.96);
}
