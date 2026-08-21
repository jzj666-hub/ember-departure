extends SceneTree
## Inspects hero_4 sub-meshes, materials, vertex bones, UVs.

func _initialize() -> void:
	var path := "res://assets/characters/hero_4/hero_4.fbx"
	var scene: PackedScene = load(path)
	if scene == null:
		print("Failed to load scene")
		quit(1)
		return
	var root: Node = scene.instantiate()
	var skel: Skeleton3D = null
	for c in root.get_children():
		if c is Skeleton3D:
			skel = c
			break
	if skel == null:
		for c in root.find_children("*", "Skeleton3D", true, false):
			skel = c
			break

	print("Skeleton: ", skel)
	var mesh_instances: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	print("Mesh instances count: ", mesh_instances.size())

	for mi_node in mesh_instances:
		var mi: MeshInstance3D = mi_node as MeshInstance3D
		var m: Mesh = mi.mesh
		var aabb: AABB = mi.get_aabb()
		var bones_used := {}
		var uv_min := Vector2(999999, 999999)
		var uv_max := Vector2(-999999, -999999)
		if m is ArrayMesh:
			var am: ArrayMesh = m as ArrayMesh
			for s in am.get_surface_count():
				var arrays: Array = am.surface_get_arrays(s)
				var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
				var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
				if uvs.size() > 0:
					for uv in uvs:
						uv_min.x = minf(uv_min.x, uv.x)
						uv_min.y = minf(uv_min.y, uv.y)
						uv_max.x = maxf(uv_max.x, uv.x)
						uv_max.y = maxf(uv_max.y, uv.y)
				if bones.size() > 0 and skel != null:
					for bi in range(bones.size()):
						var w := weights[bi]
						if w > 0.05:
							var b_idx := bones[bi]
							if b_idx >= 0 and b_idx < skel.get_bone_count():
								var b_name := skel.get_bone_name(b_idx)
								bones_used[b_name] = bones_used.get(b_name, 0) + 1

		var sorted_bones := bones_used.keys()
		sorted_bones.sort()
		var bone_summary: Array[String] = []
		for b in sorted_bones:
			bone_summary.append("%s(%d)" % [b, bones_used[b]])

		print("Mesh: %s | AABB: pos=(%.2f, %.2f, %.2f) size=(%.2f, %.2f, %.2f)" % [
			mi.name, aabb.position.x, aabb.position.y, aabb.position.z, aabb.size.x, aabb.size.y, aabb.size.z
		])
		print("  UV range: (%.2f, %.2f) -> (%.2f, %.2f)" % [uv_min.x, uv_min.y, uv_max.x, uv_max.y])
		print("  Bones: %s" % [", ".join(bone_summary)])

	root.free()
	quit(0)
