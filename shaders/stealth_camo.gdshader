shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back;

// Multi-Point Procedural Dissolve & Optical Camouflage Shader
// Character disintegrates/reconstructs across multiple focal points with luminous holographic fringes.

uniform vec4 camo_color : source_color = vec4(0.15, 0.85, 1.0, 0.28);
uniform vec4 rim_color : source_color = vec4(0.40, 0.95, 1.0, 0.90);
uniform vec4 edge_glow_color : source_color = vec4(0.3, 1.0, 0.8, 1.5); // Glowing burning fringe

uniform float dissolve_progress : hint_range(0.0, 1.0) = 0.0; // 0.0 = Fully Solid, 1.0 = Fully Invisible
uniform float edge_thickness : hint_range(0.01, 0.25) = 0.08;
uniform float rim_power : hint_range(0.5, 6.0) = 2.5;
uniform float scan_speed : hint_range(0.0, 10.0) = 2.4;
uniform float camo_alpha : hint_range(0.0, 1.0) = 0.30;
uniform bool is_in_dissolve_mode = false;

void fragment() {
	if (is_in_dissolve_mode) {
		// Multi-Point Procedural Noise Field across body (多个不同频率与位置的残破侵蚀点)
		float n1 = sin(UV.x * 24.0 + UV.y * 16.0);
		float n2 = cos(UV.x * 32.0 - UV.y * 22.0 + 1.57);
		float n3 = sin((UV.y - 0.5) * 18.0) * cos((UV.x - 0.5) * 18.0);
		float n4 = sin(UV.y * 42.0 + sin(UV.x * 28.0));
		
		float noise = (n1 * 0.30 + n2 * 0.30 + n3 * 0.25 + n4 * 0.15) * 0.5 + 0.5;
		
		// Dissolve thresholding across multiple centers
		if (noise < dissolve_progress) {
			discard;
		}
		
		// Glowing Burning Holographic Edge Fringe (残破边缘多点发光流动)
		float edge_mask = smoothstep(dissolve_progress, dissolve_progress + edge_thickness, noise);
		edge_mask = 1.0 - edge_mask; // 1.0 at burning border, 0.0 inside solid
		
		// Fresnel rim
		float fresnel = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.2);
		
		vec3 col = mix(camo_color.rgb, edge_glow_color.rgb, edge_mask * 1.5);
		col += rim_color.rgb * (fresnel * 0.8);
		
		float alpha = clamp(edge_mask * 1.8 + (1.0 - dissolve_progress) * 0.85 + fresnel * 0.5, 0.0, 1.0);
		
		ALBEDO = col;
		EMISSION = edge_glow_color.rgb * (edge_mask * 2.5) + rim_color.rgb * (fresnel * 0.6);
		ALPHA = alpha;
	} else {
		// Sustained Optical Camouflage Mode (自身操控视角：清爽半透明光学迷彩)
		float fresnel = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), rim_power);
		float scan = sin(UV.y * 32.0 - TIME * scan_speed) * 0.12 + 0.88;
		
		vec3 col = mix(camo_color.rgb, rim_color.rgb, fresnel * 0.7);
		float alpha = clamp((camo_alpha + fresnel * 0.45) * scan, 0.0, 1.0);
		
		ALBEDO = col;
		EMISSION = rim_color.rgb * fresnel * 0.85;
		ALPHA = alpha;
	}
}
