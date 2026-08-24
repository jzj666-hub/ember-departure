shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Expanding 3D Shockwave Blast Dome / Hemisphere
uniform vec4 dome_color : source_color = vec4(1.0, 0.55, 0.15, 0.95);
uniform vec4 core_color : source_color = vec4(1.5, 1.2, 0.8, 1.0);
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float rim_power : hint_range(0.5, 5.0) = 2.0;

uniform sampler2D noise_tex : source_color, hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float noise_mix : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	// Fresnel rim highlight for the expanding dome surface
	float fresnel = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), rim_power);
	
	// Soft bottom cut-off near ground and crest highlight
	float height_gradient = smoothstep(0.0, 0.2, UV.y) * smoothstep(1.0, 0.7, UV.y);
	
	// Subtle blast turbulence noise
	vec2 nuv = vec2(UV.x * 3.0, UV.y * 2.0 - TIME * 4.0);
	float n = texture(noise_tex, nuv).r;
	float pattern = mix(1.0, n * 1.5, noise_mix);
	
	vec3 col = mix(dome_color.rgb, core_color.rgb, clamp(fresnel * 1.2, 0.0, 1.0));
	float alpha = (fresnel * 0.85 + 0.15) * height_gradient * pattern * dome_color.a * fade;
	
	ALBEDO = col * 1.5;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
