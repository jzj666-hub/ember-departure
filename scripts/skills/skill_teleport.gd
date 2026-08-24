extends "res://scripts/skills/skill_base.gd"
## Cyberpunk Flash Teleport Skill (Supersonic Mach Dash).
## VFX: Double Mach Vapor Cones, Staggered Sonic Boom Shock Rings, High-speed Wind Streaks & Cyber Ghost.

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const WindCutterShader = preload("res://shaders/wind_cutter.gdshader")
const SonicRingShader = preload("res://shaders/sonic_boom_ring.gdshader")
const CyberGhostEffectScript = preload("res://scripts/vfx/cyber_ghost_effect.gd")

var distance: float = 6.0
var wind_speed: float = 24.0

func get_id() -> String:
	return "teleport"

func get_name() -> String:
	return "⚡ 瞬移 (超音速破风突进)"

func get_title() -> String:
	return "⚡ 瞬移配置 (SUPERSONIC DASH)"

func get_params() -> Dictionary:
	return {
		"distance": distance,
		"wind_speed": wind_speed
	}

func set_param(key: String, value: Variant) -> void:
	match key:
		"distance": distance = float(value)
		"wind_speed": wind_speed = float(value)

func cast(caster: CharacterBody3D, intent_dir: Vector3, vfx_parent: Node, _is_spectator: bool = false) -> Dictionary:
	if caster == null or not is_instance_valid(caster):
		return {}

	var dir := intent_dir.normalized()
	if dir.length_squared() < 0.001:
		dir = caster.global_basis.z
		dir.y = 0.0
		dir = dir.normalized()

	var from_pos := caster.global_position
	var target_pos := from_pos + dir * distance

	# Obstacle raycast clearance
	var space := caster.get_world_3d().direct_space_state
	if space != null:
		var ray_query := PhysicsRayQueryParameters3D.create(
			from_pos + Vector3.UP * 0.5,
			target_pos + Vector3.UP * 0.5,
			1
		)
		ray_query.exclude = [caster.get_rid()]
		var hit := space.intersect_ray(ray_query)
		if not hit.is_empty():
			var hit_pos: Vector3 = hit.position
			target_pos = hit_pos - dir * 0.4

	var dash_vector := target_pos - from_pos
	var actual_dist := dash_vector.length()

	# 1. Leave Cyber Ghost afterimage at departure point
	if vfx_parent != null and is_instance_valid(vfx_parent):
		CyberGhostEffectScript.spawn_at_character(caster, vfx_parent, 0.35, Color(0.4, 0.9, 1.0, 0.85), 0.4)

	# 2. Align caster facing orientation to dash direction & instant displacement
	if dir.length_squared() > 0.001:
		caster.rotation.y = atan2(dir.x, dir.z)
	caster.global_position = target_pos
	caster.velocity = Vector3.ZERO

	# 3. Spawn Mach Cone & Sonic Shockwave suite along trajectory
	if actual_dist > 0.3 and vfx_parent != null and is_instance_valid(vfx_parent):
		_spawn_supersonic_breakthrough(from_pos, target_pos, dir, actual_dist, vfx_parent, wind_speed, Color(0.4, 0.9, 1.0, 0.85))

	# 4. Trigger camera dynamic FOV impulse
	_trigger_camera_punch(caster)

	# 5. Play supersonic air-cleaving SFX
	AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/knifeSlice.ogg", 2.0)

	return {
		"skill_id": get_id(),
		"from_pos": from_pos,
		"target_pos": target_pos,
		"direction": dir,
		"distance": distance,
		"wind_speed": wind_speed
	}

func replay(caster: CharacterBody3D, record: Dictionary, vfx_parent: Node) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	var m_dir: Vector3 = record.get("direction", Vector3(0, 0, 1))
	cast(caster, m_dir, vfx_parent, true)

func get_replay_hold_time(_record: Dictionary) -> float:
	return 1.30

func build_config_panel(container: VBoxContainer, on_changed: Callable) -> void:
	# 瞬移距离
	var dist_lbl := Label.new()
	dist_lbl.text = "瞬移距离 (Distance): %.1fm" % distance
	dist_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(dist_lbl)

	var dist_slider := HSlider.new()
	dist_slider.min_value = 2.0
	dist_slider.max_value = 15.0
	dist_slider.step = 0.5
	dist_slider.value = distance
	dist_slider.value_changed.connect(func(v: float):
		distance = v
		dist_lbl.text = "瞬移距离 (Distance): %.1fm" % v
		on_changed.call("distance", v)
	)
	container.add_child(dist_slider)

	# 破风气流速度
	var wind_speed_lbl := Label.new()
	wind_speed_lbl.text = "破风气流速度 (Wind Speed): %.1f" % wind_speed
	wind_speed_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(wind_speed_lbl)

	var wind_speed_slider := HSlider.new()
	wind_speed_slider.min_value = 2.0
	wind_speed_slider.max_value = 50.0
	wind_speed_slider.step = 1.0
	wind_speed_slider.value = wind_speed
	wind_speed_slider.value_changed.connect(func(v: float):
		wind_speed = v
		wind_speed_lbl.text = "破风气流速度 (Wind Speed): %.1f" % v
		on_changed.call("wind_speed", v)
	)
	container.add_child(wind_speed_slider)

static func _spawn_supersonic_breakthrough(start_pos: Vector3, end_pos: Vector3, dir: Vector3, dist: float, parent: Node, w_spd: float, wind_color: Color) -> void:
	var chest_h := Vector3.UP * 1.0
	var tip_lead_pos := end_pos + chest_h + dir * 0.4

	# Outer Mach Vapor Cone
	var outer_height := minf(dist * 0.95 + 1.2, 5.0)
	var outer_cone := CylinderMesh.new()
	outer_cone.top_radius = 0.08
	outer_cone.bottom_radius = 1.65
	outer_cone.height = outer_height
	outer_cone.radial_segments = 28
	outer_cone.rings = 3
	outer_cone.cap_top = false
	outer_cone.cap_bottom = false

	var outer_node := MeshInstance3D.new()
	outer_node.name = "MachCone_Outer"
	outer_node.mesh = outer_cone

	var outer_mat := ShaderMaterial.new()
	outer_mat.shader = WindCutterShader
	outer_mat.set_shader_parameter("wind_color", wind_color)
	outer_mat.set_shader_parameter("core_color", Color(1.0, 1.0, 1.0, 0.95))
	outer_mat.set_shader_parameter("speed", w_spd)
	outer_mat.set_shader_parameter("fade", 1.0)
	outer_mat.set_shader_parameter("streak_count", 20.0)
	VfxTextures.bind(outer_mat, "wind_tex", VfxTextures.WIND_SLASH, "tex_mix", 0.75)
	outer_mat.set_shader_parameter("tex_tiling", 2.0)
	outer_node.material_override = outer_mat
	parent.add_child(outer_node)

	_align_cylinder_to_forward(outer_node, dir)
	outer_node.global_position = tip_lead_pos - dir * (outer_height * 0.5)

	# Inner Razor Core
	var inner_height := minf(dist * 1.1 + 1.6, 6.2)
	var inner_cone := CylinderMesh.new()
	inner_cone.top_radius = 0.02
	inner_cone.bottom_radius = 0.75
	inner_cone.height = inner_height
	inner_cone.radial_segments = 20
	inner_cone.rings = 2
	inner_cone.cap_top = false
	inner_cone.cap_bottom = false

	var inner_node := MeshInstance3D.new()
	inner_node.name = "MachCone_InnerCore"
	inner_node.mesh = inner_cone

	var inner_mat := ShaderMaterial.new()
	inner_mat.shader = WindCutterShader
	inner_mat.set_shader_parameter("wind_color", Color(0.92, 0.98, 1.0, 0.9))
	inner_mat.set_shader_parameter("core_color", Color(1.3, 1.3, 1.3, 1.0))
	inner_mat.set_shader_parameter("speed", w_spd * 1.5)
	inner_mat.set_shader_parameter("fade", 1.0)
	inner_mat.set_shader_parameter("streak_count", 12.0)
	VfxTextures.bind(inner_mat, "wind_tex", VfxTextures.WIND_SLASH, "tex_mix", 0.5)
	inner_mat.set_shader_parameter("tex_tiling", 3.5)
	inner_node.material_override = inner_mat
	parent.add_child(inner_node)

	_align_cylinder_to_forward(inner_node, dir)
	inner_node.global_position = (tip_lead_pos + dir * 0.2) - dir * (inner_height * 0.5)

	# Animations
	var tw_cone := outer_node.create_tween()
	tw_cone.set_parallel(true)
	tw_cone.tween_property(outer_node, "scale", Vector3(1.6, 1.25, 1.6), 0.18)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw_cone.tween_property(inner_node, "scale", Vector3(1.35, 1.4, 1.35), 0.15)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw_cone.tween_method(func(v: float):
		if is_instance_valid(outer_mat):
			outer_mat.set_shader_parameter("fade", v)
		if is_instance_valid(inner_mat):
			inner_mat.set_shader_parameter("fade", v)
	, 1.0, 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw_cone.chain().tween_callback(func():
		if is_instance_valid(outer_node):
			outer_node.queue_free()
		if is_instance_valid(inner_node):
			inner_node.queue_free()
	)

	# Staggered Sonic Shock Rings
	var ring_ratios := [0.15, 0.55, 0.90]
	for i in range(ring_ratios.size()):
		var ratio: float = ring_ratios[i]
		var r_pos := start_pos.lerp(end_pos, ratio) + chest_h
		_spawn_sonic_ring(r_pos, dir, parent, wind_color, i * 0.025)

static func _spawn_sonic_ring(pos: Vector3, dir: Vector3, parent: Node, color: Color, delay: float) -> void:
	var q_mesh := QuadMesh.new()
	q_mesh.size = Vector2(2.0, 2.0)

	var ring_inst := MeshInstance3D.new()
	ring_inst.name = "SonicRing"
	ring_inst.mesh = q_mesh

	var r_mat := ShaderMaterial.new()
	r_mat.shader = SonicRingShader
	r_mat.set_shader_parameter("ring_color", color)
	r_mat.set_shader_parameter("fade", 1.0)
	r_mat.set_shader_parameter("thickness", 0.14)
	VfxTextures.bind(r_mat, "ring_tex", VfxTextures.SHOCKWAVE_RING, "tex_mix", 1.0)
	VfxTextures.bind_ramp(r_mat, VfxTextures.RAMP_ICE, 0.7)
	ring_inst.material_override = r_mat
	parent.add_child(ring_inst)

	var forward := dir.normalized()
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	var temp_up := Vector3.UP if absf(forward.y) < 0.99 else Vector3.FORWARD
	var right := temp_up.cross(forward).normalized()
	var up := forward.cross(right).normalized()
	ring_inst.global_transform.basis = Basis(right, up, forward)
	ring_inst.global_position = pos
	ring_inst.scale = Vector3(0.3, 0.3, 0.3)

	var tw := ring_inst.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.set_parallel(true)
	tw.tween_property(ring_inst, "scale", Vector3(2.6, 2.6, 2.6), 0.16)\
		.set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float):
		if is_instance_valid(r_mat):
			r_mat.set_shader_parameter("fade", v)
	, 1.0, 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(ring_inst.queue_free)


static func _align_cylinder_to_forward(node: Node3D, forward_dir: Vector3) -> void:
	var forward := forward_dir.normalized()
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	var temp_up := Vector3.UP if absf(forward.y) < 0.99 else Vector3.FORWARD
	var right := forward.cross(temp_up).normalized()
	var normal := right.cross(forward).normalized()
	node.global_transform.basis = Basis(right, forward, normal)


static func _trigger_camera_punch(caster: Node) -> void:
	if caster == null or not caster.is_inside_tree():
		return
	var vp := caster.get_viewport()
	if vp == null:
		return
	var cam := vp.get_camera_3d()
	if cam == null:
		return

	var orig_fov := cam.fov
	var punch_tw := cam.create_tween()
	punch_tw.tween_property(cam, "fov", orig_fov + 3.0, 0.04)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	punch_tw.tween_property(cam, "fov", orig_fov, 0.14)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func preload_assets() -> void:
	AudioManagerScript.preload_sounds([
		"res://assets/voice/RPGsounds_Kenney/OGG/knifeSlice.ogg"
	])


func get_warmup_materials() -> Array:
	var m1 := ShaderMaterial.new()
	m1.shader = WindCutterShader
	VfxTextures.bind(m1, "wind_tex", VfxTextures.WIND_SLASH, "tex_mix", 0.75)

	var m2 := ShaderMaterial.new()
	m2.shader = SonicRingShader
	VfxTextures.bind(m2, "ring_tex", VfxTextures.SHOCKWAVE_RING, "tex_mix", 1.0)
	VfxTextures.bind_ramp(m2, VfxTextures.RAMP_ICE, 0.7)

	var m3 := ShaderMaterial.new()
	m3.shader = CyberGhostEffect.SHADER_RES

	return [m1, m2, m3]
