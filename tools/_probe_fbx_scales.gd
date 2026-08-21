extends SceneTree

func _initialize() -> void:
	var fbx_dir := "res://assets/scene_objects/FBX/"
	var dir := DirAccess.open(fbx_dir)
	if dir != null:
		dir.list_dir_begin()
		var fn := dir.get_next()
		while fn != "":
			if fn.ends_with(".fbx"):
				var scn = load(fbx_dir + fn)
				if scn is PackedScene:
					var inst = scn.instantiate()
					_inspect_inst(fn, inst)
					inst.free()
			fn = dir.get_next()
	quit(0)

func _inspect_inst(name: String, node: Node) -> void:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(node, meshes)
	for m in meshes:
		print(name, " -> mesh: ", m.name, " aabb: ", m.mesh.get_aabb() if m.mesh else "null")

func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_collect_meshes(c, out)
