shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

// 天火冲击环（技能十五·天火坠落）：落点中心闪光 + 径向扩散火环 + 预警脉冲圈。
// 全程序化径向渐变，无贴图。ring_pos / flash_decay 由外部 tween 驱动。

uniform vec4 flash_color : source_color = vec4(1.50, 1.20, 0.70, 1.0);
uniform vec4 ring_color : source_color = vec4(1.20, 0.35, 0.06, 0.90);

uniform float ring_pos : hint_range(0.0, 1.0) = 0.1;      // 环半径进度（tween 驱动）
uniform float ring_width : hint_range(0.005, 0.5) = 0.12;
uniform float flash_decay : hint_range(0.0, 1.0) = 1.0;   // 闪光亮度（tween 驱动）
uniform float flash_size : hint_range(0.05, 1.0) = 0.35;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;          // 预警脉冲圈开关
uniform float intensity : hint_range(0.0, 4.0) = 2.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;

	// 中心爆发闪光
	float flash = clamp(1.0 - r / max(flash_size, 0.001), 0.0, 1.0);
	flash = pow(flash, 2.2) * flash_decay;

	// 径向扩散火环
	float ring = smoothstep(ring_width, 0.0, abs(r - ring_pos)) * (1.0 - smoothstep(0.98, 1.0, r));

	// 施法预警脉冲圈（呼吸闪烁）
	float tele = pulse * smoothstep(0.035, 0.0, abs(r - 0.92)) * (0.65 + 0.35 * sin(TIME * 7.0));

	vec3 col = flash_color.rgb * flash * 1.6 + ring_color.rgb * (ring + tele);
	float a = clamp(flash + ring + tele * 0.9, 0.0, 1.0) * fade;

	ALBEDO = col * intensity;
	ALPHA = a;
}
