shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// 天火火焰面片（技能十五·天火坠落）：流星下坠尾焰 & 落地燃烧火舌。
// 约定：QuadMesh 底边（UV.y = 1）为炽热根部（球心/地面），顶边（UV.y = 0）为焰尖。
// Godot QuadMesh 的 UV 原点在顶边，故 rise = 1.0 - UV.y；全程序化噪声，无贴图。

uniform vec4 core_color : source_color = vec4(1.60, 1.42, 1.05, 1.0);
uniform vec4 mid_color : source_color = vec4(1.30, 0.72, 0.16, 0.95);
uniform vec4 edge_color : source_color = vec4(0.95, 0.26, 0.04, 0.90);
uniform vec4 soot_color : source_color = vec4(0.22, 0.03, 0.01, 0.85);

uniform float intensity : hint_range(0.0, 4.0) = 1.6;
uniform float density : hint_range(1.0, 20.0) = 6.0;
uniform float speed : hint_range(0.0, 10.0) = 3.2;
uniform float tip_dissipate : hint_range(0.5, 4.0) = 1.5; // 焰尖消散速率
uniform float fade : hint_range(0.0, 1.0) = 1.0;

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
		p = p * 2.17 + vec2(11.3, 7.1);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	// rise: 0 = 炽热根部（底边），1 = 焰尖（顶边）
	float rise = 1.0 - clamp(UV.y, 0.0, 1.0);

	// 噪声沿 -V 滚动 = 火焰沿 +V（朝焰尖）腾起
	vec2 sc = vec2(UV.x * density, rise * density * 0.7 - TIME * speed);
	float n = fbm2(sc);

	float flame = (1.0 - rise) + (n - 0.5) * 0.75;
	flame = clamp(flame, 0.0, 1.0);
	flame = pow(flame, mix(1.0, 2.2, tip_dissipate * 0.33));

	// 侧缘柔和收边
	float side = pow(max(sin(clamp(UV.x, 0.0, 1.0) * 3.1415926), 0.0), 0.35);

	// 高频飞溅火星
	float spark = pow(fbm2(vec2(UV.x * density * 4.0, rise * 6.0 - TIME * speed * 2.6)), 6.0) * 2.4;

	float heat = clamp(flame + spark * 0.35, 0.0, 1.0);
	vec3 col = mix(soot_color.rgb, edge_color.rgb, smoothstep(0.05, 0.35, heat));
	col = mix(col, mid_color.rgb, smoothstep(0.38, 0.68, heat));
	col = mix(col, core_color.rgb, smoothstep(0.74, 0.97, heat));
	col *= intensity;
	col += core_color.rgb * spark * intensity;

	ALBEDO = col;
	ALPHA = clamp(flame * 1.1 + spark * 0.6, 0.0, 1.0) * side * fade;
}
