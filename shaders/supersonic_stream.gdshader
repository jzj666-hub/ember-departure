shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Pure Procedural Spiral Ribbon Stream: Pure Cyan -> Deep Royal Blue -> Cosmic Violet
// 100% Analytic & Procedural: No texture artifacts, pure clean mathematical alpha blending.

uniform vec4 color_start_cyan : source_color = vec4(0.0, 0.92, 1.0, 0.95);  // Pure brilliant cyan
uniform vec4 color_mid_blue : source_color = vec4(0.12, 0.35, 1.4, 0.85);    // Deep royal blue
uniform vec4 color_end_purple : source_color = vec4(0.65, 0.12, 1.15, 0.8);  // Cosmic violet / deep purple

uniform float spiral_arms : hint_range(1.0, 16.0) = 4.0;   // Number of helical spiral ribbons
uniform float twist_turns : hint_range(0.5, 10.0) = 3.2;   // How many times ribbons wrap around the shaft
uniform float roll_speed : hint_range(0.0, 40.0) = 18.0;   // Rotation & propagation speed
uniform float streak_sharpness : hint_range(1.0, 12.0) = 4.5;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	// UV.y: 0.0 (rear trailing end) -> 1.0 (front leading tip)
	float progress = clamp(UV.y, 0.0, 1.0);
	
	// Soft feathering at ends (tapers cleanly, no hard cutoffs)
	float longitudinal_fade = sin(progress * 3.1415926);
	longitudinal_fade = pow(longitudinal_fade, 0.7);
	
	// 1. Primary Helical Spiral Ribbon (螺旋能量丝带 1)
	float phase1 = (UV.x * spiral_arms + progress * twist_turns) * 6.2831853 - TIME * roll_speed;
	float ribbon1 = sin(phase1) * 0.5 + 0.5;
	ribbon1 = pow(ribbon1, streak_sharpness);
	
	// 2. Secondary Intertwined Fine Spiral (反相/次级交织螺旋细带 2)
	float phase2 = (UV.x * (spiral_arms * 2.0) - progress * (twist_turns * 1.4)) * 6.2831853 + TIME * (roll_speed * 1.3);
	float ribbon2 = sin(phase2) * 0.5 + 0.5;
	ribbon2 = pow(ribbon2, streak_sharpness * 1.5);
	
	// 3. High-Speed Longitudinal Core Streamlines (纵向高速穿梭光丝)
	float phase3 = UV.x * 28.0 + sin(progress * 18.0 - TIME * roll_speed * 1.8) * 0.5;
	float stream_lines = pow(sin(phase3) * 0.5 + 0.5, 6.0);
	
	// Combined pure procedural pattern
	float total_ribbon = max(ribbon1 * 1.0, ribbon2 * 0.75) + stream_lines * 0.4;
	total_ribbon = clamp(total_ribbon, 0.0, 1.5);
	
	// 3-Tier Smooth Color Gradient along trajectory
	vec3 grad_col = mix(color_start_cyan.rgb, color_mid_blue.rgb, smoothstep(0.05, 0.55, progress));
	grad_col = mix(grad_col, color_end_purple.rgb, smoothstep(0.48, 0.98, progress));
	
	// Luminous Hot Core on ribbon peaks
	vec3 peak_highlight = mix(grad_col, vec3(1.4, 1.8, 2.2), clamp(ribbon1 * 0.6 + stream_lines * 0.8, 0.0, 1.0));
	
	// Alpha calculation: 100% clean and transparent between ribbons
	float alpha = total_ribbon * longitudinal_fade * fade * color_start_cyan.a;
	
	ALBEDO = peak_highlight * 1.9;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
