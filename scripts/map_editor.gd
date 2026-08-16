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
const NavGridScript = preload("res://scripts/nav_grid.gd")

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
var _nav = NavGridScript.new()
var _recorder = SpecialPathRecorderScript.new()

## Visual helpers and path meshes.
var _path_mesh_instance: MeshInstance3D
var _path_immediate_mesh: ImmediateMesh
var _special_paths_mesh_instance: MeshInstance3D
var _special_paths_mesh: ImmediateMesh
var _beacon_instance: Node3D

## Special path hover aiming and double-tap X deletion.
var _hovered_special_path_id := ""
var _last_x_press_time := -1000.0
var _last_x_target_id := ""
const DOUBLE_TAP_WINDOW := 0.45
const SPECIAL_PATH_RAY_TOLERANCE := 0.50

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
const FONT_PATH := "res://assets/Fonts/Long_Cang/LongCang-Regular.ttf"
const AudioManagerScript = preload("res://scripts/audio_manager.gd")

var _custom_font: Font = null
static var tutorial_on_start := false

var _interactive_tutorial_active := false
var _tutorial_step := 0
var _interactive_banner: PanelContainer
var _interactive_banner_style: StyleBoxFlat
var _interactive_banner_icon: TextureRect
var _interactive_banner_title: Label
var _interactive_banner_sub: Label
var _interactive_complete_dialog: PanelContainer
var _tutorial_arrow: Node3D = null
var _tutorial_arrow_base_pos: Vector3 = Vector3.ZERO
var _tutorial_arrow_time: float = 0.0

var _hud_canvas: CanvasLayer
var _top_panel: PanelContainer
var _left_panel: PanelContainer
var _right_panel: PanelContainer
var _bottom_panel: PanelContainer
var _ui_panels_visible := true

var _tutorial_dialog: PanelContainer
var _tutorial_page := 0
var _tutorial_title_lbl: Label
var _tutorial_page_lbl: Label
var _tutorial_content_box: VBoxContainer
var _tutorial_prev_btn: Button
var _tutorial_next_btn: Button

var _status_label: Label
var _mode_label: Label
var _block_info_label: Label
var _special_path_list_box: VBoxContainer
var _recording_banner: PanelContainer
var _recording_banner_style: StyleBoxFlat
var _recording_banner_title: Label
var _recording_banner_sub: Label
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
	AudioManagerScript.init_pool(self)
	if ResourceLoader.exists(FONT_PATH):
		_custom_font = load(FONT_PATH) as Font

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

	if tutorial_on_start:
		tutorial_on_start = false
		start_interactive_tutorial()


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

	_build_tutorial_arrow()

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
		_on_npc_arrived_destination(_t)
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
			if _recording_banner != null:
				_recording_banner.visible = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_mode_label.text = "模式: 【自由建造】 (按 TAB 试玩, 按 R 录制特殊跳跃, 准星对准轨迹连按两下 X 删除)"
			_set_status("准星瞄准：左键放置，右键删除方块，连按两下 X 删除特殊轨迹，Shift+左键 指定人机寻路")
		EditorMode.PLAY_TEST:
			_npc.intent_source = _player_intent_source
			_follow_camera.current = true
			_highlight.visible = false
			_ghost.visible = false
			_has_aim = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_mode_label.text = "模式: 【操控试玩】 (按 R 录制特殊跳跃, 按 TAB 返回自由建造)"
			_set_status("WASD移动，Shift加速，Space跳跃，按 R 开启特殊路径录制")
			if _interactive_tutorial_active and _tutorial_step == 3:
				_advance_interactive_tutorial(4)
		EditorMode.RECORD_SPECIAL_PATH:
			_npc.intent_source = _player_intent_source
			_follow_camera.current = true
			_highlight.visible = false
			_ghost.visible = false
			_has_aim = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_mode_label.text = "模式: 【特殊路径录制】 (按 ESC / R 取消录制)"
			_recorder.start_recording()
			_update_recording_hud(SpecialPathRecorderScript.State.ARMED_WAITING_FOR_REST, "请在起点格保持完全静止...")


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
	if _tutorial_arrow != null and _tutorial_arrow.visible:
		_tutorial_arrow_time += delta
		_tutorial_arrow.position = _tutorial_arrow_base_pos + Vector3(0.0, 0.45 + sin(_tutorial_arrow_time * 5.0) * 0.15, 0.0)
		_tutorial_arrow.rotation.y += delta * 2.5


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
				KEY_B:
					get_viewport().set_input_as_handled()
					_toggle_ui_panels_mode()
					return
				KEY_TAB:
					get_viewport().set_input_as_handled()
					if _mode == EditorMode.BUILD:
						_set_mode(EditorMode.PLAY_TEST)
					elif _mode == EditorMode.PLAY_TEST:
						_set_mode(EditorMode.BUILD)
					return
				KEY_R:
					get_viewport().set_input_as_handled()
					if _mode == EditorMode.RECORD_SPECIAL_PATH:
						_recorder.cancel_recording()
						_set_mode(EditorMode.PLAY_TEST)
						_update_recording_hud(SpecialPathRecorderScript.State.IDLE, "用户取消了本次录制", true)
						_set_status("已取消录制，按 R 重新录制，按 TAB 返回建造")
					else:
						_set_mode(EditorMode.RECORD_SPECIAL_PATH)
					return
				KEY_X:
					if _mode == EditorMode.BUILD:
						get_viewport().set_input_as_handled()
						_handle_x_double_tap()
						return
				KEY_ESCAPE:
					get_viewport().set_input_as_handled()
					if _interactive_complete_dialog != null and _interactive_complete_dialog.visible:
						_interactive_complete_dialog.visible = false
						_interactive_tutorial_active = false
						if _interactive_banner != null:
							_interactive_banner.visible = false
						_update_ui_panels_visibility()
						return
					if _tutorial_dialog != null and _tutorial_dialog.visible:
						_close_tutorial_dialog()
						return
					if _save_load_dialog != null and _save_load_dialog.visible:
						_save_load_dialog.visible = false
						_update_ui_panels_visibility()
						return
					if _mode != EditorMode.BUILD:
						_recorder.cancel_recording()
						_set_mode(EditorMode.BUILD)
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

	_update_special_path_aim(origin, direction)

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


func _update_special_path_aim(origin: Vector3, direction: Vector3) -> void:
	var prev_hovered := _hovered_special_path_id
	var best_dist := SPECIAL_PATH_RAY_TOLERANCE
	var best_id := ""

	var paths := _nav.get_special_paths()
	for p in paths:
		var path_id: String = str(p.get("id", ""))
		var traj: Array = p.get("trajectory", [])
		if traj.size() >= 2:
			for i in range(1, traj.size()):
				var s1 = traj[i - 1]
				var s2 = traj[i]
				var p1 := _vec3_from_raw(s1.get("p") if s1 is Dictionary else s1) + Vector3(0.0, 0.06, 0.0)
				var p2 := _vec3_from_raw(s2.get("p") if s2 is Dictionary else s2) + Vector3(0.0, 0.06, 0.0)
				var dist := _ray_to_segment_dist(origin, direction, p1, p2, BUILD_REACH)
				if dist >= 0.0 and dist < best_dist:
					best_dist = dist
					best_id = path_id
		else:
			var from_c: Vector3i = NavGrid._parse_coord(p.get("from"))
			var to_c: Vector3i = NavGrid._parse_coord(p.get("to"))
			var f1 := NavGrid.foot(from_c) + Vector3(0.0, 0.15, 0.0)
			var f2 := NavGrid.foot(to_c) + Vector3(0.0, 0.15, 0.0)
			var dist := _ray_to_segment_dist(origin, direction, f1, f2, BUILD_REACH)
			if dist >= 0.0 and dist < best_dist:
				best_dist = dist
				best_id = path_id

	_hovered_special_path_id = best_id
	if _hovered_special_path_id != prev_hovered:
		_redraw_special_paths()
		if _hovered_special_path_id != "":
			_set_status("已对准特殊路径 · 连续按两次 X 可快速删除")


func _handle_x_double_tap() -> void:
	if _hovered_special_path_id == "":
		_set_status("提示：请将十字准星对准特殊路径线条，连续按两次 X 删除")
		return

	var now := float(Time.get_ticks_msec()) * 0.001
	if (now - _last_x_press_time) <= DOUBLE_TAP_WINDOW and _last_x_target_id == _hovered_special_path_id:
		var del_id := _hovered_special_path_id
		_nav.remove_special_path(del_id)
		_hovered_special_path_id = ""
		_last_x_press_time = -1000.0
		_last_x_target_id = ""
		_redraw_special_paths()
		_refresh_special_paths_ui()
		_set_status("已成功删除特殊路径：%s" % del_id)
	else:
		_last_x_press_time = now
		_last_x_target_id = _hovered_special_path_id
		_set_status("⚠️ 再次按下 X 确认删除当前瞄准的特殊路径！")


static func _ray_to_segment_dist(ray_origin: Vector3, ray_dir: Vector3,
		seg_a: Vector3, seg_b: Vector3, max_reach: float) -> float:
	var u := seg_b - seg_a
	var seg_len_sq := u.length_squared()
	if seg_len_sq < 0.000001:
		var to_pt := seg_a - ray_origin
		var proj := to_pt.dot(ray_dir)
		if proj < 0.2 or proj > max_reach:
			return -1.0
		return (ray_origin + ray_dir * proj).distance_to(seg_a)

	var w0 := ray_origin - seg_a
	var b := ray_dir.dot(u)
	var c := seg_len_sq
	var d := ray_dir.dot(w0)
	var e := u.dot(w0)
	var denom := c - b * b

	var s: float = 0.0
	var t: float = 0.0

	if denom < 0.000001:
		t = 0.0
		s = clampf(-d, 0.2, max_reach)
	else:
		t = clampf((e - b * d) / denom, 0.0, 1.0)
		s = clampf(t * b - d, 0.2, max_reach)
		t = clampf((s * b + e) / c, 0.0, 1.0)

	var pt_ray := ray_origin + ray_dir * s
	var pt_seg := seg_a + u * t
	return pt_ray.distance_to(pt_seg)


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
	if _interactive_tutorial_active and _tutorial_step == 1:
		_set_status("【任务 2/6】请先拆除上方浮动箭头指示的方块，暂不可放置新方块哦")
		return

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

	if _interactive_tutorial_active and _tutorial_step == 0:
		var center_pos := Vector3(
			float(grid_pos.x) + float(_current_block_size.x) * 0.5,
			float(grid_pos.y) + float(_current_block_size.y),
			float(grid_pos.z) + float(_current_block_size.z) * 0.5
		)
		_show_tutorial_arrow_at(center_pos)
		_advance_interactive_tutorial(1)


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

	if _interactive_tutorial_active and _tutorial_step == 1:
		_hide_tutorial_arrow()
		_advance_interactive_tutorial(2)


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
	_set_mode(EditorMode.PLAY_TEST)
	var from_arr: Array = path_data.get("from", [0, 0, 0])
	var to_arr: Array = path_data.get("to", [0, 0, 0])
	var traj_count: int = (path_data.get("trajectory", []) as Array).size()
	var msg := "起点 (%d,%d,%d) -> 终点 (%d,%d,%d) · 共 %d 帧" % [
		from_arr[0], from_arr[1], from_arr[2],
		to_arr[0], to_arr[1], to_arr[2],
		traj_count
	]
	_update_recording_hud(SpecialPathRecorderScript.State.COMPLETED, msg)
	_set_status("特殊跳跃录制成功！按 R 继续录制下一条，按 TAB 切换自由建造")

	if _interactive_tutorial_active and _tutorial_step == 4:
		# Reset character back to starting platform (Platform 1)
		_npc.global_position = Vector3(1.0, 1.2, 1.0)
		_npc.velocity = Vector3.ZERO
		_follow_camera.snap()
		_advance_interactive_tutorial(5)


func _on_special_path_failed(reason: String) -> void:
	_set_mode(EditorMode.PLAY_TEST)
	_update_recording_hud(SpecialPathRecorderScript.State.IDLE, reason, true)
	_set_status("录制未完成/取消：%s" % reason)


func _on_recorder_state_changed(state: int, message: String) -> void:
	_set_status(message)
	_update_recording_hud(state, message)


func _redraw_special_paths() -> void:
	_special_paths_mesh.clear_surfaces()
	var paths := _nav.get_special_paths()
	if paths.is_empty():
		return

	_special_paths_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for p_idx in range(paths.size()):
		var p: Dictionary = paths[p_idx]
		var path_id: String = str(p.get("id", ""))
		var is_hovered := (path_id != "" and path_id == _hovered_special_path_id)
		var traj: Array = p.get("trajectory", [])
		var hue: float = fposmod(float(p_idx) * 0.31, 1.0)
		var base_col := Color(1.0, 0.95, 0.25, 1.0) if is_hovered else Color.from_hsv(hue, 0.85, 0.95, 0.95)
		if traj.size() >= 2:
			for i in range(1, traj.size()):
				var s1 = traj[i - 1]
				var s2 = traj[i]
				var p1 := _vec3_from_raw(s1.get("p") if s1 is Dictionary else s1)
				var p2 := _vec3_from_raw(s2.get("p") if s2 is Dictionary else s2)
				var is_air := not bool(s2.get("grounded", true)) if s2 is Dictionary else true
				var col := base_col if (is_hovered or is_air) else base_col.lerp(Color(0.2, 1.0, 0.5), 0.45)
				_special_paths_mesh.surface_set_color(col)
				_special_paths_mesh.surface_add_vertex(p1 + Vector3(0.0, 0.06, 0.0))
				_special_paths_mesh.surface_set_color(col)
				_special_paths_mesh.surface_add_vertex(p2 + Vector3(0.0, 0.06, 0.0))

				if is_hovered:
					# Extra prominent visual indicator along hovered trajectory
					var tick := Vector3(0.0, 0.12, 0.0)
					_special_paths_mesh.surface_set_color(Color(1.0, 1.0, 1.0, 0.9))
					_special_paths_mesh.surface_add_vertex(p2 + Vector3(0.0, 0.06, 0.0))
					_special_paths_mesh.surface_set_color(Color(1.0, 1.0, 1.0, 0.9))
					_special_paths_mesh.surface_add_vertex(p2 + Vector3(0.0, 0.06, 0.0) + tick)
		else:
			var from_c: Vector3i = NavGrid._parse_coord(p.get("from"))
			var to_c: Vector3i = NavGrid._parse_coord(p.get("to"))
			var f1 := NavGrid.foot(from_c) + Vector3(0.0, 0.15, 0.0)
			var f2 := NavGrid.foot(to_c) + Vector3(0.0, 0.15, 0.0)
			_special_paths_mesh.surface_set_color(base_col)
			_special_paths_mesh.surface_add_vertex(f1)
			_special_paths_mesh.surface_set_color(base_col)
			_special_paths_mesh.surface_add_vertex(f2)
	_special_paths_mesh.surface_end()


static func _vec3_from_raw(raw: Variant) -> Vector3:
	if raw is Vector3:
		return raw
	if raw is Array and (raw as Array).size() >= 3:
		var a: Array = raw
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


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
	var links: Dictionary = result.get("special_links", {})
	if links.is_empty():
		_set_status("已规划路径：包含 %d 个航路点 (按 TAB 可切至测试操控)" % points.size())
	else:
		_set_status("已规划路径：包含 %d 个航路点，其中 %d 段将逐帧复刻录制的特殊跳跃" % [
			points.size(), links.size()])

	if _interactive_tutorial_active:
		if _tutorial_step == 2:
			if _interactive_banner != null:
				_interactive_banner_title.text = "🎯 新手任务 (3/6): 正在寻路..."
				_interactive_banner_sub.text = "👀 人机已启动动力学规划寻路，请静静观察其移动路线与落点！"
		elif _tutorial_step == 5:
			_advance_interactive_tutorial(6)


func _on_repath_requested(from_pos: Vector3, target: Vector3) -> void:
	var result := _nav.find_path(from_pos, target)
	if result.points.is_empty():
		_npc_intent_source.clear_target()
		_set_status("NPC 受阻且无可用重寻路路径")
		return
	_npc_intent_source.set_plan_result(result)
	_draw_path(result.points, result.moves)


func _test_specific_special_path(p_dict: Dictionary) -> void:
	var from_arr: Array = p_dict.get("from", [0, 0, 0])
	var to_arr: Array = p_dict.get("to", [0, 0, 0])
	var from_cell := Vector3i(int(from_arr[0]), int(from_arr[1]), int(from_arr[2]))
	var to_cell := Vector3i(int(to_arr[0]), int(to_arr[1]), int(to_arr[2]))

	var rest_raw = p_dict.get("rest_pos")
	var rest_pos := _vec3_from_raw(rest_raw)
	if rest_pos == Vector3.ZERO:
		rest_pos = NavGrid.foot(from_cell)
	var rest_heading: float = float(p_dict.get("rest_heading", 0.0))

	# Position NPC at exact recorded rest point and orient heading
	_npc.global_position = rest_pos
	_npc.velocity = Vector3.ZERO
	_npc.rotation.y = rest_heading

	var target_pos := NavGrid.foot(to_cell)
	var points := PackedVector3Array([NavGrid.foot(from_cell), target_pos])
	var moves := PackedInt32Array([NavGrid.Move.WALK, NavGrid.Move.SPECIAL_JUMP])
	var special_links := {1: p_dict}

	var plan := {
		"points": points,
		"moves": moves,
		"goal": target_pos,
		"complete": true,
		"special_links": special_links,
	}

	_npc_intent_source.set_plan_result(plan)
	_draw_path(points, moves)
	_beacon_instance.global_position = target_pos
	_beacon_instance.visible = true
	var traj_size: int = (p_dict.get("trajectory", []) as Array).size()
	_set_status("正在精准测试特殊路径: (%d,%d,%d) -> (%d,%d,%d) · %d 帧轨迹" % [
		from_cell.x, from_cell.y, from_cell.z,
		to_cell.x, to_cell.y, to_cell.z,
		traj_size
	])


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
	_top_panel = PanelContainer.new()
	_top_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top_panel.custom_minimum_size = Vector2(0, 48)
	var top_style := StyleBoxFlat.new()
	top_style.bg_color = Color(0.1, 0.12, 0.15, 0.92)
	top_style.set_content_margin_all(8)
	_top_panel.add_theme_stylebox_override("panel", top_style)
	_hud_canvas.add_child(_top_panel)

	var top_box := HBoxContainer.new()
	top_box.add_theme_constant_override("separation", 10)
	_top_panel.add_child(top_box)

	var title_lbl := Label.new()
	title_lbl.text = "灰烬:启程 · 地图工坊"
	if _custom_font != null:
		title_lbl.add_theme_font_override("font", _custom_font)
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.modulate = Color(1.0, 0.88, 0.35)
	top_box.add_child(title_lbl)

	top_box.add_child(VSeparator.new())

	var guide_btn := Button.new()
	guide_btn.text = "📖 特殊操作指南"
	if _custom_font != null:
		guide_btn.add_theme_font_override("font", _custom_font)
	guide_btn.pressed.connect(func() -> void: _open_tutorial_dialog(0))
	top_box.add_child(guide_btn)

	var b_toggle_btn := Button.new()
	b_toggle_btn.text = "切换沉浸/面板 (B)"
	if _custom_font != null:
		b_toggle_btn.add_theme_font_override("font", _custom_font)
	b_toggle_btn.pressed.connect(_toggle_ui_panels_mode)
	top_box.add_child(b_toggle_btn)

	top_box.add_child(VSeparator.new())

	var new_btn := Button.new()
	new_btn.text = "新建 (New)"
	if _custom_font != null:
		new_btn.add_theme_font_override("font", _custom_font)
	new_btn.pressed.connect(new_map)
	top_box.add_child(new_btn)

	var save_btn := Button.new()
	save_btn.text = "保存 (Save)"
	if _custom_font != null:
		save_btn.add_theme_font_override("font", _custom_font)
	save_btn.pressed.connect(func() -> void: _open_save_dialog())
	top_box.add_child(save_btn)

	var load_btn := Button.new()
	load_btn.text = "加载 (Load)"
	if _custom_font != null:
		load_btn.add_theme_font_override("font", _custom_font)
	load_btn.pressed.connect(func() -> void: _open_load_dialog())
	top_box.add_child(load_btn)

	var clear_btn := Button.new()
	clear_btn.text = "清空方块"
	if _custom_font != null:
		clear_btn.add_theme_font_override("font", _custom_font)
	clear_btn.pressed.connect(_clear_all_blocks)
	top_box.add_child(clear_btn)

	top_box.add_child(VSeparator.new())

	var play_btn := Button.new()
	play_btn.text = "操控试玩 (TAB)"
	if _custom_font != null:
		play_btn.add_theme_font_override("font", _custom_font)
	play_btn.pressed.connect(func() -> void: _set_mode(EditorMode.PLAY_TEST))
	top_box.add_child(play_btn)

	var rec_btn := Button.new()
	rec_btn.text = "录制特殊跳跃 (R)"
	if _custom_font != null:
		rec_btn.add_theme_font_override("font", _custom_font)
	rec_btn.pressed.connect(func() -> void: _set_mode(EditorMode.RECORD_SPECIAL_PATH))
	top_box.add_child(rec_btn)

	top_box.add_child(VSeparator.new())

	var menu_btn := Button.new()
	menu_btn.text = "返回 (ESC)"
	if _custom_font != null:
		menu_btn.add_theme_font_override("font", _custom_font)
	menu_btn.pressed.connect(func() -> void:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file(MENU_SCENE)
	)
	top_box.add_child(menu_btn)

	# Left Sidebar: Block Palette and Dimensions
	_left_panel = PanelContainer.new()
	_left_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_left_panel.offset_top = 56
	_left_panel.offset_bottom = -36
	_left_panel.custom_minimum_size = Vector2(230, 0)
	var left_style := StyleBoxFlat.new()
	left_style.bg_color = Color(0.11, 0.13, 0.16, 0.88)
	left_style.set_content_margin_all(10)
	_left_panel.add_theme_stylebox_override("panel", left_style)
	_hud_canvas.add_child(_left_panel)

	var left_scroll := ScrollContainer.new()
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_left_panel.add_child(left_scroll)

	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.add_theme_constant_override("separation", 8)
	left_scroll.add_child(left_vbox)

	var palette_lbl := Label.new()
	palette_lbl.text = "方块种类 (Type)"
	if _custom_font != null:
		palette_lbl.add_theme_font_override("font", _custom_font)
	palette_lbl.add_theme_font_size_override("font_size", 15)
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

	var size_lbl := Label.new()
	size_lbl.text = "方块尺寸 (Size X Y Z)"
	if _custom_font != null:
		size_lbl.add_theme_font_override("font", _custom_font)
	size_lbl.add_theme_font_size_override("font_size", 15)
	left_vbox.add_child(size_lbl)

	var presets_lbl := Label.new()
	presets_lbl.text = "快捷尺寸预设:"
	if _custom_font != null:
		presets_lbl.add_theme_font_override("font", _custom_font)
	presets_lbl.add_theme_font_size_override("font_size", 13)
	presets_lbl.modulate = Color(1, 1, 1, 0.7)
	left_vbox.add_child(presets_lbl)

	var preset_grid := GridContainer.new()
	preset_grid.columns = 2
	preset_grid.add_theme_constant_override("h_separation", 6)
	preset_grid.add_theme_constant_override("v_separation", 6)
	left_vbox.add_child(preset_grid)

	var presets: Array = [
		{"label": "1x1x1 标准", "size": Vector3i(1, 1, 1)},
		{"label": "2x1x1 平台", "size": Vector3i(2, 1, 1)},
		{"label": "1x2x1 立柱", "size": Vector3i(1, 2, 1)},
		{"label": "2x2x1 方台", "size": Vector3i(2, 2, 1)},
		{"label": "3x1x1 长条", "size": Vector3i(3, 1, 1)},
		{"label": "2x2x2 大块", "size": Vector3i(2, 2, 2)},
		{"label": "4x1x2 高台", "size": Vector3i(4, 1, 2)},
		{"label": "1x3x1 高柱", "size": Vector3i(1, 3, 1)},
	]
	for p in presets:
		var p_btn := Button.new()
		p_btn.text = p.label
		if _custom_font != null:
			p_btn.add_theme_font_override("font", _custom_font)
		p_btn.custom_minimum_size = Vector2(95, 28)
		p_btn.add_theme_font_size_override("font_size", 12)
		var p_size: Vector3i = p.size
		p_btn.pressed.connect(func() -> void:
			_current_block_size = p_size
			_update_block_info()
		)
		preset_grid.add_child(p_btn)

	var custom_grid := GridContainer.new()
	custom_grid.columns = 2
	left_vbox.add_child(custom_grid)

	custom_grid.add_child(_make_label("X (长):"))
	var spin_x := SpinBox.new()
	spin_x.min_value = 1
	spin_x.max_value = 16
	spin_x.value = _current_block_size.x
	spin_x.value_changed.connect(func(v: float) -> void:
		_current_block_size.x = int(v)
		_update_block_info()
	)
	custom_grid.add_child(spin_x)

	custom_grid.add_child(_make_label("Y (高):"))
	var spin_y := SpinBox.new()
	spin_y.min_value = 1
	spin_y.max_value = 12
	spin_y.value = _current_block_size.y
	spin_y.value_changed.connect(func(v: float) -> void:
		_current_block_size.y = int(v)
		_update_block_info()
	)
	custom_grid.add_child(spin_y)

	custom_grid.add_child(_make_label("Z (宽):"))
	var spin_z := SpinBox.new()
	spin_z.min_value = 1
	spin_z.max_value = 16
	spin_z.value = _current_block_size.z
	spin_z.value_changed.connect(func(v: float) -> void:
		_current_block_size.z = int(v)
		_update_block_info()
	)
	custom_grid.add_child(spin_z)

	_block_info_label = Label.new()
	_block_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _custom_font != null:
		_block_info_label.add_theme_font_override("font", _custom_font)
	_block_info_label.add_theme_font_size_override("font_size", 12)
	_block_info_label.modulate = Color(0.3, 0.9, 1.0)
	left_vbox.add_child(_block_info_label)
	_update_block_info()

	# Right Sidebar: Special Paths List and Management
	_right_panel = PanelContainer.new()
	_right_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_right_panel.offset_top = 56
	_right_panel.offset_bottom = -36
	_right_panel.custom_minimum_size = Vector2(250, 0)
	var right_style := StyleBoxFlat.new()
	right_style.bg_color = Color(0.11, 0.13, 0.16, 0.88)
	right_style.set_content_margin_all(10)
	_right_panel.add_theme_stylebox_override("panel", right_style)
	_hud_canvas.add_child(_right_panel)

	var right_scroll := ScrollContainer.new()
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_right_panel.add_child(right_scroll)

	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 8)
	right_scroll.add_child(right_vbox)

	var sp_title := Label.new()
	sp_title.text = "特殊路径连接 (Special Paths)"
	if _custom_font != null:
		sp_title.add_theme_font_override("font", _custom_font)
	sp_title.add_theme_font_size_override("font_size", 15)
	right_vbox.add_child(sp_title)

	var sp_hint := Label.new()
	sp_hint.text = "准星对准空中绿线，连按两下 X 可精准删除"
	sp_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _custom_font != null:
		sp_hint.add_theme_font_override("font", _custom_font)
	sp_hint.add_theme_font_size_override("font_size", 12)
	sp_hint.modulate = Color(1, 1, 1, 0.6)
	right_vbox.add_child(sp_hint)

	_special_path_list_box = VBoxContainer.new()
	_special_path_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_special_path_list_box.add_theme_constant_override("separation", 6)
	right_vbox.add_child(_special_path_list_box)

	# Bottom Status Bar
	_bottom_panel = PanelContainer.new()
	_bottom_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bottom_panel.custom_minimum_size = Vector2(0, 36)
	var bottom_style := StyleBoxFlat.new()
	bottom_style.bg_color = Color(0.08, 0.09, 0.11, 0.95)
	bottom_style.set_content_margin_all(6)
	_bottom_panel.add_theme_stylebox_override("panel", bottom_style)
	_hud_canvas.add_child(_bottom_panel)

	var bottom_box := HBoxContainer.new()
	_bottom_panel.add_child(bottom_box)

	_mode_label = Label.new()
	_mode_label.text = "模式: 【自由建造】"
	if _custom_font != null:
		_mode_label.add_theme_font_override("font", _custom_font)
	_mode_label.add_theme_font_size_override("font_size", 13)
	_mode_label.modulate = Color(0.4, 0.85, 1.0)
	bottom_box.add_child(_mode_label)

	bottom_box.add_child(VSeparator.new())

	var b_hint_lbl := Label.new()
	b_hint_lbl.text = "[B 键]: 切换面板/沉浸模式"
	if _custom_font != null:
		b_hint_lbl.add_theme_font_override("font", _custom_font)
	b_hint_lbl.add_theme_font_size_override("font_size", 13)
	b_hint_lbl.modulate = Color(1.0, 0.85, 0.3)
	bottom_box.add_child(b_hint_lbl)

	bottom_box.add_child(VSeparator.new())

	_status_label = Label.new()
	_status_label.text = _status_text
	if _custom_font != null:
		_status_label.add_theme_font_override("font", _custom_font)
	_status_label.add_theme_font_size_override("font_size", 13)
	bottom_box.add_child(_status_label)

	_build_recording_banner()
	_build_save_load_dialog()
	_build_tutorial_dialog()
	_build_interactive_tutorial_hud()
	_refresh_special_paths_ui()


func _build_interactive_tutorial_hud() -> void:
	_interactive_banner = PanelContainer.new()
	_interactive_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_interactive_banner.offset_left = -340
	_interactive_banner.offset_right = 340
	_interactive_banner.offset_top = 58
	_interactive_banner.offset_bottom = 150
	_interactive_banner.custom_minimum_size = Vector2(680, 92)
	_interactive_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interactive_banner.visible = false

	_interactive_banner_style = StyleBoxFlat.new()
	_interactive_banner_style.bg_color = Color(0.09, 0.12, 0.17, 0.96)
	_interactive_banner_style.set_corner_radius_all(10)
	_interactive_banner_style.set_border_width_all(2)
	_interactive_banner_style.border_color = Color(1.0, 0.85, 0.25)
	_interactive_banner_style.set_content_margin_all(12)
	_interactive_banner.add_theme_stylebox_override("panel", _interactive_banner_style)
	_hud_canvas.add_child(_interactive_banner)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 14)
	_interactive_banner.add_child(hbox)

	_interactive_banner_icon = TextureRect.new()
	if ResourceLoader.exists("res://assets/UI_assets/cubes.svg"):
		_interactive_banner_icon.texture = load("res://assets/UI_assets/cubes.svg")
	_interactive_banner_icon.custom_minimum_size = Vector2(46, 46)
	_interactive_banner_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_interactive_banner_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_interactive_banner_icon.modulate = Color(1.0, 0.85, 0.25)
	hbox.add_child(_interactive_banner_icon)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(vbox)

	_interactive_banner_title = Label.new()
	if _custom_font != null:
		_interactive_banner_title.add_theme_font_override("font", _custom_font)
	_interactive_banner_title.add_theme_font_size_override("font_size", 20)
	_interactive_banner_title.modulate = Color(1.0, 0.88, 0.3)
	vbox.add_child(_interactive_banner_title)

	_interactive_banner_sub = Label.new()
	_interactive_banner_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _custom_font != null:
		_interactive_banner_sub.add_theme_font_override("font", _custom_font)
	_interactive_banner_sub.add_theme_font_size_override("font_size", 14)
	_interactive_banner_sub.modulate = Color(0.9, 0.92, 0.96)
	vbox.add_child(_interactive_banner_sub)

	_build_interactive_complete_dialog()


func _build_interactive_complete_dialog() -> void:
	_interactive_complete_dialog = PanelContainer.new()
	_interactive_complete_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_interactive_complete_dialog.offset_left = -290
	_interactive_complete_dialog.offset_right = 290
	_interactive_complete_dialog.offset_top = -180
	_interactive_complete_dialog.offset_bottom = 180
	_interactive_complete_dialog.custom_minimum_size = Vector2(580, 360)
	_interactive_complete_dialog.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.16, 0.98)
	style.set_corner_radius_all(12)
	style.set_border_width_all(2)
	style.border_color = Color(0.3, 0.9, 0.6)
	style.set_content_margin_all(22)
	_interactive_complete_dialog.add_theme_stylebox_override("panel", style)
	_hud_canvas.add_child(_interactive_complete_dialog)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	_interactive_complete_dialog.add_child(vbox)

	var icon := TextureRect.new()
	if ResourceLoader.exists("res://assets/UI_assets/freedom-dove.svg"):
		icon.texture = load("res://assets/UI_assets/freedom-dove.svg")
	icon.custom_minimum_size = Vector2(56, 56)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Color(0.3, 0.9, 0.6)
	vbox.add_child(icon)

	var title := Label.new()
	title.text = "🎉 恭喜！新手互动教学圆满完成！"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _custom_font != null:
		title.add_theme_font_override("font", _custom_font)
	title.add_theme_font_size_override("font_size", 24)
	title.modulate = Color(0.3, 0.9, 0.6)
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = "您已成功掌握方块搭建、物理寻路测试、极限跳跃录制与 AI 智能复现！\n\n💡 核心秘籍：随时按【B 键】可在【属性面板（鼠标指针工作）】与【沉浸自由视角】之间一键切换！"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _custom_font != null:
		desc.add_theme_font_override("font", _custom_font)
	desc.add_theme_font_size_override("font_size", 14)
	desc.modulate = Color(0.88, 0.92, 0.96)
	vbox.add_child(desc)

	var finish_btn := Button.new()
	finish_btn.text = "开始自由探索创作 (Start)"
	if _custom_font != null:
		finish_btn.add_theme_font_override("font", _custom_font)
	finish_btn.add_theme_font_size_override("font_size", 16)
	finish_btn.custom_minimum_size = Vector2(220, 42)
	finish_btn.pressed.connect(func() -> void:
		_interactive_complete_dialog.visible = false
		_interactive_tutorial_active = false
		_interactive_banner.visible = false
		_update_ui_panels_visibility()
	)
	vbox.add_child(finish_btn)


func start_interactive_tutorial() -> void:
	_interactive_tutorial_active = true
	_ui_panels_visible = false
	_update_ui_panels_visibility()
	_set_mode(EditorMode.BUILD)
	_advance_interactive_tutorial(0)


func _on_npc_arrived_destination(_target: Vector3) -> void:
	if not _interactive_tutorial_active:
		return
	if _tutorial_step == 2:
		if _interactive_banner != null:
			_interactive_banner_icon.modulate = Color(0.3, 0.9, 0.6)
			_interactive_banner_title.text = "🎯 新手任务 (3/6): 寻路抵达！"
			_interactive_banner_sub.text = "✅ 人机已按物理规划成功抵达目标点！停留 2 秒即将进入下一阶段..."
		await get_tree().create_timer(2.0).timeout
		if _interactive_tutorial_active and _tutorial_step == 2:
			_advance_interactive_tutorial(3)


func _advance_interactive_tutorial(step: int) -> void:
	_tutorial_step = step
	if _interactive_banner == null:
		return
	_interactive_banner.visible = true

	match step:
		0:
			if ResourceLoader.exists("res://assets/UI_assets/cubes.svg"):
				_interactive_banner_icon.texture = load("res://assets/UI_assets/cubes.svg")
				_interactive_banner_icon.modulate = Color(0.3, 0.85, 1.0)
			_interactive_banner_title.text = "🎯 新手任务 (1/6): 放置方块"
			_interactive_banner_sub.text = "准星对准地面任意网格，点击【鼠标左键 (LMB)】放置一个方块。"
			_interactive_banner_style.border_color = Color(0.3, 0.85, 1.0)
			_set_status("【任务 1/6】点击鼠标左键放置方块")

		1:
			if ResourceLoader.exists("res://assets/UI_assets/cross-mark.svg"):
				_interactive_banner_icon.texture = load("res://assets/UI_assets/cross-mark.svg")
				_interactive_banner_icon.modulate = Color(1.0, 0.4, 0.4)
			_interactive_banner_title.text = "🎯 新手任务 (2/6): 拆除方块"
			_interactive_banner_sub.text = "太棒了！现在准星对准刚才放置的方块，点击【鼠标右键 (RMB)】将其拆除。"
			_interactive_banner_style.border_color = Color(1.0, 0.4, 0.4)
			_set_status("【任务 2/6】准星对准方块点击鼠标右键拆除")

		2:
			if ResourceLoader.exists("res://assets/UI_assets/run.svg"):
				_interactive_banner_icon.texture = load("res://assets/UI_assets/run.svg")
				_interactive_banner_icon.modulate = Color(0.3, 0.9, 0.6)
			_interactive_banner_title.text = "🎯 新手任务 (3/6): 人机智能寻路"
			_interactive_banner_sub.text = "人机拥有强大的物理能力寻路！按住【Shift + 鼠标左键】点击地面较远处，指挥 NPC 走过去。"
			_interactive_banner_style.border_color = Color(0.3, 0.9, 0.6)
			_set_status("【任务 3/6】按住 Shift 点击左键测试 NPC 寻路")

		3:
			_spawn_tutorial_glowing_platforms()
			if ResourceLoader.exists("res://assets/UI_assets/cctv-camera.svg"):
				_interactive_banner_icon.texture = load("res://assets/UI_assets/cctv-camera.svg")
				_interactive_banner_icon.modulate = Color(1.0, 0.85, 0.25)
			_interactive_banner_title.text = "🎯 新手任务 (4/6): 切换自身操控"
			_interactive_banner_sub.text = "场景中央已生成两座测试跳台！按【TAB 键】切换为自己操控角色，并站到起点方块上方。"
			_interactive_banner_style.border_color = Color(1.0, 0.85, 0.25)
			_set_status("【任务 4/6】按 TAB 键切换为自身操控")

		4:
			if ResourceLoader.exists("res://assets/UI_assets/digital-trace.svg"):
				_interactive_banner_icon.texture = load("res://assets/UI_assets/digital-trace.svg")
				_interactive_banner_icon.modulate = Color(0.2, 0.85, 1.0)
			_interactive_banner_title.text = "🎯 新手任务 (5/6): 录制极限跳跃轨迹"
			_interactive_banner_sub.text = "人机原本无法判断断台可达。按【R 键】就绪，然后助跑跳到对面跳台！系统将自动捕获你的跳跃轨迹，作为人机新的可行路径！"
			_interactive_banner_style.border_color = Color(0.2, 0.85, 1.0)
			_set_status("【任务 5/6】按 R 键就绪，全力助跑起跳跨越断台，让人机学习新路径")

		5:
			if ResourceLoader.exists("res://assets/UI_assets/claw-slashes.svg"):
				_interactive_banner_icon.texture = load("res://assets/UI_assets/claw-slashes.svg")
				_interactive_banner_icon.modulate = Color(1.0, 0.88, 0.3)
			_interactive_banner_title.text = "🎯 新手任务 (6/6): 见证 AI 学习并复现跳跃"
			_interactive_banner_sub.text = "录制成功！角色已重置回起点。按【TAB 键】回到自由建造，按住【Shift + 左键】点击对面跳台，见证 NPC 完美复现你的跳跃！"
			_interactive_banner_style.border_color = Color(1.0, 0.88, 0.3)
			_set_status("【任务 6/6】角色已回起点，按 TAB 建造模式并 Shift+左键 命令 NPC 跨越跳跃")

		6:
			_interactive_banner.visible = false
			_interactive_complete_dialog.visible = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_cursor_free = true
			AudioManagerScript.play_voice_file("res://assets/voice/Voiceover Pack/Male/mission_completed.ogg", 2.0)
			_set_status("恭喜！您已圆满完成地图工坊新手互动教学！")


func _spawn_tutorial_glowing_platforms() -> void:
	_clear_all_blocks()
	_nav.clear_special_paths()

	# Platform 1
	var inst1 := BlockRegistry.BlockInstance.new()
	inst1.id = "tut_plat_1"
	inst1.type_id = "cube"
	inst1.grid_pos = Vector3i(0, 1, 0)
	inst1.size = Vector3i(2, 1, 2)
	var body1 := BlockRegistry.create_body(inst1)
	inst1.body_node = body1
	add_child(body1)
	_blocks[inst1.id] = inst1
	for c in inst1.get_occupied_cells():
		_cell_to_block_id[c] = inst1.id
		_nav.set_block(c, true)

	# Platform 2 (Across gap of 2 blocks, separated at z = 4)
	var inst2 := BlockRegistry.BlockInstance.new()
	inst2.id = "tut_plat_2"
	inst2.type_id = "cube"
	inst2.grid_pos = Vector3i(0, 1, 4)
	inst2.size = Vector3i(2, 1, 2)
	var body2 := BlockRegistry.create_body(inst2)
	inst2.body_node = body2
	add_child(body2)
	_blocks[inst2.id] = inst2
	for c in inst2.get_occupied_cells():
		_cell_to_block_id[c] = inst2.id
		_nav.set_block(c, true)

	_nav.rebuild()
	_nav.set_capability(_npc)

	# Position NPC on Platform 1
	_npc.global_position = Vector3(1.0, 1.2, 1.0)
	_npc.velocity = Vector3.ZERO
	_builder_camera.global_position = Vector3(1.0, 3.5, -3.5)
	_cam_pitch = -0.35
	_cam_yaw = 0.0
	_apply_builder_orientation()


func _build_tutorial_arrow() -> void:
	if _tutorial_arrow != null:
		return
	_tutorial_arrow = Node3D.new()
	_tutorial_arrow.name = "TutorialFloatingArrow"
	_tutorial_arrow.visible = false

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.2)
	mat.emission_energy_multiplier = 2.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

	# Arrow Head (Downward Cone)
	var head_mesh := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.35
	cone.bottom_radius = 0.0
	cone.height = 0.55
	cone.material = mat
	head_mesh.mesh = cone
	head_mesh.position.y = 0.28
	_tutorial_arrow.add_child(head_mesh)

	# Arrow Shaft (Cylinder)
	var shaft_mesh := MeshInstance3D.new()
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.12
	shaft.bottom_radius = 0.12
	shaft.height = 0.45
	shaft.material = mat
	shaft_mesh.mesh = shaft
	shaft_mesh.position.y = 0.75
	_tutorial_arrow.add_child(shaft_mesh)

	add_child(_tutorial_arrow)


func _show_tutorial_arrow_at(world_pos: Vector3) -> void:
	if _tutorial_arrow == null:
		_build_tutorial_arrow()
	_tutorial_arrow_base_pos = world_pos
	_tutorial_arrow_time = 0.0
	_tutorial_arrow.position = world_pos + Vector3(0, 0.45, 0)
	_tutorial_arrow.visible = true


func _hide_tutorial_arrow() -> void:
	if _tutorial_arrow != null:
		_tutorial_arrow.visible = false


func _toggle_ui_panels_mode() -> void:
	_ui_panels_visible = not _ui_panels_visible
	_update_ui_panels_visibility()


func _update_ui_panels_visibility() -> void:
	if _top_panel != null:
		_top_panel.visible = _ui_panels_visible
	if _left_panel != null:
		_left_panel.visible = _ui_panels_visible
	if _right_panel != null:
		_right_panel.visible = _ui_panels_visible

	if _ui_panels_visible:
		_cursor_free = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_set_status("【属性面板模式】鼠标指针可用，点击左侧调整材质尺寸或保存。按 B 切换沉浸视角")
	else:
		_cursor_free = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_set_status("【沉浸模式】鼠标隐藏，视角旋转与放置。按 B 呼出属性面板与指针")


func _open_tutorial_dialog(page: int = 0) -> void:
	_render_tutorial_page(page)
	_tutorial_dialog.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_cursor_free = true


func _close_tutorial_dialog() -> void:
	_tutorial_dialog.visible = false
	_update_ui_panels_visibility()


func _make_label(txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	if _custom_font != null:
		l.add_theme_font_override("font", _custom_font)
	l.add_theme_font_size_override("font_size", 12)
	return l


func _build_tutorial_dialog() -> void:
	_tutorial_dialog = PanelContainer.new()
	_tutorial_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_tutorial_dialog.offset_left = -340
	_tutorial_dialog.offset_right = 340
	_tutorial_dialog.offset_top = -240
	_tutorial_dialog.offset_bottom = 240
	_tutorial_dialog.custom_minimum_size = Vector2(680, 480)
	_tutorial_dialog.visible = false

	var diag_style := StyleBoxFlat.new()
	diag_style.bg_color = Color(0.09, 0.11, 0.15, 0.98)
	diag_style.set_corner_radius_all(12)
	diag_style.set_border_width_all(2)
	diag_style.border_color = Color(0.2, 0.8, 1.0)
	diag_style.set_content_margin_all(20)
	_tutorial_dialog.add_theme_stylebox_override("panel", diag_style)
	_hud_canvas.add_child(_tutorial_dialog)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	_tutorial_dialog.add_child(vbox)

	# Header: Title + Page counter + Close button
	var head_hbox := HBoxContainer.new()
	head_hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(head_hbox)

	var icon_tex := TextureRect.new()
	if ResourceLoader.exists("res://assets/UI_assets/cubes.svg"):
		icon_tex.texture = load("res://assets/UI_assets/cubes.svg")
	icon_tex.custom_minimum_size = Vector2(32, 32)
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.modulate = Color(0.2, 0.85, 1.0)
	head_hbox.add_child(icon_tex)

	_tutorial_title_lbl = Label.new()
	_tutorial_title_lbl.text = "地图工坊 · 特殊操作与录制指南"
	if _custom_font != null:
		_tutorial_title_lbl.add_theme_font_override("font", _custom_font)
	_tutorial_title_lbl.add_theme_font_size_override("font_size", 22)
	_tutorial_title_lbl.modulate = Color(0.2, 0.9, 1.0)
	_tutorial_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_hbox.add_child(_tutorial_title_lbl)

	_tutorial_page_lbl = Label.new()
	_tutorial_page_lbl.text = "第 1 / 4 页"
	if _custom_font != null:
		_tutorial_page_lbl.add_theme_font_override("font", _custom_font)
	_tutorial_page_lbl.add_theme_font_size_override("font_size", 16)
	_tutorial_page_lbl.modulate = Color(1.0, 0.85, 0.3)
	head_hbox.add_child(_tutorial_page_lbl)

	var skip_btn := Button.new()
	skip_btn.text = " 关闭 (ESC) "
	if _custom_font != null:
		skip_btn.add_theme_font_override("font", _custom_font)
	skip_btn.pressed.connect(_close_tutorial_dialog)
	head_hbox.add_child(skip_btn)

	# Content Area
	_tutorial_content_box = VBoxContainer.new()
	_tutorial_content_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tutorial_content_box.add_theme_constant_override("separation", 12)
	vbox.add_child(_tutorial_content_box)

	# Bottom Navigation
	var nav_hbox := HBoxContainer.new()
	nav_hbox.add_theme_constant_override("separation", 24)
	nav_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(nav_hbox)

	_tutorial_prev_btn = Button.new()
	_tutorial_prev_btn.text = "← 上一页 (Previous)"
	if _custom_font != null:
		_tutorial_prev_btn.add_theme_font_override("font", _custom_font)
	_tutorial_prev_btn.add_theme_font_size_override("font_size", 16)
	_tutorial_prev_btn.custom_minimum_size = Vector2(160, 40)
	_tutorial_prev_btn.pressed.connect(func() -> void: _render_tutorial_page(_tutorial_page - 1))
	nav_hbox.add_child(_tutorial_prev_btn)

	_tutorial_next_btn = Button.new()
	_tutorial_next_btn.text = "下一页 (Next) →"
	if _custom_font != null:
		_tutorial_next_btn.add_theme_font_override("font", _custom_font)
	_tutorial_next_btn.add_theme_font_size_override("font_size", 16)
	_tutorial_next_btn.custom_minimum_size = Vector2(180, 40)
	_tutorial_next_btn.pressed.connect(func() -> void:
		if _tutorial_page >= 3:
			_close_tutorial_dialog()
		else:
			_render_tutorial_page(_tutorial_page + 1)
	)
	nav_hbox.add_child(_tutorial_next_btn)

	_render_tutorial_page(0)


func _render_tutorial_page(page: int) -> void:
	_tutorial_page = clamp(page, 0, 3)
	if _tutorial_page_lbl != null:
		_tutorial_page_lbl.text = "第 %d / 4 页" % (_tutorial_page + 1)
	if _tutorial_prev_btn != null:
		_tutorial_prev_btn.disabled = (_tutorial_page == 0)
	if _tutorial_next_btn != null:
		if _tutorial_page == 3:
			_tutorial_next_btn.text = "开始探索创作 (Start) ✓"
		else:
			_tutorial_next_btn.text = "下一页 (Next) →"

	if _tutorial_content_box == null:
		return

	for child in _tutorial_content_box.get_children():
		child.queue_free()

	match _tutorial_page:
		0:
			_build_tutorial_page_0()
		1:
			_build_tutorial_page_1()
		2:
			_build_tutorial_page_2()
		3:
			_build_tutorial_page_3()


func _build_tutorial_page_0() -> void:
	var sub := Label.new()
	sub.text = "【一、视角模式与面板一键切换】"
	if _custom_font != null:
		sub.add_theme_font_override("font", _custom_font)
	sub.add_theme_font_size_override("font_size", 18)
	sub.modulate = Color(1.0, 0.85, 0.3)
	_tutorial_content_box.add_child(sub)

	_add_tutorial_step(_tutorial_content_box, "B", "按 B 键切换面板与沉浸视角",
		"按 B 键在【属性面板模式（鼠标指针工作，可点击调整尺寸材质与保存）】与【沉浸模式（鼠标隐藏，自由旋转视角飞行与瞄准）】之间随时切换。")
	_add_tutorial_step(_tutorial_content_box, "TAB", "按 TAB 键切换建造与角色试跑",
		"在【第一人称自由飞行建造】与【第三人称角色试玩】之间一键切换。试跑可实地检验跳跃距离与落点。")
	_add_tutorial_step(_tutorial_content_box, "W", "自由飞行巡航控制",
		"飞行模式下使用 WASD 水平巡航，Space 空格向上升空，Ctrl / C 向下降落，鼠标滚轮可调节飞行速度。")


func _build_tutorial_page_1() -> void:
	var sub := Label.new()
	sub.text = "【二、多尺寸方块与材质快速搭建】"
	if _custom_font != null:
		sub.add_theme_font_override("font", _custom_font)
	sub.add_theme_font_size_override("font_size", 18)
	sub.modulate = Color(1.0, 0.85, 0.3)
	_tutorial_content_box.add_child(sub)

	_add_tutorial_step(_tutorial_content_box, "LMB", "鼠标左键 (LMB) 放置方块",
		"准星对准地面或已有方块表面，点击左键放置当前选中的方块。在左侧面板可自由选择 Cube、Slab、Stairs 等类型与 2x1x1、4x1x2 等丰富尺寸。")
	_add_tutorial_step(_tutorial_content_box, "RMB", "鼠标右键 (RMB) 快速拆除",
		"准星对准任意方块，点击右键即可瞬间拆除整块积木。")
	_add_tutorial_step(_tutorial_content_box, "SHIFT", "Shift + 左键 实时指定 NPC 寻路测试",
		"准星对准地图任意地面，按住 Shift 点击左键，可指定 NPC 按照其真实物理能力规划路径前往该点。")


func _build_tutorial_page_2() -> void:
	var sub := Label.new()
	sub.text = "【三、特殊跳跃 / 极限动力学轨迹录制】"
	if _custom_font != null:
		sub.add_theme_font_override("font", _custom_font)
	sub.add_theme_font_size_override("font_size", 18)
	sub.modulate = Color(1.0, 0.85, 0.3)
	_tutorial_content_box.add_child(sub)

	_add_tutorial_step(_tutorial_content_box, "R", "按 R 键就绪录制特殊跳跃",
		"按 TAB 切换为角色试跑后，在悬崖起跳边缘停下脚步保持静止。按 R 键进入录制准备状态。")
	_add_tutorial_step(_tutorial_content_box, "SPACE", "助跑起跳与自动航迹截取",
		"顶部横幅提示【🟢 准备就绪，可以起跳】后，向目标高台全力助跑起跳。落地瞬间系统会自动从你起跳前的最后一帧零速度点开始，完整截取空中动力学航迹！")
	_add_tutorial_step(_tutorial_content_box, "AI", "NPC (AI) 智能学习复现",
		"录制成功的航迹会化为绿色轨迹线。AI 追缉或寻路时，到达该起跳点会自动无缝复现你的跳跃动作！")


func _build_tutorial_page_3() -> void:
	var sub := Label.new()
	sub.text = "【四、轨迹精准删除与地图导出对决】"
	if _custom_font != null:
		sub.add_theme_font_override("font", _custom_font)
	sub.add_theme_font_size_override("font_size", 18)
	sub.modulate = Color(1.0, 0.85, 0.3)
	_tutorial_content_box.add_child(sub)

	_add_tutorial_step(_tutorial_content_box, "X", "连按两下 X 快速删除选中轨迹",
		"在建造模式下，将准星对准空中的绿色特殊跳跃轨迹线（轨迹会高亮），连续按两下 X 键即可精准删除该段轨迹记录。")
	_add_tutorial_step(_tutorial_content_box, "SAVE", "保存地图 (Save Map)",
		"按 B 键呼出顶部工具栏，点击【保存 (Save)】输入地图名称，即可将包含全部方块与特殊跳跃的地图永久保存。")
	_add_tutorial_step(_tutorial_content_box, "PLAY", "导入追缉模式实战对决",
		"返回主大厅选择【开始追缉逃生 (Pursuit)】，在地图列表中选择你刚才保存的地图，即可在自己打造的专属战场中展开 1v1 极限逃生对决！")


func _add_tutorial_step(parent: VBoxContainer, key_or_tag: String, title: String, desc: String) -> void:
	var card := PanelContainer.new()
	var c_style := StyleBoxFlat.new()
	c_style.bg_color = Color(0.13, 0.15, 0.20, 0.85)
	c_style.set_corner_radius_all(8)
	c_style.set_border_width_all(1)
	c_style.border_color = Color(0.25, 0.30, 0.40)
	c_style.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", c_style)
	parent.add_child(card)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	card.add_child(hbox)

	var icon_widget := _create_tutorial_icon(key_or_tag)
	hbox.add_child(icon_widget)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	hbox.add_child(vbox)

	var t_lbl := Label.new()
	t_lbl.text = title
	if _custom_font != null:
		t_lbl.add_theme_font_override("font", _custom_font)
	t_lbl.add_theme_font_size_override("font_size", 16)
	t_lbl.modulate = Color(0.35, 0.9, 1.0)
	vbox.add_child(t_lbl)

	var d_lbl := Label.new()
	d_lbl.text = desc
	d_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _custom_font != null:
		d_lbl.add_theme_font_override("font", _custom_font)
	d_lbl.add_theme_font_size_override("font_size", 13)
	d_lbl.modulate = Color(0.85, 0.88, 0.92, 0.9)
	vbox.add_child(d_lbl)


func _create_tutorial_icon(key_tag: String) -> Control:
	var png_path := "res://assets/buttons_pattern/%s.png" % key_tag
	if ResourceLoader.exists(png_path):
		var tex := TextureRect.new()
		tex.texture = load(png_path)
		tex.custom_minimum_size = Vector2(36, 36)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return tex

	# If no png exists, render an attractive keycap badge
	var badge := PanelContainer.new()
	var b_style := StyleBoxFlat.new()
	b_style.bg_color = Color(0.20, 0.24, 0.32, 0.95)
	b_style.set_corner_radius_all(6)
	b_style.set_border_width_all(1)
	b_style.border_color = Color(0.4, 0.6, 0.8)
	b_style.set_content_margin_all(6)
	badge.add_theme_stylebox_override("panel", b_style)
	badge.custom_minimum_size = Vector2(40, 36)

	var lbl := Label.new()
	lbl.text = key_tag
	if _custom_font != null:
		lbl.add_theme_font_override("font", _custom_font)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.modulate = Color(1.0, 0.88, 0.35)
	badge.add_child(lbl)
	return badge


func _build_recording_banner() -> void:
	_recording_banner = PanelContainer.new()
	_recording_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_recording_banner.offset_left = -280
	_recording_banner.offset_right = 280
	_recording_banner.offset_top = 64
	_recording_banner.offset_bottom = 144
	_recording_banner.custom_minimum_size = Vector2(560, 80)
	_recording_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_recording_banner.visible = false

	_recording_banner_style = StyleBoxFlat.new()
	_recording_banner_style.bg_color = Color(0.1, 0.12, 0.16, 0.95)
	_recording_banner_style.set_corner_radius_all(10)
	_recording_banner_style.set_border_width_all(2)
	_recording_banner_style.border_color = Color(0.2, 0.85, 1.0)
	_recording_banner_style.set_content_margin_all(10)
	_recording_banner.add_theme_stylebox_override("panel", _recording_banner_style)
	_hud_canvas.add_child(_recording_banner)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 5)
	_recording_banner.add_child(vbox)

	_recording_banner_title = Label.new()
	_recording_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_recording_banner_title.add_theme_font_size_override("font_size", 16)
	_recording_banner_title.text = "🟡 准备录制中..."
	vbox.add_child(_recording_banner_title)

	_recording_banner_sub = Label.new()
	_recording_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_recording_banner_sub.add_theme_font_size_override("font_size", 12)
	_recording_banner_sub.text = "请在起点格停下脚步保持静止 0.2 秒"
	_recording_banner_sub.modulate = Color(1.0, 1.0, 1.0, 0.88)
	vbox.add_child(_recording_banner_sub)


func _update_recording_hud(state: int, message: String, is_failure := false) -> void:
	if _recording_banner == null:
		return

	if is_failure:
		_recording_banner.visible = true
		_recording_banner_style.bg_color = Color(0.28, 0.08, 0.08, 0.95)
		_recording_banner_style.border_color = Color(1.0, 0.35, 0.35)
		_recording_banner_title.text = "❌ 录制未完成 / 已取消"
		_recording_banner_title.modulate = Color(1.0, 0.45, 0.45)
		_recording_banner_sub.text = "%s\n按 R 重新开始录制 · 按 TAB 切换自由建造" % message
		_recording_banner_sub.modulate = Color(1.0, 0.88, 0.88)
		return

	match state:
		SpecialPathRecorderScript.State.ARMED_WAITING_FOR_REST:
			_recording_banner.visible = true
			_recording_banner_style.bg_color = Color(0.28, 0.18, 0.04, 0.95)
			_recording_banner_style.border_color = Color(1.0, 0.82, 0.2)
			_recording_banner_title.text = "🟡 [准备录制] 请停下脚步保持静止 0.2 秒..."
			_recording_banner_title.modulate = Color(1.0, 0.9, 0.3)
			_recording_banner_sub.text = "正在检测并锁定起点站立格 (按 ESC / R 取消)"
			_recording_banner_sub.modulate = Color(1.0, 0.94, 0.75)

		SpecialPathRecorderScript.State.GROUND_RECORDING:
			_recording_banner.visible = true
			_recording_banner_style.bg_color = Color(0.04, 0.26, 0.12, 0.96)
			_recording_banner_style.border_color = Color(0.25, 1.0, 0.45)
			_recording_banner_title.text = "🟢 ● RECORDING [可以起跑起跳！]"
			_recording_banner_title.modulate = Color(0.35, 1.0, 0.55)
			_recording_banner_sub.text = "已锁定起点！起跑并跳向目标格 · 自动以起跳前最后一次静止点为起点"
			_recording_banner_sub.modulate = Color(0.85, 1.0, 0.9)

		SpecialPathRecorderScript.State.AIRBORNE_RECORDING:
			_recording_banner.visible = true
			_recording_banner_style.bg_color = Color(0.04, 0.20, 0.30, 0.96)
			_recording_banner_style.border_color = Color(0.2, 0.88, 1.0)
			_recording_banner_title.text = "🔵 ✈️ [空中飞行轨迹采样中...]"
			_recording_banner_title.modulate = Color(0.4, 0.9, 1.0)
			_recording_banner_sub.text = "记录空中位移与操作快照 · 落地即可完成录制"
			_recording_banner_sub.modulate = Color(0.85, 0.95, 1.0)

		SpecialPathRecorderScript.State.COMPLETED:
			_recording_banner.visible = true
			_recording_banner_style.bg_color = Color(0.24, 0.08, 0.28, 0.96)
			_recording_banner_style.border_color = Color(1.0, 0.85, 0.25)
			_recording_banner_title.text = "🎉 ✓ [特殊跳跃录制成功！]"
			_recording_banner_title.modulate = Color(1.0, 0.9, 0.3)
			_recording_banner_sub.text = "%s\n按 R 立即录制下一段 · 按 TAB 切换自由建造" % message
			_recording_banner_sub.modulate = Color(1.0, 0.95, 0.95)

		SpecialPathRecorderScript.State.IDLE:
			_recording_banner.visible = false


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

		var traj_len: int = (p_dict.get("trajectory", []) as Array).size()
		var dur: float = float(p_dict.get("duration", 0.0))
		var lbl := Label.new()
		lbl.text = "路径 (%d,%d,%d) -> (%d,%d,%d)\n  %d 帧 · %.2fs" % [
			from_arr[0], from_arr[1], from_arr[2],
			to_arr[0], to_arr[1], to_arr[2],
			traj_len, dur
		]
		lbl.add_theme_font_size_override("font_size", 11)
		card_vbox.add_child(lbl)

		var btns := HBoxContainer.new()
		card_vbox.add_child(btns)

		var test_btn := Button.new()
		test_btn.text = "NPC测试"
		test_btn.add_theme_font_size_override("font_size", 10)
		test_btn.pressed.connect(func() -> void:
			_test_specific_special_path(p_dict)
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
