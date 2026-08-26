extends "res://scripts/skills/skill_base.gd"
## Skill 18: Glass Shatter / 流璃碎穹 (镜界凝结·千刹飞刃).
## 施法流程：
## 1. 玩家前方空气凝结出一面流光溢彩的巨型琉璃水晶镜
## 2. 镜面瞬间布满沃罗诺伊冰晶裂纹并爆碎为数十枚大小各异的精美多面钻石玻璃碎片
## 3. 碎片沿优美弧线回旋疾飞至玩家后方，悬浮列阵形成高能飞刃羽翼
## 4. 随后如暴雨般向初始瞄准目标点超音速齐射，贯穿刺伤沿途所有实体。

const GlassMirrorShader = preload("res://shaders/glass_mirror.gdshader")
const GlassShardShader = preload("res://shaders/glass_shard.gdshader")

## 纯净冰晶琉璃配色
const PALETTE := {
	"core": Color(2.6, 2.9, 3.4, 1.0),      # 炽白钻石反光
	"azure": Color(0.35, 0.88, 1.35, 1.0),   # 冰晶青蓝
	"deep": Color(0.08, 0.45, 0.95, 0.85),   # 冰川深蓝
	"frost": Color(0.85, 0.96, 1.0, 0.85),   # 琉璃透白
	"rainbow": Color(0.70, 0.90, 1.20, 1.0), # 色散彩光
}

var shard_count: int = 56
var damage_per_shard: float = 16.0
var strike_distance: float = 16.0
var cast_range: float = 25.0
var mirror_distance: float = 2.8
var mirror_width: float = 3.6
var mirror_height: float = 2.4

## 静态几何网格缓存
static var _quad_mesh: QuadMesh = null
static var _plane_mesh: PlaneMesh = null
static var _sphere_mesh: SphereMesh = null
static var _shard_meshes: Array[ArrayMesh] = []
static var _warmup_mats: Array = []


func get_id() -> String:
	return "glass_shatter"


func get_name() -> String:
	return "💎 流璃碎穹 (镜界凝结·千刹飞刃)"


func get_title() -> String:
	return "💎 流璃碎穹配置 (GLASS SHATTER)"


func get_params() -> Dictionary:
	return {
		"shard_count": shard_count,
		"damage_per_shard": damage_per_shard,
		"strike_distance": strike_distance,
		"mirror_distance": mirror_distance
	}


func set_param(key: String, value: Variant) -> void:
	match key:
		"shard_count": shard_count = clampi(int(value), 20, 100)
		"damage_per_shard": damage_per_shard = clampf(float(value), 2.0, 50.0)
		"strike_distance": strike_distance = clampf(float(value), 5.0, 30.0)
		"mirror_distance": mirror_distance = clampf(float(value), 1.5, 6.0)


func cast(caster: CharacterBody3D, intent_dir: Vector3, vfx_parent: Node, _is_spectator: bool = false) -> Dictionary:
	if caster == null or not is_instance_valid(caster):
		return {}
	var target_pos := _calculate_target_position(caster, intent_dir)
	return _execute_glass_shatter(caster, target_pos, vfx_parent)


func cast_at(caster: CharacterBody3D, target_pos: Vector3, vfx_parent: Node, _is_spectator: bool = false) -> Dictionary:
	if caster == null or not is_instance_valid(caster):
		return {}
	return _execute_glass_shatter(caster, target_pos, vfx_parent)


func replay(caster: CharacterBody3D, record: Dictionary, vfx_parent: Node) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	var target_pos: Vector3 = record.get("target_pos", caster.global_position + (caster.global_transform.basis.z if caster.is_inside_tree() else Vector3.FORWARD) * strike_distance)
	_execute_glass_shatter(caster, target_pos, vfx_parent)


func get_replay_hold_time(_record: Dictionary) -> float:
	return 4.5


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
	var count_lbl := Label.new()
	count_lbl.text = "琉璃碎片数量 (Shard Count): %d 片" % shard_count
	count_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(count_lbl)

	var count_slider := HSlider.new()
	count_slider.min_value = 20
	count_slider.max_value = 100
	count_slider.step = 2
	count_slider.value = shard_count
	count_slider.value_changed.connect(func(v: float):
		shard_count = int(v)
		count_lbl.text = "琉璃碎片数量 (Shard Count): %d 片" % int(v)
		on_changed.call("shard_count", int(v))
	)
	container.add_child(count_slider)

	var dmg_lbl := Label.new()
	dmg_lbl.text = "单枚碎片贯穿伤害 (Damage/Shard): %d (全中总伤害 %d)" % [int(damage_per_shard), int(damage_per_shard * shard_count)]
	dmg_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(dmg_lbl)

	var dmg_slider := HSlider.new()
	dmg_slider.min_value = 2.0
	dmg_slider.max_value = 50.0
	dmg_slider.step = 1.0
	dmg_slider.value = damage_per_shard
	dmg_slider.value_changed.connect(func(v: float):
		damage_per_shard = v
		dmg_lbl.text = "单枚碎片贯穿伤害 (Damage/Shard): %d (全中总伤害 %d)" % [int(v), int(v * shard_count)]
		on_changed.call("damage_per_shard", v)
	)
	container.add_child(dmg_slider)

	var dist_lbl := Label.new()
	dist_lbl.text = "目标齐射射程 (Strike Distance): %.1fm" % strike_distance
	dist_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(dist_lbl)

	var dist_slider := HSlider.new()
	dist_slider.min_value = 5.0
	dist_slider.max_value = 30.0
	dist_slider.step = 1.0
	dist_slider.value = strike_distance
	dist_slider.value_changed.connect(func(v: float):
		strike_distance = v
		dist_lbl.text = "目标齐射射程 (Strike Distance): %.1fm" % v
		on_changed.call("strike_distance", v)
	)
	container.add_child(dist_slider)

	var tip_panel := PanelContainer.new()
	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.04, 0.08, 0.14, 0.92)
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
	tip1.text = "💎 视觉四阶段：前方凝结琉璃大镜 ➔ 沃罗诺伊爆碎 ➔ 碎片弧线绕背列阵 ➔ 超音速贯穿齐射"
	tip1.add_theme_font_size_override("font_size", 11)
	tip1.modulate = Color(0.75, 0.92, 1.0)
	tip_vbox.add_child(tip1)


# ============================================================
# 主执行流程
# ============================================================

func _execute_glass_shatter(caster: CharacterBody3D, target_pos: Vector3, parent: Node) -> Dictionary:
	_ensure_cached_resources()

	var caster_pos := caster.global_position if caster.is_inside_tree() else caster.position
	var fwd := target_pos - caster_pos
	fwd.y = 0.0
	if fwd.length_squared() > 0.01:
		fwd = fwd.normalized()
		caster.rotation.y = atan2(fwd.x, fwd.z)
	else:
		fwd = caster.global_transform.basis.z.normalized() if caster.is_inside_tree() else Vector3.FORWARD

	var raw_ch: Variant = caster.get("character")
	var has_anim: bool = raw_ch != null and is_instance_valid(raw_ch) and raw_ch.has_method("play")
	if has_anim:
		raw_ch.call("play", "sword_regular_a", 0.08)

	var token := Time.get_ticks_msec()
	var root := Node3D.new()
	root.name = "GlassShatterVFX_%d" % token
	parent.add_child(root)

	# 1. 镜面生成位置（玩家前方）
	var mirror_pos := caster_pos + fwd * mirror_distance + Vector3.UP * 1.35
	var mirror_rot_y := atan2(fwd.x, fwd.z)

	# 阶段 1: 凝结大玻璃镜面
	_spawn_condensing_mirror(root, mirror_pos, mirror_rot_y, caster, target_pos)

	# 清理保护 (预留 7.5s 确保慢速碎片完整发射并命中爆裂)
	var clean_tw := root.create_tween()
	clean_tw.tween_interval(7.5)
	clean_tw.tween_callback(func():
		if root != null and is_instance_valid(root):
			root.queue_free()
	)

	return {
		"target_pos": target_pos,
		"shard_count": shard_count
	}


## 阶段 1 & 2: 凝结玻璃镜面并在 0.45s 碎裂
func _spawn_condensing_mirror(root: Node3D, mirror_pos: Vector3, rot_y: float, caster: CharacterBody3D, target_pos: Vector3) -> void:
	var mirror := MeshInstance3D.new()
	mirror.mesh = _quad_mesh
	mirror.scale = Vector3(0.1, 0.1, 0.1)
	root.add_child(mirror)
	mirror.global_position = mirror_pos
	mirror.rotation.y = rot_y

	var mat := ShaderMaterial.new()
	mat.shader = GlassMirrorShader
	mat.set_shader_parameter("glass_tint", PALETTE["frost"])
	mat.set_shader_parameter("rim_color", PALETTE["azure"])
	mat.set_shader_parameter("crack_color", PALETTE["core"])
	mat.set_shader_parameter("refraction_strength", 0.04)
	mat.set_shader_parameter("dispersion", 0.02)
	mat.set_shader_parameter("crack_progress", 0.0)
	mat.set_shader_parameter("fade", 0.0)
	mirror.material_override = mat

	# 伴生凝结光晕
	var light := OmniLight3D.new()
	light.light_color = PALETTE["azure"]
	light.light_energy = 5.0
	light.omni_range = 8.0
	mirror.add_child(light)

	# 1. 瞬间凝聚展开
	var tw := mirror.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mirror, "scale", Vector3(mirror_width, mirror_height, 1.0), 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "shader_parameter/fade", 1.0, 0.20)

	# 2. 0.35s ~ 0.45s: 沃罗诺伊裂纹疾速蔓延
	tw.chain().tween_property(mat, "shader_parameter/crack_progress", 1.0, 0.14).set_ease(Tween.EASE_IN)

	# 3. 0.48s: 镜面爆碎！生成碎片群
	tw.chain().tween_callback(func():
		if root == null or not is_instance_valid(root):
			return
		_shatter_into_flying_shards(root, mirror_pos, rot_y, caster, target_pos)
		mirror.queue_free()
	)


## 阶段 3 & 4: 玻璃碎片飞向玩家后方列阵，随后向目标点超音速贯穿齐射
func _shatter_into_flying_shards(root: Node3D, shatter_pos: Vector3, rot_y: float, caster: CharacterBody3D, target_pos: Vector3) -> void:
	# 爆碎瞬间的闪光与冲击波
	_spawn_shatter_burst_flash(root, shatter_pos)

	var caster_pos := caster.global_position if (caster != null and is_instance_valid(caster) and caster.is_inside_tree()) else (shatter_pos - Vector3(sin(rot_y), 0, cos(rot_y)) * mirror_distance)
	var fwd := (target_pos - caster_pos).normalized()
	var right := fwd.cross(Vector3.UP).normalized()

	var shard_mat := ShaderMaterial.new()
	shard_mat.shader = GlassShardShader
	shard_mat.set_shader_parameter("shard_tint", PALETTE["frost"])
	shard_mat.set_shader_parameter("rim_color", PALETTE["azure"])
	shard_mat.set_shader_parameter("gleam_color", PALETTE["core"])
	shard_mat.set_shader_parameter("emission_energy", 10.0)
	shard_mat.set_shader_parameter("facet_sharpness", 16.0)
	shard_mat.set_shader_parameter("chromatic_offset", 0.45)
	shard_mat.set_shader_parameter("fade", 1.0)

	var shards: Array[MeshInstance3D] = []
	var rear_positions: Array[Vector3] = []
	var rear_rotations: Array[Vector3] = []

	# 为每一枚碎片分配唯一的初始爆散位置、后方列阵位置与 3D 多面网格
	for i in range(shard_count):
		var shard := MeshInstance3D.new()
		# 随机选择一种精美多面 3D 晶片模型
		var mesh_idx := i % _shard_meshes.size() if not _shard_meshes.is_empty() else 0
		shard.mesh = _shard_meshes[mesh_idx]
		shard.material_override = shard_mat

		# 晶莹醒目的真实大块琉璃碎片尺寸 (0.24~0.48m 宽度, 0.40~0.90m 长度, 0.022~0.045m 刻面厚度)
		var s_w := randf_range(0.24, 0.48)
		var s_h := randf_range(0.40, 0.90)
		var s_d := randf_range(0.022, 0.045)
		shard.scale = Vector3(s_w, s_h, s_d)

		root.add_child(shard)

		# 初始爆散位置 (镜面上随机自然散布)
		var cols := 8
		var u_offset := (float(i % cols) / float(cols - 1) - 0.5) * mirror_width * 0.90 + randf_range(-0.15, 0.15)
		var v_offset := (float(i / cols) / float(maxi(1, shard_count / cols)) - 0.5) * mirror_height * 0.85 + randf_range(-0.15, 0.15)
		var start_p := shatter_pos + right * u_offset + Vector3.UP * v_offset
		shard.global_position = start_p
		shard.rotation = Vector3(randf_range(-PI, PI), rot_y + randf_range(-0.5, 0.5), randf_range(-PI, PI))
		shards.append(shard)

		# 玩家后方列阵位置 (悬浮在玩家后背呈弧形飞翼环形排列)
		var angle: float = (float(i) / float(shard_count) - 0.5) * 2.2 # -1.1 到 1.1 弧度展开
		var rear_dist: float = randf_range(1.6, 2.4)
		var rear_h: float = 1.2 + cos(angle) * 1.0 + randf_range(-0.2, 0.2)
		var rear_p: Vector3 = caster_pos - fwd * (rear_dist + abs(sin(angle)) * 0.6) + right * (sin(angle) * 2.2) + Vector3.UP * rear_h
		rear_positions.append(rear_p)

		# 朝向目标点的初始瞄准朝向
		var aim_dir: Vector3 = (target_pos - rear_p).normalized()
		var aim_rot_y: float = atan2(aim_dir.x, aim_dir.z)
		var aim_rot_x: float = -asin(aim_dir.y)
		rear_rotations.append(Vector3(aim_rot_x, aim_rot_y, randf_range(-0.3, 0.3)))

	# --- 阶段 3: 碎片弧线绕飞至玩家后方列阵 (0.55s) ---
	for i in range(shard_count):
		var shard := shards[i]
		var start_p := shard.global_position
		var end_p := rear_positions[i]
		var end_rot := rear_rotations[i]

		# 弯曲弧线控制点（沿玩家外侧绕飞）
		var side_dir := 1.0 if (i % 2 == 0) else -1.0
		var mid_p := (start_p + end_p) * 0.5 + right * side_dir * randf_range(2.0, 3.5) + Vector3.UP * randf_range(0.5, 1.5)

		var fly_tw := shard.create_tween()
		var dur := randf_range(0.48, 0.65)
		
		# 二阶贝塞尔曲线飞跃
		fly_tw.tween_method(func(t: float):
			if shard == null or not is_instance_valid(shard):
				return
			var p := (1.0 - t) * (1.0 - t) * start_p + 2.0 * (1.0 - t) * t * mid_p + t * t * end_p
			shard.global_position = p
		, 0.0, 1.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

		fly_tw.parallel().tween_property(shard, "rotation", end_rot, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# --- 阶段 4: 悬停能量蓄积 ➔ 连环超音速齐射 (0.65s 后开始) ---
	var volley_tw := root.create_tween()
	volley_tw.tween_interval(0.65) # 等待碎片全部就位

	# 齐射启动：等间隔平稳发射所有碎片，确保 100% 全部发射 (发射速度再减半)
	for i in range(shards.size()):
		var target_shard := shards[i]
		volley_tw.tween_callback(func():
			if target_shard != null and is_instance_valid(target_shard):
				_fire_single_shard(root, target_shard, target_pos, caster)
		)
		volley_tw.tween_interval(0.040)


## 单枚碎片真实弹道与沿途贯穿判定 (去除多余彩虹光束，保留纯粹晶莹飞刃)
func _fire_single_shard(root: Node3D, shard: MeshInstance3D, target_pos: Vector3, caster: CharacterBody3D) -> void:
	var start_pos := shard.global_position
	# 目标点加入适量散布与纵向穿透延伸
	var spread := Vector3(randf_range(-0.6, 0.6), randf_range(-0.3, 0.5), randf_range(-0.6, 0.6))
	var aim_target := target_pos + spread
	var to_target := aim_target - start_pos
	var dist := to_target.length()
	var dir := to_target.normalized()

	# 贯穿射线延伸到目标点后方 3m
	var end_pos := start_pos + dir * (dist + 3.0)
	var flight_time := maxf(0.48, dist / 10.5) # ~10.5m/s 飞刃（速度再减半，清晰可见）

	# 弹道飞行与沿途伤害贯穿
	var hit_entities := {}
	var shoot_tw := shard.create_tween()
	shoot_tw.tween_method(func(t: float):
		if shard == null or not is_instance_valid(shard):
			return
		var cur_p := start_pos.lerp(end_pos, t)
		shard.global_position = cur_p
		# 沿途贯穿判定
		_check_shard_pierce_at(cur_p, caster, hit_entities)
	, 0.0, 1.0, flight_time).set_trans(Tween.TRANS_LINEAR)

	# 命中终点：爆出碎晶火花并消亡
	shoot_tw.chain().tween_callback(func():
		if shard != null and is_instance_valid(shard):
			_spawn_hit_shatter_sparks(root, end_pos)
			shard.queue_free()
	)


## 碎片飞行沿途贯穿碰撞判定
func _check_shard_pierce_at(cur_pos: Vector3, caster: CharacterBody3D, hit_entities: Dictionary) -> void:
	var tree := caster.get_tree() if (caster != null and is_instance_valid(caster) and caster.is_inside_tree()) else null
	if tree == null:
		return
	var scene_root := tree.current_scene
	if scene_root == null:
		return

	var pierce_r := 1.1

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
		var instance_id := n3d.get_instance_id()
		if hit_entities.has(instance_id):
			continue # 每枚碎片对同一目标仅贯穿击中一次

		var b_pos := n3d.global_position
		var to_b := n3d.global_position - cur_pos
		to_b.y = 0.0
		if to_b.length() <= pierce_r:
			hit_entities[instance_id] = true
			var contact_pos := Vector3(b_pos.x, cur_pos.y, b_pos.z)
			var push_dir := (b_pos - cur_pos).normalized()
			if push_dir.length_squared() < 0.01:
				push_dir = Vector3.UP

			if b.has_method("take_hit"):
				b.call("take_hit", contact_pos, damage_per_shard, push_dir)

			if b.has_method("apply_hit_reaction"):
				b.call("apply_hit_reaction", "hit_chest", 0.15)
			elif b is CharacterBody3D:
				var raw_ch: Variant = b.get("character")
				if raw_ch != null and is_instance_valid(raw_ch) and raw_ch.has_method("play"):
					raw_ch.call("play", "hit_reaction", 0.05)

			_spawn_hit_shatter_sparks(scene_root, contact_pos)


## 镜面碎裂瞬间的爆裂闪光
func _spawn_shatter_burst_flash(root: Node3D, pos: Vector3) -> void:
	var flash := MeshInstance3D.new()
	flash.mesh = _sphere_mesh
	flash.scale = Vector3(0.5, 0.5, 0.5)
	root.add_child(flash)
	flash.global_position = pos

	var mat := StandardMaterial3D.new()
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(2.5, 2.8, 3.2, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.material_override = mat

	var tw := flash.create_tween()
	tw.set_parallel(true)
	tw.tween_property(flash, "scale", Vector3(3.5, 3.5, 3.5), 0.18).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.18).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(flash.queue_free)


## 命中实体与目标点碎晶火花
func _spawn_hit_shatter_sparks(parent: Node, pos: Vector3) -> void:
	if parent == null or not is_instance_valid(parent):
		return

	for s in range(4):
		var spark := MeshInstance3D.new()
		spark.mesh = _quad_mesh
		var s_size := randf_range(0.25, 0.6)
		spark.scale = Vector3(s_size, s_size, s_size)
		spark.rotation = Vector3(randf_range(-PI, PI), randf_range(-PI, PI), randf_range(-PI, PI))
		parent.add_child(spark)
		spark.global_position = pos + Vector3(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2), randf_range(-0.2, 0.2))

		var mat := StandardMaterial3D.new()
		mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(2.0, 2.5, 3.0, 1.0)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		spark.material_override = mat

		var target_pos := spark.global_position + Vector3(randf_range(-1.5, 1.5), randf_range(-0.5, 1.5), randf_range(-1.5, 1.5))
		var tw := spark.create_tween()
		tw.set_parallel(true)
		tw.tween_property(spark, "global_position", target_pos, 0.22).set_ease(Tween.EASE_OUT)
		tw.tween_property(spark, "scale", Vector3.ZERO, 0.22).set_ease(Tween.EASE_IN)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.22).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(spark.queue_free)


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
				if dist <= strike_distance + 5.0:
					var dot := fwd.dot(to_b.normalized())
					if dot > 0.35 and dist < closest_dist:
						closest_dist = dist
						closest_target = n3d

			if closest_target != null:
				var tpos := closest_target.global_position
				tpos.y = start_pos.y + 0.9
				return tpos

	return start_pos + fwd * strike_distance + Vector3.UP * 0.9


# ============================================================
# 多面精美玻璃碎片 3D 网格生成器
# ============================================================

static func _ensure_cached_resources() -> void:
	if _quad_mesh == null:
		_quad_mesh = QuadMesh.new()
		_quad_mesh.size = Vector2(1.0, 1.0)

	if _plane_mesh == null:
		_plane_mesh = PlaneMesh.new()
		_plane_mesh.size = Vector2(1.0, 1.0)

	if _sphere_mesh == null:
		_sphere_mesh = SphereMesh.new()
		_sphere_mesh.radial_segments = 24
		_sphere_mesh.rings = 12

	if _shard_meshes.is_empty():
		_generate_faceted_shard_meshes()

	if _warmup_mats.is_empty():
		var m_mir := ShaderMaterial.new()
		m_mir.shader = GlassMirrorShader
		_warmup_mats.append(m_mir)

		var m_shd := ShaderMaterial.new()
		m_shd.shader = GlassShardShader
		_warmup_mats.append(m_shd)


## 程序化生成 8 种不同形状的不规则 3D 锐角玻璃晶片
static func _generate_faceted_shard_meshes() -> void:
	# 形状模板顶点 (X, Y 坐标：多面锐角三角、菱形、匕首针尖、斜边四边形)
	var shapes: Array = [
		# 1. 锐角尖矛片
		[Vector2(0.0, 1.2), Vector2(-0.25, -0.7), Vector2(0.3, -0.6)],
		# 2. 菱形钻石片
		[Vector2(0.0, 0.95), Vector2(-0.4, 0.05), Vector2(0.05, -0.9), Vector2(0.4, -0.05)],
		# 3. 锯齿匕首折角晶片
		[Vector2(0.05, 1.15), Vector2(-0.3, 0.35), Vector2(-0.2, -0.75), Vector2(0.3, -0.5)],
		# 4. 梯形斜切晶片
		[Vector2(-0.15, 0.85), Vector2(-0.45, -0.65), Vector2(0.4, -0.75), Vector2(0.3, 0.65)],
		# 5. 五边形晶片
		[Vector2(0.0, 0.95), Vector2(-0.45, 0.3), Vector2(-0.25, -0.7), Vector2(0.25, -0.7), Vector2(0.45, 0.3)],
		# 6. 细长飞刃刺
		[Vector2(0.0, 1.4), Vector2(-0.16, -0.9), Vector2(0.16, -0.9)],
		# 7. 三角斜刃片
		[Vector2(0.4, 0.9), Vector2(-0.35, 0.2), Vector2(-0.1, -0.85)],
		# 8. 倒钩碎角片
		[Vector2(-0.1, 1.1), Vector2(0.35, 0.4), Vector2(0.15, -0.8), Vector2(-0.3, -0.3)],
	]

	for poly_obj in shapes:
		var poly: Array = poly_obj as Array
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var thickness: float = 0.025

		var count: int = poly.size()
		var center := Vector2.ZERO
		for pt_obj in poly:
			var pt: Vector2 = pt_obj as Vector2
			center += pt
		center /= float(count)

		# 正面多边形三角化
		for i in range(count):
			var next_i: int = (i + 1) % count
			var p1: Vector2 = poly[i] as Vector2
			var p2: Vector2 = poly[next_i] as Vector2
			
			st.set_uv(p1 * 0.5 + Vector2(0.5, 0.5))
			st.add_vertex(Vector3(p1.x, p1.y, thickness * 0.5))
			st.set_uv(p2 * 0.5 + Vector2(0.5, 0.5))
			st.add_vertex(Vector3(p2.x, p2.y, thickness * 0.5))
			st.set_uv(center * 0.5 + Vector2(0.5, 0.5))
			st.add_vertex(Vector3(center.x, center.y, thickness * 0.5 + 0.01))

		# 背面多边形三角化
		for i in range(count):
			var next_i: int = (i + 1) % count
			var p1: Vector2 = poly[i] as Vector2
			var p2: Vector2 = poly[next_i] as Vector2
			
			st.set_uv(center * 0.5 + Vector2(0.5, 0.5))
			st.add_vertex(Vector3(center.x, center.y, -thickness * 0.5 - 0.01))
			st.set_uv(p2 * 0.5 + Vector2(0.5, 0.5))
			st.add_vertex(Vector3(p2.x, p2.y, -thickness * 0.5))
			st.set_uv(p1 * 0.5 + Vector2(0.5, 0.5))
			st.add_vertex(Vector3(p1.x, p1.y, -thickness * 0.5))

		# 侧面多面厚度倒角 (Beveled Edges)
		for i in range(count):
			var next_i: int = (i + 1) % count
			var p1: Vector2 = poly[i] as Vector2
			var p2: Vector2 = poly[next_i] as Vector2

			var v1_f := Vector3(p1.x, p1.y, thickness * 0.5)
			var v2_f := Vector3(p2.x, p2.y, thickness * 0.5)
			var v1_b := Vector3(p1.x, p1.y, -thickness * 0.5)
			var v2_b := Vector3(p2.x, p2.y, -thickness * 0.5)

			st.add_vertex(v1_f)
			st.add_vertex(v1_b)
			st.add_vertex(v2_f)

			st.add_vertex(v2_f)
			st.add_vertex(v1_b)
			st.add_vertex(v2_b)

		st.generate_normals()
		st.generate_tangents()
		var mesh := st.commit()
		_shard_meshes.append(mesh)
