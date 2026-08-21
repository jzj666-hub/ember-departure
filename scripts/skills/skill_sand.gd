extends "res://scripts/skills/skill_base.gd"
## 深沙 (Deep Sand): ground-targeted quicksand zone.
## Hold F to aim with the mouse, release to cast. Bodies inside are dragged
## toward the centre, and the pull grows stronger the closer they get.

const AudioManagerScript = preload("res://scripts/audio_manager.gd")

## Quicksand pool radius (m).
var sand_radius: float = 4.0
## Max inward pull at the centre (m/s).
var suction_strength: float = 8.0
## Zone lifetime (s).
var sand_duration: float = 3.5
## Max distance the aim point may sit from the caster (m).
var cast_range: float = 16.0

## Thin air gap so the pool disc sits cleanly on the ground.
const GROUND_Y: float = 0.03


func get_id() -> String:
	return "sand"


func get_name() -> String:
	return "🏜️ 深沙 (流沙陷落)"


func get_title() -> String:
	return "🏜️ 深沙配置 (QUICKSAND ZONE)"


func get_params() -> Dictionary:
	return {
		"sand_radius": sand_radius,
		"suction_strength": suction_strength,
		"sand_duration": sand_duration,
		"cast_range": cast_range
	}


func set_param(key: String, value: Variant) -> void:
	match key:
		"sand_radius": sand_radius = float(value)
		"suction_strength": suction_strength = float(value)
		"sand_duration": sand_duration = float(value)
		"cast_range": cast_range = float(value)


## Quick-cast (Q): the pool opens directly in front of the caster.
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
	return _spawn_quicksand(caster, target_pos, vfx_parent)


## Aimed cast (F hold + release): spawn the pool at an exact ground position.
func cast_at(caster: CharacterBody3D, target_pos: Vector3, vfx_parent: Node, _is_spectator: bool = false) -> Dictionary:
	if caster == null or not is_instance_valid(caster):
		return {}
	return _spawn_quicksand(caster, target_pos, vfx_parent)


func replay(caster: CharacterBody3D, record: Dictionary, vfx_parent: Node) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	var fallback := caster.global_position + caster.global_basis.z * 6.0
	var target_pos: Vector3 = record.get("target_pos", fallback)
	_spawn_quicksand(caster, target_pos, vfx_parent)


func get_replay_hold_time(record: Dictionary) -> float:
	return maxf(float(record.get("sand_duration", sand_duration)) + 0.5, 2.0)


func build_config_panel(container: VBoxContainer, on_changed: Callable) -> void:
	# 沙区半径
	var radius_lbl := Label.new()
	radius_lbl.text = "沙区半径 (Radius): %.1fm" % sand_radius
	radius_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(radius_lbl)

	var radius_slider := HSlider.new()
	radius_slider.min_value = 2.0
	radius_slider.max_value = 10.0
	radius_slider.step = 0.5
	radius_slider.value = sand_radius
	radius_slider.value_changed.connect(func(v: float):
		sand_radius = v
		radius_lbl.text = "沙区半径 (Radius): %.1fm" % v
		on_changed.call("sand_radius", v)
	)
	container.add_child(radius_slider)

	# 吸力强度
	var pull_lbl := Label.new()
	pull_lbl.text = "吸力强度 (Suction): %.1f m/s" % suction_strength
	pull_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(pull_lbl)

	var pull_slider := HSlider.new()
	pull_slider.min_value = 2.0
	pull_slider.max_value = 20.0
	pull_slider.step = 0.5
	pull_slider.value = suction_strength
	pull_slider.value_changed.connect(func(v: float):
		suction_strength = v
		pull_lbl.text = "吸力强度 (Suction): %.1f m/s" % v
		on_changed.call("suction_strength", v)
	)
	container.add_child(pull_slider)

	# 持续时间
	var dur_lbl := Label.new()
	dur_lbl.text = "持续时间 (Duration): %.1fs" % sand_duration
	dur_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(dur_lbl)

	var dur_slider := HSlider.new()
	dur_slider.min_value = 1.0
	dur_slider.max_value = 8.0
	dur_slider.step = 0.5
	dur_slider.value = sand_duration
	dur_slider.value_changed.connect(func(v: float):
		sand_duration = v
		dur_lbl.text = "持续时间 (Duration): %.1fs" % v
		on_changed.call("sand_duration", v)
	)
	container.add_child(dur_slider)

	# 释放范围
	var range_lbl := Label.new()
	range_lbl.text = "释放范围 (Cast Range): %.1fm" % cast_range
	range_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(range_lbl)

	var range_slider := HSlider.new()
	range_slider.min_value = 4.0
	range_slider.max_value = 25.0
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
	t_style.bg_color = Color(0.16, 0.11, 0.03, 0.85)
	t_style.set_corner_radius_all(6)
	t_style.set_border_width_all(1)
	t_style.border_color = Color(0.95, 0.72, 0.2, 0.55)
	t_style.set_content_margin_all(8)
	tip_panel.add_theme_stylebox_override("panel", t_style)
	container.add_child(tip_panel)

	var tip_vbox := VBoxContainer.new()
	tip_vbox.add_theme_constant_override("separation", 4)
	tip_panel.add_child(tip_vbox)

	var tip1 := Label.new()
	tip1.text = "🖱️ 长按 [F] 移动鼠标挑选落点，松开释放心区域流沙"
	tip1.add_theme_font_size_override("font_size", 11)
	tip1.modulate = Color(1.0, 0.85, 0.35)
	tip_vbox.add_child(tip1)

	var tip2 := Label.new()
	tip2.text = "🌀 越靠近流沙中心，向内的吸力越强 (快速拖拽)"
	tip2.add_theme_font_size_override("font_size", 11)
	tip2.modulate = Color(0.95, 0.72, 0.2)
	tip_vbox.add_child(tip2)

	var tip3 := Label.new()
	tip3.text = "⌨️ 轻点 [Q] 亦可快速在正前方释放"
	tip3.add_theme_font_size_override("font_size", 11)
	tip3.modulate = Color(0.7, 0.8, 0.9)
	tip_vbox.add_child(tip3)


## Clamps the aim point to cast range, then spawns the pool and returns the record.
func _spawn_quicksand(caster: CharacterBody3D, target_pos: Vector3, parent: Node) -> Dictionary:
	if caster == null or not is_instance_valid(caster):
		return {}
	if parent == null or not is_instance_valid(parent):
		return {}

	var aim := target_pos
	aim.y = GROUND_Y

	var from := caster.global_position
	var dh := Vector3(aim.x - from.x, 0.0, aim.z - from.z)
	if dh.length() > cast_range:
		dh = dh.normalized() * cast_range
		aim = Vector3(from.x + dh.x, GROUND_Y, from.z + dh.z)

	var zone := QuicksandZone.new()
	zone.name = "QuicksandZone"
	zone.radius = maxf(sand_radius, 0.5)
	zone.max_pull = maxf(suction_strength, 0.0)
	zone.lifetime = maxf(sand_duration, 0.1)
	parent.add_child(zone)
	zone.global_position = aim

	AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg", 1.1)

	return {
		"success": true,
		"skill_id": get_id(),
		"from_pos": from,
		"target_pos": aim,
		"sand_radius": sand_radius,
		"suction_strength": suction_strength,
		"sand_duration": sand_duration,
		"cast_range": cast_range
	}


## A living quicksand pool. Drags nearby bodies inward each physics tick, then
## dissolves once its lifetime elapses.
class QuicksandZone extends Node3D:
	var radius: float = 4.0
	var max_pull: float = 8.0
	var lifetime: float = 3.5

	var _elapsed: float = 0.0
	var _dead: bool = false
	var _disc: MeshInstance3D
	var _disc_mat: StandardMaterial3D
	var _ring_outer: MeshInstance3D
	var _ring_inner: MeshInstance3D
	var _swirl: CPUParticles3D

	func _ready() -> void:
		_build_visuals()

	func _physics_process(delta: float) -> void:
		if _dead:
			return
		_elapsed += delta
		_drag_bodies(delta)
		_spin(delta)
		if _elapsed >= lifetime:
			_dead = true
			_dissolve()

	func _drag_bodies(delta: float) -> void:
		if radius <= 0.0 or max_pull <= 0.0:
			return
		var tree := get_tree()
		if tree == null:
			return

		var bodies := tree.root.find_children("", "CharacterBody3D", true, false)
		for b in bodies:
			if not (b is CharacterBody3D):
				continue
			var cb := b as CharacterBody3D
			if cb.name == "Ground":
				continue

			var to_center := global_position - cb.global_position
			to_center.y = 0.0
			var dist := to_center.length()
			if dist >= radius or dist < 0.04:
				continue

			# Pull rises from 0 at the rim to max_pull at the centre.
			var falloff := 1.0 - clampf(dist / radius, 0.0, 1.0)
			cb.global_position += to_center / dist * max_pull * falloff * delta

	func _spin(delta: float) -> void:
		if _ring_outer != null and is_instance_valid(_ring_outer):
			_ring_outer.rotation.y += delta * 0.9
		if _ring_inner != null and is_instance_valid(_ring_inner):
			_ring_inner.rotation.y -= delta * 2.4

	func _dissolve() -> void:
		if _swirl != null and is_instance_valid(_swirl):
			_swirl.emitting = false
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(self, "scale", Vector3(0.9, 0.9, 0.9), 0.32)
		if _disc_mat != null and is_instance_valid(_disc_mat):
			tw.tween_property(_disc_mat, "albedo_color:a", 0.0, 0.32)
		tw.chain().tween_callback(queue_free)

	func _build_visuals() -> void:
		var r := maxf(radius, 0.5)

		# Sand pool disc.
		_disc = MeshInstance3D.new()
		_disc.name = "SandPool"
		var dm := CylinderMesh.new()
		dm.top_radius = r
		dm.bottom_radius = r
		dm.height = 0.05
		dm.radial_segments = 48
		_disc.mesh = dm
		_disc_mat = StandardMaterial3D.new()
		_disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_disc_mat.albedo_color = Color(0.36, 0.28, 0.16, 0.62)
		_disc_mat.emission_enabled = true
		_disc_mat.emission = Color(0.55, 0.42, 0.18)
		_disc_mat.emission_energy_multiplier = 0.6
		_disc.material_override = _disc_mat
		add_child(_disc)

		# Outer rim ring.
		_ring_outer = _make_ring(r * 0.97, r * 1.02, Color(0.72, 0.55, 0.22, 0.85), 0.05)
		add_child(_ring_outer)

		# Inner swirl ring.
		_ring_inner = _make_ring(r * 0.45, r * 0.52, Color(0.5, 0.38, 0.14, 0.7), 0.03)
		add_child(_ring_inner)

		# Sinking sand grains.
		_swirl = CPUParticles3D.new()
		_swirl.name = "SinkingSand"
		_swirl.amount = 48
		_swirl.lifetime = 1.0
		_swirl.one_shot = false
		_swirl.explosiveness = 0.4
		_swirl.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_swirl.emission_sphere_radius = r * 0.6
		_swirl.direction = Vector3.DOWN
		_swirl.spread = 20.0
		_swirl.gravity = Vector3(0.0, -4.0, 0.0)
		_swirl.initial_velocity_min = 0.5
		_swirl.initial_velocity_max = 1.6
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		_swirl.mesh = sm
		var smat := StandardMaterial3D.new()
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.albedo_color = Color(0.62, 0.5, 0.24, 0.85)
		_swirl.material_override = smat
		add_child(_swirl)
		_swirl.position = Vector3(0.0, 0.15, 0.0)
		_swirl.emitting = true

	func _make_ring(inner_r: float, outer_r: float, color: Color, height: float) -> MeshInstance3D:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = inner_r
		tm.outer_radius = outer_r
		tm.rings = 40
		tm.ring_segments = 5
		ring.mesh = tm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = Color(color.r, color.g, color.b)
		mat.emission_energy_multiplier = 1.1
		ring.material_override = mat
		ring.position.y = height
		return ring


func preload_assets() -> void:
	AudioManagerScript.preload_sounds([
		"res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg"
	])