shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// 3D 锥形/柱形尾焰与火焰气柱着色器（技能十五·天火坠落）：
// 作用于 3D 圆台/圆锥网格（CylinderMesh/Cone），360 度视角全方位无死角，
// 彻底解决 2D 双片交叉（Cross-card）在摄像机旋转时穿帮露底、缺乏体积感的问题。

uniform vec4 core_color : source_color = vec4(1.60, 1.42, 1.05, 1.0);
uniform vec4 mid_color : source_color = vec4(1.30, 0.72, 0.16, 0.95);
uniform vec4 edge_color : source_color = vec4(0.95, 0.26, 0.04, 0.90);
uniform vec4 soot_color : source_color = vec4(0.22, 0.03, 0.01, 0.85);

uniform float intensity : hint_range(0.0, 5.0) = 1.8;
uniform float swirl_count : hint_range(1.0, 12.0) = 3.0; // 周向旋转螺旋数
uniform float stretch : hint_range(0.5, 10.0) = 3.0;     // 纵向拉伸度
uniform float speed : hint_range(0.0, 12.0) = 4.2;      // 火焰喷射与翻滚速度
uniform float tip_erosion : hint_range(0.5, 4.0) = 1.6; // 尾尖消散侵蚀率
uniform float fade : hint_range(0.0, 1.0) = 1.0;

varying vec3 v_local_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm2(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * vnoise2(p);
		p = p * 2.13 + vec2(7.3, 11.9);
		a *= 0.5;
	}
	return v;
}

// 保证 UV.x 在 0~1 环绕闭合无接缝的噪声采样
float seamless_noise(vec2 uv, float time_offset) {
	float angle = uv.x * 6.28318530718;
	vec3 cyl_p = vec3(cos(angle) * swirl_count, sin(angle) * swirl_count, uv.y * stretch - time_offset);
	// 双重重叠采样消除接缝
	vec2 p1 = vec2(uv.x * swirl_count, uv.y * stretch - time_offset);
	vec2 p2 = vec2((uv.x + 0.5) * swirl_count, uv.y * stretch - time_offset);
	float w = cos(uv.x * 6.28318530718) * 0.5 + 0.5;
	return mix(fbm2(p1), fbm2(p2), w * 0.5 + 0.25);
}

void vertex() {
	v_local_pos = VERTEX;
	// 顶点微幅热浪膨胀扰动
	float w = sin(VERTEX.y * 6.0 - TIME * speed * 2.0) * cos(VERTEX.x * 8.0 + TIME * speed);
	VERTEX.xz += NORMAL.xz * (w * 0.08 * (1.0 - UV.y));
}

void fragment() {
	// CylinderMesh 默认 UV:
	// UV.y: 0.0 (顶部/尾端), 1.0 (底部/陨石连接端)
	// rise: 0.0 (陨石根部), 1.0 (尾端焰尖)
	float rise = 1.0 - clamp(UV.y, 0.0, 1.0);

	// 3D 环向无缝螺旋噪声流
	float t = TIME * speed;
	vec2 uv_flow = vec2(UV.x, UV.y);
	float n1 = seamless_noise(uv_flow, t);
	float n2 = seamless_noise(uv_flow * 1.8 + vec2(0.3, 0.7), t * 1.5);
	float n = n1 * 0.65 + n2 * 0.35;

	// 火焰形状沿高度消散侵蚀（根部粗密炽热，焰尖收窄断裂）
	float shape = (1.0 - rise * 0.85);
	float flame = shape * (n * 1.35 + 0.1);
	flame = pow(clamp(flame, 0.0, 1.0), mix(0.9, 2.5, rise * tip_erosion));

	// 菲涅尔/视线边缘柔和羽化（避免圆锥边缘生硬）
	float fres = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 1.5);
	flame *= (0.45 + 0.55 * fres);

	// 飞掠火星
	float spark = pow(fbm2(vec2(UV.x * 16.0, rise * 8.0 - t * 2.5)), 5.0) * 2.2 * (1.0 - rise * 0.5);

	float heat = clamp(flame + spark * 0.3, 0.0, 1.0);

	// 色彩阶梯
	vec3 col = mix(soot_color.rgb, edge_color.rgb, smoothstep(0.05, 0.35, heat));
	col = mix(col, mid_color.rgb, smoothstep(0.35, 0.70, heat));
	col = mix(col, core_color.rgb, smoothstep(0.72, 0.98, heat));
	col *= intensity;
	col += core_color.rgb * spark * intensity * 1.5;

	ALBEDO = col;
	ALPHA = clamp(flame * 1.25 + spark * 0.5, 0.0, 1.0) * fade;
}
