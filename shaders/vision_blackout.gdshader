shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// Screen-space vision blackout: everything beyond u_vision_radius of u_actor_pos goes black,
// with a soft falloff over u_soft_edge. Drawn as a fullscreen quad (see vertex()).
// Used by SkillMist.VisionBlackout. Set u_blind_active to 0.0 to discard entirely.

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform vec3 u_actor_pos = vec3(0.0);
uniform float u_vision_radius = 2.0;
uniform float u_soft_edge = 0.35;
uniform float u_blind_active = 1.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	if (u_blind_active < 0.01) {
		discard;
	}

	float raw_depth = texture(depth_texture, SCREEN_UV).x;
	vec3 scene_color = texture(screen_texture, SCREEN_UV).rgb;

	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos.xyz /= view_pos.w;
	vec4 world_pos = INV_VIEW_MATRIX * vec4(view_pos.xyz, 1.0);

	float dist = distance(world_pos.xyz, u_actor_pos);

	ALPHA = 1.0;
	if (raw_depth >= 0.99999 || raw_depth <= 0.000001 || isinf(dist) || isnan(dist) || dist >= u_vision_radius) {
		ALBEDO = vec3(0.0);
	} else if (dist <= max(u_vision_radius - u_soft_edge, 0.0)) {
		ALBEDO = scene_color;
	} else {
		float factor = 1.0 - clamp((dist - (u_vision_radius - u_soft_edge)) / max(u_soft_edge, 0.001), 0.0, 1.0);
		factor = factor * factor;
		ALBEDO = scene_color * factor;
	}
}
