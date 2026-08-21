extends SceneTree

func _initialize() -> void:
	print("--- Inspecting Grass & Terrain Nodes ---")
	var manor_scn = load("res://scenes/manor_estate.tscn") as PackedScene
	var manor = manor_scn.instantiate()
	root.add_child(manor)
	for i in 4:
		await physics_frame

	var terrain = manor.find_child("ContinuousTerrain", true, false)
	print("Terrain: ", terrain)
	if terrain != null:
		var mi = terrain.get_node_or_null("MeshInstance3D")
		if mi == null:
			for c in terrain.get_children():
				if c is MeshInstance3D:
					mi = c
		print("Terrain MeshInstance3D: ", mi)
		if mi != null:
			print("Terrain material_override: ", mi.material_override)
			print("Terrain mesh surfaces: ", mi.mesh.get_surface_count() if mi.mesh else 0)

	var grass_mm = manor.find_child("GrassMultiMesh", true, false) as MultiMeshInstance3D
	print("GrassMultiMesh node: ", grass_mm)
	if grass_mm != null:
		print("Grass MM instance_count: ", grass_mm.multimesh.instance_count if grass_mm.multimesh else 0)
		print("Grass MM visible: ", grass_mm.visible)
		print("Grass MM material_override: ", grass_mm.material_override)
		if grass_mm.multimesh and grass_mm.multimesh.instance_count > 0:
			print("Grass MM sample transform 0: ", grass_mm.multimesh.get_instance_transform(0))

	quit(0)
