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
const FAST_REPATH_INTERVAL := 0.15
const SLOW_REPATH_INTERVAL := 0.90
const CATCH_DISTANCE_THRESHOLD := 1.05

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

var _path_mesh_instance: MeshInstance3D
var _path_immediate_mesh: ImmediateMesh
var _target_beacon: MeshInstance3D

var _hud_canvas: CanvasLayer
var _banner_panel: PanelContainer
var _banner_style: StyleBoxFlat
var _banner_title: Label
var _banner_sub: Label
var _info_box: PanelContainer
var _survival_label: Label
var _distance_label: Label
var _status_detail_label: Label

var _map_select_dialog: PanelContainer
var _map_list: ItemList
var _game_over_dialog: PanelContainer
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
			if _map_select_dialog.visible:
				get_tree().change_scene_to_file(MENU_SCENE)
				return
			if _game_over_dialog.visible:
				get_tree().change_scene_to_file(MENU_SCENE)
				return
			_open_map_select_dialog()
			get_viewport().set_input_as_handled()
			return


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

			# Catch detection: within 1 block cell distance
			var dist := _player.global_position.distance_to(_npc.global_position)
			var vert_dist := absf(_player.global_position.y - _npc.global_position.y)
			if dist <= CATCH_DISTANCE_THRESHOLD and vert_dist <= 1.5:
				_trigger_game_over()
				return

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

			# Rule 4: NPC airborne / jump / climb deferral execution on landing
			var npc_busy := _npc_intent.is_performing_jump_or_climb() or not _npc.is_on_floor()
			if not npc_busy and _deferred_repath_pending:
				_deferred_repath_pending = false
				_execute_npc_repath()


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
	_target_beacon.visible = true

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


func _trigger_game_over() -> void:
	_state = State.GAME_OVER
	_npc_intent.clear_target()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_banner_style.bg_color = Color(0.32, 0.08, 0.08, 0.96)
	_banner_style.border_color = Color(1.0, 0.3, 0.3)
	_banner_title.text = "💀 【你已被追缉者捕获！】"
	_banner_title.modulate = Color(1.0, 0.45, 0.45)
	_banner_sub.text = "追缉者获胜！按 ESC 或点击下方按钮重新挑战"

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
	# Player (Escaper)
	_player = PlayerControllerScript.new()
	_player.name = "PlayerEscaper"
	_player.position = _player_spawn
	_player_intent = PlayerIntentSourceScript.new()
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


# --- HUD Construction & Updates --------------------------------------------

func _build_hud() -> void:
	_hud_canvas = CanvasLayer.new()
	add_child(_hud_canvas)

	# Top Banner
	_banner_panel = PanelContainer.new()
	_banner_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner_panel.offset_left = -280
	_banner_panel.offset_right = 280
	_banner_panel.offset_top = 24
	_banner_panel.offset_bottom = 104
	_banner_panel.custom_minimum_size = Vector2(560, 80)
	_banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_banner_style = StyleBoxFlat.new()
	_banner_style.bg_color = Color(0.1, 0.12, 0.16, 0.95)
	_banner_style.set_corner_radius_all(10)
	_banner_style.set_border_width_all(2)
	_banner_style.border_color = Color(1.0, 0.8, 0.2)
	_banner_style.set_content_margin_all(10)
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

	# Left-top stats HUD
	_info_box = PanelContainer.new()
	_info_box.offset_left = 20
	_info_box.offset_top = 20
	_info_box.custom_minimum_size = Vector2(240, 90)
	var info_style := StyleBoxFlat.new()
	info_style.bg_color = Color(0.08, 0.10, 0.13, 0.88)
	info_style.set_corner_radius_all(8)
	info_style.set_content_margin_all(10)
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

	_build_map_select_dialog()
	_build_game_over_dialog()


func _update_escape_countdown_hud() -> void:
	_banner_style.bg_color = Color(0.28, 0.18, 0.04, 0.95)
	_banner_style.border_color = Color(1.0, 0.82, 0.2)
	_banner_title.text = "⏳ 逃生准备倒计时: %.1f 秒" % _escape_timer
	_banner_title.modulate = Color(1.0, 0.9, 0.3)
	_banner_sub.text = "尽快利用地形与跳跃拉开距离！倒计时结束后追缉者将出动！"
	_survival_label.text = "逃生倒计时: %.1f s" % _escape_timer
	_status_detail_label.text = "追缉者状态: 锁定原地倒计时中"


func _update_active_chase_hud() -> void:
	_banner_style.bg_color = Color(0.30, 0.06, 0.08, 0.95)
	_banner_style.border_color = Color(1.0, 0.35, 0.35)
	_banner_title.text = "🚨 追缉进行中！全力逃生！"
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
	_status_detail_label.text = "追缉者寻路: %s" % ("同平台高频追踪" if same_plat else "跨障碍/高低差规划")


func _build_map_select_dialog() -> void:
	_map_select_dialog = PanelContainer.new()
	_map_select_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_map_select_dialog.offset_left = -260
	_map_select_dialog.offset_right = 260
	_map_select_dialog.offset_top = -200
	_map_select_dialog.offset_bottom = 200
	_map_select_dialog.custom_minimum_size = Vector2(520, 400)
	var diag_style := StyleBoxFlat.new()
	diag_style.bg_color = Color(0.12, 0.14, 0.18, 0.98)
	diag_style.set_corner_radius_all(10)
	diag_style.set_content_margin_all(16)
	diag_style.set_border_width_all(2)
	diag_style.border_color = Color(0.3, 0.75, 1.0)
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
	back_btn.pressed.connect(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))
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
	_game_over_dialog.offset_left = -220
	_game_over_dialog.offset_right = 220
	_game_over_dialog.offset_top = -140
	_game_over_dialog.offset_bottom = 140
	_game_over_dialog.custom_minimum_size = Vector2(440, 280)
	var diag_style := StyleBoxFlat.new()
	diag_style.bg_color = Color(0.16, 0.08, 0.10, 0.98)
	diag_style.set_corner_radius_all(10)
	diag_style.set_content_margin_all(20)
	diag_style.set_border_width_all(2)
	diag_style.border_color = Color(1.0, 0.35, 0.35)
	_game_over_dialog.add_theme_stylebox_override("panel", diag_style)
	_game_over_dialog.visible = false
	_hud_canvas.add_child(_game_over_dialog)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	_game_over_dialog.add_child(vbox)

	var title := Label.new()
	title.text = "💀 追缉者获胜！"
	title.add_theme_font_size_override("font_size", 22)
	title.modulate = Color(1.0, 0.4, 0.4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

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
	menu_btn.pressed.connect(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))
	btn_box.add_child(menu_btn)
