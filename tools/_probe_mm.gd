extends SceneTree

func _initialize() -> void:
	var scn = load("res://assets/scene_objects/glTF/Grass_Common_Short.gltf") as PackedScene
	var inst = scn.instantiate()
	var mesh_node = inst.find_child("*", true, false) as MeshInstance3D
	var grass_mesh: Mesh = mesh_node.mesh

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = 100
	mm.mesh = grass_mesh

	for i in range(100):
		var t := Transform3D(Basis(), Vector3(i, 0, 0))
		mm.set_instance_transform(i, t)

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	root.add_child(mmi)
	print("MultiMesh created successfully: count=", mm.instance_count)
	quit(0)
