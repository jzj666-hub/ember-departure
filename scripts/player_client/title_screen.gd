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

var _custom_font: Font = null
var _guide_dialog: PanelContainer
var _map_dialog: PanelContainer
var _workshop_ask_dialog: PanelContainer
var _trial_ask_dialog: PanelContainer
var _map_list: ItemList

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
		_bg_omni.light_energy = 1.7 + sin(t) * 0.35


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			if _trial_ask_dialog != null and _trial_ask_dialog.visible:
				_trial_ask_dialog.visible = false
				return
			if _workshop_ask_dialog != null and _workshop_ask_dialog.visible:
				_workshop_ask_dialog.visible = false
				return
			if _guide_dialog != null and _guide_dialog.visible:
				_guide_dialog.visible = false
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
	icon_tex.modulate = Color(1.0, 0.28, 0.22, 0.95)
	left_col.add_child(icon_tex)

	var title_lbl := Label.new()
	title_lbl.text = "灰烬 · 极限追缉"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _custom_font != null:
		title_lbl.add_theme_font_override("font", _custom_font)
	title_lbl.add_theme_font_size_override("font_size", 44)
	title_lbl.modulate = Color(1.0, 0.88, 0.35)
	left_col.add_child(title_lbl)

	var subtitle_lbl := Label.new()
	subtitle_lbl.text = "EMBER DEPARTURE · PURSUIT"
	subtitle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _custom_font != null:
		subtitle_lbl.add_theme_font_override("font", _custom_font)
	subtitle_lbl.add_theme_font_size_override("font_size", 20)
	subtitle_lbl.modulate = Color(0.9, 0.92, 0.95, 0.85)
	left_col.add_child(subtitle_lbl)

	var tag_lbl := Label.new()
	tag_lbl.text = "1v1 智能动力学逃生与追捕对决 (按 ESC 返回模式选择)"
	tag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _custom_font != null:
		tag_lbl.add_theme_font_override("font", _custom_font)
	tag_lbl.add_theme_font_size_override("font_size", 14)
	tag_lbl.modulate = Color(0.55, 0.60, 0.70, 0.75)
	left_col.add_child(tag_lbl)

	# Right Column: Action Buttons
	var right_col := VBoxContainer.new()
	right_col.alignment = BoxContainer.ALIGNMENT_CENTER
	right_col.custom_minimum_size = Vector2(380, 0)
	right_col.add_theme_constant_override("separation", 12)
	main_box.add_child(right_col)

	var btn_play := _create_menu_button("开始追缉逃生 (Pursuit Challenge)", "res://assets/UI_assets/claw-slashes.svg", Color(0.9, 0.25, 0.2))
	btn_play.pressed.connect(_open_map_selector)
	right_col.add_child(btn_play)

	var btn_trial := _create_menu_button("身法试玩沙盒 (Movement Sandbox)", "res://assets/UI_assets/run.svg", Color(0.95, 0.65, 0.15))
	btn_trial.pressed.connect(func() -> void:
		_trial_ask_dialog.visible = true
	)
	right_col.add_child(btn_trial)

	var btn_weapon := _create_menu_button("兵器试炼与连招 (Weapon Armory)", "res://assets/UI_assets/winged-sword.svg", Color(0.95, 0.45, 0.2))
	btn_weapon.pressed.connect(func() -> void:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		SceneLoader.change_scene(get_tree(), WEAPON_TRIAL_SCENE, "正在装备神兵与加载试炼场...")
	)
	right_col.add_child(btn_weapon)

	var btn_editor := _create_menu_button("地图工坊 (Map Studio)", "res://assets/UI_assets/cubes.svg", Color(0.2, 0.65, 0.95))
	btn_editor.pressed.connect(func() -> void:
		_workshop_ask_dialog.visible = true
	)
	right_col.add_child(btn_editor)

	var btn_guide := _create_menu_button("逃生操作指南 (How to Play)", "res://assets/UI_assets/digital-trace.svg", Color(0.3, 0.85, 0.55))
	btn_guide.pressed.connect(_open_guide_dialog)
	right_col.add_child(btn_guide)

	var btn_gateway := _create_menu_button("返回主选择门户 (Back to Gateway)", "res://assets/UI_assets/gear-hammer.svg", Color(0.5, 0.55, 0.65))
	btn_gateway.pressed.connect(func() -> void:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		SceneLoader.change_scene(get_tree(), MAIN_GATEWAY_SCENE, "返回主模式选择门户...")
	)
	right_col.add_child(btn_gateway)

	_build_guide_dialog()
	_build_map_dialog()
	_build_workshop_ask_dialog()
	_build_trial_ask_dialog()


func _create_menu_button(text: String, icon_path: String, accent_color: Color) -> Button:
	var btn := Button.new()
	btn.text = "   " + text
	btn.custom_minimum_size = Vector2(360, 52)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	if _custom_font != null:
		btn.add_theme_font_override("font", _custom_font)
	btn.add_theme_font_size_override("font_size", 16)

	if ResourceLoader.exists(icon_path):
		var tex := load(icon_path) as Texture2D
		if tex != null:
			btn.icon = tex
			btn.expand_icon = true

	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(0.12, 0.14, 0.18, 0.9)
	style_normal.set_corner_radius_all(8)
	style_normal.set_border_width_all(1)
	style_normal.border_color = Color(0.25, 0.30, 0.38)
	style_normal.set_content_margin_all(10)
	btn.add_theme_stylebox_override("normal", style_normal)

	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = Color(0.18, 0.22, 0.28, 0.95)
	style_hover.set_corner_radius_all(8)
	style_hover.set_border_width_all(2)
	style_hover.border_color = accent_color
	style_hover.set_content_margin_all(10)
	btn.add_theme_stylebox_override("hover", style_hover)

	var style_pressed := StyleBoxFlat.new()
	style_pressed.bg_color = Color(0.10, 0.12, 0.15, 0.98)
	style_pressed.set_corner_radius_all(8)
	style_pressed.set_border_width_all(2)
	style_pressed.border_color = accent_color
	style_pressed.set_content_margin_all(10)
	btn.add_theme_stylebox_override("pressed", style_pressed)

	return btn


func _build_guide_dialog() -> void:
	_guide_dialog = PanelContainer.new()
	_guide_dialog.set_anchors_preset(PRESET_CENTER)
	_guide_dialog.offset_left = -340
	_guide_dialog.offset_right = 340
	_guide_dialog.offset_top = -240
	_guide_dialog.offset_bottom = 240
	_guide_dialog.custom_minimum_size = Vector2(680, 480)
	_guide_dialog.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.16, 0.98)
	style.set_corner_radius_all(12)
	style.set_border_width_all(2)
	style.border_color = Color(0.3, 0.85, 0.55)
	style.set_content_margin_all(20)
	_guide_dialog.add_theme_stylebox_override("panel", style)
	add_child(_guide_dialog)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	_guide_dialog.add_child(vbox)

	var title := Label.new()
	title.text = "逃生操作与对决规则指南"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _custom_font != null:
		title.add_theme_font_override("font", _custom_font)
	title.add_theme_font_size_override("font_size", 22)
	title.modulate = Color(0.3, 0.9, 0.6)
	vbox.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(grid)

	_add_guide_item(grid, "res://assets/buttons_pattern/W.png", "W A S D 键盘移动控制")
	_add_guide_item(grid, "res://assets/buttons_pattern/SHIFT.png", "Shift 按住全速奔跑逃生")
	_add_guide_item(grid, "res://assets/buttons_pattern/SPACE.png", "Space 空格跳跃 / 攀爬高台")
	_add_guide_item(grid, "res://assets/buttons_pattern/R.png", "R 键 录制直线特殊跳跃轨迹")
	_add_guide_item(grid, "res://assets/buttons_pattern/X.png", "连按两下 X 切换 AI 路线与目标柱显示")
	_add_guide_item(grid, "res://assets/buttons_pattern/ESC.png", "ESC 暂停 / 返回主菜单")

	var rule_box := PanelContainer.new()
	var r_style := StyleBoxFlat.new()
	r_style.bg_color = Color(0.15, 0.17, 0.22, 0.8)
	r_style.set_corner_radius_all(8)
	r_style.set_content_margin_all(10)
	rule_box.add_theme_stylebox_override("panel", r_style)
	vbox.add_child(rule_box)

	var rule_lbl := Label.new()
	rule_lbl.text = "【对决规则】\n1. 开局拥有 15 秒逃生时间，追缉者原地待命。\n2. 倒计时结束后追缉者全速出动，追缉限时 2 分钟！\n3. 追缉者接近至 1.5 米以内判定捕获；坚持 2 分钟未被捕获即可逃生成功！"
	if _custom_font != null:
		rule_lbl.add_theme_font_override("font", _custom_font)
	rule_lbl.add_theme_font_size_override("font_size", 14)
	rule_lbl.modulate = Color(0.85, 0.88, 0.92)
	rule_box.add_child(rule_lbl)

	var close_btn := Button.new()
	close_btn.text = "我知道了 (关闭)"
	if _custom_font != null:
		close_btn.add_theme_font_override("font", _custom_font)
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.custom_minimum_size = Vector2(160, 38)
	close_btn.size_flags_horizontal = SIZE_SHRINK_CENTER
	close_btn.pressed.connect(func() -> void: _guide_dialog.visible = false)
	vbox.add_child(close_btn)


func _add_guide_item(grid: GridContainer, key_png: String, desc: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var tex := TextureRect.new()
	if ResourceLoader.exists(key_png):
		tex.texture = load(key_png)
	tex.custom_minimum_size = Vector2(32, 32)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(tex)

	var lbl := Label.new()
	lbl.text = desc
	if _custom_font != null:
		lbl.add_theme_font_override("font", _custom_font)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)

	grid.add_child(row)


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
	SceneLoader.change_scene(get_tree(), CHASE_SCENE, "正在载入追缉对决战场与AI寻路网格...")


func _open_guide_dialog() -> void:
	_guide_dialog.visible = true


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
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		SceneLoader.change_scene(get_tree(), MAP_EDITOR_SCENE, "正在载入地图工坊教学...")
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
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		SceneLoader.change_scene(get_tree(), MAP_EDITOR_SCENE, "正在载入地图工坊创作空间...")
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
	desc.text = "在此沙盒中体验高精度物理动力学角色引擎：前后左右走动、Shift疾步奔跑、起跳腾空、攀登翻越 2 格高台、战术翻滚及视界切换！\n\n是否开启【身法基础互动教学】？"
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
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		SceneLoader.change_scene(get_tree(), PLAYGROUND_SCENE, "正在载入身法沙盒教学...")
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
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		SceneLoader.change_scene(get_tree(), PLAYGROUND_SCENE, "正在载入身法自由试玩沙盒...")
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
	env.ambient_light_energy = 0.65
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
	key_light.light_color = Color(1.0, 0.78, 0.48)
	key_light.light_energy = 2.4
	key_light.shadow_enabled = true
	key_light.transform.basis = Basis.from_euler(Vector3(deg_to_rad(-28.0), deg_to_rad(145.0), 0.0))
	_bg_viewport.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.light_color = Color(0.35, 0.65, 0.95)
	fill_light.light_energy = 0.7
	fill_light.shadow_enabled = false
	fill_light.transform.basis = Basis.from_euler(Vector3(deg_to_rad(-20.0), deg_to_rad(-45.0), 0.0))
	_bg_viewport.add_child(fill_light)

	_bg_omni = OmniLight3D.new()
	_bg_omni.light_color = Color(1.0, 0.45, 0.15)
	_bg_omni.light_energy = 1.8
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
				var anim := character.player.get_animation(resolved_name)
				if anim != null:
					anim.loop_mode = Animation.LOOP_LINEAR
			return
