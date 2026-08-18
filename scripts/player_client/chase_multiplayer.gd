extends Node3D
## 1v1 LAN Multiplayer Pursuit Match Controller.
## Supports dual-side Tab tactical commander A* pathfinding, 30Hz snapshot synchronization, and jitter buffer interpolation.

const NavGridScript = preload("res://scripts/nav_grid.gd")
const BlockRegistryScript = preload("res://scripts/block_registry.gd")
const MapDataScript = preload("res://scripts/map_data.gd")
const CharacterPipelineScript = preload("res://tools/character_pipeline.gd")
const PlayerControllerScript = preload("res://scripts/player_controller.gd")
const PlayerIntentSourceScript = preload("res://scripts/player_intent_source.gd")
const NPCIntentSourceScript = preload("res://scripts/npc_intent_source.gd")
const FollowCameraScript = preload("res://scripts/follow_camera.gd")
const SnapshotInterpolatorScript = preload("res://scripts/network/snapshot_interpolator.gd")
const AudioManagerScript = preload("res://scripts/audio_manager.gd")

const LOBBY_SCENE := "res://scenes/player_client/multiplayer_lobby.tscn"
const TITLE_SCENE := "res://scenes/player_client/title_screen.tscn"
const FONT_PATH := "res://assets/Fonts/Long_Cang/LongCang-Regular.ttf"

const GROUND_HALF := 25.0
const MAX_BLOCK_Y := 12
const ESCAPE_COUNTDOWN_TIME := 15.0
const CHASE_TIME_LIMIT := 120.0
const CATCH_DISTANCE_THRESHOLD := 1.5
const SNAPSHOT_INTERVAL := 0.033 # 30Hz

enum State {
	PREPARE_COUNTDOWN,
	CHASE_ACTIVE,
	MATCH_OVER,
}

var _state: State = State.PREPARE_COUNTDOWN
var _escape_timer := ESCAPE_COUNTDOWN_TIME
var _survival_time := 0.0
var _last_countdown_voice := -1
var _snapshot_timer := 0.0

var _nav = NavGridScript.new()
var _blocks: Dictionary = {}
var _cell_to_block_id: Dictionary = {}

# Entities
var _local_body: CharacterBody3D
var _remote_body: CharacterBody3D
var _local_player_intent: PlayerIntentSource
var _local_npc_intent: NPCIntentSource
var _remote_interpolator: SnapshotInterpolator

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

var _runner_spawn := Vector3(0.5, 0.2, 0.5)
var _chaser_spawn := Vector3(0.5, 0.2, -10.5)

var _local_path_mesh: MeshInstance3D
var _local_path_imm: ImmediateMesh
var _local_beacon: MeshInstance3D

var _hud_canvas: CanvasLayer
var _crosshair: Control
var _banner_panel: PanelContainer
var _banner_style: StyleBoxTexture
var _banner_icon: TextureRect
var _banner_title: Label
var _banner_sub: Label

var _info_box: PanelContainer
var _survival_label: Label
var _distance_label: Label
var _status_detail_label: Label
var _hint_tab_label: Label
var _custom_font: Font = null

var _game_over_dialog: PanelContainer
var _game_over_icon: TextureRect
var _game_over_title: Label
var _game_over_desc: Label
var _game_over_time_lbl: Label


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


func _ready() -> void:
	AudioManagerScript.init_pool(self)
	if ResourceLoader.exists(FONT_PATH):
		_custom_font = load(FONT_PATH) as Font

	BlockRegistryScript.init_registry()
	_nav.set_bounds(int(GROUND_HALF), MAX_BLOCK_Y + 1)

	_build_environment()
	_build_ground()
	_build_visual_helpers()
	_build_camera()
	_build_characters()
	_build_hud()

	var map_path := NetworkManager.selected_map_path
	if not map_path.is_empty() and FileAccess.file_exists(map_path):
		_load_map_data(map_path)
	else:
		_clear_all_blocks()
		_nav.clear_special_paths()
		_nav.rebuild()
		if _local_body != null:
			_nav.set_capability(_local_body)

	_reset_match_positions()
	_start_prepare_countdown()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_exit_to_lobby()
			return
		elif event.keycode == KEY_TAB:
			_toggle_commander_mode()
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
			_command_local_npc(_aim_point)
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _commander_mode:
		_drive_commander_camera(delta)
		_cast_crosshair()

	if _remote_interpolator != null:
		_remote_interpolator.update_interpolation(delta)


func _physics_process(delta: float) -> void:
	match _state:
		State.PREPARE_COUNTDOWN:
			_escape_timer = maxf(0.0, _escape_timer - delta)
			_update_countdown_hud()

			var cur_sec := int(ceil(_escape_timer))
			if cur_sec in [5, 4, 3, 2, 1] and cur_sec != _last_countdown_voice:
				_last_countdown_voice = cur_sec
				AudioManagerScript.play_countdown(cur_sec, true)

			# Keep Chaser stationary during countdown
			if NetworkManager.local_role == NetworkManager.Role.CHASER:
				if _local_body != null:
					_local_body.velocity = Vector3.ZERO
				if _local_npc_intent != null:
					_local_npc_intent.clear_target()

			if _escape_timer <= 0.0:
				_start_active_chase()

		State.CHASE_ACTIVE:
			_survival_time += delta
			_update_active_hud()

			# Host-authoritative win/loss evaluation
			if NetworkManager.is_host and _local_body != null and _remote_body != null:
				if _survival_time >= CHASE_TIME_LIMIT:
					rpc("rpc_match_over", int(NetworkManager.Role.RUNNER), "逃生者成功坚持存活满 2 分钟！")
					return

				var runner_pos := _local_body.global_position if NetworkManager.local_role == NetworkManager.Role.RUNNER else _remote_body.global_position
				var chaser_pos := _local_body.global_position if NetworkManager.local_role == NetworkManager.Role.CHASER else _remote_body.global_position
				var dist := runner_pos.distance_to(chaser_pos)
				var vert_dist := absf(runner_pos.y - chaser_pos.y)
				if dist <= CATCH_DISTANCE_THRESHOLD and vert_dist <= 1.5:
					rpc("rpc_match_over", int(NetworkManager.Role.CHASER), "追缉者已逼近至 1.5 米范围内判定捕获！")
					return

	# Network snapshot transmission (30Hz)
	if multiplayer.has_multiplayer_peer() and _local_body != null:
		_snapshot_timer += delta
		if _snapshot_timer >= SNAPSHOT_INTERVAL:
			_snapshot_timer = 0.0
			_send_local_snapshot()


func _send_local_snapshot() -> void:
	if _local_body == null:
		return
	var snap := {
		"time": float(Time.get_ticks_msec()) * 0.001,
		"pos": _local_body.global_position,
		"yaw": _local_body.rotation.y,
		"vel": _local_body.velocity,
		"anim": "",
		"state": int(_local_body.state)
	}
	rpc("rpc_receive_snapshot", snap)


@rpc("any_peer", "call_remote", "unreliable")
func rpc_receive_snapshot(snap: Dictionary) -> void:
	if _remote_interpolator != null:
		_remote_interpolator.push_snapshot(snap)


@rpc("authority", "call_local", "reliable")
func rpc_match_over(winning_role_val: int, reason_text: String) -> void:
	_state = State.MATCH_OVER
	if _local_npc_intent != null:
		_local_npc_intent.clear_target()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var i_win: bool = (NetworkManager.local_role == winning_role_val)
	if i_win:
		AudioManagerScript.play_win(true)
	else:
		AudioManagerScript.play_lose(true)

	if _game_over_title != null:
		_game_over_title.text = "🏆 胜 利 ！" if i_win else "💀 战 败 ！"
		_game_over_title.modulate = Color(0.3, 1.0, 0.5) if i_win else Color(1.0, 0.35, 0.35)

	if _game_over_desc != null:
		_game_over_desc.text = reason_text
		_game_over_desc.modulate = Color(0.9, 0.9, 0.9)

	var m := int(_survival_time) / 60
	var s := fmod(_survival_time, 60.0)
	if _game_over_time_lbl != null:
		_game_over_time_lbl.text = "对决持续时间: %02d:%05.2f" % [m, s]
		_game_over_time_lbl.modulate = Color(1.0, 0.85, 0.3)

	_game_over_dialog.visible = true
	_banner_panel.visible = false
	_local_beacon.visible = false


func _start_prepare_countdown() -> void:
	_state = State.PREPARE_COUNTDOWN
	_escape_timer = ESCAPE_COUNTDOWN_TIME
	_survival_time = 0.0
	_last_countdown_voice = -1
	_game_over_dialog.visible = false
	_banner_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	AudioManagerScript.play_countdown(5, true)


func _start_active_chase() -> void:
	_state = State.CHASE_ACTIVE
	AudioManagerScript.play_go(true)


func _reset_match_positions() -> void:
	if NetworkManager.local_role == NetworkManager.Role.RUNNER:
		_local_body.global_position = _runner_spawn
		_remote_body.global_position = _chaser_spawn
	else:
		_local_body.global_position = _chaser_spawn
		_remote_body.global_position = _runner_spawn

	if _camera != null:
		_camera.snap()


func _build_visual_helpers() -> void:
	_local_path_imm = ImmediateMesh.new()
	_local_path_mesh = MeshInstance3D.new()
	_local_path_mesh.mesh = _local_path_imm
	var p_mat := StandardMaterial3D.new()
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.vertex_color_use_as_albedo = true
	p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p_mat.no_depth_test = true
	_local_path_mesh.material_override = p_mat
	_local_path_mesh.visible = false
	add_child(_local_path_mesh)

	_local_beacon = MeshInstance3D.new()
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
	_local_beacon.mesh = p_cyl
	_local_beacon.material_override = pb_mat
	_local_beacon.position.y = 0.8
	_local_beacon.visible = false
	add_child(_local_beacon)

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
	var chars := CharacterPipelineScript.list_characters().filter(
		func(c: Dictionary) -> bool: return ResourceLoader.exists(c.scene))
	var local_char_idx := 0 if NetworkManager.local_role == NetworkManager.Role.RUNNER else 1
	var remote_char_idx := 1 if NetworkManager.local_role == NetworkManager.Role.RUNNER else 0

	# Local entity (Possessed / Commander)
	_local_body = PlayerControllerScript.new()
	_local_body.name = "LocalPlayer"
	_local_body.position = _runner_spawn if NetworkManager.local_role == NetworkManager.Role.RUNNER else _chaser_spawn
	_local_player_intent = PlayerIntentSourceScript.new()
	_local_npc_intent = NPCIntentSourceScript.new()
	_local_npc_intent.bind_nav_grid(_nav)
	_local_npc_intent.repath_requested.connect(_on_local_npc_repath_requested)
	_local_body.intent_source = _local_player_intent
	add_child(_local_body)
	_spawn_visual(_local_body, chars, local_char_idx, true)

	# Remote entity (Network Interpolated)
	_remote_body = PlayerControllerScript.new()
	_remote_body.name = "RemotePlayer"
	_remote_body.position = _chaser_spawn if NetworkManager.local_role == NetworkManager.Role.RUNNER else _runner_spawn
	_remote_interpolator = SnapshotInterpolatorScript.new()
	_remote_interpolator.setup(_remote_body)
	add_child(_remote_body)
	_spawn_visual(_remote_body, chars, remote_char_idx, false)


func _spawn_visual(body: CharacterBody3D, chars: Array, char_idx: int, is_local: bool) -> void:
	if chars.is_empty():
		return
	var entry: Dictionary = chars[clamp(char_idx, 0, chars.size() - 1)]
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

	if is_local:
		body.setup(visual, _camera)
		_camera.target = _local_body
		_camera.frame_for(height)
		_camera.snap()
		_nav.set_capability(_local_body)
	else:
		body.setup(visual, null)
		body.set_physics_process(false)
		body.set_process_unhandled_input(false)


func _toggle_commander_mode() -> void:
	_commander_mode = not _commander_mode
	if _commander_mode:
		_commander_camera.global_position = _camera.global_position + Vector3(0.0, 3.5, 0.0)
		_cam_yaw = _local_body.rotation.y + PI
		_cam_pitch = -0.65
		_apply_commander_cam_orientation()
		_commander_camera.current = true
		_local_body.intent_source = _local_npc_intent
		if _crosshair != null:
			_crosshair.visible = true
		if _hint_tab_label != null:
			_hint_tab_label.text = "【Tab】视角: 全局指挥 (Shift+左键 指挥己方NPC跑位)"
			_hint_tab_label.modulate = Color(0.2, 0.9, 1.0, 0.95)
	else:
		_camera.current = true
		_local_body.intent_source = _local_player_intent
		if _crosshair != null:
			_crosshair.visible = false
		if _highlight != null:
			_highlight.visible = false
		_has_aim = false
		_local_beacon.visible = false
		_local_path_mesh.visible = false
		_local_npc_intent.clear_target()
		if _hint_tab_label != null:
			_hint_tab_label.text = "【Tab】视角: 亲自操控 (按Tab切换全局指挥)"
			_hint_tab_label.modulate = Color(0.7, 0.8, 0.9, 0.75)


func _command_local_npc(target: Vector3) -> void:
	if _local_body == null or _local_npc_intent == null:
		return
	var cell := _nav.standing_node(target)
	if cell == NavGridScript.NO_CELL:
		return
	var goal_pos := NavGridScript.foot(cell)
	var result := _nav.find_path(_local_body.global_position, goal_pos)
	if result.points.is_empty():
		return
	_local_npc_intent.set_plan_result(result)
	_draw_local_path(result.points)
	_local_beacon.global_position = goal_pos
	_local_beacon.visible = true


func _on_local_npc_repath_requested(from_pos: Vector3, target: Vector3) -> void:
	if not _commander_mode or _local_npc_intent == null:
		return
	var result := _nav.find_path(from_pos, target)
	if result.points.is_empty():
		_local_npc_intent.clear_target()
		_local_beacon.visible = false
		_local_path_mesh.visible = false
		return
	_local_npc_intent.set_plan_result(result)
	_draw_local_path(result.points)


func _draw_local_path(points: PackedVector3Array) -> void:
	_local_path_imm.clear_surfaces()
	if points.size() < 2:
		return
	_local_path_imm.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(1, points.size()):
		var p1 := points[i - 1] + Vector3(0.0, 0.08, 0.0)
		var p2 := points[i] + Vector3(0.0, 0.08, 0.0)
		var col := Color(0.15, 0.85, 1.0, 0.95)
		_local_path_imm.surface_set_color(col)
		_local_path_imm.surface_add_vertex(p1)
		_local_path_imm.surface_set_color(col)
		_local_path_imm.surface_add_vertex(p2)
	_local_path_imm.surface_end()
	_local_path_mesh.visible = true


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


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.18, 0.22, 0.30)
	sky_mat.sky_horizon_color = Color(0.55, 0.45, 0.40)
	sky_mat.ground_bottom_color = Color(0.08, 0.08, 0.10)
	sky_mat.ground_horizon_color = Color(0.40, 0.42, 0.48)

	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var env_node := WorldEnvironment.new()
	env_node.environment = env
	add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 35.0, 0.0)
	sun.light_energy = 1.3
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


func _load_map_data(path: String) -> void:
	var data := MapDataScript.load_map_from_file(path)
	if data.is_empty():
		return
	_clear_all_blocks()
	_nav.clear_special_paths()

	var blocks_data: Array = data.get("blocks", [])
	for b in blocks_data:
		var pos_arr: Array = b.get("pos", [0, 0, 0])
		var grid_pos := Vector3i(int(pos_arr[0]), int(pos_arr[1]), int(pos_arr[2]))
		var block_id: String = str(b.get("id", "stone"))
		var size_idx: int = int(b.get("size", 1))
		var mat_idx: int = int(b.get("mat", 0))

		var inst: BlockRegistry.BlockInstance = BlockRegistryScript.create_block(block_id, grid_pos, size_idx, mat_idx)
		if inst != null and inst.body_node != null:
			add_child(inst.body_node)
			_blocks[grid_pos] = inst
			_cell_to_block_id[grid_pos] = block_id
			for cell in inst.occupied_cells:
				_nav.set_block(cell, true)

	var sp_paths: Array = data.get("special_paths", [])
	for p_dict in sp_paths:
		if p_dict is Dictionary:
			_nav.add_special_path(p_dict)

	_nav.rebuild()
	if _local_body != null:
		_nav.set_capability(_local_body)

	var p_stand := _nav.standing_node(_runner_spawn)
	if p_stand != NavGridScript.NO_CELL:
		_runner_spawn = NavGridScript.foot(p_stand) + Vector3(0.0, 0.05, 0.0)

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
		_chaser_spawn = NavGridScript.foot(best_npc_cell) + Vector3(0.0, 0.05, 0.0)
	else:
		_chaser_spawn = _runner_spawn + Vector3(0.0, 0.05, -8.0)


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

	_banner_panel = PanelContainer.new()
	_banner_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner_panel.offset_left = -310
	_banner_panel.offset_right = 310
	_banner_panel.offset_top = 16
	_banner_panel.offset_bottom = 104
	_banner_panel.custom_minimum_size = Vector2(620, 88)
	_banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_banner_style = _create_9patch_style("res://assets/UI_assets/panel_alarm.png", 60.0, 55.0, 60.0, 50.0, 24.0, 16.0, 24.0, 16.0)
	_banner_panel.add_theme_stylebox_override("panel", _banner_style)
	_hud_canvas.add_child(_banner_panel)

	var banner_hbox := HBoxContainer.new()
	banner_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	banner_hbox.add_theme_constant_override("separation", 14)
	_banner_panel.add_child(banner_hbox)

	_banner_icon = TextureRect.new()
	if ResourceLoader.exists("res://assets/UI_assets/extra-time.svg"):
		_banner_icon.texture = load("res://assets/UI_assets/extra-time.svg")
	_banner_icon.custom_minimum_size = Vector2(44, 44)
	_banner_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_banner_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	banner_hbox.add_child(_banner_icon)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 2)
	banner_hbox.add_child(vbox)

	_banner_title = Label.new()
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_title.add_theme_font_size_override("font_size", 20)
	_banner_title.text = "准备倒计时: 15.0 秒"
	vbox.add_child(_banner_title)

	_banner_sub = Label.new()
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub.add_theme_font_size_override("font_size", 13)
	_banner_sub.text = "对决即将开始！存活满 2 分钟逃生者获胜！"
	_banner_sub.modulate = Color(1.0, 1.0, 1.0, 0.88)
	vbox.add_child(_banner_sub)

	# Stats overlay
	_info_box = PanelContainer.new()
	_info_box.offset_left = 20
	_info_box.offset_top = 20
	_info_box.custom_minimum_size = Vector2(280, 120)
	_info_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var info_style := StyleBoxEmpty.new()
	_info_box.add_theme_stylebox_override("panel", info_style)
	_hud_canvas.add_child(_info_box)

	var stat_vbox := VBoxContainer.new()
	stat_vbox.add_theme_constant_override("separation", 4)
	_info_box.add_child(stat_vbox)

	var mode_tag := Label.new()
	mode_tag.text = "🌐 局域网联机对决 (%s)" % ("我是逃生者" if NetworkManager.local_role == NetworkManager.Role.RUNNER else "我是追缉者")
	if _custom_font != null:
		mode_tag.add_theme_font_override("font", _custom_font)
	mode_tag.add_theme_font_size_override("font_size", 16)
	mode_tag.modulate = Color(0.3, 0.9, 1.0)
	stat_vbox.add_child(mode_tag)

	_survival_label = Label.new()
	_survival_label.text = "对决时间: 00:00.0"
	if _custom_font != null:
		_survival_label.add_theme_font_override("font", _custom_font)
	_survival_label.add_theme_font_size_override("font_size", 14)
	stat_vbox.add_child(_survival_label)

	_distance_label = Label.new()
	_distance_label.text = "双方距离: -- 米"
	if _custom_font != null:
		_distance_label.add_theme_font_override("font", _custom_font)
	_distance_label.add_theme_font_size_override("font_size", 14)
	stat_vbox.add_child(_distance_label)

	_status_detail_label = Label.new()
	_status_detail_label.text = "网络延迟补偿: Jitter Buffer (80ms)"
	_status_detail_label.add_theme_font_size_override("font_size", 12)
	_status_detail_label.modulate = Color(1.0, 1.0, 1.0, 0.65)
	stat_vbox.add_child(_status_detail_label)

	_hint_tab_label = Label.new()
	_hint_tab_label.text = "【Tab】视角: 亲自操控 (按Tab切换全局指挥)"
	if _custom_font != null:
		_hint_tab_label.add_theme_font_override("font", _custom_font)
	_hint_tab_label.add_theme_font_size_override("font_size", 13)
	_hint_tab_label.modulate = Color(0.7, 0.8, 0.9, 0.75)
	stat_vbox.add_child(_hint_tab_label)

	_crosshair = Crosshair.new()
	_crosshair.visible = false
	_hud_canvas.add_child(_crosshair)

	_build_game_over_dialog()


func _update_countdown_hud() -> void:
	if _banner_style != null:
		_banner_style.modulate_color = Color(1.0, 0.92, 0.65, 0.98)
	_banner_title.text = "对决准备倒计时: %.1f 秒" % _escape_timer
	_banner_sub.text = "逃生者尽快拉开距离！倒计时结束后追缉者出动！"


func _update_active_hud() -> void:
	if _banner_style != null:
		_banner_style.modulate_color = Color(1.0, 0.70, 0.70, 0.98)
	_banner_title.text = "追缉进行中！全力以赴！"
	var dist := _local_body.global_position.distance_to(_remote_body.global_position) if _local_body and _remote_body else 0.0
	_banner_sub.text = "双方距离: %.1fm (接近至 1.5m 判定捕获 | 存活 2 分钟逃生胜)" % dist

	var rem_time := maxf(0.0, CHASE_TIME_LIMIT - _survival_time)
	var rem_m := int(rem_time) / 60
	var rem_s := fmod(rem_time, 60.0)
	_survival_label.text = "剩余时间: %02d:%05.2f" % [rem_m, rem_s]
	_distance_label.text = "双方距离: %.1f 米" % dist
	if dist < 3.0:
		_distance_label.modulate = Color(1.0, 0.2, 0.2)
	elif dist < 6.0:
		_distance_label.modulate = Color(1.0, 0.8, 0.2)
	else:
		_distance_label.modulate = Color(0.3, 1.0, 0.5)


func _build_game_over_dialog() -> void:
	_game_over_dialog = PanelContainer.new()
	_game_over_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_game_over_dialog.offset_left = -230
	_game_over_dialog.offset_right = 230
	_game_over_dialog.offset_top = -175
	_game_over_dialog.offset_bottom = 175
	_game_over_dialog.custom_minimum_size = Vector2(460, 350)
	_game_over_dialog.visible = false

	var diag_style := _create_9patch_style("res://assets/UI_assets/panel_exquisite.png", 50.0, 45.0, 50.0, 45.0, 24.0, 24.0, 24.0, 22.0)
	_game_over_dialog.add_theme_stylebox_override("panel", diag_style)
	_hud_canvas.add_child(_game_over_dialog)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	_game_over_dialog.add_child(vbox)

	_game_over_title = Label.new()
	_game_over_title.text = "对 决 结 束"
	_game_over_title.add_theme_font_size_override("font_size", 24)
	_game_over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_game_over_title)

	_game_over_desc = Label.new()
	_game_over_desc.text = "结算说明"
	_game_over_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_game_over_desc)

	_game_over_time_lbl = Label.new()
	_game_over_time_lbl.text = "对决时间: 00:00.0"
	_game_over_time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_game_over_time_lbl)

	var btn_box := HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_box)

	var lobby_btn := Button.new()
	lobby_btn.text = "返回联机大厅"
	lobby_btn.custom_minimum_size = Vector2(130, 38)
	lobby_btn.pressed.connect(_on_exit_to_lobby)
	btn_box.add_child(lobby_btn)

	var title_btn := Button.new()
	title_btn.text = "返回主菜单"
	title_btn.custom_minimum_size = Vector2(120, 38)
	title_btn.pressed.connect(func(): NetworkManager.close_network(); SceneLoader.change_scene(get_tree(), TITLE_SCENE, "返回主界面..."))
	btn_box.add_child(title_btn)


func _on_exit_to_lobby() -> void:
	SceneLoader.change_scene(get_tree(), LOBBY_SCENE, "返回联机大厅...")


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
