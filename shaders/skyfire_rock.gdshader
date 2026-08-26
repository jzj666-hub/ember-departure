shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// 拟真碎石着色器（技能十五·天火坠落）：
// 3D 局部空间程序化岩石花纹（深色玄武岩/花岗岩矿物斑纹 + 裂纹），
// 裂隙中透出高温炽热熔岩/余烬，随时间动态冷却熄灭，最终呈现自然粗糙碎石。

uniform vec4 ember_color : source_color = vec4(1.30, 0.50, 0.08, 1.0);  // 裂隙熔岩色
uniform vec4 core_color : source_color = vec4(1.80, 1.50, 0.90, 1.0);   // 裂隙白炽高光
uniform vec4 stone_dark : source_color = vec4(0.12, 0.11, 0.12, 1.0);   // 深色岩石基底
uniform vec4 stone_light : source_color = vec4(0.32, 0.29, 0.27, 1.0);  // 浅色岩石斑纹/矿物
uniform vec4 stone_accent : source_color = vec4(0.18, 0.16, 0.14, 1.0); // 中间风化层

uniform float cooling_progress : hint_range(0.0, 1.0) = 1.0; // 1.0 = 刚爆开炽热, 0.0 = 完全冷却为死石
uniform float rock_scale : hint_range(0.5, 20.0) = 6.0;
uniform float crack_scale : hint_range(0.5, 20.0) = 5.0;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.88;

varying vec3 v_local_pos;
varying vec3 v_world_normal;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float vnoise3(vec3 p) {
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

float fbm_rock(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * vnoise3(p);
		p = p * 2.15 + vec3(4.1, 8.7, 2.3);
		a *= 0.5;
	}
	return v;
}

// 3D Voronoi 胞元距离与裂隙检测
vec2 voronoi3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 o = hash33(i + g);
				vec3 r = g + o - f;
				float d = dot(r, r);
				if (d < d1) {
					d2 = d1;
					d1 = d;
				} else if (d < d2) {
					d2 = d;
				}
			}
		}
	}
	return vec2(sqrt(d1), sqrt(d2));
}

void vertex() {
	v_local_pos = VERTEX;
	v_world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	// 1. 岩石矿物斑纹与层理（3D 程序化玄武岩/花岗岩纹理）
	vec3 p_rock = v_local_pos * rock_scale;
	float n_base = fbm_rock(p_rock);
	float n_grain = fbm_rock(p_rock * 3.5);
	float n_layer = sin(v_local_pos.y * 14.0 + n_base * 4.0) * 0.5 + 0.5;

	// 真实岩石多层色阶混合：基底 ➔ 矿斑 ➔ 层理
	vec3 albedo_stone = mix(stone_dark.rgb, stone_accent.rgb, smoothstep(0.3, 0.6, n_base));
	albedo_stone = mix(albedo_stone, stone_light.rgb, smoothstep(0.55, 0.85, n_grain * 0.7 + n_layer * 0.3));

	// 2. 炽热裂纹与熔岩余烬（Voronoi 胞元边界）
	vec3 p_crack = v_local_pos * crack_scale;
	vec2 v_dist = voronoi3(p_crack);
	float crack_edge = v_dist.y - v_dist.x; // 边界处接近 0
	
	// 裂纹深度与粗细
	float crack_mask = 1.0 - smoothstep(0.04, 0.16, crack_edge);
	crack_mask *= smoothstep(0.2, 0.7, n_base); // 裂纹在岩体表面不均匀分布

	// 3. 冷却衰减与发光计算
	float heat = crack_mask * cooling_progress;
	vec3 lava_col = mix(ember_color.rgb, core_color.rgb, smoothstep(0.4, 0.9, heat));
	float emit_strength = heat * mix(0.0, 3.8, cooling_progress);

	// 表面微粗糙度
	ALBEDO = mix(albedo_stone, stone_dark.rgb * 0.6, crack_mask * 0.8);
	ROUGHNESS = mix(roughness_val, 0.4, heat * 0.5);
	METALLIC = 0.04;
	SPECULAR = 0.35;
	EMISSION = lava_col * emit_strength;
}
