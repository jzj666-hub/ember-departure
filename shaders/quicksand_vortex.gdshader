shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Pure Procedural Sand Vortex / Quicksand Funnel
uniform vec4 sand_color_outer : source_color = vec4(0.55, 0.42, 0.22, 0.85);
uniform vec4 sand_color_inner : source_color = vec4(0.25, 0.18, 0.08, 0.95);
uniform vec4 crest_glow : source_color = vec4(0.85, 0.68, 0.35, 1.0);
uniform float swirl_speed = 3.5;
uniform float spiral_arms = 6.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	
	float angle = atan(p.y, p.x);
	
	// Logarithmic inward spiral pattern (pure procedural, no noise texture)
	float spiral = sin(angle * spiral_arms - log(max(r, 0.001)) * 12.0 + TIME * swirl_speed);
	spiral = pow(spiral * 0.5 + 0.5, 2.2);
	
	// Concentric suction ripple rings moving inward
	float ripple = sin(r * 28.0 + TIME * (swirl_speed * 1.5)) * 0.5 + 0.5;
	
	// Center sinkhole dark vortex + bright crest streams
	float center_abyss = smoothstep(0.0, 0.45, r);
	float edge_fade = smoothstep(1.0, 0.82, r);
	
	vec3 base_col = mix(sand_color_inner.rgb, sand_color_outer.rgb, r);
	vec3 stream_col = mix(base_col, crest_glow.rgb, spiral * 0.7 + ripple * 0.3);
	
	float alpha = (0.55 + spiral * 0.45) * edge_fade * fade * sand_color_outer.a;
	
	ALBEDO = stream_col * 1.4;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
