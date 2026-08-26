shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Authentic Deep Earth Ground Fracture with Subterranean Earth Glow & Silver-White Mineral Highlights
uniform vec4 glow_core : source_color = vec4(1.35, 1.38, 1.45, 1.0);     // Silver-white incandescent core fissure
uniform vec4 glow_amber : source_color = vec4(0.95, 0.52, 0.15, 1.0);    // Warm earth magma energy
uniform vec4 glow_crimson : source_color = vec4(0.55, 0.12, 0.05, 1.0);  // Deep subterranean basalt mantle
uniform vec4 crust_color : source_color = vec4(0.18, 0.11, 0.07, 0.95);  // Deep brown earthy soil crust
uniform float crack_progress : hint_range(0.0, 1.0) = 1.0;              // Radial tear expansion
uniform float heat_intensity : hint_range(0.0, 3.0) = 1.15;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

uniform sampler2D crack_tex : source_color, hint_default_black, filter_linear_mipmap;

void fragment() {
	vec2 center = UV - vec2(0.5);
	float dist = length(center) * 2.0;

	// Radial fissure propagation (tearing open from center to boundary)
	float propagation = smoothstep(crack_progress + 0.05, crack_progress - 0.15, dist);

	// Sample high-detail ground crack texture
	vec4 c_tex = texture(crack_tex, UV);
	float crack_val = max(c_tex.r, max(c_tex.g, c_tex.b));
	crack_val = max(crack_val, c_tex.a * c_tex.r);

	// Multi-depth fracture profile
	float is_crack = smoothstep(0.08, 0.40, crack_val);
	float is_deep_core = smoothstep(0.50, 0.92, crack_val);

	// Subterranean magma heat breathing pulsation
	float pulse = sin(TIME * 4.0 + dist * 5.0) * 0.06 + 0.94;

	// Deep Earth Color Gradient: Basalt Deep Red -> Warm Earth Amber -> Silver-White Core
	vec3 magma_col = mix(glow_crimson.rgb, glow_amber.rgb, clamp(is_crack * 1.2, 0.0, 1.0));
	magma_col = mix(magma_col, glow_core.rgb, is_deep_core * 0.80);
	magma_col *= pulse * heat_intensity;

	// Deep brown earthen crust outer border
	vec3 final_color = mix(crust_color.rgb, magma_col, is_crack);

	// Edge fade at outer perimeter
	float edge_fade = smoothstep(1.0, 0.85, dist);

	float alpha = clamp(is_crack * propagation * edge_fade * fade, 0.0, 1.0);

	ALBEDO = final_color;
	ALPHA = alpha;
}
