shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Elegant, Slender, Subtle Golden Silk Ribbon Trail Shader
// Smooth continuous flow, delicate soft translucency, beautiful trailing wake.

uniform vec4 ribbon_gold_color : source_color = vec4(1.0, 0.82, 0.20, 0.70); // Gentle warm gold
uniform vec4 ribbon_sun_core : source_color = vec4(1.0, 0.96, 0.65, 0.85);   // Luminous soft silk core
uniform float speed : hint_range(0.0, 10.0) = 3.2;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	// UV.x along ribbon length (0.0 at old tail -> 1.0 at newest foot position)
	// UV.y across width (0.0 to 1.0)
	
	// Ultra-smooth lateral edge falloff (no hard borders)
	float width_dist = abs(UV.y - 0.5) * 2.0;
	float side_fade = pow(1.0 - width_dist, 1.8);
	
	// Length falloff: softly tapered at the trailing tail, clean at the leading head
	float len_fade = smoothstep(0.0, 0.35, UV.x) * smoothstep(1.0, 0.95, UV.x);
	
	// Delicate silk thread undulation
	float silk_flow1 = sin(UV.x * 16.0 - TIME * speed + UV.y * 4.0) * 0.5 + 0.5;
	float silk_flow2 = cos(UV.x * 28.0 + TIME * (speed * 1.2) - UV.y * 6.0) * 0.5 + 0.5;
	float silk = pow(silk_flow1 * 0.6 + silk_flow2 * 0.4, 2.0);
	
	vec3 col = mix(ribbon_gold_color.rgb, ribbon_sun_core.rgb, clamp(silk * 0.6 + (1.0 - width_dist * 0.6), 0.0, 1.0));
	
	// Soft, subtle, graceful aura translucency
	float alpha = (silk * 0.35 + 0.65) * side_fade * len_fade * fade * ribbon_gold_color.a;
	
	ALBEDO = col * 1.15;
	ALPHA = clamp(alpha, 0.0, 0.75);
}
