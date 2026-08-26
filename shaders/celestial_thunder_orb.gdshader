shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

// Non-Overexposed Exquisite Thunder Orb with Crisp Golden/Purple Runes
uniform vec4 orb_base : source_color = vec4(0.20, 0.06, 0.36, 0.90);    // Deep dark obsidian-violet core body
uniform vec4 rune_gold : source_color = vec4(1.0, 0.84, 0.28, 1.0);     // Crisp vibrant golden runes (NOT white)
uniform vec4 rune_violet : source_color = vec4(0.82, 0.38, 1.0, 1.0);   // Electric neon violet rune accents
uniform vec4 rim_glow : source_color = vec4(0.65, 0.25, 0.95, 0.70);    // Gentle plasma rim
uniform float spin_speed : hint_range(0.1, 5.0) = 1.2;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float brightness : hint_range(0.1, 2.0) = 1.0;

uniform sampler2D rune_tex : source_color, hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D lightning_tex : source_color, hint_default_black, filter_linear_mipmap, repeat_enable;

void fragment() {
	// Spherical Fresnel rim highlight (soft edge definition, no blinding white)
	float fresnel = 1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float rim = pow(fresnel, 2.2);

	// Rotating UV coordinates for surface rune pattern
	float t = TIME * spin_speed;
	vec2 ruv1 = vec2(UV.x * 2.0 + t * 0.20, UV.y + sin(UV.x * 4.0 + t) * 0.04);
	vec2 ruv2 = vec2(UV.x * 2.0 - t * 0.25, UV.y * 1.5 - t * 0.10);

	// Sample the rune pattern texture
	vec4 t1 = texture(rune_tex, ruv1);
	float lum1 = max(t1.r, max(t1.g, t1.b));
	float rune1 = smoothstep(0.12, 0.48, lum1);

	// Sample electric micro-crackle for rune energy
	float elec = texture(lightning_tex, ruv2).r;
	float rune2 = smoothstep(0.20, 0.60, elec) * 0.45;

	float pattern = clamp(rune1 + rune2, 0.0, 1.0);

	// Colored Rune Tinting: Rich Gold core with Neon Violet outer edges, strictly NO white washing
	vec3 rune_col = mix(rune_violet.rgb, rune_gold.rgb, pattern);

	// Blend dark crystal plasma body with vivid colored runes
	vec3 base_body = mix(orb_base.rgb, rim_glow.rgb, rim * 0.6);
	vec3 final_col = mix(base_body, rune_col, pattern);

	ALBEDO = final_col * brightness;
	ALPHA = clamp((orb_base.a + pattern * 0.3 + rim * 0.4) * fade, 0.0, 1.0);
}
