extends SceneTree

func _initialize() -> void:
	print("--- Testing FBX & glTF Loading ---")
	var house_path := "res://assets/scene_objects/FBX/House_1.fbx"
	if ResourceLoader.exists(house_path):
		var house_res = load(house_path)
		print("House_1 loaded: ", house_res)
		if house_res is PackedScene:
			var inst = house_res.instantiate()
			print("House_1 instance class: ", inst.get_class(), " children: ", inst.get_child_count())
			_dump_node(inst, "  ")
	
	var tree_path := "res://assets/scene_objects/glTF/CommonTree_1.gltf"
	if ResourceLoader.exists(tree_path):
		var tree_res = load(tree_path)
		print("CommonTree_1 loaded: ", tree_res)
		if tree_res is PackedScene:
			var inst = tree_res.instantiate()
			print("CommonTree_1 instance class: ", inst.get_class(), " children: ", inst.get_child_count())
			_dump_node(inst, "  ")

	var stall_path := "res://assets/scene_objects/glTF/Stall_Empty.gltf"
	if ResourceLoader.exists(stall_path):
		var stall_res = load(stall_path)
		print("Stall_Empty loaded: ", stall_res)
		if stall_res is PackedScene:
			var inst = stall_res.instantiate()
			_dump_node(inst, "  ")

	quit(0)

func _dump_node(node: Node, indent: String) -> void:
	print(indent, node.name, " (", node.get_class(), ")")
	if node is MeshInstance3D and node.mesh != null:
		print(indent, "  Mesh AABB: ", node.mesh.get_aabb())
	for child in node.get_children():
		_dump_node(child, indent + "  ")
