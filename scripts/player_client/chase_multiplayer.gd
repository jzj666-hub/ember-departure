extends Node3D
## 1v1 LAN Multiplayer Pursuit Match Controller.
## Supports dual-side Tab tactical commander A* pathfinding, 30Hz snapshot synchronization, and jitter buffer interpolation.

const NavGridScript = preload("res://scripts/nav_grid.gd")
const AnimPipelineScript = preload("res://tools/anim_pipeline.gd")
const BlockRegistryScript = preload("res://scripts/block_registry.gd")
const MapDataScript = preload("res://scripts/map_data.gd")
const CharacterPipelineScript = preload("res://tools/character_pipeline.gd")
const PlayerControllerScript = preload("res://scripts/player_controller.gd")
const PlayerIntentSourceScript = preload("res://scripts/player_intent_source.gd")
const NPCIntentSourceScript = preload("res://scripts/npc_intent_source.gd")
const FollowCameraScript = preload("res://scripts/follow_camera.gd")
const SnapshotInterpolatorScript = preload("res://scripts/network/snapshot_interpolator.gd")
const SkillLoadoutScript = preload("res://scripts/skills/skill_loadout.gd")
const SkillDrawPanelScript = preload("res://scripts/player_client/skill_draw_panel.gd")
const SkillAimScript = preload("res://scripts/skills/skill_aim.gd")
const SkillRegistryScript = preload("res://scripts/skills/skill_registry.gd")
const KeybindManagerScript = preload("res://scripts/keybind_manager.gd")
const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const WorldBuilderScript = preload("res://scripts/world/world_builder.gd")
const ENV_PRESET = preload("res://config/env/chase_dusk.tres")
const GROUND_PRESET = preload("res://config/ground/chase_grid.tres")
const HudKitScript = preload("res://scripts/ui/hud_kit.gd")
const CommanderCamScript = preload("res://scripts/world/commander_cam.gd")

const LOBBY_SCENE := "res://scenes/player_client/multiplayer_lobby.tscn"
const TITLE_SCENE := "res://scenes/player_client/title_screen.tscn"
const FONT_PATH := "res://assets/Fonts/Long_Cang/LongCang-Regular.ttf"

const GROUND_HALF := 25.0
const MAX_BLOCK_Y := 12
## Difficulty knobs: edit config/chase/*.tres, not here. Mirrors keep every usage below unchanged.
const CHASE_PROFILE: ChaseProfile = preload("res://config/chase/standard.tres")
var ESCAPE_COUNTDOWN_TIME: float = CHASE_PROFILE.escape_countdown
var CHASE_TIME_LIMIT: float = CHASE_PROFILE.chase_time_limit
var CATCH_DISTANCE_THRESHOLD: float = CHASE_PROFILE.catch_distance
const SNAPSHOT_INTERVAL := 0.033 # 30Hz

enum State {
	PREPARE_COUNTDOWN,
	CHASE_ACTIVE,
	MATCH_OVER,
}

var _state: State = State.PREPARE_COUNTDOWN
var _escape_timer: float = ESCAPE_COUNTDOWN_TIME
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
var _banner_style: StyleBoxFlat
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


var _local_scene_ready := false
var _remote_scene_ready := false
var _has_started_countdown := false

var _skill_label: Label
var _skill_loadout: SkillLoadout
var _skill_draw_panel: SkillDrawPanel
var _skill_aim: SkillAim
var _skills_assigned := false


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

	var map_data: Dictionary = NetworkManager.selected_map_data
	if not map_data.is_empty():
		_apply_map_data(map_data)
	elif not NetworkManager.selected_map_path.is_empty() and FileAccess.file_exists(NetworkManager.selected_map_path):
		_apply_map_data(MapDataScript.load_map_from_file(NetworkManager.selected_map_path))
	else:
		_clear_all_blocks()
		_nav.clear_special_paths()
		_nav.rebuild()
		if _local_body != null:
			_nav.set_capability(_local_body)

	_reset_match_positions()
	_setup_skill_draw()

	_local_scene_ready = true
	if multiplayer.has_multiplayer_peer():
		rpc("rpc_peer_scene_ready")
		if NetworkManager.is_host and _remote_scene_ready and not _has_started_countdown:
			_host_trigger_countdown()
	else:
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
		elif _is_skill_key(event):
			if _on_skill_key_pressed():
				get_viewport().set_input_as_handled()
			return

	if event is InputEventKey and not event.pressed and _is_skill_key(event):
		if _on_skill_key_released():
			get_viewport().set_input_as_handled()
		return

	if _state == State.MATCH_OVER and _stage_modal != null and _stage_modal.visible:
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
			_command_local_npc(_aim_point)
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _state == State.MATCH_OVER and _game_over_hero_node != null and is_instance_valid(_game_over_hero_node):
		_stage_current_yaw = lerp_angle(_stage_current_yaw, _stage_target_yaw, delta * 12.0)
		_game_over_hero_node.rotation.y = _stage_current_yaw

	if _commander_mode:
		_drive_commander_camera(delta)
		_cast_crosshair()

	if _remote_interpolator != null:
		_remote_interpolator.update_interpolation(delta)

	if _skill_aim != null and _skill_aim.active:
		_skill_aim.set_camera(_commander_camera if _commander_mode else _camera)
		_skill_aim.update_aim()


func _physics_process(delta: float) -> void:
	match _state:
		State.PREPARE_COUNTDOWN:
			_escape_timer = maxf(0.0, _escape_timer - delta)
			_update_countdown_hud()

			var cur_sec := int(ceil(_escape_timer))
			if cur_sec in [5, 4, 3, 2, 1] and cur_sec != _last_countdown_voice:
				_last_countdown_voice = cur_sec
				AudioManagerScript.play_countdown(cur_sec, true)

			# Keep Chaser firmly locked at spawn during countdown
			if NetworkManager.local_role == NetworkManager.Role.CHASER:
				if _local_body != null:
					_local_body.global_position = _chaser_spawn
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
		"action": "",
		"state": int(_local_body.state)
	}
	if NetworkManager.is_host:
		snap["host_esc_timer"] = _escape_timer
		snap["host_surv_time"] = _survival_time
		snap["host_state"] = int(_state)
	rpc("rpc_receive_snapshot", snap)


@rpc("any_peer", "call_remote", "unreliable")
func rpc_receive_snapshot(snap: Dictionary) -> void:
	if _remote_interpolator != null:
		_remote_interpolator.push_snapshot(snap)
	if not NetworkManager.is_host and snap.has("host_esc_timer"):
		var h_state: int = int(snap.get("host_state", int(_state)))
		if _state != State.MATCH_OVER:
			_state = h_state as State
		_escape_timer = snap.get("host_esc_timer", _escape_timer)
		_survival_time = snap.get("host_surv_time", _survival_time)


@rpc("any_peer", "call_remote", "reliable")
func rpc_peer_scene_ready() -> void:
	_remote_scene_ready = true
	if NetworkManager.is_host and _local_scene_ready and not _has_started_countdown:
		_host_trigger_countdown()


func _host_trigger_countdown() -> void:
	_has_started_countdown = true
	_host_assign_skills()
	rpc("rpc_start_prepare_countdown", ESCAPE_COUNTDOWN_TIME)


@rpc("authority", "call_local", "reliable")
func rpc_start_prepare_countdown(duration: float) -> void:
	_escape_timer = duration
	_start_prepare_countdown()


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

	_banner_panel.visible = false
	_local_beacon.visible = false
	_show_stage_one_report(i_win, reason_text)


func _start_prepare_countdown() -> void:
	_state = State.PREPARE_COUNTDOWN
	_escape_timer = ESCAPE_COUNTDOWN_TIME
	_survival_time = 0.0
	_last_countdown_voice = -1
	if _report_modal != null:
		_report_modal.visible = false
	if _stage_modal != null:
		_stage_modal.visible = false
	_banner_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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


# --- Skill draw & casting ----------------------------------------------------

## Builds the slot and aim cursor. The draw itself is host-assigned (rpc_assign_skills) so the two
## players never open with the same skill; a peerless scene rolls locally for debugging.
func _setup_skill_draw() -> void:
	SkillRegistryScript.init_registry()
	SkillRegistryScript.reset_all_state()
	SkillRegistryScript.warmup_all_shaders(self)

	_skill_loadout = SkillLoadoutScript.new()
	_skill_loadout.name = "SkillLoadout"
	add_child(_skill_loadout)
	_skill_loadout.setup(_local_body, self, NetworkManager.local_role == NetworkManager.Role.RUNNER)
	_skill_loadout.cooldown_changed.connect(_on_skill_cooldown_changed)

	_skill_aim = SkillAimScript.new()
	_skill_aim.name = "SkillAim"
	add_child(_skill_aim)
	_skill_aim.setup(_camera)

	_skill_draw_panel = SkillDrawPanelScript.new()
	_skill_draw_panel.name = "SkillDrawPanel"
	add_child(_skill_draw_panel)

	if not multiplayer.has_multiplayer_peer():
		_play_skill_draw(_skill_loadout.roll())


## Host draws both sides at once, guaranteeing they differ, then broadcasts the assignment.
func _host_assign_skills() -> void:
	if not NetworkManager.is_host or _skills_assigned:
		return
	_skills_assigned = true
	var pair := SkillLoadoutScript.draw_pair()
	rpc("rpc_assign_skills", str(pair["runner"]), str(pair["chaser"]))


@rpc("authority", "call_local", "reliable")
func rpc_assign_skills(runner_skill: String, chaser_skill: String) -> void:
	if _skill_loadout == null:
		return
	var mine := runner_skill if NetworkManager.local_role == NetworkManager.Role.RUNNER else chaser_skill
	_play_skill_draw(_skill_loadout.roll(mine))


func _play_skill_draw(rolled: String) -> void:
	if rolled.is_empty() or _skill_draw_panel == null:
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
			_skill_aim.begin(_skill_loadout.current_skill(), _local_body)
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
	if not _skill_loadout.cast_skill():
		return false
	if multiplayer.has_multiplayer_peer():
		rpc("rpc_peer_skill_cast", _skill_loadout.skill_id, _local_body.global_position)
	return true


## Aimed cast entry point shared by the key binding and any bot driver.
func try_cast_skill_at(target_pos: Vector3) -> bool:
	if _state != State.CHASE_ACTIVE or _skill_loadout == null:
		return false
	if not _skill_loadout.cast_skill_at(target_pos):
		return false
	if multiplayer.has_multiplayer_peer():
		rpc("rpc_peer_skill_cast", _skill_loadout.skill_id, target_pos)
	return true


## Replays a peer's cast against its avatar here, so VFX exist and area effects hit our local body.
@rpc("any_peer", "call_remote", "reliable")
func rpc_peer_skill_cast(skill_id: String, target_pos: Vector3) -> void:
	SkillLoadoutScript.cast_for_body_at(skill_id, _remote_body, self, target_pos)


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
	_camera = CommanderCamScript.build_follow(self)
	_commander_camera = CommanderCamScript.build_commander(self)


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
	add_child(_remote_body)
	_spawn_visual(_remote_body, chars, remote_char_idx, false)
	_remote_interpolator = SnapshotInterpolatorScript.new()
	_remote_interpolator.setup(_remote_body)


func _spawn_visual(body: CharacterBody3D, chars: Array, char_idx: int, is_local: bool) -> void:
	var chosen_path := NetworkManager.local_hero_scene if is_local else NetworkManager.remote_hero_scene
	var scene: PackedScene = null
	if not chosen_path.is_empty() and ResourceLoader.exists(chosen_path):
		scene = load(chosen_path) as PackedScene

	if scene == null and not chars.is_empty():
		var entry: Dictionary = chars[clamp(char_idx, 0, chars.size() - 1)]
		scene = load(entry.scene) as PackedScene

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
	_cam_velocity = CommanderCamScript.drive(_commander_camera, _cam_velocity, _fly_speed, delta)


func _cast_crosshair() -> void:
	var r := CommanderCamScript.cast_crosshair(_commander_camera, get_world_3d(), _highlight)
	_has_aim = r.has_aim
	_aim_point = r.point
	_aim_cell = r.cell


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
	WorldBuilderScript.build_environment(self, ENV_PRESET)


func _build_ground() -> void:
	WorldBuilderScript.build_ground(self, GROUND_PRESET, GROUND_HALF)


func _apply_map_data(data: Dictionary) -> void:
	if data.is_empty():
		return
	_clear_all_blocks()
	_nav.clear_special_paths()

	var sp: Array = data.get("spawn_pos", [0.5, 0.2, 0.5])
	if sp.size() >= 3:
		_runner_spawn = Vector3(sp[0], sp[1], sp[2])

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
	_banner_panel.offset_bottom = 96
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
	_info_box.custom_minimum_size = Vector2(300, 130)
	_info_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var info_style := StyleBoxFlat.new()
	info_style.bg_color = Color(0.06, 0.08, 0.11, 0.75)
	info_style.set_corner_radius_all(10)
	info_style.set_border_width_all(1)
	info_style.border_color = Color(0.25, 0.85, 1.0, 0.3)
	info_style.set_content_margin_all(12)
	_info_box.add_theme_stylebox_override("panel", info_style)
	_hud_canvas.add_child(_info_box)

	var stat_vbox := VBoxContainer.new()
	stat_vbox.add_theme_constant_override("separation", 6)
	_info_box.add_child(stat_vbox)

	var role_header := HBoxContainer.new()
	role_header.add_theme_constant_override("separation", 8)
	stat_vbox.add_child(role_header)

	var r_icon := TextureRect.new()
	r_icon.custom_minimum_size = Vector2(20, 20)
	r_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var is_runner := (NetworkManager.local_role == NetworkManager.Role.RUNNER)
	r_icon.texture = load("res://assets/UI_assets/running-shoe.svg" if is_runner else "res://assets/UI_assets/wyvern.svg")
	r_icon.modulate = Color(0.3, 1.0, 0.5) if is_runner else Color(1.0, 0.35, 0.25)
	role_header.add_child(r_icon)

	var mode_tag := Label.new()
	var my_name := ProfileManager.player_name if ProfileManager else "选手"
	mode_tag.text = "%s (%s)" % [my_name, "逃生者" if is_runner else "追缉者"]
	if _custom_font != null:
		mode_tag.add_theme_font_override("font", _custom_font)
	mode_tag.add_theme_font_size_override("font_size", 16)
	mode_tag.modulate = Color(0.3, 0.9, 1.0)
	role_header.add_child(mode_tag)

	_survival_label = Label.new()
	_survival_label.text = "对决剩余时间: 02:00.0"
	if _custom_font != null:
		_survival_label.add_theme_font_override("font", _custom_font)
	_survival_label.add_theme_font_size_override("font_size", 14)
	stat_vbox.add_child(_survival_label)

	_distance_label = Label.new()
	_distance_label.text = "双方测距: -- 米"
	if _custom_font != null:
		_distance_label.add_theme_font_override("font", _custom_font)
	_distance_label.add_theme_font_size_override("font_size", 14)
	stat_vbox.add_child(_distance_label)

	_status_detail_label = Label.new()
	_status_detail_label.text = "网络延迟补偿: Jitter Buffer (60ms)"
	_status_detail_label.add_theme_font_size_override("font_size", 11)
	_status_detail_label.modulate = Color(1.0, 1.0, 1.0, 0.5)
	stat_vbox.add_child(_status_detail_label)

	_skill_label = Label.new()
	_skill_label.text = "[1] 未持有技能"
	if _custom_font != null:
		_skill_label.add_theme_font_override("font", _custom_font)
	_skill_label.add_theme_font_size_override("font_size", 14)
	_skill_label.modulate = Color(1.0, 0.85, 0.4)
	stat_vbox.add_child(_skill_label)

	_hint_tab_label = Label.new()
	_hint_tab_label.text = "[Tab] 视角: 亲自操控 (按Tab切换全局指挥)"
	if _custom_font != null:
		_hint_tab_label.add_theme_font_override("font", _custom_font)
	_hint_tab_label.add_theme_font_size_override("font_size", 12)
	_hint_tab_label.modulate = Color(0.7, 0.8, 0.9, 0.75)
	stat_vbox.add_child(_hint_tab_label)

	_crosshair = Crosshair.new()
	_crosshair.visible = false
	_hud_canvas.add_child(_crosshair)

	_build_game_over_dialog()


func _update_countdown_hud() -> void:
	if _banner_style != null:
		_banner_style.border_color = Color(1.0, 0.85, 0.25, 0.75)
	_banner_title.text = "对决准备倒计时: %.1f 秒" % _escape_timer
	_banner_sub.text = "逃生者尽快拉开距离！倒计时结束后追缉者出动！"


func _update_active_hud() -> void:
	if _banner_style != null:
		_banner_style.border_color = Color(1.0, 0.35, 0.35, 0.75)
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
	_report_time_lbl.text = "对决时间: 00:00.0"
	_report_time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _custom_font != null:
		_report_time_lbl.add_theme_font_override("font", _custom_font)
	_report_time_lbl.add_theme_font_size_override("font_size", 22)
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

	var lobby_btn := Button.new()
	lobby_btn.text = "返回联机大厅"
	if _custom_font != null:
		lobby_btn.add_theme_font_override("font", _custom_font)
	lobby_btn.add_theme_font_size_override("font_size", 16)
	lobby_btn.custom_minimum_size = Vector2(150, 42)
	lobby_btn.pressed.connect(_on_exit_to_lobby)
	sb_hbox.add_child(lobby_btn)

	var title_btn := Button.new()
	title_btn.text = "返回主菜单"
	if _custom_font != null:
		title_btn.add_theme_font_override("font", _custom_font)
	title_btn.add_theme_font_size_override("font_size", 16)
	title_btn.custom_minimum_size = Vector2(130, 42)
	title_btn.pressed.connect(func(): NetworkManager.close_network(); SceneLoader.change_scene(get_tree(), TITLE_SCENE, "返回主界面..."))
	sb_hbox.add_child(title_btn)


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

	_report_title.text = "🏆 对 决 获 胜 (VICTORY)" if i_win else "💀 对 决 战 败 (DEFEATED)"
	_report_title.modulate = Color(0.3, 1.0, 0.5) if i_win else Color(1.0, 0.35, 0.35)
	_report_desc.text = reason_text

	var m := int(_survival_time) / 60
	var s := fmod(_survival_time, 60.0)
	_report_time_lbl.text = "对决持续时间: %02d:%05.2f" % [m, s]

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

	# Pop-out report and show Stage 2
	var tw_out := create_tween()
	tw_out.set_parallel(true)
	tw_out.tween_property(_report_modal, "scale", Vector2(0.5, 0.5), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw_out.tween_property(_report_modal, "modulate:a", 0.0, 0.25)
	tw_out.chain().tween_callback(func():
		_report_modal.visible = false
		_stage_modal.visible = true
		_show_game_over_character(_match_is_win)
	)


func _show_game_over_character(i_win: bool) -> void:
	if _game_over_stage_root == null:
		return
	if _game_over_hero_node != null and is_instance_valid(_game_over_hero_node):
		_game_over_hero_node.queue_free()
		_game_over_hero_node = null

	var hero_path := NetworkManager.local_hero_scene
	if hero_path.is_empty() or not ResourceLoader.exists(hero_path):
		hero_path = "res://assets/characters/hero_1/hero_1.tscn"

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


func _on_exit_to_lobby() -> void:
	SceneLoader.change_scene(get_tree(), LOBBY_SCENE, "返回联机大厅...")


func _create_9patch_style(texture_path: String, ml: float, mt: float, mr: float, mb: float, cl: float = 16.0, ct: float = 14.0, cr: float = 16.0, cb: float = 14.0) -> StyleBoxTexture:
	return HudKitScript.nine_patch(texture_path, ml, mt, mr, mb, cl, ct, cr, cb)
