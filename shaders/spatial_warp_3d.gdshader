shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Multi-Tier 3D Spatial Electromagnetic Warp: Neon Magenta + Electric Cyan + Deep Void Violet
uniform vec4 warp_magenta : source_color = vec4(1.0, 0.05, 0.65, 0.85); // High-contrast neon magenta
uniform vec4 warp_cyan : source_color = vec4(0.08, 0.92, 1.8, 1.0);     // Electric cyan energy core
uniform vec4 warp_violet : source_color = vec4(0.25, 0.05, 0.55, 0.7);  // Deep cosmic void edge
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float wave_speed : hint_range(0.0, 20.0) = 6.0;
uniform float wave_freq : hint_range(1.0, 30.0) = 10.0;
uniform sampler2D noise_tex : source_color, hint_default_black, filter_linear_mipmap, repeat_enable;

void fragment() {
	// Fresnel rim highlight
	float fresnel = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.2);
	
	// Pulsating electromagnetic distortion wave
	vec2 nuv = vec2(UV.x * 3.0 + sin(TIME * wave_speed) * 0.1, UV.y * 2.0 - TIME * (wave_speed * 0.5));
	float n = texture(noise_tex, nuv).r;
	
	float wave = sin(UV.y * wave_freq - TIME * wave_speed) * 0.5 + 0.5;
	float pattern = (fresnel * 0.7 + wave * 0.3) * (n * 0.8 + 0.5);
	
	// Multi-Tier Chromatic Shift: Violet Base -> Magenta Wave -> Cyan Core
	vec3 col = mix(warp_violet.rgb, warp_magenta.rgb, wave);
	col = mix(col, warp_cyan.rgb, clamp(fresnel * 1.35, 0.0, 1.0));
	
	ALBEDO = col * 2.2;
	ALPHA = clamp(pattern * fade * warp_magenta.a, 0.0, 1.0);
}
