class_name UpdateDialog
extends Control
## In-game update prompt modal dialog with animations and direct Git synchronization.

signal dismissed()
signal update_finished(success: bool)

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const UpdaterScript = preload("res://scripts/updater/updater.gd")

const FONT_PATH := "res://assets/Fonts/Long_Cang/LongCang-Regular.ttf"
const ICON_PATH := "res://assets/UI_assets/winged-sword.svg"
const OPEN_SOUND_PATH := "res://assets/voice/RPGsounds_Kenney/OGG/bookOpen.ogg"
const CLOSE_SOUND_PATH := "res://assets/voice/RPGsounds_Kenney/OGG/bookClose.ogg"
const SUCCESS_SOUND_PATH := "res://assets/voice/RPGsounds_Kenney/OGG/handleCoins.ogg"


var _custom_font: Font = null
var _panel: PanelContainer
var _content_box: VBoxContainer
var _btn_box: HBoxContainer
var _status_lbl: Label
var _progress_box: VBoxContainer
var _pull_btn: Button
var _skip_btn: Button

var _remote_info: Dictionary = {}
var _local_info: Dictionary = {}
var _is_animating: bool = false
var _is_busy: bool = false


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	if ResourceLoader.exists(FONT_PATH):
		_custom_font = load(FONT_PATH) as Font
	_build_ui()
	_animate_in()


func setup_data(remote_info: Dictionary) -> void:
	_remote_info = remote_info
	_local_info = UpdaterScript.get_local_version_info()
	_refresh_content()



func _build_ui() -> void:
	var dark_overlay := ColorRect.new()
	dark_overlay.set_anchors_preset(PRESET_FULL_RECT)
	dark_overlay.color = Color(0.02, 0.03, 0.05, 0.75)
	add_child(dark_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(580, 420)
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.11, 0.15, 0.98)
	style.set_corner_radius_all(14)
	style.set_border_width_all(2)
	style.border_color = Color(1.0, 0.78, 0.35, 0.9)
	style.shadow_color = Color(1.0, 0.6, 0.1, 0.25)
	style.shadow_size = 18
	style.set_content_margin_all(24)
	_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_panel)

	_content_box = VBoxContainer.new()
	_content_box.add_theme_constant_override("separation", 14)
	_panel.add_child(_content_box)

	# 1. Header
	var header_hbox := HBoxContainer.new()
	header_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	header_hbox.add_theme_constant_override("separation", 12)
	_content_box.add_child(header_hbox)

	if ResourceLoader.exists(ICON_PATH):
		var icon_rect := TextureRect.new()
		icon_rect.texture = load(ICON_PATH)
		icon_rect.custom_minimum_size = Vector2(38, 38)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.modulate = Color(1.0, 0.85, 0.35)
		header_hbox.add_child(icon_rect)

	var title := Label.new()
	title.text = "发现江湖新篇章 (发现新版本)"
	if _custom_font != null:
		title.add_theme_font_override("font", _custom_font)
	title.add_theme_font_size_override("font_size", 24)
	title.modulate = Color(1.0, 0.88, 0.38)
	header_hbox.add_child(title)

	# 2. Version badge box
	var v_box := PanelContainer.new()
	var v_style := StyleBoxFlat.new()
	v_style.bg_color = Color(0.14, 0.17, 0.23, 0.85)
	v_style.set_corner_radius_all(8)
	v_style.set_content_margin_all(10)
	v_box.add_theme_stylebox_override("panel", v_style)
	_content_box.add_child(v_box)

	var v_hbox := HBoxContainer.new()
	v_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	v_hbox.add_theme_constant_override("separation", 24)
	v_box.add_child(v_hbox)

	_status_lbl = Label.new()
	_status_lbl.text = "正在获取版本信息..."
	if _custom_font != null:
		_status_lbl.add_theme_font_override("font", _custom_font)
	_status_lbl.add_theme_font_size_override("font_size", 16)
	_status_lbl.modulate = Color(0.9, 0.93, 0.98)
	v_hbox.add_child(_status_lbl)

	# 3. Release Notes Scroll Area
	var notes_panel := PanelContainer.new()
	notes_panel.size_flags_vertical = SIZE_EXPAND_FILL
	var n_style := StyleBoxFlat.new()
	n_style.bg_color = Color(0.06, 0.07, 0.10, 0.8)
	n_style.set_corner_radius_all(8)
	n_style.set_border_width_all(1)
	n_style.border_color = Color(0.2, 0.25, 0.32)
	n_style.set_content_margin_all(12)
	notes_panel.add_theme_stylebox_override("panel", n_style)
	_content_box.add_child(notes_panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	notes_panel.add_child(scroll)

	var notes_vbox := VBoxContainer.new()
	notes_vbox.name = "NotesContainer"
	notes_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	notes_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(notes_vbox)

	# 4. Progress / Status Feedback Box
	_progress_box = VBoxContainer.new()
	_progress_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_progress_box.visible = false
	_content_box.add_child(_progress_box)

	var prog_lbl := Label.new()
	prog_lbl.name = "ProgressLabel"
	prog_lbl.text = "⚡ 正在从 Gitee 远程拉取最新代码与资产..."
	if _custom_font != null:
		prog_lbl.add_theme_font_override("font", _custom_font)
	prog_lbl.add_theme_font_size_override("font_size", 16)
	prog_lbl.modulate = Color(0.3, 0.9, 1.0)
	prog_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_box.add_child(prog_lbl)

	# 5. Action Buttons
	_btn_box = HBoxContainer.new()
	_btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_btn_box.add_theme_constant_override("separation", 20)
	_content_box.add_child(_btn_box)

	_pull_btn = Button.new()
	_pull_btn.text = "🚀 立即拉取更新 (Git Pull)"
	if _custom_font != null:
		_pull_btn.add_theme_font_override("font", _custom_font)
	_pull_btn.add_theme_font_size_override("font_size", 16)
	_pull_btn.custom_minimum_size = Vector2(210, 44)
	_style_gold_button(_pull_btn)
	_pull_btn.pressed.connect(_on_pull_pressed)
	_btn_box.add_child(_pull_btn)

	_skip_btn = Button.new()
	_skip_btn.text = "⏩ 暂不更新，直接启程"
	if _custom_font != null:
		_skip_btn.add_theme_font_override("font", _custom_font)
	_skip_btn.add_theme_font_size_override("font_size", 16)
	_skip_btn.custom_minimum_size = Vector2(170, 44)
	_style_dark_button(_skip_btn)
	_skip_btn.pressed.connect(_on_skip_pressed)
	_btn_box.add_child(_skip_btn)
	_refresh_content()



func _style_gold_button(btn: Button) -> void:
	var s_norm := StyleBoxFlat.new()
	s_norm.bg_color = Color(0.85, 0.55, 0.15, 0.95)
	s_norm.set_corner_radius_all(8)
	s_norm.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", s_norm)

	var s_hover := StyleBoxFlat.new()
	s_hover.bg_color = Color(1.0, 0.68, 0.22, 1.0)
	s_hover.set_corner_radius_all(8)
	s_hover.set_border_width_all(2)
	s_hover.border_color = Color(1.0, 0.9, 0.5)
	s_hover.set_content_margin_all(8)
	btn.add_theme_stylebox_override("hover", s_hover)
	btn.add_theme_stylebox_override("pressed", s_hover)


func _style_dark_button(btn: Button) -> void:
	var s_norm := StyleBoxFlat.new()
	s_norm.bg_color = Color(0.18, 0.22, 0.28, 0.9)
	s_norm.set_corner_radius_all(8)
	s_norm.set_border_width_all(1)
	s_norm.border_color = Color(0.35, 0.40, 0.50)
	s_norm.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", s_norm)

	var s_hover := StyleBoxFlat.new()
	s_hover.bg_color = Color(0.24, 0.30, 0.38, 0.98)
	s_hover.set_corner_radius_all(8)
	s_hover.set_border_width_all(1)
	s_hover.border_color = Color(0.5, 0.6, 0.75)
	s_hover.set_content_margin_all(8)
	btn.add_theme_stylebox_override("hover", s_hover)


func _refresh_content() -> void:
	if _status_lbl == null or _panel == null:
		return
	if _local_info.is_empty():
		_local_info = UpdaterScript.get_local_version_info()
	var local_v := str(_local_info.get("version", "v1.0.0"))
	var remote_v := str(_remote_info.get("version", "最新版本"))
	_status_lbl.text = "当前本地版本: %s    ➔    🔥 Gitee 最新版本: %s" % [local_v, remote_v]

	var notes_container := _panel.find_child("NotesContainer", true, false) as VBoxContainer

	if notes_container != null:
		for c in notes_container.get_children():
			c.queue_free()

		var notes_array: Array = _remote_info.get("release_notes", _local_info.get("release_notes", []))
		if notes_array.is_empty():
			notes_array = ["性能优化与核心系统升级", "最新代码与美术资产同步"]

		for item in notes_array:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)

			var bullet := Label.new()
			bullet.text = "✦"
			bullet.modulate = Color(1.0, 0.75, 0.25)
			if _custom_font != null:
				bullet.add_theme_font_override("font", _custom_font)
			bullet.add_theme_font_size_override("font_size", 14)
			row.add_child(bullet)

			var note_lbl := Label.new()
			note_lbl.text = str(item)
			note_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
			if _custom_font != null:
				note_lbl.add_theme_font_override("font", _custom_font)
			note_lbl.add_theme_font_size_override("font_size", 14)
			note_lbl.modulate = Color(0.88, 0.90, 0.95)
			row.add_child(note_lbl)

			notes_container.add_child(row)


func _animate_in() -> void:
	if _panel == null:
		return
	_panel.pivot_offset = Vector2(290, 210)
	_panel.scale = Vector2(0.75, 0.75)
	modulate.a = 0.0

	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	if ResourceLoader.exists(OPEN_SOUND_PATH):
		var s := load(OPEN_SOUND_PATH) as AudioStream
		AudioManagerScript.play_sound(s, 0.0)


func _animate_out(on_done: Callable = Callable()) -> void:
	if _is_animating:
		return
	_is_animating = true
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_panel, "scale", Vector2(0.85, 0.85), 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func() -> void:
		if on_done.is_valid():
			on_done.call()
		queue_free()
	)


func _on_skip_pressed() -> void:
	if _is_busy:
		return
	dismissed.emit()
	if ResourceLoader.exists(CLOSE_SOUND_PATH):
		var s := load(CLOSE_SOUND_PATH) as AudioStream
		AudioManagerScript.play_sound(s, 0.0)
	_animate_out()


func _on_pull_pressed() -> void:
	if _is_busy:
		return
	_is_busy = true
	_btn_box.visible = false
	_progress_box.visible = true

	var prog_lbl := _progress_box.get_node("ProgressLabel") as Label
	if prog_lbl != null:
		prog_lbl.text = "⚡ 正在从 Gitee 拉取最新代码与资产..."
		prog_lbl.modulate = Color(0.3, 0.9, 1.0)

	UpdaterScript.pull_latest_code(func(success: bool, output: String) -> void:
		_on_pull_result(success, output)
	)


func _on_pull_result(success: bool, output: String) -> void:
	var prog_lbl := _progress_box.get_node("ProgressLabel") as Label
	if success:
		if prog_lbl != null:
			prog_lbl.text = "✅ 成功拉取最新代码与资产！正在重载游戏..."
			prog_lbl.modulate = Color(0.3, 1.0, 0.4)
		if ResourceLoader.exists(SUCCESS_SOUND_PATH):
			var s := load(SUCCESS_SOUND_PATH) as AudioStream
			AudioManagerScript.play_sound(s, 1.0)
		
		# Wait 1.2s and reload scene
		var tree := get_tree()
		var timer := tree.create_timer(1.2)
		timer.timeout.connect(func() -> void:
			update_finished.emit(true)
			tree.reload_current_scene()
		)
	else:
		_is_busy = false
		if prog_lbl != null:
			prog_lbl.text = "⚠️ 拉取失败: %s" % output.strip_edges().replace("\n", " ")
			prog_lbl.modulate = Color(1.0, 0.35, 0.35)
		_btn_box.visible = true
		_pull_btn.text = "🔄 重新拉取"
		_skip_btn.text = "⏩ 忽略并继续"

