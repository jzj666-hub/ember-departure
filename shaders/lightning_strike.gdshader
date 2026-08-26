shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Multi-Tier Purple-Gold-White Triad Thunderbolt Pillar
uniform vec4 lightning_violet : source_color = vec4(0.58, 0.18, 0.92, 0.75); // Plasma royal violet
uniform vec4 lightning_gold : source_color = vec4(0.95, 0.78, 0.32, 0.80);   // Radiant gold
uniform vec4 lightning_core : source_color = vec4(1.25, 1.20, 1.35, 0.90);  // Soft luminous white-violet core
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float brightness : hint_range(0.1, 3.0) = 1.25;
uniform float transparency : hint_range(0.1, 1.0) = 0.55;

uniform sampler2D lightning_tex : source_color, hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float tex_mix : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 nuv = vec2(UV.x * 2.0 + sin(TIME * 40.0) * 0.08, UV.y * 3.0 - TIME * 12.0);
	float n = texture(lightning_tex, nuv).r;
	
	// Longitudinal line intensity
	float center_line = 1.0 - abs(UV.x - 0.5) * 2.0;
	float arc_glow = pow(clamp(center_line, 0.0, 1.0), 2.0) * mix(0.7, n * 1.8, tex_mix);
	
	// Triad Plasma Color Blend: Violet (edge) -> Gold (mid) -> Luminous Core (center)
	float gold_weight = pow(clamp(center_line, 0.0, 1.0), 2.2);
	float core_weight = pow(clamp(center_line, 0.0, 1.0), 4.5);
	
	vec3 col = mix(lightning_violet.rgb, lightning_gold.rgb, gold_weight);
	col = mix(col, lightning_core.rgb, core_weight * 0.75);
	
	// Moderate overall brightness and keep high transparency for character visibility
	ALBEDO = col * brightness;
	ALPHA = clamp(arc_glow * fade * transparency, 0.0, 1.0);
}
