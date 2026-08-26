shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Ground Crystalline Starburst Mandala & Fractal Crack Array
uniform vec4 core_color : source_color = vec4(2.2, 2.5, 3.0, 1.0);  // 炽白核心
uniform vec4 beam_color : source_color = vec4(0.25, 0.85, 1.25, 1.0); // 冰晶青蓝
uniform vec4 edge_color : source_color = vec4(0.08, 0.45, 0.95, 0.8); // 边缘深蓝

uniform float intensity : hint_range(0.0, 10.0) = 3.5;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float expansion : hint_range(0.0, 2.0) = 1.0; // 地面法阵向外扩散进度

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float single_star(vec2 p, float rays, float size) {
	float r = length(p);
	if (r > size * 1.5) return 0.0;
	float a = atan(p.y, p.x);
	float spikes1 = pow(max(0.0, cos(a * rays)), 16.0);
	float spikes2 = pow(max(0.0, cos((a + 3.14159265 / rays) * rays)), 24.0) * 0.6;
	float flare = (spikes1 + spikes2) / (r * 15.0 / size + 0.05);
	float ring = smoothstep(0.015, 0.0, abs(r - size * 0.45));
	return flare * 0.7 + ring * 0.35 + smoothstep(size * 0.2, 0.0, r) * 1.5;
}

void fragment() {
	vec2 uv = (UV - vec2(0.5)) * 2.0; // -1.0 to 1.0
	float dist = length(uv);
	
	// 范围裁剪
	if (dist > expansion) {
		discard;
	}

	// 1. 中心主星芒
	float main_star = single_star(uv, 16.0, 0.8);

	// 2. 外围环形排列的副星芒星座阵 (8个外围星芒 + 12个次外围星芒)
	float sub_stars = 0.0;
	// 内环 8 星
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 6.2831853 / 8.0;
		vec2 pos_i = vec2(cos(a), sin(a)) * 0.45;
		sub_stars += single_star(uv - pos_i, 8.0, 0.25);
	}
	// 外环 12 星
	for (int j = 0; j < 12; j++) {
		float a = float(j) * 6.2831853 / 12.0 + 0.26;
		vec2 pos_j = vec2(cos(a), sin(a)) * 0.78;
		sub_stars += single_star(uv - pos_j, 8.0, 0.20);
	}

	// 3. 几何辐射折线与冰晶裂痕网络 (Fractal Connecting Lines)
	float ang = atan(uv.y, uv.x);
	float ray_lines = pow(max(0.0, cos(ang * 16.0)), 64.0) * smoothstep(1.0, 0.1, dist);
	float ray_lines_diag = pow(max(0.0, cos(ang * 24.0 + 0.5)), 80.0) * smoothstep(1.0, 0.2, dist) * 0.6;
	
	// 同心几何环
	float ring1 = smoothstep(0.02, 0.0, abs(dist - 0.45));
	float ring2 = smoothstep(0.015, 0.0, abs(dist - 0.78));
	float ring3 = smoothstep(0.015, 0.0, abs(dist - 0.95));

	// 综合法阵亮度
	float total_pattern = main_star * 1.2 + sub_stars * 0.85 + (ray_lines + ray_lines_diag) * 0.45 + (ring1 + ring2 + ring3) * 0.35;

	// 外缘柔和消隐
	float edge_fade = smoothstep(expansion, expansion * 0.75, dist);

	vec3 col = mix(edge_color.rgb, beam_color.rgb, smoothstep(0.15, 0.65, total_pattern));
	col = mix(col, core_color.rgb, smoothstep(0.70, 1.2, total_pattern));

	float alpha = clamp(total_pattern * edge_fade * fade, 0.0, 1.0);

	ALBEDO = col;
	EMISSION = col * intensity * (0.6 + 0.4 * total_pattern);
	ALPHA = alpha;
}
