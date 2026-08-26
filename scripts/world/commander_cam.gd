class_name CommanderCam
extends RefCounted
## Free-fly spectator ("commander") camera shared by chase_mode / chase_game / chase_multiplayer.
## All static: state (velocity, aim) stays on the calling scene, this only computes and builds.

const FollowCameraScript = preload("res://scripts/follow_camera.gd")

const FLY_DAMP := 12.0
const SPRINT_MULT := 2.5
const AIM_REACH := 60.0
## Nudge the hit point back along the normal so floor() lands inside the struck cell.
const CELL_EPSILON := 0.01


## build_follow(root): third-person chase camera, current by default.
static func build_follow(root: Node) -> FollowCamera:
	var cam: FollowCamera = FollowCameraScript.new()
	cam.fov = 55.0
	cam.near = 0.1
	cam.far = 400.0
	cam.current = true
	root.add_child(cam)
	return cam


## build_commander(root): free-fly camera, starts inactive.
static func build_commander(root: Node) -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.near = 0.15
	cam.far = 400.0
	cam.current = false
	root.add_child(cam)
	return cam


## drive(cam, velocity, fly_speed, delta): WASD + Space/Ctrl fly, Shift sprints.
## Pre: cam may be null (returns velocity unchanged). Post: returns the new velocity;
## caller must store it. cam.global_position is advanced in place.
static func drive(cam: Camera3D, velocity: Vector3, fly_speed: float, delta: float) -> Vector3:
	if cam == null:
		return velocity
	var wish := Vector3.ZERO
	var cam_basis := cam.global_basis
	if Input.is_physical_key_pressed(KEY_W):
		wish -= cam_basis.z
	if Input.is_physical_key_pressed(KEY_S):
		wish += cam_basis.z
	if Input.is_physical_key_pressed(KEY_A):
		wish -= cam_basis.x
	if Input.is_physical_key_pressed(KEY_D):
		wish += cam_basis.x
	if Input.is_physical_key_pressed(KEY_SPACE):
		wish += Vector3.UP
	if Input.is_physical_key_pressed(KEY_CTRL):
		wish -= Vector3.UP
	if wish != Vector3.ZERO:
		var pace: float = fly_speed * (SPRINT_MULT if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		wish = wish.normalized() * pace
	var out := velocity.lerp(wish, 1.0 - exp(-delta * FLY_DAMP))
	cam.global_position += out * delta
	return out


## cast_crosshair(cam, world, highlight): centre-screen ray against the world.
## Pre: cam null / not current -> miss. Post: returns {has_aim, point, cell};
## `highlight` (nullable) is moved onto the hit cell and shown, or hidden on a miss.
static func cast_crosshair(cam: Camera3D, world: World3D, highlight: Node3D) -> Dictionary:
	var miss := {"has_aim": false, "point": Vector3.ZERO, "cell": Vector3i.ZERO}
	if cam == null or not cam.current or world == null:
		if highlight != null:
			highlight.visible = false
		return miss

	var query := PhysicsRayQueryParameters3D.create(
		cam.global_position, cam.global_position + (-cam.global_basis.z) * AIM_REACH)
	query.collide_with_areas = false
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		if highlight != null:
			highlight.visible = false
		return miss

	var hit_pos: Vector3 = hit.position
	var inward: Vector3 = hit_pos - (hit.normal as Vector3) * CELL_EPSILON
	var cell := Vector3i(int(floor(inward.x)), int(floor(inward.y)), int(floor(inward.z)))
	if highlight != null:
		highlight.global_position = Vector3(cell)
		highlight.visible = true
	return {"has_aim": true, "point": hit_pos, "cell": cell}
