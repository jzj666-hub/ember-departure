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
const KeybindManagerScript = preload("res://scripts/keybind_manager.gd")
const KeybindRemapPanelScript = preload("res://scripts/keybind_remap_panel.gd")
const WorldBuilderScript = preload("res://scripts/world/world_builder.gd")
const ENV_PRESET = preload("res://config/env/weapon_trial.tres")
const GROUND_PRESET = preload("res://config/ground/weapon_trial.tres")
const GROUND_HALF := 40.0

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
var _keybind_panel: Control = null
var _hint_lbl: Label

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
	WorldBuilderScript.build_environment(self, ENV_PRESET)


func _build_ground() -> void:
	WorldBuilderScript.build_ground(self, GROUND_PRESET, GROUND_HALF)


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

	var remap_btn := Button.new()
	remap_btn.text = "⚙️ 按键重定向设置 (按 O)"
	remap_btn.custom_minimum_size = Vector2(0, 32)
	if _custom_font != null:
		remap_btn.add_theme_font_override("font", _custom_font)
	remap_btn.add_theme_font_size_override("font_size", 13)
	remap_btn.pressed.connect(func() -> void: _open_keybind_panel())
	left_vbox.add_child(remap_btn)

	# 3. Bottom Immersive Hint Card
	_immersive_hint_panel = PanelContainer.new()
	_immersive_hint_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_immersive_hint_panel.position = Vector2(-420, -75)
	_immersive_hint_panel.custom_minimum_size = Vector2(400, 55)

	var b_style := StyleBoxFlat.new()
	b_style.bg_color = Color(0.07, 0.09, 0.13, 0.85)
	b_style.set_corner_radius_all(8)
	b_style.set_border_width_all(1)
	b_style.border_color = Color(0.25, 0.30, 0.40)
	b_style.set_content_margin_all(8)
	_immersive_hint_panel.add_theme_stylebox_override("panel", b_style)
	_hud_layer.add_child(_immersive_hint_panel)

	_hint_lbl = Label.new()
	_refresh_hint_text()
	if _custom_font != null:
		_hint_lbl.add_theme_font_override("font", _custom_font)
	_hint_lbl.add_theme_font_size_override("font_size", 12)
	_hint_lbl.modulate = Color(0.85, 0.88, 0.92, 0.85)
	_immersive_hint_panel.add_child(_hint_lbl)

	# 4. Keybind Remap Panel Modal
	_keybind_panel = KeybindRemapPanelScript.new()
	_keybind_panel.set_anchors_preset(Control.PRESET_CENTER)
	_keybind_panel.position = Vector2(-310, -280)
	_keybind_panel.visible = false
	_keybind_panel.closed.connect(_on_keybind_panel_closed)
	_hud_layer.add_child(_keybind_panel)

	KeybindManagerScript.get_instance().keybindings_changed.connect(func() -> void:
		_refresh_hint_text()
		_update_idle_combo_prompt()
	)


func _refresh_hint_text() -> void:
	if _hint_lbl == null:
		return
	var km = KeybindManagerScript.get_instance()
	var atk: String = km.binding_display_text("attack")
	var hvy: String = km.binding_display_text("heavy")
	var roll: String = km.binding_display_text("roll")
	_hint_lbl.text = "【L】武器库 · 【O】按键重定向 · 【Tab】换英雄\n%s: 普攻 · %s: 重击 · %s: 翻滚" % [atk, hvy, roll]


func _open_keybind_panel() -> void:
	if _keybind_panel != null:
		_keybind_panel.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_keybind_panel_closed() -> void:
	_refresh_hint_text()
	_update_idle_combo_prompt()
	if _immersive:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _set_immersive(immersive: bool) -> void:
	_immersive = immersive
	if _left_panel != null:
		_left_panel.visible = not _immersive
	if _keybind_panel != null and _immersive:
		_keybind_panel.visible = false

	if _immersive:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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

	# Compose clean prompt text dynamically from KeybindManager
	var km = KeybindManagerScript.get_instance()
	var atk_prompt: String = km.binding_short_action_text("attack")
	var hvy_prompt: String = km.binding_short_action_text("heavy")
	var prompt_action := ""
	if has_attack and has_heavy:
		prompt_action = "%s 或 %s" % [atk_prompt, hvy_prompt]
	elif has_attack:
		prompt_action = atk_prompt
	elif has_heavy:
		prompt_action = hvy_prompt
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
	var km = KeybindManagerScript.get_instance()
	var atk_prompt: String = km.binding_short_action_text("attack")
	var hvy_prompt: String = km.binding_short_action_text("heavy")

	if _current_config.is_empty():
		_combo_prompt_label.text = "【%s】普通挥击起手" % atk_prompt
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
		_combo_prompt_label.text = "【%s 或 %s】开始出招" % [atk_prompt, hvy_prompt]
	elif has_heavy:
		_combo_prompt_label.text = "【%s】重击/派生起手" % hvy_prompt
	else:
		_combo_prompt_label.text = "【%s】普通挥击起手" % atk_prompt

	_combo_prompt_label.modulate = Color(1.0, 0.88, 0.35)
	_combo_sub_label.text = "当前神兵: %s · 待命中 (按 L 开关武器库 · 按 O 重定向按键)" % _current_weapon_id


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null:
		if _immersive and button.pressed and _player != null:
			var km = KeybindManagerScript.get_instance()
			var act: String = km.get_action_for_mouse_button(button.button_index)
			if not act.is_empty():
				_player.request_button(act)
				return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_O, KEY_F2:
				get_viewport().set_input_as_handled()
				if _keybind_panel != null:
					if _keybind_panel.visible:
						_keybind_panel.visible = false
						_on_keybind_panel_closed()
					else:
						_open_keybind_panel()
				return
			KEY_L:
				get_viewport().set_input_as_handled()
				_set_immersive(not _immersive)
				return
			KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				if _keybind_panel != null and _keybind_panel.visible:
					_keybind_panel.visible = false
					_on_keybind_panel_closed()
					return
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
