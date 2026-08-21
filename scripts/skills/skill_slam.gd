extends "res://scripts/skills/skill_base.gd"
## Skill 9: Ground Slam (裂地崩击).
## Caster leaps high and slams ground with magma fissures.
## Entities are launched into parabolic air flight to varying degrees depending on distance from epicenter, then stay knocked down until standing up.

const AudioManagerScript = preload("res://scripts/audio_manager.gd")

var slam_radius: float = 8.0
var leap_height: float = 4.5
var leap_time: float = 0.38
var slam_time: float = 0.20
var max_launch_dist: float = 7.5
var max_launch_height: float = 3.2
var fall_duration: float = 1.8

static var _fissure_material: StandardMaterial3D = null
static var _shockwave_material: StandardMaterial3D = null


func get_id() -> String:
	return "slam"


func get_name() -> String:
	return "💥 裂地崩击 (地面裂纹)"


func get_title() -> String:
	return "💥 裂地崩击配置 (GROUND SLAM / EARTHQUAKE)"


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
	t_style.border_color = Color(1.0, 0.55, 0.2, 0.65)
	t_style.set_content_margin_all(8)
	tip_panel.add_theme_stylebox_override("panel", t_style)
	container.add_child(tip_panel)

	var tip_vbox := VBoxContainer.new()
	tip_vbox.add_theme_constant_override("separation", 4)
	tip_panel.add_child(tip_vbox)

	var tip1 := Label.new()
	tip1.text = "🚀 角色高高跃起至空中汇聚能量，随后极速重砸地面"
	tip1.add_theme_font_size_override("font_size", 11)
	tip1.modulate = Color(1.0, 0.8, 0.4)
	tip_vbox.add_child(tip1)

	var tip2 := Label.new()
	tip2.text = "🌋 落地生成立体熔岩地裂带、崩裂岩坑与突起碎石刺"
	tip2.add_theme_font_size_override("font_size", 11)
	tip2.modulate = Color(1.0, 0.5, 0.2)
	tip_vbox.add_child(tip2)

	var tip3 := Label.new()
	tip3.text = "💥 随距中心距离由近及远呈不同程度抛物线弹飞浮空并倒地摔平"
	tip3.add_theme_font_size_override("font_size", 11)
	tip3.modulate = Color(0.9, 0.9, 0.9)
	tip_vbox.add_child(tip3)


func _execute_slam(caster: CharacterBody3D, parent: Node) -> Dictionary:
	var start_pos := caster.global_position
	var fwd := caster.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 0.01:
		fwd = fwd.normalized()
	else:
		fwd = Vector3.FORWARD

	var apex_pos := start_pos + Vector3.UP * leap_height + fwd * 0.8
	var landing_pos := start_pos + fwd * 1.5
	landing_pos.y = start_pos.y

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

	_ensure_materials()

	var shockwave := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.3
	torus.outer_radius = 0.7
	torus.rings = 24
	torus.ring_segments = 12
	shockwave.mesh = torus
	shockwave.position.y = 0.05
	var wave_mat := _shockwave_material.duplicate() as StandardMaterial3D
	shockwave.material_override = wave_mat
	vfx.add_child(shockwave)

	var fissure_inst := MeshInstance3D.new()
	fissure_inst.mesh = _build_unified_fissure_mesh(slam_radius)
	fissure_inst.position.y = 0.04
	var f_mat := _fissure_material.duplicate() as StandardMaterial3D
	fissure_inst.material_override = f_mat
	vfx.add_child(fissure_inst)

	var max_wave_scale := slam_radius * 1.8
	var tw := vfx.create_tween().set_parallel(true)
	tw.tween_property(shockwave, "scale", Vector3(max_wave_scale, 1.0, max_wave_scale), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(wave_mat, "albedo_color:a", 0.0, 0.40).set_ease(Tween.EASE_IN)
	tw.tween_property(fissure_inst, "scale", Vector3(1.0, 1.0, 1.0), 0.25).from(Vector3(0.08, 1.0, 0.08)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	tw.chain().tween_property(f_mat, "albedo_color:a", 0.0, 2.2).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(vfx.queue_free)


func _ensure_materials() -> void:
	if _fissure_material == null:
		_fissure_material = StandardMaterial3D.new()
		_fissure_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_fissure_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_fissure_material.vertex_color_use_as_albedo = true
		_fissure_material.albedo_color = Color(1.0, 0.65, 0.25, 1.0)
		_fissure_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	if _shockwave_material == null:
		_shockwave_material = StandardMaterial3D.new()
		_shockwave_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shockwave_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_shockwave_material.albedo_color = Color(1.0, 0.55, 0.15, 0.9)
		_shockwave_material.cull_mode = BaseMaterial3D.CULL_DISABLED


func _build_unified_fissure_mesh(radius: float) -> ImmediateMesh:
	var imm := ImmediateMesh.new()
	imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	var num_branches := 8
	var segments_per_branch := 6
	var angle_step := TAU / float(num_branches)

	for b in num_branches:
		var base_angle := b * angle_step + randf_range(-0.12, 0.12)
		var pts: Array[Vector3] = [Vector3.ZERO]
		var widths: Array[float] = [0.42]

		var cur_pt := Vector3.ZERO
		for s in range(1, segments_per_branch + 1):
			var frac := float(s) / float(segments_per_branch)
			var dist := frac * radius * randf_range(0.9, 1.05)
			var cur_angle := base_angle + randf_range(-0.25, 0.25)
			var next_pt := Vector3(cos(cur_angle) * dist, 0.0, sin(cur_angle) * dist)
			var w := lerpf(0.38, 0.05, frac)

			pts.append(next_pt)
			widths.append(w)
			cur_pt = next_pt

		_build_ribbon_quads(imm, pts, widths)

		for s in [2, 4]:
			if s < pts.size():
				_build_shard_tri(imm, pts[s], 0.35 * (1.0 - float(s) / float(segments_per_branch)))

	imm.surface_end()
	return imm


func _build_ribbon_quads(imm: ImmediateMesh, pts: Array[Vector3], widths: Array[float]) -> void:
	if pts.size() < 2:
		return

	for i in range(pts.size() - 1):
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var dir := (p1 - p0).normalized()
		var norm := Vector3(-dir.z, 0.0, dir.x)

		var w0 := widths[i] * 0.5
		var w1 := widths[i + 1] * 0.5

		var left0 := p0 + norm * w0
		var right0 := p0 - norm * w0
		var left1 := p1 + norm * w1
		var right1 := p1 - norm * w1

		var frac0 := float(i) / float(pts.size() - 1)
		var frac1 := float(i + 1) / float(pts.size() - 1)

		var col_core := Color(1.0, 0.90, 0.55, 1.0)
		var col_edge0 := Color(1.0, lerpf(0.55, 0.12, frac0), 0.05, 1.0 - frac0 * 0.35)
		var col_edge1 := Color(1.0, lerpf(0.55, 0.12, frac1), 0.05, 1.0 - frac1 * 0.35)

		imm.surface_set_color(col_edge0)
		imm.surface_add_vertex(left0)
		imm.surface_set_color(col_edge1)
		imm.surface_add_vertex(left1)
		imm.surface_set_color(col_core)
		imm.surface_add_vertex(right0)

		imm.surface_set_color(col_core)
		imm.surface_add_vertex(right0)
		imm.surface_set_color(col_edge1)
		imm.surface_add_vertex(left1)
		imm.surface_set_color(col_edge1)
		imm.surface_add_vertex(right1)


func _build_shard_tri(imm: ImmediateMesh, pos: Vector3, size: float) -> void:
	var top := pos + Vector3(0.0, size * 1.5, 0.0)
	var p0 := pos + Vector3(size, 0.0, 0.0)
	var p1 := pos + Vector3(-size * 0.5, 0.0, size * 0.86)
	var p2 := pos + Vector3(-size * 0.5, 0.0, -size * 0.86)

	var col := Color(0.9, 0.45, 0.15, 0.9)
	imm.surface_set_color(col)
	imm.surface_add_vertex(p0)
	imm.surface_add_vertex(top)
	imm.surface_add_vertex(p1)

	imm.surface_set_color(col)
	imm.surface_add_vertex(p1)
	imm.surface_add_vertex(top)
	imm.surface_add_vertex(p2)


func _apply_slam_impact(caster: CharacterBody3D, impact_pos: Vector3) -> void:
	if caster == null or not is_instance_valid(caster) or not caster.is_inside_tree():
		return
	var tree := caster.get_tree()
	if tree == null:
		return

	var center := impact_pos
	center.y = 0.0
	var radius := maxf(slam_radius, 0.5)

	var bodies := tree.root.find_children("", "CharacterBody3D", true, false)
	for b in bodies:
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
		var launch_factor := pow(1.0 - t * 0.82, 1.3) # 1.0 at center, ~0.24 at edge

		var push_dir := to.normalized() if dist > 0.08 else -cb.global_transform.basis.z
		_launch_and_knockdown(cb, push_dir, launch_factor, fall_duration)


static var _active_knockdowns: Dictionary = {}


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

	# 1. Completely disable controller physics processing so WASD input & move_and_slide are frozen
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


func preload_assets() -> void:
	AudioManagerScript.preload_sounds([
		"res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg"
	])
	_ensure_materials()


func get_warmup_materials() -> Array:
	_ensure_materials()
	return [_fissure_material, _shockwave_material]


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
