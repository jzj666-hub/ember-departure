extends SceneTree

func _initialize() -> void:
	var path := "res://assets/scene_objects/FBX/House_1.fbx"
	var scn = load(path) as PackedScene
	var inst = scn.instantiate() as Node3D
	_setup_collision(inst)
	print("Colliders created: ", inst.get_node_or_null("CollisionShape3D") != null or _has_col_shape(inst))
	quit(0)

func _setup_collision(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		node.create_trimesh_collision()
	for c in node.get_children():
		_setup_collision(c)

func _has_col_shape(node: Node) -> bool:
	if node is CollisionShape3D:
		return true
	for c in node.get_children():
		if _has_col_shape(c):
			return true
	return false
