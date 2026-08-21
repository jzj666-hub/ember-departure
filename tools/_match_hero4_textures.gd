extends SceneTree
## Dumps mesh details and UVs to a JSON for matching textures.

func _initialize() -> void:
	var path := "res://assets/characters/hero_4/hero_4.fbx"
	var scene: PackedScene = load(path)
	var root: Node = scene.instantiate()
	var mesh_instances: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	var result := {}

	for mi_node in mesh_instances:
		var mi: MeshInstance3D = mi_node as MeshInstance3D
		var m: Mesh = mi.mesh
		var aabb: AABB = mi.get_aabb()
		var mesh_info := {
			"name": mi.name,
			"aabb_pos": [aabb.position.x, aabb.position.y, aabb.position.z],
			"aabb_size": [aabb.size.x, aabb.size.y, aabb.size.z],
			"uvs": []
		}
		if m is ArrayMesh:
			var am: ArrayMesh = m as ArrayMesh
			for s in am.get_surface_count():
				var arrays: Array = am.surface_get_arrays(s)
				var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
				var uv_list := []
				for uv in uvs:
					uv_list.append([uv.x, uv.y])
				mesh_info["uvs"] = uv_list
		result[mi.name] = mesh_info

	var f := FileAccess.open("res://scratch/hero4_uvs.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(result))
		f.close()
		print("Successfully wrote scratch/hero4_uvs.json")
	root.free()
	quit(0)
