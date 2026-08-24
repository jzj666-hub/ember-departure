extends SceneTree

func _initialize() -> void:
	_run()

func _run() -> void:
	print("--- 检查 Chair_1 和 Bench 模型 ---")
	var c_scn = load("res://assets/scene_objects/glTF/Chair_1.gltf") as PackedScene
	if c_scn != null:
		var c_inst = c_scn.instantiate() as Node3D
		print("Chair_1 children:")
		for child in c_inst.get_children():
			print("  ", child.name, " class:", child.get_class())
			if child is VisualInstance3D:
				print("   aabb:", (child as VisualInstance3D).get_aabb())

	var b_scn = load("res://assets/scene_objects/glTF/Bench.gltf") as PackedScene
	if b_scn != null:
		var b_inst = b_scn.instantiate() as Node3D
		print("Bench children:")
		for child in b_inst.get_children():
			print("  ", child.name, " class:", child.get_class())
			if child is VisualInstance3D:
				print("   aabb:", (child as VisualInstance3D).get_aabb())

	quit(0)
