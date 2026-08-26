extends "res://scripts/skills/skill_base.gd"
## 技能十七：裂空斩势 (Rift Slash Empowerment).
## Buff：持续期内每次普攻起手额外射出一道向前飞行的弧形风刃 (复用 CURVED_WIND_SLASH + curved_wind_blade shader)。
## Hook: PlayerController._begin_weapon_action() -> on_weapon_action(caster)。
## Invariant: _empowered[caster_id] == expire_msec; 过期条目在 on_weapon_action / reset_state 清理。

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const CurvedWindBladeShader = preload("res://shaders/curved_wind_blade.gdshader")

var duration: float = 10.0
var damage: float = 14.0
var projectile_speed: float = 26.0
var projectile_range: float = 22.0
var blade_scale: float = 1.5
var blade_roll: float = -90.0
var blade_tilt: float = 22.0

## caster_instance_id -> {"expire": msec, "dmg": float, "speed": float, "range": float, "scale": float}
static var _empowered: Dictionary = {}

func get_id() -> String:
	return "rift_slash"

func get_name() -> String:
	return "🌙 裂空斩势 (普攻裂空斩)"

func get_title() -> String:
	return "🌙 裂空斩势配置 (RIFT SLASH EMPOWERMENT)"

func get_params() -> Dictionary:
	return {
		"duration": duration,
		"damage": damage,
		"projectile_speed": projectile_speed,
		"projectile_range": projectile_range,
		"blade_scale": blade_scale,
		"blade_roll": blade_roll,
		"blade_tilt": blade_tilt
	}

func set_param(key: String, value: Variant) -> void:
	match key:
		"duration": duration = float(value)
		"damage": damage = float(value)
		"projectile_speed": projectile_speed = float(value)
		"projectile_range": projectile_range = float(value)
		"blade_scale": blade_scale = float(value)
		"blade_roll": blade_roll = float(value)
		"blade_tilt": blade_tilt = float(value)

func cast(caster: CharacterBody3D, _intent_dir: Vector3, _vfx_parent: Node, _is_spectator: bool = false) -> Dictionary:
	if caster == null or not is_instance_valid(caster):
		return {}
	_grant(caster, duration, damage, projectile_speed, projectile_range, blade_scale, blade_roll, blade_tilt)
	AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg", 1.35)
	return {
		"success": true,
		"skill_id": get_id(),
		"from_pos": caster.global_position if caster.is_inside_tree() else Vector3.ZERO,
		"duration": duration
	}

func replay(caster: CharacterBody3D, record: Dictionary, _vfx_parent: Node) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	_grant(caster, float(record.get("duration", duration)), damage, projectile_speed, projectile_range, blade_scale, blade_roll, blade_tilt)

func get_replay_hold_time(record: Dictionary) -> float:
	return float(record.get("duration", duration)) + 0.5

## _grant(): 赋予/刷新裂空斩势。Post: _empowered[id].expire = now + dur。
static func _grant(caster: CharacterBody3D, dur: float, dmg: float, spd: float, rng: float, scl: float,
		roll: float = -90.0, tilt: float = 22.0) -> void:
	_empowered[caster.get_instance_id()] = {
		"expire": Time.get_ticks_msec() + int(dur * 1000.0),
		"dmg": dmg,
		"speed": spd,
		"range": rng,
		"scale": scl,
		"roll": roll,
		"tilt": tilt
	}

## is_empowered(): buff 是否仍有效（顺带清理过期条目）。
static func is_empowered(caster: CharacterBody3D) -> bool:
	if caster == null or not is_instance_valid(caster):
		return false
	var c_id := caster.get_instance_id()
	if not _empowered.has(c_id):
		return false
	if Time.get_ticks_msec() > int(_empowered[c_id].get("expire", 0)):
		_empowered.erase(c_id)
		return false
	return true

## on_weapon_action(): 普攻起手钩子。Pre: 由 PlayerController._begin_weapon_action 调用。
## Post: buff 有效时向 caster 正前方发射一道飞行风刃。
static func on_weapon_action(caster: CharacterBody3D) -> void:
	if not is_empowered(caster) or not caster.is_inside_tree():
		return
	var cfg: Dictionary = _empowered[caster.get_instance_id()]
	var origin := caster.global_position + Vector3.UP * 1.0
	var fwd := caster.global_basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	_spawn_flying_blade(caster, origin, fwd, cfg)

## 飞行风刃：直线推进 + 半径 1.7 命中扫描（每个目标只中一次），到达射程或撞人后消散。
static func _spawn_flying_blade(caster: CharacterBody3D, origin: Vector3, fwd: Vector3, cfg: Dictionary) -> void:
	var parent: Node = caster.get_tree().current_scene
	if parent == null or not is_instance_valid(parent):
		parent = caster

	var pivot := Node3D.new()
	pivot.name = "RiftSlashBlade"
	parent.add_child(pivot)
	pivot.global_position = origin
	# 刃面平行地面：quad 法线 (+z) 对齐世界 UP，贴图 +y 指向飞行方向 fwd。
	var b_x := fwd.cross(Vector3.UP).normalized()
	pivot.global_basis = Basis(b_x, fwd, Vector3.UP).orthonormalized()
	# roll: 贴图在水平刃面内绕 UP 自转 (-90 = 弧刃指向正前方)。
	pivot.rotate_object_local(Vector3.BACK, deg_to_rad(float(cfg.get("roll", -90.0))))
	# tilt: 绕世界行进轴 fwd 侧倾，做出斜斩姿态。0 = 完全贴平地面。
	pivot.rotate(fwd, deg_to_rad(float(cfg.get("tilt", 22.0))))

	var mesh_inst := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(3.8, 3.8)
	mesh_inst.mesh = qm
	var s: float = float(cfg.get("scale", 1.5)) * 0.62
	mesh_inst.scale = Vector3(s, s, 1.0)

	var mat := ShaderMaterial.new()
	mat.shader = CurvedWindBladeShader
	mat.set_shader_parameter("outer_color", Color(0.62, 0.80, 1.0, 1.0))
	mat.set_shader_parameter("mid_color", Color(0.86, 0.94, 1.0, 1.0))
	mat.set_shader_parameter("core_color", Color(1.0, 1.0, 1.0, 1.0))
	mat.set_shader_parameter("intensity", 3.4)
	mat.set_shader_parameter("contrast_boost", 2.0)
	mat.set_shader_parameter("fade", 1.0)
	mat.set_shader_parameter("dissolve", 0.0)
	VfxTextures.bind(mat, "blade_tex", VfxTextures.CURVED_WIND_SLASH, "", 1.0)
	mesh_inst.material_override = mat
	pivot.add_child(mesh_inst)

	AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg", 1.55)

	var speed: float = float(cfg.get("speed", 26.0))
	var max_range: float = float(cfg.get("range", 22.0))
	var dmg: float = float(cfg.get("dmg", 14.0))
	var life: float = max_range / maxf(speed, 0.01)
	var hit_ids: Dictionary = {}

	var tw := pivot.create_tween()
	tw.tween_method(func(t: float):
		if not is_instance_valid(pivot):
			return
		pivot.global_position = origin + fwd * (speed * t) + Vector3.UP * sin(t * 6.0) * 0.04
		_scan_hits(caster, pivot.global_position, dmg, hit_ids)
	, 0.0, life, life)
	tw.parallel().tween_property(mat, "shader_parameter/fade", 0.0, 0.30).set_delay(maxf(life - 0.30, 0.0))
	tw.parallel().tween_property(mat, "shader_parameter/dissolve", 0.9, 0.35).set_delay(maxf(life - 0.35, 0.0))
	tw.chain().tween_callback(pivot.queue_free)

## _scan_hits(): 命中判定。Post: hit_ids 记录已命中目标，避免重复伤害。
static func _scan_hits(caster: CharacterBody3D, pos: Vector3, dmg: float, hit_ids: Dictionary) -> void:
	if caster == null or not is_instance_valid(caster) or not caster.is_inside_tree():
		return
	var tree := caster.get_tree()
	if tree == null:
		return

	var candidates: Array[Node] = tree.get_nodes_in_group("characters")
	if candidates.is_empty():
		var scene_root := tree.current_scene
		if scene_root != null:
			for ch in scene_root.find_children("*", "CharacterBody3D", true, false):
				candidates.append(ch)
			for ch in scene_root.find_children("*", "DummyTarget", true, false):
				candidates.append(ch)

	for b in candidates:
		if b == null or not is_instance_valid(b) or b == caster or b.name == "Ground":
			continue
		var b_id := b.get_instance_id()
		if hit_ids.has(b_id):
			continue
		if not (b is Node3D):
			continue
		var b_pos := (b as Node3D).global_position + Vector3.UP * 1.0
		if (b_pos - pos).length() > 1.7:
			continue
		hit_ids[b_id] = true
		var swing_dir := (b_pos - caster.global_position).normalized()
		if b.has_method("take_hit"):
			b.call("take_hit", b_pos, dmg, swing_dir)
		if b.has_method("apply_hit_reaction"):
			b.call("apply_hit_reaction", "hit_chest", 0.35)

func build_config_panel(container: VBoxContainer, on_changed: Callable) -> void:
	_add_slider(container, on_changed, "duration", "斩势持续 (Duration): %.1fs", duration, 2.0, 30.0, 0.5)
	_add_slider(container, on_changed, "damage", "单刃伤害 (Damage): %.0f", damage, 2.0, 60.0, 1.0)
	_add_slider(container, on_changed, "projectile_speed", "风刃飞行速度 (Speed): %.0f", projectile_speed, 8.0, 60.0, 1.0)
	_add_slider(container, on_changed, "projectile_range", "风刃射程 (Range): %.0f", projectile_range, 6.0, 60.0, 1.0)
	_add_slider(container, on_changed, "blade_scale", "刃身尺度 (Scale): %.2f", blade_scale, 0.5, 4.0, 0.05)
	_add_slider(container, on_changed, "blade_roll", "刃面内自转 (Roll): %.0f°", blade_roll, 0.0, 360.0, 5.0)
	_add_slider(container, on_changed, "blade_tilt", "刃面前倾 (Tilt): %.0f°", blade_tilt, -90.0, 90.0, 5.0)

func _add_slider(container: VBoxContainer, on_changed: Callable, key: String, fmt: String,
		val: float, lo: float, hi: float, step: float) -> void:
	var lbl := Label.new()
	lbl.text = fmt % val
	lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(lbl)

	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = val
	sl.value_changed.connect(func(v: float):
		set_param(key, v)
		lbl.text = fmt % v
		on_changed.call(key, v)
	)
	container.add_child(sl)

func dispel_actor(actor: CharacterBody3D) -> void:
	if actor != null and is_instance_valid(actor):
		_empowered.erase(actor.get_instance_id())

func reset_state() -> void:
	_empowered.clear()

func preload_assets() -> void:
	AudioManagerScript.preload_sounds([
		"res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg"
	])
	VfxTextures.get_tex(VfxTextures.CURVED_WIND_SLASH)

func get_warmup_materials() -> Array:
	var m := ShaderMaterial.new()
	m.shader = CurvedWindBladeShader
	VfxTextures.bind(m, "blade_tex", VfxTextures.CURVED_WIND_SLASH, "", 1.0)
	return [m]
