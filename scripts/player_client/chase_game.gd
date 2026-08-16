extends Node3D
## User client dedicated 1v1 Pursuit game scene.
## Clean game-feel UI with zero web emojis, full voiceover, keycap guide, and dynamic AI rules.

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const NavGridScript = preload("res://scripts/nav_grid.gd")
const BlockRegistryScript = preload("res://scripts/block_registry.gd")
const MapDataScript = preload("res://scripts/map_data.gd")
const CharacterPipelineScript = preload("res://tools/character_pipeline.gd")
const PlayerControllerScript = preload("res://scripts/player_controller.gd")
const PlayerIntentSourceScript = preload("res://scripts/player_intent_source.gd")
const NPCIntentSourceScript = preload("res://scripts/npc_intent_source.gd")
const FollowCameraScript = preload("res://scripts/follow_camera.gd")

const TITLE_SCENE := "res://scenes/player_client/title_screen.tscn"
const FONT_PATH := "res://assets/Fonts/Long_Cang/LongCang-Regular.ttf"
const GROUND_HALF := 25.0
const MAX_BLOCK_Y := 12
const ESCAPE_COUNTDOWN_TIME := 15.0
const FAST_REPATH_INTERVAL := 0.06
const SLOW_REPATH_INTERVAL := 0.25
const LOS_DELAY_SECONDS := 0.20
const CATCH_DISTANCE_THRESHOLD := 1.05
const DOUBLE_TAP_WINDOW := 0.45

enum State {
	PREPARE,
	ESCAPE_COUNTDOWN,
	CHASE_ACTIVE,
	GAME_OVER,
}

var preloaded_map_path: String = ""
var _custom_font: Font = null

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
var _npc_intent: NPCIntentSource
var _camera: FollowCamera

var _player_spawn := Vector3(0.5, 0.2, 0.5)
var _npc_spawn := Vector3(0.5, 0.2, -10.5)

var _characters: Array = []
var _player_char_idx := 0
var _npc_char_idx := 1

var _repath_timer := 0.0
var _player_was_jumping_or_climbing := false
var _deferred_repath_pending := false
var _player_history: Array[Dictionary] = []

var _show_debug_path := false
var _last_x_press_time := -1000.0

var _path_mesh_instance: MeshInstance3D
var _path_immediate_mesh: ImmediateMesh
var _target_beacon: MeshInstance3D

# HUD Elements
var _hud_canvas: CanvasLayer
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
var _keycaps_overlay: PanelContainer

var _game_over_dialog: PanelContainer
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

	_start_escape_countdown()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_tree().change_scene_to_file(TITLE_SCENE)
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

			if _npc_intent != null:
				_npc_intent.clear_target()

			if _escape_timer <= 0.0:
				_start_active_chase()

		State.CHASE_ACTIVE:
			_survival_time += delta
			_update_active_chase_hud()

			if _player == null or _npc == null:
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

			if not npc_busy:
				var delayed_target := _get_delayed_player_pos(LOS_DELAY_SECONDS)
				var has_los := _has_clear_line_of_sight(_npc.global_position, delayed_target)

				if has_los:
					_npc_intent.direct_chase(delayed_target)
					_target_beacon.global_position = delayed_target
					_target_beacon.visible = _show_debug_path and _state == State.CHASE_ACTIVE
					_draw_npc_path(PackedVector3Array([_npc.global_position, delayed_target]))
					_repath_timer = 0.0
					_deferred_repath_pending = false
					return

				if _deferred_repath_pending:
					_deferred_repath_pending = false
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
	_game_over_dialog.visible = false
	_banner_panel.visible = true
	_info_box.visible = true
	_keycaps_overlay.visible = true

	_update_escape_countdown_hud()


func _start_active_chase() -> void:
	_state = State.CHASE_ACTIVE
	_repath_timer = 0.0
	_deferred_repath_pending = false
	AudioManagerScript.play_go(true)
	_execute_npc_repath()


func _trigger_game_over() -> void:
	_state = State.GAME_OVER
	_npc_intent.clear_target()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	AudioManagerScript.play_lose(true)

	var m := int(_survival_time) / 60
	var s := fmod(_survival_time, 60.0)
	_game_over_time_lbl.text = "%02d:%05.2f" % [m, s]
	_game_over_dialog.visible = true
	_banner_panel.visible = false
	_target_beacon.visible = false


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


func _build_camera() -> void:
	_camera = FollowCameraScript.new()
	_camera.fov = 55.0
	_camera.near = 0.05
	_camera.current = true
	add_child(_camera)


func _build_characters() -> void:
	_player = PlayerControllerScript.new()
	_player.name = "PlayerEscaper"
	_player.position = _player_spawn
	_player_intent = PlayerIntentSourceScript.new()
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

	# Top Banner
	_banner_panel = PanelContainer.new()
	_banner_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner_panel.offset_left = -300
	_banner_panel.offset_right = 300
	_banner_panel.offset_top = 20
	_banner_panel.offset_bottom = 100
	_banner_panel.custom_minimum_size = Vector2(600, 80)
	_banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_banner_style = StyleBoxFlat.new()
	_banner_style.bg_color = Color(0.1, 0.12, 0.16, 0.95)
	_banner_style.set_corner_radius_all(10)
	_banner_style.set_border_width_all(2)
	_banner_style.border_color = Color(1.0, 0.8, 0.2)
	_banner_style.set_content_margin_all(10)
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

	# Left Bottom Stat HUD
	_info_box = PanelContainer.new()
	_info_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_info_box.offset_left = 24
	_info_box.offset_bottom = -24
	_info_box.offset_right = 320
	_info_box.offset_top = -180
	_info_box.custom_minimum_size = Vector2(296, 156)
	_info_box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var info_style := StyleBoxFlat.new()
	info_style.bg_color = Color(0.08, 0.10, 0.14, 0.90)
	info_style.set_corner_radius_all(8)
	info_style.set_border_width_all(1)
	info_style.border_color = Color(0.3, 0.35, 0.45, 0.8)
	info_style.set_content_margin_all(12)
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

	_hint_x_toggle_label = Label.new()
	_hint_x_toggle_label.text = "AI 路线与红柱: 已隐藏 (连按两下 X 开启)"
	if _custom_font != null:
		_hint_x_toggle_label.add_theme_font_override("font", _custom_font)
	_hint_x_toggle_label.add_theme_font_size_override("font_size", 13)
	_hint_x_toggle_label.modulate = Color(0.7, 0.7, 0.7, 0.65)
	stat_vbox.add_child(_hint_x_toggle_label)

	# Right Bottom Keycaps Overlay
	_build_keycaps_overlay()

	# Game Over Modal
	_build_game_over_dialog()


func _build_keycaps_overlay() -> void:
	_keycaps_overlay = PanelContainer.new()
	_keycaps_overlay.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_keycaps_overlay.offset_right = -24
	_keycaps_overlay.offset_bottom = -24
	_keycaps_overlay.offset_left = -260
	_keycaps_overlay.offset_top = -140
	_keycaps_overlay.custom_minimum_size = Vector2(236, 116)
	_keycaps_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.14, 0.75)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	_keycaps_overlay.add_theme_stylebox_override("panel", style)
	_hud_canvas.add_child(_keycaps_overlay)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	_keycaps_overlay.add_child(grid)

	_add_mini_key(grid, "res://assets/buttons_pattern/W.png", "移动控制")
	_add_mini_key(grid, "res://assets/buttons_pattern/SHIFT.png", "冲刺奔跑")
	_add_mini_key(grid, "res://assets/buttons_pattern/SPACE.png", "跳跃/攀爬")
	_add_mini_key(grid, "res://assets/buttons_pattern/X.png", "双击显隐路线")


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
	_banner_style.bg_color = Color(0.28, 0.18, 0.04, 0.95)
	_banner_style.border_color = Color(1.0, 0.82, 0.2)
	if ResourceLoader.exists("res://assets/UI_assets/extra-time.svg"):
		_banner_icon.texture = load("res://assets/UI_assets/extra-time.svg")
		_banner_icon.modulate = Color(1.0, 0.85, 0.2)

	_banner_title.text = "逃生准备倒计时: %.1f 秒" % _escape_timer
	if _custom_font != null:
		_banner_title.add_theme_font_override("font", _custom_font)
		_banner_sub.add_theme_font_override("font", _custom_font)
	_banner_title.modulate = Color(1.0, 0.9, 0.3)
	_banner_sub.text = "尽快利用地形与跳跃拉开距离！倒计时结束后追缉者将出动！"
	_survival_label.text = "逃生倒计时: %.1f s" % _escape_timer
	_status_detail_label.text = "追缉者状态: 锁定原地待命中"


func _update_active_chase_hud() -> void:
	_banner_style.bg_color = Color(0.30, 0.06, 0.08, 0.95)
	_banner_style.border_color = Color(1.0, 0.35, 0.35)
	if ResourceLoader.exists("res://assets/UI_assets/cctv-camera.svg"):
		_banner_icon.texture = load("res://assets/UI_assets/cctv-camera.svg")
		_banner_icon.modulate = Color(1.0, 0.35, 0.35)

	_banner_title.text = "追缉进行中！全力逃生！"
	if _custom_font != null:
		_banner_title.add_theme_font_override("font", _custom_font)
		_banner_sub.add_theme_font_override("font", _custom_font)
	_banner_title.modulate = Color(1.0, 0.4, 0.4)

	var dist := _player.global_position.distance_to(_npc.global_position) if _player and _npc else 0.0
	_banner_sub.text = "追缉者距离: %.1fm (接近至 1m 以内即判定捕获)" % dist

	var m := int(_survival_time) / 60
	var s := fmod(_survival_time, 60.0)
	_survival_label.text = "已逃生生存时间: %02d:%05.2f" % [m, s]
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
	if _npc_intent != null and _npc_intent._direct_chase_mode:
		_status_detail_label.text = "追缉者寻路: 直线无障碍冲锋 (200ms延迟/省算力)"
	else:
		_status_detail_label.text = "追缉者寻路: %s" % ("同平台高频追踪 (60ms)" if same_plat else "跨障碍/高低差规划 (250ms)")


func _build_game_over_dialog() -> void:
	_game_over_dialog = PanelContainer.new()
	_game_over_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_game_over_dialog.offset_left = -220
	_game_over_dialog.offset_right = 220
	_game_over_dialog.offset_top = -170
	_game_over_dialog.offset_bottom = 170
	_game_over_dialog.custom_minimum_size = Vector2(440, 340)
	_game_over_dialog.visible = false

	var diag_style := StyleBoxFlat.new()
	diag_style.bg_color = Color(0.12, 0.08, 0.08, 0.98)
	diag_style.set_corner_radius_all(12)
	diag_style.set_content_margin_all(20)
	diag_style.set_border_width_all(2)
	diag_style.border_color = Color(0.95, 0.25, 0.25)
	_game_over_dialog.add_theme_stylebox_override("panel", diag_style)
	_hud_canvas.add_child(_game_over_dialog)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	_game_over_dialog.add_child(vbox)

	var icon := TextureRect.new()
	if ResourceLoader.exists("res://assets/UI_assets/grim-reaper.svg"):
		icon.texture = load("res://assets/UI_assets/grim-reaper.svg")
	icon.custom_minimum_size = Vector2(56, 56)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Color(1.0, 0.3, 0.3)
	vbox.add_child(icon)

	var title := Label.new()
	title.text = "被 追 缉 者 捕 获 ！"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _custom_font != null:
		title.add_theme_font_override("font", _custom_font)
	title.add_theme_font_size_override("font_size", 24)
	title.modulate = Color(1.0, 0.35, 0.35)
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = "追缉者已逼近至 1 格范围以内，逃生失败。"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _custom_font != null:
		desc.add_theme_font_override("font", _custom_font)
	desc.add_theme_font_size_override("font_size", 14)
	desc.modulate = Color(0.8, 0.8, 0.8)
	vbox.add_child(desc)

	_game_over_time_lbl = Label.new()
	_game_over_time_lbl.text = "00:00.0"
	_game_over_time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _custom_font != null:
		_game_over_time_lbl.add_theme_font_override("font", _custom_font)
	_game_over_time_lbl.add_theme_font_size_override("font_size", 30)
	_game_over_time_lbl.modulate = Color(1.0, 0.85, 0.25)
	vbox.add_child(_game_over_time_lbl)

	var btn_box := HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_box)

	var retry_btn := Button.new()
	retry_btn.text = "重新逃生挑战"
	if _custom_font != null:
		retry_btn.add_theme_font_override("font", _custom_font)
	retry_btn.add_theme_font_size_override("font_size", 16)
	retry_btn.custom_minimum_size = Vector2(130, 40)
	retry_btn.pressed.connect(_start_escape_countdown)
	btn_box.add_child(retry_btn)

	var menu_btn := Button.new()
	menu_btn.text = "返回游戏大厅"
	if _custom_font != null:
		menu_btn.add_theme_font_override("font", _custom_font)
	menu_btn.add_theme_font_size_override("font_size", 16)
	menu_btn.custom_minimum_size = Vector2(130, 40)
	menu_btn.pressed.connect(func() -> void:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file(TITLE_SCENE)
	)
	btn_box.add_child(menu_btn)
