shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;

// 天火流星炽热核心与火球球体（技能十五·天火坠落）：
// 饱满 3D 球体视觉质感，熔岩流动裂隙 + 炽热玄岩外壳 + 菲涅尔大气等离子光晕，
// 彻底解决纯加法半透明球体泛白平庸、缺乏球形体积与重力压迫感的问题。

uniform vec4 core_color : source_color = vec4(1.60, 1.42, 1.05, 1.0);  // 白炽核心
uniform vec4 mid_color : source_color = vec4(1.30, 0.72, 0.16, 0.95); // 炽黄翻涌
uniform vec4 edge_color : source_color = vec4(0.95, 0.26, 0.04, 0.90); // 橙红焰壳
uniform vec4 soot_color : source_color = vec4(0.18, 0.04, 0.02, 0.95); // 暗黑玄岩壳

uniform float intensity : hint_range(0.0, 5.0) = 1.8;
uniform float noise_scale : hint_range(0.5, 12.0) = 3.5;
uniform float speed : hint_range(0.0, 10.0) = 3.2;
uniform float rim_heat : hint_range(0.0, 2.0) = 0.85;
uniform float crust_ratio : hint_range(0.0, 1.0) = 0.45; // 暗色岩壳覆盖率
uniform float fade : hint_range(0.0, 1.0) = 1.0;

varying vec3 v_local_pos;
varying vec3 v_normal;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * vnoise(p);
		p = p * 2.15 + vec3(5.7, 3.1, 8.2);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_local_pos = VERTEX;
	v_normal = NORMAL;
	// 表面熔岩翻涌与下坠风压轻微挤压形变
	float w = sin(VERTEX.x * 6.0 + TIME * speed * 2.2)
		* cos(VERTEX.y * 5.0 - TIME * speed * 1.8)
		* sin(VERTEX.z * 6.0 + TIME * speed * 2.0);
	VERTEX += NORMAL * (w * 0.06);
	// 坠落流线型轻微拉伸（顶部稍尖，底部受阻力压缩扁平）
	if (VERTEX.y > 0.0) {
		VERTEX.y += VERTEX.y * 0.15;
	}
}

void fragment() {
	// 球体表面噪声：沿下坠反方向（-Y）剧烈流动翻滚
	vec3 p = v_local_pos * noise_scale + vec3(0.0, -TIME * speed, 0.0);
	float n = fbm(p);
	float n_detail = fbm(p * 2.2 + vec3(1.7, 4.3, 2.9));

	// 强烈的 3D 球体菲涅尔边缘光效（展现球体曲率与轮廓深度）
	float ndotv = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, 2.2);

	// 球体中心与受迎风面（下半球）更炽热
	float head_boost = smoothstep(0.4, -0.6, v_local_pos.y) * 0.25;

	// 热度分布：熔岩裂隙（白炽） ➔ 焰壳 ➔ 玄岩硬壳
	float heat = clamp(n * 1.1 + n_detail * 0.35 + head_boost + rim_heat * fresnel * 0.5 - crust_ratio * 0.3, 0.0, 1.0);

	// 渐变分阶着色
	vec3 col = mix(soot_color.rgb, edge_color.rgb, smoothstep(0.08, 0.36, heat));
	col = mix(col, mid_color.rgb, smoothstep(0.38, 0.68, heat));
	col = mix(col, core_color.rgb, smoothstep(0.70, 0.95, heat));

	// 菲涅尔等离子边缘外发光增益
	col += edge_color.rgb * fresnel * rim_heat * 1.5;
	col *= intensity;

	ALBEDO = col;
	// 保持球体实心不穿帮，边缘柔化
	ALPHA = clamp(smoothstep(0.0, 0.15, ndotv) * 0.95 + fresnel * 0.4, 0.0, 1.0) * fade;
}
