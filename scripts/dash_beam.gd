class_name DashBeam
extends Node3D
## 3D character ghost afterimages with energy particle shatter dissipation.

const MIN_GHOST_STEP_SQ := 0.20
const MAX_ACTIVE_GHOSTS := 5

var _tint := Color.WHITE
var _life := 0.28
var _height := 1.75
var _sealed := false
var _last_ghost_pos := Vector3(INF, INF, INF)
var _last_ghost_frame := -1
var _ghosts: Array[Dictionary] = []
var _particles: Array[CPUParticles3D] = []
var _ghost_mat: StandardMaterial3D
var _particle_box: BoxMesh


static func start(into: Node, tint: Color, life: float, height: float) -> DashBeam:
	if into == null or not into.is_inside_tree():
		return null
	var beam := DashBeam.new()
	beam._tint = tint
	beam._life = maxf(life, 0.01)
	beam._height = maxf(height, 0.1)
	beam._init_resources(tint)
	into.add_child(beam)
	beam.global_transform = Transform3D.IDENTITY
	return beam


func _init_resources(tint: Color) -> void:
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost_mat.rim_enabled = true
	_ghost_mat.rim = 1.0
	_ghost_mat.rim_tint = 0.8
	_ghost_mat.albedo_color = tint

	_particle_box = BoxMesh.new()
	_particle_box.size = Vector3(0.05, 0.05, 0.05)
	_particle_box.material = _ghost_mat


func extend(point: Vector3, source_character: Node3D = null) -> void:
	if _sealed:
		return
	var current_frame := Engine.get_physics_frames()
	if source_character != null and is_instance_valid(source_character) and current_frame != _last_ghost_frame:
		if _last_ghost_pos.distance_squared_to(point) >= MIN_GHOST_STEP_SQ:
			_last_ghost_pos = point
			_last_ghost_frame = current_frame
			_spawn_ghost(source_character)


func _can_bake_skeleton(mesh_inst: MeshInstance3D) -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	if not mesh_inst.is_inside_tree() or mesh_inst.skin == null or mesh_inst.skeleton.is_empty():
		return false
	if mesh_inst.get_skin_reference() == null:
		return false
	var skel := mesh_inst.get_node_or_null(mesh_inst.skeleton) as Skeleton3D
	return skel != null and skel.is_inside_tree()


func _spawn_ghost(source: Node3D) -> void:
	while _ghosts.size() >= MAX_ACTIVE_GHOSTS:
		var oldest: Dictionary = _ghosts.pop_front()
		if is_instance_valid(oldest.node):
			oldest.node.queue_free()

	var stack: Array[Node] = [source]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is WeaponTrail:
			continue
		var mesh_inst := node as MeshInstance3D
		if mesh_inst != null and mesh_inst.visible and mesh_inst.mesh != null:
			var baked_mesh: Mesh = null
			if _can_bake_skeleton(mesh_inst):
				baked_mesh = mesh_inst.bake_mesh_from_current_skeleton_pose()
			if baked_mesh == null:
				baked_mesh = mesh_inst.mesh
			
			if baked_mesh != null:
				var ghost := MeshInstance3D.new()
				ghost.mesh = baked_mesh
				ghost.global_transform = mesh_inst.global_transform
				ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				ghost.material_override = _ghost_mat
				ghost.transparency = 0.0
				
				add_child(ghost)
				var ghost_life := _life * 0.85
				_ghosts.append({
					"node": ghost,
					"left": ghost_life,
					"max_life": ghost_life
				})
		stack.append_array(node.get_children())

	_spawn_particle_shatter(source.global_position)


func _spawn_particle_shatter(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.mesh = _particle_box
	p.amount = 20
	p.lifetime = _life * 0.95
	p.one_shot = true
	p.explosiveness = 0.85
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.3, _height * 0.45, 0.3)
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3(0, -1.2, 0)
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.4
	p.scale_amount_min = 0.04
	p.scale_amount_max = 0.12
	p.color = _tint
	
	add_child(p)
	p.global_position = pos + Vector3.UP * (_height * 0.5)
	p.emitting = true
	_particles.append(p)


func seal() -> void:
	_sealed = true


func _process(delta: float) -> void:
	for i in range(_ghosts.size() - 1, -1, -1):
		var g: Dictionary = _ghosts[i]
		g.left -= delta
		if g.left <= 0.0:
			if is_instance_valid(g.node):
				g.node.queue_free()
			_ghosts.remove_at(i)
		else:
			var ratio: float = clampf(g.left / g.max_life, 0.0, 1.0)
			var alpha: float = ratio * ratio
			if is_instance_valid(g.node):
				g.node.transparency = 1.0 - alpha

	for i in range(_particles.size() - 1, -1, -1):
		var p: CPUParticles3D = _particles[i]
		if not is_instance_valid(p) or not p.emitting:
			if is_instance_valid(p):
				p.queue_free()
			_particles.remove_at(i)

	if _sealed and _ghosts.is_empty() and _particles.is_empty():
		queue_free()
