shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Delicate Eight-Petal Blooming Crimson Lotus Ground Sigil (Comfortable Brightness)
uniform vec4 color_root_blue : source_color = vec4(0.08, 0.65, 1.2, 0.90);
uniform vec4 color_gold : source_color = vec4(0.95, 0.72, 0.15, 0.90);
uniform vec4 color_crimson : source_color = vec4(0.92, 0.14, 0.25, 0.90);

uniform float spin_speed : hint_range(0.0, 10.0) = 1.0;
uniform float pulse_speed : hint_range(0.0, 10.0) = 2.2;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 center = UV - vec2(0.5);
	float r = length(center) * 2.0;
	if (r > 1.0) {
		discard;
	}
	float angle = atan(center.y, center.x);
	
	// 1. Eight-Petal Lotus Contour
	float petal_contour = 0.68 + 0.25 * cos(angle * 8.0 + TIME * spin_speed * 0.4);
	float petal_mask = smoothstep(petal_contour + 0.05, petal_contour - 0.05, r);
	
	// Inner interwoven petals
	float inner_contour = 0.42 + 0.15 * cos(angle * 8.0 + PI * 0.25 - TIME * spin_speed * 0.6);
	float inner_mask = smoothstep(inner_contour + 0.04, inner_contour - 0.04, r);
	
	// Fire ripples
	float swirl = sin(angle * 10.0 - r * 12.0 + TIME * pulse_speed) * 0.5 + 0.5;
	swirl = pow(swirl, 2.2);
	
	float core = smoothstep(0.35, 0.0, r);
	float combined = clamp(petal_mask * 0.7 + inner_mask * 0.5 + swirl * 0.5 + core * 0.8, 0.0, 1.0);
	
	vec3 col = mix(color_crimson.rgb, color_gold.rgb, clamp(inner_mask * 0.7 + swirl * 0.4, 0.0, 1.0));
	col = mix(col, color_root_blue.rgb, core * 0.75);
	
	float edge_fade = smoothstep(1.0, 0.85, r);
	float alpha = combined * edge_fade * fade * color_crimson.a;
	
	ALBEDO = col * 0.90;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
