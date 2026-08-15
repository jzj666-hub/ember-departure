class_name MapEditor
extends Node3D
## Map editor controller supporting multi-cell block building, save/load/new map,
## and player-driven straight-line special jump trajectory recording.

const CharacterPipelineScript = preload("res://tools/character_pipeline.gd")
const PlayerControllerScript = preload("res://scripts/player_controller.gd")
const PlayerIntentSourceScript = preload("res://scripts/player_intent_source.gd")
const NPCIntentSourceScript = preload("res://scripts/npc_intent_source.gd")
const FollowCameraScript = preload("res://scripts/follow_camera.gd")
const BlockRegistryScript = preload("res://scripts/block_registry.gd")
const MapDataScript = preload("res://scripts/map_data.gd")
const SpecialPathRecorderScript = preload("res://scripts/special_path_recorder.gd")

const MENU_SCENE := "res://scenes/main_menu.tscn"
const GROUND_HALF := 20.0
const MAX_BLOCK_Y := 7
const SPAWN_POS := Vector3(0.5, 0.2, 0.5)

## Builder camera tuning.
const LOOK_SENS := 0.0026
const PITCH_LIMIT := 1.5
const FLY_DAMP := 12.0
const FLY_SPRINT := 3.0
const FLY_MIN := 2.0
const FLY_MAX := 40.0
const BUILD_REACH := 32.0

enum EditorMode {
	BUILD,
	PLAY_TEST,
	RECORD_SPECIAL_PATH
}

var _mode: int = EditorMode.BUILD
var _cursor_free := false

## Map state.
var _map_name := "新建地图"
var _map_file_path := ""
var _spawn_point := SPAWN_POS
var _blocks: Dictionary = {} # block_id (String) -> BlockRegistry.BlockInstance
var _cell_to_block_id: Dictionary = {} # Vector3i -> block_id (String)
var _next_block_num := 1

## Selected block placement properties.
var _current_block_type := "cube"
var _current_block_size := Vector3i(1, 1, 1)

## Navigation and special paths.
var _nav := NavGrid.new()
var _recorder = SpecialPathRecorderScript.new()

## Visual helpers and path meshes.
var _path_mesh_instance: MeshInstance3D
var _path_immediate_mesh: ImmediateMesh
var _special_paths_mesh_instance: MeshInstance3D
var _special_paths_mesh: ImmediateMesh
var _beacon_instance: Node3D

## Crosshair targeting and ghost previews.
var _highlight: MeshInstance3D
var _ghost: MeshInstance3D
var _has_aim := false
var _aim_solid := Vector3i.ZERO
var _aim_empty := Vector3i.ZERO
var _aim_point := Vector3.ZERO
var _aim_normal := Vector3.UP

## Cameras and character body.
var _builder_camera: Camera3D
var _follow_camera: Camera3D
var _cam_yaw := 0.0
var _cam_pitch := -0.55
var _cam_velocity := Vector3.ZERO
var _fly_speed := 9.0

var _npc: CharacterBody3D
var _visual: Node3D
var _npc_intent_source: NPCIntentSource
var _player_intent_source: PlayerIntentSource
var _characters: Array = []
var _char_index := 0

## HUD and UI elements.
var _hud_canvas: CanvasLayer
var _status_label: Label
var _mode_label: Label
var _block_info_label: Label
var _special_path_list_box: VBoxContainer
var _save_load_dialog: PanelContainer
var _map_file_list: ItemList
var _map_name_edit: LineEdit
var _dialog_title_label: Label
var _is_save_dialog := true

var _status_text := "地图编辑器就绪"


## Full-screen Crosshair indicator.
class EditorCrosshair extends Control:
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
	BlockRegistry.init_registry()
	_characters = CharacterPipelineScript.list_characters().filter(
		func(c: Dictionary) -> bool: return ResourceLoader.exists(c.scene))

	_nav.set_bounds(int(GROUND_HALF), MAX_BLOCK_Y + 1)
	_recorder.set_nav_grid(_nav)
	_recorder.path_recorded.connect(_on_special_path_recorded)
	_recorder.recording_failed.connect(_on_special_path_failed)
	_recorder.state_changed.connect(_on_recorder_state_changed)

	_build_environment()
	_build_ground()
	_build_visual_helpers()
	_build_cameras()
	_build_npc()
	_build_hud()

	_set_mode(EditorMode.BUILD)


# --- Scene Construction -----------------------------------------------------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.24, 0.32, 0.47)
	sky_mat.sky_horizon_color = Color(0.58, 0.60, 0.63)
	sky_mat.ground_bottom_color = Color(0.12, 0.12, 0.14)
	sky_mat.ground_horizon_color = Color(0.58, 0.60, 0.63)

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var light := DirectionalLight3D.new()
	light.light_energy = 2.2
	light.shadow_enabled = true
	light.transform.basis = Basis.from_euler(Vector3(deg_to_rad(-45.0), deg_to_rad(-35.0), 0.0))
	add_child(light)


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"

	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_HALF * 2.0, GROUND_HALF * 2.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.20, 0.23)
	mat.roughness = 0.9
	plane.material = mat
	mesh.mesh = plane
	body.add_child(mesh)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(GROUND_HALF * 2.0, 0.4, GROUND_HALF * 2.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.2, 0.0)
	body.add_child(shape)
	add_child(body)

	add_child(_make_grid())


func _make_grid() -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	var half := int(GROUND_HALF)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(-half, half + 1):
		var major := i % 5 == 0
		var colour := Color(0.45, 0.50, 0.60, 0.6) if major else Color(0.28, 0.30, 0.35, 0.3)
		mesh.surface_set_color(colour)
		mesh.surface_add_vertex(Vector3(i, 0.0, -half))
		mesh.surface_add_vertex(Vector3(i, 0.0, half))
		mesh.surface_set_color(colour)
		mesh.surface_add_vertex(Vector3(-half, 0.0, i))
		mesh.surface_add_vertex(Vector3(half, 0.0, i))
	mesh.surface_end()

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position.y = 0.003
	return node


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

	_special_paths_mesh = ImmediateMesh.new()
	_special_paths_mesh_instance = MeshInstance3D.new()
	_special_paths_mesh_instance.mesh = _special_paths_mesh
	var sp_mat := StandardMaterial3D.new()
	sp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sp_mat.vertex_color_use_as_albedo = true
	sp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sp_mat.no_depth_test = false
	_special_paths_mesh_instance.material_override = sp_mat
	add_child(_special_paths_mesh_instance)

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


func _make_wire_cube() -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	_update_wire_mesh(mesh, Vector3i.ONE)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.visible = false
	return node


func _update_wire_mesh(mesh: ImmediateMesh, size: Vector3i) -> void:
	mesh.clear_surfaces()
	var pad := 0.004
	var lo := -pad
	var hx := float(size.x) + pad
	var hy := float(size.y) + pad
	var hz := float(size.z) + pad

	var corners := [
		Vector3(lo, lo, lo), Vector3(hx, lo, lo), Vector3(hx, lo, hz), Vector3(lo, lo, hz),
		Vector3(lo, hy, lo), Vector3(hx, hy, lo), Vector3(hx, hy, hz), Vector3(lo, hy, hz),
	]
	var edges := [
		0, 1, 1, 2, 2, 3, 3, 0,
		4, 5, 5, 6, 6, 7, 7, 4,
		0, 4, 1, 5, 2, 6, 3, 7,
	]
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_set_color(Color(1.0, 0.95, 0.55, 0.95))
	for i in edges:
		mesh.surface_add_vertex(corners[i])
	mesh.surface_end()


func _make_ghost_cube() -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = Vector3(0.96, 0.96, 0.96)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.85, 1.0, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	box.material = mat

	var node := MeshInstance3D.new()
	node.mesh = box
	node.visible = false
	return node


func _update_ghost_size(size: Vector3i) -> void:
	if _ghost.mesh is BoxMesh:
		var bm := _ghost.mesh as BoxMesh
		bm.size = Vector3(float(size.x) - 0.04, float(size.y) - 0.04, float(size.z) - 0.04)


func _build_cameras() -> void:
	_follow_camera = FollowCameraScript.new()
	_follow_camera.fov = 55.0
	_follow_camera.near = 0.05
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
	_npc.name = "EditorNPC"
	_npc.position = _spawn_point

	_npc_intent_source = NPCIntentSourceScript.new()
	_player_intent_source = PlayerIntentSourceScript.new()
	_npc.intent_source = _npc_intent_source
	_npc_intent_source.bind_nav_grid(_nav)
	_npc_intent_source.repath_requested.connect(_on_repath_requested)
	_npc_intent_source.path_finished.connect(func(_t: Vector3) -> void:
		_beacon_instance.visible = false
		_draw_path(PackedVector3Array(), PackedInt32Array())
		_set_status("NPC 已抵达目标")
	)
	_npc_intent_source.path_blocked.connect(func(_t: Vector3, r: Vector3) -> void:
		_beacon_instance.visible = false
		_draw_path(PackedVector3Array(), PackedInt32Array())
		_set_status("目标不可达，已停在最近点 (%.1f, %.1f, %.1f)" % [r.x, r.y, r.z])
	)
	add_child(_npc)

	_spawn_character_visual()


func _spawn_character_visual() -> void:
	if _characters.is_empty():
		return
	if _visual != null:
		_visual.queue_free()
		_visual = null
	for child in _npc.get_children():
		if child is CollisionShape3D:
			child.queue_free()

	var entry: Dictionary = _characters[_char_index]
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

	_nav.set_capability(_npc)


# --- Mode Management --------------------------------------------------------

func _set_mode(new_mode: int) -> void:
	_mode = new_mode
	_cursor_free = false

	match _mode:
		EditorMode.BUILD:
			_npc.intent_source = _npc_intent_source
			_builder_camera.current = true
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_mode_label.text = "模式: 【自由建造】 (按 TAB 试玩, 按 R 录制特殊跳跃, 按住 ALT 解锁鼠标)"
			_set_status("准星瞄准：左键放置，右键删除，Shift+左键/中键 指定人机寻路测试")
		EditorMode.PLAY_TEST:
			_npc.intent_source = _player_intent_source
			_follow_camera.current = true
			_highlight.visible = false
			_ghost.visible = false
			_has_aim = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_mode_label.text = "模式: 【操控试玩】 (按 TAB 退出操控返回建造)"
			_set_status("WASD移动，Shift加速，Space跳跃")
		EditorMode.RECORD_SPECIAL_PATH:
			_npc.intent_source = _player_intent_source
			_follow_camera.current = true
			_highlight.visible = false
			_ghost.visible = false
			_has_aim = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_mode_label.text = "模式: 【特殊路径录制】 (按 ESC / R 取消录制)"
			_recorder.start_recording()


func _set_status(msg: String) -> void:
	_status_text = msg
	if _status_label != null:
		_status_label.text = msg


# --- Physics and Process ----------------------------------------------------

func _process(delta: float) -> void:
	if not is_inside_tree():
		return
	if _mode == EditorMode.BUILD and not _cursor_free:
		_update_builder_flight(delta)
		_update_targeting()


func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return
	if _recorder.is_recording():
		_recorder.update_frame(_npc, delta)


func _unhandled_input(event: InputEvent) -> void:
	if not is_inside_tree():
		return

	if event is InputEventKey and not event.echo:
		if event.keycode == KEY_ALT:
			_cursor_free = event.pressed
			if _cursor_free:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			elif _mode == EditorMode.BUILD or _mode == EditorMode.PLAY_TEST:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return

		if event.pressed:
			match event.keycode:
				KEY_TAB:
					if _mode == EditorMode.BUILD:
						_set_mode(EditorMode.PLAY_TEST)
					elif _mode == EditorMode.PLAY_TEST:
						_set_mode(EditorMode.BUILD)
					get_viewport().set_input_as_handled()
					return
				KEY_R:
					if _mode == EditorMode.RECORD_SPECIAL_PATH:
						_recorder.cancel_recording()
						_set_mode(EditorMode.BUILD)
					else:
						_set_mode(EditorMode.RECORD_SPECIAL_PATH)
					get_viewport().set_input_as_handled()
					return
				KEY_ESCAPE:
					if _save_load_dialog.visible:
						_save_load_dialog.visible = false
						Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
						get_viewport().set_input_as_handled()
						return
					if _mode != EditorMode.BUILD:
						_recorder.cancel_recording()
						_set_mode(EditorMode.BUILD)
						get_viewport().set_input_as_handled()
						return
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
					get_tree().change_scene_to_file(MENU_SCENE)
					return

	if _mode == EditorMode.BUILD and not _cursor_free:
		if event is InputEventMouseMotion:
			_cam_yaw -= event.relative.x * LOOK_SENS
			_cam_pitch = clampf(_cam_pitch - event.relative.y * LOOK_SENS, -PITCH_LIMIT, PITCH_LIMIT)
			_apply_builder_orientation()
			get_viewport().set_input_as_handled()

		elif event is InputEventMouseButton and event.pressed:
			match event.button_index:
				MOUSE_BUTTON_LEFT:
					if _has_aim:
						if event.shift_pressed or Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_SHIFT):
							_recalculate_npc_path(_aim_point)
						else:
							_place_block_at(_aim_empty)
						get_viewport().set_input_as_handled()
				MOUSE_BUTTON_RIGHT:
					if _has_aim:
						_remove_block_at(_aim_solid)
						get_viewport().set_input_as_handled()
				MOUSE_BUTTON_MIDDLE:
					if _has_aim:
						_recalculate_npc_path(_aim_point)
						get_viewport().set_input_as_handled()
				MOUSE_BUTTON_WHEEL_UP:
					_fly_speed = clampf(_fly_speed * 1.15, FLY_MIN, FLY_MAX)
				MOUSE_BUTTON_WHEEL_DOWN:
					_fly_speed = clampf(_fly_speed / 1.15, FLY_MIN, FLY_MAX)


func _update_builder_flight(delta: float) -> void:
	var wish := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): wish += -_builder_camera.global_transform.basis.z
	if Input.is_physical_key_pressed(KEY_S): wish += _builder_camera.global_transform.basis.z
	if Input.is_physical_key_pressed(KEY_A): wish += -_builder_camera.global_transform.basis.x
	if Input.is_physical_key_pressed(KEY_D): wish += _builder_camera.global_transform.basis.x
	if Input.is_physical_key_pressed(KEY_SPACE): wish += Vector3.UP
	if Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_C): wish += Vector3.DOWN

	if wish.length_squared() > 0.001:
		wish = wish.normalized()
		var spd := _fly_speed * (FLY_SPRINT if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
		_cam_velocity = _cam_velocity.lerp(wish * spd, 1.0 - exp(-FLY_DAMP * delta))
	else:
		_cam_velocity = _cam_velocity.lerp(Vector3.ZERO, 1.0 - exp(-FLY_DAMP * delta))

	_builder_camera.global_position += _cam_velocity * delta


func _update_targeting() -> void:
	_has_aim = false
	var viewport := get_viewport()
	var centre := viewport.get_visible_rect().size * 0.5
	var origin := _builder_camera.project_ray_origin(centre)
	var direction := _builder_camera.project_ray_normal(centre)

	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * BUILD_REACH)
	query.collide_with_areas = false
	query.exclude = [_npc.get_rid()] if _npc != null else []
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_highlight.visible = false
		_ghost.visible = false
		return

	var pos: Vector3 = hit.position
	var normal: Vector3 = hit.normal
	_aim_normal = normal
	_aim_solid = Vector3i((pos - normal * 0.5).floor())
	_aim_empty = Vector3i((pos + normal * 0.5).floor())
	_aim_point = pos
	_has_aim = true

	# Highlight existing targeted block
	if _cell_to_block_id.has(_aim_solid):
		var b_id: String = _cell_to_block_id[_aim_solid]
		var inst: BlockRegistry.BlockInstance = _blocks[b_id]
		_highlight.global_position = Vector3(inst.grid_pos)
		_update_wire_mesh(_highlight.mesh as ImmediateMesh, inst.size)
		_highlight.visible = true
	else:
		_highlight.global_position = Vector3(_aim_solid)
		_update_wire_mesh(_highlight.mesh as ImmediateMesh, Vector3i.ONE)
		_highlight.visible = true

	# Ghost placement preview
	_update_ghost_size(_current_block_size)
	_ghost.global_position = Vector3(_aim_empty) + Vector3(_current_block_size) * 0.5
	var can_place := _can_place_block(_aim_empty, _current_block_size)
	var ghost_mat := (_ghost.mesh as BoxMesh).material as StandardMaterial3D
	if ghost_mat != null:
		ghost_mat.albedo_color = Color(0.2, 0.9, 0.4, 0.4) if can_place else Color(1.0, 0.2, 0.2, 0.4)
	_ghost.visible = true


# --- Block Management -------------------------------------------------------

func _can_place_block(origin: Vector3i, size: Vector3i) -> bool:
	var half := int(GROUND_HALF)
	for x in range(size.x):
		for y in range(size.y):
			for z in range(size.z):
				var cell := Vector3i(origin.x + x, origin.y + y, origin.z + z)
				if cell.y < 0 or cell.y > MAX_BLOCK_Y:
					return false
				if cell.x < -half or cell.x >= half or cell.z < -half or cell.z >= half:
					return false
				if _cell_to_block_id.has(cell):
					return false
				if _npc_occupies_cell(cell):
					return false
	return true


func _npc_occupies_cell(cell: Vector3i) -> bool:
	if _npc == null:
		return false
	var p := _npc.global_position
	var r: float = _nav.capability().radius
	var base_y := int(floor(p.y + 0.05))
	for i in _nav.capability().head_cells():
		if cell.y != base_y + i:
			continue
		for ox in [-r, r]:
			for oz in [-r, r]:
				if cell.x == int(floor(p.x + ox)) and cell.z == int(floor(p.z + oz)):
					return true
	return false


func _place_block_at(grid_pos: Vector3i) -> void:
	if not _can_place_block(grid_pos, _current_block_size):
		_set_status("该位置无法放置方块（超出边界或已被占用）")
		return

	var inst := BlockRegistry.BlockInstance.new()
	inst.id = "blk_%d" % _next_block_num
	_next_block_num += 1
	inst.type_id = _current_block_type
	inst.grid_pos = grid_pos
	inst.size = _current_block_size

	var body := BlockRegistry.create_body(inst)
	inst.body_node = body
	add_child(body)

	_blocks[inst.id] = inst
	for cell in inst.get_occupied_cells():
		_cell_to_block_id[cell] = inst.id
		_nav.set_block(cell, true)

	_redraw_special_paths()
	_set_status("已放置方块 [%s] 尺寸 %s 于 (%d, %d, %d)" % [
		inst.type_id, inst.size, grid_pos.x, grid_pos.y, grid_pos.z])


func _remove_block_at(grid_pos: Vector3i) -> void:
	if not _cell_to_block_id.has(grid_pos):
		return
	var b_id: String = _cell_to_block_id[grid_pos]
	if not _blocks.has(b_id):
		return

	var inst: BlockRegistry.BlockInstance = _blocks[b_id]
	for cell in inst.get_occupied_cells():
		_cell_to_block_id.erase(cell)
		_nav.set_block(cell, false)

	if inst.body_node != null:
		inst.body_node.queue_free()
	_blocks.erase(b_id)

	_redraw_special_paths()
	_set_status("已删除方块 %s" % b_id)


func _clear_all_blocks() -> void:
	for inst in _blocks.values():
		if inst.body_node != null:
			inst.body_node.queue_free()
	_blocks.clear()
	_cell_to_block_id.clear()
	_nav.clear_blocks()
	_redraw_special_paths()
	_set_status("已清空所有方块")


# --- Special Path Integration -----------------------------------------------

func _on_special_path_recorded(path_data: Dictionary) -> void:
	_nav.add_special_path(path_data)
	_redraw_special_paths()
	_refresh_special_paths_ui()
	_set_mode(EditorMode.BUILD)
	_set_status("已成功记录并接入特殊跳跃路径！")


func _on_special_path_failed(reason: String) -> void:
	_set_status(reason)
	_set_mode(EditorMode.BUILD)


func _on_recorder_state_changed(_state: int, message: String) -> void:
	_set_status(message)


func _redraw_special_paths() -> void:
	_special_paths_mesh.clear_surfaces()
	var paths := _nav.get_special_paths()
	if paths.is_empty():
		return

	_special_paths_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for p in paths:
		var traj: Array = p.get("trajectory", [])
		if traj.size() >= 2:
			for i in range(1, traj.size()):
				var p1: Array = traj[i - 1]["p"]
				var p2: Array = traj[i]["p"]
				var col := Color(1.0, 0.2, 0.8, 0.9)
				_special_paths_mesh.surface_set_color(col)
				_special_paths_mesh.surface_add_vertex(Vector3(p1[0], p1[1], p1[2]))
				_special_paths_mesh.surface_set_color(col)
				_special_paths_mesh.surface_add_vertex(Vector3(p2[0], p2[1], p2[2]))
		else:
			var from_c: Vector3i = NavGrid._parse_coord(p.get("from"))
			var to_c: Vector3i = NavGrid._parse_coord(p.get("to"))
			var f1 := NavGrid.foot(from_c) + Vector3(0, 0.2, 0)
			var f2 := NavGrid.foot(to_c) + Vector3(0, 0.2, 0)
			var col := Color(0.9, 0.3, 1.0, 0.85)
			_special_paths_mesh.surface_set_color(col)
			_special_paths_mesh.surface_add_vertex(f1)
			_special_paths_mesh.surface_set_color(col)
			_special_paths_mesh.surface_add_vertex(f2)
	_special_paths_mesh.surface_end()


# --- Pathfinding & Testing --------------------------------------------------

func _recalculate_npc_path(target: Vector3) -> void:
	var result := _nav.find_path(_npc.global_position, target)
	var points: PackedVector3Array = result.points
	if points.is_empty():
		_npc_intent_source.clear_target()
		_draw_path(points, PackedInt32Array())
		_beacon_instance.visible = false
		_set_status("无法从当前位置起步（目标不可达或无可行路径）")
		return

	_npc_intent_source.set_plan_result(result)
	_draw_path(points, result.moves)
	_beacon_instance.global_position = target
	_beacon_instance.visible = true
	_set_status("已规划路径：包含 %d 个航路点 (按 TAB 可切至测试操控)" % points.size())


func _on_repath_requested(from_pos: Vector3, target: Vector3) -> void:
	var result := _nav.find_path(from_pos, target)
	if result.points.is_empty():
		_npc_intent_source.clear_target()
		_set_status("NPC 受阻且无可用重寻路路径")
		return
	_npc_intent_source.set_plan_result(result)
	_draw_path(result.points, result.moves)


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
			NavGrid.Move.SPECIAL_JUMP: colour = Color(1.0, 0.2, 0.8, 0.95)
		_path_immediate_mesh.surface_set_color(colour)
		_path_immediate_mesh.surface_add_vertex(points[i - 1] + Vector3(0.0, 0.1, 0.0))
		_path_immediate_mesh.surface_set_color(colour)
		_path_immediate_mesh.surface_add_vertex(points[i] + Vector3(0.0, 0.1, 0.0))
	_path_immediate_mesh.surface_end()


# --- Map Save / Load / New --------------------------------------------------

func new_map() -> void:
	_clear_all_blocks()
	_nav.clear_special_paths()
	_redraw_special_paths()
	_refresh_special_paths_ui()
	_map_name = "新建地图"
	_map_file_path = ""
	_spawn_point = SPAWN_POS
	_npc.global_position = _spawn_point
	_set_status("已创建新地图")


func save_current_map(file_name: String) -> void:
	if not file_name.ends_with(".json"):
		file_name += ".json"
	var save_path := MapDataScript.USER_MAPS_DIR.path_join(file_name)
	var map_dict := MapDataScript.serialize_map(
		_map_name,
		_spawn_point,
		int(GROUND_HALF),
		MAX_BLOCK_Y,
		_blocks.values(),
		_nav.get_special_paths()
	)
	var err := MapDataScript.save_map_to_file(save_path, map_dict)
	if err == OK:
		_map_file_path = save_path
		_set_status("地图已成功保存至: %s" % file_name)
	else:
		_set_status("保存地图失败，错误码: %d" % err)


func load_map(path: String) -> void:
	var data := MapDataScript.load_map_from_file(path)
	if data.is_empty():
		_set_status("加载地图失败: %s" % path)
		return

	_clear_all_blocks()
	_nav.clear_special_paths()

	_map_name = str(data.get("name", "未命名地图"))
	_map_file_path = path

	var sp: Array = data.get("spawn_pos", [0.5, 0.2, 0.5])
	if sp.size() >= 3:
		_spawn_point = Vector3(sp[0], sp[1], sp[2])
		_npc.global_position = _spawn_point

	var blocks_arr: Array = data.get("blocks", [])
	for b_dict in blocks_arr:
		if b_dict is Dictionary:
			var inst := BlockRegistryScript.BlockInstance.from_dict(b_dict)
			if inst.id.is_empty():
				inst.id = "blk_%d" % _next_block_num
				_next_block_num += 1
			var body := BlockRegistryScript.create_body(inst)
			inst.body_node = body
			add_child(body)
			_blocks[inst.id] = inst
			for cell in inst.get_occupied_cells():
				_cell_to_block_id[cell] = inst.id
				_nav.set_block(cell, true)

	var sp_arr: Array = data.get("special_paths", [])
	_nav.set_special_paths(sp_arr)

	_redraw_special_paths()
	_refresh_special_paths_ui()
	_set_status("成功加载地图: %s (包含 %d 个方块, %d 条特殊路径)" % [
		_map_name, _blocks.size(), sp_arr.size()])


# --- HUD & UI Building ------------------------------------------------------

func _build_hud() -> void:
	_hud_canvas = CanvasLayer.new()
	add_child(_hud_canvas)

	var crosshair := EditorCrosshair.new()
	_hud_canvas.add_child(crosshair)

	# Top Toolbar
	var top_panel := PanelContainer.new()
	top_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_panel.custom_minimum_size = Vector2(0, 48)
	var top_style := StyleBoxFlat.new()
	top_style.bg_color = Color(0.1, 0.12, 0.15, 0.88)
	top_style.set_content_margin_all(8)
	top_panel.add_theme_stylebox_override("panel", top_style)
	_hud_canvas.add_child(top_panel)

	var top_box := HBoxContainer.new()
	top_box.add_theme_constant_override("separation", 12)
	top_panel.add_child(top_box)

	var title_lbl := Label.new()
	title_lbl.text = "灰烬:启程 · 地图编辑器"
	title_lbl.add_theme_font_size_override("font_size", 16)
	top_box.add_child(title_lbl)

	top_box.add_child(VSeparator.new())

	var new_btn := Button.new()
	new_btn.text = "新建 (New)"
	new_btn.pressed.connect(new_map)
	top_box.add_child(new_btn)

	var save_btn := Button.new()
	save_btn.text = "保存 (Save)"
	save_btn.pressed.connect(func() -> void: _open_save_dialog())
	top_box.add_child(save_btn)

	var load_btn := Button.new()
	load_btn.text = "加载 (Load)"
	load_btn.pressed.connect(func() -> void: _open_load_dialog())
	top_box.add_child(load_btn)

	var clear_btn := Button.new()
	clear_btn.text = "清空方块"
	clear_btn.pressed.connect(_clear_all_blocks)
	top_box.add_child(clear_btn)

	top_box.add_child(VSeparator.new())

	var play_btn := Button.new()
	play_btn.text = "操控试玩 (TAB)"
	play_btn.pressed.connect(func() -> void: _set_mode(EditorMode.PLAY_TEST))
	top_box.add_child(play_btn)

	var rec_btn := Button.new()
	rec_btn.text = "录制特殊跳跃 (R)"
	rec_btn.pressed.connect(func() -> void: _set_mode(EditorMode.RECORD_SPECIAL_PATH))
	top_box.add_child(rec_btn)

	top_box.add_child(VSeparator.new())

	var menu_btn := Button.new()
	menu_btn.text = "返回主菜单 (ESC)"
	menu_btn.pressed.connect(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))
	top_box.add_child(menu_btn)

	# Left Sidebar: Block Palette and Dimensions
	var left_panel := PanelContainer.new()
	left_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left_panel.offset_top = 56
	left_panel.offset_bottom = -36
	left_panel.custom_minimum_size = Vector2(230, 0)
	var left_style := StyleBoxFlat.new()
	left_style.bg_color = Color(0.11, 0.13, 0.16, 0.85)
	left_style.set_content_margin_all(10)
	left_panel.add_theme_stylebox_override("panel", left_style)
	_hud_canvas.add_child(left_panel)

	var left_scroll := ScrollContainer.new()
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_panel.add_child(left_scroll)

	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 8)
	left_scroll.add_child(left_vbox)

	var palette_lbl := Label.new()
	palette_lbl.text = "方块种类 (Type)"
	palette_lbl.add_theme_font_size_override("font_size", 14)
	left_vbox.add_child(palette_lbl)

	var type_opt := OptionButton.new()
	for t in BlockRegistryScript.list_types():
		type_opt.add_item(t.name)
		type_opt.set_item_metadata(type_opt.item_count - 1, t.id)
	type_opt.item_selected.connect(func(idx: int) -> void:
		_current_block_type = str(type_opt.get_item_metadata(idx))
		_update_block_info()
	)
	left_vbox.add_child(type_opt)

	left_vbox.add_child(HSeparator.new())

	var size_title := Label.new()
	size_title.text = "方块尺寸 (Size X/Y/Z)"
	size_title.add_theme_font_size_override("font_size", 14)
	left_vbox.add_child(size_title)

	var sx_box := _make_dim_slider("长度 X (宽)", 1, 10, _current_block_size.x, func(val: int) -> void:
		_current_block_size.x = val
		_update_block_info()
	)
	left_vbox.add_child(sx_box)

	var sy_box := _make_dim_slider("高度 Y (高)", 1, 8, _current_block_size.y, func(val: int) -> void:
		_current_block_size.y = val
		_update_block_info()
	)
	left_vbox.add_child(sy_box)

	var sz_box := _make_dim_slider("宽度 Z (深)", 1, 10, _current_block_size.z, func(val: int) -> void:
		_current_block_size.z = val
		_update_block_info()
	)
	left_vbox.add_child(sz_box)

	left_vbox.add_child(HSeparator.new())

	var preset_title := Label.new()
	preset_title.text = "尺寸预设 (Presets)"
	preset_title.add_theme_font_size_override("font_size", 13)
	left_vbox.add_child(preset_title)

	var preset_grid := GridContainer.new()
	preset_grid.columns = 2
	left_vbox.add_child(preset_grid)

	_add_preset_btn(preset_grid, "1x1x1 标准", Vector3i(1, 1, 1))
	_add_preset_btn(preset_grid, "2x1x2 平台", Vector3i(2, 1, 2))
	_add_preset_btn(preset_grid, "4x1x4 大平台", Vector3i(4, 1, 4))
	_add_preset_btn(preset_grid, "1x4x1 立柱", Vector3i(1, 4, 1))
	_add_preset_btn(preset_grid, "4x3x1 高墙", Vector3i(4, 3, 1))
	_add_preset_btn(preset_grid, "2x2x2 方体", Vector3i(2, 2, 2))

	_block_info_label = Label.new()
	_block_info_label.text = "当前: cube (1x1x1)"
	_block_info_label.add_theme_font_size_override("font_size", 12)
	_block_info_label.modulate = Color(0.7, 0.85, 1.0)
	left_vbox.add_child(_block_info_label)

	# Right Sidebar: Special Paths List and Management
	var right_panel := PanelContainer.new()
	right_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right_panel.offset_top = 56
	right_panel.offset_bottom = -36
	right_panel.custom_minimum_size = Vector2(250, 0)
	var right_style := StyleBoxFlat.new()
	right_style.bg_color = Color(0.11, 0.13, 0.16, 0.85)
	right_style.set_content_margin_all(10)
	right_panel.add_theme_stylebox_override("panel", right_style)
	_hud_canvas.add_child(right_panel)

	var right_scroll := ScrollContainer.new()
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_panel.add_child(right_scroll)

	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 8)
	right_scroll.add_child(right_vbox)

	var sp_title := Label.new()
	sp_title.text = "特殊路径连接 (Special Paths)"
	sp_title.add_theme_font_size_override("font_size", 14)
	right_vbox.add_child(sp_title)

	var sp_hint := Label.new()
	sp_hint.text = "记录原本物理判定不可达的跳跃连接"
	sp_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sp_hint.add_theme_font_size_override("font_size", 11)
	sp_hint.modulate = Color(1, 1, 1, 0.6)
	right_vbox.add_child(sp_hint)

	_special_path_list_box = VBoxContainer.new()
	_special_path_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_special_path_list_box.add_theme_constant_override("separation", 6)
	right_vbox.add_child(_special_path_list_box)

	# Bottom Status Bar
	var bottom_panel := PanelContainer.new()
	bottom_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_panel.custom_minimum_size = Vector2(0, 32)
	var bottom_style := StyleBoxFlat.new()
	bottom_style.bg_color = Color(0.08, 0.09, 0.11, 0.92)
	bottom_style.set_content_margin_all(6)
	bottom_panel.add_theme_stylebox_override("panel", bottom_style)
	_hud_canvas.add_child(bottom_panel)

	var bottom_box := HBoxContainer.new()
	bottom_panel.add_child(bottom_box)

	_mode_label = Label.new()
	_mode_label.text = "模式: 【自由建造】"
	_mode_label.add_theme_font_size_override("font_size", 12)
	_mode_label.modulate = Color(0.4, 0.85, 1.0)
	bottom_box.add_child(_mode_label)

	bottom_box.add_child(VSeparator.new())

	_status_label = Label.new()
	_status_label.text = _status_text
	_status_label.add_theme_font_size_override("font_size", 12)
	bottom_box.add_child(_status_label)

	_build_save_load_dialog()
	_refresh_special_paths_ui()


func _make_dim_slider(label_text: String, min_val: int, max_val: int, init_val: int, callback: Callable) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var title := Label.new()
	title.text = "%s: %d" % [label_text, init_val]
	title.add_theme_font_size_override("font_size", 11)
	box.add_child(title)

	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.value = init_val
	slider.step = 1
	slider.value_changed.connect(func(v: float) -> void:
		var ival := int(v)
		title.text = "%s: %d" % [label_text, ival]
		callback.call(ival)
	)
	box.add_child(slider)
	return box


func _add_preset_btn(parent: Control, text: String, size: Vector3i) -> void:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(func() -> void:
		_current_block_size = size
		_update_block_info()
	)
	parent.add_child(btn)


func _update_block_info() -> void:
	if _block_info_label != null:
		_block_info_label.text = "当前: %s (%dx%dx%d)" % [
			_current_block_type, _current_block_size.x, _current_block_size.y, _current_block_size.z]


func _refresh_special_paths_ui() -> void:
	if _special_path_list_box == null:
		return
	for c in _special_path_list_box.get_children():
		c.queue_free()

	var paths := _nav.get_special_paths()
	if paths.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "暂无特殊路径\n按 R 进入玩家视角录制"
		empty_lbl.add_theme_font_size_override("font_size", 11)
		empty_lbl.modulate = Color(1, 1, 1, 0.45)
		_special_path_list_box.add_child(empty_lbl)
		return

	for p in paths:
		var p_dict: Dictionary = p
		var path_id: String = str(p_dict.get("id", ""))
		var from_arr: Array = p_dict.get("from", [0,0,0])
		var to_arr: Array = p_dict.get("to", [0,0,0])

		var card := PanelContainer.new()
		var card_style := StyleBoxFlat.new()
		card_style.bg_color = Color(0.18, 0.20, 0.25, 0.9)
		card_style.set_content_margin_all(6)
		card.add_theme_stylebox_override("panel", card_style)

		var card_vbox := VBoxContainer.new()
		card.add_child(card_vbox)

		var lbl := Label.new()
		lbl.text = "路径 (%d,%d,%d) -> (%d,%d,%d)" % [
			from_arr[0], from_arr[1], from_arr[2],
			to_arr[0], to_arr[1], to_arr[2]
		]
		lbl.add_theme_font_size_override("font_size", 11)
		card_vbox.add_child(lbl)

		var btns := HBoxContainer.new()
		card_vbox.add_child(btns)

		var test_btn := Button.new()
		test_btn.text = "NPC测试"
		test_btn.add_theme_font_size_override("font_size", 10)
		test_btn.pressed.connect(func() -> void:
			var target_pos := NavGrid.foot(Vector3i(to_arr[0], to_arr[1], to_arr[2]))
			_recalculate_npc_path(target_pos)
		)
		btns.add_child(test_btn)

		var del_btn := Button.new()
		del_btn.text = "删除"
		del_btn.add_theme_font_size_override("font_size", 10)
		del_btn.pressed.connect(func() -> void:
			_nav.remove_special_path(path_id)
			_redraw_special_paths()
			_refresh_special_paths_ui()
			_set_status("已删除特殊路径 %s" % path_id)
		)
		btns.add_child(del_btn)

		_special_path_list_box.add_child(card)


# --- Save/Load Dialog Modal -------------------------------------------------

func _build_save_load_dialog() -> void:
	_save_load_dialog = PanelContainer.new()
	_save_load_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_save_load_dialog.custom_minimum_size = Vector2(400, 320)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.18, 0.96)
	style.border_color = Color(0.35, 0.4, 0.5)
	style.set_border_width_all(1)
	style.set_content_margin_all(14)
	_save_load_dialog.add_theme_stylebox_override("panel", style)
	_save_load_dialog.visible = false
	_hud_canvas.add_child(_save_load_dialog)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_save_load_dialog.add_child(vbox)

	_dialog_title_label = Label.new()
	_dialog_title_label.text = "保存地图"
	_dialog_title_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_dialog_title_label)

	var name_box := HBoxContainer.new()
	vbox.add_child(name_box)
	name_box.add_child(Label.new())
	(name_box.get_child(0) as Label).text = "地图名称:"

	_map_name_edit = LineEdit.new()
	_map_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_name_edit.text = _map_name
	name_box.add_child(_map_name_edit)

	var list_lbl := Label.new()
	list_lbl.text = "已有地图存档列表:"
	list_lbl.add_theme_font_size_override("font_size", 12)
	vbox.add_child(list_lbl)

	_map_file_list = ItemList.new()
	_map_file_list.custom_minimum_size = Vector2(0, 140)
	_map_file_list.item_selected.connect(func(idx: int) -> void:
		var fn: String = _map_file_list.get_item_text(idx)
		_map_name_edit.text = fn.get_basename()
	)
	vbox.add_child(_map_file_list)

	var action_box := HBoxContainer.new()
	action_box.alignment = BoxContainer.ALIGNMENT_END
	action_box.add_theme_constant_override("separation", 10)
	vbox.add_child(action_box)

	var confirm_btn := Button.new()
	confirm_btn.text = "确认"
	confirm_btn.pressed.connect(_on_dialog_confirm)
	action_box.add_child(confirm_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.pressed.connect(func() -> void:
		_save_load_dialog.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	)
	action_box.add_child(cancel_btn)


func _open_save_dialog() -> void:
	_is_save_dialog = true
	_dialog_title_label.text = "保存地图 (Save Map)"
	_map_name_edit.text = _map_name
	_populate_map_list()
	_save_load_dialog.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _open_load_dialog() -> void:
	_is_save_dialog = false
	_dialog_title_label.text = "加载地图 (Load Map)"
	_populate_map_list()
	_save_load_dialog.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _populate_map_list() -> void:
	_map_file_list.clear()
	var maps := MapDataScript.list_available_maps()
	for m in maps:
		var fn: String = m.get("file_name", "")
		var name_str: String = m.get("name", "")
		var b_count: int = m.get("blocks_count", 0)
		var sp_count: int = m.get("special_paths_count", 0)
		var text := "%s (%s · %d 方块 · %d 特殊路径)" % [fn, name_str, b_count, sp_count]
		_map_file_list.add_item(text)
		_map_file_list.set_item_metadata(_map_file_list.item_count - 1, m.get("path", ""))


func _on_dialog_confirm() -> void:
	var chosen_name := _map_name_edit.text.strip_edges()
	if chosen_name.is_empty():
		chosen_name = "未命名地图"

	if _is_save_dialog:
		_map_name = chosen_name
		save_current_map(chosen_name)
	else:
		var selected := _map_file_list.get_selected_items()
		if selected.size() > 0:
			var path: String = str(_map_file_list.get_item_metadata(selected[0]))
			load_map(path)
		elif not chosen_name.is_empty():
			var fallback_path := MapDataScript.USER_MAPS_DIR.path_join(chosen_name + ".json")
			load_map(fallback_path)

	_save_load_dialog.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
