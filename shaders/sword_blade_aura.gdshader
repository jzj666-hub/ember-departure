shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Celestial Flying Sword Energy Aura & Razor Blade Glare (凌霄飞剑破空剑气与锋刃高光)
uniform vec4 aura_color : source_color = vec4(0.20, 0.85, 1.0, 0.85);
uniform vec4 core_color : source_color = vec4(1.2, 1.3, 1.4, 1.0);
uniform float intensity : hint_range(0.5, 4.0) = 1.35;
uniform float pulse_speed : hint_range(0.0, 30.0) = 10.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	// Narrow sharp blade edge along centerline
	float center_dist = abs(UV.x - 0.5) * 2.0;
	float blade_edge = smoothstep(0.65, 0.02, center_dist);
	float blade_core = pow(smoothstep(0.35, 0.0, center_dist), 2.0);
	
	// Longitudinal taper (pointed tip at Y=1.0, base at Y=0.0)
	float tip_taper = max(1.0 - UV.y * 0.7, 0.15);
	float tapered_dist = center_dist / tip_taper;
	float tapered_edge = smoothstep(0.85, 0.0, tapered_dist);
	
	float length_gradient = smoothstep(0.0, 0.10, UV.y) * smoothstep(1.0, 0.95, UV.y);
	
	// Streamlined flowing light along blade
	float flow = sin(TIME * pulse_speed - UV.y * 22.0) * 0.12 + 0.88;
	
	vec3 col = mix(aura_color.rgb, core_color.rgb, clamp(blade_core * 1.4, 0.0, 1.0));
	float alpha = (tapered_edge * 0.55 + blade_core * 0.65) * length_gradient * flow * fade * aura_color.a;
	
	ALBEDO = col * intensity;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
