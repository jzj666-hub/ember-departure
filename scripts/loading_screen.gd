extends Control
## Asynchronous loading screen with smooth progress bar and dynamic gameplay hints.
## Invariant: loads SceneLoader.target_scene_path and transitions upon 100% completion.

const FONT_PATH := "res://assets/Fonts/Long_Cang/LongCang-Regular.ttf"
const DEFAULT_FALLBACK := "res://scenes/main_menu.tscn"

const TIPS := [
	"提示：按住 Shift 直线奔跑可进入极速逃生状态！",
	"提示：贴近 2 格高台边缘按下空格即可自动攀登翻越！",
	"提示：双击 Shift 键可触发敏捷战术翻滚，规避追捕与攻击！",
	"提示：在地图工坊中可以自由录制人机空中直线跳跃航迹！",
	"提示：在兵器试炼中连招窗口内按下对应按键即可打出华丽派生技！",
	"提示：按 F3 键可在第一人称与第三人称视界之间随时自由切换！",
]

var _target_path := ""
var _custom_font: Font = null
var _display_progress: float = 0.0
var _tip_timer: float = 0.0
var _tip_index: int = 0

var _title_label: Label
var _progress_bar: ProgressBar
var _percent_label: Label
var _tip_label: Label
var _transitioned := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if ResourceLoader.exists(FONT_PATH):
		_custom_font = load(FONT_PATH) as Font

	_target_path = SceneLoader.target_scene_path
	if _target_path.is_empty():
		_target_path = DEFAULT_FALLBACK

	_build_ui()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.07, 0.09, 1.0)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(560, 0)
	vbox.add_theme_constant_override("separation", 18)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	var icon_tex := TextureRect.new()
	if ResourceLoader.exists("res://assets/UI_assets/daemon-skull.svg"):
		icon_tex.texture = load("res://assets/UI_assets/daemon-skull.svg")
	icon_tex.custom_minimum_size = Vector2(64, 64)
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.modulate = Color(1.0, 0.45, 0.2, 0.95)
	vbox.add_child(icon_tex)

	_title_label = Label.new()
	_title_label.text = "灰烬 · 启程"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _custom_font != null:
		_title_label.add_theme_font_override("font", _custom_font)
	_title_label.add_theme_font_size_override("font_size", 34)
	_title_label.modulate = Color(1.0, 0.88, 0.35)
	vbox.add_child(_title_label)

	var sub := Label.new()
	sub.text = "正在准备场景与动作资源 / LOADING ASSETS"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _custom_font != null:
		sub.add_theme_font_override("font", _custom_font)
	sub.add_theme_font_size_override("font_size", 14)
	sub.modulate = Color(0.7, 0.75, 0.85, 0.75)
	vbox.add_child(sub)

	# Progress Bar Container
	var bar_box := VBoxContainer.new()
	bar_box.add_theme_constant_override("separation", 6)
	vbox.add_child(bar_box)

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.value = 0.0
	_progress_bar.show_percentage = false
	_progress_bar.custom_minimum_size = Vector2(540, 14)

	var style_bg := StyleBoxFlat.new()
	style_bg.bg_color = Color(0.12, 0.14, 0.18, 0.95)
	style_bg.set_corner_radius_all(7)
	style_bg.set_border_width_all(1)
	style_bg.border_color = Color(0.25, 0.28, 0.35)
	_progress_bar.add_theme_stylebox_override("background", style_bg)

	var style_fill := StyleBoxFlat.new()
	style_fill.bg_color = Color(1.0, 0.55, 0.18)
	style_fill.set_corner_radius_all(7)
	_progress_bar.add_theme_stylebox_override("fill", style_fill)
	bar_box.add_child(_progress_bar)

	_percent_label = Label.new()
	_percent_label.text = "0%"
	_percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if _custom_font != null:
		_percent_label.add_theme_font_override("font", _custom_font)
	_percent_label.add_theme_font_size_override("font_size", 13)
	_percent_label.modulate = Color(1.0, 0.8, 0.3)
	bar_box.add_child(_percent_label)

	# Tip card
	var tip_panel := PanelContainer.new()
	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.09, 0.11, 0.15, 0.85)
	t_style.set_corner_radius_all(8)
	t_style.set_border_width_all(1)
	t_style.border_color = Color(0.22, 0.26, 0.34)
	t_style.set_content_margin_all(12)
	tip_panel.add_theme_stylebox_override("panel", t_style)
	vbox.add_child(tip_panel)

	_tip_label = Label.new()
	_tip_label.text = SceneLoader.target_hint_text if not SceneLoader.target_hint_text.is_empty() else TIPS[0]
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _custom_font != null:
		_tip_label.add_theme_font_override("font", _custom_font)
	_tip_label.add_theme_font_size_override("font_size", 13)
	_tip_label.modulate = Color(0.85, 0.88, 0.92, 0.85)
	tip_panel.add_child(_tip_label)


func _process(delta: float) -> void:
	if _transitioned:
		return

	# Tip cycling if no static hint was supplied
	if SceneLoader.target_hint_text.is_empty():
		_tip_timer += delta
		if _tip_timer >= 2.5:
			_tip_timer = 0.0
			_tip_index = (_tip_index + 1) % TIPS.size()
			_tip_label.text = TIPS[_tip_index]

	var progress_arr: Array = []
	var status := ResourceLoader.load_threaded_get_status(_target_path, progress_arr)

	var target_pct := 10.0
	if not progress_arr.is_empty():
		target_pct = maxf(target_pct, float(progress_arr[0]) * 100.0)

	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_display_progress = move_toward(_display_progress, target_pct, delta * 150.0)
		ResourceLoader.THREAD_LOAD_LOADED:
			_display_progress = move_toward(_display_progress, 100.0, delta * 200.0)
			if _display_progress >= 99.9:
				_transitioned = true
				var packed := ResourceLoader.load_threaded_get(_target_path) as PackedScene
				if packed != null:
					get_tree().change_scene_to_packed(packed)
				else:
					get_tree().change_scene_to_file(_target_path)
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_transitioned = true
			push_error("SceneLoader: failed to load %s (%d)" % [_target_path, status])
			get_tree().change_scene_to_file(_target_path)

	_progress_bar.value = _display_progress
	_percent_label.text = "%d%%" % int(_display_progress)
