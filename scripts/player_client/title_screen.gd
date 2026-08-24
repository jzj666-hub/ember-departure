extends Control
## User-facing game client title screen.
## Clean, immersive game-feel UI with LongCang font, vector icons, and ESC navigation.

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const MapDataScript = preload("res://scripts/map_data.gd")
const MapEditorScript = preload("res://scripts/map_editor.gd")
const PlaygroundScript = preload("res://scripts/playground.gd")
const AnimPipelineScript = preload("res://tools/anim_pipeline.gd")

const CHASE_SCENE := "res://scenes/player_client/chase_game.tscn"
const MAP_EDITOR_SCENE := "res://scenes/map_editor.tscn"
const PLAYGROUND_SCENE := "res://scenes/playground.tscn"
const WEAPON_TRIAL_SCENE := "res://scenes/player_client/weapon_trial.tscn"
const MAIN_GATEWAY_SCENE := "res://scenes/main_menu.tscn"
const FONT_PATH := "res://assets/Fonts/Long_Cang/LongCang-Regular.ttf"
const FONT_GLITCH_PATH := "res://assets/Fonts/Long_Cang,Rubik_Glitch/Rubik_Glitch/RubikGlitch-Regular.ttf"
const KeybindRemapPanelScript = preload("res://scripts/keybind_remap_panel.gd")
const ProfileManagerScript = preload("res://scripts/profile_manager.gd")

var _custom_font: Font = null
var _glitch_font: Font = null
var _map_dialog: PanelContainer
var _workshop_ask_dialog: PanelContainer
var _trial_ask_dialog: PanelContainer
var _profile_dialog: PanelContainer
var _keybind_dialog: Control = null
var _map_list: ItemList

var _profile_card: Button
var _profile_avatar_holder: Control
var _profile_name_lbl: Label

var _bg_viewport: SubViewport
var _bg_camera: Camera3D
var _bg_omni: OmniLight3D
var _bg_character: Character
var _bg_cam_angle: float = 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioManagerScript.init_pool(self)
	AudioManagerScript.play_bgm("res://assets/voice/background/song_of_the_sea.ogg", -6.0)
	if ResourceLoader.exists(FONT_PATH):
		_custom_font = load(FONT_PATH) as Font
	if ResourceLoader.exists(FONT_GLITCH_PATH):
		_glitch_font = load(FONT_GLITCH_PATH) as Font
	_build_ui()


func _process(delta: float) -> void:
	if _bg_camera != null:
		_bg_cam_angle += delta * 0.12
		_bg_camera.position.x = sin(_bg_cam_angle) * 0.45
		_bg_camera.position.y = 1.25 + sin(_bg_cam_angle * 1.5) * 0.05
		_bg_camera.position.z = 3.1 + cos(_bg_cam_angle) * 0.25
		_bg_camera.look_at(Vector3(0.2, 0.95, 0.0))

	if _bg_omni != null:
		var t := float(Time.get_ticks_msec()) * 0.004
		_bg_omni.light_energy = 1.2 + sin(t) * 0.25 + sin(t * 2.7) * 0.15


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			if _keybind_dialog != null and _keybind_dialog.visible:
				_keybind_dialog.visible = false
				return
			if _profile_dialog != null and _profile_dialog.visible:
				_profile_dialog.visible = false
				return
			if _trial_ask_dialog != null and _trial_ask_dialog.visible:
				_trial_ask_dialog.visible = false
				return
			if _workshop_ask_dialog != null and _workshop_ask_dialog.visible:
				_workshop_ask_dialog.visible = false
				return
			if _map_dialog != null and _map_dialog.visible:
				_map_dialog.visible = false
				return
			# Return to Mode Selector Gateway
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			SceneLoader.change_scene(get_tree(), MAIN_GATEWAY_SCENE, "返回主模式选择门户...")


func _build_ui() -> void:
	_build_3d_background()

	var overlay := ColorRect.new()
	overlay.set_anchors_preset(PRESET_FULL_RECT)
	overlay.color = Color(0.04, 0.05, 0.07, 0.52)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	var main_box := HBoxContainer.new()
	main_box.set_anchors_preset(PRESET_FULL_RECT)
	main_box.add_theme_constant_override("separation", 60)
	main_box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(main_box)

	# Left Column: Branding & Art
	var left_col := VBoxContainer.new()
	left_col.alignment = BoxContainer.ALIGNMENT_CENTER
	left_col.custom_minimum_size = Vector2(460, 0)
	main_box.add_child(left_col)

	var icon_tex := TextureRect.new()
	if ResourceLoader.exists("res://assets/UI_assets/daemon-skull.svg"):
		icon_tex.texture = load("res://assets/UI_assets/daemon-skull.svg")
	icon_tex.custom_minimum_size = Vector2(100, 100)
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.modulate = Color(1.25, 0.38, 0.28, 1.0)
	left_col.add_child(icon_tex)

	var title_lbl := Label.new()
	title_lbl.text = "灰烬 · 极限追缉"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _custom_font != null:
		title_lbl.add_theme_font_override("font", _custom_font)
	title_lbl.add_theme_font_size_override("font_size", 44)
	title_lbl.modulate = Color(0.78, 0.68, 0.44, 0.88)
	left_col.add_child(title_lbl)

	var subtitle_lbl := Label.new()
	subtitle_lbl.text = "EMBER DEPARTURE · PURSUIT"
	subtitle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _glitch_font != null:
		subtitle_lbl.add_theme_font_override("font", _glitch_font)
	subtitle_lbl.add_theme_font_size_override("font_size", 22)
	subtitle_lbl.modulate = Color(0.38, 0.54, 0.68, 0.75)
	left_col.add_child(subtitle_lbl)

	var tag_lbl := Label.new()
	tag_lbl.text = "1v1 极限身法逃生与追捕对决 (按 ESC 返回模式选择)"
	tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _custom_font != null:
		tag_lbl.add_theme_font_override("font", _custom_font)
	tag_lbl.add_theme_font_size_override("font_size", 14)
	tag_lbl.modulate = Color(0.36, 0.40, 0.46, 0.65)
	left_col.add_child(tag_lbl)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	left_col.add_child(spacer)

	# Embedded Profile Card in Left Column
	_build_left_profile_card(left_col)
	_build_keybind_entry_button(left_col)

	# Right Column: Action Buttons
	var right_col := VBoxContainer.new()
	right_col.alignment = BoxContainer.ALIGNMENT_CENTER
	right_col.custom_minimum_size = Vector2(390, 0)
	right_col.add_theme_constant_override("separation", 12)
	main_box.add_child(right_col)

	var btn_play := _create_menu_button("单机追缉对决", "SOLO PURSUIT CHALLENGE", "res://assets/UI_assets/claw-slashes.svg", Color(0.95, 0.35, 0.22))
	btn_play.pressed.connect(func(): _punch_button_and_act(btn_play, _open_map_selector))
	right_col.add_child(btn_play)

	var btn_multi := _create_menu_button("局域网联机对战", "LAN PURSUIT BATTLE", "res://assets/UI_assets/daemon-skull.svg", Color(0.30, 0.85, 1.0))
	btn_multi.pressed.connect(func() -> void:
		_trigger_scene_transition(btn_multi, func():
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			SceneLoader.change_scene(get_tree(), "res://scenes/player_client/multiplayer_lobby.tscn", "正在进入局域网联机大厅...")
		)
	)
	right_col.add_child(btn_multi)

	var btn_trial := _create_menu_button("身法试玩沙盒", "MOVEMENT SANDBOX", "res://assets/UI_assets/run.svg", Color(1.0, 0.70, 0.18))
	btn_trial.pressed.connect(func():
		_punch_button_and_act(btn_trial, func(): _trial_ask_dialog.visible = true)
	)
	right_col.add_child(btn_trial)

	var btn_weapon := _create_menu_button("兵器试炼与连招", "WEAPON ARMORY & COMBOS", "res://assets/UI_assets/winged-sword.svg", Color(1.0, 0.48, 0.20))
	btn_weapon.pressed.connect(func() -> void:
		_trigger_scene_transition(btn_weapon, func():
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			SceneLoader.change_scene(get_tree(), WEAPON_TRIAL_SCENE, "正在装备神兵与加载试炼场...")
		)
	)
	right_col.add_child(btn_weapon)

	var btn_pvp := _create_menu_button("刀剑人机对决", "1v1 SWORD PVP DUEL", "res://assets/UI_assets/winged-sword.svg", Color(0.95, 0.28, 0.45))
	btn_pvp.pressed.connect(func() -> void:
		_trigger_scene_transition(btn_pvp, func():
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			SceneLoader.change_scene(get_tree(), "res://scenes/player_client/sword_pvp_game.tscn", "正在进入刀剑决斗战场...")
		)
	)
	right_col.add_child(btn_pvp)

	var btn_editor := _create_menu_button("地图工坊", "3D MAP STUDIO", "res://assets/UI_assets/cubes.svg", Color(0.25, 0.75, 1.0))
	btn_editor.pressed.connect(func():
		_punch_button_and_act(btn_editor, func(): _workshop_ask_dialog.visible = true)
	)
	right_col.add_child(btn_editor)

	var btn_gateway := _create_menu_button("返回主选择门户", "BACK TO GATEWAY", "res://assets/UI_assets/gear-hammer.svg", Color(0.60, 0.68, 0.80))
	btn_gateway.pressed.connect(func() -> void:
		_trigger_scene_transition(btn_gateway, func():
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			SceneLoader.change_scene(get_tree(), MAIN_GATEWAY_SCENE, "返回主模式选择门户...")
		)
	)
	right_col.add_child(btn_gateway)

	_build_transition_overlay()
	_build_map_dialog()
	_build_workshop_ask_dialog()
	_build_trial_ask_dialog()
	_build_keybind_dialog()


func _create_menu_button(zh_text: String, en_text: String, icon_path: String, accent_color: Color) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(390, 56)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP

	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(0.08, 0.10, 0.14, 0.92)
	style_normal.set_corner_radius_all(10)
	style_normal.set_border_width_all(1)
	style_normal.border_color = Color(0.22, 0.26, 0.35, 0.8)
	style_normal.set_content_margin_all(10)
	btn.add_theme_stylebox_override("normal", style_normal)

	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = Color(0.14, 0.17, 0.24, 0.96)
	style_hover.set_corner_radius_all(10)
	style_hover.set_border_width_all(2)
	style_hover.border_color = accent_color
	style_hover.shadow_color = Color(accent_color.r, accent_color.g, accent_color.b, 0.3)
	style_hover.shadow_size = 8
	style_hover.set_content_margin_all(10)
	btn.add_theme_stylebox_override("hover", style_hover)

	var style_pressed := StyleBoxFlat.new()
	style_pressed.bg_color = Color(0.06, 0.08, 0.11, 0.98)
	style_pressed.set_corner_radius_all(10)
	style_pressed.set_border_width_all(2)
	style_pressed.border_color = accent_color
	style_pressed.set_content_margin_all(10)
	btn.add_theme_stylebox_override("pressed", style_pressed)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 14)
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hbox)

	var pad_left := Control.new()
	pad_left.custom_minimum_size = Vector2(4, 0)
	pad_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(pad_left)

	if ResourceLoader.exists(icon_path):
		var icon_rect := TextureRect.new()
		icon_rect.texture = load(icon_path)
		icon_rect.custom_minimum_size = Vector2(28, 28)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.modulate = Color(accent_color.r * 1.4, accent_color.g * 1.4, accent_color.b * 1.4, 1.0)
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(icon_rect)

	var text_vbox := VBoxContainer.new()
	text_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	text_vbox.add_theme_constant_override("separation", 1)
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(text_vbox)

	var zh_lbl := Label.new()
	zh_lbl.text = zh_text
	if _custom_font != null:
		zh_lbl.add_theme_font_override("font", _custom_font)
	zh_lbl.add_theme_font_size_override("font_size", 16)
	zh_lbl.modulate = Color(0.78, 0.80, 0.84, 0.95)
	zh_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_vbox.add_child(zh_lbl)

	var en_lbl := Label.new()
	en_lbl.text = en_text
	if _glitch_font != null:
		en_lbl.add_theme_font_override("font", _glitch_font)
	en_lbl.add_theme_font_size_override("font_size", 12)
	en_lbl.modulate = accent_color.lerp(Color(0.40, 0.45, 0.50), 0.55)
	en_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_vbox.add_child(en_lbl)

	return btn


var _transition_rect: ColorRect
var _transition_mat: ShaderMaterial
var _is_transitioning := false


func _build_transition_overlay() -> void:
	var trans_canvas := CanvasLayer.new()
	trans_canvas.layer = 30
	add_child(trans_canvas)

	_transition_rect = ColorRect.new()
	_transition_rect.set_anchors_preset(PRESET_FULL_RECT)
	_transition_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if ResourceLoader.exists("res://shaders/ember_burn_transition.gdshader"):
		var shader_res := load("res://shaders/ember_burn_transition.gdshader") as Shader
		_transition_mat = ShaderMaterial.new()
		_transition_mat.shader = shader_res
		_transition_mat.set_shader_parameter("progress", 0.0)
		_transition_mat.set_shader_parameter("ember_color", Color(1.0, 0.45, 0.12, 1.0))
		_transition_mat.set_shader_parameter("char_color", Color(0.04, 0.03, 0.03, 1.0))
		_transition_rect.material = _transition_mat

	trans_canvas.add_child(_transition_rect)


func _punch_button_and_act(btn: Button, action: Callable) -> void:
	AudioManagerScript.play_voice_file("res://assets/voice/sfx/swing_mid_01.wav", -4.0)
	var tw_btn := create_tween()
	tw_btn.set_parallel(true)
	tw_btn.tween_property(btn, "scale", Vector2(0.96, 0.96), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw_btn.tween_property(btn, "modulate", Color(2.2, 1.3, 0.7, 1.0), 0.05)
	tw_btn.chain().tween_property(btn, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw_btn.tween_property(btn, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.15)
	action.call()


func _trigger_scene_transition(source_node: Control = null, target_action: Callable = Callable()) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true

	# Sound punch feedback
	AudioManagerScript.play_voice_file("res://assets/voice/sfx/swing_mid_01.wav", -2.0)

	# Optional source punch squash & flash
	if source_node != null and is_instance_valid(source_node):
		var tw_btn := create_tween()
		tw_btn.set_parallel(true)
		tw_btn.tween_property(source_node, "scale", Vector2(0.95, 0.95), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw_btn.tween_property(source_node, "modulate", Color(2.5, 1.4, 0.7, 1.0), 0.06)
		tw_btn.chain().tween_property(source_node, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw_btn.tween_property(source_node, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.2)

	# Fullscreen Ember Burn Transition (0.95 seconds cinematic burn)
	if _transition_mat != null:
		_transition_mat.set_shader_parameter("progress", 0.0)
		var tw_burn := create_tween()
		tw_burn.tween_method(func(v: float): _transition_mat.set_shader_parameter("progress", v), 0.0, 1.0, 0.95).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw_burn.tween_callback(func():
			if target_action.is_valid():
				target_action.call()
			# Reset progress safety fallback
			_transition_mat.set_shader_parameter("progress", 0.0)
			_is_transitioning = false
		)
	else:
		if target_action.is_valid():
			target_action.call()
		_is_transitioning = false


func _build_map_dialog() -> void:
	_map_dialog = PanelContainer.new()
	_map_dialog.set_anchors_preset(PRESET_CENTER)
	_map_dialog.offset_left = -260
	_map_dialog.offset_right = 260
	_map_dialog.offset_top = -200
	_map_dialog.offset_bottom = 200
	_map_dialog.custom_minimum_size = Vector2(520, 400)
	_map_dialog.visible = false

	var diag_style := StyleBoxFlat.new()
	diag_style.bg_color = Color(0.12, 0.14, 0.18, 0.98)
	diag_style.set_corner_radius_all(10)
	diag_style.set_content_margin_all(16)
	diag_style.set_border_width_all(2)
	diag_style.border_color = Color(0.9, 0.25, 0.2)
	_map_dialog.add_theme_stylebox_override("panel", diag_style)
	add_child(_map_dialog)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_map_dialog.add_child(vbox)

	var title := Label.new()
	title.text = "选择追缉对决地图"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _custom_font != null:
		title.add_theme_font_override("font", _custom_font)
	title.add_theme_font_size_override("font_size", 20)
	title.modulate = Color(1.0, 0.4, 0.3)
	vbox.add_child(title)

	_map_list = ItemList.new()
	_map_list.size_flags_vertical = SIZE_EXPAND_FILL
	if _custom_font != null:
		_map_list.add_theme_font_override("font", _custom_font)
	_map_list.add_theme_font_size_override("font_size", 15)
	vbox.add_child(_map_list)

	var btn_box := HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_box)

	var start_btn := Button.new()
	start_btn.text = "进入战场 (Start)"
	if _custom_font != null:
		start_btn.add_theme_font_override("font", _custom_font)
	start_btn.add_theme_font_size_override("font_size", 16)
	start_btn.custom_minimum_size = Vector2(150, 40)
	start_btn.pressed.connect(_on_start_game_pressed)
	btn_box.add_child(start_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	if _custom_font != null:
		cancel_btn.add_theme_font_override("font", _custom_font)
	cancel_btn.add_theme_font_size_override("font_size", 16)
	cancel_btn.custom_minimum_size = Vector2(100, 40)
	cancel_btn.pressed.connect(func() -> void: _map_dialog.visible = false)
	btn_box.add_child(cancel_btn)


func _open_map_selector() -> void:
	_map_list.clear()
	var maps := MapDataScript.list_available_maps()
	if maps.is_empty():
		_map_list.add_item("默认空旷平地战场 (Default Flat Map)")
		_map_list.set_item_metadata(0, "")
	else:
		for i in range(maps.size()):
			var m: Dictionary = maps[i]
			var f_name: String = str(m.get("file_name", m.get("name", "map")))
			var display_name := "%s (%s)" % [m.get("name", "未命名"), f_name]
			_map_list.add_item(display_name)
			_map_list.set_item_metadata(i, m.get("path", ""))
	_map_list.select(0)
	_map_dialog.visible = true


func _on_start_game_pressed() -> void:
	var selected := _map_list.get_selected_items()
	var map_path := ""
	if not selected.is_empty():
		var idx := selected[0]
		map_path = str(_map_list.get_item_metadata(idx))

	var chase_script = load("res://scripts/player_client/chase_game.gd")
	if chase_script != null:
		chase_script.next_map_path = map_path

	_trigger_scene_transition(self as Control, func():
		SceneLoader.change_scene(get_tree(), CHASE_SCENE, "正在载入追缉对决战场与AI寻路网格...")
	)


func _build_workshop_ask_dialog() -> void:
	_workshop_ask_dialog = PanelContainer.new()
	_workshop_ask_dialog.set_anchors_preset(PRESET_CENTER)
	_workshop_ask_dialog.offset_left = -270
	_workshop_ask_dialog.offset_right = 270
	_workshop_ask_dialog.offset_top = -170
	_workshop_ask_dialog.offset_bottom = 170
	_workshop_ask_dialog.custom_minimum_size = Vector2(540, 340)
	_workshop_ask_dialog.visible = false

	var diag_style := StyleBoxFlat.new()
	diag_style.bg_color = Color(0.10, 0.12, 0.16, 0.98)
	diag_style.set_corner_radius_all(12)
	diag_style.set_content_margin_all(20)
	diag_style.set_border_width_all(2)
	diag_style.border_color = Color(0.2, 0.75, 1.0)
	_workshop_ask_dialog.add_theme_stylebox_override("panel", diag_style)
	add_child(_workshop_ask_dialog)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	_workshop_ask_dialog.add_child(vbox)

	var icon_tex := TextureRect.new()
	if ResourceLoader.exists("res://assets/UI_assets/cubes.svg"):
		icon_tex.texture = load("res://assets/UI_assets/cubes.svg")
	icon_tex.custom_minimum_size = Vector2(50, 50)
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.modulate = Color(0.25, 0.85, 1.0)
	vbox.add_child(icon_tex)

	var title := Label.new()
	title.text = "欢迎进入地图工坊 (Map Studio)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _custom_font != null:
		title.add_theme_font_override("font", _custom_font)
	title.add_theme_font_size_override("font_size", 22)
	title.modulate = Color(0.3, 0.9, 1.0)
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = "地图工坊支持多尺寸立体方块建造、人机物理寻路测试，以及玩家亲自示范并让 AI 学习的【特殊极限跳跃航迹录制】！\n\n是否开启【沉浸式在线互动新手教学】？"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _custom_font != null:
		desc.add_theme_font_override("font", _custom_font)
	desc.add_theme_font_size_override("font_size", 14)
	desc.modulate = Color(0.85, 0.88, 0.92, 0.9)
	vbox.add_child(desc)

	var btn_box := HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_box)

	var tut_btn := Button.new()
	tut_btn.text = "🚀 开启互动教学 (Tutorial)"
	if _custom_font != null:
		tut_btn.add_theme_font_override("font", _custom_font)
	tut_btn.add_theme_font_size_override("font_size", 16)
	tut_btn.custom_minimum_size = Vector2(190, 42)
	tut_btn.pressed.connect(func() -> void:
		_workshop_ask_dialog.visible = false
		MapEditorScript.tutorial_on_start = true
		_trigger_scene_transition(null, func():
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			SceneLoader.change_scene(get_tree(), MAP_EDITOR_SCENE, "正在载入地图工坊教学...")
		)
	)
	btn_box.add_child(tut_btn)

	var skip_btn := Button.new()
	skip_btn.text = "⏩ 跳过教学，自由创作"
	if _custom_font != null:
		skip_btn.add_theme_font_override("font", _custom_font)
	skip_btn.add_theme_font_size_override("font_size", 16)
	skip_btn.custom_minimum_size = Vector2(170, 42)
	skip_btn.pressed.connect(func() -> void:
		_workshop_ask_dialog.visible = false
		MapEditorScript.tutorial_on_start = false
		_trigger_scene_transition(null, func():
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			SceneLoader.change_scene(get_tree(), MAP_EDITOR_SCENE, "正在载入地图工坊创作空间...")
		)
	)
	btn_box.add_child(skip_btn)


func _build_trial_ask_dialog() -> void:
	_trial_ask_dialog = PanelContainer.new()
	_trial_ask_dialog.set_anchors_preset(PRESET_CENTER)
	_trial_ask_dialog.offset_left = -260
	_trial_ask_dialog.offset_right = 260
	_trial_ask_dialog.offset_top = -180
	_trial_ask_dialog.offset_bottom = 180
	_trial_ask_dialog.custom_minimum_size = Vector2(520, 360)
	_trial_ask_dialog.visible = false

	var diag_style := StyleBoxFlat.new()
	diag_style.bg_color = Color(0.10, 0.12, 0.16, 0.98)
	diag_style.set_corner_radius_all(12)
	diag_style.set_content_margin_all(20)
	diag_style.set_border_width_all(2)
	diag_style.border_color = Color(1.0, 0.75, 0.2)
	_trial_ask_dialog.add_theme_stylebox_override("panel", diag_style)
	add_child(_trial_ask_dialog)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	_trial_ask_dialog.add_child(vbox)

	var icon_tex := TextureRect.new()
	if ResourceLoader.exists("res://assets/UI_assets/run.svg"):
		icon_tex.texture = load("res://assets/UI_assets/run.svg")
	icon_tex.custom_minimum_size = Vector2(50, 50)
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.modulate = Color(1.0, 0.75, 0.2)
	vbox.add_child(icon_tex)

	var title := Label.new()
	title.text = "身法试玩沙盒 (Movement Sandbox)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _custom_font != null:
		title.add_theme_font_override("font", _custom_font)
	title.add_theme_font_size_override("font_size", 22)
	title.modulate = Color(1.0, 0.85, 0.3)
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = "在此沙盒中体验高精度身法动作系统：前后左右走动、Shift疾步奔跑、起跳腾空、攀登翻越 2 格高台、战术翻滚及视界切换！\n\n是否开启【身法基础互动教学】？"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _custom_font != null:
		desc.add_theme_font_override("font", _custom_font)
	desc.add_theme_font_size_override("font_size", 14)
	desc.modulate = Color(0.85, 0.88, 0.92, 0.9)
	vbox.add_child(desc)

	var btn_box := HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_box)

	var tut_btn := Button.new()
	tut_btn.text = "🚀 开启身法教学 (Tutorial)"
	if _custom_font != null:
		tut_btn.add_theme_font_override("font", _custom_font)
	tut_btn.add_theme_font_size_override("font_size", 16)
	tut_btn.custom_minimum_size = Vector2(190, 42)
	tut_btn.pressed.connect(func() -> void:
		_trial_ask_dialog.visible = false
		PlaygroundScript.start_with_tutorial = true
		PlaygroundScript.show_debug_hud = false
		PlaygroundScript.return_scene = "res://scenes/player_client/title_screen.tscn"
		_trigger_scene_transition(null, func():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			SceneLoader.change_scene(get_tree(), PLAYGROUND_SCENE, "正在载入身法沙盒教学...")
		)
	)
	btn_box.add_child(tut_btn)

	var skip_btn := Button.new()
	skip_btn.text = "⏩ 跳过教学，自由试玩"
	if _custom_font != null:
		skip_btn.add_theme_font_override("font", _custom_font)
	skip_btn.add_theme_font_size_override("font_size", 16)
	skip_btn.custom_minimum_size = Vector2(170, 42)
	skip_btn.pressed.connect(func() -> void:
		_trial_ask_dialog.visible = false
		PlaygroundScript.start_with_tutorial = false
		PlaygroundScript.show_debug_hud = false
		PlaygroundScript.return_scene = "res://scenes/player_client/title_screen.tscn"
		_trigger_scene_transition(null, func():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			SceneLoader.change_scene(get_tree(), PLAYGROUND_SCENE, "正在载入身法自由试玩沙盒...")
		)
	)
	btn_box.add_child(skip_btn)


func _build_3d_background() -> void:
	var vp_container := SubViewportContainer.new()
	vp_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp_container.stretch = true
	vp_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vp_container)

	_bg_viewport = SubViewport.new()
	_bg_viewport.own_world_3d = true
	_bg_viewport.handle_input_locally = false
	_bg_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp_container.add_child(_bg_viewport)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.08, 0.11, 0.18)
	sky_mat.sky_horizon_color = Color(0.28, 0.18, 0.14)
	sky_mat.ground_bottom_color = Color(0.04, 0.05, 0.07)
	sky_mat.ground_horizon_color = Color(0.12, 0.14, 0.18)

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_intensity = 1.0
	env.glow_bloom = 0.25
	env.fog_enabled = true
	env.fog_light_color = Color(0.10, 0.12, 0.16)
	env.fog_density = 0.015

	var env_node := WorldEnvironment.new()
	env_node.environment = env
	_bg_viewport.add_child(env_node)

	var key_light := DirectionalLight3D.new()
	key_light.light_color = Color(1.0, 0.88, 0.75)
	key_light.light_energy = 1.4
	key_light.shadow_enabled = true
	key_light.transform.basis = Basis.from_euler(Vector3(deg_to_rad(-28.0), deg_to_rad(145.0), 0.0))
	_bg_viewport.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.light_color = Color(0.35, 0.65, 0.95)
	fill_light.light_energy = 0.5
	fill_light.shadow_enabled = false
	fill_light.transform.basis = Basis.from_euler(Vector3(deg_to_rad(-20.0), deg_to_rad(-45.0), 0.0))
	_bg_viewport.add_child(fill_light)

	_bg_omni = OmniLight3D.new()
	_bg_omni.light_color = Color(1.0, 0.55, 0.25)
	_bg_omni.light_energy = 1.4
	_bg_omni.omni_range = 6.0
	_bg_omni.position = Vector3(0.4, 0.4, 0.2)
	_bg_viewport.add_child(_bg_omni)

	var dais := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.4
	cyl.bottom_radius = 2.6
	cyl.height = 0.3
	var dais_mat := StandardMaterial3D.new()
	dais_mat.albedo_color = Color(0.12, 0.14, 0.18)
	dais_mat.roughness = 0.7
	dais_mat.metallic = 0.3
	dais.mesh = cyl
	dais.material_override = dais_mat
	dais.position = Vector3(0.3, -0.15, 0.0)
	_bg_viewport.add_child(dais)

	var ring_mesh := ImmediateMesh.new()
	ring_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var segs := 36
	for i in range(segs + 1):
		var ang := TAU * float(i) / float(segs)
		var vx := cos(ang) * 2.38
		var vz := sin(ang) * 2.38
		ring_mesh.surface_set_color(Color(1.0, 0.5, 0.15, 0.85))
		ring_mesh.surface_add_vertex(Vector3(vx, 0.005, vz))
	ring_mesh.surface_end()

	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.vertex_color_use_as_albedo = true
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var ring_inst := MeshInstance3D.new()
	ring_inst.mesh = ring_mesh
	ring_inst.material_override = ring_mat
	dais.add_child(ring_inst)

	var particles := CPUParticles3D.new()
	particles.amount = 50
	particles.lifetime = 4.0
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(2.5, 0.1, 2.5)
	particles.position = Vector3(0.3, 0.05, 0.0)
	particles.direction = Vector3(0.0, 1.0, 0.0)
	particles.spread = 30.0
	particles.gravity = Vector3(0.0, 0.25, 0.0)
	particles.initial_velocity_min = 0.5
	particles.initial_velocity_max = 1.4
	particles.scale_amount_min = 0.04
	particles.scale_amount_max = 0.10
	particles.color = Color(1.0, 0.60, 0.20, 0.95)

	var p_mesh := QuadMesh.new()
	p_mesh.size = Vector2(0.06, 0.06)
	var p_mat := StandardMaterial3D.new()
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p_mat.albedo_color = Color(1.0, 0.65, 0.25, 0.95)
	p_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particles.mesh = p_mesh
	particles.material_override = p_mat
	_bg_viewport.add_child(particles)

	var char_scenes := [
		"res://assets/characters/hero/hero.tscn",
		"res://assets/characters/hero_1/hero_1.tscn",
		"res://assets/characters/hero_2/hero_2.tscn",
		"res://assets/characters/hero_3/hero_3.tscn",
	]
	var loaded_scene: PackedScene = null
	for p in char_scenes:
		if ResourceLoader.exists(p):
			loaded_scene = load(p) as PackedScene
			if loaded_scene != null:
				break

	if loaded_scene != null:
		var char_inst := loaded_scene.instantiate() as Character
		if char_inst != null:
			_bg_character = char_inst
			_bg_character.position = Vector3(0.3, 0.0, 0.0)
			_bg_character.rotation.y = -0.45
			_bg_viewport.add_child(_bg_character)
			if _bg_character.is_node_ready():
				_play_bg_anim(_bg_character)
			else:
				_bg_character.ready.connect(func() -> void: _play_bg_anim(_bg_character))

	_bg_camera = Camera3D.new()
	_bg_camera.fov = 48.0
	_bg_camera.near = 0.05
	_bg_camera.current = true
	_bg_viewport.add_child(_bg_camera)
	_bg_camera.look_at_from_position(Vector3(0.0, 1.25, 3.2), Vector3(0.2, 0.95, 0.0))


func _play_bg_anim(character: Character) -> void:
	if character == null:
		return
	if character.player == null:
		character.player = AnimPipelineScript.first_of_class(character, "AnimationPlayer") as AnimationPlayer
		character.skeleton = AnimPipelineScript.first_of_class(character, "Skeleton3D") as Skeleton3D
		character.attach_libraries()

	var candidate_anims := [
		"idle_fold_arms",
		"sword_idle",
		"dance",
		"idle",
	]
	for anim_name in candidate_anims:
		if character.has_clip(anim_name):
			character.play(anim_name)
			var resolved_name := character.resolve(anim_name)
			if character.player != null and character.player.has_animation(resolved_name):
				character.player.get_animation(resolved_name).loop_mode = Animation.LOOP_LINEAR
				break


func _build_left_profile_card(parent_col: VBoxContainer) -> void:
	_profile_card = Button.new()
	_profile_card.custom_minimum_size = Vector2(380, 68)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.07, 0.09, 0.13, 0.92)
	card_style.set_corner_radius_all(14)
	card_style.set_border_width_all(2)
	card_style.border_color = Color(0.25, 0.85, 1.0, 0.6)
	card_style.shadow_color = Color(0.25, 0.85, 1.0, 0.25)
	card_style.shadow_size = 8
	card_style.content_margin_left = 12
	card_style.content_margin_right = 16
	_profile_card.add_theme_stylebox_override("normal", card_style)
	_profile_card.add_theme_stylebox_override("hover", card_style)
	_profile_card.pressed.connect(_open_profile_dialog)
	parent_col.add_child(_profile_card)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(PRESET_FULL_RECT)
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	hbox.add_theme_constant_override("separation", 14)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_profile_card.add_child(hbox)

	_profile_avatar_holder = Control.new()
	_profile_avatar_holder.custom_minimum_size = Vector2(50, 50)
	_profile_avatar_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_profile_avatar_holder)

	var name_box := VBoxContainer.new()
	name_box.alignment = BoxContainer.ALIGNMENT_CENTER
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.add_theme_constant_override("separation", 2)
	name_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(name_box)

	_profile_name_lbl = Label.new()
	if _custom_font != null:
		_profile_name_lbl.add_theme_font_override("font", _custom_font)
	_profile_name_lbl.add_theme_font_size_override("font_size", 18)
	_profile_name_lbl.modulate = Color(1.0, 0.88, 0.35)
	name_box.add_child(_profile_name_lbl)

	var sub_hint := Label.new()
	sub_hint.text = "点击更换头像 / 修改昵称"
	sub_hint.add_theme_font_size_override("font_size", 11)
	sub_hint.modulate = Color(0.3, 0.85, 1.0, 0.8)
	name_box.add_child(sub_hint)

	var edit_icon := TextureRect.new()
	if ResourceLoader.exists("res://assets/UI_assets/gear-hammer.svg"):
		edit_icon.texture = load("res://assets/UI_assets/gear-hammer.svg")
	edit_icon.custom_minimum_size = Vector2(22, 22)
	edit_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	edit_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	edit_icon.modulate = Color(0.25, 0.85, 1.0, 0.7)
	edit_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(edit_icon)

	_update_left_profile_card()
	_build_profile_editor_dialog()


func _build_keybind_entry_button(parent_col: VBoxContainer) -> void:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(380, 44)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.15, 0.90)
	style.set_corner_radius_all(10)
	style.set_border_width_all(1)
	style.border_color = Color(0.35, 0.55, 0.85, 0.6)
	style.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.text = "⌨️ 战斗与身法按键设置 (Controls Remap)"
	if _custom_font != null:
		btn.add_theme_font_override("font", _custom_font)
	btn.add_theme_font_size_override("font_size", 14)
	btn.modulate = Color(0.85, 0.90, 1.0)
	btn.pressed.connect(_open_keybind_dialog)
	parent_col.add_child(btn)


func _build_keybind_dialog() -> void:
	var dlg_canvas := CanvasLayer.new()
	dlg_canvas.layer = 25
	add_child(dlg_canvas)

	_keybind_dialog = KeybindRemapPanelScript.new()
	_keybind_dialog.set_anchors_preset(PRESET_CENTER)
	_keybind_dialog.offset_left = -350
	_keybind_dialog.offset_right = 350
	_keybind_dialog.offset_top = -290
	_keybind_dialog.offset_bottom = 290
	_keybind_dialog.visible = false
	_keybind_dialog.closed.connect(func(): _keybind_dialog.visible = false)
	dlg_canvas.add_child(_keybind_dialog)


func _open_keybind_dialog() -> void:
	if _keybind_dialog != null:
		_keybind_dialog.visible = true


func _pm():
	if is_inside_tree() and has_node("/root/ProfileManager"):
		return get_node("/root/ProfileManager")
	return null


func _update_left_profile_card() -> void:
	var pm = _pm()
	if pm == null or _profile_name_lbl == null:
		return
	_profile_name_lbl.text = pm.player_name
	for child in _profile_avatar_holder.get_children():
		child.queue_free()
	var av: Control = pm.create_avatar_circle(48.0, pm.avatar_type, pm.avatar_key, Color(0.25, 0.85, 1.0))
	_profile_avatar_holder.add_child(av)


var _selected_av_type := "builtin"
var _selected_av_key := "avatar_01_01.png"
var _profile_preview_holder: Control
var _profile_name_edit: LineEdit
var _profile_item_btns: Dictionary = {}


func _open_profile_dialog() -> void:
	var pm = _pm()
	if pm != null:
		_selected_av_type = pm.avatar_type
		_selected_av_key = pm.avatar_key
		if _profile_name_edit != null:
			_profile_name_edit.text = pm.player_name
	_refresh_dialog_preview()
	_refresh_grid_selection()
	_profile_dialog.visible = true


func _refresh_dialog_preview() -> void:
	if _profile_preview_holder == null:
		return
	for c in _profile_preview_holder.get_children():
		c.queue_free()
	var pm = _pm()
	if pm != null:
		var pv: Control = pm.create_avatar_circle(56.0, _selected_av_type, _selected_av_key, Color(1.0, 0.85, 0.2))
		_profile_preview_holder.add_child(pv)


func _refresh_grid_selection() -> void:
	for key in _profile_item_btns:
		var btn: Button = _profile_item_btns[key]
		if is_instance_valid(btn):
			if _selected_av_type == "builtin" and _selected_av_key == key:
				btn.modulate = Color(1.0, 1.0, 1.0)
			else:
				btn.modulate = Color(0.4, 0.4, 0.4)


func _on_avatar_item_clicked(av_file: String) -> void:
	_selected_av_type = "builtin"
	_selected_av_key = av_file
	_refresh_dialog_preview()
	_refresh_grid_selection()


func _build_profile_editor_dialog() -> void:
	var dlg_canvas := CanvasLayer.new()
	dlg_canvas.layer = 20
	add_child(dlg_canvas)

	_profile_dialog = PanelContainer.new()
	_profile_dialog.set_anchors_preset(PRESET_CENTER)
	_profile_dialog.offset_left = -270
	_profile_dialog.offset_right = 270
	_profile_dialog.offset_top = -250
	_profile_dialog.offset_bottom = 250
	_profile_dialog.custom_minimum_size = Vector2(540, 500)
	_profile_dialog.visible = false

	var diag_style := StyleBoxFlat.new()
	diag_style.bg_color = Color(0.06, 0.08, 0.11, 0.98)
	diag_style.set_corner_radius_all(16)
	diag_style.set_border_width_all(2)
	diag_style.border_color = Color(0.25, 0.85, 1.0, 0.85)
	diag_style.shadow_color = Color(0.25, 0.85, 1.0, 0.35)
	diag_style.shadow_size = 20
	diag_style.content_margin_left = 24
	diag_style.content_margin_top = 20
	diag_style.content_margin_right = 24
	diag_style.content_margin_bottom = 20
	_profile_dialog.add_theme_stylebox_override("panel", diag_style)
	dlg_canvas.add_child(_profile_dialog)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	_profile_dialog.add_child(vbox)

	var t_lbl := Label.new()
	t_lbl.text = "选手档案与头像设置 (PLAYER PROFILE)"
	t_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _glitch_font != null:
		t_lbl.add_theme_font_override("font", _glitch_font)
	t_lbl.add_theme_font_size_override("font_size", 18)
	t_lbl.modulate = Color(0.3, 0.85, 1.0)
	vbox.add_child(t_lbl)

	# Name Edit
	var name_box := HBoxContainer.new()
	name_box.add_theme_constant_override("separation", 12)
	vbox.add_child(name_box)

	var n_lbl := Label.new()
	n_lbl.text = "选手昵称:"
	if _custom_font != null:
		n_lbl.add_theme_font_override("font", _custom_font)
	n_lbl.add_theme_font_size_override("font_size", 16)
	name_box.add_child(n_lbl)

	var pm = _pm()
	_profile_name_edit = LineEdit.new()
	_profile_name_edit.text = pm.player_name if pm != null else "灰烬行者"
	_profile_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.add_child(_profile_name_edit)

	# Current Avatar Preview & Custom File Import Row
	var custom_row := HBoxContainer.new()
	custom_row.alignment = BoxContainer.ALIGNMENT_CENTER
	custom_row.add_theme_constant_override("separation", 16)
	vbox.add_child(custom_row)

	_profile_preview_holder = Control.new()
	_profile_preview_holder.custom_minimum_size = Vector2(56, 56)
	custom_row.add_child(_profile_preview_holder)

	var file_dialog := FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; 支持的图片格式 (PNG/JPG/WEBP)"])
	dlg_canvas.add_child(file_dialog)

	var btn_import := Button.new()
	btn_import.text = "📁 从电脑导入自定义头像 (Import Image)"
	btn_import.custom_minimum_size = Vector2(250, 38)
	btn_import.pressed.connect(func(): file_dialog.popup_centered(Vector2i(700, 480)))
	custom_row.add_child(btn_import)

	file_dialog.file_selected.connect(func(path: String):
		var p_mgr = _pm()
		if p_mgr != null and p_mgr.import_custom_avatar_from_path(path):
			_selected_av_type = "custom"
			_selected_av_key = "custom"
			_refresh_dialog_preview()
			_refresh_grid_selection()
	)

	# Builtin Library Title
	var lib_title := Label.new()
	lib_title.text = "或从精选头像候选库中点选:"
	if _custom_font != null:
		lib_title.add_theme_font_override("font", _custom_font)
	lib_title.add_theme_font_size_override("font_size", 14)
	lib_title.modulate = Color(0.8, 0.85, 0.95)
	vbox.add_child(lib_title)

	# Scrollable Grid of Avatars
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 180)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)

	_profile_item_btns.clear()
	var av_list: Array = pm.available_builtin_avatars if pm != null else []
	for av_file in av_list:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(52, 52)
		var av_icon: Control = pm.create_avatar_circle(48.0, "builtin", av_file)
		btn.add_child(av_icon)
		var b_style := StyleBoxFlat.new()
		b_style.bg_color = Color.TRANSPARENT
		b_style.set_corner_radius_all(26)
		btn.add_theme_stylebox_override("normal", b_style)
		btn.pressed.connect(_on_avatar_item_clicked.bind(av_file))
		_profile_item_btns[av_file] = btn
		grid.add_child(btn)

	# Action Buttons
	var btn_box := HBoxContainer.new()
	btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 24)
	vbox.add_child(btn_box)

	var save_btn := Button.new()
	save_btn.text = "保存档案 (SAVE)"
	save_btn.custom_minimum_size = Vector2(140, 38)
	save_btn.pressed.connect(func():
		var p_mgr = _pm()
		if p_mgr != null:
			p_mgr.save_profile(_profile_name_edit.text, _selected_av_type, _selected_av_key)
		_update_left_profile_card()
		_profile_dialog.visible = false
	)
	btn_box.add_child(save_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "取消 (CANCEL)"
	cancel_btn.custom_minimum_size = Vector2(110, 38)
	cancel_btn.pressed.connect(func(): _profile_dialog.visible = false)
	btn_box.add_child(cancel_btn)
