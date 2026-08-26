shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled;

// Large Magic Glass Mirror (Ultra Transparent, Screen Refraction, Diamond Bevel Border, Fine Cracks)
uniform vec4 glass_color : source_color = vec4(0.92, 0.97, 1.0, 0.12); // 极透淡清琉璃色
uniform vec4 edge_color : source_color = vec4(0.95, 0.98, 1.0, 0.95);  // 倒角与外框高光
uniform vec4 crack_color : source_color = vec4(1.8, 2.2, 2.6, 1.0);    // 碎裂细线反光

uniform float refraction_strength : hint_range(0.0, 0.1) = 0.03; // 折射率
uniform float dispersion : hint_range(0.0, 0.05) = 0.010;        // 色散
uniform float crack_progress : hint_range(0.0, 1.0) = 0.0;       // 裂纹进度
uniform float fade : hint_range(0.0, 1.0) = 1.0;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float voronoi_cracks(vec2 p) {
	vec2 i_pos = floor(p);
	vec2 f_pos = fract(p);
	float min_dist = 1.0;
	float second_min = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 point = vec2(hash12(i_pos + neighbor), hash12(i_pos + neighbor + 13.7));
			float dist = length(neighbor + point - f_pos);
			if (dist < min_dist) {
				second_min = min_dist;
				min_dist = dist;
			} else if (dist < second_min) {
				second_min = dist;
			}
		}
	}
	return smoothstep(0.04, 0.0, second_min - min_dist);
}

void fragment() {
	vec2 uv = UV;
	vec3 normal = normalize(NORMAL);
	vec3 view = normalize(VIEW);

	// 1. 菲涅尔边缘反光
	float facing = clamp(abs(dot(normal, view)), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 3.2);

	// 2. 精致菱形倒角镜框边缘
	vec2 border_d = abs(uv - vec2(0.5)) * 2.0;
	float border = smoothstep(0.94, 0.99, max(border_d.x, border_d.y));

	// 3. 极细沃罗诺伊冰晶裂纹
	float cracks = voronoi_cracks(uv * 12.0) * step(0.01, crack_progress);
	cracks *= smoothstep(0.0, crack_progress, hash12(floor(uv * 12.0)));

	// 4. 屏幕空间折射采样
	vec2 refr_offset = normal.xy * refraction_strength * (1.0 + cracks * 1.5);
	float refr_r = texture(screen_texture, SCREEN_UV + refr_offset * (1.0 + dispersion)).r;
	float refr_g = texture(screen_texture, SCREEN_UV + refr_offset).g;
	float refr_b = texture(screen_texture, SCREEN_UV + refr_offset * (1.0 - dispersion)).b;
	vec3 refr_color = vec3(refr_r, refr_g, refr_b);

	// 5. 镜面高光 (来自上方光源的镜面反光)
	vec3 light_dir = normalize(vec3(0.3, 0.9, 0.4));
	vec3 half_v = normalize(light_dir + view);
	float spec = pow(max(0.0, dot(normal, half_v)), 48.0);

	// 6. 颜色合成
	vec3 base_color = mix(refr_color, edge_color.rgb, fresnel * 0.5 + border * 0.85);
	base_color += edge_color.rgb * spec * 1.5;
	vec3 final_rgb = mix(base_color, crack_color.rgb, cracks * 0.9);

	ALBEDO = final_rgb;
	ROUGHNESS = 0.03;
	SPECULAR = 0.98;
	EMISSION = (edge_color.rgb * border * 0.5 + crack_color.rgb * cracks * 1.2) * fade;
	ALPHA = clamp((glass_color.a + fresnel * 0.4 + border * 0.8 + cracks * 0.6 + spec * 0.5) * fade, 0.0, 1.0);
}
