shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Delicate 3D Cylindrical Fine Lightning Web (减量、透光、紫金白三色)
uniform vec4 arc_violet : source_color = vec4(0.62, 0.20, 0.95, 0.70); // Plasma royal violet
uniform vec4 arc_gold : source_color = vec4(0.95, 0.78, 0.30, 0.75);   // Warm radiant gold
uniform vec4 arc_core : source_color = vec4(1.20, 1.18, 1.30, 0.80);  // Soft luminous core
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float brightness : hint_range(0.1, 3.0) = 1.15;
uniform float transparency : hint_range(0.1, 1.0) = 0.42;
uniform float frequency : hint_range(5.0, 60.0) = 22.0;
uniform float jitter_speed : hint_range(10.0, 80.0) = 38.0;

uniform sampler2D lightning_tex : source_color, hint_default_black, filter_linear_mipmap, repeat_enable;

void fragment() {
	// Refined lightweight cylindrical coordinate sampling with high-speed micro-jitter
	float t = TIME * jitter_speed;
	vec2 uv1 = vec2(UV.x * 3.0 + sin(t * 1.3 + UV.y * frequency) * 0.08, UV.y * 2.2 - t * 0.16);
	vec2 uv2 = vec2(UV.x * 4.5 - cos(t * 1.1 - UV.y * frequency * 1.1) * 0.07, UV.y * 3.0 + t * 0.22);

	float n1 = texture(lightning_tex, uv1).r;
	float n2 = texture(lightning_tex, uv2).r;

	// Delicate fine arc filaments (reduced exponent density)
	float fine_arcs = pow(n1 * 1.15, 3.4) + pow(n2 * 1.10, 3.6);
	
	// Vertical smooth taper at ground and sky
	float v_taper = smoothstep(0.0, 0.06, UV.y) * smoothstep(1.0, 0.94, UV.y);
	
	float arc_intensity = clamp(fine_arcs * v_taper * 1.6, 0.0, 1.0);

	// Purple-Gold-White triad color composition
	vec3 col = mix(arc_violet.rgb, arc_gold.rgb, clamp(arc_intensity * 1.2, 0.0, 1.0));
	col = mix(col, arc_core.rgb, clamp(pow(arc_intensity, 2.2) * 0.8, 0.0, 1.0));

	ALBEDO = col * brightness;
	ALPHA = clamp(arc_intensity * fade * transparency, 0.0, 1.0);
}
