extends "res://scripts/skills/skill_base.gd"
## Skill: Earth Slash / 裂地斩 (三道烈谷·狂焰奔涌).
## Pure procedural shader rendering with zero texture dependencies and zero rock debris.
## Features:
## 1. Ground flame ring erupting at caster's landing impact.
## 2. 3 radiating deep-black burnt fissures with dense, roaring 3D volumetric fire plumes.
## 3. Massive terminal erupting flame crowns at all 3 gorge tips (zero crude rock spikes).
## 4. Sector-wide AOE hitzone launching enemies with heavy hit reactions.

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const EarthSlashFissureShader = preload("res://shaders/earth_slash_fissure.gdshader")
const EarthSlashFlameVolumeShader = preload("res://shaders/earth_slash_flame_volume.gdshader")
const EarthSlashRingFireShader = preload("res://shaders/earth_slash_ring_fire.gdshader")
const EarthSlashSpatialVibrationShader = preload("res://shaders/earth_slash_spatial_vibration.gdshader")

const WINDUP_TIME: float = 0.6
const FISSURE_TEAR_TIME: float = 0.22

var slash_range: float = 14.0
var slash_angle: float = 40.0
var fissure_spread: float = 24.0
var damage: float = 45.0
var launch_height: float = 2.6
var launch_dist: float = 4.2
var fissure_duration: float = 2.4

# Visual tuning parameters
var fissure_width: float = 1.1
var abyss_width: float = 0.15
var flame_scale: float = 1.35
var heat_intensity: float = 1.25

static var _cached_plane_mesh: PlaneMesh = null
static var _cached_flame_cone_mesh: CylinderMesh = null
static var _warmup_mats: Array = []
static var _active_knockdowns: Dictionary = {}


func get_id() -> String:
	return "earth_slash"


func get_name() -> String:
	return "🌋 裂地斩 (三道烈谷·狂焰奔涌)"


func get_title() -> String:
	return "🌋 裂地斩配置 (EARTH SLASH & ROARING FLAME FISSURE)"


func get_params() -> Dictionary:
	return {
		"slash_range": slash_range,
		"slash_angle": slash_angle,
		"fissure_spread": fissure_spread,
		"damage": damage,
		"launch_height": launch_height,
		"launch_dist": launch_dist,
		"fissure_duration": fissure_duration,
		"fissure_width": fissure_width,
		"abyss_width": abyss_width,
		"flame_scale": flame_scale,
		"heat_intensity": heat_intensity
	}


func set_param(key: String, value: Variant) -> void:
	match key:
		"slash_range": slash_range = clampf(float(value), 6.0, 26.0)
		"slash_angle": slash_angle = clampf(float(value), 15.0, 75.0)
		"fissure_spread": fissure_spread = clampf(float(value), 10.0, 45.0)
		"damage": damage = clampf(float(value), 5.0, 150.0)
		"launch_height": launch_height = clampf(float(value), 0.5, 6.0)
		"launch_dist": launch_dist = clampf(float(value), 1.0, 12.0)
		"fissure_duration": fissure_duration = clampf(float(value), 0.8, 5.0)
		"fissure_width": fissure_width = clampf(float(value), 0.3, 2.5)
		"abyss_width": abyss_width = clampf(float(value), 0.03, 0.40)
		"flame_scale": flame_scale = clampf(float(value), 0.6, 3.0)
		"heat_intensity": heat_intensity = clampf(float(value), 0.5, 3.0)


func cast(caster: CharacterBody3D, intent_dir: Vector3, vfx_parent: Node, _is_spectator: bool = false) -> Dictionary:
	if caster == null or not is_instance_valid(caster) or not caster.is_inside_tree():
		return {}
	return _execute_earth_slash(caster, intent_dir, vfx_parent)


func replay(caster: CharacterBody3D, record: Dictionary, vfx_parent: Node) -> void:
	if caster == null or not is_instance_valid(caster) or not caster.is_inside_tree():
		return
	var intent_dir: Vector3 = record.get("intent_dir", caster.global_transform.basis.z)
	_execute_earth_slash(caster, intent_dir, vfx_parent)


func get_replay_hold_time(_record: Dictionary) -> float:
	return WINDUP_TIME + fissure_duration + 1.0


func _execute_earth_slash(caster: CharacterBody3D, intent_dir: Vector3, parent: Node) -> Dictionary:
	_ensure_cached_resources()

	var start_pos := caster.global_position
	var fwd := intent_dir
	fwd.y = 0.0
	if fwd.length_squared() > 0.01:
		fwd = fwd.normalized()
	else:
		fwd = caster.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length_squared() > 0.01 else Vector3.FORWARD

	# Align caster facing
	caster.rotation.y = atan2(fwd.x, fwd.z)

	var raw_ch: Variant = caster.get("character")
	var has_anim: bool = raw_ch != null and is_instance_valid(raw_ch) and raw_ch.has_method("play")
	var anim_player: AnimationPlayer = raw_ch.get("player") if has_anim else null

	# Trigger overhead throw animation
	if has_anim:
		var played := false
		if raw_ch.has_method("has_clip"):
			if raw_ch.call("has_clip", "overhead_throw"):
				played = raw_ch.call("play", "overhead_throw", 0.06)
			elif raw_ch.call("has_clip", "overhand_throw"):
				played = raw_ch.call("play", "overhand_throw", 0.06)
		if not played:
			raw_ch.call("play", "overhand_throw", 0.06)

	var token := Time.get_ticks_msec()
	caster.set_meta("skill_frozen", true)
	caster.set_meta("earth_slash_token", token)

	var root := Node3D.new()
	root.name = "EarthSlashVFX_%d" % token
	parent.add_child(root)
	root.global_position = start_pos

	# 0.6s: Impact slam on ground & erupt fiery ring + triple fissures + terminal flame crowns
	var impact_tw := root.create_tween()
	impact_tw.tween_interval(WINDUP_TIME)
	impact_tw.tween_callback(func():
		if root != null and is_instance_valid(root) and caster != null and is_instance_valid(caster):
			_on_slam_down(caster, root, start_pos, fwd)
	)

	# Animation pause at 0.6s and recovery
	if anim_player != null and is_instance_valid(anim_player):
		var anim_tw := root.create_tween()
		anim_tw.tween_interval(WINDUP_TIME)
		anim_tw.tween_callback(func():
			if anim_player != null and is_instance_valid(anim_player):
				anim_player.set_meta("earth_slash_old_speed", anim_player.speed_scale)
				anim_player.speed_scale = 0.0
		)
		anim_tw.tween_interval(0.20)
		anim_tw.tween_callback(func():
			_force_restore_anim(anim_player)
		)

	# Control recovery for caster
	if caster.is_inside_tree():
		var caster_tw := caster.create_tween()
		caster_tw.tween_interval(WINDUP_TIME + 0.30)
		caster_tw.tween_callback(func():
			if caster != null and is_instance_valid(caster) and caster.get_meta("earth_slash_token", 0) == token:
				caster.remove_meta("skill_frozen")
				caster.remove_meta("earth_slash_token")
				_force_restore_anim(anim_player)
		)

	# Free root VFX node
	var clean_tw := root.create_tween()
	clean_tw.tween_interval(WINDUP_TIME + fissure_duration + 1.0)
	clean_tw.tween_callback(func():
		if root != null and is_instance_valid(root):
			root.queue_free()
	)

	return {
		"success": true,
		"skill_id": get_id(),
		"from_pos": start_pos,
		"intent_dir": fwd,
		"slash_range": slash_range,
		"damage": damage
	}


static func _force_restore_anim(anim_player: AnimationPlayer) -> void:
	if anim_player == null or not is_instance_valid(anim_player):
		return
	if anim_player.has_meta("earth_slash_old_speed"):
		anim_player.speed_scale = anim_player.get_meta("earth_slash_old_speed")
		anim_player.remove_meta("earth_slash_old_speed")
	elif anim_player.speed_scale == 0.0:
		anim_player.speed_scale = 1.0


## 0.6s Impact: Slam down, spawn ground ring fire, 3 flaming fissures with dense fire and terminal crowns
func _on_slam_down(caster: CharacterBody3D, root: Node3D, start_pos: Vector3, fwd: Vector3) -> void:
	AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg", 1.40)

	# 1. Caster Feet Ground Fire Ring
	_spawn_caster_ring_fire(root, start_pos)

	# 2. Sector-shaped air vibration
	_spawn_sector_spatial_vibration(root, start_pos, fwd, slash_range, slash_angle)

	# 3. Spawn 3 Radiating Fissures (Deep-black core rift + dense 3D volumetric fire plumes)
	var configs := [
		{ "deg": 0.0, "len": slash_range, "is_main": true },
		{ "deg": -fissure_spread, "len": slash_range * 0.88, "is_main": false },
		{ "deg": fissure_spread, "len": slash_range * 0.88, "is_main": false },
	]

	var origin := start_pos + fwd * 0.6
	origin.y = start_pos.y

	for cfg in configs:
		var dir := fwd.rotated(Vector3.UP, deg_to_rad(float(cfg["deg"]))).normalized()
		_spawn_fiery_fissure_gorge(root, origin, dir, float(cfg["len"]), bool(cfg["is_main"]))

	# 4. Whole Sector AOE Damage Scan & Launch
	_apply_sector_strike(caster, start_pos, fwd, slash_range, slash_angle, damage)


## 1. Caster Impact Ring Fire: Circular burst of flames and scorched earth around feet
func _spawn_caster_ring_fire(root: Node3D, pos: Vector3) -> void:
	var ring_mesh := MeshInstance3D.new()
	ring_mesh.mesh = _cached_plane_mesh
	ring_mesh.scale = Vector3(4.2, 1.0, 4.2)
	ring_mesh.global_position = pos + Vector3(0.0, 0.035, 0.0)
	root.add_child(ring_mesh)

	var ring_mat := ShaderMaterial.new()
	ring_mat.shader = EarthSlashRingFireShader
	ring_mat.set_shader_parameter("core_color", Color(1.10, 0.98, 0.78, 1.0))
	ring_mat.set_shader_parameter("mid_color", Color(0.96, 0.48, 0.06, 0.95))
	ring_mat.set_shader_parameter("edge_color", Color(0.50, 0.10, 0.02, 0.85))
	ring_mat.set_shader_parameter("crust_color", Color(0.08, 0.04, 0.02, 0.95))
	ring_mat.set_shader_parameter("intensity", heat_intensity * 1.1)
	ring_mat.set_shader_parameter("ring_radius", 0.52)
	ring_mat.set_shader_parameter("ring_thickness", 0.18)
	ring_mat.set_shader_parameter("fade", 1.0)
	ring_mesh.material_override = ring_mat

	var tw := ring_mesh.create_tween()
	tw.tween_interval(fissure_duration * 0.70)
	tw.tween_property(ring_mat, "shader_parameter/fade", 0.0, 0.55).set_ease(Tween.EASE_IN)
	tw.tween_callback(ring_mesh.queue_free)


## 2. Sector Space Vibration
func _spawn_sector_spatial_vibration(root: Node3D, start_pos: Vector3, fwd: Vector3, radius: float, half_angle: float) -> void:
	var sector_pivot := Node3D.new()
	root.add_child(sector_pivot)
	sector_pivot.global_position = start_pos
	sector_pivot.rotation.y = atan2(fwd.x, fwd.z)

	var sector_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(radius * 2.2, radius * 2.2)
	sector_mesh.mesh = pm
	sector_mesh.position = Vector3(0.0, 0.04, radius * 0.5)
	sector_pivot.add_child(sector_mesh)

	var mat := ShaderMaterial.new()
	mat.shader = EarthSlashSpatialVibrationShader
	mat.set_shader_parameter("sector_angle_deg", half_angle)
	mat.set_shader_parameter("wave_progress", 0.0)
	mat.set_shader_parameter("fade", 1.0)
	sector_mesh.material_override = mat

	var tw := sector_pivot.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mat, "shader_parameter/wave_progress", 1.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "shader_parameter/fade", 0.0, 0.35).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(sector_pivot.queue_free)


## 3. Spawns a complete fissure with Ground Scorch, Dense 3D Flames, and Massive Terminal Flame Crown
func _spawn_fiery_fissure_gorge(root: Node3D, origin: Vector3, dir: Vector3, length: float, is_main: bool) -> void:
	var gorge_pivot := Node3D.new()
	root.add_child(gorge_pivot)
	gorge_pivot.global_position = origin
	gorge_pivot.rotation.y = atan2(dir.x, dir.z)

	var f_width := fissure_width * (1.25 if is_main else 1.0)

	# A. Ground Fissure Plane (scorched basalt + deep black abyss trench + warm magma glow)
	var fissure_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(f_width * 2.6, length)
	fissure_mesh.mesh = pm
	fissure_mesh.position = Vector3(0.0, 0.03, length * 0.5)
	gorge_pivot.add_child(fissure_mesh)

	var fissure_mat := ShaderMaterial.new()
	fissure_mat.shader = EarthSlashFissureShader
	fissure_mat.set_shader_parameter("glow_core", Color(1.08, 0.96, 0.80, 1.0))
	fissure_mat.set_shader_parameter("glow_amber", Color(0.95, 0.46, 0.06, 1.0))
	fissure_mat.set_shader_parameter("glow_crimson", Color(0.48, 0.10, 0.02, 1.0))
	fissure_mat.set_shader_parameter("crust_color", Color(0.09, 0.05, 0.03, 0.95))
	fissure_mat.set_shader_parameter("abyss_black", Color(0.010, 0.006, 0.006, 1.0))
	fissure_mat.set_shader_parameter("heat_intensity", heat_intensity)
	fissure_mat.set_shader_parameter("fissure_width", f_width)
	fissure_mat.set_shader_parameter("abyss_width", abyss_width)
	fissure_mat.set_shader_parameter("tear_progress", 0.0)
	fissure_mat.set_shader_parameter("fade", 1.0)
	fissure_mesh.material_override = fissure_mat

	# B. Dense 3D Volumetric Roaring Flames along the entire gorge path
	_spawn_dense_volume_flames(gorge_pivot, length, is_main)

	# C. Massive Terminal Flame Eruption at the tip (Zero rock spikes)
	var tip_pos := Vector3(0.0, 0.0, length)
	_spawn_massive_terminal_flame(gorge_pivot, tip_pos, is_main)

	# D. Progressive forward tearing animation
	var tw := gorge_pivot.create_tween()
	tw.tween_property(fissure_mat, "shader_parameter/tear_progress", 1.0, FISSURE_TEAR_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(fissure_duration)
	tw.tween_property(fissure_mat, "shader_parameter/fade", 0.0, 0.65).set_ease(Tween.EASE_IN)
	tw.tween_callback(gorge_pivot.queue_free)


## Dense 3D volumetric flames along the entire fissure path
func _spawn_dense_volume_flames(gorge_pivot: Node3D, length: float, is_main: bool) -> void:
	var flame_root := Node3D.new()
	gorge_pivot.add_child(flame_root)

	var flame_mat := ShaderMaterial.new()
	flame_mat.shader = EarthSlashFlameVolumeShader
	flame_mat.set_shader_parameter("core_color", Color(1.45, 1.25, 0.85, 1.0))
	flame_mat.set_shader_parameter("mid_color", Color(1.20, 0.52, 0.05, 1.0))
	flame_mat.set_shader_parameter("edge_color", Color(0.75, 0.14, 0.02, 0.90))
	flame_mat.set_shader_parameter("smoke_color", Color(0.12, 0.04, 0.02, 0.40))
	flame_mat.set_shader_parameter("intensity", heat_intensity * 1.15)
	flame_mat.set_shader_parameter("rise_speed", 5.2)
	flame_mat.set_shader_parameter("flame_wobble", 0.22)
	flame_mat.set_shader_parameter("fade", 1.0)

	# Denser sequential fire steps along the path (every 1.1m)
	var count := maxi(4, int(length / 1.15))
	for i in range(count):
		var t := float(i + 1) / float(count + 1)
		var z_pos := length * t
		var delay := t * FISSURE_TEAR_TIME

		var flame_cone := MeshInstance3D.new()
		flame_cone.mesh = _cached_flame_cone_mesh
		flame_cone.material_override = flame_mat
		# Slight stagger left/right for natural turbulent fire stream
		var x_offset := sin(float(i) * 1.7) * (0.28 if is_main else 0.18)
		flame_cone.position = Vector3(x_offset, 0.0, z_pos)
		flame_root.add_child(flame_cone)

		var s := flame_scale * (randf_range(1.05, 1.35) if is_main else randf_range(0.85, 1.15))
		flame_cone.scale = Vector3(s * 0.2, 0.05, s * 0.2)

		var tw := flame_cone.create_tween()
		tw.tween_interval(delay)
		tw.tween_property(flame_cone, "scale", Vector3(s, s * 1.25, s), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var root_tw := flame_root.create_tween()
	root_tw.tween_interval(fissure_duration)
	root_tw.tween_property(flame_mat, "shader_parameter/fade", 0.0, 0.60).set_ease(Tween.EASE_IN)


## Massive Terminal Flame Eruption at the tip of each gorge (pure roaring fire, zero rock debris)
func _spawn_massive_terminal_flame(gorge_pivot: Node3D, tip_pos: Vector3, is_main: bool) -> void:
	var term_root := Node3D.new()
	term_root.position = tip_pos
	gorge_pivot.add_child(term_root)

	var delay := FISSURE_TEAR_TIME * 0.90

	var crown_mat := ShaderMaterial.new()
	crown_mat.shader = EarthSlashFlameVolumeShader
	crown_mat.set_shader_parameter("core_color", Color(1.50, 1.30, 0.90, 1.0))
	crown_mat.set_shader_parameter("mid_color", Color(1.25, 0.55, 0.06, 1.0))
	crown_mat.set_shader_parameter("edge_color", Color(0.78, 0.15, 0.02, 0.90))
	crown_mat.set_shader_parameter("smoke_color", Color(0.12, 0.04, 0.02, 0.40))
	crown_mat.set_shader_parameter("intensity", heat_intensity * 1.30)
	crown_mat.set_shader_parameter("rise_speed", 5.8)
	crown_mat.set_shader_parameter("flame_wobble", 0.25)
	crown_mat.set_shader_parameter("fade", 1.0)

	# Main giant terminal fire core
	var main_cone := MeshInstance3D.new()
	main_cone.mesh = _cached_flame_cone_mesh
	main_cone.material_override = crown_mat
	main_cone.position = Vector3(0.0, 0.0, 0.0)
	term_root.add_child(main_cone)

	var ts := flame_scale * (2.1 if is_main else 1.65)
	main_cone.scale = Vector3(ts * 0.2, 0.05, ts * 0.2)

	var c_tw := main_cone.create_tween()
	c_tw.tween_interval(delay)
	c_tw.tween_property(main_cone, "scale", Vector3(ts, ts * 1.4, ts), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Flanking side flame bursts to create a wide fiery crown
	for side_x in [-0.55, 0.55]:
		var side_cone := MeshInstance3D.new()
		side_cone.mesh = _cached_flame_cone_mesh
		side_cone.material_override = crown_mat
		side_cone.position = Vector3(side_x * (1.2 if is_main else 0.8), 0.0, -0.2)
		term_root.add_child(side_cone)

		var ss := ts * 0.72
		side_cone.scale = Vector3(ss * 0.2, 0.05, ss * 0.2)

		var s_tw := side_cone.create_tween()
		s_tw.tween_interval(delay + randf_range(0.01, 0.04))
		s_tw.tween_property(side_cone, "scale", Vector3(ss, ss * 1.15, ss), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var term_tw := term_root.create_tween()
	term_tw.tween_interval(fissure_duration)
	term_tw.tween_property(crown_mat, "shader_parameter/fade", 0.0, 0.60).set_ease(Tween.EASE_IN)


## Whole Sector Area Hit Detection & Launch
func _apply_sector_strike(caster: CharacterBody3D, origin: Vector3, fwd: Vector3, radius: float, half_angle_deg: float, dmg: float) -> void:
	if caster == null or not is_instance_valid(caster) or not caster.is_inside_tree():
		return
	var tree := caster.get_tree()
	if tree == null:
		return

	var candidates: Array = []
	var group_nodes := tree.get_nodes_in_group("characters")
	if not group_nodes.is_empty():
		candidates.append_array(group_nodes)
	else:
		var scene_root := tree.current_scene
		if scene_root != null:
			for ch in scene_root.find_children("*", "CharacterBody3D", true, false):
				candidates.append(ch)
			for ch in scene_root.find_children("*", "DummyTarget", true, false):
				candidates.append(ch)

	var cos_threshold := cos(deg_to_rad(half_angle_deg))

	for b in candidates:
		if b == null or not is_instance_valid(b) or b == caster or b.name == "Ground":
			continue
		if not (b is Node3D):
			continue
		var n3d := b as Node3D
		var to_b := n3d.global_position - origin
		to_b.y = 0.0
		var dist := to_b.length()
		if dist > radius or dist < 0.05:
			continue

		var dir_to_b := to_b.normalized()
		var dot := fwd.dot(dir_to_b)
		if dot < cos_threshold:
			continue

		# Target is inside the whole sector hitzone
		var hit_pos := n3d.global_position + Vector3.UP * 1.0
		var push_dir := (dir_to_b + fwd * 0.5).normalized()

		if b.has_method("take_hit"):
			b.call("take_hit", hit_pos, dmg, push_dir)

		if b is CharacterBody3D:
			_launch_and_knockdown_actor(b as CharacterBody3D, push_dir, launch_height, launch_dist, 1.4)
		elif b.has_method("apply_hit_reaction"):
			b.call("apply_hit_reaction", "hit_knockback", 0.4)


## Parabolic launch and knockdown for CharacterBody3D actors
func _launch_and_knockdown_actor(target: CharacterBody3D, push_dir: Vector3, v_height: float, h_dist: float, duration: float) -> void:
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

	target.set_physics_process(false)
	target.velocity = Vector3.ZERO

	if anim_tree != null and is_instance_valid(anim_tree):
		anim_tree.active = false

	if ch != null and is_instance_valid(ch) and ch.has_method("play"):
		ch.call("play", "hit_knockback", 0.06)

	var start_pos := target.global_position
	var target_end_pos := start_pos + push_dir * h_dist
	target_end_pos.y = start_pos.y
	var mid_pos := (start_pos + target_end_pos) * 0.5
	var apex_y := start_pos.y + v_height
	var air_time := 0.45
	var half_air := air_time * 0.5

	var tw := target.create_tween()
	_active_knockdowns[t_id] = { "actor": target, "tween": tw }

	# Parabola
	tw.set_parallel(true)
	tw.tween_property(target, "global_position:x", mid_pos.x, half_air).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(target, "global_position:z", mid_pos.z, half_air).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(target, "global_position:y", apex_y, half_air).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	tw.chain().set_parallel(true)
	tw.tween_property(target, "global_position:x", target_end_pos.x, half_air).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(target, "global_position:z", target_end_pos.z, half_air).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(target, "global_position:y", start_pos.y, half_air).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Lie on ground
	tw.chain().tween_interval(duration)

	# Getup
	tw.chain().tween_callback(func():
		if is_instance_valid(ch) and ch.has_method("play"):
			ch.call("play", "lay_to_idle", 0.15)
	)
	tw.tween_interval(1.2)

	# Restore control
	tw.chain().tween_callback(func():
		_active_knockdowns.erase(t_id)
		if is_instance_valid(target):
			target.set("state", 0)
			target.velocity = Vector3.ZERO
			target.set_physics_process(true)
		if is_instance_valid(anim_tree):
			anim_tree.active = true
	)


static func _ensure_cached_resources() -> void:
	if _cached_plane_mesh == null:
		_cached_plane_mesh = PlaneMesh.new()
		_cached_plane_mesh.size = Vector2(1.0, 1.0)

	if _cached_flame_cone_mesh == null:
		_cached_flame_cone_mesh = CylinderMesh.new()
		_cached_flame_cone_mesh.top_radius = 0.08
		_cached_flame_cone_mesh.bottom_radius = 0.52
		_cached_flame_cone_mesh.height = 1.7
		_cached_flame_cone_mesh.radial_segments = 6
		_cached_flame_cone_mesh.rings = 3

	if _warmup_mats.is_empty():
		var m_fissure := ShaderMaterial.new()
		m_fissure.shader = EarthSlashFissureShader
		_warmup_mats.append(m_fissure)

		var m_flame := ShaderMaterial.new()
		m_flame.shader = EarthSlashFlameVolumeShader
		_warmup_mats.append(m_flame)

		var m_ring := ShaderMaterial.new()
		m_ring.shader = EarthSlashRingFireShader
		_warmup_mats.append(m_ring)

		var m_vib := ShaderMaterial.new()
		m_vib.shader = EarthSlashSpatialVibrationShader
		_warmup_mats.append(m_vib)


func build_config_panel(container: VBoxContainer, on_changed: Callable) -> void:
	_add_slider(container, on_changed, "slash_range", "扇形射程 (Range): %.1fm", slash_range, 6.0, 26.0, 0.5)
	_add_slider(container, on_changed, "slash_angle", "扇形半角 (Sector Half Angle): %.0f°", slash_angle, 15.0, 75.0, 1.0)
	_add_slider(container, on_changed, "fissure_spread", "三裂谷散角 (Fissure Spread): %.0f°", fissure_spread, 10.0, 45.0, 1.0)
	_add_slider(container, on_changed, "flame_scale", "3D火焰尺寸 (Flame Scale): %.2f", flame_scale, 0.6, 3.0, 0.05)
	_add_slider(container, on_changed, "fissure_width", "地裂总体宽度 (Fissure Width): %.2f", fissure_width, 0.3, 2.5, 0.05)
	_add_slider(container, on_changed, "abyss_width", "深黑地缝宽度 (Abyss Trench): %.2f", abyss_width, 0.03, 0.40, 0.01)
	_add_slider(container, on_changed, "heat_intensity", "火焰烈度 (Intensity): %.2f", heat_intensity, 0.5, 3.0, 0.05)
	_add_slider(container, on_changed, "damage", "伤害数值 (Damage): %.0f", damage, 10.0, 120.0, 2.0)
	_add_slider(container, on_changed, "launch_height", "击飞高度 (Launch Height): %.1fm", launch_height, 0.5, 6.0, 0.2)
	_add_slider(container, on_changed, "launch_dist", "击退距离 (Launch Distance): %.1fm", launch_dist, 1.0, 10.0, 0.5)
	_add_slider(container, on_changed, "fissure_duration", "地裂持续时长 (Duration): %.1fs", fissure_duration, 0.8, 5.0, 0.1)

	var tip_panel := PanelContainer.new()
	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.12, 0.06, 0.03, 0.92)
	t_style.set_corner_radius_all(6)
	t_style.set_border_width_all(1)
	t_style.border_color = Color(0.95, 0.50, 0.15, 0.80)
	t_style.set_content_margin_all(8)
	tip_panel.add_theme_stylebox_override("panel", t_style)
	container.add_child(tip_panel)

	var tip_vbox := VBoxContainer.new()
	tip_vbox.add_theme_constant_override("separation", 4)
	tip_panel.add_child(tip_vbox)

	var tip1 := Label.new()
	tip1.text = "🔥 纯正 3D 体积狂焰：三道裂谷烈火奔涌喷薄，末端巨型火焰冠冕爆发"
	tip1.add_theme_font_size_override("font_size", 11)
	tip1.modulate = Color(1.0, 0.85, 0.55)
	tip_vbox.add_child(tip1)

	var tip2 := Label.new()
	tip2.text = "🌋 彻底去除粗糙碎石，深黑玄武地缝与纯粹烈火交织，气势磅礴"
	tip2.add_theme_font_size_override("font_size", 11)
	tip2.modulate = Color(0.9, 0.9, 0.9)
	tip_vbox.add_child(tip2)


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


func reset_state() -> void:
	_active_knockdowns.clear()


func preload_assets() -> void:
	AudioManagerScript.preload_sounds([
		"res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg"
	])
	_ensure_cached_resources()


func get_warmup_materials() -> Array:
	_ensure_cached_resources()
	return _warmup_mats.duplicate()
