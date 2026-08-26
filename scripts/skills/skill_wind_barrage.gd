extends "res://scripts/skills/skill_base.gd"
## Skill 13: Spatial Cleave / 裂空千刃 (弧形风刃·3D多维异面斩击).
## Features 10+ selectable exquisite color presets (绯红炽金, 水墨极白, 极光苍青, 虚空幽紫, 纯金圣辉, 万仞玄冰, 九幽血刹, 赛博霓虹, 幽冥碧火, 暮色落樱).
## Clean, simplified 11-strike 3D multi-planar cutting sequence (非共面立体拓扑切面) intersecting precisely at the target focal point.
## Deeply integrated with PVP / DummyTarget hit stun: interrupts attacks, locks control/actions, and plays hit flinch animations throughout the flurry duration.
## Fully preloaded with GPU material warmup for zero first-cast stutter.

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const CurvedWindBladeShader = preload("res://shaders/curved_wind_blade.gdshader")

var slash_count: int = 11
var flurry_duration: float = 0.72
var strike_distance: float = 3.5
var blade_scale: float = 2.5
var damage_per_hit: float = 12.0
var theme_index: int = 0

const THEME_PRESETS: Array[Dictionary] = [
	{
		"name": "🔴 绯红炽金 (深绯 ➔ 朱炎 ➔ 炽白金芒)",
		"outer": Color(0.92, 0.08, 0.15, 1.0),
		"mid": Color(1.0, 0.38, 0.08, 1.0),
		"core": Color(1.0, 0.96, 0.86, 1.0),
		"fin_outer": Color(1.0, 0.15, 0.22, 1.0),
		"fin_mid": Color(1.0, 0.55, 0.15, 1.0),
		"intensity": 3.3
	},
	{
		"name": "🖤 水墨极白 (墨曜 ➔ 钢灰 ➔ 纯白极光)",
		"outer": Color(0.12, 0.12, 0.15, 1.0),
		"mid": Color(0.48, 0.52, 0.58, 1.0),
		"core": Color(1.20, 1.20, 1.25, 1.0),
		"fin_outer": Color(0.20, 0.20, 0.25, 1.0),
		"fin_mid": Color(0.70, 0.75, 0.80, 1.0),
		"intensity": 3.6
	},
	{
		"name": "💠 极光苍青 (天青 ➔ 翠翡 ➔ 霜白寒光)",
		"outer": Color(0.08, 0.70, 0.95, 1.0),
		"mid": Color(0.12, 0.95, 0.68, 1.0),
		"core": Color(0.90, 1.0, 1.0, 1.0),
		"fin_outer": Color(0.15, 0.85, 1.0, 1.0),
		"fin_mid": Color(0.35, 1.0, 0.85, 1.0),
		"intensity": 3.2
	},
	{
		"name": "🟣 虚空幽紫 (暗渊 ➔ 霓虹紫红 ➔ 幽夜丁香)",
		"outer": Color(0.55, 0.08, 0.85, 1.0),
		"mid": Color(0.88, 0.15, 0.70, 1.0),
		"core": Color(1.0, 0.88, 1.0, 1.0),
		"fin_outer": Color(0.70, 0.15, 1.0, 1.0),
		"fin_mid": Color(1.0, 0.35, 0.85, 1.0),
		"intensity": 3.4
	},
	{
		"name": "🌟 纯金圣辉 (琥珀金 ➔ 阳炎金辉 ➔ 极昼圣白)",
		"outer": Color(0.95, 0.55, 0.05, 1.0),
		"mid": Color(1.0, 0.82, 0.15, 1.0),
		"core": Color(1.0, 1.0, 0.92, 1.0),
		"fin_outer": Color(1.0, 0.70, 0.10, 1.0),
		"fin_mid": Color(1.0, 0.95, 0.30, 1.0),
		"intensity": 3.5
	},
	{
		"name": "❄️ 万仞玄冰 (深海苍蓝 ➔ 冰晶天蓝 ➔ 极寒苍白)",
		"outer": Color(0.08, 0.42, 0.95, 1.0),
		"mid": Color(0.35, 0.82, 1.0, 1.0),
		"core": Color(0.95, 0.98, 1.0, 1.0),
		"fin_outer": Color(0.20, 0.60, 1.0, 1.0),
		"fin_mid": Color(0.60, 0.92, 1.0, 1.0),
		"intensity": 3.2
	},
	{
		"name": "🩸 九幽血刹 (暗血赭褐 ➔ 猩红血月 ➔ 炽红焚心)",
		"outer": Color(0.48, 0.02, 0.06, 1.0),
		"mid": Color(0.98, 0.05, 0.12, 1.0),
		"core": Color(1.0, 0.88, 0.82, 1.0),
		"fin_outer": Color(0.65, 0.04, 0.08, 1.0),
		"fin_mid": Color(1.0, 0.18, 0.22, 1.0),
		"intensity": 3.6
	},
	{
		"name": "⚡ 赛博霓虹 (绝艳品红 ➔ 荧光电青 ➔ 全息璀璨)",
		"outer": Color(1.0, 0.05, 0.55, 1.0),
		"mid": Color(0.05, 0.90, 1.0, 1.0),
		"core": Color(1.0, 1.0, 1.0, 1.0),
		"fin_outer": Color(1.0, 0.20, 0.70, 1.0),
		"fin_mid": Color(0.25, 0.95, 1.0, 1.0),
		"intensity": 3.5
	},
	{
		"name": "🟢 幽冥碧火 (幽魂墨绿 ➔ 荧光毒翠 ➔ 苍白魂火)",
		"outer": Color(0.05, 0.65, 0.35, 1.0),
		"mid": Color(0.30, 1.0, 0.20, 1.0),
		"core": Color(0.90, 1.0, 0.85, 1.0),
		"fin_outer": Color(0.10, 0.85, 0.45, 1.0),
		"fin_mid": Color(0.55, 1.0, 0.35, 1.0),
		"intensity": 3.3
	},
	{
		"name": "🌸 暮色落樱 (暮紫霞光 ➔ 樱粉花瓣 ➔ 珍珠白霞)",
		"outer": Color(0.70, 0.18, 0.52, 1.0),
		"mid": Color(1.0, 0.45, 0.70, 1.0),
		"core": Color(1.0, 0.95, 0.98, 1.0),
		"fin_outer": Color(0.85, 0.25, 0.65, 1.0),
		"fin_mid": Color(1.0, 0.65, 0.82, 1.0),
		"intensity": 3.2
	}
]

static var _cached_blade_mesh: QuadMesh = null
static var _cached_blade_mat: ShaderMaterial = null


func get_id() -> String:
	return "wind_barrage"


func get_name() -> String:
	return "🌪️ 裂空千刃 (弧形风刃·多维异面斩)"


func get_title() -> String:
	return "🌪️ 裂空千刃配置 (3D MULTI-PLANAR CLEAVE)"


func get_params() -> Dictionary:
	return {
		"slash_count": slash_count,
		"flurry_duration": flurry_duration,
		"strike_distance": strike_distance,
		"blade_scale": blade_scale,
		"damage_per_hit": damage_per_hit,
		"theme_index": theme_index
	}


func set_param(key: String, value: Variant) -> void:
	match key:
		"slash_count": slash_count = int(value)
		"flurry_duration": flurry_duration = float(value)
		"strike_distance": strike_distance = float(value)
		"blade_scale": blade_scale = float(value)
		"damage_per_hit": damage_per_hit = float(value)
		"theme_index": theme_index = clampi(int(value), 0, THEME_PRESETS.size() - 1)


func cast(caster: CharacterBody3D, intent_dir: Vector3, vfx_parent: Node, _is_spectator: bool = false) -> Dictionary:
	if caster == null or not is_instance_valid(caster) or not caster.is_inside_tree():
		return {}
	return _execute_cleave_flurry(caster, intent_dir, vfx_parent)


func replay(caster: CharacterBody3D, record: Dictionary, vfx_parent: Node) -> void:
	if caster == null or not is_instance_valid(caster) or not caster.is_inside_tree():
		return
	var dir: Vector3 = record.get("direction", caster.global_transform.basis.z)
	_execute_cleave_flurry(caster, dir, vfx_parent)


func get_replay_hold_time(_record: Dictionary) -> float:
	return flurry_duration + 0.8


func build_config_panel(container: VBoxContainer, on_changed: Callable) -> void:
	# 剑光主题配色下拉选项
	var theme_lbl := Label.new()
	theme_lbl.text = "🎨 剑光灵韵主题配色 (Color Theme Preset):"
	theme_lbl.add_theme_font_size_override("font_size", 12)
	theme_lbl.modulate = Color(1.0, 0.85, 0.5)
	container.add_child(theme_lbl)

	var theme_opt := OptionButton.new()
	for i in range(THEME_PRESETS.size()):
		theme_opt.add_item(THEME_PRESETS[i]["name"], i)
	theme_opt.selected = theme_index
	theme_opt.item_selected.connect(func(idx: int):
		theme_index = idx
		on_changed.call("theme_index", idx)
	)
	container.add_child(theme_opt)

	# 斩击总次数
	var count_lbl := Label.new()
	count_lbl.text = "立体斩击总数 (Total Slashes): %d 刀" % slash_count
	count_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(count_lbl)

	var count_slider := HSlider.new()
	count_slider.min_value = 6
	count_slider.max_value = 24
	count_slider.step = 1
	count_slider.value = slash_count
	count_slider.value_changed.connect(func(v: float):
		slash_count = int(v)
		count_lbl.text = "立体斩击总数 (Total Slashes): %d 刀" % slash_count
		on_changed.call("slash_count", slash_count)
	)
	container.add_child(count_slider)

	# 斩击持续时长
	var dur_lbl := Label.new()
	dur_lbl.text = "狂斩持续时间 (Duration): %.2fs" % flurry_duration
	dur_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(dur_lbl)

	var dur_slider := HSlider.new()
	dur_slider.min_value = 0.35
	dur_slider.max_value = 1.50
	dur_slider.step = 0.05
	dur_slider.value = flurry_duration
	dur_slider.value_changed.connect(func(v: float):
		flurry_duration = v
		dur_lbl.text = "狂斩持续时间 (Duration): %.2fs" % v
		on_changed.call("flurry_duration", v)
	)
	container.add_child(dur_slider)

	# 锁定中心距离
	var dist_lbl := Label.new()
	dist_lbl.text = "斩击锁定中心距 (Distance): %.1fm" % strike_distance
	dist_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(dist_lbl)

	var dist_slider := HSlider.new()
	dist_slider.min_value = 1.5
	dist_slider.max_value = 8.0
	dist_slider.step = 0.5
	dist_slider.value = strike_distance
	dist_slider.value_changed.connect(func(v: float):
		strike_distance = v
		dist_lbl.text = "斩击锁定中心距 (Distance): %.1fm" % v
		on_changed.call("strike_distance", v)
	)
	container.add_child(dist_slider)

	# 风刃尺寸倍率
	var scale_lbl := Label.new()
	scale_lbl.text = "风刃体积倍率 (Blade Scale): %.1fx" % blade_scale
	scale_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(scale_lbl)

	var scale_slider := HSlider.new()
	scale_slider.min_value = 1.2
	scale_slider.max_value = 4.0
	scale_slider.step = 0.1
	scale_slider.value = blade_scale
	scale_slider.value_changed.connect(func(v: float):
		blade_scale = v
		scale_lbl.text = "风刃体积倍率 (Blade Scale): %.1fx" % v
		on_changed.call("blade_scale", v)
	)
	container.add_child(scale_slider)

	# 说明面板
	var tip_panel := PanelContainer.new()
	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.10, 0.08, 0.12, 0.90)
	t_style.set_corner_radius_all(6)
	t_style.set_border_width_all(1)
	t_style.border_color = Color(0.85, 0.65, 1.0, 0.65)
	t_style.set_content_margin_all(8)
	tip_panel.add_theme_stylebox_override("panel", t_style)
	container.add_child(tip_panel)

	var tip_vbox := VBoxContainer.new()
	tip_vbox.add_theme_constant_override("separation", 4)
	tip_panel.add_child(tip_vbox)

	var tip1 := Label.new()
	tip1.text = "🎨 10款经典华丽多层色调：水墨黑白、绯红炽金、万仞玄冰、虚空幽紫、赛博霓虹等"
	tip1.add_theme_font_size_override("font_size", 11)
	tip1.modulate = Color(1.0, 0.90, 0.75)
	tip_vbox.add_child(tip1)

	var tip2 := Label.new()
	tip2.text = "🎯 简化精炼节奏：11 刀严整 3D 异面穿心斩，清晰干脆、层次分明"
	tip2.add_theme_font_size_override("font_size", 11)
	tip2.modulate = Color(0.85, 1.0, 0.90)
	tip_vbox.add_child(tip2)

	var tip3 := Label.new()
	tip3.text = "🛑 深度 PVP 受击硬直：打断攻击、锁定受击状态并禁用反击"
	tip3.add_theme_font_size_override("font_size", 11)
	tip3.modulate = Color(1.0, 0.65, 0.5)
	tip_vbox.add_child(tip3)


func _execute_cleave_flurry(caster: CharacterBody3D, intent_dir: Vector3, parent: Node) -> Dictionary:
	var start_pos := caster.global_position
	var fwd := intent_dir
	fwd.y = 0.0
	if fwd.length_squared() > 0.01:
		fwd = fwd.normalized()
	else:
		fwd = caster.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length_squared() > 0.01 else Vector3.FORWARD

	# Lock precisely onto the target focal point (enemy body center or point in front of caster)
	var focal_point := _find_target_focal_point(caster, start_pos, fwd)

	var raw_ch: Variant = caster.get("character")
	if raw_ch != null and is_instance_valid(raw_ch) and raw_ch.has_method("play"):
		raw_ch.call("play", "attack_heavy", 0.06)

	_ensure_cached_resources()

	var vfx_root := Node3D.new()
	vfx_root.name = "CustomMultiPlanarCleaveVFX"
	parent.add_child(vfx_root)
	vfx_root.global_position = focal_point

	# Definition of distinct, non-coplanar 3D spatial cutting planes passing through the focal center
	var planar_topologies: Array[Vector3] = [
		Vector3(32.0, 42.0, 35.0),
		Vector3(32.0, -42.0, -35.0),
		Vector3(88.0, 10.0, 0.0),
		Vector3(0.0, 85.0, 90.0),
		Vector3(-45.0, 38.0, 60.0),
		Vector3(-45.0, -38.0, -60.0),
		Vector3(55.0, -65.0, 48.0),
		Vector3(68.0, 75.0, -25.0),
		Vector3(45.0, 0.0, 45.0),
		Vector3(0.0, 45.0, 90.0),
		Vector3(-45.0, 45.0, -45.0)
	]

	var cur_theme: Dictionary = THEME_PRESETS[clampi(theme_index, 0, THEME_PRESETS.size() - 1)]

	var total_cuts := maxi(slash_count, planar_topologies.size())
	var body_cuts := total_cuts - 3
	var body_duration := flurry_duration * 0.78
	var time_step := body_duration / float(maxi(body_cuts, 1))

	for i in range(total_cuts):
		var cut_time := 0.0
		var is_finisher := (i >= total_cuts - 3)
		if is_finisher:
			cut_time = body_duration + (float(i - (total_cuts - 3)) * 0.02)
		else:
			cut_time = float(i) * time_step

		var plane_euler: Vector3 = planar_topologies[i % planar_topologies.size()]

		var tw := vfx_root.create_tween()
		tw.tween_interval(cut_time)
		tw.tween_callback(func():
			if is_instance_valid(caster) and is_instance_valid(vfx_root):
				_spawn_3d_planar_slash(focal_point, fwd, plane_euler, is_finisher, cur_theme, vfx_root)
				_apply_target_hitstun(caster, focal_point, is_finisher)
		)

	# Clean up VFX root container
	var cleanup_tw := vfx_root.create_tween()
	cleanup_tw.tween_interval(flurry_duration + 0.5)
	cleanup_tw.tween_callback(vfx_root.queue_free)

	return {
		"success": true,
		"skill_id": get_id(),
		"from_pos": start_pos,
		"target_pos": focal_point,
		"direction": fwd,
		"slash_count": slash_count,
		"duration": flurry_duration,
		"theme_index": theme_index
	}


## Finds the target's exact body center point (focal point).
func _find_target_focal_point(caster: CharacterBody3D, start_pos: Vector3, forward: Vector3) -> Vector3:
	var default_focal := start_pos + forward * strike_distance + Vector3.UP * 1.1

	var tree := caster.get_tree()
	if tree == null:
		return default_focal

	var candidates: Array[Node] = tree.get_nodes_in_group("characters")
	if candidates.is_empty():
		var scene_root := tree.current_scene
		if scene_root != null:
			for ch in scene_root.find_children("*", "CharacterBody3D", true, false):
				candidates.append(ch)
			for ch in scene_root.find_children("*", "DummyTarget", true, false):
				candidates.append(ch)

	var closest_target: Node = null
	var closest_dist := 999.0

	for b in candidates:
		if b == null or not is_instance_valid(b) or b == caster or b.name == "Ground":
			continue
		if not (b is Node3D):
			continue
		var n3d := b as Node3D
		var to_b := n3d.global_position - start_pos
		var dist := to_b.length()
		if dist <= strike_distance + 2.5:
			var dot := forward.dot(to_b.normalized())
			if dot > 0.40 and dist < closest_dist:
				closest_dist = dist
				closest_target = b

	if closest_target != null:
		return (closest_target as Node3D).global_position + Vector3.UP * 1.05

	return default_focal


## Spawns one clean curved crescent slash oriented on its own unique 3D spatial cutting plane passing through the focal center.
func _spawn_3d_planar_slash(focal_pos: Vector3, forward: Vector3, euler_deg: Vector3, is_finisher: bool, theme: Dictionary, parent: Node) -> void:
	AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg", 1.30 + randf_range(-0.08, 0.12))

	var slash_pivot := Node3D.new()
	parent.add_child(slash_pivot)
	slash_pivot.global_position = focal_pos

	# Align base forward vector
	var fwd_norm := forward.normalized()
	var temp_up := Vector3.UP if absf(fwd_norm.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var right := temp_up.cross(fwd_norm).normalized()
	var actual_up := fwd_norm.cross(right).normalized()
	var base_basis := Basis(right, actual_up, fwd_norm)

	# Apply full 3D Euler angles (Pitch, Yaw, Roll) to define the unique 3D non-coplanar cutting plane
	var rot_basis := Basis.from_euler(Vector3(deg_to_rad(euler_deg.x), deg_to_rad(euler_deg.y), deg_to_rad(euler_deg.z)))
	slash_pivot.transform.basis = (base_basis * rot_basis).orthonormalized()

	var slash_mesh := MeshInstance3D.new()
	slash_mesh.mesh = _cached_blade_mesh
	slash_mesh.position = Vector3.ZERO

	# Scale sizing: finisher is larger and more brilliant
	var cur_scale := blade_scale * (1.65 if is_finisher else randf_range(0.96, 1.14))
	var mesh_sz := cur_scale * 2.2
	slash_mesh.scale = Vector3(mesh_sz / 3.8, mesh_sz / 3.8, 1.0)
	slash_pivot.add_child(slash_mesh)

	var mat := ShaderMaterial.new()
	mat.shader = CurvedWindBladeShader

	var out_c: Color = theme["fin_outer"] if is_finisher else theme["outer"]
	var mid_c: Color = theme["fin_mid"] if is_finisher else theme["mid"]
	var core_c: Color = theme["core"]
	var base_int: float = float(theme.get("intensity", 3.2))

	mat.set_shader_parameter("outer_color", out_c)
	mat.set_shader_parameter("mid_color", mid_c)
	mat.set_shader_parameter("core_color", core_c)
	mat.set_shader_parameter("intensity", base_int * (1.25 if is_finisher else 1.0))
	mat.set_shader_parameter("fade", 1.0)
	mat.set_shader_parameter("dissolve", 0.0)
	mat.set_shader_parameter("contrast_boost", 2.0)
	VfxTextures.bind(mat, "blade_tex", VfxTextures.CURVED_WIND_SLASH, "", 1.0)
	slash_mesh.material_override = mat

	var slash_life := 0.20 if not is_finisher else 0.30

	# Sharp snap-open slicing in place on its unique 3D plane, luminous glint, and clean dissolve evaporation
	var tw := slash_pivot.create_tween()
	tw.set_parallel(true)
	# Snap open expansion directly centered on focal point
	tw.tween_property(slash_pivot, "scale", Vector3(1.12, 1.12, 1.12), 0.035).from(Vector3(0.25, 0.25, 0.25)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Edge dissolve erosion
	tw.tween_property(mat, "shader_parameter/dissolve", 0.95, slash_life * 0.60).set_delay(slash_life * 0.40).set_ease(Tween.EASE_IN)
	# Alpha fade
	tw.tween_property(mat, "shader_parameter/fade", 0.0, slash_life * 0.45).set_delay(slash_life * 0.55).set_ease(Tween.EASE_IN)

	tw.chain().tween_callback(slash_pivot.queue_free)


## Applies authentic PVP hit stun and control interruption to targets at the focal point.
func _apply_target_hitstun(caster: CharacterBody3D, focal_pos: Vector3, is_finisher: bool) -> void:
	if caster == null or not is_instance_valid(caster) or not caster.is_inside_tree():
		return
	var tree := caster.get_tree()
	if tree == null:
		return

	var candidates: Array[Node] = tree.get_nodes_in_group("characters")
	if candidates.is_empty():
		var scene_root := tree.current_scene
		if scene_root != null:
			for ch in scene_root.find_children("*", "CharacterBody3D", true, false):
				candidates.append(ch)
			for ch in scene_root.find_children("*", "DummyTarget", true, false):
				candidates.append(ch)

	for b in candidates:
		if b == null or not is_instance_valid(b) or b == caster or b.name == "Ground":
			continue

		var b_pos := (b as Node3D).global_position if (b is Node3D) else Vector3.ZERO
		var dist := (b_pos - focal_pos).length()
		# Within tight focal contact range
		if dist > 2.2:
			continue

		var hit_pos := focal_pos
		var swing_dir := (b_pos - caster.global_position).normalized()
		var dmg := damage_per_hit * (2.0 if is_finisher else 1.0)

		# 1. Standard take_hit for DummyTarget (PVP sandbox & VFX lab dummy)
		# Triggers dummy's CLIP_HIT_BODY, damage numbers, HP reduction, and Reaction.STAGGER control lock
		if b.has_method("take_hit"):
			b.call("take_hit", hit_pos, dmg, swing_dir)

		# 2. PlayerController PVP Hit Stun / Attack Interruption:
		# Calls apply_hit_reaction: resets weapon graph, interrupts attack, sets State.HIT_STUN, locks controls
		if b.has_method("apply_hit_reaction"):
			b.call("apply_hit_reaction", "hit_chest", 0.45)
		elif b is CharacterBody3D:
			var cb := b as CharacterBody3D
			var raw_ch: Variant = cb.get("character")
			if raw_ch != null and is_instance_valid(raw_ch) and raw_ch.has_method("play"):
				raw_ch.call("play", "hit_knockback" if is_finisher else "hit_reaction", 0.05)


static func _ensure_cached_resources() -> void:
	if _cached_blade_mesh == null:
		_cached_blade_mesh = QuadMesh.new()
		_cached_blade_mesh.size = Vector2(3.8, 3.8)

	if _cached_blade_mat == null:
		_cached_blade_mat = ShaderMaterial.new()
		_cached_blade_mat.shader = CurvedWindBladeShader
		_cached_blade_mat.set_shader_parameter("outer_color", Color(0.92, 0.08, 0.15, 1.0))
		_cached_blade_mat.set_shader_parameter("mid_color", Color(1.0, 0.38, 0.08, 1.0))
		_cached_blade_mat.set_shader_parameter("core_color", Color(1.0, 0.96, 0.86, 1.0))
		_cached_blade_mat.set_shader_parameter("intensity", 3.3)
		_cached_blade_mat.set_shader_parameter("contrast_boost", 2.0)
		VfxTextures.bind(_cached_blade_mat, "blade_tex", VfxTextures.CURVED_WIND_SLASH, "", 1.0)


func preload_assets() -> void:
	AudioManagerScript.preload_sounds([
		"res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg"
	])
	_ensure_cached_resources()
	VfxTextures.get_tex(VfxTextures.CURVED_WIND_SLASH)


func get_warmup_materials() -> Array:
	_ensure_cached_resources()

	var m_blade := ShaderMaterial.new()
	m_blade.shader = CurvedWindBladeShader
	VfxTextures.bind(m_blade, "blade_tex", VfxTextures.CURVED_WIND_SLASH, "", 1.0)

	return [m_blade, _cached_blade_mat]
