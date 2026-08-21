shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 ember_color : source_color = vec4(1.0, 0.45, 0.12, 1.0);
uniform vec4 char_color : source_color = vec4(0.08, 0.05, 0.04, 1.0);
uniform float burn_width : hint_range(0.01, 0.25) = 0.08;

// Procedural noise for fire/ash erosion without external texture dependencies
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	vec2 shift = vec2(100.0);
	for (int i = 0; i < 4; ++i) {
		v += a * noise(p);
		p = p * 2.0 + shift;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	if (progress <= 0.001) {
		COLOR = vec4(0.0);
		discard;
	}

	vec2 uv = UV;
	// Radial burn distortion starting from center/click outwards
	float n = fbm(uv * 7.5 + vec2(progress * 1.5, -progress * 0.8));
	float dist_from_center = length(uv - vec2(0.5)) * 0.6;
	float burn_threshold = progress * 1.4 - dist_from_center * 0.3;

	if (n < burn_threshold - burn_width) {
		// Fully burned to ash / dark void
		COLOR = vec4(char_color.rgb, min(1.0, progress * 1.8));
	} else if (n < burn_threshold) {
		// Glowing ember burning edge
		float edge_t = (burn_threshold - n) / burn_width;
		vec3 fire = mix(ember_color.rgb * 3.2, char_color.rgb, edge_t);
		COLOR = vec4(fire, 1.0);
	} else {
		// Chromatic aberration and heat shock before burning
		float shock = smoothstep(burn_threshold + burn_width * 2.0, burn_threshold, n);
		vec4 base = texture(TEXTURE, uv);
		COLOR = mix(vec4(0.0), vec4(ember_color.rgb, 0.35), shock * progress);
	}
}
