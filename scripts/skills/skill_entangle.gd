extends "res://scripts/skills/skill_base.gd"
## 幽冥死沼·深渊黑绿毒藤宏大向心缠绕 (Grand Dark Toxic Vine Cataclysm Entanglement).
## 纯正黑绿剧毒基调（深渊黑绿底色 + 高亮毒绿侵蚀 + 蚀骨酸绿符文 + 邪魅死灵紫），
## 起手超大向心毒沼巨阵与8股地狱毒流合围，终结以巨型毒爆冲击波双环与冲天毒瘴气浪大场面收尾。

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const VineGrowthShader = preload("res://shaders/vine_growth.gdshader")
const ConvergingResinSigilShader = preload("res://shaders/converging_resin_sigil.gdshader")
const SonicRingShader = preload("res://shaders/sonic_boom_ring.gdshader")

var search_radius: float = 12.0
var bind_duration: float = 3.5

# Active immobilization tracking: actor_id -> Dictionary
static var _active_binds: Dictionary = {}

func get_id() -> String:
	return "entangle"

func get_name() -> String:
	return "🌿 荆棘缠绕 (深渊黑绿毒藤锁死)"

func get_title() -> String:
	return "🌿 荆棘缠绕配置 (GRAND DARK TOXIC VINE)"

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

	# 4. Spawn Grand Dark Toxic Converging Sigil, Shadow Ribbons & Ascending Spores
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

	var dur_lbl := Label.new()
	dur_lbl.text = "锁死禁锢时长 (Duration): %.1fs" % bind_duration
	dur_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(dur_lbl)

	var dur_slider := HSlider.new()
	dur_slider.min_value = 1.0
	dur_slider.max_value = 8.0
	dur_slider.step = 0.5
	dur_slider.value = bind_duration
	dur_slider.value_changed.connect(func(v: float):
		bind_duration = v
		dur_lbl.text = "锁死禁锢时长 (Duration): %.1fs" % v
		on_changed.call("bind_duration", v)
	)
	container.add_child(dur_slider)

	var tip_panel := PanelContainer.new()
	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.01, 0.08, 0.03, 0.90)
	t_style.set_corner_radius_all(6)
	t_style.set_border_width_all(1)
	t_style.border_color = Color(0.1, 0.85, 0.25, 0.7)
	t_style.set_content_margin_all(8)
	tip_panel.add_theme_stylebox_override("panel", t_style)
	container.add_child(tip_panel)

	var tip_vbox := VBoxContainer.new()
	tip_vbox.add_theme_constant_override("separation", 4)
	tip_panel.add_child(tip_vbox)

	var tip1 := Label.new()
	tip1.text = "☠️ 宏大起手：超大深渊毒沼地阵，8股黑绿毒流自四周破土向心猛烈包夹"
	tip1.add_theme_font_size_override("font_size", 11)
	tip1.modulate = Color(0.2, 0.95, 0.35)
	tip_vbox.add_child(tip1)

	var tip2 := Label.new()
	tip2.text = "🌿 毒缎流淌蚀骨酸绿符文与死灵紫影，升腾幽冥剧毒光尘"
	tip2.add_theme_font_size_override("font_size", 11)
	tip2.modulate = Color(0.7, 1.0, 0.2)
	tip_vbox.add_child(tip2)

	var tip3 := Label.new()
	tip3.text = "💥 宏大收尾：巨型毒爆冲击波双环横扫 + 冲天毒瘴蘑菇云升华"
	tip3.add_theme_font_size_override("font_size", 11)
	tip3.modulate = Color(0.8, 0.4, 1.0)
	tip_vbox.add_child(tip3)

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

static func _immobilize_target(target: CharacterBody3D, duration: float) -> void:
	if target == null or not is_instance_valid(target):
		return

	var t_id := target.get_instance_id()

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

## Spawns the authentic Grand Dark Toxic & Venomous Vine Entanglement VFX Suite.
static func _spawn_vine_entangle_vfx(caster: CharacterBody3D, target: CharacterBody3D, dur: float, parent: Node) -> void:
	var c_pos := caster.global_position + Vector3.UP * 0.9
	var t_pos := target.global_position
	var t_chest := t_pos + Vector3.UP * 0.9

	# --- 1. Toxic Energy Tether to Target ---
	_spawn_spore_tether(c_pos, t_chest, parent)

	# --- 2. 8 股深渊向心猛烈合围毒流 (Grand Inward Toxic Tendrils) ---
	_spawn_inward_toxic_tendrils(t_pos, parent)

	# --- 3. 宏大黑绿深渊向心毒沼巨阵 (Grand Dark Toxic Ground Sigil: 直径 5.6m) ---
	var sigil_quad := QuadMesh.new()
	sigil_quad.size = Vector2(5.6, 5.6)
	var sigil_inst := MeshInstance3D.new()
	sigil_inst.name = "GrandDarkToxicSigil"
	sigil_inst.mesh = sigil_quad
	sigil_inst.rotation.x = -PI * 0.5

	var sigil_mat := ShaderMaterial.new()
	sigil_mat.shader = ConvergingResinSigilShader
	sigil_mat.set_shader_parameter("color_dark_shadow", Color(0.01, 0.10, 0.03, 0.95))
	sigil_mat.set_shader_parameter("color_toxic_green", Color(0.05, 0.95, 0.25, 0.95))
	sigil_mat.set_shader_parameter("color_acid_lime", Color(0.68, 1.0, 0.05, 1.0))
	sigil_mat.set_shader_parameter("color_necro_violet", Color(0.42, 0.02, 0.60, 0.85))
	sigil_mat.set_shader_parameter("spin_speed", 1.4)
	sigil_mat.set_shader_parameter("inward_flow_speed", 3.8)
	sigil_mat.set_shader_parameter("pulse_speed", 2.6)
	sigil_mat.set_shader_parameter("fade", 1.0)
	VfxTextures.bind(sigil_mat, "sigil_tex", VfxTextures.MAGIC_CIRCLE, "tex_mix", 0.75)
	sigil_inst.material_override = sigil_mat
	parent.add_child(sigil_inst)
	sigil_inst.global_position = t_pos + Vector3.UP * 0.02
	sigil_inst.scale = Vector3(0.1, 0.1, 0.1)

	# --- 4. 4 股厚重死灵黑绿毒缎 (Grand Dark Toxic Ribbons) ---
	var ribbon_mesh := _generate_organic_ribbon_mesh(4, 1.95, 54)
	var ribbon_inst := MeshInstance3D.new()
	ribbon_inst.name = "GrandDarkToxicRibbons"
	ribbon_inst.mesh = ribbon_mesh

	var vine_mat := ShaderMaterial.new()
	vine_mat.shader = VineGrowthShader
	vine_mat.set_shader_parameter("color_shadow_black", Color(0.01, 0.08, 0.03, 0.95))
	vine_mat.set_shader_parameter("color_toxic_green", Color(0.06, 0.95, 0.25, 0.95))
	vine_mat.set_shader_parameter("color_acid_lime", Color(0.72, 1.0, 0.08, 1.0))
	vine_mat.set_shader_parameter("color_necro_purple", Color(0.48, 0.03, 0.68, 0.85))
	vine_mat.set_shader_parameter("pulse_speed", 3.6)
	vine_mat.set_shader_parameter("wave_amplitude", 0.025)
	vine_mat.set_shader_parameter("growth_progress", 0.0)
	vine_mat.set_shader_parameter("fade", 1.0)
	ribbon_inst.material_override = vine_mat
	parent.add_child(ribbon_inst)
	ribbon_inst.global_position = t_pos

	# --- 5. Ascending Dark Toxic Spore Dust (45+ 颗升腾毒光星尘) ---
	var spore_particles := _spawn_ascending_spores(t_pos, dur, parent)

	# --- Growth & Inward Converge Animation in 0.28s ---
	var tw_grow := ribbon_inst.create_tween()
	tw_grow.set_parallel(true)
	tw_grow.tween_property(sigil_inst, "scale", Vector3.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw_grow.tween_method(func(v: float):
		if is_instance_valid(vine_mat):
			vine_mat.set_shader_parameter("growth_progress", v)
	, 0.0, 1.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# --- Duration Hold & Grand Toxic Rupture Cataclysm Dissolve ---
	var tw_end := ribbon_inst.create_tween()
	tw_end.tween_interval(dur)
	tw_end.tween_callback(func():
		# 宏大深渊毒爆大轰炸
		_spawn_grand_toxic_cataclysm(t_chest, parent)
		AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/knifeSlice.ogg", 1.6)
	)
	tw_end.set_parallel(true)
	tw_end.tween_method(func(v: float):
		if is_instance_valid(vine_mat):
			vine_mat.set_shader_parameter("fade", v)
		if is_instance_valid(sigil_mat):
			sigil_mat.set_shader_parameter("fade", v)
	, 1.0, 0.0, 0.22)

	tw_end.chain().tween_callback(func():
		if is_instance_valid(sigil_inst):
			sigil_inst.queue_free()
		if is_instance_valid(ribbon_inst):
			ribbon_inst.queue_free()
		if is_instance_valid(spore_particles):
			spore_particles.queue_free()
	)

## 8 股深渊向心猛烈合围毒流
static func _spawn_inward_toxic_tendrils(center_pos: Vector3, parent: Node) -> void:
	var tendril_count := 8
	for i in range(tendril_count):
		var angle := float(i) * (TAU / float(tendril_count)) + randf_range(-0.12, 0.12)
		var spawn_rad := 3.2
		var start_p := center_pos + Vector3(cos(angle) * spawn_rad, 0.03, sin(angle) * spawn_rad)
		var end_p := center_pos + Vector3(cos(angle) * 0.25, 0.03, sin(angle) * 0.25)

		var tendril := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.28, spawn_rad)
		tendril.mesh = qm
		tendril.rotation.x = -PI * 0.5
		tendril.rotation.y = angle - PI * 0.5

		var t_mat := StandardMaterial3D.new()
		t_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		t_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		t_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		t_mat.albedo_color = Color(0.08, 0.95, 0.28, 0.95).lerp(Color(0.55, 0.05, 0.75, 0.85), float(i) / float(tendril_count))
		t_mat.albedo_texture = VfxTextures.get_tex(VfxTextures.FLASH_GLOW)
		tendril.material_override = t_mat
		parent.add_child(tendril)
		tendril.global_position = (start_p + end_p) * 0.5

		var tw := tendril.create_tween().set_parallel(true)
		tw.tween_property(tendril, "scale", Vector3(1.4, 1.4, 1.4), 0.26).from(Vector3(0.2, 0.2, 0.2))\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(t_mat, "albedo_color:a", 0.0, 0.32).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(tendril.queue_free)

## Generates smooth organic double-sided energy ribbon quads hugging humanoid body curves.
static func _generate_organic_ribbon_mesh(strand_count: int, total_height: float, segments: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	for strand in range(strand_count):
		var base_angle: float = strand * (TAU / float(strand_count))
		var strand_start_idx: int = verts.size()

		for s in range(segments + 1):
			var t: float = float(s) / float(segments)
			var y: float = t * total_height

			var angle: float = base_angle + t * (TAU * 1.35)
			var body_r: float = 0.38 + sin(t * PI) * 0.08 + cos(t * PI * 2.0) * 0.04
			var center := Vector3(cos(angle) * body_r, y, sin(angle) * body_r)

			var next_t: float = minf(t + 0.015, 1.0)
			var next_y: float = next_t * total_height
			var next_angle: float = base_angle + next_t * (TAU * 1.35)
			var next_r: float = 0.38 + sin(next_t * PI) * 0.08 + cos(next_t * PI * 2.0) * 0.04
			var next_center := Vector3(cos(next_angle) * next_r, next_y, sin(next_angle) * next_r)
			var tangent := (next_center - center).normalized()

			var radial_out := Vector3(cos(angle), 0.0, sin(angle)).normalized()
			var ribbon_binormal := tangent.cross(radial_out).normalized()

			var half_width: float = (0.11 * (1.0 - t * 0.40) + sin(t * PI) * 0.045)

			var v_left := center - ribbon_binormal * half_width
			var v_right := center + ribbon_binormal * half_width

			verts.append(v_left)
			verts.append(v_right)

			normals.append(radial_out)
			normals.append(radial_out)

			uvs.append(Vector2(0.0, t))
			uvs.append(Vector2(1.0, t))

		# Build two-sided quad strip indices
		for s in range(segments):
			var r1 := strand_start_idx + s * 2
			var r2 := strand_start_idx + (s + 1) * 2

			var a := r1
			var b := r1 + 1
			var c := r2
			var d := r2 + 1

			# Front face
			indices.append(a)
			indices.append(c)
			indices.append(b)

			indices.append(b)
			indices.append(c)
			indices.append(d)

			# Back face
			indices.append(a)
			indices.append(b)
			indices.append(c)

			indices.append(b)
			indices.append(d)
			indices.append(c)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Ascending dark toxic dust particles
static func _spawn_ascending_spores(t_pos: Vector3, dur: float, parent: Node) -> CPUParticles3D:
	var parts := CPUParticles3D.new()
	parts.name = "AscendingToxicSporeDust"
	parts.amount = 45
	parts.lifetime = 1.6
	parts.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	parts.emission_ring_radius = 1.1
	parts.emission_ring_inner_radius = 0.15
	parts.emission_ring_height = 0.15
	parts.emission_ring_axis = Vector3(0, 1, 0)
	parts.direction = Vector3.UP
	parts.spread = 18.0
	parts.gravity = Vector3(0, 0.45, 0)
	parts.initial_velocity_min = 1.0
	parts.initial_velocity_max = 2.4
	parts.scale_amount_min = 0.6
	parts.scale_amount_max = 1.4

	var p_mesh := QuadMesh.new()
	p_mesh.size = Vector2(0.12, 0.12)
	var p_mat := StandardMaterial3D.new()
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	p_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	p_mat.albedo_color = Color(0.15, 1.0, 0.35, 0.85)
	p_mat.albedo_texture = VfxTextures.get_tex(VfxTextures.FLASH_GLOW)
	parts.mesh = p_mesh
	parts.material_override = p_mat

	parent.add_child(parts)
	parts.global_position = t_pos + Vector3.UP * 0.05
	parts.emitting = true

	var tw := parts.create_tween()
	tw.tween_interval(maxf(dur - 0.2, 0.1))
	tw.tween_property(p_mat, "albedo_color:a", 0.0, 0.25)
	tw.tween_callback(func():
		parts.emitting = false
	)

	return parts

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
	mat.albedo_color = Color(0.1, 0.95, 0.3, 0.9)
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
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(inst.queue_free)

## 宏大深渊毒爆大轰炸收尾特效 (Grand Abyssal Toxic Cataclysm Rupture)
static func _spawn_grand_toxic_cataclysm(pos: Vector3, parent: Node) -> void:
	# 1. 巨型毒爆冲击主光环 (Grand Shockwave Ring 1: 5.5m 直径)
	var ring1 := MeshInstance3D.new()
	var qm1 := QuadMesh.new()
	qm1.size = Vector2(5.5, 5.5)
	ring1.mesh = qm1
	ring1.rotation.x = -PI * 0.5
	ring1.position = pos

	var r1_mat := ShaderMaterial.new()
	r1_mat.shader = SonicRingShader
	r1_mat.set_shader_parameter("ring_color", Color(0.15, 1.0, 0.4, 1.0))
	r1_mat.set_shader_parameter("fade", 1.0)
	r1_mat.set_shader_parameter("thickness", 0.22)
	VfxTextures.bind(r1_mat, "ring_tex", VfxTextures.SHOCKWAVE_RING, "tex_mix", 1.0)
	VfxTextures.bind_ramp(r1_mat, VfxTextures.RAMP_TOXIC, 0.85)
	ring1.material_override = r1_mat
	parent.add_child(ring1)

	var tw_ring1 := ring1.create_tween().set_parallel(true)
	tw_ring1.tween_property(ring1, "scale", Vector3(2.0, 2.0, 2.0), 0.36).from(Vector3(0.15, 0.15, 0.15))\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw_ring1.tween_method(func(v: float):
		if is_instance_valid(r1_mat):
			r1_mat.set_shader_parameter("fade", v)
	, 1.0, 0.0, 0.36).set_ease(Tween.EASE_IN)
	tw_ring1.chain().tween_callback(ring1.queue_free)

	# 2. 次级死灵紫电回响光环 (Secondary Necrotic Violet Ring 2: 4.2m)
	var ring2 := MeshInstance3D.new()
	var qm2 := QuadMesh.new()
	qm2.size = Vector2(4.2, 4.2)
	ring2.mesh = qm2
	ring2.rotation.x = -PI * 0.5
	ring2.position = pos + Vector3.UP * 0.15

	var r2_mat := ShaderMaterial.new()
	r2_mat.shader = SonicRingShader
	r2_mat.set_shader_parameter("ring_color", Color(0.65, 0.08, 0.85, 0.9))
	r2_mat.set_shader_parameter("fade", 1.0)
	r2_mat.set_shader_parameter("thickness", 0.16)
	VfxTextures.bind(r2_mat, "ring_tex", VfxTextures.SHOCKWAVE_RING, "tex_mix", 1.0)
	ring2.material_override = r2_mat
	parent.add_child(ring2)

	var tw_ring2 := ring2.create_tween()
	tw_ring2.tween_interval(0.04)
	tw_ring2.set_parallel(true)
	tw_ring2.tween_property(ring2, "scale", Vector3(1.8, 1.8, 1.8), 0.32).from(Vector3(0.2, 0.2, 0.2))\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw_ring2.tween_method(func(v: float):
		if is_instance_valid(r2_mat):
			r2_mat.set_shader_parameter("fade", v)
	, 1.0, 0.0, 0.32).set_ease(Tween.EASE_IN)
	tw_ring2.chain().tween_callback(ring2.queue_free)

	# 3. 冲天毒瘴蘑菇云与升华气浪 (Ascending Toxic Miasma Plume)
	var smoke := MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2(4.2, 4.2)
	smoke.mesh = sq
	smoke.position = pos + Vector3.UP * 0.2

	var s_mat := StandardMaterial3D.new()
	s_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	s_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	s_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	s_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	s_mat.albedo_color = Color(0.06, 0.92, 0.28, 0.85)
	s_mat.albedo_texture = VfxTextures.get_tex(VfxTextures.SMOKE)
	smoke.material_override = s_mat
	parent.add_child(smoke)

	var tw_smoke := smoke.create_tween().set_parallel(true)
	tw_smoke.tween_property(smoke, "scale", Vector3(1.9, 1.9, 1.9), 0.42).from(Vector3(0.3, 0.3, 0.3))\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw_smoke.tween_property(smoke, "position:y", pos.y + 1.6, 0.42)
	tw_smoke.tween_property(s_mat, "albedo_color:a", 0.0, 0.42).set_ease(Tween.EASE_IN)
	tw_smoke.chain().tween_callback(smoke.queue_free)

	# 4. 毒爆瞬间全向强闪光
	var light := OmniLight3D.new()
	light.light_color = Color(0.2, 1.0, 0.4)
	light.light_energy = 4.5
	light.omni_range = 14.0
	light.position = pos + Vector3.UP * 0.5
	parent.add_child(light)

	var tw_l := light.create_tween()
	tw_l.tween_property(light, "light_energy", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw_l.tween_callback(light.queue_free)

## reset_state(): drops root/bind bookkeeping. Scene entry only.
func reset_state() -> void:
	_active_binds.clear()


func preload_assets() -> void:
	AudioManagerScript.preload_sounds([
		"res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg",
		"res://assets/voice/RPGsounds_Kenney/OGG/knifeSlice.ogg"
	])

func get_warmup_materials() -> Array:
	var m1 := ShaderMaterial.new()
	m1.shader = VineGrowthShader
	var m2 := ShaderMaterial.new()
	m2.shader = ConvergingResinSigilShader
	var m3 := ShaderMaterial.new()
	m3.shader = SonicRingShader
	return [m1, m2, m3]

func dispel_actor(actor: CharacterBody3D) -> void:
	if actor != null and is_instance_valid(actor):
		_release_target(actor)
