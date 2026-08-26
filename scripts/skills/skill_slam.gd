extends "res://scripts/skills/skill_base.gd"
## Skill 9: Ground Slam (裂地崩击).
## Caster leaps high and slams ground with natural glowing subterranean fissures, 3D rock debris, and jutting ground rock spikes that erupt and scatter outward.
## Features localized 3D spatial refraction distortion shockwaves, rich deep-brown soil & silver-white rock palette, and sustained duration.
## Automatically detects true ground plane even when cast while jumping/airborne.
## Preloads all textures, audio, shaders and warmup materials with static mesh/material caching to eliminate first-cast stutter.

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const SonicRingShader = preload("res://shaders/sonic_boom_ring.gdshader")
const ShockwaveDomeShader = preload("res://shaders/shockwave_dome.gdshader")
const EarthSpatialDistortionShader = preload("res://shaders/earth_spatial_distortion.gdshader")
const GroundFractureGlowShader = preload("res://shaders/ground_fracture_glow.gdshader")

var slam_radius: float = 8.0
var leap_height: float = 4.5
var leap_time: float = 0.38
var slam_time: float = 0.20
var max_launch_dist: float = 7.5
var max_launch_height: float = 3.2
var fall_duration: float = 1.8

const SUSTAIN_DURATION: float = 2.2

static var _active_knockdowns: Dictionary = {}

# Reusable cached meshes and materials to eliminate runtime instantiation latency
static var _cached_rock_mesh: PrismMesh = null
static var _cached_spike_mesh: CylinderMesh = null
static var _cached_rock_mat: StandardMaterial3D = null


func get_id() -> String:
	return "slam"


func get_name() -> String:
	return "💥 裂地崩击 (地面裂纹·突起岩石)"


func get_title() -> String:
	return "💥 裂地崩击配置 (GROUND SLAM & EARTH FISSURE)"


func get_params() -> Dictionary:
	return {
		"slam_radius": slam_radius,
		"leap_height": leap_height,
		"leap_time": leap_time,
		"slam_time": slam_time,
		"max_launch_dist": max_launch_dist,
		"max_launch_height": max_launch_height,
		"fall_duration": fall_duration
	}


func set_param(key: String, value: Variant) -> void:
	match key:
		"slam_radius": slam_radius = float(value)
		"leap_height": leap_height = float(value)
		"leap_time": leap_time = float(value)
		"slam_time": slam_time = float(value)
		"max_launch_dist": max_launch_dist = float(value)
		"max_launch_height": max_launch_height = float(value)
		"fall_duration": fall_duration = float(value)


func cast(caster: CharacterBody3D, _intent_dir: Vector3, vfx_parent: Node, _is_spectator: bool = false) -> Dictionary:
	if caster == null or not is_instance_valid(caster) or not caster.is_inside_tree():
		return {}
	return _execute_slam(caster, vfx_parent)


func replay(caster: CharacterBody3D, record: Dictionary, vfx_parent: Node) -> void:
	if caster == null or not is_instance_valid(caster) or not caster.is_inside_tree():
		return
	_execute_slam(caster, vfx_parent)


func get_replay_hold_time(_record: Dictionary) -> float:
	return leap_time + slam_time + fall_duration + 2.0


func build_config_panel(container: VBoxContainer, on_changed: Callable) -> void:
	# 波及半径
	var radius_lbl := Label.new()
	radius_lbl.text = "地裂波及半径 (Radius): %.1fm" % slam_radius
	radius_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(radius_lbl)

	var radius_slider := HSlider.new()
	radius_slider.min_value = 3.0
	radius_slider.max_value = 16.0
	radius_slider.step = 0.5
	radius_slider.value = slam_radius
	radius_slider.value_changed.connect(func(v: float):
		slam_radius = v
		radius_lbl.text = "地裂波及半径 (Radius): %.1fm" % v
		on_changed.call("slam_radius", v)
	)
	container.add_child(radius_slider)

	# 跃起高度
	var leap_lbl := Label.new()
	leap_lbl.text = "起跳跃起高度 (Leap Height): %.1fm" % leap_height
	leap_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(leap_lbl)

	var leap_slider := HSlider.new()
	leap_slider.min_value = 2.0
	leap_slider.max_value = 8.0
	leap_slider.step = 0.5
	leap_slider.value = leap_height
	leap_slider.value_changed.connect(func(v: float):
		leap_height = v
		leap_lbl.text = "起跳跃起高度 (Leap Height): %.1fm" % v
		on_changed.call("leap_height", v)
	)
	container.add_child(leap_slider)

	# 最大弹飞距离
	var dist_lbl := Label.new()
	dist_lbl.text = "核心最大弹飞距离 (Max Launch Distance): %.1fm" % max_launch_dist
	dist_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(dist_lbl)

	var dist_slider := HSlider.new()
	dist_slider.min_value = 2.0
	dist_slider.max_value = 15.0
	dist_slider.step = 0.5
	dist_slider.value = max_launch_dist
	dist_slider.value_changed.connect(func(v: float):
		max_launch_dist = v
		dist_lbl.text = "核心最大弹飞距离 (Max Launch Distance): %.1fm" % v
		on_changed.call("max_launch_dist", v)
	)
	container.add_child(dist_slider)

	# 最大浮空高度
	var h_lbl := Label.new()
	h_lbl.text = "核心最大浮空高度 (Max Launch Height): %.1fm" % max_launch_height
	h_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(h_lbl)

	var h_slider := HSlider.new()
	h_slider.min_value = 1.0
	h_slider.max_value = 6.0
	h_slider.step = 0.2
	h_slider.value = max_launch_height
	h_slider.value_changed.connect(func(v: float):
		max_launch_height = v
		h_lbl.text = "核心最大浮空高度 (Max Launch Height): %.1fm" % v
		on_changed.call("max_launch_height", v)
	)
	container.add_child(h_slider)

	# 倒地时长
	var fall_lbl := Label.new()
	fall_lbl.text = "摔倒倒地时长 (Fall Duration): %.1fs" % fall_duration
	fall_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(fall_lbl)

	var fall_slider := HSlider.new()
	fall_slider.min_value = 0.8
	fall_slider.max_value = 3.5
	fall_slider.step = 0.1
	fall_slider.value = fall_duration
	fall_slider.value_changed.connect(func(v: float):
		fall_duration = v
		fall_lbl.text = "摔倒倒地时长 (Fall Duration): %.1fs" % v
		on_changed.call("fall_duration", v)
	)
	container.add_child(fall_slider)

	# 说明面板
	var tip_panel := PanelContainer.new()
	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.12, 0.08, 0.05, 0.90)
	t_style.set_corner_radius_all(6)
	t_style.set_border_width_all(1)
	t_style.border_color = Color(0.75, 0.55, 0.35, 0.65)
	t_style.set_content_margin_all(8)
	tip_panel.add_theme_stylebox_override("panel", t_style)
	container.add_child(tip_panel)

	var tip_vbox := VBoxContainer.new()
	tip_vbox.add_theme_constant_override("separation", 4)
	tip_panel.add_child(tip_vbox)

	var tip1 := Label.new()
	tip1.text = "🚀 空中起跳重砸自动校准地面，重重贯穿砸向真实地表"
	tip1.add_theme_font_size_override("font_size", 11)
	tip1.modulate = Color(1.0, 0.85, 0.6)
	tip_vbox.add_child(tip1)

	var tip2 := Label.new()
	tip2.text = "🌋 深褐厚重泥土与银白矿纹岩柱破土向外崩散，伴随真实局部空间折射震荡"
	tip2.add_theme_font_size_override("font_size", 11)
	tip2.modulate = Color(0.9, 0.85, 0.95)
	tip_vbox.add_child(tip2)

	var tip3 := Label.new()
	tip3.text = "💥 纯正 3D 棱角碎石暴雨翻滚，地裂与突岩长效持续同频消散"
	tip3.add_theme_font_size_override("font_size", 11)
	tip3.modulate = Color(0.85, 0.85, 0.85)
	tip_vbox.add_child(tip3)


## Detects the real ground surface elevation directly beneath the caster using downward physics raycast.
func _find_ground_y(caster: CharacterBody3D, from_pos: Vector3) -> float:
	var world := caster.get_world_3d()
	if world != null:
		var space_state := world.direct_space_state
		if space_state != null:
			var query := PhysicsRayQueryParameters3D.create(
				from_pos + Vector3.UP * 1.0,
				from_pos + Vector3.DOWN * 80.0
			)
			query.exclude = [caster.get_rid()]
			var hit := space_state.intersect_ray(query)
			if not hit.is_empty() and hit.has("position"):
				return float(hit.position.y)

	# Fallback: if caster is on floor or near ground level
	if caster.is_on_floor():
		return caster.global_position.y
	return 0.0


func _execute_slam(caster: CharacterBody3D, parent: Node) -> Dictionary:
	var start_pos := caster.global_position
	var fwd := caster.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 0.01:
		fwd = fwd.normalized()
	else:
		fwd = Vector3.FORWARD

	# Probe true ground elevation directly below the character
	var ground_y := _find_ground_y(caster, start_pos)

	# Calculate apex and true ground landing coordinates
	var landing_pos := start_pos + fwd * 1.5
	landing_pos.y = ground_y

	var apex_pos := start_pos + fwd * 0.8
	apex_pos.y = maxf(start_pos.y + 1.8, ground_y + leap_height)

	var raw_ch: Variant = caster.get("character")
	if raw_ch != null and is_instance_valid(raw_ch) and raw_ch.has_method("play"):
		raw_ch.call("play", "jump", 0.08)

	AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg", 0.9)

	var tw := caster.create_tween()
	tw.tween_property(caster, "global_position", apex_pos, leap_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.04)
	tw.tween_callback(func():
		if is_instance_valid(caster):
			var r_ch: Variant = caster.get("character")
			if r_ch != null and is_instance_valid(r_ch) and r_ch.has_method("play"):
				r_ch.call("play", "hard_landing", 0.05)
	)
	tw.tween_property(caster, "global_position", landing_pos, slam_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		if is_instance_valid(caster) and is_instance_valid(parent):
			_on_slam_impact(caster, landing_pos, parent)
	)

	return {
		"success": true,
		"skill_id": get_id(),
		"from_pos": start_pos,
		"target_pos": landing_pos,
		"ground_y": ground_y,
		"slam_radius": slam_radius,
		"leap_height": leap_height,
		"max_launch_dist": max_launch_dist
	}


func _on_slam_impact(caster: CharacterBody3D, impact_pos: Vector3, parent: Node) -> void:
	AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg", 1.4)

	_spawn_fracture_vfx(impact_pos, parent)
	_apply_slam_impact(caster, impact_pos)


func _spawn_fracture_vfx(impact_pos: Vector3, parent: Node) -> void:
	var vfx := Node3D.new()
	vfx.name = "GroundSlamFractureVFX"
	parent.add_child(vfx)
	vfx.global_position = impact_pos

	_ensure_cached_resources()

	# 1. Realistic Subterranean Glowing Magma Fissure Mesh (sustained with rocks)
	_spawn_ground_fissure(vfx, slam_radius)

	# 2. Deep Soil Brown & Silver-White Jutting Rock Pillars that thrust up and tilt/scatter outward
	_spawn_jutting_rock_spikes(vfx, slam_radius)

	# 3. Dynamic 3D Jagged Rock & Stone Debris Explosion (Zero flat billboard squares)
	_spawn_exploding_shattered_rocks(vfx, slam_radius)

	# 4. Localized 3D Spatial Refraction Distortion Shockwave (Bends & shakes screen/space)
	_spawn_spatial_distortion_dome(vfx, slam_radius)

	# 5. Earth Blast Sonic Shockwave Ring (Deep Earth Brown & Silver Dust)
	_spawn_earth_shockwave_ring(vfx, slam_radius)

	# 6. Dynamic Earthen Impact Light
	_spawn_impact_light(vfx, slam_radius)


## Ensures static meshes and materials are initialized once without runtime re-allocation.
static func _ensure_cached_resources() -> void:
	if _cached_rock_mesh == null:
		_cached_rock_mesh = PrismMesh.new()
		_cached_rock_mesh.size = Vector3(0.40, 0.65, 0.35)

	if _cached_spike_mesh == null:
		_cached_spike_mesh = CylinderMesh.new()
		_cached_spike_mesh.top_radius = 0.10
		_cached_spike_mesh.bottom_radius = 0.48
		_cached_spike_mesh.height = 1.95
		_cached_spike_mesh.radial_segments = 5

	if _cached_rock_mat == null:
		_cached_rock_mat = StandardMaterial3D.new()
		_cached_rock_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_cached_rock_mat.albedo_color = Color(0.25, 0.15, 0.10)
		_cached_rock_mat.roughness = 0.82
		_cached_rock_mat.emission_enabled = true
		_cached_rock_mat.emission = Color(0.85, 0.90, 1.0)
		_cached_rock_mat.emission_energy_multiplier = 0.40


## Spawns the ground fissure with radiant subterranean earth glow bleeding naturally through cracks.
func _spawn_ground_fissure(vfx: Node3D, radius: float) -> void:
	var fissure := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(radius * 2.2, radius * 2.2)
	fissure.mesh = pm
	fissure.position.y = 0.03

	var mat := ShaderMaterial.new()
	mat.shader = GroundFractureGlowShader
	mat.set_shader_parameter("glow_core", Color(1.30, 1.32, 1.40, 1.0))
	mat.set_shader_parameter("glow_amber", Color(0.92, 0.48, 0.14, 1.0))
	mat.set_shader_parameter("glow_crimson", Color(0.50, 0.10, 0.04, 1.0))
	mat.set_shader_parameter("crust_color", Color(0.22, 0.13, 0.08, 0.95))
	mat.set_shader_parameter("heat_intensity", 1.15)
	mat.set_shader_parameter("crack_progress", 0.0)
	mat.set_shader_parameter("fade", 1.0)
	VfxTextures.bind(mat, "crack_tex", VfxTextures.GROUND_CRACK, "", 1.0)
	fissure.material_override = mat
	vfx.add_child(fissure)

	# Tearing open, sustaining across SUSTAIN_DURATION, then slowly fading away together with rocks
	var tw := vfx.create_tween()
	tw.tween_property(mat, "shader_parameter/crack_progress", 1.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(SUSTAIN_DURATION)
	tw.tween_property(mat, "shader_parameter/fade", 0.0, 0.85).set_ease(Tween.EASE_IN)
	tw.tween_callback(fissure.queue_free)


## Spawns protruding deep brown & silver-white mineral rock spikes that thrust up and tilt/scatter outward.
func _spawn_jutting_rock_spikes(vfx: Node3D, radius: float) -> void:
	var spike_root := Node3D.new()
	vfx.add_child(spike_root)

	var num_spikes := 8
	for i in range(num_spikes):
		var base_angle := float(i) * (TAU / float(num_spikes)) + randf_range(-0.16, 0.16)
		var ring_r := radius * randf_range(0.38, 0.65)
		var local_pos := Vector3(cos(base_angle) * ring_r, 0.0, sin(base_angle) * ring_r)

		var spike_pivot := Node3D.new()
		spike_pivot.position = local_pos
		spike_root.add_child(spike_pivot)

		# Jagged tapered angular 3D rock mesh
		var spike_mesh := MeshInstance3D.new()
		spike_mesh.mesh = _cached_spike_mesh
		spike_mesh.material_override = _cached_rock_mat
		spike_mesh.position.y = 0.75
		spike_mesh.rotation = Vector3(randf_range(-0.15, 0.15), randf_range(0.0, TAU), randf_range(-0.15, 0.15))
		spike_pivot.add_child(spike_mesh)

		# Direction pointing radially outward from epicenter
		var out_dir := local_pos.normalized()
		var tilt_axis := Vector3(-out_dir.z, 0.0, out_dir.x).normalized()
		var tilt_target := Basis(tilt_axis, deg_to_rad(randf_range(36.0, 52.0)))

		# Long-sustained 3-Phase Animation: Thrust Up -> Tilt Outward -> Hold with Fissure -> Sink Together
		var tw := spike_pivot.create_tween()
		spike_pivot.position.y = -1.6
		spike_pivot.scale = Vector3(0.2, 0.2, 0.2)

		# Phase 1: Erupt up out of ground
		tw.set_parallel(true)
		tw.tween_property(spike_pivot, "position:y", 0.0, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(spike_pivot, "scale", Vector3(1.0, 1.0, 1.0), 0.10).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

		# Phase 2: Tilt and push outward with the shockwave
		tw.chain().set_parallel(true)
		tw.tween_property(spike_pivot, "transform:basis", Transform3D(tilt_target, Vector3.ZERO).basis, 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(spike_pivot, "position", local_pos + out_dir * randf_range(0.7, 1.3), 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

		# Phase 3: Sustain duration matching the ground fissure, then smoothly sink and fade
		tw.chain().tween_interval(SUSTAIN_DURATION)
		tw.chain().set_parallel(true)
		tw.tween_property(spike_pivot, "position:y", -1.8, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(spike_pivot, "scale", Vector3(0.1, 0.1, 0.1), 0.85).set_ease(Tween.EASE_IN)

	var root_tw := spike_root.create_tween()
	root_tw.tween_interval(SUSTAIN_DURATION + 1.2)
	root_tw.tween_callback(spike_root.queue_free)


## Spawns realistic 3D jagged rock fragments exploding outward into the air with heavy gravity and tumbling rotation.
func _spawn_exploding_shattered_rocks(vfx: Node3D, _radius: float) -> void:
	var rock_particles := CPUParticles3D.new()
	rock_particles.position.y = 0.20
	rock_particles.amount = 32
	rock_particles.lifetime = 1.2
	rock_particles.one_shot = true
	rock_particles.explosiveness = 0.98

	# Upward conical explosion
	rock_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	rock_particles.emission_sphere_radius = 0.6
	rock_particles.direction = Vector3(0.0, 1.0, 0.0)
	rock_particles.spread = 70.0
	rock_particles.initial_velocity_min = 10.0
	rock_particles.initial_velocity_max = 20.0
	rock_particles.gravity = Vector3(0.0, -32.0, 0.0)

	# High tumbling angular rotation
	rock_particles.angular_velocity_min = 14.0
	rock_particles.angular_velocity_max = 35.0
	rock_particles.scale_amount_min = 0.20
	rock_particles.scale_amount_max = 0.55

	rock_particles.mesh = _cached_rock_mesh
	rock_particles.material_override = _cached_rock_mat

	vfx.add_child(rock_particles)
	rock_particles.emitting = true


## Spawns the localized 3D screen refraction spatial distortion shockwave dome that violently shakes & bends surrounding 3D space.
func _spawn_spatial_distortion_dome(vfx: Node3D, radius: float) -> void:
	var warp_dome := MeshInstance3D.new()
	var dome_mesh := SphereMesh.new()
	dome_mesh.radius = radius * 0.95
	dome_mesh.height = radius * 0.95
	dome_mesh.is_hemisphere = true
	dome_mesh.radial_segments = 24
	dome_mesh.rings = 12
	warp_dome.mesh = dome_mesh
	warp_dome.position.y = 0.02

	var mat := ShaderMaterial.new()
	mat.shader = EarthSpatialDistortionShader
	mat.set_shader_parameter("distortion_strength", 0.065)
	mat.set_shader_parameter("rim_tint", Color(0.88, 0.92, 0.98, 0.35))
	mat.set_shader_parameter("fade", 1.0)
	VfxTextures.bind(mat, "noise_tex", VfxTextures.WIND_SLASH, "", 1.0)
	warp_dome.material_override = mat
	vfx.add_child(warp_dome)

	var tw := vfx.create_tween().set_parallel(true)
	tw.tween_property(warp_dome, "scale", Vector3(1.35, 1.5, 1.35), 0.38).from(Vector3(0.1, 0.1, 0.1)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "shader_parameter/fade", 0.0, 0.38).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(warp_dome.queue_free)


## Spawns the earth blast ground sonic shockwave ring (deep brown earth dust & silver condensation ring).
func _spawn_earth_shockwave_ring(vfx: Node3D, radius: float) -> void:
	var ground_ring := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(radius * 2.3, radius * 2.3)
	ground_ring.mesh = pm
	ground_ring.position.y = 0.05

	var ring_mat := ShaderMaterial.new()
	ring_mat.shader = SonicRingShader
	ring_mat.set_shader_parameter("ring_color", Color(0.42, 0.28, 0.18, 0.85))
	ring_mat.set_shader_parameter("fade", 1.0)
	ring_mat.set_shader_parameter("thickness", 0.20)
	VfxTextures.bind(ring_mat, "ring_tex", VfxTextures.SHOCKWAVE_RING, "tex_mix", 1.0)
	ground_ring.material_override = ring_mat
	vfx.add_child(ground_ring)

	var tw := vfx.create_tween().set_parallel(true)
	tw.tween_property(ground_ring, "scale", Vector3(1.25, 1.0, 1.25), 0.40).from(Vector3(0.1, 1.0, 0.1)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring_mat, "shader_parameter/fade", 0.0, 0.40).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(ground_ring.queue_free)


## Spawns an explosive earthy amber/white impact omni light.
func _spawn_impact_light(vfx: Node3D, radius: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.45)
	light.light_energy = 5.0
	light.omni_range = radius * 2.2
	light.position = Vector3.UP * 1.6
	vfx.add_child(light)

	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(light.queue_free)


func _apply_slam_impact(caster: CharacterBody3D, impact_pos: Vector3) -> void:
	if caster == null or not is_instance_valid(caster) or not caster.is_inside_tree():
		return
	var tree := caster.get_tree()
	if tree == null:
		return

	var center := impact_pos
	var radius := maxf(slam_radius, 0.5)

	# High performance entity lookup avoiding whole scene-tree recursive search
	var candidates: Array[Node] = tree.get_nodes_in_group("characters")
	if candidates.is_empty():
		var scene_root := tree.current_scene
		if scene_root != null:
			for ch in scene_root.find_children("*", "CharacterBody3D", true, false):
				candidates.append(ch)
			for ch in scene_root.find_children("*", "DummyTarget", true, false):
				candidates.append(ch)

	for b in candidates:
		if b == null or not is_instance_valid(b):
			continue
		if not (b is CharacterBody3D):
			continue
		var cb := b as CharacterBody3D
		if cb == caster or cb.name == "Ground":
			continue

		var to := cb.global_position - center
		to.y = 0.0
		var dist := to.length()
		if dist > radius:
			continue

		# Non-linear graduated factor: closest to epicenter gets max launch, edge gets minor toss
		var t := clampf(dist / radius, 0.0, 1.0)
		var launch_factor := pow(1.0 - t * 0.82, 1.3)

		var push_dir := to.normalized() if dist > 0.08 else -cb.global_transform.basis.z
		_launch_and_knockdown(cb, push_dir, launch_factor, fall_duration)


func _launch_and_knockdown(target: CharacterBody3D, push_dir: Vector3, launch_factor: float, duration: float) -> void:
	if target == null or not is_instance_valid(target):
		return

	var t_id := target.get_instance_id()
	if _active_knockdowns.has(t_id):
		var prev_tw: Tween = _active_knockdowns[t_id].get("tween")
		if prev_tw != null and prev_tw.is_valid():
			prev_tw.kill()

	var raw_ch: Variant = target.get("character")
	var ch: Node = null
	if raw_ch != null and is_instance_valid(raw_ch) and (raw_ch is Node):
		ch = raw_ch as Node

	var raw_tree: Variant = target.get("_tree")
	var anim_tree: AnimationTree = null
	if raw_tree != null and is_instance_valid(raw_tree) and (raw_tree is AnimationTree):
		anim_tree = raw_tree as AnimationTree

	# 1. Completely disable controller physics processing
	target.set_physics_process(false)
	target.velocity = Vector3.ZERO

	# 2. Disable AnimationTree during flight and ground tumble
	if anim_tree != null and is_instance_valid(anim_tree):
		anim_tree.active = false

	# 3. Trigger knockdown reaction clip
	if ch != null and is_instance_valid(ch) and ch.has_method("play"):
		ch.call("play", "hit_knockback", 0.08)

	# 4. Calculate graduated launch parabolic flight
	var start_pos := target.global_position
	var h_dist := max_launch_dist * launch_factor
	var v_height := max_launch_height * launch_factor
	var air_time := lerpf(0.32, 0.58, launch_factor)
	var half_air := air_time * 0.5

	var target_end_pos := start_pos + push_dir * h_dist
	target_end_pos.y = start_pos.y
	var mid_pos := (start_pos + target_end_pos) * 0.5
	var apex_y := start_pos.y + v_height

	# 5. Single Chained Sequence: Parabolic Arc -> Ground Hold -> Getup -> Locomotion Restore
	var tw := target.create_tween()
	_active_knockdowns[t_id] = { "actor": target, "tween": tw }

	# Upward parabola half
	tw.set_parallel(true)
	tw.tween_property(target, "global_position:x", mid_pos.x, half_air).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(target, "global_position:z", mid_pos.z, half_air).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(target, "global_position:y", apex_y, half_air).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Downward parabola half
	tw.chain().set_parallel(true)
	tw.tween_property(target, "global_position:x", target_end_pos.x, half_air).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(target, "global_position:z", target_end_pos.z, half_air).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(target, "global_position:y", start_pos.y, half_air).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Lie on ground
	tw.chain().tween_interval(duration)

	# Play getup animation
	tw.chain().tween_callback(func():
		if is_instance_valid(ch) and ch.has_method("play"):
			ch.call("play", "lay_to_idle", 0.15)
	)
	tw.tween_interval(1.3)

	# Fully restore player control, physics process, state, and AnimationTree
	tw.chain().tween_callback(func():
		_active_knockdowns.erase(t_id)
		if is_instance_valid(target):
			target.set("state", 0)
			target.velocity = Vector3.ZERO
			target.set_physics_process(true)
		if is_instance_valid(anim_tree):
			anim_tree.active = true
	)


## Preloads all audio files and textures used by Skill 9 to prevent any runtime hitching.
## reset_state(): drops knockdown bookkeeping. _cached_* are asset caches, kept.
func reset_state() -> void:
	_active_knockdowns.clear()


func preload_assets() -> void:
	AudioManagerScript.preload_sounds([
		"res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg"
	])
	_ensure_cached_resources()
	# Pre-cache and warmup textures
	VfxTextures.get_tex(VfxTextures.GROUND_CRACK)
	VfxTextures.get_tex(VfxTextures.WIND_SLASH)
	VfxTextures.get_tex(VfxTextures.SHOCKWAVE_RING)


## Returns all warmup materials with shader parameters and textures bound for GPU pipeline warmup.
func get_warmup_materials() -> Array:
	_ensure_cached_resources()

	var m_warp := ShaderMaterial.new()
	m_warp.shader = EarthSpatialDistortionShader
	VfxTextures.bind(m_warp, "noise_tex", VfxTextures.WIND_SLASH, "", 1.0)

	var m_ring := ShaderMaterial.new()
	m_ring.shader = SonicRingShader
	VfxTextures.bind(m_ring, "ring_tex", VfxTextures.SHOCKWAVE_RING, "tex_mix", 1.0)

	var m_fissure := ShaderMaterial.new()
	m_fissure.shader = GroundFractureGlowShader
	VfxTextures.bind(m_fissure, "crack_tex", VfxTextures.GROUND_CRACK, "", 1.0)

	var m_dome := ShaderMaterial.new()
	m_dome.shader = ShockwaveDomeShader
	VfxTextures.bind(m_dome, "noise_tex", VfxTextures.WIND_SLASH, "noise_mix", 0.4)

	return [m_warp, m_ring, m_fissure, m_dome, _cached_rock_mat]


func dispel_actor(actor: CharacterBody3D) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var t_id := actor.get_instance_id()
	if not _active_knockdowns.has(t_id):
		return
	var entry: Dictionary = _active_knockdowns[t_id]
	var tw: Tween = entry.get("tween")
	if tw != null and tw.is_valid():
		tw.kill()
	_active_knockdowns.erase(t_id)

	actor.set_physics_process(true)
	actor.velocity = Vector3.ZERO
	actor.set("state", 0)

	var raw_tree: Variant = actor.get("_tree")
	if raw_tree != null and is_instance_valid(raw_tree) and (raw_tree is AnimationTree):
		var anim_tree := raw_tree as AnimationTree
		anim_tree.active = true
