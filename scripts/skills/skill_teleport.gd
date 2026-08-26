extends "res://scripts/skills/skill_base.gd"
## 空间跃迁·超音速破风突进 (Supersonic Spatial Dash).
## 纯数学双重交织螺旋能量丝带（无黑底贴图瑕疵，后端削薄修长），
## 起点保留赛博残影，终点空灵高亮奇点与指数级缩小景深无限隧道环。

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const SupersonicStreamShader = preload("res://shaders/supersonic_stream.gdshader")
const VanishingTunnelShader = preload("res://shaders/vanishing_tunnel.gdshader")
const CyberGhostEffectScript = preload("res://scripts/vfx/cyber_ghost_effect.gd")

var distance: float = 6.0
var wind_speed: float = 28.0

func get_id() -> String:
	return "teleport"

func get_name() -> String:
	return "⚡ 瞬移 (超音速时空跃迁)"

func get_title() -> String:
	return "⚡ 瞬移配置 (SUPERSONIC SPATIAL DASH)"

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

	# 1. 起点：保留角色周围微妙发光的赛博轮廓残影（已去除地面法阵）
	if vfx_parent != null and is_instance_valid(vfx_parent):
		CyberGhostEffectScript.spawn_at_character(caster, vfx_parent, 0.38, Color(0.15, 0.85, 1.5, 0.85), 0.4)

	# 2. 转向并瞬移角色
	if dir.length_squared() > 0.001:
		caster.rotation.y = atan2(dir.x, dir.z)
	caster.global_position = target_pos
	caster.velocity = Vector3.ZERO

	# 3. 改进路径：修长修削的纯数学螺旋能量带 + 散乱微光粒子 + 终点空灵奇点时空隧道
	if actual_dist > 0.3 and vfx_parent != null and is_instance_valid(vfx_parent):
		_spawn_supersonic_breakthrough(from_pos, target_pos, dir, actual_dist, vfx_parent, wind_speed)

	# 4. 镜头动态微冲击
	_trigger_camera_punch(caster)

	# 5. 音效
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


## 2 & 3 & 4. 削薄修长螺旋能量带 + 散乱粒子 + 终点空灵奇点与无限隧道
static func _spawn_supersonic_breakthrough(start_pos: Vector3, end_pos: Vector3, dir: Vector3, dist: float, parent: Node, w_spd: float) -> void:
	var chest_h := Vector3.UP * 0.95
	var tip_lead_pos := end_pos + chest_h + dir * 0.2

	var cone_height := minf(dist * 1.02 + 0.8, 6.5)

	# A1. 外层主螺旋能量带 (Outer Helical Spiral Ribbon Stream - 削薄修长流线)
	var outer_cone := CylinderMesh.new()
	outer_cone.top_radius = 0.04
	outer_cone.bottom_radius = 0.48 # 显著削薄后端半径
	outer_cone.height = cone_height
	outer_cone.radial_segments = 32
	outer_cone.rings = 4
	outer_cone.cap_top = false
	outer_cone.cap_bottom = false

	var outer_node := MeshInstance3D.new()
	outer_node.name = "SupersonicSpiralOuter"
	outer_node.mesh = outer_cone

	var outer_mat := ShaderMaterial.new()
	outer_mat.shader = SupersonicStreamShader
	outer_mat.set_shader_parameter("color_start_cyan", Color(0.05, 0.90, 1.8, 0.95))
	outer_mat.set_shader_parameter("color_mid_blue", Color(0.12, 0.38, 1.4, 0.88))
	outer_mat.set_shader_parameter("color_end_purple", Color(0.65, 0.12, 1.15, 0.8))
	outer_mat.set_shader_parameter("spiral_arms", 4.0)
	outer_mat.set_shader_parameter("twist_turns", 3.2)
	outer_mat.set_shader_parameter("roll_speed", w_spd * 0.8)
	outer_mat.set_shader_parameter("streak_sharpness", 4.0)
	outer_mat.set_shader_parameter("fade", 1.0)
	outer_node.material_override = outer_mat
	parent.add_child(outer_node)

	_align_cylinder_to_forward(outer_node, dir)
	outer_node.global_position = tip_lead_pos - dir * (cone_height * 0.5)

	# A2. 内层反向交织细螺旋光丝 (Inner Fast Counter-Twisting Spiral)
	var inner_cone := CylinderMesh.new()
	inner_cone.top_radius = 0.02
	inner_cone.bottom_radius = 0.28
	inner_cone.height = cone_height * 1.04
	inner_cone.radial_segments = 24
	inner_cone.rings = 3
	inner_cone.cap_top = false
	inner_cone.cap_bottom = false

	var inner_node := MeshInstance3D.new()
	inner_node.name = "SupersonicSpiralInner"
	inner_node.mesh = inner_cone

	var inner_mat := ShaderMaterial.new()
	inner_mat.shader = SupersonicStreamShader
	inner_mat.set_shader_parameter("color_start_cyan", Color(0.3, 0.95, 2.0, 1.0))
	inner_mat.set_shader_parameter("color_mid_blue", Color(0.2, 0.5, 1.6, 0.9))
	inner_mat.set_shader_parameter("color_end_purple", Color(0.8, 0.25, 1.4, 0.85))
	inner_mat.set_shader_parameter("spiral_arms", 3.0)
	inner_mat.set_shader_parameter("twist_turns", -2.6)
	inner_mat.set_shader_parameter("roll_speed", w_spd * 1.2)
	inner_mat.set_shader_parameter("streak_sharpness", 5.5)
	inner_mat.set_shader_parameter("fade", 1.0)
	inner_node.material_override = inner_mat
	parent.add_child(inner_node)

	_align_cylinder_to_forward(inner_node, dir)
	inner_node.global_position = tip_lead_pos - dir * (cone_height * 0.52)

	# 双重螺旋带缓动淡出动画
	var tw_stream := outer_node.create_tween().set_parallel(true)
	tw_stream.tween_property(outer_node, "scale", Vector3(1.3, 1.15, 1.3), 0.20)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw_stream.tween_property(inner_node, "scale", Vector3(1.25, 1.2, 1.25), 0.18)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw_stream.tween_method(func(v: float):
		if is_instance_valid(outer_mat):
			outer_mat.set_shader_parameter("fade", v)
		if is_instance_valid(inner_mat):
			inner_mat.set_shader_parameter("fade", v)
	, 1.0, 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw_stream.chain().tween_callback(func():
		if is_instance_valid(outer_node):
			outer_node.queue_free()
		if is_instance_valid(inner_node):
			inner_node.queue_free()
	)

	# B. 散乱流动能量光点粒子 (Floating & Drifting Energy Motes)
	_spawn_drifting_motes(start_pos + chest_h, end_pos + chest_h, dir, dist, parent)

	# C. 终点：空灵高亮能量消失点核心 + 指数级衰减景深软环 (Vanishing Point Singularity & Infinite Depth Rings)
	_spawn_vanishing_portal(tip_lead_pos, dir, parent)


## 散落能量粒子
static func _spawn_drifting_motes(from_p: Vector3, to_p: Vector3, dir: Vector3, dist: float, parent: Node) -> void:
	var mote_count := int(clampf(dist * 3.5, 8.0, 24.0))
	for i in range(mote_count):
		var frac := float(i) / float(mote_count)
		var base_p := from_p.lerp(to_p, frac)
		var jitter := Vector3(randf_range(-0.25, 0.25), randf_range(-0.25, 0.25), randf_range(-0.25, 0.25))
		var p := base_p + jitter

		var mote := MeshInstance3D.new()
		var qm := QuadMesh.new()
		var sz := randf_range(0.08, 0.20)
		qm.size = Vector2(sz, sz * 2.0)
		mote.mesh = qm

		var m_mat := StandardMaterial3D.new()
		m_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		var mote_col := Color(0.1, 0.85, 1.5, 0.9).lerp(Color(0.7, 0.2, 1.2, 0.8), frac)
		m_mat.albedo_color = mote_col
		m_mat.albedo_texture = VfxTextures.get_tex(VfxTextures.FLASH_GLOW)
		mote.material_override = m_mat
		parent.add_child(mote)
		mote.global_position = p

		var tw := mote.create_tween().set_parallel(true)
		var drift_offset := -dir * randf_range(0.4, 1.2) + Vector3(randf_range(-0.15, 0.15), randf_range(-0.1, 0.25), randf_range(-0.15, 0.15))
		tw.tween_property(mote, "global_position", p + drift_offset, 0.26)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(m_mat, "albedo_color:a", 0.0, 0.26).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(mote.queue_free)


## 终点空灵消失点核心与指数级缩小景深无限隧道环
static func _spawn_vanishing_portal(lead_pos: Vector3, dir: Vector3, parent: Node) -> void:
	var fwd := dir.normalized()
	if fwd.length_squared() < 0.001:
		fwd = Vector3.FORWARD
	var temp_up := Vector3.UP if absf(fwd.y) < 0.99 else Vector3.FORWARD
	var right := temp_up.cross(fwd).normalized()
	var up := fwd.cross(right).normalized()
	var portal_basis := Basis(right, up, fwd)

	# 1. 核心高亮度空灵能量消失点 (Singularity Core Flare)
	var core_node := MeshInstance3D.new()
	var core_quad := QuadMesh.new()
	core_quad.size = Vector2(1.8, 1.8)
	core_node.mesh = core_quad
	core_node.global_transform = Transform3D(portal_basis, lead_pos)

	var core_mat := ShaderMaterial.new()
	core_mat.shader = VanishingTunnelShader
	core_mat.set_shader_parameter("is_singularity", true)
	core_mat.set_shader_parameter("core_color", Color(2.2, 2.5, 3.0, 1.0))
	core_mat.set_shader_parameter("ring_cyan", Color(0.1, 0.85, 1.6, 0.9))
	core_mat.set_shader_parameter("fade", 1.0)
	core_node.material_override = core_mat
	parent.add_child(core_node)

	var tw_core := core_node.create_tween().set_parallel(true)
	tw_core.tween_property(core_node, "scale", Vector3(1.4, 1.4, 1.4), 0.18).from(Vector3(0.2, 0.2, 0.2))\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw_core.tween_method(func(v: float):
		if is_instance_valid(core_mat):
			core_mat.set_shader_parameter("fade", v)
	, 1.0, 0.0, 0.25).set_ease(Tween.EASE_IN)
	tw_core.chain().tween_callback(core_node.queue_free)

	# 2. 指数级缩小且融于景深的能量软环 (Exponential Depth Tunnel Rings)
	var ring_scales := [1.25, 0.82, 0.52, 0.32]
	var ring_offsets := [0.0, 0.35, 0.65, 0.90]

	for i in range(ring_scales.size()):
		var s: float = ring_scales[i]
		var offset_dist: float = ring_offsets[i]
		var r_pos := lead_pos + fwd * offset_dist

		var ring_node := MeshInstance3D.new()
		var r_quad := QuadMesh.new()
		r_quad.size = Vector2(2.2 * s, 2.2 * s)
		ring_node.mesh = r_quad
		ring_node.global_transform = Transform3D(portal_basis, r_pos)

		var r_mat := ShaderMaterial.new()
		r_mat.shader = VanishingTunnelShader
		r_mat.set_shader_parameter("is_singularity", false)
		r_mat.set_shader_parameter("ring_radius", 0.52)
		r_mat.set_shader_parameter("ring_softness", 0.16)
		r_mat.set_shader_parameter("ring_cyan", Color(0.1, 0.85, 1.6, 0.85 * (1.0 - float(i) * 0.18)))
		r_mat.set_shader_parameter("ring_violet", Color(0.65, 0.15, 1.2, 0.65 * (1.0 - float(i) * 0.18)))
		r_mat.set_shader_parameter("pulse_speed", 4.0 + float(i) * 1.5)
		r_mat.set_shader_parameter("fade", 1.0)
		ring_node.material_override = r_mat
		parent.add_child(ring_node)

		var delay: float = float(i) * 0.025
		var tw_ring := ring_node.create_tween()
		if delay > 0.0:
			tw_ring.tween_interval(delay)
		tw_ring.set_parallel(true)
		tw_ring.tween_property(ring_node, "scale", Vector3(1.15, 1.15, 1.15), 0.22).from(Vector3(0.4, 0.4, 0.4))\
			.set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
		tw_ring.tween_method(func(v: float):
			if is_instance_valid(r_mat):
				r_mat.set_shader_parameter("fade", v)
		, 1.0, 0.0, 0.22).set_ease(Tween.EASE_IN)
		tw_ring.chain().tween_callback(ring_node.queue_free)


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
	m1.shader = SupersonicStreamShader

	var m2 := ShaderMaterial.new()
	m2.shader = VanishingTunnelShader

	var m3 := ShaderMaterial.new()
	m3.shader = CyberGhostEffect.SHADER_RES

	return [m1, m2, m3]
