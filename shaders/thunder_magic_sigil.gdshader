shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Ground Thunder Magic Sigil: Aspect-Corrected 1:1 Circle with Sharp Purple-Gold Runes
uniform vec4 sigil_purple : source_color = vec4(0.55, 0.18, 0.85, 0.95); // Imperial Purple
uniform vec4 sigil_gold : source_color = vec4(1.0, 0.82, 0.35, 1.0);    // Warm Radiant Gold
uniform float spin_speed : hint_range(-10.0, 10.0) = 0.30;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float brightness : hint_range(0.1, 3.0) = 1.10;
uniform float rune_threshold : hint_range(0.0, 0.5) = 0.05;

uniform sampler2D sigil_tex : source_color, hint_default_black, filter_linear_mipmap;

void fragment() {
	vec2 center = UV - vec2(0.5);

	// Auto-correct texture aspect ratio so the pattern is ALWAYS a 1:1 perfect circle
	ivec2 tex_sz = textureSize(sigil_tex, 0);
	if (tex_sz.x > 0 && tex_sz.y > 0) {
		if (tex_sz.x > tex_sz.y) {
			center.x *= float(tex_sz.x) / float(tex_sz.y);
		} else if (tex_sz.y > tex_sz.x) {
			center.y *= float(tex_sz.y) / float(tex_sz.x);
		}
	}

	float dist = length(center) * 2.0;

	// Slow smooth rotation
	float sa = sin(TIME * spin_speed);
	float ca = cos(TIME * spin_speed);
	vec2 ruv = vec2(center.x * ca - center.y * sa, center.x * sa + center.y * ca) + vec2(0.5);

	// Discard any sampling outside the [0, 1] unit square after aspect correction
	if (ruv.x < 0.0 || ruv.x > 1.0 || ruv.y < 0.0 || ruv.y > 1.0) {
		discard;
	}

	// Sample user's black-and-white雷电法阵 texture
	vec4 tex_col = texture(sigil_tex, ruv);
	// Extract luminance: white is rune pattern, black is transparent background
	float lum = max(tex_col.r, max(tex_col.g, tex_col.b));
	lum = max(lum, tex_col.a * tex_col.r);

	// Sharp contrast thresholding: black is 0 alpha, runes stand out clearly
	float rune_alpha = smoothstep(rune_threshold, rune_threshold + 0.25, lum);

	// Purple-Gold two-tone gradient: edge of line is purple, core of line is gold
	float gold_factor = smoothstep(0.32, 0.85, lum);
	vec3 rune_col = mix(sigil_purple.rgb, sigil_gold.rgb, gold_factor);

	// Soft circular edge fade to prevent any quad corner clipping
	float outer_fade = smoothstep(1.0, 0.90, dist);

	ALBEDO = rune_col * brightness;
	ALPHA = rune_alpha * fade * outer_fade * sigil_purple.a;
}
