shader_type canvas_item;

uniform vec4 border_color : source_color = vec4(0.25, 0.85, 1.0, 1.0);
uniform float border_width : hint_range(0.0, 0.2) = 0.04;

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float dist = length(uv);
	float radius = 0.5;

	// Anti-aliased circular alpha mask
	float edge_softness = fwidth(dist) * 1.5;
	float alpha = 1.0 - smoothstep(radius - edge_softness, radius, dist);

	if (alpha <= 0.0) {
		discard;
	}

	vec4 tex_color = texture(TEXTURE, UV);

	// Outer border ring
	float border_inner = radius - border_width;
	float border_factor = smoothstep(border_inner - edge_softness, border_inner + edge_softness, dist);

	vec4 final_color = mix(tex_color, border_color, border_factor * border_color.a);
	final_color.a *= alpha;

	COLOR = final_color;
}
