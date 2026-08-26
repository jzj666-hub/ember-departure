extends "res://scripts/skills/skill_base.gd"
## 光学迷彩·多点消融潜行 (Multi-Point Dissolve Optical Stealth).
## 隐身与显形过程由模型多个中心平滑残破消融与全息重构呈现，
## 彻底去除生硬方块粒子；自身视角呈现清爽半透明全息轮廓，外界视角绝对隐形。

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const StealthCamoShader = preload("res://shaders/stealth_camo.gdshader")

var duration: float = 4.0
var self_alpha: float = 0.30

# Active stealth session tracking: caster_id -> Dictionary
static var _active_stealth: Dictionary = {}

func get_id() -> String:
	return "stealth"

func get_name() -> String:
	return "👻 隐身 (多点消融潜行)"

func get_title() -> String:
	return "👻 隐身配置 (DISSOLVE OPTICAL STEALTH)"

func get_params() -> Dictionary:
	return {
		"duration": duration,
		"self_alpha": self_alpha
	}

func set_param(key: String, value: Variant) -> void:
	match key:
		"duration": duration = float(value)
		"self_alpha": self_alpha = float(value)

func cast(caster: CharacterBody3D, _intent_dir: Vector3, vfx_parent: Node, is_spectator: bool = false) -> Dictionary:
	if caster == null or not is_instance_valid(caster):
		return {}

	execute_stealth(caster, duration, self_alpha, vfx_parent, is_spectator)

	return {
		"skill_id": get_id(),
		"from_pos": caster.global_position,
		"direction": caster.global_basis.z,
		"duration": duration,
		"self_alpha": self_alpha,
		"caster": caster
	}

func replay(caster: CharacterBody3D, record: Dictionary, vfx_parent: Node) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	var dur: float = float(record.get("duration", duration))
	var s_alpha: float = float(record.get("self_alpha", self_alpha))
	execute_stealth(caster, dur, s_alpha, vfx_parent, true)

func get_replay_hold_time(_record: Dictionary) -> float:
	return maxf(duration, 1.8)

func build_config_panel(container: VBoxContainer, on_changed: Callable) -> void:
	var dur_lbl := Label.new()
	dur_lbl.text = "隐身持续时间 (Duration): %.1fs" % duration
	dur_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(dur_lbl)

	var dur_slider := HSlider.new()
	dur_slider.min_value = 1.0
	dur_slider.max_value = 10.0
	dur_slider.step = 0.5
	dur_slider.value = duration
	dur_slider.value_changed.connect(func(v: float):
		duration = v
		dur_lbl.text = "隐身持续时间 (Duration): %.1fs" % v
		on_changed.call("duration", v)
	)
	container.add_child(dur_slider)

	var alpha_lbl := Label.new()
	alpha_lbl.text = "自身半透明度 (Self-View Alpha): %.2f" % self_alpha
	alpha_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(alpha_lbl)

	var alpha_slider := HSlider.new()
	alpha_slider.min_value = 0.05
	alpha_slider.max_value = 0.80
	alpha_slider.step = 0.05
	alpha_slider.value = self_alpha
	alpha_slider.value_changed.connect(func(v: float):
		self_alpha = v
		alpha_lbl.text = "自身半透明度 (Self-View Alpha): %.2f" % v
		on_changed.call("self_alpha", v)
	)
	container.add_child(alpha_slider)

	var tip_panel := PanelContainer.new()
	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.02, 0.12, 0.18, 0.75)
	t_style.set_corner_radius_all(6)
	t_style.set_border_width_all(1)
	t_style.border_color = Color(0.0, 0.8, 1.0, 0.4)
	t_style.set_content_margin_all(8)
	tip_panel.add_theme_stylebox_override("panel", t_style)
	container.add_child(tip_panel)

	var tip_vbox := VBoxContainer.new()
	tip_vbox.add_theme_constant_override("separation", 4)
	tip_panel.add_child(tip_vbox)

	var tip1 := Label.new()
	tip1.text = "✨ 隐身时角色从身体多个部位残破消融，显形时发光重构凝聚"
	tip1.add_theme_font_size_override("font_size", 11)
	tip1.modulate = Color(0.4, 0.95, 1.0)
	tip_vbox.add_child(tip1)

	var tip2 := Label.new()
	tip2.text = "👁️ 自身视角：清爽半透明光学迷彩；对方/旁观视角：绝对隐形"
	tip2.add_theme_font_size_override("font_size", 11)
	tip2.modulate = Color(1.0, 0.85, 0.3)
	tip_vbox.add_child(tip2)

static func execute_stealth(caster: CharacterBody3D, dur: float, s_alpha: float, vfx_parent: Node, is_spectator_view: bool = false) -> bool:
	if caster == null or not is_instance_valid(caster):
		return false

	var c_id := caster.get_instance_id()

	# If already stealthed, cancel prior timer and re-cloak
	if _active_stealth.has(c_id):
		var prev_entry: Dictionary = _active_stealth[c_id]
		var prev_tw: Tween = prev_entry.get("tween")
		if prev_tw != null and prev_tw.is_valid():
			prev_tw.kill()
		_restore_mesh_states(prev_entry.get("meshes", []))

	var mesh_entries: Array[Dictionary] = []
	_gather_meshes(caster, mesh_entries)

	var camo_mat := ShaderMaterial.new()
	camo_mat.shader = StealthCamoShader
	camo_mat.set_shader_parameter("camo_alpha", s_alpha)
	camo_mat.set_shader_parameter("is_in_dissolve_mode", true)
	camo_mat.set_shader_parameter("dissolve_progress", 0.0)

	for entry in mesh_entries:
		var mi: MeshInstance3D = entry["mesh"]
		if mi == null or not is_instance_valid(mi):
			continue
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = true
		mi.material_override = camo_mat

	_update_tag_visibility(caster, not is_spectator_view)

	# Audio activation
	AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg", 1.2)

	# 1. 进入隐身的多点平滑残破消融动画 (0.0 -> 1.0 over 0.35s)
	var dissolve_in_tw := caster.create_tween()
	dissolve_in_tw.tween_method(func(v: float):
		if is_instance_valid(camo_mat):
			camo_mat.set_shader_parameter("dissolve_progress", v)
	, 0.0, 1.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

	dissolve_in_tw.chain().tween_callback(func():
		if is_instance_valid(camo_mat):
			if is_spectator_view:
				# External / Opponent view: completely invisible
				for entry in mesh_entries:
					var mi: MeshInstance3D = entry["mesh"]
					if mi != null and is_instance_valid(mi):
						mi.visible = false
			else:
				# Self view: sustained holographic shimmer
				camo_mat.set_shader_parameter("is_in_dissolve_mode", false)
				camo_mat.set_shader_parameter("camo_alpha", s_alpha)
	)

	# 2. 隐身持续与定时结束
	var tw := caster.create_tween()
	_active_stealth[c_id] = {
		"caster": caster,
		"meshes": mesh_entries,
		"tween": tw,
		"vfx_parent": vfx_parent,
		"camo_mat": camo_mat,
		"duration": dur,
		"self_alpha": s_alpha,
		"is_spectator_view": is_spectator_view
	}

	tw.tween_interval(dur)
	tw.tween_callback(func():
		end_stealth(caster)
	)

	return true

## Dynamically switches stealth appearance when perspective changes
static func update_perspective(current_active_controller: CharacterBody3D, is_spectator_mode: bool = false) -> void:
	for c_id in _active_stealth.keys():
		var entry: Dictionary = _active_stealth[c_id]
		var caster: CharacterBody3D = entry.get("caster")
		if caster == null or not is_instance_valid(caster):
			continue

		var mesh_entries: Array = entry.get("meshes", [])
		var camo_mat: ShaderMaterial = entry.get("camo_mat")
		var is_self_controlling := (caster == current_active_controller) and not is_spectator_mode
		entry["is_spectator_view"] = not is_self_controlling

		for item in mesh_entries:
			var dict: Dictionary = item
			var mi: MeshInstance3D = dict.get("mesh")
			if mi == null or not is_instance_valid(mi):
				continue

			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if is_self_controlling:
				mi.visible = true
				mi.material_override = camo_mat
				if is_instance_valid(camo_mat):
					camo_mat.set_shader_parameter("is_in_dissolve_mode", false)
			else:
				mi.visible = false

		_update_tag_visibility(caster, is_self_controlling)

static func end_stealth(caster: CharacterBody3D) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	var c_id := caster.get_instance_id()
	if not _active_stealth.has(c_id):
		return

	var entry: Dictionary = _active_stealth[c_id]
	_active_stealth.erase(c_id)

	var mesh_entries: Array = entry.get("meshes", [])
	var camo_mat: ShaderMaterial = entry.get("camo_mat")

	if is_instance_valid(camo_mat):
		camo_mat.set_shader_parameter("is_in_dissolve_mode", true)
		camo_mat.set_shader_parameter("dissolve_progress", 1.0)

	for item in mesh_entries:
		var dict: Dictionary = item
		var mi: MeshInstance3D = dict.get("mesh")
		if mi != null and is_instance_valid(mi):
			mi.visible = true
			mi.material_override = camo_mat

	AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/cloth1.ogg", 1.2)

	# 显形多点平滑重构凝聚动画 (1.0 -> 0.0 over 0.38s)
	var reconstruct_tw := caster.create_tween()
	reconstruct_tw.tween_method(func(v: float):
		if is_instance_valid(camo_mat):
			camo_mat.set_shader_parameter("dissolve_progress", v)
	, 1.0, 0.0, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	reconstruct_tw.chain().tween_callback(func():
		_restore_mesh_states(mesh_entries)
		_update_tag_visibility(caster, true)
	)

static func is_stealthed(caster: CharacterBody3D) -> bool:
	if caster == null or not is_instance_valid(caster):
		return false
	return _active_stealth.has(caster.get_instance_id())

static func _gather_meshes(node: Node, result: Array[Dictionary]) -> void:
	if node == null:
		return
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			result.append({
				"mesh": mi,
				"orig_mat": mi.material_override,
				"orig_shadow": mi.cast_shadow,
				"orig_visible": mi.visible
			})
		_gather_meshes(child, result)

static func _restore_mesh_states(mesh_entries: Array) -> void:
	for item in mesh_entries:
		var entry: Dictionary = item
		var mi: MeshInstance3D = entry.get("mesh")
		if mi != null and is_instance_valid(mi):
			mi.material_override = entry.get("orig_mat", null)
			mi.cast_shadow = entry.get("orig_shadow", GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
			mi.visible = entry.get("orig_visible", true)

static func _update_tag_visibility(caster: CharacterBody3D, is_visible: bool) -> void:
	if caster == null:
		return
	for child in caster.get_children():
		if child is Label3D:
			child.visible = is_visible

## reset_state(): drops stealth bookkeeping. Scene entry only.
func reset_state() -> void:
	_active_stealth.clear()


func preload_assets() -> void:
	AudioManagerScript.preload_sounds([
		"res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg",
		"res://assets/voice/RPGsounds_Kenney/OGG/cloth1.ogg"
	])

func get_warmup_materials() -> Array:
	var m := ShaderMaterial.new()
	m.shader = StealthCamoShader
	return [m]
