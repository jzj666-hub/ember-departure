extends SceneTree

func _initialize() -> void:
	var path := "res://assets/characters/hero_4/hero_4.fbx"
	var scene: PackedScene = load(path)
	var root: Node = scene.instantiate()
	var mesh_instances: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	for mi_node in mesh_instances:
		var mi: MeshInstance3D = mi_node as MeshInstance3D
		var m: Mesh = mi.mesh
		if m is ArrayMesh:
			var am: ArrayMesh = m as ArrayMesh
			var arrays: Array = am.surface_get_arrays(0)
			var uv1 = arrays[Mesh.ARRAY_TEX_UV]
			if uv1 != null and uv1 is PackedVector2Array:
				var u_min := 999.0
				var u_max := -999.0
				var v_min := 999.0
				var v_max := -999.0
				for uv in uv1:
					u_min = minf(u_min, uv.x)
					u_max = maxf(u_max, uv.x)
					v_min = minf(v_min, uv.y)
					v_max = maxf(v_max, uv.y)
				print("%s: uv1 count=%d, u=[%.3f, %.3f], v=[%.3f, %.3f], sample0=%s" % [mi.name, uv1.size(), u_min, u_max, v_min, v_max, uv1[0] if uv1.size() > 0 else "none"])
			else:
				print("%s: uv1 is NULL" % mi.name)
	root.free()
	quit(0)
