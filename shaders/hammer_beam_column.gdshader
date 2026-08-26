shader_type spatial;
render_mode blend_add, unshaded, cull_disabled;

// Vertical Holy Starburst Pillar & Radiant Crystal Needle Rays
uniform vec4 core_color : source_color = vec4(2.2, 2.5, 3.0, 1.0);  // 炽白核心
uniform vec4 beam_color : source_color = vec4(0.25, 0.85, 1.25, 1.0); // 冰晶青蓝
uniform vec4 edge_color : source_color = vec4(0.08, 0.45, 0.95, 0.8); // 边缘深蓝

uniform float emission_energy : hint_range(0.0, 30.0) = 7.0;
uniform float scroll_speed : hint_range(0.0, 20.0) = 3.0;
uniform float mandala_repeat_y : hint_range(0.0, 20.0) = 4.0; // 纵向重复曼陀罗星芒节点数
uniform float mandala_mix : hint_range(0.0, 1.0) = 0.75;      // 曼陀罗图样强度
uniform float is_needle_ray : hint_range(0.0, 1.0) = 0.0;      // 1.0=放射光刺模式 (尖端渐隐锥形)

uniform float fresnel_power : hint_range(0.1, 10.0) = 2.0;
uniform float vertical_fade : hint_range(0.0, 0.5) = 0.12;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float depth_fade_distance : hint_range(0.0, 5.0) = 1.0;

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

// 几何星芒单元
float single_starburst(vec2 p) {
	float r = length(p);
	if (r < 0.0001) return 1.5;
	float a = atan(p.y, p.x);
	float spikes1 = pow(max(0.0, cos(a * 8.0)), 12.0);
	float spikes2 = pow(max(0.0, cos((a + 3.14159265 / 8.0) * 8.0)), 18.0) * 0.7;
	float flare = (spikes1 + spikes2) / (r * 8.0 + 0.06);
	float ring = smoothstep(0.03, 0.0, abs(r - 0.28));
	vec2 ap = abs(p);
	float diamond = smoothstep(0.02, 0.0, abs(ap.x + ap.y - 0.35));
	return flare * 0.7 + ring * 0.4 + diamond * 0.4 + smoothstep(0.12, 0.0, r) * 1.5;
}

void fragment() {
	vec2 uv = UV;
	
	// 1. 基础纵向能量涌流与电弧
	vec2 flow_uv = vec2(uv.x * 6.0, uv.y * 3.0 - TIME * scroll_speed);
	float n1 = vnoise2(flow_uv);
	float n2 = vnoise2(vec2(uv.x * 12.0 + 3.3, uv.y * 6.0 - TIME * scroll_speed * 1.6));
	float flow = n1 * 0.6 + n2 * 0.4;

	// 2. 纵向重复的几何星芒晶格 (Mandala Column Nodes)
	float mandala_val = 0.0;
	if (mandala_repeat_y > 0.01) {
		float ny = fract(uv.y * mandala_repeat_y - TIME * scroll_speed * 0.35) - 0.5;
		float nx = fract(uv.x * 2.0) - 0.5;
		mandala_val = single_starburst(vec2(nx, ny));
	}

	// 3. 混合光柱图案：星芒晶格 + 纵向激波
	float pattern = mix(flow, max(flow * 0.6, mandala_val), mandala_mix);

	// 4. 放射状冰晶光刺处理 (Needle Ray Mode)
	float needle_mask = 1.0;
	if (is_needle_ray > 0.5) {
		// 沿 X 轴居中聚拢，沿 Y 轴向尖端渐隐（基部粗亮，尖端尖细）
		float center_dist = abs(uv.x - 0.5) * 2.0;
		float taper = mix(1.0, 0.05, uv.y); // 越往尖端越细
		needle_mask = smoothstep(taper, 0.0, center_dist) * smoothstep(1.0, 0.15, uv.y);
		pattern = (pattern * 0.5 + 0.5) * needle_mask;
	}

	// 5. 菲涅尔边缘淡出 (柱体中间实，轮廓虚)
	float facing = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float fresnel = pow(facing, fresnel_power);

	// 6. 上下端过渡
	float v_fade = 1.0;
	if (vertical_fade > 0.001 && is_needle_ray < 0.5) {
		v_fade = smoothstep(0.0, vertical_fade, uv.y) * smoothstep(1.0, 1.0 - vertical_fade, uv.y);
	}

	// 7. 深度虚化
	float depth_fade = 1.0;
	if (depth_fade_distance > 0.001) {
		float depth = texture(depth_texture, SCREEN_UV).r;
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
		vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		view.xyz /= view.w;
		float linear_depth = -view.z;
		depth_fade = clamp((linear_depth + VERTEX.z) / depth_fade_distance, 0.0, 1.0);
	}

	// 颜色叠加：边缘深蓝 -> 主色青蓝 -> 核心炽白
	vec3 col = mix(edge_color.rgb, beam_color.rgb, smoothstep(0.15, 0.65, pattern));
	col = mix(col, core_color.rgb, smoothstep(0.70, 1.1, pattern));

	float alpha = clamp(pattern * fresnel * v_fade * depth_fade * fade * beam_color.a, 0.0, 1.0);

	ALBEDO = col;
	EMISSION = col * emission_energy * (0.5 + 0.5 * pattern);
	ALPHA = alpha;
}
