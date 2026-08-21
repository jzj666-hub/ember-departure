class_name CyberGhostEffect
extends Node3D
## Cyberpunk hologram afterimage spawner.
## Clones character visual snapshot, executes glitch jitter and digital fragmentation dissolve.

const SHADER_RES := preload("res://shaders/cyber_ghost.gdshader")

@export var lifetime: float = 0.45
@export var neon_color: Color = Color(0.0, 0.94, 1.0, 0.85)
@export var secondary_color: Color = Color(1.0, 0.05, 0.55, 0.9)
@export var glitch_intensity: float = 0.45

var _mat_instances: Array[ShaderMaterial] = []
var _base_pos: Vector3


static func spawn_at_character(source_node: Node3D, parent_tree: Node, duration: float = 0.45, tint: Color = Color(0.0, 0.94, 1.0, 0.85), glitch: float = 0.45) -> CyberGhostEffect:
	if source_node == null or not is_instance_valid(source_node) or parent_tree == null or not is_instance_valid(parent_tree):
		return null
	var effect := CyberGhostEffect.new()
	effect.lifetime = duration
	effect.neon_color = tint
	effect.glitch_intensity = glitch
	parent_tree.add_child(effect)
	effect.setup_from_source(source_node)
	return effect


func setup_from_source(source: Node3D) -> void:
	if source == null or not is_instance_valid(source):
		return
	global_transform = source.global_transform
	_base_pos = global_position

	_mat_instances.clear()
	_clone_meshes(source, self)
	_spawn_cyber_burst_particles()
	_start_dissolve_sequence()


func _clone_meshes(src_node: Node, target_parent: Node3D) -> void:
	if src_node == null or not is_instance_valid(src_node) or target_parent == null or not is_instance_valid(target_parent):
		return
	for child in src_node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh != null:
				var clone_mi := MeshInstance3D.new()
				clone_mi.mesh = mi.mesh
				clone_mi.transform = mi.transform
				clone_mi.skin = mi.skin
				clone_mi.skeleton = mi.skeleton

				var mat := ShaderMaterial.new()
				mat.shader = SHADER_RES
				mat.set_shader_parameter("neon_color", neon_color)
				mat.set_shader_parameter("secondary_color", secondary_color)
				mat.set_shader_parameter("glitch_intensity", glitch_intensity)
				mat.set_shader_parameter("dissolve_progress", 0.0)
				clone_mi.material_override = mat

				_mat_instances.append(mat)
				target_parent.add_child(clone_mi)
		elif child is Skeleton3D:
			# Traverse child bones if present
			_clone_meshes(child, target_parent)


func _spawn_cyber_burst_particles() -> void:
	var parts := CPUParticles3D.new()
	parts.amount = 18
	parts.lifetime = 0.35
	parts.one_shot = true
	parts.explosiveness = 0.9
	parts.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	parts.emission_box_extents = Vector3(0.3, 0.8, 0.3)
	parts.position.y = 0.8
	parts.direction = Vector3(0, 1, 0)
	parts.spread = 180.0
	parts.gravity = Vector3.ZERO
	parts.initial_velocity_min = 1.0
	parts.initial_velocity_max = 2.5
	parts.scale_amount_min = 0.03
	parts.scale_amount_max = 0.07

	var p_mesh := QuadMesh.new()
	p_mesh.size = Vector2(0.06, 0.06)
	var p_mat := StandardMaterial3D.new()
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p_mat.albedo_color = neon_color * 1.5
	p_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	parts.mesh = p_mesh
	parts.material_override = p_mat

	add_child(parts)
	parts.emitting = true


func _start_dissolve_sequence() -> void:
	var tw := create_tween()
	tw.set_parallel(true)

	# High frequency positional jitter
	var shake_tw := create_tween()
	var shake_steps := int(lifetime * 20.0)
	for i in range(shake_steps):
		var offset := Vector3(randf_range(-0.03, 0.03), randf_range(-0.01, 0.01), randf_range(-0.03, 0.03)) * glitch_intensity
		shake_tw.tween_property(self, "global_position", _base_pos + offset, lifetime / float(shake_steps))

	# Dissolve progress from 0.0 to 1.0
	tw.tween_method(func(v: float):
		for m in _mat_instances:
			if m != null:
				m.set_shader_parameter("dissolve_progress", v)
	, 0.0, 1.0, lifetime).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Finish & Free
	tw.chain().tween_callback(queue_free)
