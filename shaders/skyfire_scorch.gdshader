shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// 天火焦痕（技能十五·天火坠落）：地面暗色烟熏灼痕 + 中心余烬随时间冷却熄灭。
// 全程序化噪声侵蚀边缘，无贴图。ember_glow 由外部 tween 驱动冷却。

uniform vec4 scorch_color : source_color = vec4(0.030, 0.020, 0.015, 0.85);
uniform vec4 ember_color : source_color = vec4(1.10, 0.28, 0.04, 1.0);

uniform float ember_glow : hint_range(0.0, 3.0) = 1.2; // 余烬亮度（tween 驱动冷却）
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
	for (int k = 0; k < 3; k++) {
		v += a * vnoise2(p);
		p = p * 2.21 + vec2(9.7, 5.3);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float n = fbm2(UV * 5.0);

	// 噪声侵蚀的不规则灼痕边缘
	float edge = smoothstep(1.0, 0.55, r + (n - 0.5) * 0.35);
	float a = clamp(edge * scorch_color.a, 0.0, 1.0) * fade;

	// 中心余烬：明暗脉动，随 ember_glow 冷却熄灭
	float ember = pow(clamp(1.0 - r / 0.45, 0.0, 1.0), 1.8);
	ember *= 0.75 + 0.25 * sin(TIME * 9.0 + n * 6.2831);

	vec3 col = scorch_color.rgb + ember_color.rgb * ember * ember_glow;

	ALBEDO = col;
	ALPHA = a;
}
