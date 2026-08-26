shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Multi-Tier Quicksand Vortex: Dark Amber Sand + Ancient Mystic Cyan/Turquoise Runes + Sparkling Gold Crests
uniform vec4 sand_color_outer : source_color = vec4(0.45, 0.32, 0.16, 0.85); // Warm dark amber sand outer
uniform vec4 sand_color_inner : source_color = vec4(0.18, 0.12, 0.05, 0.95); // Deep vortex center abyss
uniform vec4 mystic_cyan : source_color = vec4(0.08, 0.78, 0.85, 0.9);      // Ancient turquoise magic pulse
uniform vec4 crest_gold : source_color = vec4(1.4, 1.1, 0.45, 1.0);         // Glistening desert gold crests
uniform float swirl_speed = 3.6;
uniform float spiral_arms = 6.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	
	float angle = atan(p.y, p.x);
	
	// Logarithmic inward spiral arms
	float spiral = sin(angle * spiral_arms - log(max(r, 0.001)) * 12.0 + TIME * swirl_speed);
	spiral = pow(spiral * 0.5 + 0.5, 2.2);
	
	// Secondary counter-phase mystical rune streak
	float rune_spiral = sin(angle * (spiral_arms * 1.5) - log(max(r, 0.001)) * 16.0 - TIME * (swirl_speed * 0.7));
	rune_spiral = pow(rune_spiral * 0.5 + 0.5, 4.0);
	
	// Concentric suction ripple rings moving inward
	float ripple = sin(r * 28.0 + TIME * (swirl_speed * 1.5)) * 0.5 + 0.5;
	
	// Center sinkhole dark vortex + smooth outer edge fade
	float center_abyss = smoothstep(0.0, 0.45, r);
	float edge_fade = smoothstep(1.0, 0.82, r);
	
	// Color Layering: Dark sand base -> Ancient mystic cyan pulses -> Radiant gold crests
	vec3 base_col = mix(sand_color_inner.rgb, sand_color_outer.rgb, r);
	vec3 col = mix(base_col, mystic_cyan.rgb, rune_spiral * 0.75 * center_abyss);
	col = mix(col, crest_gold.rgb, (spiral * 0.65 + ripple * 0.35) * (1.0 - rune_spiral * 0.3));
	
	float alpha = (0.55 + spiral * 0.45 + rune_spiral * 0.4) * edge_fade * fade * sand_color_outer.a;
	
	ALBEDO = col * 1.5;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
