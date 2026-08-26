extends "res://scripts/skills/skill_base.gd"
## Grapple: forward thick hook. Extend → latch → retract+pull. Hit = model capsule vs hook width.

const AudioManagerScript = preload("res://scripts/audio_manager.gd")

## Max forward reach (m).
var hook_distance: float = 10.0
## Extend & retract speed (m/s).
var hook_speed: float = 22.0
## Grab volume full width (m). Hit if corridor radius = width/2 + body_r.
var hook_width: float = 2.4
## Horizontal capture cap: max off-axis angle (deg) a target may sit from forward.
var hook_angle: float = 45.0

## Stand-off when pulled beside caster (m along facing).
const PULL_STANDOFF: float = 1.2
## Fallback body radius / half-height when no CapsuleShape3D.
const DEFAULT_BODY_RADIUS: float = 0.45
const DEFAULT_BODY_HALF_H: float = 0.9
## Hook flight height above feet (m).
const HOOK_HEIGHT: float = 1.0
## Brief latch pause before retract (s).
const LATCH_HOLD: float = 0.08

## active sessions: caster_id -> {tween, ...}
static var _active_casts: Dictionary = {}
## active pulls: target_id -> {tween, ...}
static var _active_pulls: Dictionary = {}

func get_id() -> String:
	return "grapple"

func get_name() -> String:
	return "🪝 钩锁 (正前方牵引)"

func get_title() -> String:
	return "🪝 钩锁配置 (GRAPPLE HOOK)"

func get_params() -> Dictionary:
	return {
		"hook_distance": hook_distance,
		"hook_speed": hook_speed,
		"hook_width": hook_width,
		"hook_angle": hook_angle
	}

func set_param(key: String, value: Variant) -> void:
	match key:
		"hook_distance": hook_distance = float(value)
		"hook_speed": hook_speed = float(value)
		"hook_width": hook_width = float(value)
		"hook_angle": hook_angle = float(value)

func cast(caster: CharacterBody3D, _intent_dir: Vector3, vfx_parent: Node, _is_spectator: bool = false) -> Dictionary:
	if caster == null or not is_instance_valid(caster):
		return {}
	if vfx_parent == null or not is_instance_valid(vfx_parent):
		return {}

	# Facing only. Pre: forward = +global_basis.z.
	var dir := caster.global_basis.z
	dir.y = 0.0
	if dir.length_squared() < 0.001:
		dir = Vector3(0.0, 0.0, 1.0)
	else:
		dir = dir.normalized()

	var hand := caster.global_position + Vector3.UP * HOOK_HEIGHT
	var hit := _find_forward_hit(caster, dir, hook_distance, hook_width, hook_angle)
	var target: CharacterBody3D = hit.get("target") as CharacterBody3D
	var latch_world: Vector3 = hit.get("latch_pos", hand + dir * hook_distance) as Vector3

	var spd := maxf(hook_speed, 0.1)
	var extend_dur := maxf(hand.distance_to(latch_world) / spd, 0.06)
	var retract_dur := extend_dur
	if target != null:
		var pull_end := caster.global_position + dir * PULL_STANDOFF
		pull_end.y = target.global_position.y
		retract_dur = maxf(target.global_position.distance_to(pull_end) / spd, 0.08)

	_cancel_caster_cast(caster)
	_play_hook_sequence(caster, target, dir, hand, latch_world, extend_dur, retract_dur, vfx_parent)

	AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/knifeSlice.ogg", 1.5)

	var total_hold := extend_dur + LATCH_HOLD + retract_dur + 0.35
	return {
		"success": true,
		"hit": target != null,
		"skill_id": get_id(),
		"from_pos": caster.global_position,
		"latch_pos": latch_world,
		"direction": dir,
		"target_actor": target,
		"hook_distance": hook_distance,
		"hook_speed": hook_speed,
		"hook_width": hook_width,
		"extend_duration": extend_dur,
		"retract_duration": retract_dur,
		"pull_duration": total_hold
	}

func replay(caster: CharacterBody3D, record: Dictionary, vfx_parent: Node) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	cast(caster, Vector3.ZERO, vfx_parent, true)

func get_replay_hold_time(record: Dictionary) -> float:
	var dur: float = float(record.get("pull_duration", 1.2))
	return maxf(dur, 1.5)

func build_config_panel(container: VBoxContainer, on_changed: Callable) -> void:
	var dist_lbl := Label.new()
	dist_lbl.text = "钩锁距离 (Distance): %.1fm" % hook_distance
	dist_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(dist_lbl)

	var dist_slider := HSlider.new()
	dist_slider.min_value = 3.0
	dist_slider.max_value = 25.0
	dist_slider.step = 0.5
	dist_slider.value = hook_distance
	dist_slider.value_changed.connect(func(v: float):
		hook_distance = v
		dist_lbl.text = "钩锁距离 (Distance): %.1fm" % v
		on_changed.call("hook_distance", v)
	)
	container.add_child(dist_slider)

	var spd_lbl := Label.new()
	spd_lbl.text = "钩锁速度 (Speed): %.1f m/s" % hook_speed
	spd_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(spd_lbl)

	var spd_slider := HSlider.new()
	spd_slider.min_value = 4.0
	spd_slider.max_value = 40.0
	spd_slider.step = 1.0
	spd_slider.value = hook_speed
	spd_slider.value_changed.connect(func(v: float):
		hook_speed = v
		spd_lbl.text = "钩锁速度 (Speed): %.1f m/s" % v
		on_changed.call("hook_speed", v)
	)
	container.add_child(spd_slider)

	var width_lbl := Label.new()
	width_lbl.text = "勾宽 (Hook Width): %.1fm" % hook_width
	width_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(width_lbl)

	var width_slider := HSlider.new()
	width_slider.min_value = 0.8
	width_slider.max_value = 5.0
	width_slider.step = 0.1
	width_slider.value = hook_width
	width_slider.value_changed.connect(func(v: float):
		hook_width = v
		width_lbl.text = "勾宽 (Hook Width): %.1fm" % v
		on_changed.call("hook_width", v)
	)
	container.add_child(width_slider)

	var angle_lbl := Label.new()
	angle_lbl.text = "勾角 (Hook Angle): %.0f°" % hook_angle
	angle_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(angle_lbl)

	var angle_slider := HSlider.new()
	angle_slider.min_value = 5.0
	angle_slider.max_value = 90.0
	angle_slider.step = 1.0
	angle_slider.value = hook_angle
	angle_slider.value_changed.connect(func(v: float):
		hook_angle = v
		angle_lbl.text = "勾角 (Hook Angle): %.0f°" % v
		on_changed.call("hook_angle", v)
	)
	container.add_child(angle_slider)

	var tip_panel := PanelContainer.new()
	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.12, 0.08, 0.02, 0.85)
	t_style.set_corner_radius_all(6)
	t_style.set_border_width_all(1)
	t_style.border_color = Color(1.0, 0.7, 0.2, 0.55)
	t_style.set_content_margin_all(8)
	tip_panel.add_theme_stylebox_override("panel", t_style)
	container.add_child(tip_panel)

	var tip_vbox := VBoxContainer.new()
	tip_vbox.add_theme_constant_override("separation", 4)
	tip_panel.add_child(tip_vbox)

	var tip1 := Label.new()
	tip1.text = "➡️ 仅正前方直线射出；勾宽内且水平夹角≤勾角即命中"
	tip1.add_theme_font_size_override("font_size", 11)
	tip1.modulate = Color(1.0, 0.85, 0.35)
	tip_vbox.add_child(tip1)

	var tip2 := Label.new()
	tip2.text = "🪝 流程：朝正前方直线放出 → 碰到目标即勾 → 收回并吸至身旁"
	tip2.add_theme_font_size_override("font_size", 11)
	tip2.modulate = Color(1.0, 0.55, 0.25)
	tip_vbox.add_child(tip2)

## Nearest body whose capsule lies within the forward hook corridor (width) and
## within the horizontal off-axis cap (angle_deg). Returns {target, along, latch_pos}.
func _find_forward_hit(caster: CharacterBody3D, forward: Vector3, max_dist: float, width: float, angle_deg: float) -> Dictionary:
	var empty := {"target": null, "along": max_dist, "latch_pos": caster.global_position + Vector3.UP * HOOK_HEIGHT + forward * max_dist}
	if caster == null or not caster.is_inside_tree():
		return empty
	var tree := caster.get_tree()
	if tree == null:
		return empty

	var origin := caster.global_position
	var hook_origin := origin + Vector3.UP * HOOK_HEIGHT
	var half_w := width * 0.5
	var angle_rad := deg_to_rad(maxf(angle_deg, 0.0))
	var best: CharacterBody3D = null
	var best_along := max_dist + 1.0
	var best_latch: Vector3 = empty["latch_pos"] as Vector3

	var bodies := tree.root.find_children("", "CharacterBody3D", true, false)
	for b in bodies:
		if b == caster or not (b is CharacterBody3D):
			continue
		var cb := b as CharacterBody3D
		if cb.name == "Ground":
			continue

		var body := _get_body_capsule(cb)
		var body_r: float = body.radius
		var body_c: Vector3 = body.center
		var body_hh: float = body.half_height

		var to_c := body_c - hook_origin
		var along := to_c.dot(forward)
		# Horizontal off-axis gate: target centre must stay inside the capture cone.
		var to_h := Vector2(to_c.x, to_c.z)
		var horiz_ang := 0.0 if to_h.length_squared() < 0.0001 else absf(Vector2(forward.x, forward.z).angle_to(to_h))
		if horiz_ang > angle_rad:
			continue
		# Capsule can stick into near end / far end of hook segment.
		var along_clamped := clampf(along, 0.0, max_dist)
		var closest_on_axis := hook_origin + forward * along_clamped
		var sep := body_c - closest_on_axis
		# Vertical allowance: capsule half-height; horizontal uses radius.
		var sep_h := Vector3(sep.x, 0.0, sep.z)
		var sep_v := absf(sep.y)
		var hit_r := half_w + body_r
		if sep_h.length() > hit_r:
			continue
		if sep_v > body_hh + 0.35:
			continue
		# Require some forward reach into the body (not behind caster).
		if along + body_r < 0.25:
			continue
		if along_clamped < best_along:
			best_along = along_clamped
			best = cb
			# Latch on the forward line where the hook head reaches the body,
			# not aimed at the target's chest.
			best_latch = hook_origin + forward * along_clamped

	if best == null:
		return empty
	return {"target": best, "along": best_along, "latch_pos": best_latch}

## Reads CapsuleShape3D if present. Post: {radius, half_height, center}.
static func _get_body_capsule(body: CharacterBody3D) -> Dictionary:
	var radius := DEFAULT_BODY_RADIUS
	var half_h := DEFAULT_BODY_HALF_H
	var center := body.global_position + Vector3.UP * half_h
	for child in body.get_children():
		if child is CollisionShape3D:
			var cs := child as CollisionShape3D
			if cs.shape is CapsuleShape3D:
				var cap := cs.shape as CapsuleShape3D
				radius = maxf(cap.radius, 0.2)
				# CapsuleShape3D.height is total cylinder+hemispheres length.
				half_h = maxf(cap.height * 0.5, radius)
				center = cs.global_position
				break
	return {"radius": radius, "half_height": half_h, "center": center}

## Visual + logic: tip extends, latch, then retract (pull if latched).
static func _play_hook_sequence(
	caster: CharacterBody3D,
	target: CharacterBody3D,
	dir: Vector3,
	hand: Vector3,
	latch_pos: Vector3,
	extend_dur: float,
	retract_dur: float,
	parent: Node
) -> void:
	var root := Node3D.new()
	root.name = "GrappleHookFX"
	parent.add_child(root)

	# Chain (grows with tip)
	var chain_mesh := CylinderMesh.new()
	chain_mesh.top_radius = 0.028
	chain_mesh.bottom_radius = 0.028
	chain_mesh.height = 0.05
	chain_mesh.radial_segments = 8
	var chain := MeshInstance3D.new()
	chain.name = "GrappleChain"
	chain.mesh = chain_mesh
	var chain_mat := StandardMaterial3D.new()
	chain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	chain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	chain_mat.albedo_color = Color(0.55, 0.42, 0.28, 0.95)
	# Energy-tether look until a real chain-link sheet exists. Null texture keeps the flat cord.
	chain_mat.albedo_texture = VfxTextures.get_tex(VfxTextures.LIGHTNING)
	chain_mat.uv1_scale = Vector3(1.0, 4.0, 1.0)
	chain.material_override = chain_mat
	root.add_child(chain)

	# Hook tip (claw-like: sphere + two prongs) - 暗铁玄钢质感，与黑铁索链统一
	var tip := Node3D.new()
	tip.name = "GrappleTip"
	root.add_child(tip)
	tip.global_position = hand

	var tip_core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.09
	core_mesh.height = 0.18
	tip_core.mesh = core_mesh
	var tip_mat := StandardMaterial3D.new()
	tip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tip_mat.albedo_color = Color(0.28, 0.30, 0.34, 1.0)
	tip_mat.emission_enabled = true
	tip_mat.emission = Color(0.45, 0.48, 0.55)
	tip_mat.emission_energy_multiplier = 0.8
	tip_core.material_override = tip_mat
	tip.add_child(tip_core)

	for side in [-1.0, 1.0]:
		var prong := MeshInstance3D.new()
		var p_mesh := BoxMesh.new()
		p_mesh.size = Vector3(0.04, 0.04, 0.18)
		prong.mesh = p_mesh
		prong.position = Vector3(side * 0.07, 0.0, 0.12)
		prong.rotation.y = side * 0.45
		var p_mat := StandardMaterial3D.new()
		p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		p_mat.albedo_color = Color(0.42, 0.45, 0.52, 1.0)
		p_mat.emission_enabled = true
		p_mat.emission = Color(0.6, 0.65, 0.75)
		p_mat.emission_energy_multiplier = 1.0
		prong.material_override = p_mat
		tip.add_child(prong)

	_update_chain(chain, chain_mesh, hand, hand)

	var c_id := caster.get_instance_id()
	var tw := root.create_tween()
	_active_casts[c_id] = {"root": root, "tween": tw, "caster": caster}

	# 1) Extend tip to latch / max range
	tw.tween_method(func(t: float):
		if not is_instance_valid(tip) or not is_instance_valid(caster):
			return
		var hand_now := caster.global_position + Vector3.UP * HOOK_HEIGHT
		var tip_pos := hand_now.lerp(latch_pos, t)
		tip.global_position = tip_pos
		_face_tip(tip, dir)
		_update_chain(chain, chain_mesh, hand_now, tip_pos)
	, 0.0, 1.0, extend_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 2) Latch flash
	tw.tween_callback(func():
		if target != null and is_instance_valid(target):
			_spawn_latch_flash(latch_pos, parent)
			AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg", 1.2)
	)
	tw.tween_interval(LATCH_HOLD)

	# 3) Retract: empty return OR pull target while chain shortens
	tw.tween_callback(func():
		if target != null and is_instance_valid(target) and is_instance_valid(caster):
			_begin_pull(caster, target, retract_dur)
	)

	tw.tween_method(func(t: float):
		if not is_instance_valid(tip) or not is_instance_valid(caster):
			return
		var hand_now := caster.global_position + Vector3.UP * HOOK_HEIGHT
		var tip_pos: Vector3
		if target != null and is_instance_valid(target):
			# Tip sticks on target chest while being reeled in.
			tip_pos = target.global_position + Vector3.UP * HOOK_HEIGHT
		else:
			tip_pos = latch_pos.lerp(hand_now, t)
		tip.global_position = tip_pos
		_face_tip(tip, (tip_pos - hand_now).normalized() if tip_pos.distance_squared_to(hand_now) > 0.01 else dir)
		_update_chain(chain, chain_mesh, hand_now, tip_pos)
	, 0.0, 1.0, retract_dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	tw.chain().tween_callback(func():
		_active_casts.erase(c_id)
		if is_instance_valid(root):
			root.queue_free()
	)

static func _begin_pull(caster: CharacterBody3D, target: CharacterBody3D, duration: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var t_id := target.get_instance_id()
	if _active_pulls.has(t_id):
		var prev: Tween = _active_pulls[t_id].get("tween")
		if prev != null and prev.is_valid():
			prev.kill()

	var start_pos := target.global_position
	target.velocity = Vector3.ZERO
	var tw := target.create_tween()
	_active_pulls[t_id] = {"target": target, "tween": tw, "caster": caster}

	tw.tween_method(func(t: float):
		if not is_instance_valid(target):
			return
		var end_pos := start_pos
		if is_instance_valid(caster):
			var f := caster.global_basis.z
			f.y = 0.0
			if f.length_squared() > 0.001:
				f = f.normalized()
			end_pos = caster.global_position + f * PULL_STANDOFF
			end_pos.y = start_pos.y
		target.global_position = start_pos.lerp(end_pos, t)
		target.velocity = Vector3.ZERO
	, 0.0, 1.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	tw.chain().tween_callback(func():
		_release_pull(target)
	)

static func _release_pull(target: CharacterBody3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	var t_id := target.get_instance_id()
	_active_pulls.erase(t_id)
	if is_instance_valid(target):
		target.velocity = Vector3.ZERO

static func _cancel_caster_cast(caster: CharacterBody3D) -> void:
	if caster == null:
		return
	var c_id := caster.get_instance_id()
	if not _active_casts.has(c_id):
		return
	var entry: Dictionary = _active_casts[c_id]
	var tw: Tween = entry.get("tween")
	if tw != null and tw.is_valid():
		tw.kill()
	var root: Node = entry.get("root")
	if root != null and is_instance_valid(root):
		root.queue_free()
	_active_casts.erase(c_id)

static func _update_chain(chain: MeshInstance3D, mesh: CylinderMesh, a: Vector3, b: Vector3) -> void:
	if chain == null or not is_instance_valid(chain):
		return
	var d := a.distance_to(b)
	if d < 0.04:
		chain.visible = false
		return
	chain.visible = true
	mesh.height = d
	# The cylinder stretches, so the sheet must retile with it or the links smear.
	var cm := chain.material_override as StandardMaterial3D
	if cm != null and cm.albedo_texture != null:
		cm.uv1_scale = Vector3(1.0, maxf(1.0, d * 2.0), 1.0)
	var link_dir := (b - a).normalized()
	_align_cylinder(chain, link_dir)
	chain.global_position = (a + b) * 0.5

static func _face_tip(tip: Node3D, dir: Vector3) -> void:
	if tip == null or not is_instance_valid(tip):
		return
	var f := dir
	f.y = 0.0
	if f.length_squared() < 0.001:
		return
	f = f.normalized()
	tip.rotation.y = atan2(f.x, f.z)

static func _spawn_latch_flash(pos: Vector3, parent: Node) -> void:
	var flash := MeshInstance3D.new()
	flash.name = "GrappleLatchFlash"
	var q := SphereMesh.new()
	q.radius = 0.22
	q.height = 0.44
	flash.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.85, 0.92, 1.0, 0.9)
	mat.albedo_texture = VfxTextures.get_tex(VfxTextures.FLASH_GLOW)
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.85, 1.0)
	mat.emission_energy_multiplier = 2.0
	flash.material_override = mat
	parent.add_child(flash)
	flash.global_position = pos
	flash.scale = Vector3(0.4, 0.4, 0.4)
	var tw := flash.create_tween()
	tw.set_parallel(true)
	tw.tween_property(flash, "scale", Vector3(1.6, 1.6, 1.6), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.14)
	tw.chain().tween_callback(flash.queue_free)

static func _align_cylinder(node: Node3D, forward_dir: Vector3) -> void:
	var forward := forward_dir.normalized()
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	var temp_up := Vector3.UP if absf(forward.y) < 0.99 else Vector3.FORWARD
	var right := forward.cross(temp_up).normalized()
	var normal := right.cross(forward).normalized()
	node.global_transform.basis = Basis(right, forward, normal)

static func is_being_pulled(target: CharacterBody3D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return _active_pulls.has(target.get_instance_id())


## reset_state(): drops in-flight cast and pull bookkeeping. Scene entry only.
func reset_state() -> void:
	_active_casts.clear()
	_active_pulls.clear()


func preload_assets() -> void:
	AudioManagerScript.preload_sounds([
		"res://assets/voice/RPGsounds_Kenney/OGG/knifeSlice.ogg",
		"res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg"
	])


func dispel_actor(actor: CharacterBody3D) -> void:
	if actor != null and is_instance_valid(actor):
		_release_pull(actor)
