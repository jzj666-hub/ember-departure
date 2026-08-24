shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// Dynamic Roaring Fire Wall / Flame Curtain
uniform vec4 fire_core : source_color = vec4(1.8, 1.4, 0.8, 1.0);
uniform vec4 fire_mid : source_color = vec4(1.0, 0.55, 0.08, 0.95);
uniform vec4 fire_top : source_color = vec4(0.8, 0.15, 0.02, 0.8);
uniform float speed : hint_range(0.0, 20.0) = 4.5;
uniform float flame_density : hint_range(2.0, 30.0) = 14.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	// Godot QuadMesh upright: UV.y = 0.0 is top, UV.y = 1.0 is bottom near ground.
	// height_ratio: 0.0 (ground root) -> 1.0 (sky top)
	float height_ratio = 1.0 - UV.y;
	
	// Vertical upward flame turbulence using layered trigonometric frequencies
	float f1 = sin(UV.x * flame_density + (TIME * speed * 0.8)) * 0.5 + 0.5;
	float f2 = sin(UV.x * (flame_density * 2.2) - (TIME * speed * 1.4) + height_ratio * 6.0) * 0.5 + 0.5;
	float f3 = sin(UV.x * (flame_density * 0.5) + (height_ratio * 18.0) - (TIME * speed * 2.8)) * 0.5 + 0.5;
	
	float combined_tongue = (f1 * 0.35 + f2 * 0.4 + f3 * 0.25);
	
	// Flame dissipation along height (dense intense bottom root, flickering tearing top tongues)
	float flame_mask = 1.0 - height_ratio;
	flame_mask += (combined_tongue - 0.5) * 0.45 * (1.0 - height_ratio * 0.5);
	flame_mask = clamp(flame_mask * 1.5, 0.0, 1.0);
	flame_mask = pow(flame_mask, 1.8);
	
	// Side edge smooth fade
	float side_fade = sin(clamp(UV.x, 0.0, 1.0) * 3.1415926);
	side_fade = pow(side_fade, 0.4);
	
	// Dynamic heat color gradient (Dense white-hot core at bottom -> blazing orange mid -> tearing red top)
	vec3 col = mix(fire_top.rgb, fire_mid.rgb, clamp(flame_mask * 1.4, 0.0, 1.0));
	col = mix(col, fire_core.rgb, clamp(pow(flame_mask, 3.0) * 1.2, 0.0, 1.0));
	
	float alpha = flame_mask * side_fade * fade * fire_mid.a;
	
	ALBEDO = col * 1.6;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
