extends "res://scripts/skills/skill_base.gd"
## 孽血业火·十方核爆喷火血莲壮观火屏 (Spectacular Blood-Lotus Atomic Flame Barrier).
## 外圈环绕10座深红血红莲花，莲心向上喷射高耸壮观的原子弹式黑红翻滚巨型火柱（5.8m+冲天火柱与翻滚蘑菇烟冠）；
## 中部保持单层实体模型，通过立体波动Shader渲染深红孽血与极为醒目的幽蓝等离子火流。

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const FlameWallShader = preload("res://shaders/flame_wall.gdshader")
const CrimsonLotusPetalShader = preload("res://shaders/crimson_lotus_petal.gdshader")
const LotusFireSigilShader = preload("res://shaders/lotus_fire_sigil.gdshader")
const LotusFlameJetShader = preload("res://shaders/lotus_flame_jet.gdshader")

## Horizontal span of the wall (m).
var wall_length: float = 6.0
## Wall height (m) — tall enough that jumping cannot clear it.
var wall_height: float = 3.6
## Wall lifetime (s).
var wall_duration: float = 4.0
## Max distance the wall centre may sit from the caster (m).
var cast_range: float = 12.0

const GROUND_Y: float = 0.03

func get_id() -> String:
	return "wall"

func get_name() -> String:
	return "🔥 红莲断 (十方核焰红莲屏)"

func get_title() -> String:
	return "🔥 红莲断配置 (SPECTACULAR BLOOD LOTUS)"

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
	var len_lbl := Label.new()
	len_lbl.text = "红莲屏障宽度 (Span): %.1fm" % wall_length
	len_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(len_lbl)

	var len_slider := HSlider.new()
	len_slider.min_value = 3.0
	len_slider.max_value = 14.0
	len_slider.step = 0.5
	len_slider.value = wall_length
	len_slider.value_changed.connect(func(v: float):
		wall_length = v
		len_lbl.text = "红莲屏障宽度 (Span): %.1fm" % v
		on_changed.call("wall_length", v)
	)
	container.add_child(len_slider)

	var h_lbl := Label.new()
	h_lbl.text = "屏障火焰高度 (Height): %.1fm" % wall_height
	h_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(h_lbl)

	var h_slider := HSlider.new()
	h_slider.min_value = 2.0
	h_slider.max_value = 7.0
	h_slider.step = 0.5
	h_slider.value = wall_height
	h_slider.value_changed.connect(func(v: float):
		wall_height = v
		h_lbl.text = "屏障火焰高度 (Height): %.1fm" % v
		on_changed.call("wall_height", v)
	)
	container.add_child(h_slider)

	var dur_lbl := Label.new()
	dur_lbl.text = "存在持续时间 (Duration): %.1fs" % wall_duration
	dur_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(dur_lbl)

	var dur_slider := HSlider.new()
	dur_slider.min_value = 1.0
	dur_slider.max_value = 10.0
	dur_slider.step = 0.5
	dur_slider.value = wall_duration
	dur_slider.value_changed.connect(func(v: float):
		wall_duration = v
		dur_lbl.text = "存在持续时间 (Duration): %.1fs" % v
		on_changed.call("wall_duration", v)
	)
	container.add_child(dur_slider)

	var tip_panel := PanelContainer.new()
	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.18, 0.01, 0.04, 0.90)
	t_style.set_corner_radius_all(6)
	t_style.set_border_width_all(1)
	t_style.border_color = Color(0.85, 0.05, 0.20, 0.8)
	t_style.set_content_margin_all(8)
	tip_panel.add_theme_stylebox_override("panel", t_style)
	container.add_child(tip_panel)

	var tip_vbox := VBoxContainer.new()
	tip_vbox.add_theme_constant_override("separation", 4)
	tip_panel.add_child(tip_vbox)

	var tip1 := Label.new()
	tip1.text = "🌋 外圈10座血莲喷射 5.8m+ 壮观原子弹蘑菇云翻滚烟火柱"
	tip1.add_theme_font_size_override("font_size", 11)
	tip1.modulate = Color(1.0, 0.35, 0.45)
	tip_vbox.add_child(tip1)

	var tip2 := Label.new()
	tip2.text = "🔥 中部单层实体模型，渲染醒目幽蓝等离子火流与深红孽血"
	tip2.add_theme_font_size_override("font_size", 11)
	tip2.modulate = Color(0.2, 0.85, 1.5)
	tip_vbox.add_child(tip2)

	var tip3 := Label.new()
	tip3.text = "🚫 实体碰撞阻隔翻滚与跳跃，消散时化作飞扬业火星屑"
	tip3.add_theme_font_size_override("font_size", 11)
	tip3.modulate = Color(0.9, 0.8, 0.4)
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

	var wall_dir := Vector3(aim_dir.z, 0.0, -aim_dir.x)

	var zone := WallZone.new()
	zone.name = "CrimsonLotusWall"
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

## A living Blood-Lotus flame barrier: outer ring fire-spouting lotuses, single-mesh volumetric flame screen.
class WallZone extends Node3D:
	var length: float = 6.0
	var height: float = 3.6
	var duration: float = 4.0

	var _elapsed: float = 0.0
	var _dead: bool = false
	var _body: StaticBody3D
	var _collider: CollisionShape3D
	var _outer_lotuses_root: Node3D
	var _lotus_materials: Array[ShaderMaterial] = []
	var _flame_jet_materials: Array[ShaderMaterial] = []
	var _flame_screen: MeshInstance3D
	var _flame_mat: ShaderMaterial
	var _ground_sigil: MeshInstance3D
	var _sigil_mat: ShaderMaterial
	var _embers: CPUParticles3D

	func _ready() -> void:
		_build_visuals()

	func _physics_process(delta: float) -> void:
		if _dead:
			return
		_elapsed += delta
		if _elapsed >= duration:
			_dead = true
			_dissolve()

	func _dissolve() -> void:
		if _collider != null and is_instance_valid(_collider):
			_collider.set_deferred("disabled", true)
		var tw := create_tween().set_parallel(true)
		for p_mat in _lotus_materials:
			if is_instance_valid(p_mat):
				tw.tween_method(func(v: float):
					if is_instance_valid(p_mat):
						p_mat.set_shader_parameter("fade", v)
				, 1.0, 0.0, 0.35)
		for j_mat in _flame_jet_materials:
			if is_instance_valid(j_mat):
				tw.tween_method(func(v: float):
					if is_instance_valid(j_mat):
						j_mat.set_shader_parameter("fade", v)
				, 1.0, 0.0, 0.35)
		if _flame_mat != null and is_instance_valid(_flame_mat):
			tw.tween_method(func(v: float):
				if is_instance_valid(_flame_mat):
					_flame_mat.set_shader_parameter("fade", v)
			, 1.0, 0.0, 0.35)
		if _sigil_mat != null and is_instance_valid(_sigil_mat):
			tw.tween_method(func(v: float):
				if is_instance_valid(_sigil_mat):
					_sigil_mat.set_shader_parameter("fade", v)
			, 1.0, 0.0, 0.35)
		if _embers != null and is_instance_valid(_embers):
			_embers.emitting = false
		tw.chain().tween_callback(queue_free)

	func _build_visuals() -> void:
		var len := maxf(length, 1.0)
		var h := maxf(height, 1.0)

		# 1. 物理屏障 (Physical Collision Barrier)
		_body = StaticBody3D.new()
		_body.name = "FlameWallBody"
		_collider = CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(len, h, 0.45)
		_collider.shape = box
		_collider.position.y = h * 0.5
		_body.add_child(_collider)
		add_child(_body)

		# 2. 地面深红孽血八瓣神火地阵 (Deep Blood-Ruby Ground Sigil)
		_ground_sigil = MeshInstance3D.new()
		_ground_sigil.name = "LotusGroundSigil"
		var g_quad := QuadMesh.new()
		var sigil_size_x := len * 1.30
		var sigil_size_z := 3.4
		g_quad.size = Vector2(sigil_size_x, sigil_size_z)
		_ground_sigil.mesh = g_quad
		_ground_sigil.rotation.x = -PI * 0.5
		_ground_sigil.position.y = 0.02

		_sigil_mat = ShaderMaterial.new()
		_sigil_mat.shader = LotusFireSigilShader
		_sigil_mat.set_shader_parameter("color_root_blue", Color(0.02, 0.72, 1.25, 0.95))
		_sigil_mat.set_shader_parameter("color_gold", Color(0.95, 0.40, 0.12, 0.90))
		_sigil_mat.set_shader_parameter("color_crimson", Color(0.85, 0.02, 0.10, 0.92))
		_sigil_mat.set_shader_parameter("spin_speed", 1.0)
		_sigil_mat.set_shader_parameter("pulse_speed", 2.2)
		_sigil_mat.set_shader_parameter("fade", 1.0)
		_ground_sigil.material_override = _sigil_mat
		add_child(_ground_sigil)

		# 3. 外圈环绕 10 座深红血红莲花台（莲心向上喷射 5.8m+ 壮观原子弹蘑菇云火柱）
		_outer_lotuses_root = Node3D.new()
		_outer_lotuses_root.name = "OuterRingLotuses"
		add_child(_outer_lotuses_root)

		var outer_count := 10
		var rad_x := len * 0.54
		var rad_z := 1.35
		var grand_jet_h := maxf(h * 1.65, 5.8)

		for i in range(outer_count):
			var theta := float(i) * (TAU / float(outer_count))
			var pos := Vector3(cos(theta) * rad_x, 0.0, sin(theta) * rad_z)
			
			var is_tip := absf(pos.x) >= len * 0.45
			var s_factor: float = 0.55 if is_tip else 0.45
			var flower_node := _build_complete_spectacular_fire_lotus(s_factor, grand_jet_h)
			flower_node.position = pos
			flower_node.rotation.y = theta + PI * 0.5
			_outer_lotuses_root.add_child(flower_node)

		# 4. 中部单层实体模型 (Single-Mesh Volumetric Flame Screen with Vivid Azure Core)
		_flame_screen = MeshInstance3D.new()
		_flame_screen.name = "CentralFlameScreen"
		var qm := QuadMesh.new()
		qm.size = Vector2(len, h)
		_flame_screen.mesh = qm
		_flame_screen.position.y = h * 0.5

		_flame_mat = ShaderMaterial.new()
		_flame_mat.shader = FlameWallShader
		_flame_mat.set_shader_parameter("flame_azure_blue", Color(0.02, 0.72, 1.25, 0.95))
		_flame_mat.set_shader_parameter("flame_blood_crimson", Color(0.85, 0.02, 0.10, 0.92))
		_flame_mat.set_shader_parameter("flame_dark_soot", Color(0.10, 0.00, 0.02, 0.92))
		_flame_mat.set_shader_parameter("flame_gold_wisp", Color(1.0, 0.55, 0.12, 0.85))
		_flame_mat.set_shader_parameter("speed", 4.2)
		_flame_mat.set_shader_parameter("flame_density", maxf(len * 2.2, 8.0))
		_flame_mat.set_shader_parameter("blue_dominance", 1.35)
		_flame_mat.set_shader_parameter("thickness_wave", 0.18)
		_flame_mat.set_shader_parameter("fade", 1.0)
		_flame_screen.material_override = _flame_mat
		add_child(_flame_screen)

		# 5. 升腾红莲业火微光星屑 (Ascending Blood Lotus Sparks)
		_embers = _spawn_lotus_embers(len, h, self)

		# 6. 破土绽放动态展开 (Blooming Unfurling in 0.28s)
		_ground_sigil.scale = Vector3(0.2, 0.2, 0.2)
		_outer_lotuses_root.scale = Vector3(0.2, 0.2, 0.2)
		_flame_screen.scale = Vector3(1.0, 0.05, 1.0)

		var tw := create_tween().set_parallel(true)
		tw.tween_property(_ground_sigil, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_outer_lotuses_root, "scale", Vector3.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_flame_screen, "scale", Vector3.ONE, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

		for p_mat in _lotus_materials:
			tw.tween_method(func(v: float):
				if is_instance_valid(p_mat):
					p_mat.set_shader_parameter("growth_progress", v)
			, 0.0, 1.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	## 组装一朵喷射壮观巨型原子弹蘑菇云黑红烟火柱的深红血红莲花
	func _build_complete_spectacular_fire_lotus(scale_factor: float, jet_height: float) -> Node3D:
		var flower := Node3D.new()
		flower.name = "SpectacularFireLotusFlower"

		# 外层 8 片舒展深红血红花瓣
		var outer_count := 8
		var outer_petal_mesh := _generate_curved_lotus_petal_mesh(0.48 * scale_factor, 0.86 * scale_factor, 0.22 * scale_factor, 16, 8)
		for i in range(outer_count):
			var angle := float(i) * (TAU / float(outer_count))
			var p_inst := MeshInstance3D.new()
			p_inst.mesh = outer_petal_mesh

			var p_mat := ShaderMaterial.new()
			p_mat.shader = CrimsonLotusPetalShader
			p_mat.set_shader_parameter("color_root_blue", Color(0.02, 0.72, 1.25, 0.95))
			p_mat.set_shader_parameter("color_blood_shadow", Color(0.18, 0.00, 0.03, 0.95))
			p_mat.set_shader_parameter("color_blood_ruby", Color(0.88, 0.02, 0.12, 0.92))
			p_mat.set_shader_parameter("color_carmine_vein", Color(1.0, 0.35, 0.20, 0.90))
			p_mat.set_shader_parameter("pulse_speed", 2.6)
			p_mat.set_shader_parameter("growth_progress", 0.0)
			p_mat.set_shader_parameter("fade", 1.0)
			p_inst.material_override = p_mat
			_lotus_materials.append(p_mat)

			p_inst.position = Vector3(cos(angle) * (0.24 * scale_factor), 0.0, sin(angle) * (0.24 * scale_factor))
			p_inst.rotation = Vector3(0.55, -angle + PI * 0.5, 0.0)
			flower.add_child(p_inst)

		# 内层 6 片挺立花瓣
		var inner_count := 6
		var inner_petal_mesh := _generate_curved_lotus_petal_mesh(0.38 * scale_factor, 0.72 * scale_factor, 0.14 * scale_factor, 16, 8)
		for i in range(inner_count):
			var angle := float(i) * (TAU / float(inner_count)) + 0.52
			var p_inst := MeshInstance3D.new()
			p_inst.mesh = inner_petal_mesh

			var p_mat := ShaderMaterial.new()
			p_mat.shader = CrimsonLotusPetalShader
			p_mat.set_shader_parameter("color_root_blue", Color(0.02, 0.72, 1.25, 0.95))
			p_mat.set_shader_parameter("color_blood_shadow", Color(0.18, 0.00, 0.03, 0.95))
			p_mat.set_shader_parameter("color_blood_ruby", Color(0.92, 0.04, 0.14, 0.92))
			p_mat.set_shader_parameter("color_carmine_vein", Color(1.0, 0.40, 0.22, 0.92))
			p_mat.set_shader_parameter("pulse_speed", 2.8)
			p_mat.set_shader_parameter("growth_progress", 0.0)
			p_mat.set_shader_parameter("fade", 1.0)
			p_inst.material_override = p_mat
			_lotus_materials.append(p_mat)

			p_inst.position = Vector3(cos(angle) * (0.12 * scale_factor), 0.02, sin(angle) * (0.12 * scale_factor))
			p_inst.rotation = Vector3(0.30, -angle + PI * 0.5, 0.0)
			flower.add_child(p_inst)

		# 莲心向上喷射的 5.8m+ 壮观原子弹蘑菇云烟火柱 (3层交叉大体量火柱)
		var jet_mesh := QuadMesh.new()
		jet_mesh.size = Vector2(1.35 * scale_factor, jet_height)
		
		for j in range(3):
			var jet_inst := MeshInstance3D.new()
			jet_inst.mesh = jet_mesh
			jet_inst.position.y = jet_height * 0.5
			jet_inst.rotation.y = float(j) * (TAU / 3.0)

			var j_mat := ShaderMaterial.new()
			j_mat.shader = LotusFlameJetShader
			j_mat.set_shader_parameter("flame_blood_crimson", Color(0.95, 0.02, 0.10, 0.96))
			j_mat.set_shader_parameter("smoke_dark_charcoal", Color(0.05, 0.00, 0.01, 0.94))
			j_mat.set_shader_parameter("vein_carmine_glow", Color(1.0, 0.35, 0.15, 0.98))
			j_mat.set_shader_parameter("base_blue_plasma", Color(0.02, 0.85, 1.60, 0.95))
			j_mat.set_shader_parameter("speed", 5.6 + randf_range(-0.4, 0.4))
			j_mat.set_shader_parameter("fade", 1.0)
			jet_inst.material_override = j_mat
			_flame_jet_materials.append(j_mat)

			flower.add_child(jet_inst)

		return flower

	## 程序化曲面3D红莲花瓣网格生成算法 (Parametric Curved 3D Lotus Petal Mesh)
	static func _generate_curved_lotus_petal_mesh(width: float, height: float, curvature: float, segments_u: int, segments_v: int) -> ArrayMesh:
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

	static func _spawn_lotus_embers(len: float, h: float, parent: Node) -> CPUParticles3D:
		var parts := CPUParticles3D.new()
		parts.name = "LotusEmbers"
		parts.amount = 36
		parts.lifetime = 1.6
		parts.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		parts.emission_box_extents = Vector3(len * 0.50, 0.15, 0.8)
		parts.direction = Vector3.UP
		parts.spread = 20.0
		parts.gravity = Vector3(0, 0.5, 0)
		parts.initial_velocity_min = 1.0
		parts.initial_velocity_max = 2.4
		parts.scale_amount_min = 0.5
		parts.scale_amount_max = 1.3

		var p_mesh := QuadMesh.new()
		p_mesh.size = Vector2(0.12, 0.12)
		var p_mat := StandardMaterial3D.new()
		p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		p_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		p_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		p_mat.albedo_color = Color(0.95, 0.35, 0.18, 0.85)
		p_mat.albedo_texture = VfxTextures.get_tex(VfxTextures.FLASH_GLOW)
		parts.mesh = p_mesh
		parts.material_override = p_mat

		parent.add_child(parts)
		parts.position.y = 0.1
		parts.emitting = true
		return parts

func preload_assets() -> void:
	AudioManagerScript.preload_sounds([
		"res://assets/voice/RPGsounds_Kenney/OGG/knifeSlice.ogg"
	])

func get_warmup_materials() -> Array:
	var m_petal := ShaderMaterial.new()
	m_petal.shader = CrimsonLotusPetalShader
	var m_sigil := ShaderMaterial.new()
	m_sigil.shader = LotusFireSigilShader
	var m_flame := ShaderMaterial.new()
	m_flame.shader = FlameWallShader
	var m_jet := ShaderMaterial.new()
	m_jet.shader = LotusFlameJetShader
	return [m_petal, m_sigil, m_flame, m_jet]