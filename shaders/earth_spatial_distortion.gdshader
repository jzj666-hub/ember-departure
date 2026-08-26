shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Localized 3D Screen Refraction Spatial Distortion (真实局部空间震荡/空气折射冲击波 - 无卡顿优化)
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D noise_tex : source_color, hint_default_black, filter_linear, repeat_enable;
uniform float distortion_strength : hint_range(0.0, 0.2) = 0.055;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform vec4 rim_tint : source_color = vec4(0.88, 0.92, 0.98, 0.35); // Silver-white shockwave condensation shimmer

void fragment() {
	// Fresnel rim profile on expanding shockwave dome
	float fresnel = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.2);
	
	// Shockwave turbulence noise
	vec2 nuv = UV * 3.5 + vec2(sin(TIME * 12.0) * 0.06, -TIME * 3.0);
	float n = texture(noise_tex, nuv).r - 0.5;
	
	// Normal-based screen-space refraction offset
	vec2 offset = NORMAL.xy * distortion_strength * (fresnel * 1.2 + 0.25) * (n * 0.7 + 0.65) * fade;
	vec4 screen_col = texture(screen_tex, SCREEN_UV + offset);
	
	// Blend refracted background with subtle silver-white shockwave crest
	vec3 col = mix(screen_col.rgb, rim_tint.rgb, fresnel * rim_tint.a * fade);
	
	ALBEDO = col;
	ALPHA = fade;
}
