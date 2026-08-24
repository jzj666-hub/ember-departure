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
		"title": "连续地图寻路测试 / Continuous Map Navigation Test",
		"blurb": "不含任何方块的地图：斜坡、旋转的墙、圆柱。NPC 走的是烘焙出来的 NavigationMesh，寻路后端换成 NavMeshProvider，而 AI 执行器一行未改。WASD/QE 飞行，准星对准地面 LMB 指定目的地。",
		"scene": "res://scenes/navmesh_test.tscn",
	},
	{
		"title": "追缉模式底层调试 / Raw Pursuit Debug",
		"blurb": "1v1 追缉逃生底层调试场景（包含调试红柱与直接参数监视）。",
		"scene": "res://scenes/chase_mode.tscn",
	},
	{
		"title": "技能与特效演练场 / Skill & VFX Lab",
		"blurb": "实时技能与特效参数微调靶场。支持赛博瞬移与高频抖动残影、全息破碎消散，支持 0.2x/0.5x 慢放调试。",
		"scene": "res://scenes/skill_vfx_lab.tscn",
	},
	{
		"title": "局域网多人追缉大厅 / LAN Multiplayer Pursuit Lobby",
		"blurb": "1v1 局域网/P2P 多人对战追缉模式大厅，支持延迟快照插值与双方 Tab 自由上帝视角 A* 战术规划。",
		"scene": "res://scenes/player_client/multiplayer_lobby.tscn",
	},
	{
		"title": "庄园探索与秘契商舍 / Manor Estate & Ember Merchant",
		"blurb": "连续自然起伏地形庄园，包含完整欧风建筑群、植被林地、双向无缝传送门与室内商舍（支持金币与灰烬凭证兑换）。",
		"scene": "res://scenes/manor_estate.tscn",
	},
	{
		"title": "人机刀剑PVP测试 / NPC Sword PVP Sandbox",
		"blurb": "方块地图 1v1 刀剑实时格斗测试：双方血量、武器基础攻击力、双方攻击力加成、防御力全参数实时可调，支持翻滚受击减伤50%与免控机制。",
		"scene": "res://scenes/pvp_sword_sandbox.tscn",
	},
]

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const VIDEO_OGV_PATH := "res://assets/UI_assets/主界面动画.ogv"

static var open_dev_menu_on_enter: bool = false

var _custom_font: Font = null
var _mode_select_box: VBoxContainer
var _dev_scroll: ScrollContainer
var _dev_box: VBoxContainer
var _video_player: VideoStreamPlayer


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioManagerScript.init_pool(self)
	AudioManagerScript.play_bgm("res://assets/voice/background/song_of_the_sea.ogg", -6.0)
	if ResourceLoader.exists(FONT_PATH):
		_custom_font = load(FONT_PATH) as Font
	_build_ui()

	if open_dev_menu_on_enter:
		open_dev_menu_on_enter = false
		_show_dev_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if _dev_scroll != null and _dev_scroll.visible:
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
		"底层动作调试、骨骼绑定测试、武器参数调整、NPC 智能寻路测试",
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
	_dev_scroll = ScrollContainer.new()
	_dev_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dev_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_dev_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_dev_scroll.visible = false
	add_child(_dev_scroll)

	_dev_box = VBoxContainer.new()
	_dev_box.add_theme_constant_override("separation", 10)
	_dev_box.custom_minimum_size = Vector2(520, 0)
	_dev_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_dev_scroll.add_child(_dev_box)

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
	return button


func _show_dev_menu() -> void:
	open_dev_menu_on_enter = true
	_mode_select_box.visible = false
	_dev_scroll.visible = true
	_dev_scroll.scroll_vertical = 0


func _show_mode_select() -> void:
	open_dev_menu_on_enter = false
	_dev_scroll.visible = false
	_mode_select_box.visible = true


func _open(scene_path: String) -> void:
	if scene_path != PLAYER_CLIENT_SCENE:
		open_dev_menu_on_enter = true
	else:
		open_dev_menu_on_enter = false

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
