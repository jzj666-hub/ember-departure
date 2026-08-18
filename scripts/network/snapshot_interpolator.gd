class_name SnapshotInterpolator
extends RefCounted
## Jitter buffer and snapshot interpolator for smoothing network remote entity transforms.

const BUFFER_MAX_SIZE := 32
const TARGET_DELAY_SECONDS := 0.080

var _buffer: Array[Dictionary] = []
var _target_body: CharacterBody3D = null
var _last_rendered_pos: Vector3 = Vector3.ZERO
var _last_rendered_yaw: float = 0.0


func setup(body: CharacterBody3D) -> void:
	_target_body = body
	_buffer.clear()
	if _target_body != null:
		_last_rendered_pos = _target_body.global_position
		_last_rendered_yaw = _target_body.rotation.y


func push_snapshot(snap: Dictionary) -> void:
	_buffer.append(snap)
	if _buffer.size() > BUFFER_MAX_SIZE:
		_buffer.pop_front()


func clear() -> void:
	_buffer.clear()


func update_interpolation(delta: float) -> void:
	if _target_body == null or _buffer.is_empty():
		return

	var now := float(Time.get_ticks_msec()) * 0.001
	var render_time := now - TARGET_DELAY_SECONDS

	if _buffer.size() == 1:
		var snap: Dictionary = _buffer[0]
		_apply_state(snap.get("pos", _target_body.global_position),
			snap.get("yaw", _target_body.rotation.y),
			snap.get("vel", Vector3.ZERO),
			snap.get("anim", ""),
			snap.get("state", 0),
			delta)
		return

	var idx0 := -1
	var idx1 := -1
	for i in range(_buffer.size() - 1, -1, -1):
		var t: float = _buffer[i].get("time", 0.0)
		if t <= render_time:
			idx0 = i
			idx1 = min(i + 1, _buffer.size() - 1)
			break

	if idx0 == -1:
		var oldest: Dictionary = _buffer[0]
		_apply_state(oldest.get("pos", _target_body.global_position),
			oldest.get("yaw", _target_body.rotation.y),
			oldest.get("vel", Vector3.ZERO),
			oldest.get("anim", ""),
			oldest.get("state", 0),
			delta)
		return

	if idx0 == idx1:
		var snap: Dictionary = _buffer[idx0]
		_apply_state(snap.get("pos", _target_body.global_position),
			snap.get("yaw", _target_body.rotation.y),
			snap.get("vel", Vector3.ZERO),
			snap.get("anim", ""),
			snap.get("state", 0),
			delta)
		return

	var s0: Dictionary = _buffer[idx0]
	var s1: Dictionary = _buffer[idx1]
	var t0: float = s0.get("time", render_time)
	var t1: float = s1.get("time", render_time + 0.033)
	var span := maxf(0.0001, t1 - t0)
	var alpha := clampf((render_time - t0) / span, 0.0, 1.0)

	var p0: Vector3 = s0.get("pos", _target_body.global_position)
	var p1: Vector3 = s1.get("pos", p0)
	var lerped_pos := p0.lerp(p1, alpha)

	var y0: float = s0.get("yaw", _target_body.rotation.y)
	var y1: float = s1.get("yaw", y0)
	var lerped_yaw := lerp_angle(y0, y1, alpha)

	var v0: Vector3 = s0.get("vel", Vector3.ZERO)
	var v1: Vector3 = s1.get("vel", v0)
	var lerped_vel := v0.lerp(v1, alpha)

	var anim_name: String = str(s1.get("anim", s0.get("anim", "")))
	var char_state: int = int(s1.get("state", s0.get("state", 0)))

	_apply_state(lerped_pos, lerped_yaw, lerped_vel, anim_name, char_state, delta)

	while _buffer.size() > 2 and _buffer[0].get("time", 0.0) < render_time - 0.5:
		_buffer.pop_front()


func _apply_state(pos: Vector3, yaw: float, vel: Vector3, anim: String, state_val: int, delta: float) -> void:
	if _target_body == null:
		return

	var current_pos := _target_body.global_position
	if current_pos.distance_to(pos) > 4.0:
		_target_body.global_position = pos
	else:
		_target_body.global_position = current_pos.lerp(pos, 1.0 - exp(-delta * 24.0))

	_target_body.rotation.y = lerp_angle(_target_body.rotation.y, yaw, 1.0 - exp(-delta * 20.0))
	_target_body.velocity = vel

	if not anim.is_empty() and _target_body.has_method("force_network_anim"):
		_target_body.force_network_anim(anim, state_val)
