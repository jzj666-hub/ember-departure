shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Specialized Shader for Curved Wind Blade (弧形风刃 - 华丽多层次炽红/金芒/绯红渐变剑光)
// Multi-tone layered palette: Deep Crimson Aura -> Vibrant Solar Vermilion -> White-Hot Gold Cutting Spine.

uniform sampler2D blade_tex : source_color, hint_default_black, filter_linear;
uniform vec4 outer_color : source_color = vec4(0.92, 0.08, 0.15, 1.0); // Rich Crimson Scarlet
uniform vec4 mid_color : source_color = vec4(1.0, 0.38, 0.08, 1.0);   // Hot Solar Vermilion
uniform vec4 core_color : source_color = vec4(1.0, 0.96, 0.86, 1.0);  // White-Hot Gold Sharp Core
uniform float intensity : hint_range(0.5, 6.0) = 3.2;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform float contrast_boost : hint_range(1.0, 4.0) = 1.9;

void fragment() {
	vec2 uv = UV;
	vec4 tex = texture(blade_tex, uv);

	// Strictly extract luminance from RGB channels (black background keying)
	float raw_luma = max(tex.r, max(tex.g, tex.b));
	if (raw_luma < 0.015) {
		discard;
	}

	// Boost contrast to make the crescent blade razor sharp and purge low ambient bleed
	float shape_mask = clamp(pow(raw_luma, contrast_boost) * 1.35, 0.0, 1.0);

	// Edge dissolve during flight fade
	float dissolve_mask = smoothstep(dissolve, dissolve + 0.18, shape_mask);
	if (dissolve_mask < 0.01) {
		discard;
	}

	// Multi-layer rich color gradient across the blade profile:
	// Outer aura (crimson) -> Mid blade body (vermilion orange) -> Center spine (white-hot gold)
	float t_mid = smoothstep(0.15, 0.65, shape_mask);
	float t_core = pow(shape_mask, 2.6);

	vec3 blade_body = mix(outer_color.rgb, mid_color.rgb, t_mid);
	vec3 col = mix(blade_body, core_color.rgb, t_core * 0.92);
	col *= intensity;

	// View-angle glint shimmer
	float fresnel = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 1.6);
	col += core_color.rgb * fresnel * 0.30;

	float final_alpha = shape_mask * dissolve_mask * fade * outer_color.a;

	ALBEDO = col;
	ALPHA = clamp(final_alpha, 0.0, 1.0);
}
