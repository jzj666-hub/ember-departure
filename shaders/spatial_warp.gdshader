shader_type canvas_item;

// Screen-space spatial distortion and electromagnetic chromatic aberration warp.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float warp_intensity : hint_range(0.0, 0.2) = 0.04;
uniform float wave_frequency : hint_range(1.0, 30.0) = 14.0;
uniform float wave_speed : hint_range(0.0, 15.0) = 5.0;
uniform float vignette_power : hint_range(0.5, 4.0) = 1.8;
uniform vec4 tint_color : source_color = vec4(0.3, 0.7, 1.0, 0.18);
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 center = vec2(0.5, 0.5);
	vec2 to_center = uv - center;
	float dist = length(to_center);
	
	// Radial pulse wave & swirl distortion
	float wave = sin(dist * wave_frequency - TIME * wave_speed) * warp_intensity * fade;
	vec2 dir = (dist > 0.001) ? normalize(to_center) : vec2(0.0);
	
	// Chromatic aberration (RGB shift)
	vec2 offset_r = dir * (wave * 1.25);
	vec2 offset_g = dir * wave;
	vec2 offset_b = dir * (wave * 0.75);
	
	float r = texture(screen_texture, uv + offset_r).r;
	float g = texture(screen_texture, uv + offset_g).g;
	float b = texture(screen_texture, uv + offset_b).b;
	
	vec4 base_col = vec4(r, g, b, 1.0);
	
	// Edge vignette tint for electric confusion feeling
	float edge = pow(dist * 1.4, vignette_power) * fade;
	vec3 final_rgb = mix(base_col.rgb, tint_color.rgb, clamp(edge * tint_color.a * 2.5, 0.0, 1.0));
	
	COLOR = vec4(final_rgb, 1.0);
}
