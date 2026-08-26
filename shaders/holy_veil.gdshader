shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;

// Multi-Hue Opal / Aurora Holy Protective Veil (Pearl White + Rose Gold + Ethereal Mint/Cyan Rim)
uniform vec4 veil_core : source_color = vec4(0.92, 0.95, 1.0, 0.08);     // Translucent pearl core
uniform vec4 rim_rosegold : source_color = vec4(1.0, 0.82, 0.65, 0.55);   // Warm sacred rose gold
uniform vec4 rim_aurora : source_color = vec4(0.35, 0.92, 0.85, 0.65);    // Iridescent aurora mint/cyan
uniform float rim_power : hint_range(0.5, 6.0) = 2.8;
uniform float pulse_speed : hint_range(0.0, 10.0) = 1.8;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	// Multi-Angle Fresnel Refraction
	float fresnel = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), rim_power);
	
	// Gentle breathing ripple & rainbow dispersion
	float ripple = sin(UV.y * 14.0 - TIME * pulse_speed) * 0.12 + 0.88;
	float rainbow_shift = sin(UV.x * 6.28 + UV.y * 3.14 + TIME * (pulse_speed * 0.5)) * 0.5 + 0.5;
	
	vec3 rim_color = mix(rim_rosegold.rgb, rim_aurora.rgb, rainbow_shift);
	vec3 col = mix(veil_core.rgb, rim_color, clamp(fresnel * 1.2, 0.0, 1.0));
	
	float alpha = (veil_core.a * 0.2 + fresnel * 0.75) * ripple * fade;
	
	ALBEDO = col * 1.2;
	ALPHA = clamp(alpha, 0.0, 0.75);
}
