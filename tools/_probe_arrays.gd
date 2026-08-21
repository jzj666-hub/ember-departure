extends SceneTree

func _initialize() -> void:
	var path := "res://assets/characters/hero_4/hero_4.fbx"
	var scene: PackedScene = load(path)
	var root: Node = scene.instantiate()
	var mesh_instances: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if mesh_instances.size() > 0:
		var mi: MeshInstance3D = mesh_instances[0] as MeshInstance3D
		var m: Mesh = mi.mesh
		if m is ArrayMesh:
			var am: ArrayMesh = m as ArrayMesh
			var arrays: Array = am.surface_get_arrays(0)
			for i in range(arrays.size()):
				var item = arrays[i]
				if item == null:
					print("Array[%d]: null" % i)
				elif item is PackedVector3Array:
					print("Array[%d] (Vec3Array): size=%d, [0]=%s" % [i, (item as PackedVector3Array).size(), (item as PackedVector3Array)[0]])
				elif item is PackedVector2Array:
					var p: PackedVector2Array = item as PackedVector2Array
					print("Array[%d] (Vec2Array): size=%d, [0]=%s, [1]=%s, [2]=%s" % [i, p.size(), p[0] if p.size()>0 else "", p[1] if p.size()>1 else "", p[2] if p.size()>2 else ""])
				else:
					print("Array[%d] (%s): size=%s" % [i, typeof(item), item.size() if item is Array or item is PackedInt32Array or item is PackedFloat32Array else item])
	root.free()
	quit(0)
