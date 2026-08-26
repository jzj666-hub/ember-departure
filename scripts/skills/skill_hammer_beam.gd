extends "res://scripts/skills/skill_base.gd"
## Skill 16: Hammer Beam / 圣辉天华 (神圣星芒光束·万华晶爆).
## 抡锤重击落点爆发神圣几何星芒万华阵：
## 1. 地面展开巨型冰晶星芒法阵与蛛网裂纹网络
## 2. 核心绽放万华镜星芒能量球与冲天星芒晶格光柱
## 3. 周围呈冠状爆发放射状冰晶光刺与飞刃
## 4. 地面环绕喷涌真实爆裂尘烟与飞溅碎石破片
## 5. 全程纯净冰晶圣光蓝白统一配色，持续多段连击轰击。

const HammerBeamColumnShader = preload("res://shaders/hammer_beam_column.gdshader")
const HammerBeamGroundShader = preload("res://shaders/hammer_beam_ground.gdshader")
const HammerBeamSphereShader = preload("res://shaders/hammer_beam_sphere.gdshader")
const HammerBeamSmokeShader = preload("res://shaders/hammer_beam_smoke.gdshader")
const HammerBeamCrystalShader = preload("res://shaders/hammer_beam_crystal.gdshader")

## 纯净神圣冰晶配色（统一色调，告别杂乱混色）
const PALETTE := {
	"core": Color(2.6, 2.9, 3.3, 1.0),      # 纯白炽光核心
	"azure": Color(0.35, 0.88, 1.35, 1.0),   # 冰晶青蓝主色
	"deep": Color(0.08, 0.45, 0.95, 0.85),   # 冰川深蓝边缘
	"frost": Color(0.70, 0.92, 1.10, 1.0),   # 霜华白亮高光
	"smoke": Color(0.65, 0.72, 0.80, 0.45),  # 真实冷调地面尘烟
	"light": Color(0.65, 0.90, 1.35),        # 圣辉点光源
}

const WINDUP_TIME := 0.6     # 动作定格时间
const BEAM_HEIGHT := 22.0    # 通天光柱高度
const HIT_INTERVAL := 0.15   # 连击伤害判定间隔 (秒)

var beam_duration: float = 2.2
var beam_radius: float = 1.3
var strike_distance: float = 7.0
var cast_range: float = 18.0
var damage: float = 15.0     # 单段连击伤害

## 静态资源缓存
static var _quad_mesh: QuadMesh = null
static var _plane_mesh: PlaneMesh = null
static var _sphere_mesh: SphereMesh = null
static var _box_mesh: BoxMesh = null
static var _warmup_mats: Array = []


func get_id() -> String:
	return "hammer_beam"


func get_name() -> String:
	return "✨ 圣辉天华 (神圣星芒光束·万华晶爆)"


func get_title() -> String:
	return "✨ 圣辉天华配置 (SACRED MANDALA BEAM)"


func get_params() -> Dictionary:
	return {
		"beam_duration": beam_duration,
		"beam_radius": beam_radius,
		"strike_distance": strike_distance,
		"damage": damage
	}


func set_param(key: String, value: Variant) -> void:
	match key:
		"beam_duration": beam_duration = clampf(float(value), 0.8, 5.0)
		"beam_radius": beam_radius = clampf(float(value), 0.6, 3.5)
		"strike_distance": strike_distance = clampf(float(value), 2.0, 15.0)
		"damage": damage = clampf(float(value), 2.0, 100.0)


func cast(caster: CharacterBody3D, intent_dir: Vector3, vfx_parent: Node, _is_spectator: bool = false) -> Dictionary:
	if caster == null or not is_instance_valid(caster):
		return {}
	var target_pos := _calculate_target_position(caster, intent_dir)
	return _execute_hammer_beam(caster, target_pos, vfx_parent)


func cast_at(caster: CharacterBody3D, target_pos: Vector3, vfx_parent: Node, _is_spectator: bool = false) -> Dictionary:
	if caster == null or not is_instance_valid(caster):
		return {}
	return _execute_hammer_beam(caster, target_pos, vfx_parent)


func replay(caster: CharacterBody3D, record: Dictionary, vfx_parent: Node) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	var target_pos: Vector3 = record.get("target_pos", caster.global_position + (caster.global_transform.basis.z if caster.is_inside_tree() else Vector3.FORWARD) * strike_distance)
	_execute_hammer_beam(caster, target_pos, vfx_parent)


func get_replay_hold_time(_record: Dictionary) -> float:
	return WINDUP_TIME + beam_duration + 1.2


func preload_assets() -> void:
	_ensure_cached_resources()


func get_warmup_materials() -> Array:
	_ensure_cached_resources()
	return _warmup_mats.duplicate()


func dispel_actor(_actor: CharacterBody3D) -> void:
	pass


func reset_state() -> void:
	pass


func build_config_panel(container: VBoxContainer, on_changed: Callable) -> void:
	var dur_lbl := Label.new()
	dur_lbl.text = "光束喷射时长 (Beam Duration): %.1fs" % beam_duration
	dur_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(dur_lbl)

	var dur_slider := HSlider.new()
	dur_slider.min_value = 0.8
	dur_slider.max_value = 5.0
	dur_slider.step = 0.1
	dur_slider.value = beam_duration
	dur_slider.value_changed.connect(func(v: float):
		beam_duration = v
		dur_lbl.text = "光束喷射时长 (Beam Duration): %.1fs" % v
		on_changed.call("beam_duration", v)
	)
	container.add_child(dur_slider)

	var rad_lbl := Label.new()
	rad_lbl.text = "星芒法阵半径 (Mandala Radius): %.1fm" % beam_radius
	rad_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(rad_lbl)

	var rad_slider := HSlider.new()
	rad_slider.min_value = 0.6
	rad_slider.max_value = 3.5
	rad_slider.step = 0.1
	rad_slider.value = beam_radius
	rad_slider.value_changed.connect(func(v: float):
		beam_radius = v
		rad_lbl.text = "星芒法阵半径 (Mandala Radius): %.1fm" % v
		on_changed.call("beam_radius", v)
	)
	container.add_child(rad_slider)

	var dist_lbl := Label.new()
	dist_lbl.text = "施法落点距离 (Cast Distance): %.1fm" % strike_distance
	dist_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(dist_lbl)

	var dist_slider := HSlider.new()
	dist_slider.min_value = 2.0
	dist_slider.max_value = 15.0
	dist_slider.step = 0.5
	dist_slider.value = strike_distance
	dist_slider.value_changed.connect(func(v: float):
		strike_distance = v
		dist_lbl.text = "施法落点距离 (Cast Distance): %.1fm" % v
		on_changed.call("strike_distance", v)
	)
	container.add_child(dist_slider)

	var dmg_lbl := Label.new()
	dmg_lbl.text = "连击单段伤害 (Damage/Hit): %d (总连击约 %d 段)" % [int(damage), int(beam_duration / HIT_INTERVAL)]
	dmg_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(dmg_lbl)

	var dmg_slider := HSlider.new()
	dmg_slider.min_value = 2.0
	dmg_slider.max_value = 100.0
	dmg_slider.step = 2.0
	dmg_slider.value = damage
	dmg_slider.value_changed.connect(func(v: float):
		damage = v
		dmg_lbl.text = "连击单段伤害 (Damage/Hit): %d (总连击约 %d 段)" % [int(v), int(beam_duration / HIT_INTERVAL)]
		on_changed.call("damage", v)
	)
	container.add_child(dmg_slider)

	var tip_panel := PanelContainer.new()
	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.03, 0.07, 0.12, 0.92)
	t_style.set_corner_radius_all(6)
	t_style.set_border_width_all(1)
	t_style.border_color = Color(0.35, 0.85, 1.25, 0.7)
	t_style.set_content_margin_all(8)
	tip_panel.add_theme_stylebox_override("panel", t_style)
	container.add_child(tip_panel)

	var tip_vbox := VBoxContainer.new()
	tip_vbox.add_theme_constant_override("separation", 4)
	tip_panel.add_child(tip_vbox)

	var tip1 := Label.new()
	tip1.text = "✨ 神圣星芒万华爆裂：地面冰晶法阵 + 核心星芒球 + 通天晶格光柱 + 放射状冰晶光刺 + 真实尘烟碎石"
	tip1.add_theme_font_size_override("font_size", 11)
	tip1.modulate = Color(0.75, 0.92, 1.0)
	tip_vbox.add_child(tip1)


# ============================================================
# 主执行流程
# ============================================================

func _execute_hammer_beam(caster: CharacterBody3D, target_pos: Vector3, parent: Node) -> Dictionary:
	_ensure_cached_resources()

	var raw_ch: Variant = caster.get("character")
	var has_anim: bool = raw_ch != null and is_instance_valid(raw_ch) and raw_ch.has_method("play")

	# 面向落点
	var to_t := target_pos - caster.global_position
	to_t.y = 0.0
	if to_t.length_squared() > 0.01:
		caster.rotation.y = atan2(to_t.x, to_t.z)

	var token := Time.get_ticks_msec()
	caster.set_meta("skill_frozen", true)
	caster.set_meta("hammer_beam_token", token)

	var root := Node3D.new()
	root.name = "HammerBeamVFX_%d" % token
	parent.add_child(root)
	root.global_position = target_pos

	if has_anim:
		raw_ch.call("play", "overhand_throw", 0.08)

	# 落点前摇聚能法阵
	_spawn_charge_disc(root, target_pos)

	var anim_player: AnimationPlayer = raw_ch.get("player") if has_anim else null
	var clip_len := _overhand_clip_length(raw_ch)
	var rest := maxf(clip_len - WINDUP_TIME, 0.15)
	var resume_t := WINDUP_TIME + beam_duration + 0.05

	# 0.6s 定格
	if anim_player != null and is_instance_valid(anim_player):
		var pose_tw := root.create_tween()
		pose_tw.tween_interval(WINDUP_TIME)
		pose_tw.tween_callback(func():
			if anim_player != null and is_instance_valid(anim_player):
				anim_player.set_meta("hammer_beam_old_speed", anim_player.speed_scale)
				anim_player.speed_scale = 0.0
		)

	# 0.6s 爆发
	var beam_tw := root.create_tween()
	beam_tw.tween_interval(WINDUP_TIME)
	beam_tw.tween_callback(func():
		if root != null and is_instance_valid(root):
			_spawn_beam(root, target_pos, caster)
	)

	# 恢复动画与解除静止逻辑挂在 caster 上
	if caster.is_inside_tree():
		var caster_tw := caster.create_tween()
		caster_tw.tween_interval(resume_t)
		caster_tw.tween_callback(func():
			_force_restore_anim(anim_player)
		)
		caster_tw.tween_interval(rest + 0.10)
		caster_tw.tween_callback(func():
			if caster != null and is_instance_valid(caster) and caster.get_meta("hammer_beam_token", 0) == token:
				caster.remove_meta("skill_frozen")
				caster.remove_meta("hammer_beam_token")
				_force_restore_anim(anim_player)
		)
		caster_tw.tween_interval(1.0)
		caster_tw.tween_callback(func():
			if caster != null and is_instance_valid(caster):
				if caster.get_meta("hammer_beam_token", 0) == token:
					caster.remove_meta("skill_frozen")
					caster.remove_meta("hammer_beam_token")
				_force_restore_anim(anim_player)
		)

	var clean_tw := root.create_tween()
	clean_tw.tween_interval(resume_t + rest + 1.5)
	clean_tw.tween_callback(func():
		if root != null and is_instance_valid(root):
			root.queue_free()
	)

	return {
		"target_pos": target_pos,
		"beam_duration": beam_duration
	}


static func _force_restore_anim(anim_player: AnimationPlayer) -> void:
	if anim_player == null or not is_instance_valid(anim_player):
		return
	if anim_player.has_meta("hammer_beam_old_speed"):
		anim_player.speed_scale = anim_player.get_meta("hammer_beam_old_speed")
		anim_player.remove_meta("hammer_beam_old_speed")
	elif anim_player.speed_scale == 0.0:
		anim_player.speed_scale = 1.0


func _calculate_target_position(caster: CharacterBody3D, intent_dir: Vector3) -> Vector3:
	var start_pos := caster.global_position if caster.is_inside_tree() else caster.position
	var fwd := intent_dir
	fwd.y = 0.0
	if fwd.length_squared() > 0.01:
		fwd = fwd.normalized()
	else:
		var basis_z := caster.global_transform.basis.z if caster.is_inside_tree() else caster.transform.basis.z
		basis_z.y = 0.0
		fwd = basis_z.normalized() if basis_z.length_squared() > 0.01 else Vector3.FORWARD

	var tree := caster.get_tree() if caster.is_inside_tree() else null
	if tree != null:
		var scene_root := tree.current_scene
		if scene_root != null:
			var closest_target: Node3D = null
			var closest_dist := 999.0
			var candidates: Array = []
			for ch in scene_root.find_children("*", "CharacterBody3D", true, false):
				candidates.append(ch)
			for ch in scene_root.find_children("*", "DummyTarget", true, false):
				candidates.append(ch)

			for b in candidates:
				if b == null or not is_instance_valid(b) or b == caster or b.name == "Ground":
					continue
				if not (b is Node3D):
					continue
				var n3d := b as Node3D
				var to_b := n3d.global_position - start_pos
				var dist := to_b.length()
				if dist <= strike_distance + 4.0:
					var dot := fwd.dot(to_b.normalized())
					if dot > 0.35 and dist < closest_dist:
						closest_dist = dist
						closest_target = n3d

			if closest_target != null:
				var tpos := closest_target.global_position
				tpos.y = start_pos.y
				return tpos

	return start_pos + fwd * strike_distance


func _overhand_clip_length(raw_ch: Variant) -> float:
	if raw_ch == null or not is_instance_valid(raw_ch):
		return 0.9
	var anim: AnimationPlayer = raw_ch.get("player")
	if anim == null or not is_instance_valid(anim):
		return 0.9
	var full: String = raw_ch.call("resolve", "overhand_throw")
	if full.is_empty() or not anim.has_animation(full):
		return 0.9
	return anim.get_animation(full).length


# ============================================================
# 特效构建 (还原参考图的高端冰晶圣辉万华爆裂)
# ============================================================

func _spawn_charge_disc(root: Node3D, pos: Vector3) -> void:
	var disc := MeshInstance3D.new()
	disc.mesh = _plane_mesh
	disc.scale = Vector3(beam_radius * 4.0, 1.0, beam_radius * 4.0)
	root.add_child(disc)
	disc.global_position = pos + Vector3(0.0, 0.04, 0.0)

	var mat := ShaderMaterial.new()
	mat.shader = HammerBeamGroundShader
	mat.set_shader_parameter("core_color", PALETTE["core"])
	mat.set_shader_parameter("beam_color", PALETTE["azure"])
	mat.set_shader_parameter("edge_color", PALETTE["deep"])
	mat.set_shader_parameter("intensity", 2.0)
	mat.set_shader_parameter("expansion", 0.1)
	mat.set_shader_parameter("fade", 0.0)
	disc.material_override = mat

	var tw := disc.create_tween()
	tw.tween_property(mat, "shader_parameter/fade", 1.0, 0.10)
	tw.parallel().tween_property(mat, "shader_parameter/expansion", 1.0, WINDUP_TIME - 0.05).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(mat, "shader_parameter/fade", 0.0, 0.12)
	tw.tween_callback(disc.queue_free)


func _spawn_beam(root: Node3D, pos: Vector3, caster: CharacterBody3D) -> void:
	var fade_mats: Array = []

	# 1. 地面巨型冰晶星芒法阵与裂痕网络
	fade_mats.append(_spawn_ground_mandala(root, pos))

	# 2. 核心万华镜星芒几何能量球
	fade_mats.append(_spawn_central_sphere(root, pos))

	# 3. 通天星芒晶格能量光柱 (三层嵌套)
	# 内层：纯白炽心激流
	fade_mats.append(_spawn_beam_column(root, pos, beam_radius * 0.45, PALETTE["core"], PALETTE["azure"], 12.0, 4.5, 0.0, 0.0, 3.5))
	# 中层：纵向排列流动的神圣星芒曼陀罗晶格光柱
	fade_mats.append(_spawn_beam_column(root, pos, beam_radius * 0.90, PALETTE["core"], PALETTE["azure"], 8.5, 1.8, 5.0, 0.85, 2.0))
	# 外层：冰蓝柔和气场
	fade_mats.append(_spawn_beam_column(root, pos, beam_radius * 1.35, PALETTE["azure"], PALETTE["deep"], 4.5, 0.8, 0.0, 0.0, 1.4))

	# 4. 环抱基部的多面冰晶石簇 (粗壮矮实 + 六棱多面反光 + 稳固扎根不抽动)
	_spawn_ground_crystal_clusters(root, pos, fade_mats)

	# 5. 地面真实爆裂尘烟与飞溅碎石破片
	_spawn_ground_dust_and_debris(root, pos, fade_mats)

	# 6. 超亮主副点光源
	_spawn_lighting(root, pos)

	# 7. 持续多段连击判定
	_start_continuous_combo(root, caster, pos)

	# 8. 整体淡出
	var fade_tw := root.create_tween()
	fade_tw.set_parallel(true)
	for m in fade_mats:
		if m != null:
			fade_tw.tween_property(m, "shader_parameter/fade", 0.0, 0.40).set_ease(Tween.EASE_IN).set_delay(beam_duration)


## 1. 地面星芒法阵与冰裂网络
func _spawn_ground_mandala(root: Node3D, pos: Vector3) -> ShaderMaterial:
	var disc := MeshInstance3D.new()
	disc.mesh = _plane_mesh
	var g_size := beam_radius * 8.5
	disc.scale = Vector3(g_size, 1.0, g_size)
	root.add_child(disc)
	disc.global_position = pos + Vector3(0.0, 0.05, 0.0)

	var mat := ShaderMaterial.new()
	mat.shader = HammerBeamGroundShader
	mat.set_shader_parameter("core_color", PALETTE["core"])
	mat.set_shader_parameter("beam_color", PALETTE["azure"])
	mat.set_shader_parameter("edge_color", PALETTE["deep"])
	mat.set_shader_parameter("intensity", 4.0)
	mat.set_shader_parameter("expansion", 0.05)
	mat.set_shader_parameter("fade", 1.0)
	disc.material_override = mat

	# 瞬间向外炸开扩散
	var tw := disc.create_tween()
	tw.tween_property(mat, "shader_parameter/expansion", 1.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return mat


## 2. 核心万华镜星芒能量球
func _spawn_central_sphere(root: Node3D, pos: Vector3) -> ShaderMaterial:
	var sphere := MeshInstance3D.new()
	sphere.mesh = _sphere_mesh
	var sphere_r := beam_radius * 1.5
	sphere.scale = Vector3(0.2, 0.2, 0.2)
	root.add_child(sphere)
	sphere.global_position = pos + Vector3(0.0, sphere_r * 0.85, 0.0)

	var mat := ShaderMaterial.new()
	mat.shader = HammerBeamSphereShader
	mat.set_shader_parameter("core_color", PALETTE["core"])
	mat.set_shader_parameter("beam_color", PALETTE["azure"])
	mat.set_shader_parameter("edge_color", PALETTE["deep"])
	mat.set_shader_parameter("emission_energy", 10.0)
	mat.set_shader_parameter("mandala_density", 3.0)
	mat.set_shader_parameter("rotation_speed", 0.4)
	mat.set_shader_parameter("depth_fade_distance", 0.8)
	mat.set_shader_parameter("fade", 1.0)
	sphere.material_override = mat

	# 核心球猛烈膨胀并定型
	var tw := sphere.create_tween()
	tw.tween_property(sphere, "scale", Vector3(sphere_r, sphere_r, sphere_r), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return mat


## 3. 光束柱生成
func _spawn_beam_column(root: Node3D, pos: Vector3, radius: float, core_c: Color, beam_c: Color, emission: float, scroll: float, mandala_rep: float, mandala_mix: float, fresnel_p: float) -> ShaderMaterial:
	var col := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = BEAM_HEIGHT
	cyl.radial_segments = 36
	cyl.rings = 6
	col.mesh = cyl
	root.add_child(col)
	col.global_position = pos + Vector3(0.0, BEAM_HEIGHT * 0.5, 0.0)

	var mat := ShaderMaterial.new()
	mat.shader = HammerBeamColumnShader
	mat.set_shader_parameter("core_color", core_c)
	mat.set_shader_parameter("beam_color", beam_c)
	mat.set_shader_parameter("edge_color", PALETTE["deep"])
	mat.set_shader_parameter("emission_energy", emission)
	mat.set_shader_parameter("scroll_speed", scroll)
	mat.set_shader_parameter("mandala_repeat_y", mandala_rep)
	mat.set_shader_parameter("mandala_mix", mandala_mix)
	mat.set_shader_parameter("is_needle_ray", 0.0)
	mat.set_shader_parameter("fresnel_power", fresnel_p)
	mat.set_shader_parameter("vertical_fade", 0.12)
	mat.set_shader_parameter("depth_fade_distance", 1.0)
	mat.set_shader_parameter("fade", 1.0)
	col.material_override = mat

	col.scale = Vector3(1.0, 0.02, 1.0)
	var tw := col.create_tween()
	tw.tween_property(col, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return mat


## 4. 环抱基部的多面冰晶石簇 (粗壮矮实 + 六棱多面反光 + 稳固扎根不抽动)
func _spawn_ground_crystal_clusters(root: Node3D, pos: Vector3, fade_mats: Array) -> void:
	var crystal_mat := ShaderMaterial.new()
	crystal_mat.shader = HammerBeamCrystalShader
	crystal_mat.set_shader_parameter("crystal_color", PALETTE["azure"])
	crystal_mat.set_shader_parameter("core_color", PALETTE["core"])
	crystal_mat.set_shader_parameter("facet_color", PALETTE["frost"])
	crystal_mat.set_shader_parameter("emission_energy", 7.0)
	crystal_mat.set_shader_parameter("facet_sharpness", 10.0)
	crystal_mat.set_shader_parameter("internal_glow", 0.85)
	crystal_mat.set_shader_parameter("depth_fade_distance", 0.4)
	crystal_mat.set_shader_parameter("fade", 1.0)
	fade_mats.append(crystal_mat)

	# 内环核心晶柱 (8根粗壮六棱柱环绕球体基部) + 外环裂纹晶石 (14根斜刺石簇)
	var total_crystals := 22
	for i in range(total_crystals):
		var is_inner := (i < 8)
		var c_mesh := CylinderMesh.new()
		c_mesh.radial_segments = 6 # 经典六棱晶体
		c_mesh.rings = 1
		
		# 粗壮矮实尺寸：高 2.0~4.5m，底粗 0.4~0.8m，顶尖细 0.05m
		var c_height := randf_range(3.2, 5.2) if is_inner else randf_range(1.8, 3.4)
		var c_radius := randf_range(0.45, 0.85) if is_inner else randf_range(0.30, 0.55)
		c_mesh.top_radius = 0.04
		c_mesh.bottom_radius = c_radius
		c_mesh.height = c_height

		var dist := (beam_radius * randf_range(0.9, 1.4)) if is_inner else (beam_radius * randf_range(1.6, 2.8))
		var azimuth := float(i) * TAU / float(total_crystals) + randf_range(-0.12, 0.12)
		var tilt_outward := randf_range(0.18, 0.38) if is_inner else randf_range(0.40, 0.72) # 斜向外刺出的角度

		var pivot := Node3D.new()
		root.add_child(pivot)
		pivot.global_position = pos + Vector3(cos(azimuth) * dist, 0.02, sin(azimuth) * dist)
		pivot.rotation.y = azimuth
		pivot.rotation.x = -tilt_outward
		pivot.rotation.z = randf_range(-0.15, 0.15)

		var crystal := MeshInstance3D.new()
		crystal.mesh = c_mesh
		crystal.material_override = crystal_mat
		pivot.add_child(crystal)
		crystal.position = Vector3(0.0, c_height * 0.5, 0.0)

		# 破土暴刺破土生长：迅速长出后定格扎根，不抽动，晶体棱角反射光芒
		crystal.scale = Vector3(1.0, 0.01, 1.0)
		var tw := crystal.create_tween()
		tw.tween_property(crystal, "scale", Vector3.ONE, randf_range(0.10, 0.16)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 5. 庞大翻滚地面尘烟云与连续喷涌 (Massive Dynamic Billowing Dust & Debris)
func _spawn_ground_dust_and_debris(root: Node3D, pos: Vector3, fade_mats: Array) -> void:
	var smoke_mat := ShaderMaterial.new()
	smoke_mat.shader = HammerBeamSmokeShader
	smoke_mat.set_shader_parameter("smoke_color", PALETTE["smoke"])
	smoke_mat.set_shader_parameter("rim_color", PALETTE["azure"])
	smoke_mat.set_shader_parameter("churn_speed", 1.8)
	smoke_mat.set_shader_parameter("depth_fade_distance", 0.8)
	smoke_mat.set_shader_parameter("fade", 1.0)
	fade_mats.append(smoke_mat)

	# 1. 爆发初始：超巨型浓烟环 (16团大烟云向外狂涌)
	for k in range(16):
		_spawn_smoke_cloud(root, pos, smoke_mat, randf_range(4.5, 8.5) * beam_radius, randf_range(4.5, 8.5) * beam_radius, randf_range(0.8, 1.4))

	# 2. 持续喷涌对流：光束喷发期间每 0.16s 持续向外翻滚涌出新烟团 (动起来！)
	var smoke_waves := int(beam_duration / 0.16)
	var wave_tw := root.create_tween()
	for w in range(smoke_waves):
		wave_tw.tween_callback(func():
			if root == null or not is_instance_valid(root):
				return
			for n in range(2):
				_spawn_smoke_cloud(root, pos, smoke_mat, randf_range(3.5, 6.5) * beam_radius, randf_range(3.5, 7.5) * beam_radius, randf_range(0.7, 1.2))
		)
		wave_tw.tween_interval(0.16)

	# 3. 飞溅碎石破片 (24块高速向外抛射并翻转的暗色碎石)
	for d in range(24):
		var rock := MeshInstance3D.new()
		rock.mesh = _box_mesh
		var r_size := randf_range(0.12, 0.35) * beam_radius
		rock.scale = Vector3(r_size, r_size * randf_range(0.8, 1.8), r_size)
		root.add_child(rock)

		var r_ang := randf_range(0.0, TAU)
		rock.global_position = pos + Vector3(cos(r_ang) * 0.4, randf_range(0.1, 0.6), sin(r_ang) * 0.4)

		var rock_mat := StandardMaterial3D.new()
		rock_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		rock_mat.albedo_color = Color(0.14, 0.18, 0.24)
		rock.material_override = rock_mat

		var target_rock := rock.global_position + Vector3(cos(r_ang) * randf_range(4.0, 9.5), randf_range(2.0, 5.5), sin(r_ang) * randf_range(4.0, 9.5))
		var r_life := randf_range(0.5, 0.9)

		var r_tw := rock.create_tween()
		r_tw.set_parallel(true)
		r_tw.tween_property(rock, "global_position", target_rock, r_life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		r_tw.tween_property(rock, "rotation", Vector3(randf_range(-10, 10), randf_range(-10, 10), randf_range(-10, 10)), r_life)
		r_tw.tween_property(rock, "scale", Vector3.ZERO, r_life * 0.4).set_delay(r_life * 0.6)
		r_tw.chain().tween_callback(rock.queue_free)


## 单团翻滚烟雾实例生成
func _spawn_smoke_cloud(root: Node3D, pos: Vector3, smoke_mat: ShaderMaterial, initial_size: float, target_spread: float, life: float) -> void:
	var puff := MeshInstance3D.new()
	puff.mesh = _sphere_mesh
	puff.scale = Vector3(0.2, 0.2, 0.2)
	root.add_child(puff)

	var ang := randf_range(0.0, TAU)
	var start_dist := randf_range(0.3, 1.2) * beam_radius
	puff.global_position = pos + Vector3(cos(ang) * start_dist, randf_range(0.1, 0.6), sin(ang) * start_dist)
	puff.material_override = smoke_mat

	var target_pos := puff.global_position + Vector3(cos(ang) * target_spread, randf_range(0.6, 2.2), sin(ang) * target_spread)

	var tw := puff.create_tween()
	tw.set_parallel(true)
	# 位置外涌
	tw.tween_property(puff, "global_position", target_pos, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 自身体积迅速膨胀
	tw.tween_property(puff, "scale", Vector3(initial_size, initial_size * 0.65, initial_size), life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 自身旋转翻滚 (动起来)
	tw.tween_property(puff, "rotation:y", randf_range(-2.5, 2.5), life)
	tw.tween_property(puff, "rotation:x", randf_range(-1.2, 1.2), life)
	tw.chain().tween_callback(puff.queue_free)


## 6. 超亮主副点光源
func _spawn_lighting(root: Node3D, pos: Vector3) -> void:
	var light := OmniLight3D.new()
	light.light_color = PALETTE["light"]
	light.light_energy = 9.0
	light.omni_range = 24.0
	root.add_child(light)
	light.global_position = pos + Vector3(0.0, 2.5, 0.0)

	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 7.0, 0.1)
	tw.tween_property(light, "light_energy", 0.0, 0.4).set_delay(beam_duration)


## 7. 持续多段连击判定
func _start_continuous_combo(root: Node3D, caster: CharacterBody3D, pos: Vector3) -> void:
	var tick_count := maxi(1, int(floor(beam_duration / HIT_INTERVAL)))
	var hit_tw := root.create_tween()
	for i in range(tick_count):
		hit_tw.tween_callback(func():
			if root != null and is_instance_valid(root) and caster != null and is_instance_valid(caster):
				_resolve_beam_damage_tick(caster, pos, i == 0, i == tick_count - 1, i)
		)
		hit_tw.tween_interval(HIT_INTERVAL)


func _resolve_beam_damage_tick(caster: CharacterBody3D, hit_pos: Vector3, _is_first: bool, is_last: bool, _tick_idx: int) -> void:
	var tree := caster.get_tree() if (caster != null and is_instance_valid(caster) and caster.is_inside_tree()) else null
	if tree == null:
		return
	var scene_root := tree.current_scene
	if scene_root == null:
		return

	var aoe_r := beam_radius * 3.2
	var tick_dmg := damage * (1.8 if is_last else 1.0)

	var candidates: Array = []
	for ch in scene_root.find_children("*", "CharacterBody3D", true, false):
		candidates.append(ch)
	for ch in scene_root.find_children("*", "DummyTarget", true, false):
		candidates.append(ch)

	for b in candidates:
		if b == null or not is_instance_valid(b) or b == caster or b.name == "Ground":
			continue
		if not (b is Node3D):
			continue
		var n3d := b as Node3D
		var to_b := n3d.global_position - hit_pos
		to_b.y = 0.0
		if to_b.length() > aoe_r:
			continue

		var b_pos := n3d.global_position
		var contact_pos := Vector3(b_pos.x, hit_pos.y + 0.9 + randf_range(-0.2, 0.2), b_pos.z)
		var swing_dir := (b_pos - hit_pos).normalized()
		if swing_dir.length_squared() < 0.01:
			swing_dir = Vector3.UP

		if b.has_method("take_hit"):
			b.call("take_hit", contact_pos, tick_dmg, swing_dir)

		if b.has_method("apply_hit_reaction"):
			b.call("apply_hit_reaction", "hit_chest", 0.20)
		elif b is CharacterBody3D:
			var raw_ch: Variant = b.get("character")
			if raw_ch != null and is_instance_valid(raw_ch) and raw_ch.has_method("play"):
				raw_ch.call("play", "hit_knockback" if is_last else "hit_reaction", 0.05)

		_spawn_hit_spark(scene_root, contact_pos)


func _spawn_hit_spark(parent: Node, pos: Vector3) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var spark := MeshInstance3D.new()
	spark.mesh = _quad_mesh
	var s_size := randf_range(0.8, 1.4)
	spark.scale = Vector3(s_size, s_size, s_size)
	spark.rotation.y = randf_range(0.0, TAU)
	parent.add_child(spark)
	spark.global_position = pos + Vector3(randf_range(-0.15, 0.15), randf_range(-0.15, 0.15), randf_range(-0.15, 0.15))

	var mat := ShaderMaterial.new()
	mat.shader = HammerBeamColumnShader
	mat.set_shader_parameter("core_color", PALETTE["core"])
	mat.set_shader_parameter("beam_color", PALETTE["azure"])
	mat.set_shader_parameter("edge_color", PALETTE["deep"])
	mat.set_shader_parameter("emission_energy", 8.0)
	mat.set_shader_parameter("is_needle_ray", 1.0)
	mat.set_shader_parameter("fade", 1.0)
	spark.material_override = mat

	var tw := spark.create_tween()
	tw.set_parallel(true)
	tw.tween_property(spark, "scale", Vector3.ZERO, 0.20).set_ease(Tween.EASE_IN)
	tw.tween_property(mat, "shader_parameter/fade", 0.0, 0.20).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(spark.queue_free)


static func _ensure_cached_resources() -> void:
	if _quad_mesh == null:
		_quad_mesh = QuadMesh.new()
		_quad_mesh.size = Vector2(1.0, 1.0)

	if _plane_mesh == null:
		_plane_mesh = PlaneMesh.new()
		_plane_mesh.size = Vector2(1.0, 1.0)

	if _sphere_mesh == null:
		_sphere_mesh = SphereMesh.new()
		_sphere_mesh.radial_segments = 32
		_sphere_mesh.rings = 16

	if _box_mesh == null:
		_box_mesh = BoxMesh.new()
		_box_mesh.size = Vector3(1.0, 1.0, 1.0)

	if _warmup_mats.is_empty():
		var m_col := ShaderMaterial.new()
		m_col.shader = HammerBeamColumnShader
		_warmup_mats.append(m_col)

		var m_gnd := ShaderMaterial.new()
		m_gnd.shader = HammerBeamGroundShader
		_warmup_mats.append(m_gnd)

		var m_sph := ShaderMaterial.new()
		m_sph.shader = HammerBeamSphereShader
		_warmup_mats.append(m_sph)

		var m_smk := ShaderMaterial.new()
		m_smk.shader = HammerBeamSmokeShader
		_warmup_mats.append(m_smk)

		var m_crys := ShaderMaterial.new()
		m_crys.shader = HammerBeamCrystalShader
		_warmup_mats.append(m_crys)
