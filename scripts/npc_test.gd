extends Node3D
## Scene controller for NPC possession, first-person voxel building, and
## capability-derived pathfinding.
##
## Two modes, toggled with E:
## - possessed: PlayerIntentSource drives the body, FollowCamera is current
## - building: free-flying camera with a crosshair, NPCIntentSource drives the body
## Invariant: the block dictionary and NavGrid's block set are written together.

const CharacterPipelineScript = preload("res://tools/character_pipeline.gd")
const PlayerControllerScript = preload("res://scripts/player_controller.gd")
const PlayerIntentSourceScript = preload("res://scripts/player_intent_source.gd")
const NPCIntentSourceScript = preload("res://scripts/npc_intent_source.gd")
const FollowCameraScript = preload("res://scripts/follow_camera.gd")
const WorldBuilderScript = preload("res://scripts/world/world_builder.gd")
const ENV_PRESET = preload("res://config/env/editor_blue.tres")
const GROUND_PRESET = preload("res://config/ground/editor_slate.tres")

const MENU_SCENE := "res://scenes/main_menu.tscn"
const GROUND_HALF := 20.0
const SPAWN_POS := Vector3(0.5, 0.2, 0.5)
## Highest layer a block may occupy. Cells one above it are still standable.
const MAX_BLOCK_Y := 7

## Builder camera.
const LOOK_SENS := 0.0026
const PITCH_LIMIT := 1.5
const FLY_DAMP := 12.0
const FLY_SPRINT := 3.0
const FLY_MIN := 2.0
const FLY_MAX := 40.0
## How far the crosshair reaches for a block face, metres.
const BUILD_REACH := 24.0

var _characters: Array = []
var _index := 0

var _npc: CharacterBody3D
var _visual: Node3D
var _follow_camera: Camera3D
var _builder_camera: Camera3D

var _npc_intent_source: NPCIntentSource
var _player_intent_source: PlayerIntentSource

var _is_possessed := false
## Alt is held: pointer released so the HUD buttons can be clicked.
var _cursor_free := false

## Placed cubes. Vector3i -> StaticBody3D. Mirrors NavGrid's block set.
var _blocks := {}
var _nav := NavGrid.new()

## Visual path renderer and target beacon.
var _path_mesh_instance: MeshInstance3D
var _path_immediate_mesh: ImmediateMesh
var _beacon_instance: Node3D

## Crosshair targeting.
var _highlight: MeshInstance3D
var _ghost: MeshInstance3D
var _has_aim := false
## Cell the crosshair is on, and the empty cell in front of its face.
var _aim_solid := Vector3i.ZERO
var _aim_empty := Vector3i.ZERO
var _aim_point := Vector3.ZERO

## HUD UI controls.
var _state_label: Label
var _hint_label: Label
var _sequence_label: Label
var _nav_label: Label
var _aim_label: Label
## Last pathfinding outcome, shown in the HUD.
var _nav_status := "尚未指定目的地"

## Builder camera state.
var _cam_yaw := 0.0
var _cam_pitch := -0.55
var _cam_velocity := Vector3.ZERO
var _fly_speed := 9.0


## Full-screen crosshair. Mouse-transparent so the HUD underneath stays clickable.
class Crosshair extends Control:
	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var tint := Color(1.0, 1.0, 1.0, 0.85)
		var shade := Color(0.0, 0.0, 0.0, 0.5)
		for pass_index in 2:
			var col := shade if pass_index == 0 else tint
			var w := 3.0 if pass_index == 0 else 1.5
			draw_line(c - Vector2(10, 0), c - Vector2(3, 0), col, w)
			draw_line(c + Vector2(3, 0), c + Vector2(10, 0), col, w)
			draw_line(c - Vector2(0, 10), c - Vector2(0, 3), col, w)
			draw_line(c + Vector2(0, 3), c + Vector2(0, 10), col, w)


func _ready() -> void:
	_characters = CharacterPipelineScript.list_characters().filter(
		func(c: Dictionary) -> bool: return ResourceLoader.exists(c.scene))
	if _characters.is_empty():
		push_error("no character scenes available")
		return

	_nav.set_bounds(int(GROUND_HALF), MAX_BLOCK_Y + 1)

	_build_environment()
	_build_ground()
	_build_visual_helpers()
	_build_cameras()
	_build_npc()
	_build_hud()
	_set_possession(false)


# --- environment & ground ---------------------------------------------------

func _build_environment() -> void:
	WorldBuilderScript.build_environment(self, ENV_PRESET)


func _build_ground() -> void:
	WorldBuilderScript.build_ground(self, GROUND_PRESET, GROUND_HALF)




# --- visuals: path, beacon, crosshair markers -------------------------------

func _build_visual_helpers() -> void:
	_path_immediate_mesh = ImmediateMesh.new()
	_path_mesh_instance = MeshInstance3D.new()
	_path_mesh_instance.mesh = _path_immediate_mesh

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	_path_mesh_instance.material_override = mat
	add_child(_path_mesh_instance)

	_beacon_instance = Node3D.new()
	var beacon_mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.3
	cyl.bottom_radius = 0.3
	cyl.height = 2.0
	var b_mat := StandardMaterial3D.new()
	b_mat.albedo_color = Color(0.2, 0.85, 1.0, 0.7)
	b_mat.emission_enabled = true
	b_mat.emission = Color(0.1, 0.7, 0.9)
	b_mat.emission_energy_multiplier = 1.5
	b_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cyl.material = b_mat
	beacon_mesh.mesh = cyl
	beacon_mesh.position.y = 1.0
	_beacon_instance.add_child(beacon_mesh)
	_beacon_instance.visible = false
	add_child(_beacon_instance)

	_highlight = _make_wire_cube()
	add_child(_highlight)
	_ghost = _make_ghost_cube()
	add_child(_ghost)


## Unit cube outline drawn from the origin corner, inflated so it clears the
## face it wraps. Post: node origin == cell min corner.
func _make_wire_cube() -> MeshInstance3D:
	var pad := 0.004
	var lo := -pad
	var hi := 1.0 + pad
	var corners := [
		Vector3(lo, lo, lo), Vector3(hi, lo, lo), Vector3(hi, lo, hi), Vector3(lo, lo, hi),
		Vector3(lo, hi, lo), Vector3(hi, hi, lo), Vector3(hi, hi, hi), Vector3(lo, hi, hi),
	]
	var edges := [
		0, 1, 1, 2, 2, 3, 3, 0,
		4, 5, 5, 6, 6, 7, 7, 4,
		0, 4, 1, 5, 2, 6, 3, 7,
	]
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_set_color(Color(1.0, 0.95, 0.55, 0.95))
	for i in edges:
		mesh.surface_add_vertex(corners[i])
	mesh.surface_end()

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.visible = false
	return node


## Translucent preview of the cube a click would place. Post: node origin ==
## cell centre, so the caller offsets by half a cell.
func _make_ghost_cube() -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = Vector3(0.96, 0.96, 0.96)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.85, 1.0, 0.28)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	box.material = mat

	var node := MeshInstance3D.new()
	node.mesh = box
	node.visible = false
	return node


## Draws the plan, one coloured segment per leg so climbs and drops read apart
## from ordinary walking.
func _draw_path(points: PackedVector3Array, moves: PackedInt32Array) -> void:
	_path_immediate_mesh.clear_surfaces()
	if points.size() < 2:
		return

	_path_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(1, points.size()):
		var move: int = moves[i] if i < moves.size() else NavGrid.Move.WALK
		var colour := Color(0.2, 0.95, 0.55, 0.9)
		match move:
			NavGrid.Move.CLIMB: colour = Color(1.0, 0.65, 0.2, 0.95)
			NavGrid.Move.JUMP: colour = Color(1.0, 0.9, 0.3, 0.95)
			NavGrid.Move.DROP: colour = Color(0.4, 0.7, 1.0, 0.95)
		_path_immediate_mesh.surface_set_color(colour)
		_path_immediate_mesh.surface_add_vertex(points[i - 1] + Vector3(0.0, 0.1, 0.0))
		_path_immediate_mesh.surface_set_color(colour)
		_path_immediate_mesh.surface_add_vertex(points[i] + Vector3(0.0, 0.1, 0.0))
	_path_immediate_mesh.surface_end()


# --- cameras & setup --------------------------------------------------------

func _build_cameras() -> void:
	_follow_camera = FollowCameraScript.new()
	_follow_camera.fov = 55.0
	_follow_camera.near = 0.05
	_follow_camera.connect("mode_changed", func(_fp: bool) -> void: _refresh_hud_text())
	add_child(_follow_camera)

	_builder_camera = Camera3D.new()
	_builder_camera.fov = 65.0
	_builder_camera.near = 0.05
	_builder_camera.far = 400.0
	add_child(_builder_camera)
	_builder_camera.global_position = Vector3(0.5, 8.0, 12.5)
	_apply_builder_orientation()


func _apply_builder_orientation() -> void:
	_builder_camera.global_transform = Transform3D(
		Basis.from_euler(Vector3(_cam_pitch, _cam_yaw, 0.0)),
		_builder_camera.global_position)


func _build_npc() -> void:
	_npc = PlayerControllerScript.new()
	_npc.name = "NPC"
	_npc.position = SPAWN_POS

	_npc_intent_source = NPCIntentSourceScript.new()
	_player_intent_source = PlayerIntentSourceScript.new()
	_npc.intent_source = _npc_intent_source
	_npc_intent_source.bind_nav_grid(_nav)
	_npc_intent_source.repath_requested.connect(_on_repath_requested)
	_npc_intent_source.path_finished.connect(_on_path_finished)
	_npc_intent_source.path_blocked.connect(_on_path_blocked)
	add_child(_npc)

	_spawn_character_visual()


func _spawn_character_visual() -> void:
	if _visual != null:
		_visual.queue_free()
		_visual = null
	for child in _npc.get_children():
		if child is CollisionShape3D:
			child.queue_free()

	var entry: Dictionary = _characters[_index]
	var scene := load(entry.scene) as PackedScene
	if scene == null:
		return
	_visual = scene.instantiate() as Node3D
	_npc.add_child(_visual)

	var height: float = _visual.get("body_height")
	if height <= 0.1:
		height = 1.75

	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = minf(0.3, height * 0.2)
	capsule.height = height
	collider.shape = capsule
	collider.position.y = height * 0.5
	_npc.add_child(collider)

	_npc.setup(_visual, _follow_camera)
	_follow_camera.target = _npc
	_follow_camera.frame_for(height)
	_follow_camera.snap()

	# Every navigation rule is derived from this body, so the graph is only valid
	# once the body it was built for is the one standing here.
	_nav.set_capability(_npc)


# --- possession state toggle ------------------------------------------------

func _set_possession(possessed: bool) -> void:
	_is_possessed = possessed
	_cursor_free = false
	if _is_possessed:
		_npc.intent_source = _player_intent_source
		_follow_camera.current = true
		_highlight.visible = false
		_ghost.visible = false
		_has_aim = false
	else:
		_npc.intent_source = _npc_intent_source
		_builder_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	_refresh_hud_text()


# --- building & pathfinding -------------------------------------------------

func _recalculate_npc_path(target: Vector3) -> void:
	var result := _nav.find_path(_npc.global_position, target)
	var points: PackedVector3Array = result.points
	if points.is_empty():
		_npc_intent_source.clear_target()
		_draw_path(points, PackedInt32Array())
		_beacon_instance.visible = false
		_nav_status = "无法从当前位置起步（人机被封死？）"
		return

	_npc_intent_source.set_plan_result(result)
	_draw_path(points, result.moves)
	_beacon_instance.global_position = target
	_beacon_instance.visible = true

	var climbs := 0
	var jumps := 0
	var drops := 0
	for m in result.moves:
		if m == NavGrid.Move.CLIMB:
			climbs += 1
		elif m == NavGrid.Move.JUMP:
			jumps += 1
		elif m == NavGrid.Move.DROP:
			drops += 1
	if result.complete:
		_nav_status = "路径 %d 段 · 攀爬 %d · 跳跃 %d · 落差 %d" % [
			points.size(), climbs, jumps, drops]
	else:
		var last: Vector3 = points[points.size() - 1]
		_nav_status = "目标不可达，已移动至最近点 (%.0f, %.0f, %.0f) · 路径 %d 段" % [
			last.x, last.y, last.z, points.size()]


func _on_repath_requested(from_pos: Vector3, target: Vector3) -> void:
	var result := _nav.find_path(from_pos, target)
	if result.points.is_empty():
		_npc_intent_source.clear_target()
		_nav_status = "受阻且无可用路径，已停止"
		return
	_npc_intent_source.set_plan_result(result)
	_draw_path(result.points, result.moves)
	var climbs := 0
	var jumps := 0
	var drops := 0
	for m in result.moves:
		if m == NavGrid.Move.CLIMB:
			climbs += 1
		elif m == NavGrid.Move.JUMP:
			jumps += 1
		elif m == NavGrid.Move.DROP:
			drops += 1
	if result.complete:
		_nav_status = "路径 %d 段 · 攀爬 %d · 跳跃 %d · 落差 %d" % [
			result.points.size(), climbs, jumps, drops]
	else:
		var last: Vector3 = result.points[result.points.size() - 1]
		_nav_status = "目标不可达，已移动至最近点 (%.0f, %.0f, %.0f) · 路径 %d 段" % [
			last.x, last.y, last.z, result.points.size()]


func _on_path_finished(_target: Vector3) -> void:
	_beacon_instance.visible = false
	_draw_path(PackedVector3Array(), PackedInt32Array())
	_nav_status = "已抵达目的地"


func _on_path_blocked(_target: Vector3, reachable: Vector3) -> void:
	_beacon_instance.visible = false
	_draw_path(PackedVector3Array(), PackedInt32Array())
	_nav_status = "目标不可达，已停在最近点 (%.0f, %.0f, %.0f)" % [
		reachable.x, reachable.y, reachable.z]


## Cell is inside the buildable volume. Stricter than NavGrid.in_bounds, which
## also admits the standable layer above the top block.
func _can_build_at(coord: Vector3i) -> bool:
	if coord.y < 0 or coord.y > MAX_BLOCK_Y:
		return false
	var half := int(GROUND_HALF)
	return coord.x >= -half and coord.x < half and coord.z >= -half and coord.z < half


## Cell overlaps the NPC's standing volume. Building into the body would leave
## it embedded in a wall it has no rule for.
func _npc_occupies(coord: Vector3i) -> bool:
	if _npc == null:
		return false
	var p := _npc.global_position
	var r: float = _nav.capability().radius
	var base_y := int(floor(p.y + 0.05))
	for i in _nav.capability().head_cells():
		if coord.y != base_y + i:
			continue
		for ox in [-r, r]:
			for oz in [-r, r]:
				if coord.x == int(floor(p.x + ox)) and coord.z == int(floor(p.z + oz)):
					return true
	return false


func _place_block(grid_pos: Vector3i) -> void:
	if not _can_build_at(grid_pos) or _blocks.has(grid_pos):
		return
	if _npc_occupies(grid_pos):
		_nav_status = "该位置正被人机占用，无法搭建"
		return

	var body := StaticBody3D.new()
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(1, 1, 1)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.42, 0.38)
	mat.roughness = 0.8
	box_mesh.material = mat
	mesh.mesh = box_mesh
	mesh.position = Vector3(0.5, 0.5, 0.5)
	body.add_child(mesh)

	var col := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(1, 1, 1)
	col.shape = box_shape
	col.position = Vector3(0.5, 0.5, 0.5)
	body.add_child(col)

	body.position = Vector3(grid_pos)
	add_child(body)
	_blocks[grid_pos] = body
	_nav.set_block(grid_pos, true)


func _remove_block(grid_pos: Vector3i) -> void:
	if not _blocks.has(grid_pos):
		return
	var body: Node = _blocks[grid_pos]
	_blocks.erase(grid_pos)
	body.queue_free()
	_nav.set_block(grid_pos, false)


func _clear_all_blocks() -> void:
	for body in _blocks.values():
		body.queue_free()
	_blocks.clear()
	_nav.clear_blocks()
	_nav_status = "已清空障碍物"


# --- crosshair targeting ----------------------------------------------------

## Casts from the screen centre and parks the two markers. Post: _has_aim is
## true only when _aim_solid / _aim_empty are meaningful.
func _update_targeting() -> void:
	_has_aim = false
	var viewport := get_viewport()
	var centre := viewport.get_visible_rect().size * 0.5
	var origin := _builder_camera.project_ray_origin(centre)
	var direction := _builder_camera.project_ray_normal(centre)

	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * BUILD_REACH)
	query.collide_with_areas = false
	# The body is a target to command, not a surface to build on.
	query.exclude = [_npc.get_rid()] if _npc != null else []
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_highlight.visible = false
		_ghost.visible = false
		return

	var pos: Vector3 = hit.position
	var normal: Vector3 = hit.normal
	# The hit lies exactly on a face plane, so half a cell either way along the
	# normal lands dead centre in the cell on that side of it.
	_aim_solid = Vector3i((pos - normal * 0.5).floor())
	_aim_empty = Vector3i((pos + normal * 0.5).floor())
	_aim_point = pos
	_has_aim = true

	_highlight.global_position = Vector3(_aim_solid)
	_highlight.visible = true
	var buildable := _can_build_at(_aim_empty) and not _blocks.has(_aim_empty)
	_ghost.global_position = Vector3(_aim_empty) + Vector3(0.5, 0.5, 0.5)
	_ghost.visible = buildable


# --- input ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.keycode:
			KEY_E:
				_set_possession(not _is_possessed)
				return
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				SceneLoader.change_scene(get_tree(), MENU_SCENE, "返回主菜单...")
				return
			KEY_TAB:
				_index = (_index + 1) % _characters.size()
				_spawn_character_visual()
				return

	if _is_possessed:
		return

	var motion := event as InputEventMouseMotion
	if motion != null:
		if _cursor_free:
			return
		_cam_yaw -= motion.relative.x * LOOK_SENS
		_cam_pitch = clampf(_cam_pitch - motion.relative.y * LOOK_SENS, -PITCH_LIMIT, PITCH_LIMIT)
		_apply_builder_orientation()
		return

	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return

	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		_fly_speed = clampf(_fly_speed * 1.15, FLY_MIN, FLY_MAX)
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_fly_speed = clampf(_fly_speed / 1.15, FLY_MIN, FLY_MAX)
		return

	# With the pointer released the clicks belong to the HUD, not the world.
	if _cursor_free or not _has_aim:
		return

	if mb.button_index == MOUSE_BUTTON_MIDDLE \
			or (mb.button_index == MOUSE_BUTTON_LEFT and Input.is_key_pressed(KEY_SHIFT)):
		_recalculate_npc_path(_aim_point)
	elif mb.button_index == MOUSE_BUTTON_LEFT:
		_place_block(_aim_empty)
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		_remove_block(_aim_solid)


## Alt held releases the pointer for the HUD and takes it back on release.
func _update_cursor_mode() -> void:
	var wants_free := Input.is_key_pressed(KEY_ALT)
	if wants_free == _cursor_free:
		return
	_cursor_free = wants_free
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if wants_free else Input.MOUSE_MODE_CAPTURED


func _drive_builder_camera(delta: float) -> void:
	var wish := Vector3.ZERO
	if not _cursor_free:
		var cam_basis := _builder_camera.global_basis
		if Input.is_physical_key_pressed(KEY_W):
			wish -= cam_basis.z
		if Input.is_physical_key_pressed(KEY_S):
			wish += cam_basis.z
		if Input.is_physical_key_pressed(KEY_A):
			wish -= cam_basis.x
		if Input.is_physical_key_pressed(KEY_D):
			wish += cam_basis.x
		if Input.is_physical_key_pressed(KEY_SPACE):
			wish += Vector3.UP
		if Input.is_physical_key_pressed(KEY_CTRL):
			wish -= Vector3.UP
		if wish != Vector3.ZERO:
			var pace: float = _fly_speed * (FLY_SPRINT if Input.is_key_pressed(KEY_SHIFT) else 1.0)
			wish = wish.normalized() * pace

	_cam_velocity = _cam_velocity.lerp(wish, 1.0 - exp(-delta * FLY_DAMP))
	_builder_camera.global_position += _cam_velocity * delta


# --- task sequence automation -----------------------------------------------

func _run_test_sequence() -> void:
	if _is_possessed:
		_set_possession(false)

	var pt_a := Vector3(-7.5, 0.0, 7.5)
	var pt_b := Vector3(7.5, 0.0, -7.5)

	var leg_a := _nav.find_path(_npc.global_position, pt_a)
	var leg_b := _nav.find_path(pt_a, pt_b)
	var leg_home := _nav.find_path(pt_b, SPAWN_POS)

	var tasks: Array = [
		_move_task(pt_a, leg_a, true),
		{"type": "jump"},
		{"type": "wait", "duration": 0.5},
		_move_task(pt_b, leg_b, true),
		{"type": "crouch", "duration": 1.2},
		{"type": "attack", "button": "attack"},
		_move_task(SPAWN_POS, leg_home, false),
	]

	_npc_intent_source.execute_sequence(tasks)
	_nav_status = "自动化序列已启动"


func _move_task(target: Vector3, result: Dictionary, run: bool) -> Dictionary:
	return {
		"type": "move_to",
		"target": target,
		"path": result.points,
		"moves": result.moves,
		"complete": result.complete,
		"run": run,
	}


## A barrier across the whole field at z = 4: three cubes in the middle, two on
## either side of that, one out at the ends. The body climbs 2.2 m, so the middle
## is not a route and the plan has to walk out to a stretch that is.
func _setup_climb_demo() -> void:
	if _is_possessed:
		_set_possession(false)

	var half := int(GROUND_HALF)
	for x in range(-half, half):
		_place_block(Vector3i(x, 0, 4))
		if absi(x) > 8:
			continue
		_place_block(Vector3i(x, 1, 4))
		if absi(x) <= 4:
			_place_block(Vector3i(x, 2, 4))

	_recalculate_npc_path(Vector3(0.5, 0.0, 8.5))


## A barrier with a decked tunnel through it. The old height-map graph read the
## deck as the walking surface and sealed the tunnel; the voxel graph keeps it.
func _setup_bridge_demo() -> void:
	if _is_possessed:
		_set_possession(false)

	var half := int(GROUND_HALF)
	for x in range(-half, half):
		if absi(x) <= 3:
			_place_block(Vector3i(x, 2, -5))
			continue
		for y in range(0, 3):
			_place_block(Vector3i(x, y, -5))

	_recalculate_npc_path(Vector3(0.5, 0.0, -8.5))


## A row of three-cube platforms with voids of one, two and three metres between
## them, and a diagonal pair of 2.83 m beside it. Every void is inside the body's
## 3.15 m range, so the row is a chain of gap jumps.
##
## Three cubes rather than two on purpose: a two-cube platform is climbable
## straight off the ground and the whole course would be walked round instead.
## The stepped ramp at x = -10 is the only way up.
func _setup_gap_demo() -> void:
	if _is_possessed:
		_set_possession(false)

	# Voids of 1, 2, 3 and 4 m: near cells of consecutive platforms sit 2, 3, 4 and
	# 5 columns apart, and edge to edge that is one less each time.
	_slab(Vector3i(-10, 0, 4), Vector3i(-10, 0, 8))
	for x0 in [-9, -5, 0, 6, 13]:
		_slab(Vector3i(x0, 0, 4), Vector3i(x0 + 2, 2, 8))

	# Near cells (-7, 13) and (-4, 16): three columns apart on both axes, so
	# 2 * sqrt(2) metres of void on the diagonal.
	_slab(Vector3i(-10, 0, 11), Vector3i(-10, 0, 13))
	_slab(Vector3i(-9, 0, 11), Vector3i(-7, 2, 13))
	_slab(Vector3i(-4, 0, 16), Vector3i(-2, 2, 18))

	_recalculate_npc_path(Vector3(14.5, 3.0, 6.5))


## Fills the inclusive box `from`..`to` with cubes.
func _slab(from: Vector3i, to: Vector3i) -> void:
	for x in range(from.x, to.x + 1):
		for y in range(from.y, to.y + 1):
			for z in range(from.z, to.z + 1):
				_place_block(Vector3i(x, y, z))


# --- hud UI -----------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(430, 0)
	layer.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	_state_label = Label.new()
	_state_label.add_theme_font_size_override("font_size", 13)
	box.add_child(_state_label)

	_nav_label = Label.new()
	_nav_label.add_theme_font_size_override("font_size", 12)
	_nav_label.modulate = Color(0.55, 1.0, 0.7, 0.95)
	box.add_child(_nav_label)

	_aim_label = Label.new()
	_aim_label.add_theme_font_size_override("font_size", 12)
	_aim_label.modulate = Color(1.0, 0.92, 0.6, 0.95)
	box.add_child(_aim_label)

	box.add_child(HSeparator.new())

	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", 11)
	_hint_label.modulate = Color(1, 1, 1, 0.8)
	box.add_child(_hint_label)

	_sequence_label = Label.new()
	_sequence_label.add_theme_font_size_override("font_size", 11)
	_sequence_label.modulate = Color(0.4, 0.9, 1.0, 0.9)
	box.add_child(_sequence_label)

	box.add_child(HSeparator.new())

	var btn_row := HBoxContainer.new()
	box.add_child(btn_row)

	var toggle_btn := Button.new()
	toggle_btn.text = "切换寄身/搭建 [E]"
	toggle_btn.pressed.connect(func() -> void: _set_possession(not _is_possessed))
	btn_row.add_child(toggle_btn)

	var climb_btn := Button.new()
	climb_btn.text = "1/2/3 格墙"
	climb_btn.pressed.connect(_setup_climb_demo)
	btn_row.add_child(climb_btn)

	var bridge_btn := Button.new()
	bridge_btn.text = "桥洞"
	bridge_btn.pressed.connect(_setup_bridge_demo)
	btn_row.add_child(bridge_btn)

	var gap_btn := Button.new()
	gap_btn.text = "跳跃演练场"
	gap_btn.pressed.connect(_setup_gap_demo)
	btn_row.add_child(gap_btn)

	var seq_btn := Button.new()
	seq_btn.text = "自动化序列"
	seq_btn.pressed.connect(_run_test_sequence)
	btn_row.add_child(seq_btn)

	var clear_btn := Button.new()
	clear_btn.text = "清空"
	clear_btn.pressed.connect(_clear_all_blocks)
	btn_row.add_child(clear_btn)

	layer.add_child(Crosshair.new())


func _refresh_hud_text() -> void:
	if _hint_label == null:
		return
	if _is_possessed:
		var mode_str := "第一视角" if (_follow_camera != null and bool(_follow_camera.get("is_first_person"))) else "第三视角"
		_hint_label.text = "【模式: 寄身操控中（当前: %s）】\n" % mode_str \
			+ "E 取消寄身 · WASD 移动 · Shift 跑 · Ctrl 蹲 · 空格 跳/爬 · F3 切换视角 · 鼠标 转向"
	else:
		_hint_label.text = "【模式: 搭建/指挥（第一人称自由飞行）】\n" \
			+ "鼠标 转视角 · WASD 飞行 · 空格/Ctrl 升降 · Shift 加速 · 滚轮 调速\n" \
			+ "左键 放置 · 右键 拆除 · 中键(或 Shift+左键) 指定人机目的地\n" \
			+ "按住 Alt 松开鼠标点面板 · E 寄身 · Tab 换角色 · Esc 返回菜单"


func _process(delta: float) -> void:
	# Debounced: one graph rebuild per frame no matter how many cubes changed.
	_nav.rebuild()

	if not _is_possessed:
		_update_cursor_mode()
		_drive_builder_camera(delta)
		_update_targeting()

	if _state_label != null and _npc != null:
		_state_label.text = "人机状态: %s (速度 %.2f m/s)" % [_npc.state_name(), _npc.speed()]

	if _nav_label != null:
		var stuck: float = _npc_intent_source.obstructed_time()
		var suffix := "  ⚠ 受阻 %.1fs" % stuck if stuck > 0.2 else ""
		_nav_label.text = "寻路: " + _nav_status + suffix

	if _aim_label != null:
		if _is_possessed:
			_aim_label.text = ""
		elif _has_aim:
			_aim_label.text = "准星: 命中 (%d, %d, %d) · 放置 (%d, %d, %d) · 飞行 %.1f m/s · 方块 %d" % [
				_aim_solid.x, _aim_solid.y, _aim_solid.z,
				_aim_empty.x, _aim_empty.y, _aim_empty.z, _fly_speed, _blocks.size()]
		else:
			_aim_label.text = "准星: 未命中方块 · 飞行 %.1f m/s · 方块 %d" % [
				_fly_speed, _blocks.size()]

	if _sequence_label != null and _npc_intent_source != null:
		_sequence_label.text = "自动化序列状态: " + _npc_intent_source.get_sequence_status()
