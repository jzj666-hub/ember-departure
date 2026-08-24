extends Node3D
## User client dedicated 1v1 Pursuit game scene.
## Clean game-feel UI with zero web emojis, full voiceover, keycap guide, and dynamic AI rules.

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const AnimPipelineScript = preload("res://tools/anim_pipeline.gd")
const NavGridScript = preload("res://scripts/nav_grid.gd")
const BlockRegistryScript = preload("res://scripts/block_registry.gd")
const MapDataScript = preload("res://scripts/map_data.gd")
const CharacterPipelineScript = preload("res://tools/character_pipeline.gd")
const PlayerControllerScript = preload("res://scripts/player_controller.gd")
const PlayerIntentSourceScript = preload("res://scripts/player_intent_source.gd")
const NPCIntentSourceScript = preload("res://scripts/npc_intent_source.gd")
const FollowCameraScript = preload("res://scripts/follow_camera.gd")
const SkillLoadoutScript = preload("res://scripts/skills/skill_loadout.gd")
const SkillDrawPanelScript = preload("res://scripts/player_client/skill_draw_panel.gd")
const SkillAimScript = preload("res://scripts/skills/skill_aim.gd")
const SkillRegistryScript = preload("res://scripts/skills/skill_registry.gd")
const KeybindManagerScript = preload("res://scripts/keybind_manager.gd")
const WorldBuilderScript = preload("res://scripts/world/world_builder.gd")
const ENV_PRESET = preload("res://config/env/chase_dusk.tres")
const GROUND_PRESET = preload("res://config/ground/chase_grid.tres")

const TITLE_SCENE := "res://scenes/player_client/title_screen.tscn"
const FONT_PATH := "res://assets/Fonts/Long_Cang/LongCang-Regular.ttf"
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
	PREPARE,
	ESCAPE_COUNTDOWN,
	CHASE_ACTIVE,
	GAME_OVER,
}

var preloaded_map_path: String = ""
var _custom_font: Font = null

var _skill_label: Label
var _skill_loadout: SkillLoadout
var _skill_draw_panel: SkillDrawPanel
var _skill_aim: SkillAim

static var next_map_path: String = ""

var _state: State = State.PREPARE
var _escape_timer: float = ESCAPE_COUNTDOWN_TIME
var _last_countdown_voice := 16
var _survival_time: float = 0.0

var _nav = NavGridScript.new()
var _blocks: Dictionary = {}
var _cell_to_block_id: Dictionary = {}
var _map_name := "默认对决战场"

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

# HUD Elements
var _hud_canvas: CanvasLayer
var _crosshair: Control
var _banner_panel: PanelContainer
var _banner_style: StyleBoxFlat
var _banner_icon: TextureRect
var _banner_title: Label
var _banner_sub: Label

var _info_box: PanelContainer
var _survival_label: Label
var _distance_label: Label
var _status_detail_label: Label
var _hint_x_toggle_label: Label
var _hint_tab_label: Label
var _keycaps_overlay: PanelContainer

var _game_over_dialog: PanelContainer
var _game_over_icon: TextureRect
var _game_over_title: Label
var _game_over_desc: Label
var _game_over_time_lbl: Label


func _ready() -> void:
	if not next_map_path.is_empty():
		preloaded_map_path = next_map_path
		next_map_path = ""

	AudioManagerScript.init_pool(self)
	BlockRegistryScript.init_registry()

	if ResourceLoader.exists(FONT_PATH):
		_custom_font = load(FONT_PATH) as Font

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

	if not preloaded_map_path.is_empty() and FileAccess.file_exists(preloaded_map_path):
		_load_map_data(preloaded_map_path)
	else:
		_clear_all_blocks()
		_nav.clear_special_paths()
		_nav.rebuild()
		_nav.set_capability(_npc)

	_setup_skill_draw()
	_start_escape_countdown()


# --- Skill draw & casting ----------------------------------------------------

## Player is always the runner here, so the draw comes from the runner pool.
func _setup_skill_draw() -> void:
	SkillRegistryScript.init_registry()
	SkillRegistryScript.warmup_all_shaders(self)

	_skill_loadout = SkillLoadoutScript.new()
	_skill_loadout.name = "SkillLoadout"
	add_child(_skill_loadout)
	_skill_loadout.setup(_player, self, true)
	_skill_loadout.cooldown_changed.connect(_on_skill_cooldown_changed)

	_skill_aim = SkillAimScript.new()
	_skill_aim.name = "SkillAim"
	add_child(_skill_aim)
	_skill_aim.setup(_camera)

	_skill_draw_panel = SkillDrawPanelScript.new()
	_skill_draw_panel.name = "SkillDrawPanel"
	add_child(_skill_draw_panel)

	var rolled := _skill_loadout.roll()
	if rolled.is_empty():
		return
	var names: Array[String] = []
	for s_id in _skill_loadout.candidates():
		names.append(_skill_loadout.display_name_of(s_id))
	_skill_draw_panel.play(names, _skill_loadout.display_name_of(rolled))
	_refresh_skill_hud()


func _on_skill_cooldown_changed(_left: float, _total: float) -> void:
	_refresh_skill_hud()


func _refresh_skill_hud() -> void:
	if _skill_label == null or _skill_loadout == null:
		return
	_skill_label.text = _skill_loadout.hud_text(_skill_key_label())


func _skill_key_label() -> String:
	var km = KeybindManagerScript.get_instance()
	if km == null:
		return "1"
	var text: String = km.binding_key_only_text("skill_1")
	return text if not text.is_empty() and text != "未绑定" else "1"


func _is_skill_key(event: InputEventKey) -> bool:
	var km = KeybindManagerScript.get_instance()
	var code := KEY_1
	if km != null:
		var b: Dictionary = km.get_binding("skill_1")
		if b.get("device", "key") == "key" and int(b.get("code", 0)) != 0:
			code = int(b.get("code"))
	return event.keycode == code or event.physical_keycode == code


## Key press. An aimed skill arms the ground cursor and waits for the release; the rest fire now.
func _on_skill_key_pressed() -> bool:
	if _state != State.CHASE_ACTIVE or _skill_loadout == null:
		return false
	if not _skill_loadout.can_cast():
		return false
	if _skill_loadout.is_aimed():
		if _skill_aim != null and not _skill_aim.active:
			_skill_aim.set_camera(_commander_camera if _commander_mode else _camera)
			_skill_aim.begin(_skill_loadout.current_skill(), _player)
		return true
	return try_cast_skill()


## Key release. Only meaningful mid-aim: locks the ground position and casts there.
func _on_skill_key_released() -> bool:
	if _skill_aim == null or not _skill_aim.active:
		return false
	var pos := _skill_aim.finish()
	if _state != State.CHASE_ACTIVE:
		return false
	return try_cast_skill_at(pos)


## Instant cast entry point shared by the key binding and any bot driver.
func try_cast_skill() -> bool:
	if _state != State.CHASE_ACTIVE or _skill_loadout == null:
		return false
	return _skill_loadout.cast_skill()


## Aimed cast entry point shared by the key binding and any bot driver.
func try_cast_skill_at(target_pos: Vector3) -> bool:
	if _state != State.CHASE_ACTIVE or _skill_loadout == null:
		return false
	return _skill_loadout.cast_skill_at(target_pos)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.pressed and _is_skill_key(event):
		if _on_skill_key_released():
			get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			SceneLoader.change_scene(get_tree(), TITLE_SCENE, "返回主界面...")
			return
		elif event.keycode == KEY_TAB:
			_toggle_commander_mode()
			get_viewport().set_input_as_handled()
			return
		elif _is_skill_key(event):
			if _on_skill_key_pressed():
				get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_X:
			get_viewport().set_input_as_handled()
			var now := float(Time.get_ticks_msec()) * 0.001
			if (now - _last_x_press_time) <= DOUBLE_TAP_WINDOW:
				_show_debug_path = not _show_debug_path
				_last_x_press_time = -1000.0
				_update_debug_path_visibility()
			else:
				_last_x_press_time = now
			return

	if _state == State.GAME_OVER and _stage_modal != null and _stage_modal.visible:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_is_stage_dragging = event.pressed
		elif event is InputEventMouseMotion and _is_stage_dragging:
			_stage_target_yaw += event.relative.x * 0.008

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
	if _state == State.GAME_OVER and _game_over_hero_node != null and is_instance_valid(_game_over_hero_node):
		_stage_current_yaw = lerp_angle(_stage_current_yaw, _stage_target_yaw, delta * 12.0)
		_game_over_hero_node.rotation.y = _stage_current_yaw

	if _commander_mode:
		_drive_commander_camera(delta)
		_cast_crosshair()

	if _skill_aim != null and _skill_aim.active:
		_skill_aim.set_camera(_commander_camera if _commander_mode else _camera)
		_skill_aim.update_aim()


func _physics_process(delta: float) -> void:
	match _state:
		State.ESCAPE_COUNTDOWN:
			_escape_timer = maxf(0.0, _escape_timer - delta)
			_update_escape_countdown_hud()

			# Voiceover countdown ticks for 5, 4, 3, 2, 1
			var cur_sec := int(ceil(_escape_timer))
			if cur_sec in [5, 4, 3, 2, 1] and cur_sec != _last_countdown_voice:
				_last_countdown_voice = cur_sec
				AudioManagerScript.play_countdown(cur_sec, true)

			if _npc != null:
				_npc.global_position = _npc_spawn
				_npc.velocity = Vector3.ZERO
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

			var dist := _player.global_position.distance_to(_npc.global_position)
			var vert_dist := absf(_player.global_position.y - _npc.global_position.y)
			if dist <= CATCH_DISTANCE_THRESHOLD and vert_dist <= 1.5:
				_trigger_game_over()
				return

			var now := float(Time.get_ticks_msec()) * 0.001
			_player_history.append({"time": now, "pos": _player.global_position})
			while _player_history.size() > 1 and (now - _player_history[0].time) > 1.2:
				_player_history.pop_front()

			var npc_busy := _npc_intent.is_performing_jump_or_climb() or not _npc.is_on_floor()
			var npc_just_finished_climb_or_air := _npc_was_busy and not npc_busy
			_npc_was_busy = npc_busy

			if not npc_busy:
				if _deferred_repath_pending or npc_just_finished_climb_or_air:
					_deferred_repath_pending = false
					_repath_timer = 0.0
					_execute_npc_repath()

			var player_grounded := _player.is_on_floor()
			if not player_grounded:
				_player_was_jumping_or_climbing = true
			elif _player_was_jumping_or_climbing and player_grounded:
				_player_was_jumping_or_climbing = false
				_request_npc_repath(true)

			var p_cell := _nav.standing_node(_player.global_position)
			var n_cell := _nav.standing_node(_npc.global_position)
			var on_same_platform := _nav.is_same_flat_platform(n_cell, p_cell)
			var interval := FAST_REPATH_INTERVAL if on_same_platform else SLOW_REPATH_INTERVAL

			_repath_timer += delta
			if _repath_timer >= interval:
				_request_npc_repath(false)


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
	var ray_from := from_pos + Vector3(0.0, 0.8, 0.0)
	var ray_to := to_pos + Vector3(0.0, 0.8, 0.0)
	var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
	query.collide_with_areas = false
	query.exclude = [_player.get_rid(), _npc.get_rid()] if _player and _npc else []
	var hit := space_state.intersect_ray(query)
	if not hit.is_empty():
		return false

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


func _request_npc_repath(_from_player_landing: bool) -> void:
	_repath_timer = 0.0
	var npc_busy := _npc_intent.is_performing_jump_or_climb() or not _npc.is_on_floor()
	if npc_busy:
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

	var target_pos := NavGridScript.foot(player_cell)
	_target_beacon.global_position = target_pos
	_target_beacon.visible = _show_debug_path and _state == State.CHASE_ACTIVE

	var result := _nav.find_path(_npc.global_position, target_pos)
	if result.points.is_empty():
		return

	_npc_intent.set_plan_result(result)
	_draw_npc_path(result.points)


func _on_npc_repath_requested(_from: Vector3, _to: Vector3) -> void:
	if _state == State.CHASE_ACTIVE:
		_request_npc_repath(false)


func _start_escape_countdown() -> void:
	_state = State.ESCAPE_COUNTDOWN
	_escape_timer = ESCAPE_COUNTDOWN_TIME
	_last_countdown_voice = 16
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
	if _report_modal != null:
		_report_modal.visible = false
	if _stage_modal != null:
		_stage_modal.visible = false
	_banner_panel.visible = true
	_info_box.visible = true

	_update_escape_countdown_hud()


func _start_active_chase() -> void:
	_state = State.CHASE_ACTIVE
	_repath_timer = 0.0
	_deferred_repath_pending = false
	AudioManagerScript.play_go(true)
	_execute_npc_repath()


func _trigger_game_win() -> void:
	_state = State.GAME_OVER
	_npc_intent.clear_target()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	AudioManagerScript.play_win(true)
	_banner_panel.visible = false
	_target_beacon.visible = false
	_show_stage_one_report(true, "成功坚持存活满 2 分钟，赢得了追缉对决！")


func _trigger_game_over() -> void:
	_state = State.GAME_OVER
	_npc_intent.clear_target()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	AudioManagerScript.play_lose(true)
	_banner_panel.visible = false
	_target_beacon.visible = false
	_show_stage_one_report(false, "追缉者已逼近至 1.5 米范围以内，逃生失败。")


func _build_environment() -> void:
	WorldBuilderScript.build_environment(self, ENV_PRESET)


func _build_ground() -> void:
	WorldBuilderScript.build_ground(self, GROUND_PRESET, GROUND_HALF)


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

	_npc = PlayerControllerScript.new()
	_npc.name = "NPCChaser"
	_npc.position = _npc_spawn
	_npc_intent = NPCIntentSourceScript.new()
	_npc.intent_source = _npc_intent
	_npc_intent.bind_nav_grid(_nav)
	_npc_intent.repath_requested.connect(_on_npc_repath_requested)
	add_child(_npc)
	_spawn_character_visual(_npc, _npc_char_idx, false)


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
			_hint_x_toggle_label.text = "AI 路线与红柱: 显示中 (连按两下 X 隐藏)"
			_hint_x_toggle_label.modulate = Color(1.0, 0.85, 0.3, 0.9)
		else:
			_hint_x_toggle_label.text = "AI 路线与红柱: 已隐藏 (连按两下 X 开启)"
			_hint_x_toggle_label.modulate = Color(0.7, 0.7, 0.7, 0.65)


func _load_map_data(path: String) -> void:
	var data := MapDataScript.load_map_from_file(path)
	if data.is_empty():
		return

	_clear_all_blocks()
	_nav.clear_special_paths()
	_map_name = str(data.get("name", "自定义地图"))

	var sp: Array = data.get("spawn_pos", [0.5, 0.2, 0.5])
	if sp.size() >= 3:
		_player_spawn = Vector3(sp[0], sp[1], sp[2])

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
	_banner_panel.offset_left = -310
	_banner_panel.offset_right = 310
	_banner_panel.offset_top = 16
	_banner_panel.offset_bottom = 104
	_banner_panel.custom_minimum_size = Vector2(620, 72)
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

	var banner_vbox := VBoxContainer.new()
	banner_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	banner_hbox.add_child(banner_vbox)

	_banner_title = Label.new()
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_title.add_theme_font_size_override("font_size", 18)
	_banner_title.text = "逃生准备倒计时: 15.0 秒"
	banner_vbox.add_child(_banner_title)

	_banner_sub = Label.new()
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub.add_theme_font_size_override("font_size", 12)
	_banner_sub.text = "尽快利用地形与跳跃拉开距离！倒计时结束后追缉者将出动！"
	_banner_sub.modulate = Color(1.0, 1.0, 1.0, 0.88)
	banner_vbox.add_child(_banner_sub)

	# Left Bottom Stat HUD (Clean, no background panel)
	_info_box = PanelContainer.new()
	_info_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_info_box.offset_left = 24
	_info_box.offset_bottom = -24
	_info_box.offset_right = 330
	_info_box.offset_top = -190
	_info_box.custom_minimum_size = Vector2(306, 166)
	_info_box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var info_style := StyleBoxEmpty.new()
	_info_box.add_theme_stylebox_override("panel", info_style)
	_hud_canvas.add_child(_info_box)

	var stat_vbox := VBoxContainer.new()
	stat_vbox.add_theme_constant_override("separation", 6)
	_info_box.add_child(stat_vbox)

	var mode_tag := Label.new()
	mode_tag.text = "对决模式: 1v1 极限追缉"
	if _custom_font != null:
		mode_tag.add_theme_font_override("font", _custom_font)
	mode_tag.add_theme_font_size_override("font_size", 16)
	mode_tag.modulate = Color(0.4, 0.85, 1.0)
	stat_vbox.add_child(mode_tag)

	_survival_label = Label.new()
	_survival_label.text = "逃生生存时间: 00:00.0"
	if _custom_font != null:
		_survival_label.add_theme_font_override("font", _custom_font)
	_survival_label.add_theme_font_size_override("font_size", 14)
	stat_vbox.add_child(_survival_label)

	_distance_label = Label.new()
	_distance_label.text = "距离追缉者: -- m"
	if _custom_font != null:
		_distance_label.add_theme_font_override("font", _custom_font)
	_distance_label.add_theme_font_size_override("font_size", 14)
	stat_vbox.add_child(_distance_label)

	_status_detail_label = Label.new()
	_status_detail_label.text = "追缉者状态: 锁定原地待命"
	if _custom_font != null:
		_status_detail_label.add_theme_font_override("font", _custom_font)
	_status_detail_label.add_theme_font_size_override("font_size", 13)
	_status_detail_label.modulate = Color(1.0, 1.0, 1.0, 0.65)
	stat_vbox.add_child(_status_detail_label)

	_skill_label = Label.new()
	_skill_label.text = "[1] 未持有技能"
	if _custom_font != null:
		_skill_label.add_theme_font_override("font", _custom_font)
	_skill_label.add_theme_font_size_override("font_size", 14)
	_skill_label.modulate = Color(1.0, 0.85, 0.4)
	stat_vbox.add_child(_skill_label)

	_hint_x_toggle_label = Label.new()
	_hint_x_toggle_label.text = "AI 路线与红柱: 已隐藏 (连按两下 X 开启)"
	if _custom_font != null:
		_hint_x_toggle_label.add_theme_font_override("font", _custom_font)
	_hint_x_toggle_label.add_theme_font_size_override("font_size", 13)
	_hint_x_toggle_label.modulate = Color(0.7, 0.7, 0.7, 0.65)
	stat_vbox.add_child(_hint_x_toggle_label)

	_hint_tab_label = Label.new()
	_hint_tab_label.text = "【Tab】视角: 第三人称操纵 (按Tab切换全局指挥)"
	if _custom_font != null:
		_hint_tab_label.add_theme_font_override("font", _custom_font)
	_hint_tab_label.add_theme_font_size_override("font_size", 13)
	_hint_tab_label.modulate = Color(0.7, 0.8, 0.9, 0.75)
	stat_vbox.add_child(_hint_tab_label)

	_crosshair = Crosshair.new()
	_crosshair.visible = false
	_hud_canvas.add_child(_crosshair)

	# Game Over Modal (Exquisite 9-Patch Frame with rounded and feathered soft borders)
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


func _build_keycaps_overlay() -> void:
	_keycaps_overlay = PanelContainer.new()
	_keycaps_overlay.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_keycaps_overlay.offset_right = -24
	_keycaps_overlay.offset_bottom = -24
	_keycaps_overlay.offset_left = -270
	_keycaps_overlay.offset_top = -146
	_keycaps_overlay.custom_minimum_size = Vector2(246, 122)
	_keycaps_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := _create_9patch_style("res://assets/UI_assets/panel_exquisite.png", 50.0, 45.0, 50.0, 45.0, 16.0, 14.0, 16.0, 14.0)
	_keycaps_overlay.add_theme_stylebox_override("panel", style)
	_hud_canvas.add_child(_keycaps_overlay)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	_keycaps_overlay.add_child(grid)

	_add_mini_key(grid, "res://assets/buttons_pattern/W.png", "移动/飞行控制")
	_add_mini_key(grid, "res://assets/buttons_pattern/TAB.png", "全局指挥切换")
	_add_mini_key(grid, "res://assets/buttons_pattern/SPACE.png", "跳跃/升空")
	_add_mini_key(grid, "res://assets/buttons_pattern/LMB.png", "Shift+左键指挥")


func _add_mini_key(grid: GridContainer, key_png: String, label_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var tex := TextureRect.new()
	if ResourceLoader.exists(key_png):
		tex.texture = load(key_png)
	tex.custom_minimum_size = Vector2(22, 22)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(tex)

	var lbl := Label.new()
	lbl.text = label_text
	if _custom_font != null:
		lbl.add_theme_font_override("font", _custom_font)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.modulate = Color(0.85, 0.88, 0.92, 0.8)
	row.add_child(lbl)

	grid.add_child(row)


func _update_escape_countdown_hud() -> void:
	if _banner_style != null:
		_banner_style.border_color = Color(1.0, 0.85, 0.25, 0.75)
	if ResourceLoader.exists("res://assets/UI_assets/extra-time.svg"):
		_banner_icon.texture = load("res://assets/UI_assets/extra-time.svg")
		_banner_icon.modulate = Color(1.0, 0.85, 0.2)

	_banner_title.text = "逃生准备倒计时: %.1f 秒" % _escape_timer
	if _custom_font != null:
		_banner_title.add_theme_font_override("font", _custom_font)
		_banner_sub.add_theme_font_override("font", _custom_font)
	_banner_title.modulate = Color(1.0, 0.9, 0.3)
	_banner_sub.text = "尽快利用地形与跳跃拉开距离！存活满 2 分钟即可逃生胜利！"
	_survival_label.text = "逃生准备: %.1f s (追缉限时 2 分钟)" % _escape_timer
	_status_detail_label.text = "追缉者状态: 锁定原地待命中"


func _update_active_chase_hud() -> void:
	if _banner_style != null:
		_banner_style.border_color = Color(1.0, 0.35, 0.35, 0.75)
	if ResourceLoader.exists("res://assets/UI_assets/cctv-camera.svg"):
		_banner_icon.texture = load("res://assets/UI_assets/cctv-camera.svg")
		_banner_icon.modulate = Color(1.0, 0.35, 0.35)

	_banner_title.text = "追缉进行中！全力逃生！"
	if _custom_font != null:
		_banner_title.add_theme_font_override("font", _custom_font)
		_banner_sub.add_theme_font_override("font", _custom_font)
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


# Game Over Two-Stage UI
var _report_modal: PanelContainer
var _report_icon: TextureRect
var _report_title: Label
var _report_desc: Label
var _report_time_lbl: Label
var _title_pulse_tween: Tween

var _stage_modal: Control
var _game_over_viewport: SubViewport
var _game_over_stage_root: Node3D
var _game_over_hero_node: Character
var _stage_target_yaw: float = 0.0
var _stage_current_yaw: float = 0.0
var _is_stage_dragging := false
var _match_is_win := false


func _build_game_over_dialog() -> void:
	# --- Stage 1: Exquisite 9-Patch Report Modal ---
	_report_modal = PanelContainer.new()
	_report_modal.set_anchors_preset(Control.PRESET_CENTER)
	_report_modal.offset_left = -260
	_report_modal.offset_right = 260
	_report_modal.offset_top = -190
	_report_modal.offset_bottom = 190
	_report_modal.custom_minimum_size = Vector2(520, 380)
	_report_modal.pivot_offset = Vector2(260, 190)
	_report_modal.visible = false

	var diag_style := _create_9patch_style("res://assets/UI_assets/panel_exquisite.png", 50.0, 45.0, 50.0, 45.0, 24.0, 24.0, 24.0, 22.0)
	_report_modal.add_theme_stylebox_override("panel", diag_style)
	_hud_canvas.add_child(_report_modal)

	var r_vbox := VBoxContainer.new()
	r_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	r_vbox.add_theme_constant_override("separation", 14)
	_report_modal.add_child(r_vbox)

	_report_icon = TextureRect.new()
	_report_icon.custom_minimum_size = Vector2(64, 64)
	_report_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_report_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r_vbox.add_child(_report_icon)

	_report_title = Label.new()
	_report_title.text = "对 决 结 束"
	if _custom_font != null:
		_report_title.add_theme_font_override("font", _custom_font)
	_report_title.add_theme_font_size_override("font_size", 30)
	_report_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	r_vbox.add_child(_report_title)

	_report_desc = Label.new()
	_report_desc.text = "结算说明"
	_report_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_report_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_report_desc.add_theme_font_size_override("font_size", 14)
	r_vbox.add_child(_report_desc)

	_report_time_lbl = Label.new()
	_report_time_lbl.text = "00:00.0"
	_report_time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _custom_font != null:
		_report_time_lbl.add_theme_font_override("font", _custom_font)
	_report_time_lbl.add_theme_font_size_override("font_size", 24)
	_report_time_lbl.modulate = Color(1.0, 0.85, 0.25)
	r_vbox.add_child(_report_time_lbl)

	var continue_btn := Button.new()
	continue_btn.text = "▶ 点击继续 (CONTINUE)"
	if _custom_font != null:
		continue_btn.add_theme_font_override("font", _custom_font)
	continue_btn.add_theme_font_size_override("font_size", 18)
	continue_btn.custom_minimum_size = Vector2(240, 46)
	continue_btn.pressed.connect(_on_report_continue_pressed)

	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.85, 0.45, 0.15, 0.95)
	btn_style.set_corner_radius_all(8)
	btn_style.set_content_margin_all(8)
	continue_btn.add_theme_stylebox_override("normal", btn_style)
	r_vbox.add_child(continue_btn)

	# --- Stage 2: 3D Character Stage & Actions ---
	_stage_modal = Control.new()
	_stage_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage_modal.mouse_filter = Control.MOUSE_FILTER_PASS
	_stage_modal.visible = false
	_hud_canvas.add_child(_stage_modal)

	var vp_cont := SubViewportContainer.new()
	vp_cont.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp_cont.stretch = true
	vp_cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_modal.add_child(vp_cont)

	_game_over_viewport = SubViewport.new()
	_game_over_viewport.size = Vector2i(get_viewport().get_visible_rect().size)
	_game_over_viewport.world_3d = World3D.new()
	_game_over_viewport.msaa_3d = Viewport.MSAA_4X
	_game_over_viewport.use_hdr_2d = false
	_game_over_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp_cont.add_child(_game_over_viewport)

	_game_over_stage_root = Node3D.new()
	_game_over_viewport.add_child(_game_over_stage_root)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.07, 0.92)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.25, 0.35)
	env.ambient_light_energy = 0.5
	env.glow_enabled = true
	env.glow_intensity = 0.8

	var env_node := WorldEnvironment.new()
	env_node.environment = env
	_game_over_stage_root.add_child(env_node)

	var dais := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.0
	cyl.bottom_radius = 2.2
	cyl.height = 0.3
	var dais_mat := StandardMaterial3D.new()
	dais_mat.albedo_color = Color(0.10, 0.12, 0.16)
	dais_mat.roughness = 0.6
	dais_mat.metallic = 0.4
	dais.mesh = cyl
	dais.material_override = dais_mat
	dais.position = Vector3(0.0, -0.15, 0.0)
	_game_over_stage_root.add_child(dais)

	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.05
	cam.current = true
	_game_over_stage_root.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 1.15, 3.2), Vector3(0.0, 0.95, 0.0))

	var light := DirectionalLight3D.new()
	light.light_color = Color(1.0, 0.9, 0.75)
	light.light_energy = 1.2
	light.transform.basis = Basis.from_euler(Vector3(deg_to_rad(-20.0), deg_to_rad(135.0), 0.0))
	_game_over_stage_root.add_child(light)

	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.3, 0.8, 1.0)
	rim.light_energy = 0.7
	rim.transform.basis = Basis.from_euler(Vector3(deg_to_rad(-15.0), deg_to_rad(-45.0), 0.0))
	_game_over_stage_root.add_child(rim)

	# Bottom Action Bar on Stage 2
	var stage_bot_panel := PanelContainer.new()
	stage_bot_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	stage_bot_panel.offset_left = 60
	stage_bot_panel.offset_right = -60
	stage_bot_panel.offset_top = -96
	stage_bot_panel.offset_bottom = -24

	var sb_style := _create_9patch_style("res://assets/UI_assets/panel_exquisite.png", 50.0, 45.0, 50.0, 45.0, 20.0, 14.0, 20.0, 14.0)
	stage_bot_panel.add_theme_stylebox_override("panel", sb_style)
	_stage_modal.add_child(stage_bot_panel)

	var sb_hbox := HBoxContainer.new()
	sb_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	sb_hbox.add_theme_constant_override("separation", 24)
	stage_bot_panel.add_child(sb_hbox)

	var drag_hint := Label.new()
	drag_hint.text = "💡 鼠标在中央按住左键拖拽可 360° 旋转观察角色动作"
	drag_hint.add_theme_font_size_override("font_size", 12)
	drag_hint.modulate = Color(0.45, 0.75, 0.95, 0.8)
	sb_hbox.add_child(drag_hint)

	var retry_btn := Button.new()
	retry_btn.text = "重新逃生挑战"
	if _custom_font != null:
		retry_btn.add_theme_font_override("font", _custom_font)
	retry_btn.add_theme_font_size_override("font_size", 16)
	retry_btn.custom_minimum_size = Vector2(150, 42)
	retry_btn.pressed.connect(_on_stage_retry_pressed)
	sb_hbox.add_child(retry_btn)

	var menu_btn := Button.new()
	menu_btn.text = "返回主菜单"
	if _custom_font != null:
		menu_btn.add_theme_font_override("font", _custom_font)
	menu_btn.add_theme_font_size_override("font_size", 16)
	menu_btn.custom_minimum_size = Vector2(130, 42)
	menu_btn.pressed.connect(func() -> void:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		SceneLoader.change_scene(get_tree(), TITLE_SCENE, "返回主界面...")
	)
	sb_hbox.add_child(menu_btn)


func _show_stage_one_report(i_win: bool, reason_text: String) -> void:
	_match_is_win = i_win
	_stage_modal.visible = false
	_report_modal.visible = true
	_report_modal.scale = Vector2(0.35, 0.35)
	_report_modal.modulate = Color(1.0, 1.0, 1.0, 0.0)

	var icon_path := "res://assets/UI_assets/freedom-dove.svg" if i_win else "res://assets/UI_assets/grim-reaper.svg"
	if ResourceLoader.exists(icon_path):
		_report_icon.texture = load(icon_path)
		_report_icon.modulate = Color(0.3, 1.0, 0.5) if i_win else Color(1.0, 0.35, 0.35)

	_report_title.text = "🏆 逃 生 成 功 (VICTORY)" if i_win else "💀 被 追 缉 者 捕 获 (DEFEATED)"
	_report_title.modulate = Color(0.3, 1.0, 0.5) if i_win else Color(1.0, 0.35, 0.35)
	_report_desc.text = reason_text

	var m := int(CHASE_TIME_LIMIT if i_win else _survival_time) / 60
	var s := fmod(CHASE_TIME_LIMIT if i_win else _survival_time, 60.0)
	_report_time_lbl.text = "逃生耗时: %02d:%05.2f" % [m, s]

	# Pop-in Elastic Animation
	var tw_in := create_tween()
	tw_in.set_parallel(true)
	tw_in.tween_property(_report_modal, "scale", Vector2(1.0, 1.0), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw_in.tween_property(_report_modal, "modulate:a", 1.0, 0.35)

	# Text Pulse Tween
	if _title_pulse_tween != null and _title_pulse_tween.is_valid():
		_title_pulse_tween.kill()
	_title_pulse_tween = create_tween().set_loops()
	var base_col := Color(0.3, 1.0, 0.5) if i_win else Color(1.0, 0.35, 0.35)
	var glow_col := Color(0.6, 1.3, 0.8) if i_win else Color(1.5, 0.5, 0.5)
	_title_pulse_tween.tween_property(_report_title, "modulate", glow_col, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_title_pulse_tween.tween_property(_report_title, "modulate", base_col, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _on_report_continue_pressed() -> void:
	if _title_pulse_tween != null and _title_pulse_tween.is_valid():
		_title_pulse_tween.kill()

	AudioManagerScript.play_voice_file("res://assets/voice/sfx/swing_mid_01.wav", -2.0)

	var tw_out := create_tween()
	tw_out.set_parallel(true)
	tw_out.tween_property(_report_modal, "scale", Vector2(0.5, 0.5), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw_out.tween_property(_report_modal, "modulate:a", 0.0, 0.25)
	tw_out.chain().tween_callback(func():
		_report_modal.visible = false
		_stage_modal.visible = true
		_show_game_over_character(_match_is_win)
	)


func _on_stage_retry_pressed() -> void:
	_stage_modal.visible = false
	_start_escape_countdown()


func _show_game_over_character(i_win: bool) -> void:
	if _game_over_stage_root == null:
		return
	if _game_over_hero_node != null and is_instance_valid(_game_over_hero_node):
		_game_over_hero_node.queue_free()
		_game_over_hero_node = null

	var hero_path := "res://assets/characters/hero_1/hero_1.tscn"
	var p_scene := load(hero_path) as PackedScene
	if p_scene != null:
		var inst := p_scene.instantiate() as Character
		if inst != null:
			_game_over_hero_node = inst
			_game_over_hero_node.position = Vector3(0.0, 0.0, 0.0)
			_game_over_hero_node.rotation.y = _stage_current_yaw
			_game_over_stage_root.add_child(_game_over_hero_node)
			if _game_over_hero_node.is_node_ready():
				_play_match_end_anim(_game_over_hero_node, i_win)
			else:
				_game_over_hero_node.ready.connect(func(): _play_match_end_anim(_game_over_hero_node, i_win))


func _play_match_end_anim(char_node: Character, i_win: bool) -> void:
	if char_node == null:
		return
	if char_node.player == null:
		char_node.player = AnimPipelineScript.first_of_class(char_node, "AnimationPlayer") as AnimationPlayer
		char_node.skeleton = AnimPipelineScript.first_of_class(char_node, "Skeleton3D") as Skeleton3D
		char_node.attach_libraries()

	var anim_to_play := "yes" if i_win else "idle_no"
	if not char_node.has_clip(anim_to_play):
		anim_to_play = "dance" if i_win else "idle"

	if char_node.has_clip(anim_to_play):
		char_node.play(anim_to_play)
		var resolved := char_node.resolve(anim_to_play)
		if char_node.player != null and char_node.player.has_animation(resolved):
			char_node.player.get_animation(resolved).loop_mode = Animation.LOOP_LINEAR
