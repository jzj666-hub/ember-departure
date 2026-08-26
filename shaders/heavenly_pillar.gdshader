shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Grand Heavenly Light Pillar & Divine Ray of Purification
uniform vec4 beam_core : source_color = vec4(1.9, 1.9, 1.8, 1.0);       // Ultra-bright white-gold core
uniform vec4 beam_gold : source_color = vec4(1.0, 0.85, 0.45, 0.95);    // Sacred radiant gold
uniform vec4 beam_aurora : source_color = vec4(0.35, 0.92, 0.95, 0.7);  // Ethereal aurora cyan edge
uniform float speed : hint_range(0.0, 20.0) = 6.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	// Vertical upward and downward light streaks
	float streak1 = sin(UV.x * 24.0 + TIME * speed * 0.5) * 0.5 + 0.5;
	float streak2 = sin(UV.x * 48.0 - TIME * speed * 0.8 + UV.y * 8.0) * 0.5 + 0.5;
	float streaks = (streak1 * 0.6 + streak2 * 0.4);
	streaks = pow(streaks, 2.5);
	
	// Soft vertical gradient (dense near ground, softly disappearing in the clouds)
	float height_fade = smoothstep(0.0, 0.08, UV.y) * smoothstep(1.0, 0.65, UV.y);
	
	// Fresnel rim highlight
	float fresnel = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	
	// Core intensity
	float core = pow(fresnel, 4.0) + streaks * 0.5;
	
	vec3 col = mix(beam_aurora.rgb, beam_gold.rgb, clamp(streaks * 1.2, 0.0, 1.0));
	col = mix(col, beam_core.rgb, clamp(core * 1.4, 0.0, 1.0));
	
	float alpha = (streaks * 0.65 + fresnel * 0.55) * height_fade * fade * beam_gold.a;
	
	ALBEDO = col * 2.2;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
