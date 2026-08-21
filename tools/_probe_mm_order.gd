extends SceneTree

func _initialize() -> void:
	var scn = load("res://assets/scene_objects/glTF/Grass_Common_Short.gltf") as PackedScene
	var inst = scn.instantiate()
	var mesh_node: MeshInstance3D = null
	for c in inst.get_children():
		if c is MeshInstance3D:
			mesh_node = c
			break
	var grass_mesh: Mesh = mesh_node.mesh

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = grass_mesh
	mm.instance_count = 5

	for i in range(5):
		var t := Transform3D(Basis(), Vector3(10.0 + i, 2.0, 5.0))
		mm.set_instance_transform(i, t)

	print("Sample transform 0 after proper order: ", mm.get_instance_transform(0))
	quit(0)
