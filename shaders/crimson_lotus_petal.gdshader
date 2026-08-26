shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Deep Blood-Ruby Crimson Lotus Petal Shader (Visceral Blood-Lotus Aesthetic)
// Dark Blood Crimson Shadows, Visceral Ruby Petal Body, Azure Plasma Root, Carmine Veins.

uniform vec4 color_root_blue : source_color = vec4(0.08, 0.78, 1.40, 0.95);    // Azure Plasma Root
uniform vec4 color_blood_shadow : source_color = vec4(0.18, 0.00, 0.03, 0.95); // Deep Blood-Black Shadow
uniform vec4 color_blood_ruby : source_color = vec4(0.88, 0.02, 0.12, 0.92);   // Visceral Blood Ruby Body
uniform vec4 color_carmine_vein : source_color = vec4(1.0, 0.35, 0.20, 0.90);  // Carmine Heat Vein

uniform float pulse_speed : hint_range(0.0, 10.0) = 2.8;
uniform float wave_amplitude : hint_range(0.0, 0.1) = 0.018;
uniform float growth_progress : hint_range(0.0, 1.0) = 1.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	float heat_wave = sin(UV.y * 10.0 - TIME * pulse_speed * 1.2 + UV.x * 3.14);
	VERTEX += NORMAL * (heat_wave * wave_amplitude * UV.y);
}

void fragment() {
	if (UV.y > growth_progress) {
		discard;
	}

	float center_dist = abs(UV.x - 0.5) * 2.0;
	float edge_glow = pow(clamp(center_dist, 0.0, 1.0), 2.6);
	
	// Fine radial petal vein
	float vein1 = sin(UV.x * 26.0 + (UV.y - 0.5) * 3.5) * 0.5 + 0.5;
	float center_vein = smoothstep(0.14, 0.0, center_dist);
	float vein_pattern = pow(mix(vein1, 1.0, center_vein), 2.4);
	
	float y = UV.y;
	vec3 base_col = mix(color_blood_shadow.rgb, color_blood_ruby.rgb, smoothstep(0.05, 0.65, y));
	
	// Azure Plasma Root at base
	float blue_mask = smoothstep(0.35, 0.0, y) * (1.0 - center_dist * 0.4);
	base_col = mix(base_col, color_root_blue.rgb, blue_mask * 0.85);
	
	// Carmine heat veins and luminous edge trims
	base_col = mix(base_col, color_carmine_vein.rgb, clamp(vein_pattern * 0.55 + edge_glow * 0.5, 0.0, 1.0));
	
	float fresnel = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.2);
	base_col += color_carmine_vein.rgb * (fresnel * 0.4);
	
	float tip_fade = sin(clamp(UV.y / max(growth_progress, 0.001), 0.0, 1.0) * 3.1415926);
	tip_fade = pow(tip_fade, 0.35);
	
	float alpha = (0.55 + edge_glow * 0.35 + vein_pattern * 0.35 + fresnel * 0.35) * tip_fade * fade * color_blood_ruby.a;
	
	ALBEDO = base_col * 1.05;
	ALPHA = clamp(alpha, 0.0, 0.95);
}
