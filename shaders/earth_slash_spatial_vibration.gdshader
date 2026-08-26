shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Pure Procedural Sector Space Vibration & Refraction (Zero Texture Dependencies)
// Trembles and refracts the screen space precisely across the forward attack sector.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float sector_angle_deg : hint_range(10.0, 90.0) = 40.0;
uniform float wave_progress : hint_range(0.0, 1.0) = 1.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

const float DISTORTION_STRENGTH = 0.028;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
	           mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	// Sector root is at UV (0.5, 0.0), pointing forward toward UV (0.5, 1.0)
	vec2 dir = UV - vec2(0.5, 0.0);
	float dist = length(dir) * 2.0; // 0.0 at root, ~2.0 at far edge

	// Angle from forward axis
	float ang_rad = atan(abs(dir.x), max(dir.y, 0.0001));
	float half_ang_rad = radians(sector_angle_deg);

	// Sector mask with soft lateral edge fade
	float angular_mask = 1.0 - smoothstep(half_ang_rad * 0.82, half_ang_rad, ang_rad);
	if (dir.y <= 0.0) {
		angular_mask = 0.0;
	}

	// Forward propagating shock vibration band
	float band_dist = abs(dist - wave_progress * 1.7);
	float wave_band = exp(-band_dist * 8.0);
	float fill_band = (1.0 - smoothstep(0.0, wave_progress * 1.7, dist)) * 0.45;
	float total_mask = (wave_band + fill_band) * angular_mask * (1.0 - smoothstep(1.7, 2.0, dist));

	// High frequency spatial tremor noise
	vec2 p = UV * 18.0;
	float n1 = noise(p + vec2(sin(TIME * 26.0) * 0.3, cos(TIME * 22.0) * 0.3));
	float n2 = noise(p * 1.5 - vec2(TIME * 18.0, sin(TIME * 20.0)));
	vec2 tremor_dir = vec2(n1 - 0.5, n2 - 0.5) * 2.0;

	// Screen-space refraction offset
	vec2 offset = tremor_dir * DISTORTION_STRENGTH * total_mask * fade;
	vec4 screen_col = texture(screen_tex, SCREEN_UV + offset);

	ALBEDO = screen_col.rgb;
	ALPHA = fade * clamp(total_mask, 0.0, 1.0);
}
