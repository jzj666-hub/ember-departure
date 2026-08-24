shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Mach vapor cone & supersonic air-cleaving streamlines.
uniform vec4 wind_color : source_color = vec4(0.55, 0.90, 1.0, 0.7);
uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 0.95);
uniform float speed : hint_range(0.0, 60.0) = 24.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float streak_count : hint_range(4.0, 40.0) = 18.0;

// Painted slash sheet scrolled along the cone. tex_mix stays 0 until a caller binds one.
uniform sampler2D wind_tex : source_color, hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float tex_mix : hint_range(0.0, 1.0) = 0.0;
uniform float tex_tiling : hint_range(0.25, 8.0) = 2.0;

void fragment() {
	float ribbon = sin(UV.x * 3.1415926 * streak_count);
	ribbon = pow(ribbon * 0.5 + 0.5, 4.0);

	float stream1 = sin((UV.y * 22.0) - (TIME * speed)) * 0.5 + 0.5;
	stream1 = pow(stream1, 3.0);

	float stream2 = sin((UV.y * 45.0 + UV.x * 6.0) - (TIME * speed * 1.6)) * 0.5 + 0.5;
	stream2 = pow(stream2, 5.0);

	float combined_stream = max(stream1, stream2 * 0.9) * (0.3 + 0.7 * ribbon);

	// Scrolls down the cone's length: the sheet supplies the streak detail the sine stack
	// only approximates. Ribbon still gates it so the cone keeps its lengthwise banding.
	vec2 wuv = vec2(UV.x, fract(UV.y * tex_tiling - TIME * speed * 0.03));
	float sheet = texture(wind_tex, wuv).r * (0.35 + 0.65 * ribbon);
	float stream = mix(combined_stream, sheet, tex_mix);

	float tip_spark = pow(1.0 - clamp(UV.y * 1.8, 0.0, 1.0), 3.0);
	float body_fade = sin(clamp(UV.y, 0.0, 1.0) * 3.1415926);

	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);

	vec3 col = mix(wind_color.rgb, core_color.rgb, clamp(tip_spark + stream * 0.5, 0.0, 1.0));
	float alpha = (stream * 0.65 + fresnel * 0.45 + tip_spark * 0.8) * body_fade * fade * wind_color.a;

	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
