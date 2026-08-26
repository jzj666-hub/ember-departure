shader_type spatial;
render_mode blend_add, cull_disabled, unshaded;

// Authentic Faceted Ice Crystal / Quartz Mineral Shader
// Sharp faceted diamond reflections, internal frost luminescence, and depth blending.

uniform vec4 crystal_color : source_color = vec4(0.35, 0.88, 1.35, 0.90); // 冰晶青蓝
uniform vec4 core_color : source_color = vec4(2.4, 2.7, 3.2, 1.0);       // 炽白内芯高光
uniform vec4 facet_color : source_color = vec4(0.85, 0.96, 1.0, 1.0);     // 棱角高光反射

uniform float emission_energy : hint_range(0.0, 30.0) = 6.0;
uniform float facet_sharpness : hint_range(1.0, 20.0) = 8.0;
uniform float internal_glow : hint_range(0.0, 2.0) = 0.8;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float depth_fade_distance : hint_range(0.0, 5.0) = 0.5;

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

void fragment() {
	// 1. 棱面法线高光反射 (Sharp Crystalline Facet Specular Glint)
	// 使用 flat dFdx/dFdy 生成六棱柱每个刻面的独立镜面反射
	vec3 d_x = dFdx(VERTEX);
	vec3 d_y = dFdy(VERTEX);
	vec3 facet_normal = normalize(cross(d_x, d_y));
	
	vec3 view_dir = normalize(VIEW);
	// 模拟来自上方和斜向圣光源的高光反射
	vec3 light_dir1 = normalize(vec3(0.3, 1.0, 0.4));
	vec3 light_dir2 = normalize(vec3(-0.5, 0.8, -0.3));
	
	vec3 h1 = normalize(light_dir1 + view_dir);
	vec3 h2 = normalize(light_dir2 + view_dir);
	
	float spec1 = pow(max(0.0, dot(facet_normal, h1)), facet_sharpness);
	float spec2 = pow(max(0.0, dot(facet_normal, h2)), facet_sharpness * 1.5) * 0.7;
	float facet_glint = spec1 + spec2;

	// 2. 边缘折射与晶体棱角线强化 (Fresnel Rim)
	float facing = clamp(abs(dot(facet_normal, view_dir)), 0.0, 1.0);
	float edge_rim = pow(1.0 - facing, 2.5);

	// 3. 内部冰纹与絮状结晶噪波 (Internal Frost Inclusions)
	float frost_noise = vnoise2(UV * 8.0 + vec2(0.0, -TIME * 0.2));
	float internal_structure = frost_noise * 0.35 + (1.0 - UV.y) * 0.45; // 根部更厚实，尖端更剔透

	// 4. 深度虚化（根部与地面自然融合）
	float depth_fade = 1.0;
	if (depth_fade_distance > 0.001) {
		float depth = texture(depth_texture, SCREEN_UV).r;
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
		vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		view.xyz /= view.w;
		float linear_depth = -view.z;
		depth_fade = clamp((linear_depth + VERTEX.z) / depth_fade_distance, 0.0, 1.0);
	}

	// 5. 颜色合成：晶体基础冰蓝 + 内部结晶光 + 棱面耀眼反射光
	vec3 base_col = crystal_color.rgb * (internal_glow + internal_structure);
	vec3 glint_col = mix(facet_color.rgb, core_color.rgb, spec1);
	vec3 final_rgb = base_col + glint_col * (facet_glint * 1.8 + edge_rim * 0.8);

	float alpha = clamp((0.45 + internal_structure * 0.3 + facet_glint * 0.6 + edge_rim * 0.4) * depth_fade * fade, 0.0, 1.0);

	ALBEDO = final_rgb;
	EMISSION = final_rgb * emission_energy * (0.4 + 0.6 * facet_glint);
	ALPHA = alpha;
}
