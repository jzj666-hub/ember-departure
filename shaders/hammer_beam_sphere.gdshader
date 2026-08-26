shader_type spatial;
render_mode blend_add, unshaded, cull_disabled;

// Central Sacred Geometry Starburst Mandala Sphere
uniform vec4 core_color : source_color = vec4(2.2, 2.5, 3.0, 1.0);  // 炽白核心
uniform vec4 beam_color : source_color = vec4(0.25, 0.85, 1.25, 1.0); // 冰晶青蓝
uniform vec4 edge_color : source_color = vec4(0.08, 0.45, 0.95, 0.8); // 边缘深蓝

uniform float emission_energy : hint_range(0.0, 30.0) = 8.0;
uniform float mandala_density : hint_range(1.0, 10.0) = 3.0;
uniform float rotation_speed : hint_range(-5.0, 5.0) = 0.5;
uniform float pulse_speed : hint_range(0.0, 20.0) = 8.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float depth_fade_distance : hint_range(0.0, 5.0) = 0.8;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

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

// 几何星芒/曼陀罗晶格生成函数
float starburst_pattern(vec2 p, float rays) {
	float r = length(p);
	if (r < 0.0001) return 1.5;
	float a = atan(p.y, p.x);
	
	// 12/16 芒星主光刺
	float spikes1 = pow(max(0.0, cos(a * rays)), 16.0);
	float spikes2 = pow(max(0.0, cos((a + 3.14159265 / rays) * rays)), 24.0) * 0.6;
	float flare = (spikes1 + spikes2) / (r * 7.0 + 0.06);
	
	// 同心几何圆环
	float ring1 = smoothstep(0.025, 0.0, abs(r - 0.20));
	float ring2 = smoothstep(0.020, 0.0, abs(r - 0.38));
	float ring3 = smoothstep(0.018, 0.0, abs(r - 0.55));
	
	// 菱形晶格交错线
	vec2 ap = abs(p);
	float diamond = smoothstep(0.02, 0.0, abs(ap.x + ap.y - 0.28));
	float diamond2 = smoothstep(0.02, 0.0, abs(ap.x + ap.y - 0.50));
	
	// 经纬八向网格
	float axis = smoothstep(0.015, 0.0, min(ap.x, ap.y)) * step(r, 0.65);
	
	return flare * 0.65 + (ring1 + ring2 + ring3) * 0.35 + (diamond + diamond2) * 0.30 + axis * 0.25 + smoothstep(0.15, 0.0, r) * 1.8;
}

void fragment() {
	// UV 转换为以球心为基准的经纬几何映射
	vec2 uv = UV - vec2(0.5);
	// 缓慢旋转
	float ang = TIME * rotation_speed;
	float ca = cos(ang);
	float sa = sin(ang);
	vec2 rot_uv = vec2(uv.x * ca - uv.y * sa, uv.x * sa + uv.y * ca);

	// 采样星芒几何曼陀罗
	float mandala = starburst_pattern(rot_uv * mandala_density, 12.0);

	// 表面能量闪电微噪波
	float noise = vnoise2(UV * 16.0 + vec2(TIME * 2.0, -TIME * 3.5));
	mandala += noise * 0.25;

	// 菲涅尔边缘光晕
	float facing = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float rim = pow(1.0 - facing, 1.8);
	float core = pow(facing, 1.2);

	// 能量呼吸脉动
	float pulse = 0.90 + 0.10 * sin(TIME * pulse_speed);

	// 深度虚化与地面柔和交融
	float depth_fade = 1.0;
	if (depth_fade_distance > 0.001) {
		float depth = texture(depth_texture, SCREEN_UV).r;
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
		vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		view.xyz /= view.w;
		float linear_depth = -view.z;
		depth_fade = clamp((linear_depth + VERTEX.z) / depth_fade_distance, 0.0, 1.0);
	}

	// 颜色合成：白金核心 + 冰晶青蓝涌流 + 深蓝边缘
	vec3 col = mix(edge_color.rgb, beam_color.rgb, smoothstep(0.2, 0.7, mandala));
	col = mix(col, core_color.rgb, smoothstep(0.75, 1.3, mandala) * core);

	float alpha = clamp((mandala * 0.8 + rim * 0.6 + core * 0.4) * depth_fade * fade, 0.0, 1.0);

	ALBEDO = col;
	EMISSION = col * emission_energy * pulse * (0.6 + 0.4 * mandala);
	ALPHA = alpha;
}
