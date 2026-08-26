shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Multi-Tier Expanding 3D Shockwave Blast Dome: White-Gold Core -> Blazing Orange -> Crimson-Violet Wavefront
uniform vec4 core_gold : source_color = vec4(1.9, 1.6, 0.9, 1.0);       // White-hot blast center
uniform vec4 mid_orange : source_color = vec4(1.0, 0.45, 0.05, 0.95);    // Blazing fiery mid
uniform vec4 wave_crimson : source_color = vec4(0.75, 0.06, 0.35, 0.85); // High-speed shockwave front edge
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float rim_power : hint_range(0.5, 5.0) = 2.2;

uniform sampler2D noise_tex : source_color, hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float noise_mix : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	// Fresnel rim highlight for the expanding dome surface
	float fresnel = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), rim_power);
	
	// Soft ground cut-off and top crest highlight
	float height_gradient = smoothstep(0.0, 0.2, UV.y) * smoothstep(1.0, 0.7, UV.y);
	
	// Blast turbulence noise
	vec2 nuv = vec2(UV.x * 3.0, UV.y * 2.0 - TIME * 4.0);
	float n = texture(noise_tex, nuv).r;
	float pattern = mix(1.0, n * 1.5, noise_mix);
	
	// Multi-Tier Color Gradient: Wave Edge (Crimson/Violet) -> Mid (Orange) -> Crest/Core (Gold)
	vec3 col = mix(wave_crimson.rgb, mid_orange.rgb, clamp(fresnel * 1.4, 0.0, 1.0));
	col = mix(col, core_gold.rgb, clamp(pow(fresnel, 2.5) * 1.5, 0.0, 1.0));
	
	float alpha = (fresnel * 0.85 + 0.15) * height_gradient * pattern * mid_orange.a * fade;
	
	ALBEDO = col * 1.6;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
