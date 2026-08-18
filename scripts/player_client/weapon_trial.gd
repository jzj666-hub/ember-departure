extends Node3D
## Player client weapon trial and combo sandbox.
## Default immersive mode (L toggles armory menu). Real-time node tree combo prompts on top center HUD.

const CharacterPipelineScript = preload("res://tools/character_pipeline.gd")
const PlayerControllerScript = preload("res://scripts/player_controller.gd")
const PlayerIntentSourceScript = preload("res://scripts/player_intent_source.gd")
const FollowCameraScript = preload("res://scripts/follow_camera.gd")
const EquipmentManagerScript = preload("res://scripts/equipment_manager.gd")
const DummyTargetScript = preload("res://scripts/dummy_target.gd")
const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const WeaponConfigScript = preload("res://scripts/weapon_config.gd")
const WeaponGraphScript = preload("res://scripts/weapon_graph.gd")

const TITLE_SCENE := "res://scenes/player_client/title_screen.tscn"
const FONT_PATH := "res://assets/Fonts/Long_Cang/LongCang-Regular.ttf"
const SPAWN := Vector3(0.0, 0.2, 0.0)
const DUMMY_POS := Vector3(0.0, 0.0, 3.2)
const BLADE_PAD := 0.15
const HIT_DAMAGE := 25.0

var _characters: Array = []
var _char_index := 0
var _player: CharacterBody3D
var _camera: Camera3D
var _visual: Node3D
var _equipment_manager: EquipmentManager
var _dummy: DummyTarget

var _configured_weapons: Array[String] = []
var _current_weapon_id := ""
var _current_config := {}
var _custom_font: Font = null
var _immersive := true

# UI Layers and Elements
var _hud_layer: CanvasLayer
var _left_panel: PanelContainer
var _weapon_list: ItemList
var _combo_box: VBoxContainer
var _weapon_title_label: Label
var _immersive_hint_panel: PanelContainer

# Top Real-time Combo Prompt Banner
var _combo_banner_panel: PanelContainer
var _combo_prompt_label: Label
var _combo_sub_label: Label
var _combo_window_progress: ProgressBar

# Combat Tracking
var _blade_inside := false
var _last_stroke := -1
var _prev_tip := Vector3.ZERO
var _has_prev_tip := false


func _ready() -> void:
	AudioManagerScript.init_pool(self)
	if ResourceLoader.exists(FONT_PATH):
		_custom_font = load(FONT_PATH) as Font

	_characters = CharacterPipelineScript.list_characters().filter(
		func(c: Dictionary) -> bool: return ResourceLoader.exists(c.scene))

	_load_configured_weapons()

	_build_environment()
	_build_ground()
	_build_dummy()
	_build_player()
	_build_hud()

	if not _configured_weapons.is_empty():
		_select_weapon(_configured_weapons[0])

	_set_immersive(true)


func _load_configured_weapons() -> void:
	_configured_weapons.clear()
	var raw_list := WeaponConfigScript.list_configured()
	for id in raw_list:
		if id != "_default" and id != "none":
			if WeaponConfigScript.mesh_scene_for(id) != null:
				_configured_weapons.append(id)


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.18, 0.24, 0.35)
	sky_mat.sky_horizon_color = Color(0.55, 0.52, 0.58)
	sky_mat.ground_bottom_color = Color(0.10, 0.10, 0.12)
	sky_mat.ground_horizon_color = Color(0.45, 0.48, 0.55)

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_intensity = 0.9
	env.glow_bloom = 0.2
	env.fog_enabled = true
	env.fog_light_color = Color(0.35, 0.38, 0.45)
	env.fog_density = 0.008

	var env_node := WorldEnvironment.new()
	env_node.environment = env
	add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	sun.transform.basis = Basis.from_euler(Vector3(deg_to_rad(-45.0), deg_to_rad(-35.0), 0.0))
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.6
	fill.shadow_enabled = false
	fill.transform.basis = Basis.from_euler(Vector3(deg_to_rad(-20.0), deg_to_rad(145.0), 0.0))
	add_child(fill)


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"

	var plane := PlaneMesh.new()
	plane.size = Vector2(80.0, 80.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.14, 0.15, 0.18)
	mat.roughness = 0.95
	plane.material = mat

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = plane
	body.add_child(mesh_inst)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 0.4, 80.0)
	shape.shape = box
	shape.position.y = -0.2
	body.add_child(shape)
	add_child(body)

	# Decorative arena ring
	var ring_mesh := ImmediateMesh.new()
	ring_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var segs := 64
	for i in range(segs + 1):
		var ang := TAU * float(i) / float(segs)
		var vx := cos(ang) * 12.0
		var vz := sin(ang) * 12.0
		ring_mesh.surface_set_color(Color(0.9, 0.55, 0.2, 0.6))
		ring_mesh.surface_add_vertex(Vector3(vx, 0.005, vz))
	ring_mesh.surface_end()

	var r_mat := StandardMaterial3D.new()
	r_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	r_mat.vertex_color_use_as_albedo = true
	r_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var ring_inst := MeshInstance3D.new()
	ring_inst.mesh = ring_mesh
	ring_inst.material_override = r_mat
	add_child(ring_inst)


func _build_dummy() -> void:
	_dummy = DummyTargetScript.new()
	_dummy.name = "TrainingDummy"
	_dummy.position = DUMMY_POS
	add_child(_dummy)


func _build_player() -> void:
	_player = PlayerControllerScript.new()
	_player.name = "Player"
	_player.position = SPAWN
	_player.intent_source = PlayerIntentSourceScript.new()
	add_child(_player)

	_camera = FollowCameraScript.new()
	_camera.name = "Camera"
	_camera.fov = 55.0
	_camera.near = 0.05
	_camera.current = true
	add_child(_camera)

	_spawn_character()


func _spawn_character() -> void:
	if _characters.is_empty():
		return
	if _visual != null:
		_visual.queue_free()
		_visual = null
	for child in _player.get_children():
		if child is CollisionShape3D or child is EquipmentManager:
			child.queue_free()

	_equipment_manager = EquipmentManagerScript.new()
	_equipment_manager.name = "EquipmentManager"
	_player.add_child(_equipment_manager)

	var entry: Dictionary = _characters[_char_index]
	var scene := load(entry.scene) as PackedScene
	if scene == null:
		return
	_visual = scene.instantiate() as Node3D
	_player.add_child(_visual)

	var height: float = _visual.get("body_height")
	if height <= 0.1:
		height = 1.75

	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = minf(0.3, height * 0.2)
	capsule.height = height
	collider.shape = capsule
	collider.position.y = height * 0.5
	_player.add_child(collider)

	_player.setup(_visual, _camera)
	_camera.target = _player
	_camera.frame_for(height)
	_camera.snap()

	if not _current_weapon_id.is_empty():
		_equipment_manager.equip_by_id(_current_weapon_id)


func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "HUD"
	add_child(_hud_layer)

	# 1. Top Real-time Combo Prompt Banner (Node Tree driven)
	_combo_banner_panel = PanelContainer.new()
	_combo_banner_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_combo_banner_panel.offset_left = 320
	_combo_banner_panel.offset_right = -320
	_combo_banner_panel.offset_top = 22
	_combo_banner_panel.offset_bottom = 110

	var cb_style := StyleBoxFlat.new()
	cb_style.bg_color = Color(0.06, 0.08, 0.12, 0.90)
	cb_style.set_corner_radius_all(10)
	cb_style.set_border_width_all(2)
	cb_style.border_color = Color(1.0, 0.65, 0.15, 0.95)
	cb_style.set_content_margin_all(10)
	_combo_banner_panel.add_theme_stylebox_override("panel", cb_style)
	_hud_layer.add_child(_combo_banner_panel)

	var cb_vbox := VBoxContainer.new()
	cb_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	cb_vbox.add_theme_constant_override("separation", 4)
	_combo_banner_panel.add_child(cb_vbox)

	_combo_prompt_label = Label.new()
	_combo_prompt_label.text = "【点左键】普通挥击起手"
	_combo_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _custom_font != null:
		_combo_prompt_label.add_theme_font_override("font", _custom_font)
	_combo_prompt_label.add_theme_font_size_override("font_size", 22)
	_combo_prompt_label.modulate = Color(1.0, 0.88, 0.35)
	cb_vbox.add_child(_combo_prompt_label)

	_combo_sub_label = Label.new()
	_combo_sub_label.text = "当前神兵: 未装备 · 连招窗口待命"
	_combo_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _custom_font != null:
		_combo_sub_label.add_theme_font_override("font", _custom_font)
	_combo_sub_label.add_theme_font_size_override("font_size", 13)
	_combo_sub_label.modulate = Color(0.75, 0.85, 0.95, 0.85)
	cb_vbox.add_child(_combo_sub_label)

	_combo_window_progress = ProgressBar.new()
	_combo_window_progress.min_value = 0.0
	_combo_window_progress.max_value = 1.0
	_combo_window_progress.value = 0.0
	_combo_window_progress.show_percentage = false
	_combo_window_progress.custom_minimum_size = Vector2(0, 4)
	var win_fill := StyleBoxFlat.new()
	win_fill.bg_color = Color(1.0, 0.65, 0.2)
	win_fill.set_corner_radius_all(2)
	_combo_window_progress.add_theme_stylebox_override("fill", win_fill)
	cb_vbox.add_child(_combo_window_progress)

	# 2. Left Menu Panel: Saved Weapons Armory (Toggled by L key)
	_left_panel = PanelContainer.new()
	_left_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_left_panel.position = Vector2(20, 20)
	_left_panel.custom_minimum_size = Vector2(300, 520)

	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color(0.07, 0.09, 0.13, 0.96)
	p_style.set_corner_radius_all(10)
	p_style.set_border_width_all(2)
	p_style.border_color = Color(0.9, 0.55, 0.2)
	p_style.set_content_margin_all(14)
	_left_panel.add_theme_stylebox_override("panel", p_style)
	_hud_layer.add_child(_left_panel)

	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 10)
	_left_panel.add_child(left_vbox)

	var list_title := Label.new()
	list_title.text = "⚔️ 兵器藏经阁 (按 L 关闭)"
	if _custom_font != null:
		list_title.add_theme_font_override("font", _custom_font)
	list_title.add_theme_font_size_override("font_size", 18)
	list_title.modulate = Color(1.0, 0.85, 0.3)
	left_vbox.add_child(list_title)

	var list_desc := Label.new()
	list_desc.text = "点击切换武器 · 按数字键 1~9 快速装备"
	if _custom_font != null:
		list_desc.add_theme_font_override("font", _custom_font)
	list_desc.add_theme_font_size_override("font_size", 12)
	list_desc.modulate = Color(0.65, 0.7, 0.8)
	left_vbox.add_child(list_desc)

	_weapon_list = ItemList.new()
	_weapon_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if _custom_font != null:
		_weapon_list.add_theme_font_override("font", _custom_font)
	_weapon_list.add_theme_font_size_override("font_size", 14)
	_weapon_list.item_selected.connect(func(idx: int) -> void:
		if idx >= 0 and idx < _configured_weapons.size():
			_select_weapon(_configured_weapons[idx])
			_set_immersive(true)
	)
	left_vbox.add_child(_weapon_list)

	for i in range(_configured_weapons.size()):
		var w_id := _configured_weapons[i]
		var shortcut_prefix := "[%d] " % (i + 1) if i < 9 else "    "
		_weapon_list.add_item(shortcut_prefix + w_id)

	# 3. Bottom Immersive Hint Card
	_immersive_hint_panel = PanelContainer.new()
	_immersive_hint_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_immersive_hint_panel.position = Vector2(-380, -75)
	_immersive_hint_panel.custom_minimum_size = Vector2(360, 55)

	var b_style := StyleBoxFlat.new()
	b_style.bg_color = Color(0.07, 0.09, 0.13, 0.85)
	b_style.set_corner_radius_all(8)
	b_style.set_border_width_all(1)
	b_style.border_color = Color(0.25, 0.30, 0.40)
	b_style.set_content_margin_all(8)
	_immersive_hint_panel.add_theme_stylebox_override("panel", b_style)
	_hud_layer.add_child(_immersive_hint_panel)

	var hint_lbl := Label.new()
	hint_lbl.text = "【L 键】开关武器库菜单 · 【Tab】换英雄\n左键: 普攻 · 右键: 重击/派生 · ESC: 返回主菜单"
	if _custom_font != null:
		hint_lbl.add_theme_font_override("font", _custom_font)
	hint_lbl.add_theme_font_size_override("font_size", 12)
	hint_lbl.modulate = Color(0.85, 0.88, 0.92, 0.85)
	_immersive_hint_panel.add_child(hint_lbl)


func _set_immersive(immersive: bool) -> void:
	_immersive = immersive
	if _left_panel != null:
		_left_panel.visible = not _immersive

	if _immersive:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _select_weapon(weapon_id: String) -> void:
	_current_weapon_id = weapon_id
	_current_config = WeaponConfigScript.load_for(weapon_id)

	if _equipment_manager != null:
		_equipment_manager.equip_by_id(weapon_id)

	var idx := _configured_weapons.find(weapon_id)
	if idx >= 0 and _weapon_list != null:
		_weapon_list.select(idx)

	_update_idle_combo_prompt()


func _physics_process(_delta: float) -> void:
	if _player == null or _dummy == null or _equipment_manager == null:
		return

	var is_attacking: bool = _player.get("state") == PlayerControllerScript.State.ATTACKING
	if not is_attacking:
		_blade_inside = false
		_has_prev_tip = false
		return

	if _player.has_method("weapon_stroke_count"):
		var stroke: int = _player.call("weapon_stroke_count")
		if stroke != _last_stroke:
			_last_stroke = stroke
			_blade_inside = false
			_has_prev_tip = false

	var base := Vector3.ZERO
	var tip := Vector3.ZERO
	var item: HandheldItem = _equipment_manager.equipped("right_hand")

	if item != null and item.trail_anchor(0) != null and item.trail_anchor(1) != null:
		base = item.trail_anchor(0).global_position
		tip = item.trail_anchor(1).global_position
	elif item != null and item.has_method("blade_base_global"):
		base = item.blade_base_global()
		tip = item.blade_tip_global()
	else:
		base = _player.global_position + Vector3(0.0, 1.1, 0.0)
		tip = base + _player.global_transform.basis.z * -0.7

	var swing := (tip - _prev_tip) if _has_prev_tip else Vector3.ZERO
	var last_tip := _prev_tip if _has_prev_tip else tip
	_prev_tip = tip
	_has_prev_tip = true

	var hit: Dictionary = _dummy.segment_hit(base, tip, BLADE_PAD)
	if hit.is_empty():
		hit = _dummy.segment_hit(last_tip, tip, BLADE_PAD)

	var inside: bool = not hit.is_empty()
	if inside and not _blade_inside:
		_dummy.take_hit(hit.get("point", _dummy.global_position + Vector3(0, 0.9, 0)), HIT_DAMAGE, swing)
	_blade_inside = inside


func _process(_delta: float) -> void:
	if _player == null or _combo_prompt_label == null:
		return

	var graph = _player.get("_weapon_graph") as WeaponGraph
	var is_attacking: bool = _player.get("state") == PlayerControllerScript.State.ATTACKING

	if not is_attacking or graph == null or graph.current.is_empty():
		_update_idle_combo_prompt()
		_combo_window_progress.value = 0.0
		return

	# Real-time combo resolution from active weapon graph node
	var cur_id: String = graph.current
	var elapsed: float = graph.elapsed
	var action: Dictionary = graph.action_of(cur_id)
	var links: Array = action.get("links", [])

	_combo_sub_label.text = "神兵: %s · 招式: %s (%.2fs)" % [_current_weapon_id, cur_id, elapsed]

	if links.is_empty():
		_combo_prompt_label.text = "【招式收尾 / 连招结束】"
		_combo_prompt_label.modulate = Color(0.7, 0.75, 0.8)
		_combo_window_progress.value = 0.0
		return

	var has_attack := false
	var has_heavy := false
	var in_window := false
	var window_start := 999.0
	var window_end := 0.0

	for link in links:
		var trig: String = str(link.get("trigger", "attack"))
		if trig == "attack":
			has_attack = true
		elif trig == "heavy":
			has_heavy = true

		var win: Array = link.get("window", [0.0, 1.0])
		var w_start: float = float(win[0]) if win.size() >= 1 else 0.0
		var w_end: float = float(win[1]) if win.size() >= 2 else 1.0
		window_start = minf(window_start, w_start)
		window_end = maxf(window_end, w_end)

		if elapsed >= w_start and elapsed <= w_end:
			in_window = true

	# Compose clean prompt text according to user request
	var prompt_action := ""
	if has_attack and has_heavy:
		prompt_action = "点左键 或 点右键"
	elif has_attack:
		prompt_action = "点左键"
	elif has_heavy:
		prompt_action = "点右键"
	else:
		prompt_action = "按对应按键"

	if in_window:
		_combo_prompt_label.text = "🔥 连招窗口开启！【%s】" % prompt_action
		_combo_prompt_label.modulate = Color(1.0, 0.45, 0.15)
		var span := maxf(window_end - window_start, 0.01)
		_combo_window_progress.value = clampf((elapsed - window_start) / span, 0.0, 1.0)
	elif elapsed < window_start:
		_combo_prompt_label.text = "⏳ 连击准备（可预输入）：【%s】" % prompt_action
		_combo_prompt_label.modulate = Color(1.0, 0.88, 0.35)
		_combo_window_progress.value = 0.0
	else:
		_combo_prompt_label.text = "【窗口关闭 / 招式收尾】"
		_combo_prompt_label.modulate = Color(0.65, 0.7, 0.75)
		_combo_window_progress.value = 1.0


func _update_idle_combo_prompt() -> void:
	if _current_config.is_empty():
		_combo_prompt_label.text = "【点左键】普通挥击起手"
		_combo_sub_label.text = "当前神兵: %s · 待命状态" % _current_weapon_id
		return

	var entries: Array = _current_config.get("entries", [])
	var has_attack := false
	var has_heavy := false
	for entry in entries:
		var trig: String = str(entry.get("trigger", "attack"))
		if trig == "attack":
			has_attack = true
		elif trig == "heavy":
			has_heavy = true

	if has_attack and has_heavy:
		_combo_prompt_label.text = "【点左键 或 点右键】开始出招"
	elif has_heavy:
		_combo_prompt_label.text = "【点右键】重击/派生起手"
	else:
		_combo_prompt_label.text = "【点左键】普通挥击起手"

	_combo_prompt_label.modulate = Color(1.0, 0.88, 0.35)
	_combo_sub_label.text = "当前神兵: %s · 待命中（按 L 键打开武器库菜单）" % _current_weapon_id


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null:
		if _immersive and button.pressed and _player != null:
			if button.button_index == MOUSE_BUTTON_LEFT:
				_player.request_button("attack")
				return
			elif button.button_index == MOUSE_BUTTON_RIGHT:
				_player.request_button("heavy")
				return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_L:
				get_viewport().set_input_as_handled()
				_set_immersive(not _immersive)
				return
			KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				if not _immersive:
					_set_immersive(true)
					return
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				SceneLoader.change_scene(get_tree(), TITLE_SCENE, "返回主界面...")
				return
			KEY_TAB:
				get_viewport().set_input_as_handled()
				_char_index = (_char_index + 1) % _characters.size()
				_spawn_character()
				return
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				var num_idx: int = event.keycode - KEY_1
				if num_idx >= 0 and num_idx < _configured_weapons.size():
					get_viewport().set_input_as_handled()
					_select_weapon(_configured_weapons[num_idx])
					return
