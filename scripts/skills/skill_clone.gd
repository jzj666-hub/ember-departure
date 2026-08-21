extends "res://scripts/skills/skill_base.gd"
## 分身 (Mirror Clone): summon a physically identical clone in place.
## For its lifetime both entities are driven by the same input, but the clone's
## left/right strafe is mirrored (A/D reversed) while everything else — W/S,
## facing, actions, effects — stays identical.

const AudioManagerScript = preload("res://scripts/audio_manager.gd")

## Clone lifetime (s).
var clone_duration: float = 8.0

## Active clone tracking: caster_id -> { "clone": PlayerController }
static var _active_clones: Dictionary = {}


## Mirrors the body around the cast-time facing axis: left/right strafe (A/D) and
## mouse look yaw are reversed; forward/back (W/S) and every other input are shared.
class MirrorIntentSource extends PlayerIntentSource:
	## 中轴：放技能时本体面朝的方向（镜头 yaw）。鼠标朝向/heading 以此轴对称镜像。
	var mirror_axis_yaw: float = 0.0

	func poll(body: Node, delta: float, intent: CharacterIntent) -> void:
		super.poll(body, delta, intent)
		intent.move.x = -intent.move.x
		intent.heading = 2.0 * mirror_axis_yaw - intent.heading


## Stands still (used for global-spectator replay, which only re-enacts the VFX).
class IdleCloneSource extends IntentSource:
	func poll(_body: Node, _delta: float, intent: CharacterIntent) -> void:
		intent.clear()


func get_id() -> String:
	return "clone"


func get_name() -> String:
	return "👥 分身 (轴对称镜像)"


func get_title() -> String:
	return "👥 分身配置 (MIRROR CLONE)"


func get_params() -> Dictionary:
	return {
		"clone_duration": clone_duration
	}


func set_param(key: String, value: Variant) -> void:
	match key:
		"clone_duration": clone_duration = float(value)


func cast(caster: CharacterBody3D, _intent_dir: Vector3, vfx_parent: Node, is_spectator: bool = false) -> Dictionary:
	if caster == null or not is_instance_valid(caster):
		return {}
	var c_id := caster.get_instance_id()
	if _active_clones.has(c_id):
		_despawn_clone(c_id)

	var clone := _spawn_clone(caster, vfx_parent, not is_spectator)
	if clone == null:
		return {}
	_active_clones[c_id] = { "clone": clone }
	_start_clone_timer(c_id, clone_duration)

	AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/cloth1.ogg", 1.0)

	return {
		"success": true,
		"skill_id": get_id(),
		"from_pos": caster.global_position,
		"clone_duration": clone_duration
	}


func replay(caster: CharacterBody3D, record: Dictionary, vfx_parent: Node) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	var c_id := caster.get_instance_id()
	if _active_clones.has(c_id):
		_despawn_clone(c_id)

	var clone := _spawn_clone(caster, vfx_parent, false)
	if clone == null:
		return
	var dur: float = float(record.get("clone_duration", clone_duration))
	_active_clones[c_id] = { "clone": clone }
	_start_clone_timer(c_id, dur)


func get_replay_hold_time(record: Dictionary) -> float:
	return maxf(float(record.get("clone_duration", clone_duration)) + 0.5, 2.0)


func build_config_panel(container: VBoxContainer, on_changed: Callable) -> void:
	# 持续时长
	var dur_lbl := Label.new()
	dur_lbl.text = "分身持续 (Duration): %.1fs" % clone_duration
	dur_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(dur_lbl)

	var dur_slider := HSlider.new()
	dur_slider.min_value = 2.0
	dur_slider.max_value = 20.0
	dur_slider.step = 0.5
	dur_slider.value = clone_duration
	dur_slider.value_changed.connect(func(v: float):
		clone_duration = v
		dur_lbl.text = "分身持续 (Duration): %.1fs" % v
		on_changed.call("clone_duration", v)
	)
	container.add_child(dur_slider)

	# 特性说明面板
	var tip_panel := PanelContainer.new()
	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.10, 0.06, 0.16, 0.85)
	t_style.set_corner_radius_all(6)
	t_style.set_border_width_all(1)
	t_style.border_color = Color(0.7, 0.4, 1.0, 0.55)
	t_style.set_content_margin_all(8)
	tip_panel.add_theme_stylebox_override("panel", t_style)
	container.add_child(tip_panel)

	var tip_vbox := VBoxContainer.new()
	tip_vbox.add_theme_constant_override("separation", 4)
	tip_panel.add_child(tip_vbox)

	var tip1 := Label.new()
	tip1.text = "👥 原地召唤一个外观完全相同的分身"
	tip1.add_theme_font_size_override("font_size", 11)
	tip1.modulate = Color(0.85, 0.7, 1.0)
	tip_vbox.add_child(tip1)

	var tip2 := Label.new()
	tip2.text = "🪞 技能期间同时操控本体与分身"
	tip2.add_theme_font_size_override("font_size", 11)
	tip2.modulate = Color(0.7, 0.5, 1.0)
	tip_vbox.add_child(tip2)

	var tip3 := Label.new()
	tip3.text = "↔️ A/D 左右位移镜像相反，W/S 及其余动作完全一致"
	tip3.add_theme_font_size_override("font_size", 11)
	tip3.modulate = Color(0.9, 0.75, 0.2)
	tip_vbox.add_child(tip3)


static var _scene_cache: Dictionary = {}


func preload_assets() -> void:
	AudioManagerScript.preload_sounds([
		"res://assets/voice/RPGsounds_Kenney/OGG/cloth1.ogg"
	])
	for i in [1, 2, 3, 4, 5, 8, 9, 10, 11, 12]:
		var h_id := "hero_%d" % i
		var p := "res://assets/characters/%s/%s.tscn" % [h_id, h_id]
		if ResourceLoader.exists(p) and not _scene_cache.has(h_id):
			_scene_cache[h_id] = load(p) as PackedScene


## Spawns a visually identical PlayerController clone at the caster's feet.
func _spawn_clone(caster: CharacterBody3D, vfx_parent: Node, mirror_input: bool) -> PlayerController:
	if caster == null or not is_instance_valid(caster):
		return null
	if vfx_parent == null or not is_instance_valid(vfx_parent):
		return null

	var hero_id: String = str(caster.get_meta("hero_id", "hero_1"))
	var p_scene: PackedScene = _scene_cache.get(hero_id, null)
	if p_scene == null:
		var scene_path := "res://assets/characters/%s/%s.tscn" % [hero_id, hero_id]
		if ResourceLoader.exists(scene_path):
			p_scene = load(scene_path) as PackedScene
			_scene_cache[hero_id] = p_scene
		elif _scene_cache.has("hero_1"):
			p_scene = _scene_cache["hero_1"]
		elif ResourceLoader.exists("res://assets/characters/hero_1/hero_1.tscn"):
			p_scene = load("res://assets/characters/hero_1/hero_1.tscn") as PackedScene
			_scene_cache["hero_1"] = p_scene

	if p_scene == null:
		return null
	var visual := p_scene.instantiate() as Node3D
	if visual == null:
		return null

	var clone := PlayerController.new()
	clone.name = "ClonePlayer"
	if mirror_input:
		# 中轴 = 放技能时本体的面朝方向（取镜头 yaw，与 heading 同一 yaw 空间）
		var axis_yaw: float = caster.rotation.y
		var cam_peek: Node3D = caster.get("camera")
		if cam_peek != null:
			axis_yaw = float(cam_peek.get("yaw"))
		var m := MirrorIntentSource.new()
		m.mirror_axis_yaw = axis_yaw
		clone.intent_source = m
	else:
		clone.intent_source = IdleCloneSource.new()

	# 面朝方向上的左右向（严格水平、垂直于朝向），保证是并排而非前后错位
	var side := Vector3(caster.global_basis.x.x, 0.0, caster.global_basis.x.z)
	if side.length_squared() < 0.0001:
		side = Vector3(1.0, 0.0, 0.0)
	else:
		side = side.normalized()
	# 随机各半：本体与分身谁左谁右 50%，避免一眼看出谁是新生的
	var sign := 1.0 if randf() < 0.5 else -1.0
	var origin := caster.global_position
	var half_gap := 0.5

	vfx_parent.add_child(clone)
	caster.global_position = origin + side * (half_gap * sign)
	clone.global_position = origin - side * (half_gap * sign)
	clone.rotation.y = caster.rotation.y

	clone.add_child(visual)

	# Matching capsule collider, so the clone collides and animates identically.
	var height: float = visual.get("body_height")
	if height <= 0.1:
		height = 1.75
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = minf(0.3, height * 0.2)
	capsule.height = height
	collider.shape = capsule
	collider.position.y = height * 0.5
	clone.add_child(collider)

	# Share the casters camera so heading/facing stays in lockstep with the real body.
	var cam: Node3D = caster.get("camera")
	clone.setup(visual, cam)
	return clone


func _start_clone_timer(caster_id: int, dur: float) -> void:
	if not _active_clones.has(caster_id):
		return
	var entry: Dictionary = _active_clones[caster_id]
	var clone: PlayerController = entry.get("clone")
	if clone == null or not is_instance_valid(clone):
		return

	var tw: Tween = clone.create_tween()
	tw.tween_interval(maxf(dur, 0.2))
	tw.tween_callback(func():
		_despawn_clone(caster_id)
	)


static func _despawn_clone(caster_id: int) -> void:
	if not _active_clones.has(caster_id):
		return
	var entry: Dictionary = _active_clones[caster_id]
	_active_clones.erase(caster_id)
	var clone: PlayerController = entry.get("clone")
	if clone != null and is_instance_valid(clone):
		clone.queue_free()


## Removes every active clone. Called when the lab switches play/spectate modes.
static func clear_all() -> void:
	for c_id in _active_clones.keys():
		_despawn_clone(c_id)
