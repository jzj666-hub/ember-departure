extends SceneTree

func _initialize() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = 2
	var t := Transform3D(Basis(), Vector3(12.0, 3.0, 4.0))
	mm.set_instance_transform(0, t)
	print("Direct test get_instance_transform: ", mm.get_instance_transform(0))
	print("Buffer size: ", mm.buffer.size())
	if mm.buffer.size() >= 12:
		print("Buffer floats 0..11: ", mm.buffer.slice(0, 12))
	quit(0)
