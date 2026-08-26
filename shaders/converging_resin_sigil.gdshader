shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Sinister Dark Toxic & Necrotic Venom Inward Sigil
// Dominant Toxic Black-Green Base with Acid Lime & Dark Necrotic Violet Undertones.

uniform vec4 color_dark_shadow : source_color = vec4(0.01, 0.12, 0.04, 0.95);  // Abyssal Dark Black-Green
uniform vec4 color_toxic_green : source_color = vec4(0.05, 0.95, 0.28, 0.95);  // Venomous Toxic Green
uniform vec4 color_acid_lime : source_color = vec4(0.65, 1.0, 0.05, 1.0);       // Corrosive Acid Lime
uniform vec4 color_necro_violet : source_color = vec4(0.45, 0.02, 0.65, 0.85);  // Sinister Necrotic Violet

uniform float spin_speed : hint_range(0.0, 10.0) = 1.4;
uniform float inward_flow_speed : hint_range(0.0, 15.0) = 3.6;
uniform float pulse_speed : hint_range(0.0, 10.0) = 2.8;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

uniform sampler2D sigil_tex : source_color, hint_default_black, filter_linear_mipmap;
uniform float tex_mix : hint_range(0.0, 1.0) = 0.8;

void fragment() {
	vec2 center = UV - vec2(0.5);
	float r = length(center) * 2.0;
	if (r > 1.0) {
		discard;
	}
	float angle = atan(center.y, center.x);
	
	// 1. Inward Converging Acidic Poison Veins (向中心高速汇聚的毒液脉络)
	float inward_stream = sin(angle * 6.0 - log(max(r, 0.001)) * 11.0 - TIME * inward_flow_speed);
	inward_stream = pow(inward_stream * 0.5 + 0.5, 3.2);
	
	// Concentric collapsing suction ripples
	float suction_rings = sin(r * 26.0 + TIME * (inward_flow_speed * 1.5)) * 0.5 + 0.5;
	suction_rings = pow(suction_rings, 2.2);
	
	// 2. Rotating Rune Sigil
	float sa = sin(TIME * spin_speed * 0.35);
	float ca = cos(TIME * spin_speed * 0.35);
	vec2 ruv = vec2(center.x * ca - center.y * sa, center.x * sa + center.y * ca) + vec2(0.5);
	float sheet = texture(sigil_tex, ruv).r;
	
	float outer_ring = smoothstep(0.05, 0.0, abs(r - 0.88));
	float inner_core = smoothstep(0.42, 0.0, r);
	
	float combined = mix(inward_stream * 0.75 + suction_rings * 0.45 + outer_ring * 0.8 + inner_core * 0.95, sheet, tex_mix);
	
	// 3. Dark Toxic & Necrotic Color Modulation
	float wave = sin(TIME * pulse_speed + angle * 3.0 - r * 4.0) * 0.5 + 0.5;
	
	// Dark black-green base with venomous green streams
	vec3 base_col = mix(color_dark_shadow.rgb, color_toxic_green.rgb, clamp(combined * 1.2, 0.0, 1.0));
	
	// Acid lime highlight on stream peaks & center
	base_col = mix(base_col, color_acid_lime.rgb, clamp(inward_stream * 0.7 + inner_core * 0.9, 0.0, 1.0));
	
	// Dark necrotic violet edge fringes (增强剧毒与邪恶感)
	base_col = mix(base_col, color_necro_violet.rgb, wave * (1.0 - inner_core) * 0.45);
	
	float edge_fade = smoothstep(1.0, 0.82, r);
	float alpha = combined * edge_fade * fade * color_toxic_green.a;
	
	ALBEDO = base_col * 2.0;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
