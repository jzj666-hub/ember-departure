extends "res://scripts/skills/skill_base.gd"
## Stealth / Optical Camouflage Skill.
## Self View: Translucent holographic camouflage mesh, shadow removed.
## External/Opponent View (Other Player or Spectator): Absolute invisibility (0% opacity, 0 shadows, no meshes).

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const StealthCamoShader = preload("res://shaders/stealth_camo.gdshader")

var duration: float = 4.0
var self_alpha: float = 0.30

# Active stealth session tracking: caster_id -> Dictionary
static var _active_stealth: Dictionary = {}

func get_id() -> String:
	return "stealth"

func get_name() -> String:
	return "👻 隐身 (光学迷彩潜行)"

func get_title() -> String:
	return "👻 隐身配置 (OPTICAL STEALTH)"

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
	# 持续时间
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

	# 自身半透明度
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

	# 视角机制提示卡片
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
	tip1.text = "👁️ 自身操控视角：呈现半透明光学迷彩与菲涅尔轮廓"
	tip1.add_theme_font_size_override("font_size", 11)
	tip1.modulate = Color(0.4, 0.95, 1.0)
	tip_vbox.add_child(tip1)

	var tip2 := Label.new()
	tip2.text = "🚫 对方视角 (按F2切换) / Tab全局：绝对隐形 (无模型/无阴影)"
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

	# Collect all mesh instances
	var mesh_entries: Array[Dictionary] = []
	_gather_meshes(caster, mesh_entries)

	var camo_mat := ShaderMaterial.new()
	camo_mat.shader = StealthCamoShader
	camo_mat.set_shader_parameter("camo_alpha", s_alpha)

	for entry in mesh_entries:
		var mi: MeshInstance3D = entry["mesh"]
		if mi == null or not is_instance_valid(mi):
			continue
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if is_spectator_view:
			mi.visible = false
		else:
			mi.visible = true
			mi.material_override = camo_mat

	# Hide any floating name tag / badge while stealthed if external
	_update_tag_visibility(caster, not is_spectator_view)

	# Spawn activation shimmer pulse
	if vfx_parent != null and is_instance_valid(vfx_parent):
		_spawn_stealth_pulse(caster.global_position + Vector3.UP * 0.9, vfx_parent, Color(0.35, 0.85, 1.0, 0.7))

	# Audio activation feedback
	AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg", 1.0)

	# Cloak lifetime tween
	var tw := caster.create_tween()
	_active_stealth[c_id] = {
		"caster": caster,
		"meshes": mesh_entries,
		"tween": tw,
		"vfx_parent": vfx_parent,
		"camo_mat": camo_mat,
		"duration": dur,
		"self_alpha": s_alpha
	}

	tw.tween_interval(dur)
	tw.tween_callback(func():
		end_stealth(caster)
	)

	return true

## Dynamically switches stealth appearance when perspective/controlled actor changes (e.g. F2 or Tab).
static func update_perspective(current_active_controller: CharacterBody3D, is_spectator_mode: bool = false) -> void:
	for c_id in _active_stealth.keys():
		var entry: Dictionary = _active_stealth[c_id]
		var caster: CharacterBody3D = entry.get("caster")
		if caster == null or not is_instance_valid(caster):
			continue

		var mesh_entries: Array = entry.get("meshes", [])
		var camo_mat: ShaderMaterial = entry.get("camo_mat")
		var is_self_controlling := (caster == current_active_controller) and not is_spectator_mode

		for item in mesh_entries:
			var dict: Dictionary = item
			var mi: MeshInstance3D = dict.get("mesh")
			if mi == null or not is_instance_valid(mi):
				continue

			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if is_self_controlling:
				# Self view: translucent hologram
				mi.visible = true
				mi.material_override = camo_mat
			else:
				# External/Opponent view: completely invisible!
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
	_restore_mesh_states(mesh_entries)
	_update_tag_visibility(caster, true)

	var vfx_parent: Node = entry.get("vfx_parent")
	if vfx_parent != null and is_instance_valid(vfx_parent) and is_instance_valid(caster):
		_spawn_stealth_pulse(caster.global_position + Vector3.UP * 0.9, vfx_parent, Color(1.0, 0.95, 0.5, 0.8))
		AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/cloth1.ogg", 1.0)

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

static func _spawn_stealth_pulse(pos: Vector3, parent: Node, color: Color) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.6, 1.6)

	var inst := MeshInstance3D.new()
	inst.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	inst.material_override = mat

	parent.add_child(inst)
	inst.global_position = pos
	inst.scale = Vector3(0.2, 0.2, 0.2)

	var tw := inst.create_tween()
	tw.set_parallel(true)
	tw.tween_property(inst, "scale", Vector3(2.2, 2.2, 2.2), 0.28)\
		.set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.28)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(inst.queue_free)


func preload_assets() -> void:
	AudioManagerScript.preload_sounds([
		"res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg",
		"res://assets/voice/RPGsounds_Kenney/OGG/cloth1.ogg"
	])


func get_warmup_materials() -> Array:
	var m := ShaderMaterial.new()
	m.shader = StealthCamoShader
	return [m]
