extends SceneTree

func _initialize() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	mm.use_custom_data = false
	
	var floats: PackedFloat32Array = []
	# Add 1 instance at (10, 2, 5) with scale 1
	# Transform3D 12 floats: X.x, X.y, X.z, O.x, Y.x, Y.y, Y.z, O.y, Z.x, Z.y, Z.z, O.z (or Basis rows + Origin)
	var t := Transform3D(Basis(), Vector3(10.0, 2.0, 5.0))
	floats.append(t.basis.x.x)
	floats.append(t.basis.x.y)
	floats.append(t.basis.x.z)
	floats.append(t.origin.x)
	
	floats.append(t.basis.y.x)
	floats.append(t.basis.y.y)
	floats.append(t.basis.y.z)
	floats.append(t.origin.y)

	floats.append(t.basis.z.x)
	floats.append(t.basis.z.y)
	floats.append(t.basis.z.z)
	floats.append(t.origin.z)

	mm.buffer = floats
	print("Direct buffer set instance_count: ", mm.instance_count)
	print("Direct buffer get_instance_transform(0): ", mm.get_instance_transform(0))
	quit(0)
