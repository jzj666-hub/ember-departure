class_name FollowCamera
extends Camera3D
## Third-person / First-person camera. Orbits/follows target.

signal mode_changed(is_first_person: bool)

## Radians per pixel of mouse movement.
@export var sensitivity := 0.0028
## Camera distance scale (multiplied by body height).
@export var distance_scale := 2.1
## Target vertical tracking point (fraction of height).
@export var aim_height := 0.78
## Eye height scale for first-person mode (fraction of height).
@export var eye_height_scale := 0.88
## Forward offset from eye position in first-person mode.
@export var first_person_forward_offset := 0.12
## Pitch the shot returns to once the character is moving. Negative looks down.
@export var travel_pitch := -0.14
## Seconds to ease the pitch back after free-looking.
@export var recentre_time := 0.35
@export var pitch_limit := 1.15
## Follow movement smoothing factor.
@export var follow_smoothing := 14.0

## Camera follow target Node3D.
var target: Node3D

## Perspective mode flag.
var is_first_person := false

## Camera yaw rotation (ground plane).
var yaw := 0.0
var pitch := -0.14

var _distance := 3.6
var _aim_height := 1.4
var _eye_height := 1.6
var _settled := Vector3.ZERO
var _has_settled := false
## Flag to swallow first mouse motion frame (prevents view yank on capture).
var _swallow_first_motion := true


func _ready() -> void:
	pitch = travel_pitch
	# Captured, not confined: the point of this camera is that the pointer never
	# leaves it. The playground releases it on Esc.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Scale camera distance and offset to target height.
func frame_for(body_height: float) -> void:
	var height := body_height if body_height > 0.1 else 1.75
	_distance = height * distance_scale
	_aim_height = height * aim_height
	_eye_height = height * eye_height_scale


## Teleport camera to target position instantly.
func snap() -> void:
	_has_settled = false
	_place(0.0)


## Toggle perspective mode between third-person and first-person.
func toggle_first_person() -> void:
	set_first_person(not is_first_person)


## Set perspective mode explicitly.
func set_first_person(enabled: bool) -> void:
	if is_first_person == enabled:
		return
	is_first_person = enabled
	_has_settled = false
	mode_changed.emit(is_first_person)


func _unhandled_input(event: InputEvent) -> void:
	# Scenes with a second camera keep the pointer captured for it too; a camera
	# nobody is looking through must not drift while that one is steered.
	if not current:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_F3:
			toggle_first_person()
			get_viewport().set_input_as_handled()
			return

	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	if _swallow_first_motion:
		_swallow_first_motion = false
		return
	yaw -= motion.relative.x * sensitivity
	pitch = clampf(pitch - motion.relative.y * sensitivity, -pitch_limit, pitch_limit)


func _process(delta: float) -> void:
	if target == null:
		return

	# Eases camera pitch to travel pitch when target is moving in third-person mode.
	if not is_first_person and target.has_method("is_moving") and target.is_moving():
		var t: float = 1.0 - exp(-delta / maxf(recentre_time, 0.001))
		pitch = lerpf(pitch, travel_pitch, t)
	_place(delta)


func _place(delta: float) -> void:
	if target == null:
		return

	var look := Vector3(
		sin(yaw) * cos(pitch),
		sin(pitch),
		cos(yaw) * cos(pitch))

	if is_first_person:
		var head_front := _get_head_front_position()
		global_position = head_front
		_settled = head_front
		look_at(head_front + look * 10.0, Vector3.UP)
	else:
		var aim: Vector3 = target.global_position + Vector3.UP * _aim_height
		if not _has_settled:
			_settled = aim
			_has_settled = true
		else:
			_settled = _settled.lerp(aim, 1.0 - exp(-delta * follow_smoothing))
		global_position = _pull_in(_settled, _settled - look * _distance)
		look_at(_settled, Vector3.UP)


## Find head front position from target skeleton or character.
func _get_head_front_position() -> Vector3:
	if target == null:
		return Vector3.ZERO
	if target.has_method("get_head_front_position"):
		var pos: Vector3 = target.call("get_head_front_position")
		if pos != Vector3.ZERO:
			return pos
	var char_node: Node3D = target.get("character") as Node3D if target.get("character") is Node3D else null
	if char_node != null and char_node.has_method("get_head_front_position"):
		var pos: Vector3 = char_node.call("get_head_front_position")
		if pos != Vector3.ZERO:
			return pos
	return target.global_position + Vector3.UP * _eye_height


## Raycast to adjust camera position and prevent geometry clipping.
func _pull_in(from: Vector3, to: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	if target != null:
		query.exclude = [target.get_rid()] if target is CollisionObject3D else []
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return to
	# Stop short of the surface so the near plane clears it.
	return (hit.position as Vector3).lerp(from, 0.12)

