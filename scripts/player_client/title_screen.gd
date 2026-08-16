extends Control
## User-facing game client title screen.
## Clean, immersive game-feel UI with LongCang font, vector icons, and ESC navigation.

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const MapDataScript = preload("res://scripts/map_data.gd")

const CHASE_SCENE := "res://scenes/player_client/chase_game.tscn"
const MAP_EDITOR_SCENE := "res://scenes/map_editor.tscn"
const MAIN_GATEWAY_SCENE := "res://scenes/main_menu.tscn"
const FONT_PATH := "res://assets/Fonts/Long_Cang/LongCang-Regular.ttf"

var _custom_font: Font = null
var _guide_dialog: PanelContainer
var _map_dialog: PanelContainer
var _map_list: ItemList


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioManagerScript.init_pool(self)
	if ResourceLoader.exists(FONT_PATH):
		_custom_font = load(FONT_PATH) as Font
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if _guide_dialog != null and _guide_dialog.visible:
				_guide_dialog.visible = false
				get_viewport().set_input_as_handled()
				return
			if _map_dialog != null and _map_dialog.visible:
				_map_dialog.visible = false
				get_viewport().set_input_as_handled()
				return
			# Return to Mode Selector Gateway
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_tree().change_scene_to_file(MAIN_GATEWAY_SCENE)
			get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.07, 0.09, 1.0)
	add_child(bg)

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
	if ResourceLoader.exists("res://assets/UI_assets/claw-slashes.svg"):
		icon_tex.texture = load("res://assets/UI_assets/claw-slashes.svg")
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
	right_col.add_theme_constant_override("separation", 14)
	main_box.add_child(right_col)

	var btn_play := _create_menu_button("开始追缉逃生 (Pursuit Challenge)", "res://assets/UI_assets/run.svg", Color(0.9, 0.25, 0.2))
	btn_play.pressed.connect(_open_map_selector)
	right_col.add_child(btn_play)

	var btn_editor := _create_menu_button("地图工坊 (Map Studio)", "res://assets/UI_assets/cubes.svg", Color(0.2, 0.65, 0.95))
	btn_editor.pressed.connect(func() -> void:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file(MAP_EDITOR_SCENE)
	)
	right_col.add_child(btn_editor)

	var btn_guide := _create_menu_button("逃生操作指南 (How to Play)", "res://assets/UI_assets/digital-trace.svg", Color(0.3, 0.85, 0.55))
	btn_guide.pressed.connect(_open_guide_dialog)
	right_col.add_child(btn_guide)

	var btn_gateway := _create_menu_button("返回主选择门户 (Back to Gateway)", "res://assets/UI_assets/gear-hammer.svg", Color(0.5, 0.55, 0.65))
	btn_gateway.pressed.connect(func() -> void:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file(MAIN_GATEWAY_SCENE)
	)
	right_col.add_child(btn_gateway)

	_build_guide_dialog()
	_build_map_dialog()


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
	rule_lbl.text = "【对决规则】\n1. 开局拥有 15 秒逃生时间，追缉者原地待命。\n2. 倒计时结束后追缉者全速出动，接近被追方 1 格以内判定追缉者获胜！\n3. 利用复杂高低差地形与跳跃攀爬拉开距离，争取更长生存时间！"
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

	var chase_scene := load(CHASE_SCENE) as PackedScene
	if chase_scene == null:
		return
	var inst := chase_scene.instantiate()
	inst.set("preloaded_map_path", map_path)
	get_tree().root.add_child(inst)
	get_tree().current_scene.queue_free()
	get_tree().current_scene = inst


func _open_guide_dialog() -> void:
	_guide_dialog.visible = true
