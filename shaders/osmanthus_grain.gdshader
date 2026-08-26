shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Four-Petal Golden Osmanthus Grain / Petal Particle Shader (手部金色桂花粒)
uniform vec4 color_osmanthus_gold : source_color = vec4(1.0, 0.82, 0.15, 0.95);
uniform vec4 color_osmanthus_bright : source_color = vec4(1.0, 0.95, 0.60, 0.98);

void fragment() {
	vec2 p = UV - vec2(0.5);
	float r = length(p) * 2.0;
	if (r > 1.0) {
		discard;
	}
	float angle = atan(p.y, p.x);
	
	// 4-petal cross geometry profile of authentic osmanthus blossoms
	float petal_contour = 0.55 + 0.35 * pow(abs(cos(angle * 2.0)), 1.5);
	if (r > petal_contour) {
		discard;
	}
	
	float edge_fade = smoothstep(petal_contour, petal_contour * 0.5, r);
	float core = smoothstep(0.4, 0.0, r);
	
	vec3 col = mix(color_osmanthus_gold.rgb, color_osmanthus_bright.rgb, core);
	
	ALBEDO = col * 1.4;
	ALPHA = clamp(edge_fade * COLOR.a, 0.0, 0.98);
}
