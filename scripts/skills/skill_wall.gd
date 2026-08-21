extends "res://scripts/skills/skill_base.gd"
## 焰气之痕 (Flame Wall): place a wall of fire perpendicular to the aim line.
## Blocks anyone from crossing; the flame screen above the trace prevents jumping over.

const AudioManagerScript = preload("res://scripts/audio_manager.gd")

## Horizontal span of the wall (m).
var wall_length: float = 6.0
## Wall height (m) — tall enough that jumping cannot clear it.
var wall_height: float = 3.5
## Wall lifetime (s).
var wall_duration: float = 4.0
## Max distance the wall centre may sit from the caster (m).
var cast_range: float = 12.0

const GROUND_Y: float = 0.03


func get_id() -> String:
	return "wall"


func get_name() -> String:
	return "🔥 焰气之痕 (焰墙)"


func get_title() -> String:
	return "🔥 焰气之痕配置 (FLAME WALL)"


func get_params() -> Dictionary:
	return {
		"wall_length": wall_length,
		"wall_height": wall_height,
		"wall_duration": wall_duration,
		"cast_range": cast_range
	}


func set_param(key: String, value: Variant) -> void:
	match key:
		"wall_length": wall_length = float(value)
		"wall_height": wall_height = float(value)
		"wall_duration": wall_duration = float(value)
		"cast_range": cast_range = float(value)


## Quick-cast (Q): the wall rises directly in front of the caster.
func cast(caster: CharacterBody3D, _intent_dir: Vector3, vfx_parent: Node, _is_spectator: bool = false) -> Dictionary:
	if caster == null or not is_instance_valid(caster):
		return {}
	var fwd := caster.global_basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.001:
		fwd = Vector3(0.0, 0.0, 1.0)
	else:
		fwd = fwd.normalized()
	var target_pos := caster.global_position + fwd * (cast_range * 0.6)
	return _spawn_wall(caster, target_pos, vfx_parent)


## Aimed cast (F hold + release): spawn the wall at an exact ground position.
func cast_at(caster: CharacterBody3D, target_pos: Vector3, vfx_parent: Node, _is_spectator: bool = false) -> Dictionary:
	if caster == null or not is_instance_valid(caster):
		return {}
	return _spawn_wall(caster, target_pos, vfx_parent)


func replay(caster: CharacterBody3D, record: Dictionary, vfx_parent: Node) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	var fallback := caster.global_position + caster.global_basis.z * 6.0
	var target_pos: Vector3 = record.get("target_pos", fallback)
	_spawn_wall(caster, target_pos, vfx_parent)


func get_replay_hold_time(record: Dictionary) -> float:
	return maxf(float(record.get("wall_duration", wall_duration)) + 0.5, 2.0)


func build_config_panel(container: VBoxContainer, on_changed: Callable) -> void:
	# 墙长
	var len_lbl := Label.new()
	len_lbl.text = "墙长 (Length): %.1fm" % wall_length
	len_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(len_lbl)

	var len_slider := HSlider.new()
	len_slider.min_value = 3.0
	len_slider.max_value = 14.0
	len_slider.step = 0.5
	len_slider.value = wall_length
	len_slider.value_changed.connect(func(v: float):
		wall_length = v
		len_lbl.text = "墙长 (Length): %.1fm" % v
		on_changed.call("wall_length", v)
	)
	container.add_child(len_slider)

	# 墙高
	var h_lbl := Label.new()
	h_lbl.text = "墙高 (Height): %.1fm" % wall_height
	h_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(h_lbl)

	var h_slider := HSlider.new()
	h_slider.min_value = 1.5
	h_slider.max_value = 8.0
	h_slider.step = 0.5
	h_slider.value = wall_height
	h_slider.value_changed.connect(func(v: float):
		wall_height = v
		h_lbl.text = "墙高 (Height): %.1fm" % v
		on_changed.call("wall_height", v)
	)
	container.add_child(h_slider)

	# 持续时间
	var dur_lbl := Label.new()
	dur_lbl.text = "持续 (Duration): %.1fs" % wall_duration
	dur_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(dur_lbl)

	var dur_slider := HSlider.new()
	dur_slider.min_value = 1.0
	dur_slider.max_value = 8.0
	dur_slider.step = 0.5
	dur_slider.value = wall_duration
	dur_slider.value_changed.connect(func(v: float):
		wall_duration = v
		dur_lbl.text = "持续 (Duration): %.1fs" % v
		on_changed.call("wall_duration", v)
	)
	container.add_child(dur_slider)

	# 释放范围
	var range_lbl := Label.new()
	range_lbl.text = "释放范围 (Cast Range): %.1fm" % cast_range
	range_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(range_lbl)

	var range_slider := HSlider.new()
	range_slider.min_value = 4.0
	range_slider.max_value = 20.0
	range_slider.step = 0.5
	range_slider.value = cast_range
	range_slider.value_changed.connect(func(v: float):
		cast_range = v
		range_lbl.text = "释放范围 (Cast Range): %.1fm" % v
		on_changed.call("cast_range", v)
	)
	container.add_child(range_slider)

	# 特性说明面板
	var tip_panel := PanelContainer.new()
	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.18, 0.09, 0.02, 0.85)
	t_style.set_corner_radius_all(6)
	t_style.set_border_width_all(1)
	t_style.border_color = Color(1.0, 0.55, 0.1, 0.55)
	t_style.set_content_margin_all(8)
	tip_panel.add_theme_stylebox_override("panel", t_style)
	container.add_child(tip_panel)

	var tip_vbox := VBoxContainer.new()
	tip_vbox.add_theme_constant_override("separation", 4)
	tip_panel.add_child(tip_vbox)

	var tip1 := Label.new()
	tip1.text = "🖱️ 长按 [F] 移动鼠标挑选落点，松开释放"
	tip1.add_theme_font_size_override("font_size", 11)
	tip1.modulate = Color(1.0, 0.85, 0.35)
	tip_vbox.add_child(tip1)

	var tip2 := Label.new()
	tip2.text = "🔥 焰墙垂直于你与落点的连线，阻挡任何人穿越"
	tip2.add_theme_font_size_override("font_size", 11)
	tip2.modulate = Color(1.0, 0.65, 0.18)
	tip_vbox.add_child(tip2)

	var tip3 := Label.new()
	tip3.text = "🧗 焰屏高耸，跳跃也无法越过"
	tip3.add_theme_font_size_override("font_size", 11)
	tip3.modulate = Color(0.7, 0.8, 0.9)
	tip_vbox.add_child(tip3)


## Clamps the wall centre to cast range, then spawns the wall and returns the record.
func _spawn_wall(caster: CharacterBody3D, target_pos: Vector3, parent: Node) -> Dictionary:
	if caster == null or not is_instance_valid(caster):
		return {}
	if parent == null or not is_instance_valid(parent):
		return {}

	var from := caster.global_position
	var aim := target_pos
	aim.y = GROUND_Y

	var aim_dir := aim - from
	aim_dir.y = 0.0
	if aim_dir.length_squared() < 0.001:
		aim_dir = Vector3(0.0, 0.0, 1.0)
	else:
		aim_dir = aim_dir.normalized()

	var dist := Vector3(aim.x - from.x, 0.0, aim.z - from.z).length()
	if dist > cast_range:
		aim = from + aim_dir * cast_range
		aim.y = GROUND_Y

	# Wall line runs perpendicular to the aim direction.
	var wall_dir := Vector3(aim_dir.z, 0.0, -aim_dir.x)

	var zone := WallZone.new()
	zone.name = "FlameWall"
	zone.length = maxf(wall_length, 1.0)
	zone.height = maxf(wall_height, 1.0)
	zone.duration = maxf(wall_duration, 0.2)
	parent.add_child(zone)
	zone.global_transform = Transform3D(Basis(wall_dir, Vector3.UP, aim_dir), aim)

	AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/knifeSlice.ogg", 1.4)

	return {
		"success": true,
		"skill_id": get_id(),
		"from_pos": from,
		"target_pos": aim,
		"direction": aim_dir,
		"wall_length": wall_length,
		"wall_height": wall_height,
		"wall_duration": wall_duration,
		"cast_range": cast_range
	}


## A living flame wall: a physical barrier plus the flame trace and fire screen
## above it. Blocks movement until it dissolves.
class WallZone extends Node3D:
	var length: float = 6.0
	var height: float = 3.5
	var duration: float = 4.0

	var _elapsed: float = 0.0
	var _dead: bool = false
	var _body: StaticBody3D
	var _collider: CollisionShape3D
	var _screen_mat: StandardMaterial3D
	var _strip_mat: StandardMaterial3D
	var _flames: CPUParticles3D

	func _ready() -> void:
		_build_visuals()

	func _physics_process(delta: float) -> void:
		if _dead:
			return
		_elapsed += delta
		_flicker(delta)
		if _elapsed >= duration:
			_dead = true
			_dissolve()

	func _flicker(_delta: float) -> void:
		if _screen_mat != null and is_instance_valid(_screen_mat):
			var e := 1.3 + sin(_elapsed * 14.0) * 0.3 + sin(_elapsed * 37.0) * 0.15
			_screen_mat.emission_energy_multiplier = e

	func _dissolve() -> void:
		if _collider != null and is_instance_valid(_collider):
			_collider.set_deferred("disabled", true)
		if _flames != null and is_instance_valid(_flames):
			_flames.emitting = false
		var tw := create_tween()
		tw.set_parallel(true)
		if _screen_mat != null and is_instance_valid(_screen_mat):
			tw.tween_property(_screen_mat, "albedo_color:a", 0.0, 0.35)
		if _strip_mat != null and is_instance_valid(_strip_mat):
			tw.tween_property(_strip_mat, "albedo_color:a", 0.0, 0.35)
		tw.chain().tween_callback(queue_free)

	func _build_visuals() -> void:
		var len := maxf(length, 1.0)
		var h := maxf(height, 1.0)

		# Physical barrier (blocks walking and jumping over).
		_body = StaticBody3D.new()
		_body.name = "FlameWallBody"
		_collider = CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(len, h, 0.32)
		_collider.shape = box
		_body.add_child(_collider)
		add_child(_body)

		# Ground flame-gas trace strip.
		var strip := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(len, 0.14, 0.55)
		strip.mesh = sm
		_strip_mat = StandardMaterial3D.new()
		_strip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_strip_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_strip_mat.albedo_color = Color(1.0, 0.45, 0.1, 0.85)
		_strip_mat.emission_enabled = true
		_strip_mat.emission = Color(1.0, 0.4, 0.05)
		_strip_mat.emission_energy_multiplier = 2.0
		strip.material_override = _strip_mat
		strip.position.y = 0.1
		add_child(strip)

		# Flame screen rising above the trace.
		var screen := MeshInstance3D.new()
		var pmesh := BoxMesh.new()
		pmesh.size = Vector3(len, h, 0.12)
		screen.mesh = pmesh
		_screen_mat = StandardMaterial3D.new()
		_screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_screen_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_screen_mat.albedo_color = Color(1.0, 0.5, 0.08, 0.5)
		_screen_mat.emission_enabled = true
		_screen_mat.emission = Color(1.0, 0.4, 0.03)
		_screen_mat.emission_energy_multiplier = 1.5
		screen.material_override = _screen_mat
		screen.position.y = h * 0.5
		add_child(screen)

		# Rising flame particles along the wall.
		_flames = CPUParticles3D.new()
		_flames.amount = 64
		_flames.lifetime = 0.55
		_flames.one_shot = false
		_flames.explosiveness = 0.55
		_flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_flames.emission_box_extents = Vector3(len * 0.5, h * 0.25, 0.12)
		_flames.direction = Vector3.UP
		_flames.spread = 28.0
		_flames.gravity = Vector3(0.0, -1.5, 0.0)
		_flames.initial_velocity_min = 1.2
		_flames.initial_velocity_max = 3.2
		var fm := SphereMesh.new()
		fm.radius = 0.07
		fm.height = 0.14
		_flames.mesh = fm
		var fmat := StandardMaterial3D.new()
		fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fmat.albedo_color = Color(1.0, 0.6, 0.15, 0.85)
		_flames.material_override = fmat
		_flames.position.y = h * 0.4
		add_child(_flames)
		_flames.emitting = true


func preload_assets() -> void:
	AudioManagerScript.preload_sounds([
		"res://assets/voice/RPGsounds_Kenney/OGG/knifeSlice.ogg"
	])