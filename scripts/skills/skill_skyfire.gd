extends "res://scripts/skills/skill_base.gd"
## Skill 15: Skyfire Fall / 天火坠落 (九霄焚陨·连珠天陨).
## 多颗炽热火球轮流自高空竖直坠落，砸中地面爆出火光冲击环与余烬焦痕。
## 碎石为程序化生成的不规则岩石网格（非方块、非纯色粒子），挂 RigidBody3D 真实物理：
## 重力坠落、弹跳、翻滚、余烬冷却后消散。全程零贴图，火焰全部由程序化噪声 shader 驱动。

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const SkyfireMeteorShader = preload("res://shaders/skyfire_meteor.gdshader")
const SkyfireFlameConeShader = preload("res://shaders/skyfire_flame_cone.gdshader")
const SkyfireFlameSheetShader = preload("res://shaders/skyfire_flame_sheet.gdshader")
const SkyfireImpactRingShader = preload("res://shaders/skyfire_impact_ring.gdshader")
const SkyfireScorchShader = preload("res://shaders/skyfire_scorch.gdshader")
const SkyfireRockShader = preload("res://shaders/skyfire_rock.gdshader")

var meteor_count: int = 7
var drop_interval: float = 0.34
var strike_radius: float = 4.5
var strike_distance: float = 8.0
var cast_range: float = 18.0
var meteor_scale: float = 1.0
var damage_per_meteor: float = 22.0
var theme_index: int = 0

## Color Hierarchy (60-30-10):
## 60% 暗红烟羽/焰体底色 ➔ 30% 橙红炽黄翻涌 ➔ 10% 白炽核心与火星高光
const THEME_PRESETS: Array[Dictionary] = [
	{
		"name": "☄️ 陨火燎原 (暗红烟羽 60% ➔ 橙红炽焰 30% ➔ 白炽陨心 10%)",
		"core": Color(1.60, 1.42, 1.05, 1.0),
		"mid": Color(1.30, 0.72, 0.16, 0.95),
		"edge": Color(0.95, 0.26, 0.04, 0.90),
		"soot": Color(0.18, 0.04, 0.02, 0.95),
		"flash": Color(1.50, 1.20, 0.70, 1.0),
		"ring": Color(1.20, 0.35, 0.06, 0.90),
		"ember": Color(1.30, 0.45, 0.08, 1.0),
		"scorch": Color(0.030, 0.020, 0.015, 0.85),
		"light": Color(1.0, 0.45, 0.15),
		"stone_dark": Color(0.11, 0.10, 0.11, 1.0),
		"stone_light": Color(0.33, 0.30, 0.27, 1.0),
		"stone_accent": Color(0.20, 0.17, 0.15, 1.0)
	},
	{
		"name": "👻 幽冥青焰 (墨渊青烟 60% ➔ 碧火青焰 30% ➔ 冥白炽心 10%)",
		"core": Color(1.30, 1.50, 1.40, 1.0),
		"mid": Color(0.20, 1.10, 0.90, 0.95),
		"edge": Color(0.05, 0.50, 0.60, 0.90),
		"soot": Color(0.01, 0.06, 0.08, 0.95),
		"flash": Color(1.00, 1.40, 1.30, 1.0),
		"ring": Color(0.20, 0.90, 0.80, 0.90),
		"ember": Color(0.20, 1.10, 0.85, 1.0),
		"scorch": Color(0.010, 0.030, 0.035, 0.85),
		"light": Color(0.25, 0.85, 0.75),
		"stone_dark": Color(0.08, 0.10, 0.12, 1.0),
		"stone_light": Color(0.25, 0.32, 0.35, 1.0),
		"stone_accent": Color(0.14, 0.18, 0.20, 1.0)
	},
	{
		"name": "🌅 赤金圣焰 (玄烬金烟 60% ➔ 赤金流焰 30% ➔ 圣白陨心 10%)",
		"core": Color(1.70, 1.50, 1.10, 1.0),
		"mid": Color(1.40, 1.00, 0.30, 0.95),
		"edge": Color(1.00, 0.55, 0.10, 0.90),
		"soot": Color(0.15, 0.09, 0.02, 0.95),
		"flash": Color(1.60, 1.35, 0.90, 1.0),
		"ring": Color(1.30, 0.80, 0.20, 0.90),
		"ember": Color(1.40, 0.90, 0.20, 1.0),
		"scorch": Color(0.050, 0.035, 0.020, 0.85),
		"light": Color(1.0, 0.70, 0.25),
		"stone_dark": Color(0.12, 0.11, 0.09, 1.0),
		"stone_light": Color(0.36, 0.32, 0.25, 1.0),
		"stone_accent": Color(0.22, 0.19, 0.14, 1.0)
	}
]

## 静态资源缓存：基础网格、岩石变体、物理材质、预热材质
static var _quad_mesh: QuadMesh = null
static var _plane_mesh: PlaneMesh = null
static var _sphere_mesh: SphereMesh = null
static var _cone_mesh: CylinderMesh = null
static var _rock_meshes: Array[ArrayMesh] = []
static var _rock_phys_mat: PhysicsMaterial = null
static var _warmup_mats: Array = []


func get_id() -> String:
	return "skyfire"


func get_name() -> String:
	return "☄️ 天火坠落 (九霄焚陨·连珠天陨)"


func get_title() -> String:
	return "☄️ 天火坠落配置 (SKYFIRE METEOR FALL)"


func get_params() -> Dictionary:
	return {
		"meteor_count": meteor_count,
		"drop_interval": drop_interval,
		"strike_radius": strike_radius,
		"strike_distance": strike_distance,
		"meteor_scale": meteor_scale,
		"damage_per_meteor": damage_per_meteor,
		"theme_index": theme_index
	}


func set_param(key: String, value: Variant) -> void:
	match key:
		"meteor_count": meteor_count = clampi(int(value), 1, 24)
		"drop_interval": drop_interval = clampf(float(value), 0.08, 1.5)
		"strike_radius": strike_radius = clampf(float(value), 1.5, 12.0)
		"strike_distance": strike_distance = clampf(float(value), 2.0, 15.0)
		"meteor_scale": meteor_scale = clampf(float(value), 0.5, 3.0)
		"damage_per_meteor": damage_per_meteor = clampf(float(value), 2.0, 120.0)
		"theme_index": theme_index = clampi(int(value), 0, THEME_PRESETS.size() - 1)


func cast(caster: CharacterBody3D, intent_dir: Vector3, vfx_parent: Node, _is_spectator: bool = false) -> Dictionary:
	if caster == null or not is_instance_valid(caster):
		return {}
	var target_pos := _calculate_target_position(caster, intent_dir)
	return _execute_skyfire(caster, target_pos, vfx_parent)


## Aim-support: allows SkillAim ground targeting
func cast_at(caster: CharacterBody3D, target_pos: Vector3, vfx_parent: Node, _is_spectator: bool = false) -> Dictionary:
	if caster == null or not is_instance_valid(caster):
		return {}
	return _execute_skyfire(caster, target_pos, vfx_parent)


func replay(caster: CharacterBody3D, record: Dictionary, vfx_parent: Node) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	var target_pos: Vector3 = record.get("target_pos", caster.global_position + (caster.global_transform.basis.z if caster.is_inside_tree() else Vector3.FORWARD) * strike_distance)
	theme_index = clampi(int(record.get("theme_index", theme_index)), 0, THEME_PRESETS.size() - 1)
	_execute_skyfire(caster, target_pos, vfx_parent)


func get_replay_hold_time(_record: Dictionary) -> float:
	return float(meteor_count) * drop_interval + 1.6


func preload_assets() -> void:
	_ensure_cached_resources()
	AudioManagerScript.preload_sounds([
		"res://assets/voice/RPGsounds_Kenney/OGG/knifeSlice.ogg",
		"res://assets/voice/RPGsounds_Kenney/OGG/knifeSlice2.ogg",
		"res://assets/voice/RPGsounds_Kenney/OGG/chop.ogg",
		"res://assets/voice/RPGsounds_Kenney/OGG/metalPot1.ogg",
		"res://assets/voice/RPGsounds_Kenney/OGG/metalPot2.ogg",
		"res://assets/voice/RPGsounds_Kenney/OGG/metalPot3.ogg"
	])


func get_warmup_materials() -> Array:
	_ensure_cached_resources()
	return _warmup_mats.duplicate()


func dispel_actor(_actor: CharacterBody3D) -> void:
	pass


func reset_state() -> void:
	pass


func build_config_panel(container: VBoxContainer, on_changed: Callable) -> void:
	# 配色主题
	var theme_lbl := Label.new()
	theme_lbl.text = "🎨 天火灵焰配色 (Skyfire Theme Preset):"
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

	# 陨火数量
	var count_lbl := Label.new()
	count_lbl.text = "连珠陨火数量 (Meteor Count): %d 颗" % meteor_count
	count_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(count_lbl)

	var count_slider := HSlider.new()
	count_slider.min_value = 1
	count_slider.max_value = 24
	count_slider.step = 1
	count_slider.value = meteor_count
	count_slider.value_changed.connect(func(v: float):
		meteor_count = int(v)
		count_lbl.text = "连珠陨火数量 (Meteor Count): %d 颗" % meteor_count
		on_changed.call("meteor_count", meteor_count)
	)
	container.add_child(count_slider)

	# 轮流坠落间隔
	var itv_lbl := Label.new()
	itv_lbl.text = "轮流坠落间隔 (Drop Interval): %.2fs" % drop_interval
	itv_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(itv_lbl)

	var itv_slider := HSlider.new()
	itv_slider.min_value = 0.08
	itv_slider.max_value = 1.5
	itv_slider.step = 0.02
	itv_slider.value = drop_interval
	itv_slider.value_changed.connect(func(v: float):
		drop_interval = v
		itv_lbl.text = "轮流坠落间隔 (Drop Interval): %.2fs" % v
		on_changed.call("drop_interval", v)
	)
	container.add_child(itv_slider)

	# 落点散布半径
	var rad_lbl := Label.new()
	rad_lbl.text = "落点散布半径 (Strike Radius): %.1fm" % strike_radius
	rad_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(rad_lbl)

	var rad_slider := HSlider.new()
	rad_slider.min_value = 1.5
	rad_slider.max_value = 12.0
	rad_slider.step = 0.5
	rad_slider.value = strike_radius
	rad_slider.value_changed.connect(func(v: float):
		strike_radius = v
		rad_lbl.text = "落点散布半径 (Strike Radius): %.1fm" % v
		on_changed.call("strike_radius", v)
	)
	container.add_child(rad_slider)

	# 施法落点距离
	var dist_lbl := Label.new()
	dist_lbl.text = "施法落点距离 (Cast Distance): %.1fm" % strike_distance
	dist_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(dist_lbl)

	var dist_slider := HSlider.new()
	dist_slider.min_value = 2.0
	dist_slider.max_value = 15.0
	dist_slider.step = 0.5
	dist_slider.value = strike_distance
	dist_slider.value_changed.connect(func(v: float):
		strike_distance = v
		dist_lbl.text = "施法落点距离 (Cast Distance): %.1fm" % v
		on_changed.call("strike_distance", v)
	)
	container.add_child(dist_slider)

	# 陨火体型缩放
	var scale_lbl := Label.new()
	scale_lbl.text = "陨火体型缩放 (Meteor Scale): %.2fx" % meteor_scale
	scale_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(scale_lbl)

	var scale_slider := HSlider.new()
	scale_slider.min_value = 0.5
	scale_slider.max_value = 3.0
	scale_slider.step = 0.05
	scale_slider.value = meteor_scale
	scale_slider.value_changed.connect(func(v: float):
		meteor_scale = v
		scale_lbl.text = "陨火体型缩放 (Meteor Scale): %.2fx" % v
		on_changed.call("meteor_scale", v)
	)
	container.add_child(scale_slider)

	# 单颗伤害
	var dmg_lbl := Label.new()
	dmg_lbl.text = "单颗陨火伤害 (Damage per Meteor): %d" % int(damage_per_meteor)
	dmg_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(dmg_lbl)

	var dmg_slider := HSlider.new()
	dmg_slider.min_value = 2.0
	dmg_slider.max_value = 120.0
	dmg_slider.step = 1.0
	dmg_slider.value = damage_per_meteor
	dmg_slider.value_changed.connect(func(v: float):
		damage_per_meteor = v
		dmg_lbl.text = "单颗陨火伤害 (Damage per Meteor): %d" % int(v)
		on_changed.call("damage_per_meteor", v)
	)
	container.add_child(dmg_slider)

	# 提示面板
	var tip_panel := PanelContainer.new()
	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.10, 0.05, 0.03, 0.90)
	t_style.set_corner_radius_all(6)
	t_style.set_border_width_all(1)
	t_style.border_color = Color(1.0, 0.55, 0.25, 0.65)
	t_style.set_content_margin_all(8)
	tip_panel.add_theme_stylebox_override("panel", t_style)
	container.add_child(tip_panel)

	var tip_vbox := VBoxContainer.new()
	tip_vbox.add_theme_constant_override("separation", 4)
	tip_panel.add_child(tip_vbox)

	var tip1 := Label.new()
	tip1.text = "☄️ 全程序化火焰：白炽陨心+翻涌焰壳+下坠尾焰，全程零贴图，支持 SkillAim 自由选点"
	tip1.add_theme_font_size_override("font_size", 11)
	tip1.modulate = Color(1.0, 0.80, 0.60)
	tip_vbox.add_child(tip1)

	var tip2 := Label.new()
	tip2.text = "🪨 拟真碎石：程序化不规则岩块挂真实刚体物理，弹跳翻滚，灼热余烬渐冷后消散"
	tip2.add_theme_font_size_override("font_size", 11)
	tip2.modulate = Color(0.90, 0.85, 0.80)
	tip_vbox.add_child(tip2)

	var tip3 := Label.new()
	tip3.text = "💥 末颗终结陨体积 2.4 倍：更大爆炸、更多碎石与更高灼烧范围"
	tip3.add_theme_font_size_override("font_size", 11)
	tip3.modulate = Color(1.0, 0.65, 0.45)
	tip_vbox.add_child(tip3)


# ============================================================
# 主执行流程
# ============================================================

func _execute_skyfire(caster: CharacterBody3D, target_pos: Vector3, parent: Node) -> Dictionary:
	_ensure_cached_resources()

	# 施法者重击前摇动画
	var raw_ch: Variant = caster.get("character")
	if raw_ch != null and is_instance_valid(raw_ch) and raw_ch.has_method("play"):
		raw_ch.call("play", "attack_heavy", 0.08)

	var theme: Dictionary = THEME_PRESETS[theme_index]
	var root := Node3D.new()
	root.name = "SkyfireVFX_%d" % Time.get_ticks_msec()
	parent.add_child(root)
	root.global_position = target_pos

	# 落点预警脉冲圈（覆盖整轮陨落区域）
	_spawn_telegraph_ring(root, target_pos, strike_radius * 2.3, theme)

	var windup_time := 0.30
	var total_barrage := windup_time + float(meteor_count) * drop_interval + 0.4

	for i in range(meteor_count):
		var is_finisher := (i == meteor_count - 1)
		var delay := windup_time + float(i) * drop_interval + randf_range(0.0, drop_interval * 0.25)
		var t_tween := root.create_tween()
		t_tween.tween_interval(delay)
		t_tween.tween_callback(func():
			if root == null or not is_instance_valid(root):
				return
			_spawn_meteor(root, caster, target_pos, theme, is_finisher)
		)

	# 根节点清理（碎石自身约 4.5s 消散，留足余量）
	var clean_tw := root.create_tween()
	clean_tw.tween_interval(total_barrage + 6.0)
	clean_tw.tween_callback(func():
		if root != null and is_instance_valid(root):
			root.queue_free()
	)

	return {
		"target_pos": target_pos,
		"theme_index": theme_index,
		"meteor_count": meteor_count
	}


func _calculate_target_position(caster: CharacterBody3D, intent_dir: Vector3) -> Vector3:
	var start_pos := caster.global_position if caster.is_inside_tree() else caster.position
	var fwd := intent_dir
	fwd.y = 0.0
	if fwd.length_squared() > 0.01:
		fwd = fwd.normalized()
	else:
		var basis_z := caster.global_transform.basis.z if caster.is_inside_tree() else caster.transform.basis.z
		basis_z.y = 0.0
		fwd = basis_z.normalized() if basis_z.length_squared() > 0.01 else Vector3.FORWARD

	# 正前方索敌：优先锁定射程内最近的敌人或木桩
	var tree := caster.get_tree() if caster.is_inside_tree() else null
	if tree != null:
		var scene_root := tree.current_scene
		if scene_root != null:
			var closest_target: Node3D = null
			var closest_dist := 999.0
			var candidates: Array = []
			for ch in scene_root.find_children("*", "CharacterBody3D", true, false):
				candidates.append(ch)
			for ch in scene_root.find_children("*", "DummyTarget", true, false):
				candidates.append(ch)

			for b in candidates:
				if b == null or not is_instance_valid(b) or b == caster or b.name == "Ground":
					continue
				if not (b is Node3D):
					continue
				var n3d := b as Node3D
				var to_b := n3d.global_position - start_pos
				var dist := to_b.length()
				if dist <= strike_distance + strike_radius + 2.0:
					var dot := fwd.dot(to_b.normalized())
					if dot > 0.35 and dist < closest_dist:
						closest_dist = dist
						closest_target = n3d

			if closest_target != null:
				var tpos := closest_target.global_position
				tpos.y = start_pos.y
				return tpos

	return start_pos + fwd * strike_distance


# ============================================================
# 陨火流星：竖直坠落
# ============================================================

func _spawn_meteor(root: Node3D, caster: CharacterBody3D, target_center: Vector3, theme: Dictionary, is_finisher: bool) -> void:
	if root == null or not is_instance_valid(root):
		return

	var scale_f: float = meteor_scale * (2.4 if is_finisher else randf_range(0.9, 1.2))

	# 落点：终结陨正中目标，其余在散布半径内随机
	var angle := randf_range(0.0, TAU)
	var r := 0.0 if is_finisher else sqrt(randf()) * strike_radius
	var land_pos := target_center + Vector3(cos(angle) * r, 0.0, sin(angle) * r)

	var spawn_height := 26.0
	var meteor_node := Node3D.new()
	root.add_child(meteor_node)
	meteor_node.global_position = land_pos + Vector3(0.0, spawn_height, 0.0)

	# --- 1. 白炽熔岩实心球核（3D 饱满球体质感 + 熔岩裂隙与玄岩外壳） ---
	var core := MeshInstance3D.new()
	core.mesh = _sphere_mesh
	core.scale = Vector3.ONE * (0.65 * scale_f)
	core.material_override = _make_meteor_mat(theme, 2.2, 4.0, 0.90, 0.40)
	meteor_node.add_child(core)

	# --- 2. 翻涌等离子外层焰冠球（菲涅尔高温等离子边缘） ---
	var shell := MeshInstance3D.new()
	shell.mesh = _sphere_mesh
	shell.scale = Vector3.ONE * (0.95 * scale_f)
	shell.material_override = _make_meteor_mat(theme, 1.4, 2.4, 1.6, 0.10)
	meteor_node.add_child(shell)

	# --- 3. 3D 无缝环向锥形尾焰（360度全向立体圆柱/锥体射流，彻底消除2D十字片穿帮） ---
	var trail_root := Node3D.new()
	meteor_node.add_child(trail_root)

	# 内层白炽高速等离子射流锥
	var inner_cone := MeshInstance3D.new()
	inner_cone.mesh = _cone_mesh
	var inner_len := 4.4 * scale_f
	var inner_r := 0.55 * scale_f
	inner_cone.scale = Vector3(inner_r * 2.0, inner_len, inner_r * 2.0)
	inner_cone.position = Vector3(0.0, inner_len * 0.5, 0.0)
	inner_cone.material_override = _make_flame_cone_mat(theme, 2.6, 3.0, 3.6, 5.2, 1.3)
	trail_root.add_child(inner_cone)

	# 外层翻涌气浪拖尾锥（更长、更宽、带螺旋旋涡侵蚀）
	var outer_cone := MeshInstance3D.new()
	outer_cone.mesh = _cone_mesh
	var outer_len := 6.2 * scale_f
	var outer_r := 0.92 * scale_f
	outer_cone.scale = Vector3(outer_r * 2.0, outer_len, outer_r * 2.0)
	outer_cone.position = Vector3(0.0, outer_len * 0.5, 0.0)
	outer_cone.material_override = _make_flame_cone_mat(theme, 1.6, 2.0, 2.6, 3.8, 1.7)
	trail_root.add_child(outer_cone)

	# --- 4. 灼橙点光源（闪烁） ---
	var light := OmniLight3D.new()
	light.light_color = theme["light"]
	light.light_energy = 5.5 * scale_f
	light.omni_range = 14.0 * scale_f
	light.position = Vector3(0.0, 0.2, 0.0)
	meteor_node.add_child(light)
	_flicker_light(light, 5.5 * scale_f)

	# 音效：坠落的撕裂风啸
	AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/knifeSlice2.ogg", randf_range(0.55, 0.70))
	if is_finisher:
		AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/knifeSlice.ogg", 0.48)

	# 竖直坠落（重力加速感：EASE_IN + QUAD）
	var fall_time := maxf(spawn_height / (42.0 if is_finisher else randf_range(34.0, 40.0)), 0.40)
	var tw := meteor_node.create_tween()
	tw.tween_property(meteor_node, "global_position", land_pos, fall_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		if meteor_node == null or not is_instance_valid(meteor_node):
			return
		_on_meteor_impact(root, caster, meteor_node, trail_root, land_pos, scale_f, theme, is_finisher)
	)


func _on_meteor_impact(root: Node3D, caster: CharacterBody3D, meteor_node: Node3D, trail_root: Node3D, hit_pos: Vector3, scale_f: float, theme: Dictionary, is_finisher: bool) -> void:
	if root == null or not is_instance_valid(root) or meteor_node == null or not is_instance_valid(meteor_node):
		return

	# 移除坠落尾焰
	if trail_root != null and is_instance_valid(trail_root):
		trail_root.queue_free()

	# 音效：深沉轰爆
	if is_finisher:
		AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/metalPot3.ogg", 0.85)
		AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/metalPot2.ogg", 1.0)
		AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/chop.ogg", 0.80)
	else:
		var boom := ["res://assets/voice/RPGsounds_Kenney/OGG/metalPot1.ogg", "res://assets/voice/RPGsounds_Kenney/OGG/metalPot2.ogg", "res://assets/voice/RPGsounds_Kenney/OGG/chop.ogg"]
		AudioManagerScript.play_voice_file(boom[randi() % boom.size()], randf_range(0.80, 1.05))

	# --- 1. 落点闪光 + 扩散火环 ---
	_spawn_impact_flash_and_ring(root, hit_pos, scale_f, theme, is_finisher)

	# --- 2. 余烬焦痕（中心炽热渐冷） ---
	_spawn_scorch(root, hit_pos, scale_f, theme, is_finisher)

	# --- 3. 落地燃烧火舌（3D 向上喷涌火柱与火穹） ---
	_spawn_ground_flames(root, hit_pos, scale_f, theme, is_finisher)

	# --- 4. 冲击闪光灯 ---
	_spawn_impact_light(root, hit_pos, scale_f, theme, is_finisher)

	# --- 5. 拟真碎石飞溅（程序化玄武岩纹理 + 熔岩裂隙冷却物理刚体） ---
	_spawn_rock_debris(root, hit_pos, scale_f, theme, is_finisher)

	# --- 6. 范围伤害与硬直 ---
	_resolve_meteor_damage(caster, hit_pos, is_finisher)

	# 陨火本体迅速收缩湮灭
	var vanish_tw := meteor_node.create_tween()
	vanish_tw.set_parallel(true)
	vanish_tw.tween_property(meteor_node, "scale", Vector3(0.05, 0.05, 0.05), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	vanish_tw.chain().tween_callback(meteor_node.queue_free)


# ============================================================
# 落地特效组件
# ============================================================

func _spawn_telegraph_ring(root: Node3D, pos: Vector3, size: float, theme: Dictionary) -> void:
	var ring := MeshInstance3D.new()
	ring.mesh = _plane_mesh
	ring.scale = Vector3(size, 1.0, size)
	root.add_child(ring)
	ring.global_position = pos + Vector3(0.0, 0.04, 0.0)

	var mat := ShaderMaterial.new()
	mat.shader = SkyfireImpactRingShader
	mat.set_shader_parameter("flash_color", theme["flash"])
	mat.set_shader_parameter("ring_color", theme["ring"])
	mat.set_shader_parameter("ring_pos", 0.92)
	mat.set_shader_parameter("ring_width", 0.035)
	mat.set_shader_parameter("flash_decay", 0.0)
	mat.set_shader_parameter("pulse", 1.0)
	mat.set_shader_parameter("intensity", 1.6)
	mat.set_shader_parameter("fade", 0.0)
	ring.material_override = mat

	var tw := ring.create_tween()
	tw.tween_property(mat, "shader_parameter/fade", 1.0, 0.22)
	tw.tween_interval(float(meteor_count) * drop_interval + 0.15)
	tw.tween_property(mat, "shader_parameter/fade", 0.0, 0.35)
	tw.tween_callback(ring.queue_free)


func _spawn_impact_flash_and_ring(root: Node3D, pos: Vector3, scale_f: float, theme: Dictionary, is_finisher: bool) -> void:
	# 中心爆发闪光 + 扩散火环（同一张面片）
	var ring := MeshInstance3D.new()
	ring.mesh = _plane_mesh
	var sz := (6.5 if is_finisher else randf_range(3.2, 4.2)) * scale_f
	ring.scale = Vector3(sz, 1.0, sz)
	root.add_child(ring)
	ring.global_position = pos + Vector3(0.0, 0.05, 0.0)

	var mat := ShaderMaterial.new()
	mat.shader = SkyfireImpactRingShader
	mat.set_shader_parameter("flash_color", theme["flash"])
	mat.set_shader_parameter("ring_color", theme["ring"])
	mat.set_shader_parameter("ring_pos", 0.10)
	mat.set_shader_parameter("ring_width", 0.16)
	mat.set_shader_parameter("flash_decay", 1.0)
	mat.set_shader_parameter("flash_size", 0.34)
	mat.set_shader_parameter("pulse", 0.0)
	mat.set_shader_parameter("intensity", 3.0 if is_finisher else 2.0)
	mat.set_shader_parameter("fade", 1.0)
	ring.material_override = mat

	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mat, "shader_parameter/ring_pos", 0.96, 0.42).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(mat, "shader_parameter/flash_decay", 0.0, 0.20).set_ease(Tween.EASE_IN)
	tw.tween_property(mat, "shader_parameter/fade", 0.0, 0.42).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(ring.queue_free)


func _spawn_scorch(root: Node3D, pos: Vector3, scale_f: float, theme: Dictionary, is_finisher: bool) -> void:
	var scorch := MeshInstance3D.new()
	scorch.mesh = _plane_mesh
	var sz := (4.8 if is_finisher else randf_range(2.2, 3.0)) * scale_f
	scorch.scale = Vector3(sz, 1.0, sz)
	root.add_child(scorch)
	scorch.global_position = pos + Vector3(0.0, 0.025, 0.0)

	var mat := ShaderMaterial.new()
	mat.shader = SkyfireScorchShader
	mat.set_shader_parameter("scorch_color", theme["scorch"])
	mat.set_shader_parameter("ember_color", theme["ember"])
	mat.set_shader_parameter("ember_glow", 1.6 if is_finisher else 1.1)
	mat.set_shader_parameter("fade", 0.0)
	scorch.material_override = mat

	var tw := scorch.create_tween()
	tw.tween_property(mat, "shader_parameter/fade", 1.0, 0.12)
	# 余烬冷却：2.6s 内从炽亮熄灭为死灰
	tw.tween_property(mat, "shader_parameter/ember_glow", 0.0, 2.6).set_ease(Tween.EASE_IN)
	tw.tween_interval(1.6)
	tw.tween_property(mat, "shader_parameter/fade", 0.0, 1.2).set_ease(Tween.EASE_IN)
	tw.tween_callback(scorch.queue_free)


func _spawn_ground_flames(root: Node3D, pos: Vector3, scale_f: float, theme: Dictionary, is_finisher: bool) -> void:
	# 3D 向上腾起的柱形/锥形火柱（无交叉片死角）
	var plume_h := (2.8 if is_finisher else randf_range(1.6, 2.1)) * scale_f
	var plume_r := (1.1 if is_finisher else randf_range(0.65, 0.85)) * scale_f
	var life := 1.35 if is_finisher else 0.95

	var plume := MeshInstance3D.new()
	plume.mesh = _cone_mesh
	plume.scale = Vector3(plume_r * 2.0, plume_h, plume_r * 2.0)
	root.add_child(plume)
	plume.global_position = pos + Vector3(0.0, plume_h * 0.5, 0.0)

	var p_mat := _make_flame_cone_mat(theme, 2.2 if is_finisher else 1.7, 2.5, 3.2, 4.5, 1.4)
	plume.material_override = p_mat

	var ptw := plume.create_tween()
	ptw.set_parallel(true)
	ptw.tween_property(plume, "scale", Vector3(plume_r * 2.6, plume_h * 1.2, plume_r * 2.6), 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ptw.tween_property(p_mat, "shader_parameter/fade", 0.0, life).set_ease(Tween.EASE_IN).set_delay(0.15)
	ptw.chain().tween_callback(plume.queue_free)

	# 地面火穹（短暂膨胀的半球火云）
	var dome := MeshInstance3D.new()
	dome.mesh = _sphere_mesh
	var dome_r := (1.8 if is_finisher else randf_range(0.9, 1.2)) * scale_f
	dome.scale = Vector3(0.2 * dome_r, 0.2 * dome_r, 0.2 * dome_r)
	root.add_child(dome)
	dome.global_position = pos + Vector3(0.0, 0.1, 0.0)

	var dome_mat := _make_meteor_mat(theme, 1.5, 2.6, 0.6, 0.15)
	dome.material_override = dome_mat

	var dtw := dome.create_tween()
	dtw.set_parallel(true)
	dtw.tween_property(dome, "scale", Vector3(dome_r, dome_r * 0.75, dome_r), 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	dtw.tween_property(dome_mat, "shader_parameter/fade", 0.0, 0.30).set_ease(Tween.EASE_IN)
	dtw.chain().tween_callback(dome.queue_free)


func _spawn_impact_light(root: Node3D, pos: Vector3, scale_f: float, theme: Dictionary, is_finisher: bool) -> void:
	var light := OmniLight3D.new()
	light.light_color = theme["light"]
	light.light_energy = (9.0 if is_finisher else 6.0) * scale_f
	light.omni_range = (16.0 if is_finisher else 11.0) * scale_f
	root.add_child(light)
	light.global_position = pos + Vector3(0.0, 1.6, 0.0)

	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", light.light_energy * 0.35, 0.16)
	tw.tween_interval(0.22)
	tw.tween_property(light, "light_energy", 0.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(light.queue_free)


# ============================================================
# 拟真碎石：程序化不规则岩块 + 真实刚体物理 + 熔岩裂隙冷却
# ============================================================

func _spawn_rock_debris(root: Node3D, pos: Vector3, scale_f: float, theme: Dictionary, is_finisher: bool) -> void:
	if _rock_meshes.is_empty():
		return

	var rock_count := (11 if is_finisher else 6) + randi() % 2
	var ember_count := 3 if is_finisher else 2

	# 同一次冲击共用一份程序化岩石材质：裂隙熔岩红光随时间统一冷却降温
	var rock_mat := _make_rock_mat(theme, 1.0)

	var cool_tw := root.create_tween()
	cool_tw.tween_interval(0.12)
	cool_tw.tween_property(rock_mat, "shader_parameter/cooling_progress", 0.0, 2.5).set_ease(Tween.EASE_IN)

	# 高亮余烬碎粒材质（炽热飞溅的极小火星岩屑）
	var ember_mat := _make_rock_mat(theme, 1.0)
	ember_mat.set_shader_parameter("cooling_progress", 1.0)

	var ember_tw := root.create_tween()
	ember_tw.tween_interval(0.06)
	ember_tw.tween_property(ember_mat, "shader_parameter/cooling_progress", 0.0, 1.6).set_ease(Tween.EASE_IN)

	var speed_mult := 1.6 if is_finisher else 1.0

	for k in range(rock_count):
		var mesh: ArrayMesh = _rock_meshes[randi() % _rock_meshes.size()]
		var s := randf_range(0.24, 0.54) * scale_f * (1.3 if is_finisher else 1.0)
		var burst := Vector3(randf_range(-1.0, 1.0), randf_range(1.4, 2.8), randf_range(-1.0, 1.0)).normalized()
		var vel := burst * randf_range(3.5, 7.5) * speed_mult
		var ang := Vector3(randf_range(-9.0, 9.0), randf_range(-9.0, 9.0), randf_range(-9.0, 9.0))
		_spawn_rock_body(root, pos + Vector3(randf_range(-0.3, 0.3), 0.22, randf_range(-0.3, 0.3)), mesh, s, rock_mat, vel, ang, randf_range(3.0, 3.8))

	for k in range(ember_count):
		var mesh: ArrayMesh = _rock_meshes[randi() % _rock_meshes.size()]
		var s := randf_range(0.08, 0.15) * scale_f
		var burst := Vector3(randf_range(-1.0, 1.0), randf_range(1.8, 3.4), randf_range(-1.0, 1.0)).normalized()
		var vel := burst * randf_range(5.5, 9.5) * speed_mult
		var ang := Vector3(randf_range(-14.0, 14.0), randf_range(-14.0, 14.0), randf_range(-14.0, 14.0))
		_spawn_rock_body(root, pos + Vector3(randf_range(-0.2, 0.2), 0.25, randf_range(-0.2, 0.2)), mesh, s, ember_mat, vel, ang, randf_range(1.5, 2.2))


func _spawn_rock_body(parent: Node3D, pos: Vector3, mesh: ArrayMesh, scale_f: float, mat: Material, vel: Vector3, ang: Vector3, lifetime: float) -> void:
	var body := RigidBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 1 # 仅与地面(层1)碰撞
	body.physics_material_override = _rock_phys_mat
	body.scale = Vector3.ONE * scale_f

	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.40 # 岩石网格近似半径 0.5，碰撞体略小避免卡地
	cs.shape = sh
	body.add_child(cs)

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)

	parent.add_child(body)
	body.global_position = pos
	body.linear_velocity = vel
	body.angular_velocity = ang

	# 静置后冻结并收缩消散
	var tw := body.create_tween()
	tw.tween_interval(lifetime)
	tw.tween_callback(func():
		if body != null and is_instance_valid(body):
			body.freeze = true
	)
	tw.tween_property(body, "scale", Vector3.ZERO, 0.40).set_ease(Tween.EASE_IN)
	tw.tween_callback(body.queue_free)


## 程序化不规则岩块网格：低多边形球体经三组随机正弦谐波径向形变 + 各向异性拉伸，
## 逐三角面硬法线（棱角分明的碎岩质感），重心居中。同位置顶点形变一致（无裂缝）。
static func _build_rock_mesh(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var sphere := SphereMesh.new()
	sphere.radial_segments = 7
	sphere.rings = 4
	sphere.radius = 0.5
	sphere.height = 1.0
	var arrays: Array = sphere.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	var dir1 := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
	var dir2 := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
	var dir3 := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
	var freq1 := rng.randf_range(2.5, 6.5)
	var freq2 := rng.randf_range(2.5, 6.5)
	var freq3 := rng.randf_range(2.5, 6.5)
	var phase1 := rng.randf_range(0.0, TAU)
	var phase2 := rng.randf_range(0.0, TAU)
	var phase3 := rng.randf_range(0.0, TAU)
	var amp1 := rng.randf_range(0.08, 0.18)
	var amp2 := rng.randf_range(0.08, 0.18)
	var amp3 := rng.randf_range(0.06, 0.14)
	var aniso := Vector3(rng.randf_range(0.80, 1.45), rng.randf_range(0.65, 1.30), rng.randf_range(0.80, 1.45))

	# 展开索引并施加连续形变
	var tris: PackedVector3Array = PackedVector3Array()
	var _displace := func(v: Vector3) -> Vector3:
		var d := sin(v.dot(dir1) * freq1 + phase1) * amp1
		d += sin(v.dot(dir2) * freq2 + phase2) * amp2
		d += sin(v.dot(dir3) * freq3 + phase3) * amp3
		return v * (1.0 + d) * aniso

	if idx.size() > 0:
		for i in idx:
			tris.append(_displace.call(verts[i]))
	else:
		for v in verts:
			tris.append(_displace.call(v))

	# 重心居中
	var centroid := Vector3.ZERO
	for v in tris:
		centroid += v
	if tris.size() > 0:
		centroid /= float(tris.size())

	# 逐三角面硬法线：棱角碎岩质感
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri_count := tris.size() / 3
	for t in range(tri_count):
		var a: Vector3 = tris[t * 3 + 0] - centroid
		var b: Vector3 = tris[t * 3 + 1] - centroid
		var c: Vector3 = tris[t * 3 + 2] - centroid
		var n := (b - a).cross(c - a)
		if n.length_squared() < 0.0001:
			continue
		n = n.normalized()
		st.set_normal(n)
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)

	return st.commit()


# ============================================================
# 材质与工具
# ============================================================

func _make_meteor_mat(theme: Dictionary, intensity: float, noise_scale: float, rim_heat: float, crust_ratio: float = 0.35) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SkyfireMeteorShader
	mat.set_shader_parameter("core_color", theme["core"])
	mat.set_shader_parameter("mid_color", theme["mid"])
	mat.set_shader_parameter("edge_color", theme["edge"])
	mat.set_shader_parameter("soot_color", theme["soot"])
	mat.set_shader_parameter("intensity", intensity)
	mat.set_shader_parameter("noise_scale", noise_scale)
	mat.set_shader_parameter("speed", 3.2)
	mat.set_shader_parameter("rim_heat", rim_heat)
	mat.set_shader_parameter("crust_ratio", crust_ratio)
	mat.set_shader_parameter("fade", 1.0)
	return mat


func _make_flame_cone_mat(theme: Dictionary, intensity: float, swirl_count: float, stretch: float, speed: float, tip_erosion: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SkyfireFlameConeShader
	mat.set_shader_parameter("core_color", theme["core"])
	mat.set_shader_parameter("mid_color", theme["mid"])
	mat.set_shader_parameter("edge_color", theme["edge"])
	mat.set_shader_parameter("soot_color", theme["soot"])
	mat.set_shader_parameter("intensity", intensity)
	mat.set_shader_parameter("swirl_count", swirl_count)
	mat.set_shader_parameter("stretch", stretch)
	mat.set_shader_parameter("speed", speed)
	mat.set_shader_parameter("tip_erosion", tip_erosion)
	mat.set_shader_parameter("fade", 1.0)
	return mat


func _make_rock_mat(theme: Dictionary, cooling_progress: float = 1.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SkyfireRockShader
	mat.set_shader_parameter("ember_color", theme.get("ember", Color(1.30, 0.45, 0.08, 1.0)))
	mat.set_shader_parameter("core_color", theme.get("core", Color(1.80, 1.50, 0.90, 1.0)))
	mat.set_shader_parameter("stone_dark", theme.get("stone_dark", Color(0.11, 0.10, 0.11, 1.0)))
	mat.set_shader_parameter("stone_light", theme.get("stone_light", Color(0.33, 0.30, 0.27, 1.0)))
	mat.set_shader_parameter("stone_accent", theme.get("stone_accent", Color(0.20, 0.17, 0.15, 1.0)))
	mat.set_shader_parameter("cooling_progress", cooling_progress)
	mat.set_shader_parameter("rock_scale", 6.5)
	mat.set_shader_parameter("crack_scale", 5.5)
	mat.set_shader_parameter("roughness_val", 0.88)
	return mat


func _make_flame_sheet_mat(theme: Dictionary, intensity: float, density: float, speed: float, tip_dissipate: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SkyfireFlameSheetShader
	mat.set_shader_parameter("core_color", theme["core"])
	mat.set_shader_parameter("mid_color", theme["mid"])
	mat.set_shader_parameter("edge_color", theme["edge"])
	mat.set_shader_parameter("soot_color", theme["soot"])
	mat.set_shader_parameter("intensity", intensity)
	mat.set_shader_parameter("density", density)
	mat.set_shader_parameter("speed", speed)
	mat.set_shader_parameter("tip_dissipate", tip_dissipate)
	mat.set_shader_parameter("fade", 1.0)
	return mat


## 点光源火焰闪烁：随机能量抖动的无限链式 tween（光源销毁后自动终止）
func _flicker_light(light: OmniLight3D, base_energy: float) -> void:
	if light == null or not is_instance_valid(light):
		return
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", base_energy * randf_range(0.72, 1.32), 0.07)
	tw.tween_callback(func():
		_flicker_light(light, base_energy)
	)


func _resolve_meteor_damage(caster: CharacterBody3D, hit_pos: Vector3, is_finisher: bool) -> void:
	var tree := caster.get_tree() if (caster != null and is_instance_valid(caster) and caster.is_inside_tree()) else null
	if tree == null:
		return
	var scene_root := tree.current_scene
	if scene_root == null:
		return

	var aoe_r := (4.2 if is_finisher else 2.4) * meteor_scale
	var dmg := damage_per_meteor * (2.6 if is_finisher else 1.0)
	var swing_dir := Vector3.UP

	var candidates: Array = []
	for ch in scene_root.find_children("*", "CharacterBody3D", true, false):
		candidates.append(ch)
	for ch in scene_root.find_children("*", "DummyTarget", true, false):
		candidates.append(ch)

	for b in candidates:
		if b == null or not is_instance_valid(b) or b == caster or b.name == "Ground":
			continue
		if not (b is Node3D):
			continue
		var n3d := b as Node3D
		var d := (n3d.global_position - hit_pos).length()
		if d > aoe_r:
			continue

		if b.has_method("take_hit"):
			b.call("take_hit", hit_pos, dmg, swing_dir)

		if b.has_method("apply_hit_reaction"):
			b.call("apply_hit_reaction", "hit_chest", 0.45 if is_finisher else 0.22)


static func _ensure_cached_resources() -> void:
	if _quad_mesh == null:
		_quad_mesh = QuadMesh.new()
		_quad_mesh.size = Vector2(1.0, 1.0)

	if _plane_mesh == null:
		_plane_mesh = PlaneMesh.new()
		_plane_mesh.size = Vector2(1.0, 1.0)

	if _sphere_mesh == null:
		_sphere_mesh = SphereMesh.new()
		_sphere_mesh.radial_segments = 24
		_sphere_mesh.rings = 12

	if _cone_mesh == null:
		_cone_mesh = CylinderMesh.new()
		_cone_mesh.top_radius = 0.01
		_cone_mesh.bottom_radius = 0.5
		_cone_mesh.height = 1.0
		_cone_mesh.radial_segments = 24
		_cone_mesh.rings = 8
		_cone_mesh.cap_top = false
		_cone_mesh.cap_bottom = false

	if _rock_meshes.is_empty():
		for k in range(6):
			var rock := _build_rock_mesh(1337 + k * 7919)
			if rock != null:
				_rock_meshes.append(rock)

	if _rock_phys_mat == null:
		_rock_phys_mat = PhysicsMaterial.new()
		_rock_phys_mat.bounce = 0.38
		_rock_phys_mat.friction = 0.75

	if _warmup_mats.is_empty():
		var m_meteor := ShaderMaterial.new()
		m_meteor.shader = SkyfireMeteorShader
		_warmup_mats.append(m_meteor)

		var m_cone := ShaderMaterial.new()
		m_cone.shader = SkyfireFlameConeShader
		_warmup_mats.append(m_cone)

		var m_flame := ShaderMaterial.new()
		m_flame.shader = SkyfireFlameSheetShader
		_warmup_mats.append(m_flame)

		var m_ring := ShaderMaterial.new()
		m_ring.shader = SkyfireImpactRingShader
		_warmup_mats.append(m_ring)

		var m_scorch := ShaderMaterial.new()
		m_scorch.shader = SkyfireScorchShader
		_warmup_mats.append(m_scorch)

		var m_rock := ShaderMaterial.new()
		m_rock.shader = SkyfireRockShader
		_warmup_mats.append(m_rock)
