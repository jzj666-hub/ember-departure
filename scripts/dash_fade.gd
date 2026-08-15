class_name DashFade
extends RefCounted
## Whole-character opacity with smoothstep easing for dash dissolve/fade.

static func collect(source: Node3D) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	if source == null:
		return out
	var stack: Array[Node] = [source]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is WeaponTrail:
			continue
		var drawable := node as GeometryInstance3D
		if drawable != null:
			out.append(drawable)
		stack.append_array(node.get_children())
	return out


static func apply(meshes: Array[GeometryInstance3D], alpha: float) -> void:
	var clamped_alpha := clampf(alpha, 0.0, 1.0)
	var curved := clamped_alpha * clamped_alpha * (3.0 - 2.0 * clamped_alpha)
	var hidden := clampf(1.0 - curved, 0.0, 1.0)

	for mesh in meshes:
		if is_instance_valid(mesh):
			mesh.transparency = hidden


static func clear(meshes: Array[GeometryInstance3D]) -> void:
	apply(meshes, 1.0)


static func spawn_burst(into: Node, pos: Vector3, height: float, tint: Color = Color(0.7, 0.85, 1.0, 0.8)) -> void:
	if into == null or not into.is_inside_tree():
		return
	var p := CPUParticles3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.04, 0.04, 0.04)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = tint
	box.material = mat
	
	p.mesh = box
	p.amount = 16
	p.lifetime = 0.25
	p.one_shot = true
	p.explosiveness = 0.9
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.25, maxf(height, 0.5) * 0.45, 0.25)
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3(0, 0.5, 0)
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.2
	p.scale_amount_min = 0.03
	p.scale_amount_max = 0.1
	p.color = tint
	
	into.add_child(p)
	p.global_position = pos + Vector3.UP * (height * 0.5)
	p.emitting = true
	
	var timer := into.get_tree().create_timer(0.3)
	timer.timeout.connect(p.queue_free)


