shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Translucent Rounded Glass Energy Barrier Shell enclosing the inner flame
uniform vec4 glass_tint : source_color = vec4(0.08, 0.18, 0.28, 0.18);
uniform vec4 rim_amber : source_color = vec4(1.0, 0.72, 0.25, 0.9);
uniform vec4 rim_cyan : source_color = vec4(0.2, 0.85, 1.4, 0.85);
uniform float corner_radius : hint_range(0.05, 0.5) = 0.28;
uniform float rim_power : hint_range(0.5, 6.0) = 2.4;
uniform float pulse_speed : hint_range(0.0, 10.0) = 2.5;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

// Signed distance function to a rounded rectangle in UV space [0, 1]
float rounded_box_sdf(vec2 p, vec2 b, float r) {
	vec2 d = abs(p) - b + vec2(r);
	return min(max(d.x, d.y), 0.0) + length(max(d, vec2(0.0))) - r;
}

void fragment() {
	// 1. Procedural smooth rounded capsule boundary
	vec2 uv_centered = UV - vec2(0.5, 0.5);
	vec2 half_size = vec2(0.48, 0.48);
	float d = rounded_box_sdf(uv_centered, half_size, corner_radius);
	
	// Sharp yet antialiased outer contour
	float contour_mask = 1.0 - smoothstep(-0.012, 0.004, d);
	if (contour_mask <= 0.001) {
		discard;
	}
	
	// Crisp glowing border stroke
	float border_stroke = smoothstep(-0.05, -0.01, d) * (1.0 - smoothstep(-0.01, 0.002, d));
	
	// 2. Glass curvature & Dual-Tone Fresnel Reflections (Amber Gold & Electric Cyan)
	float fresnel = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), rim_power);
	
	// Height gradient: bottom connects to blue magma, top catches golden ambient rim
	float height_ratio = 1.0 - UV.y;
	vec3 rim_col = mix(rim_cyan.rgb, rim_amber.rgb, clamp(height_ratio * 1.2 - 0.1, 0.0, 1.0));
	
	// 3. Diagonal glass gloss shine / energy caustics flow
	float gloss_sweep = sin((UV.x * 2.5 + UV.y * 1.5) * 6.28318 - TIME * pulse_speed) * 0.5 + 0.5;
	gloss_sweep = pow(gloss_sweep, 8.0);
	
	// Subtle honeycomb/crystal refraction lattice
	float lattice = sin(UV.x * 38.0) * sin(UV.y * 38.0);
	lattice = pow(clamp(lattice, 0.0, 1.0), 4.0) * 0.15;
	
	// 4. Color blending
	vec3 glass_base = glass_tint.rgb;
	vec3 col = mix(glass_base, rim_col, clamp(fresnel * 0.85 + border_stroke * 1.5 + gloss_sweep * 0.6 + lattice, 0.0, 1.0));
	
	// Alpha transparency: clear in the middle to reveal roaring inner fire, glowing edges
	float edge_alpha = fresnel * 0.65 + border_stroke * 0.85 + gloss_sweep * 0.35 + lattice * 0.2;
	float total_alpha = (glass_tint.a + edge_alpha) * contour_mask * fade;
	
	ALBEDO = col * 1.4;
	ALPHA = clamp(total_alpha, 0.0, 0.95);
}
