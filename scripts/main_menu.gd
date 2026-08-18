extends Control
## Project Mode Selection Gateway (Player Client vs Developer Sandbox).

const FONT_PATH := "res://assets/Fonts/Long_Cang/LongCang-Regular.ttf"
const PLAYER_CLIENT_SCENE := "res://scenes/player_client/title_screen.tscn"

const DEV_ENTRIES := [
	{
		"title": "动作调试 / Animation Debug",
		"blurb": "所有角色并排，同步播同一个动作。检查重定向、身高、骨骼绑定。",
		"scene": "res://scenes/anim_debug.tscn",
	},
	{
		"title": "第三人称试玩 / Third-person Playground",
		"blurb": "操控一个角色走路、侧移、跑步、蹲行。鼠标转向，相机锁在背后。",
		"scene": "res://scenes/playground.tscn",
	},
	{
		"title": "角色手持武器测试 / Handheld Weapon Test",
		"blurb": "测试手持刀具挂载与微调。点击列表装备，滑动条调整握持Transform，LMB进行挥砍。",
		"scene": "res://scenes/weapon_test.tscn",
	},
	{
		"title": "人机操控与寻路测试 / NPC Control & Pathfinding Test",
		"blurb": "第一人称自由飞行搭建：鼠标转视角，准星高亮目标格，左键放置右键拆除，中键指定人机目的地。按 E 寄身操控。寻路按角色真实的跳跃/攀爬能力规划。",
		"scene": "res://scenes/npc_test.tscn",
	},
	{
		"title": "地图编辑器 / Map Editor",
		"blurb": "支持多尺寸方块搭建与材质切换、地图新建/存档/加载，支持玩家录制空中直线特殊跳跃轨迹并与NPC寻路无缝集成。",
		"scene": "res://scenes/map_editor.tscn",
	},
	{
		"title": "追缉模式底层调试 / Raw Pursuit Debug",
		"blurb": "1v1 追缉逃生底层调试场景（包含调试红柱与直接参数监视）。",
		"scene": "res://scenes/chase_mode.tscn",
	},
]

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const VIDEO_OGV_PATH := "res://assets/UI_assets/主界面动画.ogv"

var _custom_font: Font = null
var _mode_select_box: VBoxContainer
var _dev_box: VBoxContainer
var _video_player: VideoStreamPlayer


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioManagerScript.init_pool(self)
	AudioManagerScript.play_bgm("res://assets/voice/background/song_of_the_sea.ogg", -6.0)
	if ResourceLoader.exists(FONT_PATH):
		_custom_font = load(FONT_PATH) as Font
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if _dev_box != null and _dev_box.visible:
				_show_mode_select()
				get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.06, 0.07, 0.09)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	if ResourceLoader.exists(VIDEO_OGV_PATH):
		var v_stream = load(VIDEO_OGV_PATH)
		if v_stream != null:
			_video_player = VideoStreamPlayer.new()
			_video_player.stream = v_stream
			_video_player.set_anchors_preset(Control.PRESET_FULL_RECT)
			_video_player.expand = true
			_video_player.loop = true
			_video_player.autoplay = true
			_video_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_video_player.volume_db = -80.0
			add_child(_video_player)
			_video_player.play()

	var overlay := ColorRect.new()
	overlay.color = Color(0.05, 0.07, 0.10, 0.58)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	# --- Mode Select Panel (Homepage) ---
	_mode_select_box = VBoxContainer.new()
	_mode_select_box.add_theme_constant_override("separation", 18)
	_mode_select_box.custom_minimum_size = Vector2(500, 0)
	centre.add_child(_mode_select_box)

	var title := Label.new()
	title.text = "灰烬 · 启程"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _custom_font != null:
		title.add_theme_font_override("font", _custom_font)
	title.add_theme_font_size_override("font_size", 42)
	title.modulate = Color(1.0, 0.88, 0.35)
	_mode_select_box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "请选择运行模式 / SELECT RUNTIME MODE"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _custom_font != null:
		subtitle.add_theme_font_override("font", _custom_font)
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.modulate = Color(0.7, 0.75, 0.85, 0.8)
	_mode_select_box.add_child(subtitle)

	_mode_select_box.add_child(_spacer(14))

	# Player Client Big Button
	var btn_player := _make_big_mode_button(
		"进入 玩家正式端 (Player Mode)",
		"全套美术画风、真人语音倒数、按键图元指引、1v1 极限追缉与地图工坊",
		"res://assets/UI_assets/daemon-skull.svg",
		Color(0.95, 0.30, 0.22)
	)
	btn_player.pressed.connect(func() -> void: _open(PLAYER_CLIENT_SCENE))
	_mode_select_box.add_child(btn_player)

	# Developer Sandbox Big Button
	var btn_dev := _make_big_mode_button(
		"打开 开发者工作台 (Developer Sandbox)",
		"底层动作调试、骨骼绑定测试、武器参数调整、NPC 动力学寻路测试",
		"res://assets/UI_assets/gear-hammer.svg",
		Color(0.25, 0.70, 0.95)
	)
	btn_dev.pressed.connect(_show_dev_menu)
	_mode_select_box.add_child(btn_dev)

	_mode_select_box.add_child(_spacer(10))

	var quit_btn := Button.new()
	quit_btn.text = "退出游戏 / Quit"
	if _custom_font != null:
		quit_btn.add_theme_font_override("font", _custom_font)
	quit_btn.add_theme_font_size_override("font_size", 16)
	quit_btn.custom_minimum_size = Vector2(0, 40)
	quit_btn.pressed.connect(func() -> void: get_tree().quit())
	_mode_select_box.add_child(quit_btn)

	# --- Developer Scenes Panel ---
	_dev_box = VBoxContainer.new()
	_dev_box.add_theme_constant_override("separation", 10)
	_dev_box.custom_minimum_size = Vector2(520, 0)
	_dev_box.visible = false
	centre.add_child(_dev_box)

	var dev_title := Label.new()
	dev_title.text = "🛠️ 开发者沙盒调试工具箱"
	dev_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _custom_font != null:
		dev_title.add_theme_font_override("font", _custom_font)
	dev_title.add_theme_font_size_override("font_size", 28)
	dev_title.modulate = Color(0.3, 0.8, 1.0)
	_dev_box.add_child(dev_title)

	for entry in DEV_ENTRIES:
		_dev_box.add_child(_make_dev_entry(entry))

	_dev_box.add_child(_spacer(10))

	var back_btn := Button.new()
	back_btn.text = "← 返回模式选择 (Back to Mode Select)"
	if _custom_font != null:
		back_btn.add_theme_font_override("font", _custom_font)
	back_btn.add_theme_font_size_override("font_size", 16)
	back_btn.custom_minimum_size = Vector2(0, 44)
	back_btn.pressed.connect(_show_mode_select)
	_dev_box.add_child(back_btn)


func _make_big_mode_button(title: String, desc: String, icon_path: String, border_col: Color) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(500, 76)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	var style_norm := StyleBoxFlat.new()
	style_norm.bg_color = Color(0.12, 0.14, 0.18, 0.95)
	style_norm.set_corner_radius_all(10)
	style_norm.set_border_width_all(2)
	style_norm.border_color = Color(0.25, 0.30, 0.38)
	style_norm.set_content_margin_all(12)
	btn.add_theme_stylebox_override("normal", style_norm)

	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = Color(0.16, 0.20, 0.26, 0.98)
	style_hover.set_corner_radius_all(10)
	style_hover.set_border_width_all(2)
	style_hover.border_color = border_col
	style_hover.set_content_margin_all(12)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_hover)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(PRESET_FULL_RECT)
	hbox.mouse_filter = MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 14)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn.add_child(hbox)

	if ResourceLoader.exists(icon_path):
		var icon_tex := TextureRect.new()
		icon_tex.texture = load(icon_path)
		icon_tex.custom_minimum_size = Vector2(40, 40)
		icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_tex.modulate = border_col
		hbox.add_child(icon_tex)

	var text_vbox := VBoxContainer.new()
	text_vbox.mouse_filter = MOUSE_FILTER_IGNORE
	text_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(text_vbox)

	var t_lbl := Label.new()
	t_lbl.text = title
	if _custom_font != null:
		t_lbl.add_theme_font_override("font", _custom_font)
	t_lbl.add_theme_font_size_override("font_size", 20)
	t_lbl.modulate = Color(1.0, 0.95, 0.9)
	text_vbox.add_child(t_lbl)

	var d_lbl := Label.new()
	d_lbl.text = desc
	if _custom_font != null:
		d_lbl.add_theme_font_override("font", _custom_font)
	d_lbl.add_theme_font_size_override("font_size", 12)
	d_lbl.modulate = Color(0.7, 0.75, 0.8)
	text_vbox.add_child(d_lbl)

	return btn


func _make_dev_entry(entry: Dictionary) -> Control:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 2)

	var button := Button.new()
	button.text = entry.title
	if _custom_font != null:
		button.add_theme_font_override("font", _custom_font)
	button.add_theme_font_size_override("font_size", 14)
	button.custom_minimum_size = Vector2(0, 38)
	if not ResourceLoader.exists(entry.scene):
		button.disabled = true
		button.text += "   (缺少 %s)" % String(entry.scene).get_file()
	else:
		button.pressed.connect(func() -> void: _open(entry.scene))
	panel.add_child(button)

	var blurb := Label.new()
	blurb.text = entry.blurb
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _custom_font != null:
		blurb.add_theme_font_override("font", _custom_font)
	blurb.add_theme_font_size_override("font_size", 12)
	blurb.modulate = Color(1, 1, 1, 0.55)
	panel.add_child(blurb)
	return panel


func _show_dev_menu() -> void:
	_mode_select_box.visible = false
	_dev_box.visible = true


func _show_mode_select() -> void:
	_dev_box.visible = false
	_mode_select_box.visible = true


func _open(scene_path: String) -> void:
	if scene_path == "res://scenes/playground.tscn":
		var playground_script = load("res://scripts/playground.gd")
		if playground_script != null:
			playground_script.show_debug_hud = true
			playground_script.return_scene = "res://scenes/main_menu.tscn"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	SceneLoader.change_scene(get_tree(), scene_path)


func _spacer(height: int) -> Control:
	var node := Control.new()
	node.custom_minimum_size = Vector2(0, height)
	return node
