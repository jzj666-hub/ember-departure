extends "res://scripts/skills/skill_base.gd"
## Skill 10: Jump Buff (🦘 弹跳增益).
## Multiplies caster's jump speed and air agility for duration.
## VFX: Glowing cyan/gold wind spiral vortex at feet, rising aerodynamic air ribbons, and launch burst.

const AudioManagerScript = preload("res://scripts/audio_manager.gd")

var duration: float = 8.0
var jump_multiplier: float = 2.4
var air_control_boost: float = 1.8

# Active buffs tracking: caster_id -> Dictionary
static var _active_buffs: Dictionary = {}


func get_id() -> String:
	return "jump_buff"


func get_name() -> String:
	return "🦘 弹跳增益 (高空飞跃)"


func get_title() -> String:
	return "🦘 弹跳增益配置 (JUMP BOOST BUFF)"


func get_params() -> Dictionary:
	return {
		"duration": duration,
		"jump_multiplier": jump_multiplier,
		"air_control_boost": air_control_boost
	}


func set_param(key: String, value: Variant) -> void:
	match key:
		"duration": duration = float(value)
		"jump_multiplier": jump_multiplier = float(value)
		"air_control_boost": air_control_boost = float(value)


func cast(caster: CharacterBody3D, _intent_dir: Vector3, vfx_parent: Node, _is_spectator: bool = false) -> Dictionary:
	if caster == null or not is_instance_valid(caster):
		return {}

	_apply_jump_buff(caster, duration, jump_multiplier, air_control_boost, vfx_parent)

	AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg", 1.2)

	return {
		"success": true,
		"skill_id": get_id(),
		"from_pos": caster.global_position if caster.is_inside_tree() else Vector3.ZERO,
		"duration": duration,
		"jump_multiplier": jump_multiplier
	}


func replay(caster: CharacterBody3D, record: Dictionary, vfx_parent: Node) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	var dur: float = float(record.get("duration", duration))
	var mult: float = float(record.get("jump_multiplier", jump_multiplier))
	_apply_jump_buff(caster, dur, mult, air_control_boost, vfx_parent)


func get_replay_hold_time(record: Dictionary) -> float:
	return float(record.get("duration", duration)) + 0.5


func build_config_panel(container: VBoxContainer, on_changed: Callable) -> void:
	# 持续时长
	var dur_lbl := Label.new()
	dur_lbl.text = "增益持续时长 (Duration): %.1fs" % duration
	dur_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(dur_lbl)

	var dur_slider := HSlider.new()
	dur_slider.min_value = 2.0
	dur_slider.max_value = 20.0
	dur_slider.step = 0.5
	dur_slider.value = duration
	dur_slider.value_changed.connect(func(v: float):
		duration = v
		dur_lbl.text = "增益持续时长 (Duration): %.1fs" % v
		on_changed.call("duration", v)
	)
	container.add_child(dur_slider)

	# 跳跃倍率
	var mult_lbl := Label.new()
	mult_lbl.text = "跳跃力度倍率 (Jump Multiplier): %.1fx" % jump_multiplier
	mult_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(mult_lbl)

	var mult_slider := HSlider.new()
	mult_slider.min_value = 1.2
	mult_slider.max_value = 4.5
	mult_slider.step = 0.1
	mult_slider.value = jump_multiplier
	mult_slider.value_changed.connect(func(v: float):
		jump_multiplier = v
		mult_lbl.text = "跳跃力度倍率 (Jump Multiplier): %.1fx" % v
		on_changed.call("jump_multiplier", v)
	)
	container.add_child(mult_slider)

	# 说明面板
	var tip_panel := PanelContainer.new()
	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.04, 0.12, 0.14, 0.90)
	t_style.set_corner_radius_all(6)
	t_style.set_border_width_all(1)
	t_style.border_color = Color(0.2, 0.85, 0.95, 0.7)
	t_style.set_content_margin_all(8)
	tip_panel.add_theme_stylebox_override("panel", t_style)
	container.add_child(tip_panel)

	var tip_vbox := VBoxContainer.new()
	tip_vbox.add_theme_constant_override("separation", 4)
	tip_panel.add_child(tip_vbox)

	var tip1 := Label.new()
	tip1.text = "💨 瞬间强化足底气流涡旋，巨幅提升起跳高度与浮空时间"
	tip1.add_theme_font_size_override("font_size", 11)
	tip1.modulate = Color(0.4, 0.95, 1.0)
	tip_vbox.add_child(tip1)

	var tip2 := Label.new()
	tip2.text = "🦘 轻松跨越超高地形与高台障碍，滞空期间拥有极高机动性"
	tip2.add_theme_font_size_override("font_size", 11)
	tip2.modulate = Color(1.0, 0.9, 0.4)
	tip_vbox.add_child(tip2)


static func _apply_jump_buff(caster: CharacterBody3D, dur: float, mult: float, ctrl_boost: float, parent: Node) -> void:
	if caster == null or not is_instance_valid(caster):
		return

	var c_id := caster.get_instance_id()
	var orig_speed: float = float(caster.get("jump_speed")) if caster.get("jump_speed") != null else 4.7
	var orig_ctrl: float = float(caster.get("air_control")) if caster.get("air_control") != null else 0.35

	if _active_buffs.has(c_id):
		var entry: Dictionary = _active_buffs[c_id]
		orig_speed = float(entry.get("orig_speed", orig_speed))
		orig_ctrl = float(entry.get("orig_ctrl", orig_ctrl))
		var old_tw: Tween = entry.get("tween")
		if old_tw != null and old_tw.is_valid():
			old_tw.kill()
		var old_vfx: Node = entry.get("vfx")
		if old_vfx != null and is_instance_valid(old_vfx):
			old_vfx.queue_free()

	caster.set("jump_speed", orig_speed * mult)
	caster.set("air_control", orig_ctrl * ctrl_boost)

	var aura := _spawn_wind_vortex_vfx(caster, dur, parent)

	var tw := caster.create_tween()
	_active_buffs[c_id] = {
		"orig_speed": orig_speed,
		"orig_ctrl": orig_ctrl,
		"tween": tw,
		"vfx": aura
	}

	tw.tween_interval(dur)
	tw.tween_callback(func():
		_remove_jump_buff(caster)
	)


static func _remove_jump_buff(caster: CharacterBody3D) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	var c_id := caster.get_instance_id()
	if not _active_buffs.has(c_id):
		return
	var entry: Dictionary = _active_buffs[c_id]
	var orig_speed: float = float(entry.get("orig_speed", 4.7))
	var orig_ctrl: float = float(entry.get("orig_ctrl", 0.35))
	_active_buffs.erase(c_id)

	if is_instance_valid(caster):
		caster.set("jump_speed", orig_speed)
		caster.set("air_control", orig_ctrl)


static func _spawn_wind_vortex_vfx(caster: CharacterBody3D, dur: float, parent: Node) -> Node3D:
	if parent == null or not is_instance_valid(parent):
		parent = caster

	var root_vfx := Node3D.new()
	root_vfx.name = "JumpBuffWindAura"
	parent.add_child(root_vfx)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.45
	torus.outer_radius = 0.75
	torus.rings = 24
	torus.ring_segments = 12
	ring.mesh = torus
	ring.position.y = 0.08

	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = Color(0.2, 0.95, 1.0, 0.85)
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = ring_mat
	root_vfx.add_child(ring)

	var parts := CPUParticles3D.new()
	parts.amount = 28
	parts.lifetime = 0.6
	parts.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	parts.emission_ring_radius = 0.6
	parts.emission_ring_inner_radius = 0.3
	parts.direction = Vector3.UP
	parts.spread = 15.0
	parts.gravity = Vector3(0.0, 4.0, 0.0)
	parts.initial_velocity_min = 2.0
	parts.initial_velocity_max = 4.5
	var sm := SphereMesh.new()
	sm.radius = 0.04
	sm.height = 0.08
	parts.mesh = sm
	var p_mat := StandardMaterial3D.new()
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p_mat.albedo_color = Color(0.3, 0.95, 0.85, 0.75)
	parts.material_override = p_mat
	root_vfx.add_child(parts)
	parts.emitting = true

	var tw := root_vfx.create_tween()
	tw.set_parallel(true)
	tw.tween_method(func(_t: float):
		if is_instance_valid(caster) and is_instance_valid(root_vfx):
			root_vfx.global_position = caster.global_position
			ring.rotate_y(0.12)
	, 0.0, 1.0, dur)

	tw.chain().tween_property(ring_mat, "albedo_color:a", 0.0, 0.3)
	tw.chain().tween_callback(root_vfx.queue_free)

	return root_vfx


func preload_assets() -> void:
	AudioManagerScript.preload_sounds([
		"res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg"
	])
