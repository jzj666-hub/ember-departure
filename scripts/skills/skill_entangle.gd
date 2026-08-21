extends "res://scripts/skills/skill_base.gd"
## Realistic Bioluminescent Thorny Vine Entanglement Skill.
## Procedurally generated 3D coiling thorn vines, root expansion, physical lock & seamless release.

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const VineGrowthShader = preload("res://shaders/vine_growth.gdshader")
const SigilRingShader = preload("res://shaders/sigil_ring.gdshader")

var search_radius: float = 12.0
var bind_duration: float = 3.5

# Active immobilization tracking: actor_id -> Dictionary
static var _active_binds: Dictionary = {}

func get_id() -> String:
	return "entangle"

func get_name() -> String:
	return "🌿 荆棘缠绕 (虚空藤蔓锁死)"

func get_title() -> String:
	return "🌿 荆棘缠绕配置 (THORNY VINE BIND)"

func get_params() -> Dictionary:
	return {
		"search_radius": search_radius,
		"bind_duration": bind_duration
	}

func set_param(key: String, value: Variant) -> void:
	match key:
		"search_radius": search_radius = float(value)
		"bind_duration": bind_duration = float(value)

func cast(caster: CharacterBody3D, _intent_dir: Vector3, vfx_parent: Node, _is_spectator: bool = false) -> Dictionary:
	if caster == null or not is_instance_valid(caster):
		return {}

	# 1. Search for nearest enemy within search_radius
	var target_actor := _find_nearest_target(caster, search_radius)
	if target_actor == null:
		# No target in range -> Fail to cast
		AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg", 0.8)
		return {
			"success": false,
			"skill_id": get_id(),
			"reason": "no_target"
		}

	# 2. Align caster facing direction towards target
	var to_target := (target_actor.global_position - caster.global_position)
	to_target.y = 0.0
	if to_target.length_squared() > 0.01:
		caster.rotation.y = atan2(to_target.x, to_target.z)

	# 3. Apply physical position & velocity immobilization
	_immobilize_target(target_actor, bind_duration)

	# 4. Spawn 3D Coiling Thorn Vines & Root Spores
	if vfx_parent != null and is_instance_valid(vfx_parent):
		_spawn_vine_entangle_vfx(caster, target_actor, bind_duration, vfx_parent)

	# 5. Play vine eruption sound
	AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/knifeSlice.ogg", 1.8)

	return {
		"success": true,
		"skill_id": get_id(),
		"from_pos": caster.global_position,
		"target_pos": target_actor.global_position,
		"target_actor": target_actor,
		"search_radius": search_radius,
		"bind_duration": bind_duration
	}

func replay(caster: CharacterBody3D, record: Dictionary, vfx_parent: Node) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	cast(caster, Vector3.ZERO, vfx_parent, true)

func get_replay_hold_time(record: Dictionary) -> float:
	var dur: float = float(record.get("bind_duration", bind_duration))
	return maxf(dur + 0.5, 2.0)

func build_config_panel(container: VBoxContainer, on_changed: Callable) -> void:
	# 索敌搜寻半径
	var radius_lbl := Label.new()
	radius_lbl.text = "索敌搜寻半径 (Search Radius): %.1fm" % search_radius
	radius_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(radius_lbl)

	var radius_slider := HSlider.new()
	radius_slider.min_value = 3.0
	radius_slider.max_value = 25.0
	radius_slider.step = 0.5
	radius_slider.value = search_radius
	radius_slider.value_changed.connect(func(v: float):
		search_radius = v
		radius_lbl.text = "索敌搜寻半径 (Search Radius): %.1fm" % v
		on_changed.call("search_radius", v)
	)
	container.add_child(radius_slider)

	# 缠绕持续时间
	var dur_lbl := Label.new()
	dur_lbl.text = "缠绕锁死时间 (Duration): %.1fs" % bind_duration
	dur_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(dur_lbl)

	var dur_slider := HSlider.new()
	dur_slider.min_value = 1.0
	dur_slider.max_value = 8.0
	dur_slider.step = 0.5
	dur_slider.value = bind_duration
	dur_slider.value_changed.connect(func(v: float):
		bind_duration = v
		dur_lbl.text = "缠绕锁死时间 (Duration): %.1fs" % v
		on_changed.call("bind_duration", v)
	)
	container.add_child(dur_slider)

	# 特性说明面板
	var tip_panel := PanelContainer.new()
	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.02, 0.14, 0.10, 0.85)
	t_style.set_corner_radius_all(6)
	t_style.set_border_width_all(1)
	t_style.border_color = Color(0.1, 0.9, 0.4, 0.5)
	t_style.set_content_margin_all(8)
	tip_panel.add_theme_stylebox_override("panel", t_style)
	container.add_child(tip_panel)

	var tip_vbox := VBoxContainer.new()
	tip_vbox.add_theme_constant_override("separation", 4)
	tip_panel.add_child(tip_vbox)

	var tip1 := Label.new()
	tip1.text = "🌿 3D 生物藤蔓：4股荆棘藤蔓自地面盘旋缠死躯干"
	tip1.add_theme_font_size_override("font_size", 11)
	tip1.modulate = Color(0.2, 1.0, 0.5)
	tip_vbox.add_child(tip1)

	var tip2 := Label.new()
	tip2.text = "🎯 自动索敌与空放保护：范围内无敌人自动提示"
	tip2.add_theme_font_size_override("font_size", 11)
	tip2.modulate = Color(1.0, 0.85, 0.3)
	tip_vbox.add_child(tip2)

	var tip3 := Label.new()
	tip3.text = "🔒 物理锚定：缠绕期移速锁零，结束后无需按键立即行动"
	tip3.add_theme_font_size_override("font_size", 11)
	tip3.modulate = Color(0.4, 0.95, 1.0)
	tip_vbox.add_child(tip3)

## Searches scene tree for nearest CharacterBody3D (excluding caster) within max_dist.
func _find_nearest_target(caster: CharacterBody3D, max_dist: float) -> CharacterBody3D:
	if caster == null or not caster.is_inside_tree():
		return null

	var tree := caster.get_tree()
	if tree == null:
		return null

	var nearest: CharacterBody3D = null
	var min_dist_sq := max_dist * max_dist
	var from_p := caster.global_position

	var bodies := tree.root.find_children("", "CharacterBody3D", true, false)
	for b in bodies:
		if b == caster or not (b is CharacterBody3D):
			continue
		var cb := b as CharacterBody3D
		if cb.name == "Ground":
			continue
		var dist_sq := from_p.distance_squared_to(cb.global_position)
		if dist_sq <= min_dist_sq:
			min_dist_sq = dist_sq
			nearest = cb

	return nearest

## Locks the target actor in place cleanly without breaking intent references.
static func _immobilize_target(target: CharacterBody3D, duration: float) -> void:
	if target == null or not is_instance_valid(target):
		return

	var t_id := target.get_instance_id()

	# If already bound, cancel previous timer
	if _active_binds.has(t_id):
		var prev_tw: Tween = _active_binds[t_id].get("tween")
		if prev_tw != null and prev_tw.is_valid():
			prev_tw.kill()

	var locked_pos := target.global_position
	target.velocity = Vector3.ZERO

	var tw := target.create_tween()
	_active_binds[t_id] = {
		"target": target,
		"locked_pos": locked_pos,
		"tween": tw
	}

	# Maintain zero velocity and position pinning during bind
	tw.tween_method(func(_progress: float):
		if is_instance_valid(target):
			target.global_position = locked_pos
			target.velocity = Vector3.ZERO
	, 0.0, 1.0, duration)

	tw.chain().tween_callback(func():
		_release_target(target)
	)

static func _release_target(target: CharacterBody3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	var t_id := target.get_instance_id()
	if not _active_binds.has(t_id):
		return

	_active_binds.erase(t_id)
	if is_instance_valid(target):
		target.velocity = Vector3.ZERO

static func is_immobilized(target: CharacterBody3D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return _active_binds.has(target.get_instance_id())

## Spawns the authentic 3D Winding Thorny Vines VFX Suite.
static func _spawn_vine_entangle_vfx(caster: CharacterBody3D, target: CharacterBody3D, dur: float, parent: Node) -> void:
	var c_pos := caster.global_position + Vector3.UP * 0.9
	var t_pos := target.global_position
	var t_chest := t_pos + Vector3.UP * 0.9

	# --- 1. Green Energy Spore Tether to Target ---
	_spawn_spore_tether(c_pos, t_chest, parent)

	# --- 2. Ground Sprouting Magic Circle & Mossy Root Decal ---
	var sigil_quad := QuadMesh.new()
	sigil_quad.size = Vector2(3.0, 3.0)
	var sigil_inst := MeshInstance3D.new()
	sigil_inst.name = "VineGroundSigil"
	sigil_inst.mesh = sigil_quad
	sigil_inst.rotation.x = -PI * 0.5

	var sigil_mat := ShaderMaterial.new()
	sigil_mat.shader = SigilRingShader
	sigil_mat.set_shader_parameter("sigil_color", Color(0.15, 0.95, 0.35, 0.9))
	sigil_mat.set_shader_parameter("spin_speed", 1.2)
	sigil_mat.set_shader_parameter("fade", 1.0)
	sigil_inst.material_override = sigil_mat
	parent.add_child(sigil_inst)
	sigil_inst.global_position = t_pos + Vector3.UP * 0.02
	sigil_inst.scale = Vector3(0.1, 0.1, 0.1)

	# --- 3. Procedural 3D Spiraling Thorny Vines (4 股自地面盘旋缠绕躯干的立体荆棘藤蔓) ---
	var vine_mesh := _generate_coiling_vines_mesh(4, 1.75, 36)
	var vine_inst := MeshInstance3D.new()
	vine_inst.name = "CoilingThornVines"
	vine_inst.mesh = vine_mesh

	var vine_mat := ShaderMaterial.new()
	vine_mat.shader = VineGrowthShader
	vine_mat.set_shader_parameter("bark_color", Color(0.06, 0.30, 0.12, 1.0))
	vine_mat.set_shader_parameter("thorn_color", Color(0.20, 0.95, 0.38, 1.0))
	vine_mat.set_shader_parameter("vein_glow", Color(0.6, 1.0, 0.5, 1.0))
	vine_mat.set_shader_parameter("pulse_speed", 3.0)
	vine_mat.set_shader_parameter("growth_progress", 0.0)
	vine_mat.set_shader_parameter("fade", 1.0)
	vine_inst.material_override = vine_mat
	parent.add_child(vine_inst)
	vine_inst.global_position = t_pos

	# --- 4. Tight Clamping Body Rings (身体紧锁棘刺环) ---
	var ring_nodes: Array[MeshInstance3D] = []
	var ring_heights := [0.35, 0.85, 1.35]
	for rh in ring_heights:
		var r_torus := TorusMesh.new()
		r_torus.inner_radius = 0.36
		r_torus.outer_radius = 0.44
		r_torus.rings = 16
		r_torus.ring_segments = 6

		var r_inst := MeshInstance3D.new()
		r_inst.name = "VineClampingRing"
		r_inst.mesh = r_torus
		var r_mat := StandardMaterial3D.new()
		r_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		r_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		r_mat.albedo_color = Color(0.18, 0.95, 0.40, 0.85)
		r_inst.material_override = r_mat
		parent.add_child(r_inst)
		r_inst.global_position = t_pos + Vector3.UP * rh
		r_inst.scale = Vector3(0.1, 0.1, 0.1)
		ring_nodes.append(r_inst)

	# --- Growth Animation: Vines swiftly shoot up and coil around the body in 0.26s ---
	var tw_grow := vine_inst.create_tween()
	tw_grow.set_parallel(true)
	tw_grow.tween_property(sigil_inst, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw_grow.tween_method(func(v: float):
		if is_instance_valid(vine_mat):
			vine_mat.set_shader_parameter("growth_progress", v)
	, 0.0, 1.0, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	for r_node in ring_nodes:
		tw_grow.tween_property(r_node, "scale", Vector3.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# --- Duration Hold & Snap Break Animation ---
	var tw_end := vine_inst.create_tween()
	tw_end.tween_interval(dur)
	tw_end.tween_callback(func():
		# Snap burst effect
		_spawn_vine_burst(t_chest, parent)
		AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/knifeSlice.ogg", 1.4)
	)
	tw_end.set_parallel(true)
	tw_end.tween_method(func(v: float):
		if is_instance_valid(vine_mat):
			vine_mat.set_shader_parameter("fade", v)
		if is_instance_valid(sigil_mat):
			sigil_mat.set_shader_parameter("fade", v)
	, 1.0, 0.0, 0.22)

	for r_node in ring_nodes:
		tw_end.tween_property(r_node, "scale", Vector3(1.5, 1.5, 1.5), 0.20)
		tw_end.tween_property(r_node.material_override, "albedo_color:a", 0.0, 0.20)

	tw_end.chain().tween_callback(func():
		if is_instance_valid(sigil_inst):
			sigil_inst.queue_free()
		if is_instance_valid(vine_inst):
			vine_inst.queue_free()
		for r_node in ring_nodes:
			if is_instance_valid(r_node):
				r_node.queue_free()
	)

## Generates true 3D spiraling multi-strand thorny vine geometry wrapped around a humanoid.
static func _generate_coiling_vines_mesh(strand_count: int, total_height: float, segments: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	var cross_sides := 6
	var d_cross := TAU / float(cross_sides)

	for strand in range(strand_count):
		var base_angle: float = strand * (TAU / float(strand_count))
		var strand_start_idx: int = verts.size()

		for s in range(segments + 1):
			var t: float = float(s) / float(segments)
			var y: float = t * total_height

			# 3D Helix spiral formula: coils ~1.2 full turns around the character
			var angle: float = base_angle + t * (TAU * 1.25)

			# Body curvature radius: hugging feet, knees, waist, chest
			var body_r: float = 0.85 * (1.0 - t) * 0.4 + 0.38 + sin(t * PI * 2.0) * 0.04
			var center := Vector3(cos(angle) * body_r, y, sin(angle) * body_r)

			# Tangent direction
			var next_t: float = minf(t + 0.02, 1.0)
			var next_y: float = next_t * total_height
			var next_angle: float = base_angle + next_t * (TAU * 1.25)
			var next_r: float = 0.85 * (1.0 - next_t) * 0.4 + 0.38 + sin(next_t * PI * 2.0) * 0.04
			var next_center := Vector3(cos(next_angle) * next_r, next_y, sin(next_angle) * next_r)
			var tangent := (next_center - center).normalized()

			# Vine cross section radius (thick root, tapering tip)
			var stem_radius: float = 0.042 * (1.0 - t * 0.50)

			var temp_up := Vector3.UP if absf(tangent.y) < 0.95 else Vector3.FORWARD
			var right := tangent.cross(temp_up).normalized()
			var up := right.cross(tangent).normalized()

			for c in range(cross_sides):
				var ca: float = c * d_cross
				var normal := (right * cos(ca) + up * sin(ca)).normalized()
				var v_pos := center + normal * stem_radius

				# Add thorn projections every few segments
				if s % 5 == 0 and c % 2 == 0:
					v_pos += normal * (stem_radius * 1.8)

				verts.append(v_pos)
				normals.append(normal)
				uvs.append(Vector2(float(c) / float(cross_sides), t))

		# Build tube indices for this strand
		for s in range(segments):
			var r1 := strand_start_idx + s * cross_sides
			var r2 := strand_start_idx + (s + 1) * cross_sides
			for c in range(cross_sides):
				var next_c: int = (c + 1) % cross_sides
				var a: int = r1 + c
				var b: int = r2 + c
				var d: int = r1 + next_c
				var e: int = r2 + next_c

				indices.append(a)
				indices.append(b)
				indices.append(d)

				indices.append(d)
				indices.append(b)
				indices.append(e)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

static func _spawn_spore_tether(start_p: Vector3, end_p: Vector3, parent: Node) -> void:
	var dist := start_p.distance_to(end_p)
	if dist < 0.1:
		return

	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.03
	cyl.height = dist
	cyl.radial_segments = 8

	var inst := MeshInstance3D.new()
	inst.name = "VineTether"
	inst.mesh = cyl

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.2, 1.0, 0.4, 0.85)
	inst.material_override = mat
	parent.add_child(inst)

	var dir := (end_p - start_p).normalized()
	var temp_up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD
	var right := dir.cross(temp_up).normalized()
	var normal := right.cross(dir).normalized()
	inst.global_transform.basis = Basis(right, dir, normal)
	inst.global_position = (start_p + end_p) * 0.5

	var tw := inst.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(inst.queue_free)

static func _spawn_vine_burst(pos: Vector3, parent: Node) -> void:
	var parts := CPUParticles3D.new()
	parts.name = "VineSplinterBurst"
	parts.amount = 32
	parts.lifetime = 0.45
	parts.one_shot = true
	parts.explosiveness = 0.95
	parts.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	parts.emission_sphere_radius = 0.6
	parts.direction = Vector3.UP
	parts.spread = 160.0
	parts.gravity = Vector3(0, -7.0, 0)
	parts.initial_velocity_min = 3.5
	parts.initial_velocity_max = 8.0

	var p_mesh := BoxMesh.new()
	p_mesh.size = Vector3(0.06, 0.12, 0.04)
	var p_mat := StandardMaterial3D.new()
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p_mat.albedo_color = Color(0.25, 0.95, 0.40, 0.9)
	parts.mesh = p_mesh
	parts.material_override = p_mat

	parent.add_child(parts)
	parts.global_position = pos
	parts.emitting = true

	var tw := parts.create_tween()
	tw.tween_interval(0.50)
	tw.tween_callback(parts.queue_free)


func preload_assets() -> void:
	AudioManagerScript.preload_sounds([
		"res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg",
		"res://assets/voice/RPGsounds_Kenney/OGG/knifeSlice.ogg"
	])


func get_warmup_materials() -> Array:
	var m1 := ShaderMaterial.new()
	m1.shader = VineGrowthShader
	var m2 := ShaderMaterial.new()
	m2.shader = SigilRingShader
	return [m1, m2]


func dispel_actor(actor: CharacterBody3D) -> void:
	if actor != null and is_instance_valid(actor):
		_release_target(actor)
