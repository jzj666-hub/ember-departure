class_name HandheldItem
extends Node3D
## Node representing an item instantiated on a bone attachment socket.
## Uses a Pivot child node to handle automatic model origin anchoring/offset corrections.

var data: ItemData
## The model instance, exactly as the importer built it.
var mesh_instance: Node3D

var _pivot: Node3D
## Local anchor transform (model space to item space).
var _anchor := Transform3D.IDENTITY
## Model-space bounds of the whole mesh, measured once in initialize().
var _box := AABB()
## Measured model length in meters.
var _length := 0.0
## Blade anchors the trail samples from, [near, far], parented to _pivot so grip,
## item_scale and flip reach them for free. Invariant: size 0 or 2.
var _trail_anchors: Array[Node3D] = []
## Where those two sit, as fractions of the blade's length.
var _trail_t := [0.0, 1.0]


func initialize(item_data: ItemData) -> void:
	data = item_data
	if data.mesh_scene == null:
		return

	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)

	mesh_instance = data.mesh_scene.instantiate() as Node3D
	_pivot.add_child(mesh_instance)

	_box = combined_aabb(mesh_instance)
	_length = _box.size[_long_axis(_box)]
	_anchor = _anchor_transform(_box, data.flip_grip) if data.auto_anchor \
		else Transform3D.IDENTITY
	_apply()


## Returns the unscaled model length.
func measured_length() -> float:
	return _length


func set_grip(t: Transform3D) -> void:
	data.grip_transform = t
	transform = t


func set_item_scale(s: float) -> void:
	data.item_scale = maxf(s, 0.0001)
	_apply()


func set_flip(flip: bool) -> void:
	if flip == data.flip_grip:
		return
	data.flip_grip = flip
	if data.auto_anchor and mesh_instance != null:
		_anchor = _anchor_transform(_box, flip)
	_apply()


## Places the two blade anchors, as fractions of the blade's length.
## Pre: initialize() has run. Post: trail_anchor(0) is the near end,
## trail_anchor(1) the far one, both following grip / item_scale / flip.
func set_trail_anchors(near_t: float, far_t: float) -> void:
	if _pivot == null:
		return
	_trail_t = [clampf(near_t, 0.0, 1.0), clampf(far_t, 0.0, 1.0)]
	while _trail_anchors.size() < _trail_t.size():
		var node := Node3D.new()
		node.name = "TrailAnchor%d" % _trail_anchors.size()
		_pivot.add_child(node)
		_trail_anchors.append(node)
	_place_trail_anchors()


## The near (0) or far (1) blade anchor, or null before set_trail_anchors().
func trail_anchor(index: int) -> Node3D:
	if index < 0 or index >= _trail_anchors.size():
		return null
	return _trail_anchors[index]


func blade_base_global() -> Vector3:
	var anchor := trail_anchor(0)
	if anchor != null:
		return anchor.global_position
	return global_position


func blade_tip_global() -> Vector3:
	var anchor := trail_anchor(1)
	if anchor != null:
		return anchor.global_position
	return global_position + global_transform.basis.y * maxf(_length, 0.5)


func _place_trail_anchors() -> void:
	if _trail_anchors.is_empty() or mesh_instance == null:
		return
	for i in _trail_anchors.size():
		_trail_anchors[i].position = _anchor_point(float(_trail_t[i]))


## Pivot-local position of the point `t` of the way along the blade.
##
## Measured in anchored space and mapped back, so t == 0 is the end _anchor
## planted at the origin - the grip - and t == 1 is the tip, flip included. With
## auto_anchor off _anchor is identity and t just runs along the model's own long
## axis, whichever end is which.
func _anchor_point(t: float) -> Vector3:
	var placed := _anchor * _box
	var axis := _long_axis(placed)
	var point := placed.position + placed.size * 0.5
	point[axis] = lerpf(placed.position[axis], placed.end[axis], clampf(t, 0.0, 1.0))
	return _anchor.affine_inverse() * point


func _apply() -> void:
	transform = data.grip_transform
	if _pivot != null:
		_pivot.transform = _anchor.scaled(Vector3.ONE * data.item_scale)
	# After the pivot, not before: an anchor is placed in pivot-local space, and
	# _anchor may have just been rebuilt by a flip.
	_place_trail_anchors()


## Calculates anchor transform to align the longest bounding box axis to +Y.
static func _anchor_transform(box: AABB, flip: bool) -> Transform3D:
	if box.size == Vector3.ZERO:
		return Transform3D.IDENTITY
	var aligned := _upright(_long_axis(box))
	if flip:
		# Half a turn about X sends +Y to -Y, so the other end of the long axis
		# becomes the one that gets planted at the origin below.
		aligned = Basis(Vector3.RIGHT, PI) * aligned
	var placed := Transform3D(aligned, Vector3.ZERO) * box
	return Transform3D(aligned, -Vector3(
		placed.position.x + placed.size.x * 0.5,
		placed.position.y,
		placed.position.z + placed.size.z * 0.5))


## Calculates alignment basis for the given axis.
static func _upright(axis: int) -> Basis:
	match axis:
		0:
			return Basis(Vector3(0, 1, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1))
		2:
			return Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
	return Basis.IDENTITY


static func _long_axis(box: AABB) -> int:
	var axis := 0
	for i in 3:
		if box.size[i] > box.size[axis]:
			axis = i
	return axis


## Combines AABBs of all meshes under the node.
static func combined_aabb(node: Node, xform := Transform3D.IDENTITY, depth := 0) -> AABB:
	var here := xform
	var spatial := node as Node3D
	if spatial != null and depth > 0:
		here = xform * spatial.transform
	var out := AABB()
	var found := false
	var mesh := node as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		out = here * mesh.mesh.get_aabb()
		found = true
	for child in node.get_children():
		var sub := combined_aabb(child, here, depth + 1)
		if sub.size == Vector3.ZERO:
			continue
		out = out.merge(sub) if found else sub
		found = true
	return out
