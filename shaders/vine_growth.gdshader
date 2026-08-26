shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Sinister Dark Toxic & Venomous Shadow Vine Ribbon
// Toxic Black-Green Core, Acid Lime Bioluminescence, and Shadow Necrotic Violet Rim.

uniform vec4 color_shadow_black : source_color = vec4(0.01, 0.08, 0.03, 0.95); // Abyssal Black-Green Shadow
uniform vec4 color_toxic_green : source_color = vec4(0.06, 0.95, 0.25, 0.95);  // Venomous Emerald Toxic
uniform vec4 color_acid_lime : source_color = vec4(0.72, 1.0, 0.08, 1.0);       // Searing Acid Lime Pulse
uniform vec4 color_necro_purple : source_color = vec4(0.48, 0.03, 0.68, 0.85); // Sinister Dark Violet Undertone

uniform float pulse_speed : hint_range(0.0, 10.0) = 3.6;
uniform float wave_amplitude : hint_range(0.0, 0.1) = 0.022;
uniform float growth_progress : hint_range(0.0, 1.0) = 1.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	// Sinister writhing / organic pulse
	float wave_y = sin(UV.y * 16.0 - TIME * pulse_speed * 1.3);
	float wave_x = cos(UV.x * 6.28318 + TIME * pulse_speed * 0.9);
	VERTEX += NORMAL * ((wave_y + wave_x * 0.6) * wave_amplitude);
}

void fragment() {
	if (UV.y > growth_progress) {
		discard;
	}

	// 1. Dark Shadow Veins & Toxic Edge Glow
	float edge_dist = min(UV.x, 1.0 - UV.x);
	float edge_glow = pow(1.0 - clamp(edge_dist * 3.6, 0.0, 1.0), 3.0);
	
	// 2. Corrosive Acid Pulses along the ribbon
	float venom1 = sin(UV.y * 32.0 - TIME * pulse_speed * 2.2 + UV.x * 8.0) * 0.5 + 0.5;
	float venom2 = sin(UV.y * 58.0 - TIME * pulse_speed * 3.4 - UV.x * 14.0) * 0.5 + 0.5;
	float venom_flow = pow(venom1 * 0.6 + venom2 * 0.4, 2.6);
	
	// 3. Ancient Necrotic / Cursed Toxic Rune Engravings
	float rune_y = fract(UV.y * 20.0 - TIME * pulse_speed * 0.45);
	float rune_x = fract(UV.x * 3.0);
	float rune_dot = pow(clamp(sin(rune_y * 3.14159) * sin(rune_x * 3.14159), 0.0, 1.0), 4.2);
	float rune_step = step(0.42, fract(UV.y * 10.0 - TIME * pulse_speed * 0.22));
	float rune_glow = rune_dot * rune_step * (1.0 - edge_glow);
	
	// 4. Dark Black-Green / Toxic Lime / Necrotic Violet Color Palette
	vec3 col = mix(color_shadow_black.rgb, color_toxic_green.rgb, clamp(venom_flow * 0.8 + edge_glow * 0.6, 0.0, 1.0));
	col = mix(col, color_acid_lime.rgb, clamp(rune_glow * 1.6 + venom_flow * 0.5, 0.0, 1.0));
	
	// Outer edge fringe shifts to sinister dark violet
	float fresnel = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.2);
	col = mix(col, color_necro_purple.rgb, fresnel * 0.65);
	
	float tip_fade = sin(clamp(UV.y / max(growth_progress, 0.001), 0.0, 1.0) * 3.1415926);
	tip_fade = pow(tip_fade, 0.4);
	
	float alpha = (edge_glow * 0.85 + venom_flow * 0.7 + rune_glow * 0.95 + fresnel * 0.5) * tip_fade * fade * color_toxic_green.a;
	
	ALBEDO = col * 2.1;
	ALPHA = clamp(alpha, 0.0, 0.98);
}
