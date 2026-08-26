shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Dense, Opaque, Thick Volumetric Black Mist Shroud Shader
// Solid ink-black core, multi-harmonic churning density - 100% dense opaque cloud, not a hollow shell.

uniform vec4 color_deep_ink : source_color = vec4(0.02, 0.01, 0.03, 0.98);    // Pitch Void Ink Black
uniform vec4 color_charcoal_smoke : source_color = vec4(0.08, 0.05, 0.10, 0.95);// Heavy Churning Charcoal Smoke
uniform vec4 color_shadow_fringe : source_color = vec4(0.16, 0.11, 0.18, 0.85); // Turbulent Ash Wisps

uniform float speed : hint_range(0.0, 10.0) = 3.2;
uniform float smoke_density : hint_range(1.0, 20.0) = 7.0;
uniform float expansion_progress : hint_range(0.0, 1.0) = 0.0;
uniform float core_opacity : hint_range(0.0, 2.0) = 1.3;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	// Deep turbulent deformation to break spherical regularity into organic boiling smoke clumps
	float n1 = sin(VERTEX.x * 2.5 + TIME * speed * 1.1) * cos(VERTEX.z * 2.5 + TIME * speed * 0.9);
	float n2 = sin(VERTEX.y * 3.5 - TIME * speed * 1.3) * 0.5;
	VERTEX += NORMAL * ((n1 + n2) * 0.28 * (1.0 + expansion_progress * 0.6));
}

void fragment() {
	vec3 p = normalize(VERTEX);
	
	// 1. Multi-octave dense volumetric turbulence
	float n1 = sin(p.x * smoke_density + p.y * (smoke_density * 1.4) - TIME * speed);
	float n2 = cos(p.z * smoke_density - p.x * (smoke_density * 1.2) + TIME * (speed * 1.3));
	float n3 = sin(p.y * (smoke_density * 2.2) + p.z * (smoke_density * 1.8) - TIME * (speed * 0.9));
	float n4 = cos(p.x * (smoke_density * 3.6) + p.y * (smoke_density * 3.2) + TIME * (speed * 1.5));
	
	float billow = (n1 * 0.35 + n2 * 0.30 + n3 * 0.20 + n4 * 0.15) * 0.5 + 0.5;
	billow = pow(billow, 1.1);
	
	// 2. High-Density Opaque Core (No hollow transparent bubble!)
	float density_factor = clamp(billow * 0.65 + 0.45, 0.0, 1.0);
	
	// Smooth edge falloff so boundary is soft and misty, not hard geometry
	float rim = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float soft_border = smoothstep(0.05, 0.35, rim);
	
	// Dissipation as the mist expands outwards
	float dissipation = smoothstep(1.0, 0.15, expansion_progress);
	
	// Color Mixing: Ultra-dense Pitch Ink Black Core -> Dark Charcoal Smoke -> Soft Ash Edge
	vec3 col = mix(color_deep_ink.rgb, color_charcoal_smoke.rgb, billow * 0.7);
	col = mix(col, color_shadow_fringe.rgb, (1.0 - rim) * 0.4);
	
	// Truly dense, heavy, solid black mist opacity
	float alpha = density_factor * soft_border * dissipation * fade * core_opacity;
	
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 0.98);
}
