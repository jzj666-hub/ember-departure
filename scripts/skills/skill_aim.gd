class_name SkillAim
extends Node3D
## Ground-target aim controller for skills that expose cast_at(). Extracted from the VFX lab flow:
## hold the skill key -> cursor tracks the camera aim point (clamped to cast_range) -> release casts.
## Invariant: aim_pos is only meaningful while active.

const GROUND_Y := 0.03

var aim_pos: Vector3 = Vector3.ZERO
var active := false

var _camera: Camera3D = null
var _caster: CharacterBody3D = null
var _skill: RefCounted = null
var _cursor: Node3D = null


## A skill is aimable exactly when it implements cast_at(). Add cast_at to a skill to opt it in.
static func supports_aim(skill: RefCounted) -> bool:
	return skill != null and skill.has_method("cast_at")


func setup(camera: Camera3D) -> void:
	_camera = camera


func set_camera(camera: Camera3D) -> void:
	_camera = camera


## begin(): arms the cursor for one cast. Pre: supports_aim(skill).
func begin(skill: RefCounted, caster: CharacterBody3D) -> void:
	_skill = skill
	_caster = caster
	active = true
	_build_cursor()
	update_aim()


func cancel() -> void:
	active = false
	if _cursor != null and is_instance_valid(_cursor):
		_cursor.queue_free()
	_cursor = null


## finish(): returns the locked ground position and disarms.
func finish() -> Vector3:
	var pos := aim_pos
	cancel()
	return pos


func update_aim() -> void:
	if not active or _cursor == null or not is_instance_valid(_cursor):
		return

	var from := _caster.global_position if _caster != null and is_instance_valid(_caster) else Vector3.ZERO
	var aim := _ground_point(from)

	var cast_r: float = float(_skill.get("cast_range")) if _skill != null and _skill.get("cast_range") != null else 16.0
	if cast_r > 0.0:
		var dh := Vector3(aim.x - from.x, 0.0, aim.z - from.z)
		if dh.length() > cast_r:
			dh = dh.normalized() * cast_r
			aim = Vector3(from.x + dh.x, aim.y, from.z + dh.z)

	aim_pos = aim
	_cursor.global_position = aim
	_shape_cursor(from, aim)


## Physics ray through the screen centre; falls back to the y=0 plane when it hits nothing.
func _ground_point(from: Vector3) -> Vector3:
	var fallback := from + (_caster.global_basis.z if _caster != null else Vector3.BACK) * 6.0
	fallback.y = GROUND_Y
	if _camera == null or not is_instance_valid(_camera) or not _camera.is_inside_tree():
		return fallback

	var origin := _camera.global_position
	var dir := -_camera.global_transform.basis.z

	var space := get_world_3d().direct_space_state
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 120.0)
		q.collide_with_areas = false
		if _caster != null and is_instance_valid(_caster):
			q.exclude = [_caster.get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var p: Vector3 = hit.position
			p.y += GROUND_Y
			return p

	if dir.y > -0.001:
		return fallback
	var t := -origin.y / dir.y
	if t < 0.0:
		return fallback
	var plane_hit := origin + dir * t
	plane_hit.y = GROUND_Y
	return plane_hit


## Cursor footprint mirrors what the skill will actually occupy.
func _shape_cursor(from: Vector3, aim: Vector3) -> void:
	var s_id := str(_skill.call("get_id")) if _skill != null else ""
	if s_id == "wall":
		var wall_len: float = float(_skill.get("wall_length")) if _skill.get("wall_length") != null else 6.0
		var dir := aim - from
		dir.y = 0.0
		dir = dir.normalized() if dir.length_squared() > 0.001 else Vector3(0.0, 0.0, 1.0)
		# The wall runs perpendicular to the caster→aim line.
		_cursor.scale = Vector3(wall_len, 1.0, 1.0)
		_cursor.rotation.y = atan2(dir.x, dir.z)
	else:
		var r: float = float(_skill.get("sand_radius")) if _skill != null and _skill.get("sand_radius") != null else 4.0
		_cursor.scale = Vector3(r, 1.0, r)


func _build_cursor() -> void:
	if _cursor != null and is_instance_valid(_cursor):
		_cursor.queue_free()
	_cursor = Node3D.new()
	_cursor.name = "SkillAimCursor"
	var s_id := str(_skill.call("get_id")) if _skill != null else ""
	if s_id == "wall":
		_cursor.add_child(_make_bar())
	else:
		_cursor.add_child(_make_disc())
		_cursor.add_child(_make_ring())
	add_child(_cursor)


func _make_disc() -> MeshInstance3D:
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 1.0
	dm.bottom_radius = 1.0
	dm.height = 0.04
	dm.radial_segments = 48
	disc.mesh = dm
	disc.material_override = _cursor_material(Color(0.75, 0.6, 0.25, 0.32), Color(0.85, 0.68, 0.22), 0.7)
	return disc


func _make_ring() -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 0.94
	rm.outer_radius = 1.0
	rm.rings = 40
	rm.ring_segments = 5
	ring.mesh = rm
	ring.material_override = _cursor_material(Color(0.9, 0.72, 0.3, 0.7), Color(0.85, 0.68, 0.22), 1.4)
	return ring


func _make_bar() -> MeshInstance3D:
	var bar := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 0.12, 0.12)
	bar.mesh = bm
	bar.material_override = _cursor_material(Color(1.0, 0.45, 0.08, 0.55), Color(1.0, 0.4, 0.05), 1.6)
	return bar


func _cursor_material(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = albedo
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = energy
	return mat
