extends SceneTree

func _initialize() -> void:
	var scn = load("res://assets/scene_objects/glTF/Grass_Common_Short.gltf") as PackedScene
	var inst = scn.instantiate()
	var mesh_node: MeshInstance3D = null
	for c in inst.get_children():
		if c is MeshInstance3D:
			mesh_node = c
	if mesh_node != null:
		var mat = mesh_node.mesh.surface_get_material(0) as StandardMaterial3D
		print("Original Grass Material: ", mat)
		if mat != null:
			print("  albedo_color: ", mat.albedo_color)
			print("  albedo_texture: ", mat.albedo_texture)
			print("  transparency: ", mat.transparency)
			print("  cull_mode: ", mat.cull_mode)
	quit(0)
