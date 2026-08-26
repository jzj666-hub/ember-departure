shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Grand Volumetric Abyssal Dark Mist Dome Shader
// Rolling, churning procedural dark miasma cloud dome - 100% mathematical, 0% raw texture clipping.

uniform vec4 color_dark_ink : source_color = vec4(0.02, 0.01, 0.04, 0.95);      // Deepest Abyssal Ink
uniform vec4 color_smoke_body : source_color = vec4(0.08, 0.04, 0.12, 0.85);    // Rolling Dark Violet Smoke
uniform vec4 color_ethereal_cyan : source_color = vec4(0.05, 0.85, 1.1, 0.45);   // Faint Ethereal Wisps

uniform float speed : hint_range(0.0, 10.0) = 1.6;
uniform float smoke_density : hint_range(1.0, 20.0) = 6.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	// Billowing volumetric turbulent deformation along the dome surface
	float n = sin(VERTEX.x * 0.8 + TIME * speed * 0.7) * cos(VERTEX.z * 0.8 + TIME * speed * 0.5);
	VERTEX += NORMAL * (n * 0.25);
}

void fragment() {
	// Spherical coordinate mapping for continuous seamless smoke turbulence
	vec3 p = normalize(VERTEX);
	
	// Multi-frequency spherical harmonic noise
	float n1 = sin(p.x * smoke_density + p.y * (smoke_density * 1.5) - TIME * speed);
	float n2 = cos(p.z * smoke_density - p.x * (smoke_density * 1.2) + TIME * (speed * 1.2));
	float n3 = sin(p.y * (smoke_density * 2.2) + p.z * (smoke_density * 1.8) - TIME * (speed * 0.8));
	
	float cloud = (n1 * 0.45 + n2 * 0.35 + n3 * 0.20) * 0.5 + 0.5;
	cloud = pow(cloud, 1.4);
	
	// Soft Fresnel rim defining the misty perimeter
	float fresnel = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.2);
	
	// Ground fade so it merges seamlessly into the terrain
	float ground_fade = smoothstep(-0.2, 0.4, VERTEX.y);
	
	// Color mixing: Deep ink black core, dark violet body, subtle glowing ethereal rim
	vec3 col = mix(color_dark_ink.rgb, color_smoke_body.rgb, cloud * 0.8);
	col = mix(col, color_ethereal_cyan.rgb, fresnel * cloud * 0.35);
	
	float alpha = (cloud * 0.70 + fresnel * 0.45) * ground_fade * fade * color_dark_ink.a;
	
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 0.95);
}
