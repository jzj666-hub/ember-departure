shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Realistic Massive Churning Ground Dust & Shockwave Smoke
uniform vec4 smoke_color : source_color = vec4(0.68, 0.74, 0.82, 0.55); // 灰蓝冷调浓烟
uniform vec4 rim_color : source_color = vec4(0.45, 0.90, 1.35, 0.85);   // 强能量映光

uniform float churn_speed : hint_range(0.0, 5.0) = 1.2; // 烟雾内部翻滚对流速度
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

float fbm_swirl(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	for (int k = 0; k < 4; k++) {
		v += a * vnoise2(p);
		// 旋转涡流分量
		p = vec2(p.x * 0.8 - p.y * 0.6, p.x * 0.6 + p.y * 0.8) * 2.15 + vec2(3.7, 5.1);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = (UV - vec2(0.5)) * 2.0;
	float r = length(uv);
	
	// 动态翻滚涡流对流
	vec2 flow1 = UV * 3.5 + vec2(TIME * churn_speed * 0.35, -TIME * churn_speed * 0.55);
	vec2 flow2 = UV * 5.0 - vec2(TIME * churn_speed * 0.45, TIME * churn_speed * 0.25);
	float noise1 = fbm_swirl(flow1);
	float noise2 = fbm_swirl(flow2);
	float combined_noise = noise1 * 0.65 + noise2 * 0.35;

	// 烟雾球形边缘柔化与动态侵蚀
	float mask = smoothstep(1.0, 0.15, r + (combined_noise - 0.5) * 0.7);

	// 菲涅尔边缘光照（被中心圣光照亮的边缘轮廓）
	float facing = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float rim = pow(1.0 - facing, 2.2);

	// 深度虚化
	float depth_fade = 1.0;
	if (depth_fade_distance > 0.001) {
		float depth = texture(depth_texture, SCREEN_UV).r;
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
		vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		view.xyz /= view.w;
		float linear_depth = -view.z;
		depth_fade = clamp((linear_depth + VERTEX.z) / depth_fade_distance, 0.0, 1.0);
	}

	vec3 col = mix(smoke_color.rgb, rim_color.rgb, rim * 0.8 + (1.0 - mask) * 0.2);
	float alpha = mask * smoke_color.a * depth_fade * fade;

	ALBEDO = col;
	EMISSION = rim_color.rgb * rim * 1.2 * (0.8 + 0.2 * noise1);
	ALPHA = clamp(alpha, 0.0, 1.0);
}
