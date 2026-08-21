extends SceneTree

func _initialize() -> void:
	var scn = load("res://assets/scene_objects/glTF/Grass_Common_Short.gltf") as PackedScene
	if scn != null:
		var inst = scn.instantiate()
		print("Grass inst: ", inst)
		var mesh_inst = inst.find_child("*", true, false)
		if mesh_inst is MeshInstance3D:
			print("Grass mesh: ", mesh_inst.mesh, " aabb: ", mesh_inst.mesh.get_aabb())
			print("Grass mat: ", mesh_inst.mesh.surface_get_material(0))
	quit(0)
