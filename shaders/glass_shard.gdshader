shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled;

// Exquisite Iridescent Prismatic Glass Shard Shader (彩色琉璃剔透·彩虹色散·晶莹透光)
uniform vec4 glass_tint : source_color = vec4(0.92, 0.97, 1.0, 0.12); // 极透琉璃基底 (纯净高透)
uniform vec4 edge_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);    // 倒角极锐纯白反光

uniform float refraction_strength : hint_range(0.0, 0.1) = 0.038; // 真实物理折射
uniform float dispersion : hint_range(0.0, 0.1) = 0.024;          // 琉璃彩虹分光色散 (RGB分离)
uniform float iridescence_intensity : hint_range(0.0, 2.0) = 0.85;// 七彩霓光琉璃感
uniform float sparkle_intensity : hint_range(0.0, 5.0) = 1.5;    // 小小明光闪烁
uniform float roughness_val : hint_range(0.0, 1.0) = 0.02;        // 镜面极光滑
uniform float specular_val : hint_range(0.0, 1.0) = 0.99;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// 模拟光谱三棱镜彩虹色彩 (Spectral Rainbow Curve)
vec3 spectral_rainbow(float t) {
	return vec3(
		clamp(abs(t * 6.0 - 3.0) - 1.0, 0.0, 1.0),
		clamp(2.0 - abs(t * 6.0 - 2.0), 0.0, 1.0),
		clamp(2.0 - abs(t * 6.0 - 4.0), 0.0, 1.0)
	);
}

void fragment() {
	// 1. 多面体真实刻面法线 (Facet Normal)
	vec3 d_x = dFdx(VERTEX);
	vec3 d_y = dFdy(VERTEX);
	vec3 facet_normal = normalize(cross(d_x, d_y));
	vec3 view_dir = normalize(VIEW);

	// 2. 真实菲涅尔掠射边缘
	float facing = clamp(abs(dot(facet_normal, view_dir)), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 3.2);

	// 3. 琉璃三棱镜彩色色散 (Spectral Iridescence on Bevels & Rim)
	float rainbow_t = fract(dot(facet_normal, vec3(0.5, 0.8, 0.3)) * 1.5 + fresnel * 0.8 + TIME * 0.15);
	vec3 rainbow_color = spectral_rainbow(rainbow_t);

	// 4. 真实双光源高锐镜面高光 (Specular Glints)
	vec3 l1 = normalize(vec3(0.5, 0.9, 0.4));
	vec3 l2 = normalize(vec3(-0.6, 0.7, -0.5));
	vec3 h1 = normalize(l1 + view_dir);
	vec3 h2 = normalize(l2 + view_dir);
	float spec1 = pow(max(0.0, dot(facet_normal, h1)), 64.0);
	float spec2 = pow(max(0.0, dot(facet_normal, h2)), 48.0) * 0.7;
	float specular_glint = spec1 + spec2;

	// 5. 小小的晶莹明光火花 (Micro Sparkle on Facets)
	float sparkle = pow(max(0.0, dot(facet_normal, normalize(vec3(sin(TIME * 3.0 + VERTEX.x * 10.0), 1.0, cos(TIME * 3.0 + VERTEX.z * 10.0))))), 80.0) * sparkle_intensity;

	// 6. 屏幕空间真实折射采样 (三通道色散分光)
	vec2 refr_offset = facet_normal.xy * refraction_strength;
	float refr_r = texture(screen_texture, SCREEN_UV + refr_offset * (1.0 + dispersion)).r;
	float refr_g = texture(screen_texture, SCREEN_UV + refr_offset).g;
	float refr_b = texture(screen_texture, SCREEN_UV + refr_offset * (1.0 - dispersion)).b;
	vec3 background_refraction = vec3(refr_r, refr_g, refr_b);

	// 7. 颜色合成：清透背景透光 + 边缘彩色琉璃霓光 + 晶亮纯白反光
	vec3 base_glass = background_refraction * mix(vec3(1.0), glass_tint.rgb, glass_tint.a);
	vec3 colored_rim = mix(edge_color.rgb, rainbow_color * 1.4, iridescence_intensity * (fresnel * 0.6 + 0.2));
	
	vec3 final_rgb = mix(base_glass, colored_rim, fresnel * 0.75);
	final_rgb += edge_color.rgb * specular_glint * 1.8;
	final_rgb += rainbow_color * sparkle * 1.5;

	// 8. 极高通透度：本体透光，边缘与高光处显出剔透琉璃光泽
	float alpha = clamp((glass_tint.a + fresnel * 0.65 + specular_glint * 0.95 + sparkle * 0.8) * fade, 0.0, 1.0);

	ALBEDO = final_rgb;
	ROUGHNESS = roughness_val;
	SPECULAR = specular_val;
	EMISSION = (rainbow_color * (sparkle * 1.2 + fresnel * iridescence_intensity * 0.4) + edge_color.rgb * specular_glint * 0.6) * fade;
	ALPHA = alpha;
}
