extends "res://scripts/skills/skill_base.gd"
## 技能十：蟾宫折桂 (Osmanthus of the Moon Palace / Jump & Agility Buff).
## 纯正金黄主题：释放时脚底绽开璀璨3D金黄莲花；
## Buff期间复用项目统一的武器三轨流光飘带系统 (WeaponTrail + TrailPalette "gold")，
## 在双足生成丝滑细长的金色流光丝绸飘带步迹（走过留痕，淡淡仙气），双手挥动之处流淌飘落四瓣金色桂花粒。

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const AnimPipelineScript = preload("res://tools/anim_pipeline.gd")
const SonicRingShader = preload("res://shaders/sonic_boom_ring.gdshader")
const GoldenOsmanthusLotusShader = preload("res://shaders/golden_osmanthus_lotus.gdshader")
const OsmanthusGrainShader = preload("res://shaders/osmanthus_grain.gdshader")

var duration: float = 8.0
var jump_multiplier: float = 2.4
var air_control_boost: float = 1.8

# Active buffs tracking: caster_id -> Dictionary
static var _active_buffs: Dictionary = {}

func get_id() -> String:
	return "jump_buff"

func get_name() -> String:
	return "🌕 蟾宫折桂 (金莲步·桂花流光)"

func get_title() -> String:
	return "🌕 蟾宫折桂配置 (MOON PALACE OSMANTHUS)"

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
	var dur_lbl := Label.new()
	dur_lbl.text = "折桂增益持续 (Duration): %.1fs" % duration
	dur_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(dur_lbl)

	var dur_slider := HSlider.new()
	dur_slider.min_value = 2.0
	dur_slider.max_value = 20.0
	dur_slider.step = 0.5
	dur_slider.value = duration
	dur_slider.value_changed.connect(func(v: float):
		duration = v
		dur_lbl.text = "折桂增益持续 (Duration): %.1fs" % v
		on_changed.call("duration", v)
	)
	container.add_child(dur_slider)

	var mult_lbl := Label.new()
	mult_lbl.text = "轻身飞跃倍率 (Jump Multiplier): %.1fx" % jump_multiplier
	mult_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(mult_lbl)

	var mult_slider := HSlider.new()
	mult_slider.min_value = 1.2
	mult_slider.max_value = 4.5
	mult_slider.step = 0.1
	mult_slider.value = jump_multiplier
	mult_slider.value_changed.connect(func(v: float):
		jump_multiplier = v
		mult_lbl.text = "轻身飞跃倍率 (Jump Multiplier): %.1fx" % v
		on_changed.call("jump_multiplier", v)
	)
	container.add_child(mult_slider)

	var tip_panel := PanelContainer.new()
	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.16, 0.12, 0.03, 0.90)
	t_style.set_corner_radius_all(6)
	t_style.set_border_width_all(1)
	t_style.border_color = Color(1.0, 0.82, 0.2, 0.8)
	t_style.set_content_margin_all(8)
	tip_panel.add_theme_stylebox_override("panel", t_style)
	container.add_child(tip_panel)

	var tip_vbox := VBoxContainer.new()
	tip_vbox.add_theme_constant_override("separation", 4)
	tip_panel.add_child(tip_vbox)

	var tip1 := Label.new()
	tip1.text = "🪷 释放瞬间脚底盛开纯金琉璃折桂金莲，月华神辉冲天"
	tip1.add_theme_font_size_override("font_size", 11)
	tip1.modulate = Color(1.0, 0.9, 0.4)
	tip_vbox.add_child(tip1)

	var tip2 := Label.new()
	tip2.text = "🎗️ 复用项目 WeaponTrail 三轨流光引擎，双足产生细长丝滑金色飘带"
	tip2.add_theme_font_size_override("font_size", 11)
	tip2.modulate = Color(1.0, 0.78, 0.2)
	tip_vbox.add_child(tip2)

	var tip3 := Label.new()
	tip3.text = "🌼 双手挥舞摆动之处，流淌飘落四瓣金色桂花粒"
	tip3.add_theme_font_size_override("font_size", 11)
	tip3.modulate = Color(1.0, 0.95, 0.6)
	tip_vbox.add_child(tip3)

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

	# 1. 施法瞬间脚底绽开 3D 盛开金黄莲花 (Blooming Golden Lotus)
	_spawn_blooming_golden_lotus(caster.global_position, parent)

	# 2. 挂载 Buff 期间基于项目统一 WeaponTrail 的金色流光飘带与双手桂花微粒
	var aura := _spawn_osmanthus_buff_aura(caster, dur, parent)

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

## 施法瞬间脚底绽开的 3D 纯金黄莲花
static func _spawn_blooming_golden_lotus(ground_pos: Vector3, parent: Node) -> void:
	if parent == null or not is_instance_valid(parent):
		return

	var lotus_root := Node3D.new()
	lotus_root.name = "BloomingGoldenLotus"
	lotus_root.position = ground_pos
	parent.add_child(lotus_root)

	# 金色月华冲击金环
	var ring := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(3.6, 3.6)
	ring.mesh = qm
	ring.rotation.x = -PI * 0.5
	ring.position.y = 0.04

	var r_mat := ShaderMaterial.new()
	r_mat.shader = SonicRingShader
	r_mat.set_shader_parameter("ring_color", Color(1.0, 0.85, 0.25, 0.95))
	r_mat.set_shader_parameter("thickness", 0.18)
	r_mat.set_shader_parameter("fade", 1.0)
	VfxTextures.bind(r_mat, "ring_tex", VfxTextures.SHOCKWAVE_RING, "tex_mix", 1.0)
	ring.material_override = r_mat
	lotus_root.add_child(ring)

	# 3D 盛开金莲：8片外层舒展花瓣 + 6片内层挺拔花瓣
	var petal_mats: Array[ShaderMaterial] = []
	var outer_petal_mesh := _generate_curved_petal_mesh(0.45, 0.80, 0.22, 16, 8)
	var outer_count := 8
	for i in range(outer_count):
		var angle := float(i) * (TAU / float(outer_count))
		var p_inst := MeshInstance3D.new()
		p_inst.mesh = outer_petal_mesh

		var p_mat := ShaderMaterial.new()
		p_mat.shader = GoldenOsmanthusLotusShader
		p_mat.set_shader_parameter("color_pure_gold", Color(1.0, 0.78, 0.08, 0.95))
		p_mat.set_shader_parameter("color_bright_sun", Color(1.0, 0.92, 0.45, 0.98))
		p_mat.set_shader_parameter("color_moon_halo", Color(1.0, 0.98, 0.80, 0.90))
		p_mat.set_shader_parameter("growth_progress", 0.0)
		p_mat.set_shader_parameter("fade", 1.0)
		p_inst.material_override = p_mat
		petal_mats.append(p_mat)

		p_inst.position = Vector3(cos(angle) * 0.24, 0.0, sin(angle) * 0.24)
		p_inst.rotation = Vector3(0.55, -angle + PI * 0.5, 0.0)
		lotus_root.add_child(p_inst)

	var inner_petal_mesh := _generate_curved_petal_mesh(0.35, 0.65, 0.14, 16, 8)
	var inner_count := 6
	for i in range(inner_count):
		var angle := float(i) * (TAU / float(inner_count)) + 0.52
		var p_inst := MeshInstance3D.new()
		p_inst.mesh = inner_petal_mesh

		var p_mat := ShaderMaterial.new()
		p_mat.shader = GoldenOsmanthusLotusShader
		p_mat.set_shader_parameter("color_pure_gold", Color(1.0, 0.82, 0.15, 0.95))
		p_mat.set_shader_parameter("color_bright_sun", Color(1.0, 0.96, 0.55, 0.98))
		p_mat.set_shader_parameter("color_moon_halo", Color(1.0, 1.0, 0.90, 0.95))
		p_mat.set_shader_parameter("growth_progress", 0.0)
		p_mat.set_shader_parameter("fade", 1.0)
		p_inst.material_override = p_mat
		petal_mats.append(p_mat)

		p_inst.position = Vector3(cos(angle) * 0.12, 0.02, sin(angle) * 0.12)
		p_inst.rotation = Vector3(0.30, -angle + PI * 0.5, 0.0)
		lotus_root.add_child(p_inst)

	# 绽放与留存消散动画
	ring.scale = Vector3(0.2, 0.2, 0.2)
	var tw := lotus_root.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float):
		if is_instance_valid(r_mat):
			r_mat.set_shader_parameter("fade", v)
	, 1.0, 0.0, 0.35).set_ease(Tween.EASE_IN)

	for p_mat in petal_mats:
		tw.tween_method(func(v: float):
			if is_instance_valid(p_mat):
				p_mat.set_shader_parameter("growth_progress", v)
		, 0.0, 1.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	var fade_tw := lotus_root.create_tween()
	fade_tw.tween_interval(1.8)
	for p_mat in petal_mats:
		fade_tw.parallel().tween_method(func(v: float):
			if is_instance_valid(p_mat):
				p_mat.set_shader_parameter("fade", v)
		, 1.0, 0.0, 0.45)
	fade_tw.chain().tween_callback(lotus_root.queue_free)

## 挂载于角色的折桂灵韵：复用项目统一 WeaponTrail 三轨流光引擎的双足飘带 + 双手桂花微粒
static func _spawn_osmanthus_buff_aura(caster: CharacterBody3D, dur: float, parent: Node) -> Node3D:
	if parent == null or not is_instance_valid(parent):
		parent = caster

	var aura_root := Node3D.new()
	aura_root.name = "OsmanthusBuffAura"
	parent.add_child(aura_root)

	# 1. 左右足部各创建一对锚点节点 (Left & Right Foot Anchors)
	var l_anchor_base := Node3D.new()
	var l_anchor_tip := Node3D.new()
	var r_anchor_base := Node3D.new()
	var r_anchor_tip := Node3D.new()

	aura_root.add_child(l_anchor_base)
	aura_root.add_child(l_anchor_tip)
	aura_root.add_child(r_anchor_base)
	aura_root.add_child(r_anchor_tip)

	# 2. 复用统一的 WeaponTrail 服务层与 TrailPalette "gold" 金色预设
	var trail_cfg: Dictionary = {
		"palette": "gold",
		"energy": 1.4,
		"life": 0.85,
		"min_speed": 0.12,
		"particles": 0.0,
		"light": 0.0,
		"width": 0.20
	}

	var left_trail: WeaponTrail = WeaponTrail.start(parent, trail_cfg)
	if left_trail != null:
		left_trail.bind_anchors(l_anchor_base, l_anchor_tip)
		left_trail.open()

	var right_trail: WeaponTrail = WeaponTrail.start(parent, trail_cfg)
	if right_trail != null:
		right_trail.bind_anchors(r_anchor_base, r_anchor_tip)
		right_trail.open()

	# 3. 双手金色四瓣桂花微粒发射器 (Hands Osmanthus Grains)
	var left_hand_grains := _create_hand_grains(true)
	var right_hand_grains := _create_hand_grains(false)
	aura_root.add_child(left_hand_grains)
	aura_root.add_child(right_hand_grains)

	# 动态骨骼跟踪
	var skel: Skeleton3D = AnimPipelineScript.first_of_class(caster, "Skeleton3D") as Skeleton3D
	var l_hand_idx := -1
	var r_hand_idx := -1
	var l_foot_idx := -1
	var r_foot_idx := -1

	if skel != null:
		for b in range(skel.get_bone_count()):
			var b_name := skel.get_bone_name(b).to_lower()
			if "hand" in b_name or "wrist" in b_name:
				if "l" in b_name or "left" in b_name:
					l_hand_idx = b
				elif "r" in b_name or "right" in b_name:
					r_hand_idx = b
			elif "foot" in b_name or "toe" in b_name or "ankle" in b_name:
				if "l" in b_name or "left" in b_name:
					l_foot_idx = b
				elif "r" in b_name or "right" in b_name:
					r_foot_idx = b

	var tw := aura_root.create_tween()
	tw.set_parallel(true)
	tw.tween_method(func(_t: float):
		if is_instance_valid(caster) and is_instance_valid(aura_root):
			aura_root.global_position = caster.global_position
			
			var root_pos := caster.global_position
			var l_foot_pos := root_pos + caster.global_basis.x * -0.22 + Vector3.UP * 0.08
			var r_foot_pos := root_pos + caster.global_basis.x * 0.22 + Vector3.UP * 0.08

			if skel != null and is_instance_valid(skel):
				if l_foot_idx >= 0:
					l_foot_pos = (skel.global_transform * skel.get_bone_global_pose(l_foot_idx)).origin
				if r_foot_idx >= 0:
					r_foot_pos = (skel.global_transform * skel.get_bone_global_pose(r_foot_idx)).origin
				if l_hand_idx >= 0 and is_instance_valid(left_hand_grains):
					left_hand_grains.global_position = (skel.global_transform * skel.get_bone_global_pose(l_hand_idx)).origin
				if r_hand_idx >= 0 and is_instance_valid(right_hand_grains):
					right_hand_grains.global_position = (skel.global_transform * skel.get_bone_global_pose(r_hand_idx)).origin

			# 设置左右足部的飘带宽度锚点（左右两点定义飘带跨度）
			var l_span := caster.global_basis.x * 0.10
			l_anchor_base.global_position = l_foot_pos - l_span
			l_anchor_tip.global_position = l_foot_pos + l_span

			var r_span := caster.global_basis.x * 0.10
			r_anchor_base.global_position = r_foot_pos - r_span
			r_anchor_tip.global_position = r_foot_pos + r_span
	, 0.0, 1.0, dur)

	tw.chain().tween_callback(func():
		if is_instance_valid(left_hand_grains):
			left_hand_grains.emitting = false
		if is_instance_valid(right_hand_grains):
			right_hand_grains.emitting = false
		if is_instance_valid(left_trail):
			left_trail.seal()
		if is_instance_valid(right_trail):
			right_trail.seal()
	)
	tw.chain().tween_interval(1.2)
	tw.chain().tween_callback(aura_root.queue_free)

	return aura_root

static func _create_hand_grains(is_left: bool) -> CPUParticles3D:
	var parts := CPUParticles3D.new()
	parts.name = "HandOsmanthusGrains_%s" % ("L" if is_left else "R")
	parts.amount = 24
	parts.lifetime = 0.9
	parts.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	parts.emission_sphere_radius = 0.16
	parts.direction = Vector3(0, -0.2, -0.6).normalized()
	parts.spread = 40.0
	parts.gravity = Vector3(0.0, -0.6, 0.0) # 轻柔下落
	parts.initial_velocity_min = 0.5
	parts.initial_velocity_max = 1.4
	parts.scale_amount_min = 0.6
	parts.scale_amount_max = 1.3

	var qm := QuadMesh.new()
	qm.size = Vector2(0.09, 0.09)
	var g_mat := ShaderMaterial.new()
	g_mat.shader = OsmanthusGrainShader
	g_mat.set_shader_parameter("color_osmanthus_gold", Color(1.0, 0.82, 0.15, 0.90))
	g_mat.set_shader_parameter("color_osmanthus_bright", Color(1.0, 0.96, 0.60, 0.95))
	parts.mesh = qm
	parts.material_override = g_mat
	parts.position = Vector3(-0.35 if is_left else 0.35, 1.1, 0.0)
	parts.emitting = true
	return parts

## 参数化曲面花瓣网格生成算法
static func _generate_curved_petal_mesh(width: float, height: float, curvature: float, segments_u: int, segments_v: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	for u_idx in range(segments_u + 1):
		var u := float(u_idx) / float(segments_u)
		var y := u * height
		var z_arch := sin(u * PI * 0.82) * curvature
		var width_factor := pow(sin(u * PI), 0.65) * (1.0 + 0.15 * sin(u * PI * 2.0))
		var cur_half_w := (width * 0.5) * maxf(width_factor, 0.01)

		for v_idx in range(segments_v + 1):
			var v := (float(v_idx) / float(segments_v) - 0.5) * 2.0
			var x := v * cur_half_w
			var z_cup := -(v * v) * (curvature * 0.35) * sin(u * PI)
			var pos := Vector3(x, y, z_arch + z_cup)
			verts.append(pos)
			normals.append(Vector3(0, 0, 1).normalized())
			uvs.append(Vector2((v + 1.0) * 0.5, u))

	var row_size := segments_v + 1
	for u_idx in range(segments_u):
		for v_idx in range(segments_v):
			var a := u_idx * row_size + v_idx
			var b := a + 1
			var c := (u_idx + 1) * row_size + v_idx
			var d := c + 1

			# Front
			indices.append(a)
			indices.append(c)
			indices.append(b)

			indices.append(b)
			indices.append(c)
			indices.append(d)

			# Back
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

## reset_state(): drops jump-buff bookkeeping. Scene entry only.
func reset_state() -> void:
	_active_buffs.clear()


func preload_assets() -> void:
	AudioManagerScript.preload_sounds([
		"res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg"
	])

func get_warmup_materials() -> Array:
	var m_ring := ShaderMaterial.new()
	m_ring.shader = SonicRingShader
	VfxTextures.bind(m_ring, "ring_tex", VfxTextures.SHOCKWAVE_RING, "tex_mix", 0.9)

	var m_lotus := ShaderMaterial.new()
	m_lotus.shader = GoldenOsmanthusLotusShader

	var m_grain := ShaderMaterial.new()
	m_grain.shader = OsmanthusGrainShader

	return [m_ring, m_lotus, m_grain]
