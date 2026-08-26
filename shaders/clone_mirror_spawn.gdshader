shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Prismatic Mirror Phantom Clone Dispersal & Shatter Wave
// Quantum mirror distortion rings with holographic glitch dispersion - 100% procedural.

uniform vec4 color_mirror_cyan : source_color = vec4(0.15, 0.95, 1.5, 0.95);
uniform vec4 color_phantom_violet : source_color = vec4(0.85, 0.25, 1.2, 0.85);
uniform vec4 color_sparkle : source_color = vec4(1.0, 1.0, 1.0, 1.0);

uniform float speed : hint_range(0.0, 15.0) = 5.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 center = UV - vec2(0.5);
	float r = length(center) * 2.0;
	if (r > 1.0) {
		discard;
	}
	float angle = atan(center.y, center.x);
	
	// 1. Concentric Shattering Mirror Interference Rings
	float ring1 = sin(r * 18.0 - TIME * speed) * 0.5 + 0.5;
	float ring2 = sin(r * 32.0 + angle * 6.0 - TIME * (speed * 1.5)) * 0.5 + 0.5;
	float pattern = pow(ring1 * 0.6 + ring2 * 0.4, 2.5);
	
	// 2. Polygonal Shard Glitch Artifacts
	float shard = step(0.4, fract(angle * 4.7746 + r * 3.0));
	
	// 3. Color Grading: Cyan to Phantom Violet with White Sparkle Peaks
	vec3 col = mix(color_mirror_cyan.rgb, color_phantom_violet.rgb, r);
	col = mix(col, color_sparkle.rgb, pattern * shard * 0.8);
	
	float edge_fade = smoothstep(1.0, 0.75, r);
	float alpha = (pattern * 0.8 + 0.2) * edge_fade * fade * color_mirror_cyan.a;
	
	ALBEDO = col * 1.8;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
