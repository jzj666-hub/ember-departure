shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Ethereal Vanishing Point Core & Infinite Depth Tunnel Soft Ring
uniform vec4 core_color : source_color = vec4(1.8, 2.2, 2.8, 1.0);       // Ultra-bright ethereal singularity
uniform vec4 ring_cyan : source_color = vec4(0.05, 0.85, 1.4, 0.85);     // Cyan tunnel glow
uniform vec4 ring_violet : source_color = vec4(0.65, 0.15, 1.1, 0.65);   // Deep violet depth melt
uniform float ring_radius : hint_range(0.1, 0.9) = 0.55;
uniform float ring_softness : hint_range(0.02, 0.4) = 0.18;
uniform float pulse_speed : hint_range(0.0, 15.0) = 4.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform bool is_singularity = false; // When true, renders the central soft blinding flare core

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) {
		discard;
	}
	
	if (is_singularity) {
		// Central Ethereal Singularity Flare: Ultra-soft luminous star core
		float core = 1.0 - smoothstep(0.0, 0.75, r);
		core = pow(core, 2.2);
		
		float rays = sin(atan(p.y, p.x) * 8.0 + TIME * pulse_speed) * 0.1 + 0.9;
		float flare = core * rays;
		
		vec3 col = mix(ring_cyan.rgb, core_color.rgb, clamp(core * 1.5, 0.0, 1.0));
		ALBEDO = col * 2.2;
		ALPHA = clamp(flare * fade, 0.0, 1.0);
	} else {
		// Infinite Depth Soft Energy Ring (exponentially soft gaussian edge)
		float ring_dist = abs(r - ring_radius);
		float ring_mask = exp(-pow(ring_dist / ring_softness, 2.0));
		
		// Soft breathing wave
		float wave = sin(r * 18.0 - TIME * pulse_speed) * 0.1 + 0.9;
		
		// Outer chromatic shift to violet
		vec3 ring_col = mix(ring_cyan.rgb, ring_violet.rgb, smoothstep(0.3, 0.8, r));
		
		ALBEDO = ring_col * 1.6 * wave;
		ALPHA = clamp(ring_mask * wave * fade * ring_cyan.a, 0.0, 1.0);
	}
}
