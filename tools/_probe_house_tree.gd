extends SceneTree

func _initialize() -> void:
	var scn = load("res://assets/scene_objects/FBX/House_1.fbx")
	var inst = scn.instantiate()
	_print_tree(inst, "")
	quit(0)

func _print_tree(node: Node, indent: String) -> void:
	print(indent, node.name, " [", node.get_class(), "] transform: ", (node as Node3D).transform if node is Node3D else "")
	for c in node.get_children():
		_print_tree(c, indent + "  ")
