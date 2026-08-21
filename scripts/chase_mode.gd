extends Node3D
## 1v1 Pursuit / Chase Mode controller.
## Player escapes, Chaser NPC tracks player foot center with dynamic repath rules.

const NavGridScript = preload("res://scripts/nav_grid.gd")
const BlockRegistryScript = preload("res://scripts/block_registry.gd")
const MapDataScript = preload("res://scripts/map_data.gd")
const CharacterPipelineScript = preload("res://tools/character_pipeline.gd")
const PlayerControllerScript = preload("res://scripts/player_controller.gd")
const PlayerIntentSourceScript = preload("res://scripts/player_intent_source.gd")
const NPCIntentSourceScript = preload("res://scripts/npc_intent_source.gd")
const FollowCameraScript = preload("res://scripts/follow_camera.gd")

const MENU_SCENE := "res://scenes/main_menu.tscn"
const GROUND_HALF := 25.0
const MAX_BLOCK_Y := 12
const ESCAPE_COUNTDOWN_TIME := 15.0
const CHASE_TIME_LIMIT := 120.0
const FAST_REPATH_INTERVAL := 0.06
const SLOW_REPATH_INTERVAL := 0.25
const LOS_DELAY_SECONDS := 0.20
const CATCH_DISTANCE_THRESHOLD := 1.5
const DOUBLE_TAP_WINDOW := 0.45

enum State {
	SELECT_MAP,
	ESCAPE_COUNTDOWN,
	CHASE_ACTIVE,
	GAME_OVER,
}

var _state: State = State.SELECT_MAP
var _escape_timer: float = ESCAPE_COUNTDOWN_TIME
var _survival_time: float = 0.0

var _nav = NavGridScript.new()
var _blocks: Dictionary = {}
var _cell_to_block_id: Dictionary = {}
var _map_name := "默认地图"
var _map_file_path := ""

var _player: CharacterBody3D
var _npc: CharacterBody3D
var _player_visual: Node3D
var _npc_visual: Node3D
var _player_intent: PlayerIntentSource
var _player_npc_intent: NPCIntentSource
var _npc_intent: NPCIntentSource
var _camera: FollowCamera
var _commander_camera: Camera3D

var _commander_mode := false
var _cam_yaw := 0.0
var _cam_pitch := -0.55
var _cam_velocity := Vector3.ZERO
var _fly_speed := 12.0

var _highlight: MeshInstance3D
var _has_aim := false
var _aim_point := Vector3.ZERO
var _aim_cell := Vector3i.ZERO

var _player_spawn := Vector3(0.5, 0.2, 0.5)
var _npc_spawn := Vector3(0.5, 0.2, -10.5)

var _characters: Array = []
var _player_char_idx := 0
var _npc_char_idx := 1

var _repath_timer := 0.0
var _player_was_jumping_or_climbing := false
var _npc_was_busy := false
var _deferred_repath_pending := false
var _player_history: Array[Dictionary] = []

var _show_debug_path := false
var _last_x_press_time := -1000.0

var _path_mesh_instance: MeshInstance3D
var _path_immediate_mesh: ImmediateMesh
var _target_beacon: MeshInstance3D

var _player_path_mesh: MeshInstance3D
var _player_path_imm: ImmediateMesh
var _player_beacon: MeshInstance3D

var _hud_canvas: CanvasLayer
var _crosshair: Control
var _banner_panel: PanelContainer
var _banner_style: StyleBoxFlat
var _banner_title: Label
var _banner_sub: Label
var _info_box: PanelContainer
var _survival_label: Label
var _distance_label: Label
var _status_detail_label: Label
var _hint_x_toggle_label: Label
var _hint_tab_label: Label

var _map_select_dialog: PanelContainer
var _map_list: ItemList
var _game_over_dialog: PanelContainer
var _game_over_title: Label
var _game_over_time_lbl: Label


func _ready() -> void:
	BlockRegistryScript.init_registry()
	_characters = CharacterPipelineScript.list_characters().filter(
		func(c: Dictionary) -> bool: return ResourceLoader.exists(c.scene))

	if _characters.size() >= 2:
		_npc_char_idx = 1
	else:
		_npc_char_idx = 0

	_nav.set_bounds(int(GROUND_HALF), MAX_BLOCK_Y + 1)

	_build_environment()
	_build_ground()
	_build_visual_helpers()
	_build_camera()
	_build_characters()
	_build_hud()

	_open_map_select_dialog()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if _map_select_dialog.visible or _game_over_dialog.visible:
				SceneLoader.change_scene(get_tree(), MENU_SCENE, "返回主菜单...")
				return
			_open_map_select_dialog()
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_TAB:
			_toggle_commander_mode()
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_X:
			var now := float(Time.get_ticks_msec()) * 0.001
			if (now - _last_x_press_time) <= DOUBLE_TAP_WINDOW:
				_show_debug_path = not _show_debug_path
				_last_x_press_time = -1000.0
				_update_debug_path_visibility()
			else:
				_last_x_press_time = now
			get_viewport().set_input_as_handled()
			return

	if not _commander_mode:
		return

	var motion := event as InputEventMouseMotion
	if motion != null:
		_cam_yaw -= motion.relative.x * 0.0026
		_cam_pitch = clampf(_cam_pitch - motion.relative.y * 0.0026, -1.5, 1.5)
		_apply_commander_cam_orientation()
		return

	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return

	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		_fly_speed = clampf(_fly_speed * 1.15, 3.0, 40.0)
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_fly_speed = clampf(_fly_speed / 1.15, 3.0, 40.0)
		return

	if mb.button_index == MOUSE_BUTTON_MIDDLE \
			or (mb.button_index == MOUSE_BUTTON_LEFT and Input.is_key_pressed(KEY_SHIFT)):
		if _has_aim:
			_command_player_npc(_aim_point)
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _commander_mode:
		_drive_commander_camera(delta)
		_cast_crosshair()


func _physics_process(delta: float) -> void:
	match _state:
		State.ESCAPE_COUNTDOWN:
			_escape_timer = maxf(0.0, _escape_timer - delta)
			_update_escape_countdown_hud()

			# Keep NPC stationary during escape countdown
			if _npc_intent != null:
				_npc_intent.clear_target()

			if _escape_timer <= 0.0:
				_start_active_chase()

		State.CHASE_ACTIVE:
			_survival_time += delta
			_update_active_chase_hud()

			if _player == null or _npc == null:
				return

			if _survival_time >= CHASE_TIME_LIMIT:
				_trigger_game_win()
				return

			# Catch detection: within catch distance threshold
			var dist := _player.global_position.distance_to(_npc.global_position)
			var vert_dist := absf(_player.global_position.y - _npc.global_position.y)
			if dist <= CATCH_DISTANCE_THRESHOLD and vert_dist <= 1.5:
				_trigger_game_over()
				return

			# Track player position history for 200ms delayed chase
			var now := float(Time.get_ticks_msec()) * 0.001
			_player_history.append({"time": now, "pos": _player.global_position})
			while _player_history.size() > 1 and (now - _player_history[0].time) > 1.2:
				_player_history.pop_front()

			# Rule 4 Check: If NPC is currently jumping, climbing, or in air, do not interrupt!
			var npc_busy := _npc_intent.is_performing_jump_or_climb() or not _npc.is_on_floor()
			var npc_just_finished_climb_or_air := _npc_was_busy and not npc_busy
			_npc_was_busy = npc_busy

			if not npc_busy:
				# If NPC just finished climbing/jumping or had deferred repath, execute immediately!
				if _deferred_repath_pending or npc_just_finished_climb_or_air:
					_deferred_repath_pending = false
					_repath_timer = 0.0
					_execute_npc_repath()

			# Rule 3: Escaper Jump/Climb Landing Trigger
			var player_grounded := _player.is_on_floor()
			if not player_grounded:
				_player_was_jumping_or_climbing = true
			elif _player_was_jumping_or_climbing and player_grounded:
				_player_was_jumping_or_climbing = false
				# Escaper just landed! Immediately request repath and reset timer
				_request_npc_repath(true)

			# Rule 2: Interval Timer (Fast on same flat platform, Slow across gaps/levels)
			var p_cell := _nav.standing_node(_player.global_position)
			var n_cell := _nav.standing_node(_npc.global_position)
			var on_same_platform := _nav.is_same_flat_platform(n_cell, p_cell)
			var interval := FAST_REPATH_INTERVAL if on_same_platform else SLOW_REPATH_INTERVAL

			_repath_timer += delta
			if _repath_timer >= interval:
				_request_npc_repath(false)


# --- Line-of-Sight & Delay Math ---------------------------------------------

func _get_delayed_player_pos(delay: float) -> Vector3:
	if _player_history.is_empty():
		return _player.global_position if _player != null else Vector3.ZERO
	var target_t := (float(Time.get_ticks_msec()) * 0.001) - delay
	for i in range(_player_history.size() - 1, -1, -1):
		if _player_history[i].time <= target_t:
			return _player_history[i].pos
	return _player_history[0].pos


func _has_clear_line_of_sight(from_pos: Vector3, to_pos: Vector3) -> bool:
	if absf(from_pos.y - to_pos.y) > 0.85:
		return false

	var space_state := get_world_3d().direct_space_state

	# Obstacle raycast at chest height
	var ray_from := from_pos + Vector3(0.0, 0.8, 0.0)
	var ray_to := to_pos + Vector3(0.0, 0.8, 0.0)
	var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	query.collide_with_areas = false
	query.exclude = [_player.get_rid(), _npc.get_rid()] if _player and _npc else []
	var hit := space_state.intersect_ray(query)
	if not hit.is_empty():
		return false

	# Floor continuity raycast checks (ensure no pits/void in between)
	var samples := 4
	for i in range(1, samples):
		var frac := float(i) / float(samples)
		var sample_p := from_pos.lerp(to_pos, frac)
		var down_query := PhysicsRayQueryParameters3D.create(
			sample_p + Vector3(0.0, 0.4, 0.0),
			sample_p + Vector3(0.0, -1.2, 0.0)
		)
		down_query.collide_with_areas = false
		down_query.exclude = [_player.get_rid(), _npc.get_rid()] if _player and _npc else []
		var down_hit := space_state.intersect_ray(down_query)
		if down_hit.is_empty():
			return false

	return true


# --- Repath Orchestration ---------------------------------------------------

func _request_npc_repath(from_player_landing: bool) -> void:
	_repath_timer = 0.0

	var npc_busy := _npc_intent.is_performing_jump_or_climb() or not _npc.is_on_floor()
	if npc_busy:
		# Rule 4: NPC is currently jumping or climbing -> DEFER until NPC lands!
		_deferred_repath_pending = true
	else:
		_deferred_repath_pending = false
		_execute_npc_repath()


func _execute_npc_repath() -> void:
	if _player == null or _npc == null:
		return
	var player_cell := _nav.standing_node(_player.global_position)
	if player_cell == NavGridScript.NO_CELL:
		return

	# Rule: Chaser always targets the center of the block under the Escaper's feet
	var target_pos := NavGridScript.foot(player_cell)
	_target_beacon.global_position = target_pos
	_target_beacon.visible = _show_debug_path and _state == State.CHASE_ACTIVE

	var result := _nav.find_path(_npc.global_position, target_pos)
	if result.points.is_empty():
		return

	_npc_intent.set_plan_result(result)
	_draw_npc_path(result.points)


func _on_npc_repath_requested(_from: Vector3, _to: Vector3) -> void:
	# Rule 1: Existing triggers (repath requested by NPC intent source)
	if _state == State.CHASE_ACTIVE:
		_request_npc_repath(false)


# --- Game State Transitions -------------------------------------------------

func _start_escape_countdown() -> void:
	_state = State.ESCAPE_COUNTDOWN
	_escape_timer = ESCAPE_COUNTDOWN_TIME
	_survival_time = 0.0
	_deferred_repath_pending = false
	_player_was_jumping_or_climbing = false
	_repath_timer = 0.0

	_player.global_position = _player_spawn
	_player.velocity = Vector3.ZERO
	_npc.global_position = _npc_spawn
	_npc.velocity = Vector3.ZERO
	_npc_intent.clear_target()

	_camera.target = _player
	if _player_visual != null:
		var height: float = _player_visual.get("body_height")
		_camera.frame_for(height if height > 0.1 else 1.75)
	_camera.snap()

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_map_select_dialog.visible = false
	_game_over_dialog.visible = false
	_banner_panel.visible = true
	_info_box.visible = true

	_update_escape_countdown_hud()


func _start_active_chase() -> void:
	_state = State.CHASE_ACTIVE
	_repath_timer = 0.0
	_deferred_repath_pending = false
	_execute_npc_repath()


func _trigger_game_win() -> void:
	_state = State.GAME_OVER
	_npc_intent.clear_target()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if _banner_style != null:
		_banner_style.border_color = Color(0.3, 1.0, 0.5, 0.8)
	_banner_title.text = "🏆 【逃生成功！存活满 2 分钟！】"
	_banner_title.modulate = Color(0.4, 1.0, 0.6)
	_banner_sub.text = "恭喜逃生成功！追缉者未能在 2 分钟内捕获你"

	if _game_over_title != null:
		_game_over_title.text = "🏆 逃生成功！"
		_game_over_title.modulate = Color(0.3, 1.0, 0.5)

	var m := int(CHASE_TIME_LIMIT) / 60
	var s := fmod(CHASE_TIME_LIMIT, 60.0)
	_game_over_time_lbl.text = "本次生存逃生时间: %02d:%05.2f (挑战胜利)" % [m, s]
	_game_over_dialog.visible = true


func _trigger_game_over() -> void:
	_state = State.GAME_OVER
	_npc_intent.clear_target()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if _banner_style != null:
		_banner_style.border_color = Color(1.0, 0.35, 0.35, 0.8)
	_banner_title.text = "💀 【你已被追缉者捕获！】"
	_banner_title.modulate = Color(1.0, 0.45, 0.45)
	_banner_sub.text = "追缉者已接近至 1.5m 范围内！按 ESC 或点击下方按钮重新挑战"

	if _game_over_title != null:
		_game_over_title.text = "💀 追缉者获胜！"
		_game_over_title.modulate = Color(1.0, 0.4, 0.4)

	var m := int(_survival_time) / 60
	var s := fmod(_survival_time, 60.0)
	_game_over_time_lbl.text = "本次生存逃生时间: %02d:%05.2f" % [m, s]
	_game_over_dialog.visible = true


# --- Scene & Visuals Construction -------------------------------------------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.18, 0.22, 0.35)
	sky_mat.sky_horizon_color = Color(0.48, 0.50, 0.55)
	sky_mat.ground_bottom_color = Color(0.10, 0.10, 0.12)
	sky_mat.ground_horizon_color = Color(0.48, 0.50, 0.55)

	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var env_node := WorldEnvironment.new()
	env_node.environment = env
	add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 35.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 150.0
	sun.directional_shadow_fade_start = 0.85
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.0
	add_child(sun)


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(GROUND_HALF * 2.0, 0.4, GROUND_HALF * 2.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.2, 0.0)
	body.add_child(shape)
	add_child(body)

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
	add_child(node)


class Crosshair extends Control:
	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var tint := Color(0.2, 0.9, 1.0, 0.9)
		var shade := Color(0.0, 0.0, 0.0, 0.5)
		for pass_index in 2:
			var col := shade if pass_index == 0 else tint
			var w := 3.0 if pass_index == 0 else 1.5
			draw_line(c - Vector2(10, 0), c - Vector2(3, 0), col, w)
			draw_line(c + Vector2(3, 0), c + Vector2(10, 0), col, w)
			draw_line(c - Vector2(0, 10), c - Vector2(0, 3), col, w)
			draw_line(c + Vector2(0, 3), c + Vector2(0, 10), col, w)


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
	_path_mesh_instance.visible = false
	add_child(_path_mesh_instance)

	_target_beacon = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.35
	cyl.bottom_radius = 0.35
	cyl.height = 1.6
	var b_mat := StandardMaterial3D.new()
	b_mat.albedo_color = Color(1.0, 0.25, 0.2, 0.75)
	b_mat.emission_enabled = true
	b_mat.emission = Color(1.0, 0.15, 0.1)
	b_mat.emission_energy_multiplier = 2.0
	b_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_target_beacon.mesh = cyl
	_target_beacon.material_override = b_mat
	_target_beacon.position.y = 0.8
	_target_beacon.visible = false
	add_child(_target_beacon)

	# Commander Player NPC visual path & beacon
	_player_path_imm = ImmediateMesh.new()
	_player_path_mesh = MeshInstance3D.new()
	_player_path_mesh.mesh = _player_path_imm
	var p_mat := StandardMaterial3D.new()
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.vertex_color_use_as_albedo = true
	p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p_mat.no_depth_test = true
	_player_path_mesh.material_override = p_mat
	_player_path_mesh.visible = false
	add_child(_player_path_mesh)

	_player_beacon = MeshInstance3D.new()
	var p_cyl := CylinderMesh.new()
	p_cyl.top_radius = 0.35
	p_cyl.bottom_radius = 0.35
	p_cyl.height = 1.6
	var pb_mat := StandardMaterial3D.new()
	pb_mat.albedo_color = Color(0.2, 0.85, 1.0, 0.75)
	pb_mat.emission_enabled = true
	pb_mat.emission = Color(0.1, 0.7, 0.9)
	pb_mat.emission_energy_multiplier = 2.0
	pb_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_player_beacon.mesh = p_cyl
	_player_beacon.material_override = pb_mat
	_player_beacon.position.y = 0.8
	_player_beacon.visible = false
	add_child(_player_beacon)

	_highlight = _make_wire_cube()
	_highlight.visible = false
	add_child(_highlight)


func _build_camera() -> void:
	_camera = FollowCameraScript.new()
	_camera.fov = 55.0
	_camera.near = 0.1
	_camera.far = 400.0
	_camera.current = true
	add_child(_camera)

	_commander_camera = Camera3D.new()
	_commander_camera.fov = 60.0
	_commander_camera.near = 0.15
	_commander_camera.far = 400.0
	_commander_camera.current = false
	add_child(_commander_camera)


func _build_characters() -> void:
	# Player (Escaper)
	_player = PlayerControllerScript.new()
	_player.name = "PlayerEscaper"
	_player.position = _player_spawn
	_player_intent = PlayerIntentSourceScript.new()
	_player_npc_intent = NPCIntentSourceScript.new()
	_player_npc_intent.bind_nav_grid(_nav)
	_player_npc_intent.repath_requested.connect(_on_player_npc_repath_requested)
	_player.intent_source = _player_intent
	add_child(_player)
	_spawn_character_visual(_player, _player_char_idx, true)

	# NPC (Chaser)
	_npc = PlayerControllerScript.new()
	_npc.name = "NPCChaser"
	_npc.position = _npc_spawn
	_npc_intent = NPCIntentSourceScript.new()
	_npc.intent_source = _npc_intent
	_npc_intent.bind_nav_grid(_nav)
	_npc_intent.repath_requested.connect(_on_npc_repath_requested)
	add_child(_npc)
	_spawn_character_visual(_npc, _npc_char_idx, false)


func _spawn_character_visual(body: CharacterBody3D, char_idx: int, is_player: bool) -> void:
	if _characters.is_empty():
		return
	var entry: Dictionary = _characters[clamp(char_idx, 0, _characters.size() - 1)]
	var scene := load(entry.scene) as PackedScene
	if scene == null:
		return
	var visual: Node3D = scene.instantiate()
	body.add_child(visual)

	var height: float = visual.get("body_height")
	if height <= 0.1:
		height = 1.75

	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = minf(0.3, height * 0.2)
	capsule.height = height
	collider.shape = capsule
	collider.position.y = height * 0.5
	body.add_child(collider)

	body.setup(visual, _camera)

	if is_player:
		_player_visual = visual
		_camera.target = _player
		_camera.frame_for(height)
		_camera.snap()
	else:
		_npc_visual = visual
		_nav.set_capability(_npc)


func _toggle_commander_mode() -> void:
	_commander_mode = not _commander_mode
	if _commander_mode:
		_commander_camera.global_position = _camera.global_position + Vector3(0.0, 3.5, 0.0)
		_cam_yaw = _player.rotation.y + PI
		_cam_pitch = -0.65
		_apply_commander_cam_orientation()
		_commander_camera.current = true
		_player.intent_source = _player_npc_intent
		if _crosshair != null:
			_crosshair.visible = true
		if _hint_tab_label != null:
			_hint_tab_label.text = "【Tab】视角: 全局指挥模式 (Shift+左键 指挥己方NPC)"
			_hint_tab_label.modulate = Color(0.2, 0.9, 1.0, 0.95)
	else:
		_camera.current = true
		_player.intent_source = _player_intent
		if _crosshair != null:
			_crosshair.visible = false
		if _highlight != null:
			_highlight.visible = false
		_has_aim = false
		_player_beacon.visible = false
		_player_path_mesh.visible = false
		_player_npc_intent.clear_target()
		if _hint_tab_label != null:
			_hint_tab_label.text = "【Tab】视角: 第三人称操纵 (按Tab切换全局指挥)"
			_hint_tab_label.modulate = Color(0.7, 0.8, 0.9, 0.75)


func _command_player_npc(target: Vector3) -> void:
	if _player == null or _player_npc_intent == null:
		return
	var cell := _nav.standing_node(target)
	if cell == NavGridScript.NO_CELL:
		return
	var goal_pos := NavGridScript.foot(cell)
	var result := _nav.find_path(_player.global_position, goal_pos)
	if result.points.is_empty():
		return
	_player_npc_intent.set_plan_result(result)
	_draw_player_path(result.points)
	_player_beacon.global_position = goal_pos
	_player_beacon.visible = true


func _on_player_npc_repath_requested(from_pos: Vector3, target: Vector3) -> void:
	if not _commander_mode or _player_npc_intent == null:
		return
	var result := _nav.find_path(from_pos, target)
	if result.points.is_empty():
		_player_npc_intent.clear_target()
		_player_beacon.visible = false
		_player_path_mesh.visible = false
		return
	_player_npc_intent.set_plan_result(result)
	_draw_player_path(result.points)


func _draw_player_path(points: PackedVector3Array) -> void:
	_player_path_imm.clear_surfaces()
	if points.size() < 2:
		return
	_player_path_imm.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(1, points.size()):
		var p1 := points[i - 1] + Vector3(0.0, 0.08, 0.0)
		var p2 := points[i] + Vector3(0.0, 0.08, 0.0)
		var col := Color(0.15, 0.85, 1.0, 0.95)
		_player_path_imm.surface_set_color(col)
		_player_path_imm.surface_add_vertex(p1)
		_player_path_imm.surface_set_color(col)
		_player_path_imm.surface_add_vertex(p2)
	_player_path_imm.surface_end()
	_player_path_mesh.visible = true


func _apply_commander_cam_orientation() -> void:
	if _commander_camera == null:
		return
	_commander_camera.basis = Basis(Vector3.UP, _cam_yaw) * Basis(Vector3.RIGHT, _cam_pitch)


func _drive_commander_camera(delta: float) -> void:
	if _commander_camera == null:
		return
	var wish := Vector3.ZERO
	var cam_basis := _commander_camera.global_basis
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
		var pace: float = _fly_speed * (2.5 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		wish = wish.normalized() * pace

	_cam_velocity = _cam_velocity.lerp(wish, 1.0 - exp(-delta * 12.0))
	_commander_camera.global_position += _cam_velocity * delta


func _cast_crosshair() -> void:
	if _commander_camera == null or not _commander_camera.current:
		_has_aim = false
		if _highlight != null:
			_highlight.visible = false
		return

	var space := get_world_3d().direct_space_state
	var origin := _commander_camera.global_position
	var forward := -_commander_camera.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * 60.0)
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)

	if hit.is_empty():
		_has_aim = false
		if _highlight != null:
			_highlight.visible = false
		return

	_has_aim = true
	var hit_pos: Vector3 = hit.position
	var normal: Vector3 = hit.normal
	_aim_point = hit_pos
	var inward := hit_pos - normal * 0.01
	_aim_cell = Vector3i(int(floor(inward.x)), int(floor(inward.y)), int(floor(inward.z)))
	if _highlight != null:
		_highlight.global_position = Vector3(_aim_cell)
		_highlight.visible = true


func _make_wire_cube() -> MeshInstance3D:
	var pad := 0.004
	var lo := -pad
	var hi := 1.0 + pad
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for seg in [
		[Vector3(lo,lo,lo), Vector3(hi,lo,lo)], [Vector3(hi,lo,lo), Vector3(hi,lo,hi)],
		[Vector3(hi,lo,hi), Vector3(lo,lo,hi)], [Vector3(lo,lo,hi), Vector3(lo,lo,lo)],
		[Vector3(lo,hi,lo), Vector3(hi,hi,lo)], [Vector3(hi,hi,lo), Vector3(hi,hi,hi)],
		[Vector3(hi,hi,hi), Vector3(lo,hi,hi)], [Vector3(lo,hi,hi), Vector3(lo,hi,lo)],
		[Vector3(lo,lo,lo), Vector3(lo,hi,lo)], [Vector3(hi,lo,lo), Vector3(hi,hi,lo)],
		[Vector3(hi,lo,hi), Vector3(hi,hi,hi)], [Vector3(lo,lo,hi), Vector3(lo,hi,hi)],
	]:
		mesh.surface_add_vertex(seg[0])
		mesh.surface_add_vertex(seg[1])
	mesh.surface_end()

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.2, 0.85, 1.0, 0.9)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	return node


func _draw_npc_path(points: PackedVector3Array) -> void:
	_path_immediate_mesh.clear_surfaces()
	if points.size() < 2:
		return

	_path_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(1, points.size()):
		var p1 := points[i - 1] + Vector3(0.0, 0.08, 0.0)
		var p2 := points[i] + Vector3(0.0, 0.08, 0.0)
		var col := Color(1.0, 0.2, 0.2, 0.9)
		_path_immediate_mesh.surface_set_color(col)
		_path_immediate_mesh.surface_add_vertex(p1)
		_path_immediate_mesh.surface_set_color(col)
		_path_immediate_mesh.surface_add_vertex(p2)
	_path_immediate_mesh.surface_end()
	_path_mesh_instance.visible = _show_debug_path


func _update_debug_path_visibility() -> void:
	if _path_mesh_instance != null:
		_path_mesh_instance.visible = _show_debug_path
	if _target_beacon != null:
		_target_beacon.visible = _show_debug_path and _state == State.CHASE_ACTIVE
	if _hint_x_toggle_label != null:
		if _show_debug_path:
			_hint_x_toggle_label.text = "AI路线与红柱: 显示中 (连按两下X隐藏)"
			_hint_x_toggle_label.modulate = Color(1.0, 0.85, 0.3, 0.9)
		else:
			_hint_x_toggle_label.text = "AI路线与红柱: 已隐藏 (连按两下X显示)"
			_hint_x_toggle_label.modulate = Color(0.7, 0.7, 0.7, 0.65)


# --- Map Loading ------------------------------------------------------------

func _load_map_data(path: String) -> void:
	var data := MapDataScript.load_map_from_file(path)
	if data.is_empty():
		return

	_clear_all_blocks()
	_nav.clear_special_paths()

	_map_name = str(data.get("name", "未命名地图"))
	_map_file_path = path

	var sp: Array = data.get("spawn_pos", [0.5, 0.2, 0.5])
	if sp.size() >= 3:
		_player_spawn = Vector3(sp[0], sp[1], sp[2])

	# Spawn NPC at opposite side or offset
	_npc_spawn = _player_spawn + Vector3(0.0, 0.0, -10.0)

	var blocks_arr: Array = data.get("blocks", [])
	var next_id := 1
	for b_dict in blocks_arr:
		if b_dict is Dictionary:
			var inst := BlockRegistryScript.BlockInstance.from_dict(b_dict)
			if inst.id.is_empty():
				inst.id = "blk_%d" % next_id
				next_id += 1
			var body := BlockRegistryScript.create_body(inst)
			inst.body_node = body
			add_child(body)
			_blocks[inst.id] = inst
			for cell in inst.get_occupied_cells():
				_cell_to_block_id[cell] = inst.id
				_nav.set_block(cell, true)

	var sp_paths: Array = data.get("special_paths", [])
	for p_dict in sp_paths:
		if p_dict is Dictionary:
			_nav.add_special_path(p_dict)

	_nav.rebuild()
	if _npc != null:
		_nav.set_capability(_npc)

	var p_stand := _nav.standing_node(_player_spawn)
	if p_stand != NavGridScript.NO_CELL:
		_player_spawn = NavGridScript.foot(p_stand) + Vector3(0.0, 0.05, 0.0)

	var best_npc_cell := NavGridScript.NO_CELL
	var best_dist := -1.0
	for col_key in _nav._columns:
		var col: Vector2i = col_key
		var levels: PackedInt32Array = _nav._columns[col]
		for lvl in levels:
			var c := Vector3i(col.x, lvl, col.y)
			var d: float = Vector2(float(c.x - p_stand.x), float(c.z - p_stand.z)).length()
			if d >= 6.0 and (best_dist < 0.0 or absf(d - 10.0) < absf(best_dist - 10.0)):
				best_dist = d
				best_npc_cell = c
	if best_npc_cell != NavGridScript.NO_CELL:
		_npc_spawn = NavGridScript.foot(best_npc_cell) + Vector3(0.0, 0.05, 0.0)
	else:
		_npc_spawn = _player_spawn + Vector3(0.0, 0.05, -8.0)


func _clear_all_blocks() -> void:
	for id in _blocks:
		var inst: BlockRegistry.BlockInstance = _blocks[id]
		if inst.body_node != null and is_instance_valid(inst.body_node):
			inst.body_node.queue_free()
	_blocks.clear()
	_cell_to_block_id.clear()
	_nav.clear_blocks()


func _build_hud() -> void:
	_hud_canvas = CanvasLayer.new()
	add_child(_hud_canvas)

	# Top Banner (Red/Alarm Alert 9-Patch Frame)
	_banner_panel = PanelContainer.new()
	_banner_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner_panel.offset_left = -300
	_banner_panel.offset_right = 300
	_banner_panel.offset_top = 16
	_banner_panel.offset_bottom = 96
	_banner_panel.custom_minimum_size = Vector2(600, 72)
	_banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_banner_style = StyleBoxFlat.new()
	_banner_style.bg_color = Color(0.06, 0.08, 0.12, 0.88)
	_banner_style.set_corner_radius_all(12)
	_banner_style.set_border_width_all(1)
	_banner_style.border_color = Color(1.0, 0.85, 0.25, 0.6)
	_banner_style.content_margin_left = 16
	_banner_style.content_margin_right = 16
	_banner_style.content_margin_top = 8
	_banner_style.content_margin_bottom = 8
	_banner_panel.add_theme_stylebox_override("panel", _banner_style)
	_hud_canvas.add_child(_banner_panel)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	_banner_panel.add_child(vbox)

	_banner_title = Label.new()
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_title.add_theme_font_size_override("font_size", 18)
	_banner_title.text = "⏳ 逃生准备倒计时: 15.0 秒"
	vbox.add_child(_banner_title)

	_banner_sub = Label.new()
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub.add_theme_font_size_override("font_size", 12)
	_banner_sub.text = "尽快利用地形与跳跃拉开距离！倒计时结束后追缉者将出动！"
	_banner_sub.modulate = Color(1.0, 1.0, 1.0, 0.88)
	vbox.add_child(_banner_sub)

	# Left-top stats HUD (Clean, no background panel)
	_info_box = PanelContainer.new()
	_info_box.offset_left = 20
	_info_box.offset_top = 20
	_info_box.custom_minimum_size = Vector2(260, 110)
	var info_style := StyleBoxEmpty.new()
	_info_box.add_theme_stylebox_override("panel", info_style)
	_hud_canvas.add_child(_info_box)

	var stat_vbox := VBoxContainer.new()
	stat_vbox.add_theme_constant_override("separation", 4)
	_info_box.add_child(stat_vbox)

	var mode_tag := Label.new()
	mode_tag.text = "⚔️ 1v1 追缉逃生模式"
	mode_tag.add_theme_font_size_override("font_size", 13)
	mode_tag.modulate = Color(0.4, 0.85, 1.0)
	stat_vbox.add_child(mode_tag)

	_survival_label = Label.new()
	_survival_label.text = "逃生生存时间: 00:00.0"
	_survival_label.add_theme_font_size_override("font_size", 12)
	stat_vbox.add_child(_survival_label)

	_distance_label = Label.new()
	_distance_label.text = "距离追缉者: -- m"
	_distance_label.add_theme_font_size_override("font_size", 12)
	stat_vbox.add_child(_distance_label)

	_status_detail_label = Label.new()
	_status_detail_label.text = "追缉者状态: 准备中"
	_status_detail_label.add_theme_font_size_override("font_size", 11)
	_status_detail_label.modulate = Color(1.0, 1.0, 1.0, 0.65)
	stat_vbox.add_child(_status_detail_label)

	_hint_x_toggle_label = Label.new()
	_hint_x_toggle_label.text = "AI路线与红柱: 已隐藏 (连按两下X显示)"
	_hint_x_toggle_label.add_theme_font_size_override("font_size", 11)
	_hint_x_toggle_label.modulate = Color(0.7, 0.7, 0.7, 0.65)
	stat_vbox.add_child(_hint_x_toggle_label)

	_hint_tab_label = Label.new()
	_hint_tab_label.text = "【Tab】视角: 第三人称操纵 (按Tab切换全局指挥)"
	_hint_tab_label.add_theme_font_size_override("font_size", 11)
	_hint_tab_label.modulate = Color(0.7, 0.8, 0.9, 0.75)
	stat_vbox.add_child(_hint_tab_label)

	_crosshair = Crosshair.new()
	_crosshair.visible = false
	_hud_canvas.add_child(_crosshair)

	_build_map_select_dialog()
	_build_game_over_dialog()


func _create_9patch_style(texture_path: String, ml: float, mt: float, mr: float, mb: float, cl: float = 16.0, ct: float = 14.0, cr: float = 16.0, cb: float = 14.0) -> StyleBoxTexture:
	var sbox := StyleBoxTexture.new()
	if ResourceLoader.exists(texture_path):
		sbox.texture = load(texture_path)
	sbox.texture_margin_left = ml
	sbox.texture_margin_top = mt
	sbox.texture_margin_right = mr
	sbox.texture_margin_bottom = mb
	sbox.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sbox.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sbox.content_margin_left = cl
	sbox.content_margin_top = ct
	sbox.content_margin_right = cr
	sbox.content_margin_bottom = cb
	return sbox


func _update_escape_countdown_hud() -> void:
	if _banner_style != null:
		_banner_style.border_color = Color(1.0, 0.85, 0.25, 0.75)
	_banner_title.text = "⏳ 逃生准备倒计时: %.1f 秒" % _escape_timer
	_banner_title.modulate = Color(1.0, 0.9, 0.3)
	_banner_sub.text = "尽快利用地形与跳跃拉开距离！存活满 2 分钟即可逃生胜利！"
	_survival_label.text = "逃生倒计时: %.1f s (追缉限时 2 分钟)" % _escape_timer
	_status_detail_label.text = "追缉者状态: 锁定原地倒计时中"


func _update_active_chase_hud() -> void:
	if _banner_style != null:
		_banner_style.border_color = Color(1.0, 0.35, 0.35, 0.75)
	_banner_title.text = "🚨 追缉进行中！全力逃生！"
	_banner_title.modulate = Color(1.0, 0.4, 0.4)

	var dist := _player.global_position.distance_to(_npc.global_position) if _player and _npc else 0.0
	_banner_sub.text = "追缉者距离: %.1fm (接近至 1.5m 判定捕获 | 存活 2 分钟获胜)" % dist

	var rem_time := maxf(0.0, CHASE_TIME_LIMIT - _survival_time)
	var rem_m := int(rem_time) / 60
	var rem_s := fmod(rem_time, 60.0)
	var surv_m := int(_survival_time) / 60
	var surv_s := fmod(_survival_time, 60.0)
	_survival_label.text = "剩余逃生时间: %02d:%05.2f (已存活: %02d:%02d)" % [rem_m, rem_s, surv_m, int(surv_s)]
	_distance_label.text = "距离追缉者: %.1f 米" % dist
	if dist < 3.0:
		_distance_label.modulate = Color(1.0, 0.2, 0.2)
	elif dist < 6.0:
		_distance_label.modulate = Color(1.0, 0.8, 0.2)
	else:
		_distance_label.modulate = Color(0.3, 1.0, 0.5)

	var p_cell := _nav.standing_node(_player.global_position)
	var n_cell := _nav.standing_node(_npc.global_position)
	var same_plat := _nav.is_same_flat_platform(n_cell, p_cell)
	_status_detail_label.text = "追缉者寻路: A* 智能路径规划 (%s)" % ("同平台高频 60ms" if same_plat else "跨障碍 250ms")


func _build_map_select_dialog() -> void:
	_map_select_dialog = PanelContainer.new()
	_map_select_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_map_select_dialog.offset_left = -270
	_map_select_dialog.offset_right = 270
	_map_select_dialog.offset_top = -210
	_map_select_dialog.offset_bottom = 210
	_map_select_dialog.custom_minimum_size = Vector2(540, 420)
	var diag_style := _create_9patch_style("res://assets/UI_assets/panel_exquisite.png", 50.0, 45.0, 50.0, 45.0, 20.0, 20.0, 20.0, 20.0)
	_map_select_dialog.add_theme_stylebox_override("panel", diag_style)
	_hud_canvas.add_child(_map_select_dialog)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_map_select_dialog.add_child(vbox)

	var title := Label.new()
	title.text = "⚔️ 追缉模式 · 选择逃生与追缉地图"
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = "请从保存的地图中选择一张开始追缉挑战。\n开局有 15 秒逃生准备时间，追缉者将按规则全速追捕！"
	desc.add_theme_font_size_override("font_size", 12)
	desc.modulate = Color(1.0, 1.0, 1.0, 0.75)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(desc)

	_map_list = ItemList.new()
	_map_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_list.custom_minimum_size = Vector2(0, 180)
	vbox.add_child(_map_list)

	var btn_box := HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_box)

	var start_btn := Button.new()
	start_btn.text = "开始追缉 (Start Chase)"
	start_btn.custom_minimum_size = Vector2(180, 36)
	start_btn.pressed.connect(_on_start_map_pressed)
	btn_box.add_child(start_btn)

	var back_btn := Button.new()
	back_btn.text = "返回主菜单 (ESC)"
	back_btn.custom_minimum_size = Vector2(140, 36)
	back_btn.pressed.connect(func() -> void: SceneLoader.change_scene(get_tree(), MENU_SCENE, "返回主菜单..."))
	btn_box.add_child(back_btn)


func _open_map_select_dialog() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_banner_panel.visible = false
	_info_box.visible = false
	_game_over_dialog.visible = false
	_map_select_dialog.visible = true

	_map_list.clear()
	var maps := MapDataScript.list_available_maps()
	if maps.is_empty():
		_map_list.add_item("默认空旷平地地图 (Default Flat Map)")
		_map_list.set_item_metadata(0, "")
	else:
		for i in range(maps.size()):
			var m: Dictionary = maps[i]
			var f_name: String = str(m.get("file_name", m.get("name", "map")))
			var display_name := "%s (%s)" % [m.get("name", "未命名"), f_name]
			_map_list.add_item(display_name)
			_map_list.set_item_metadata(i, m.get("path", ""))
	_map_list.select(0)


func _on_start_map_pressed() -> void:
	var selected := _map_list.get_selected_items()
	if selected.is_empty():
		return
	var idx := selected[0]
	var path: String = str(_map_list.get_item_metadata(idx))
	if not path.is_empty():
		_load_map_data(path)
	else:
		_clear_all_blocks()
		_nav.clear_special_paths()
		_player_spawn = Vector3(0.5, 0.2, 0.5)
		_npc_spawn = Vector3(0.5, 0.2, -10.5)

	_start_escape_countdown()


func _build_game_over_dialog() -> void:
	_game_over_dialog = PanelContainer.new()
	_game_over_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_game_over_dialog.offset_left = -230
	_game_over_dialog.offset_right = 230
	_game_over_dialog.offset_top = -150
	_game_over_dialog.offset_bottom = 150
	_game_over_dialog.custom_minimum_size = Vector2(460, 300)
	var diag_style := _create_9patch_style("res://assets/UI_assets/panel_exquisite.png", 50.0, 45.0, 50.0, 45.0, 24.0, 24.0, 24.0, 22.0)
	_game_over_dialog.add_theme_stylebox_override("panel", diag_style)
	_game_over_dialog.visible = false
	_hud_canvas.add_child(_game_over_dialog)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	_game_over_dialog.add_child(vbox)

	_game_over_title = Label.new()
	_game_over_title.text = "💀 追缉者获胜！"
	_game_over_title.add_theme_font_size_override("font_size", 22)
	_game_over_title.modulate = Color(1.0, 0.4, 0.4)
	_game_over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_game_over_title)

	_game_over_time_lbl = Label.new()
	_game_over_time_lbl.text = "本次生存逃生时间: 00:00.0"
	_game_over_time_lbl.add_theme_font_size_override("font_size", 14)
	_game_over_time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_game_over_time_lbl)

	var btn_box := HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 14)
	vbox.add_child(btn_box)

	var retry_btn := Button.new()
	retry_btn.text = "重新挑战"
	retry_btn.custom_minimum_size = Vector2(100, 36)
	retry_btn.pressed.connect(_start_escape_countdown)
	btn_box.add_child(retry_btn)

	var change_btn := Button.new()
	change_btn.text = "更换地图"
	change_btn.custom_minimum_size = Vector2(100, 36)
	change_btn.pressed.connect(_open_map_select_dialog)
	btn_box.add_child(change_btn)

	var menu_btn := Button.new()
	menu_btn.text = "主菜单"
	menu_btn.custom_minimum_size = Vector2(100, 36)
	menu_btn.pressed.connect(func() -> void: SceneLoader.change_scene(get_tree(), MENU_SCENE, "返回主菜单..."))
	btn_box.add_child(menu_btn)
