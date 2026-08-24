shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;

// Elegant Holy Cleanse Aura & Translucent Protective Veil
uniform vec4 veil_color : source_color = vec4(0.85, 0.92, 1.0, 0.12);
uniform vec4 rim_color : source_color = vec4(1.0, 0.96, 0.8, 0.45);
uniform float rim_power : hint_range(0.5, 6.0) = 3.5;
uniform float pulse_speed : hint_range(0.0, 10.0) = 1.8;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	// Crisp thin fresnel rim so the center remains totally clear for vision
	float fresnel = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), rim_power);
	
	// Very gentle breathing ripple
	float ripple = sin(UV.y * 12.0 - TIME * pulse_speed) * 0.1 + 0.9;
	
	vec3 col = mix(veil_color.rgb, rim_color.rgb, fresnel * 0.8);
	float alpha = (veil_color.a * 0.15 + fresnel * rim_color.a) * ripple * fade;
	
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 0.65);
}
