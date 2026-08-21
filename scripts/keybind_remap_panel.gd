class_name KeybindRemapPanel
extends PanelContainer
## Combat and locomotion input remapping UI panel.
## Supports rebinding all gameplay actions to any key or mouse button, with direct single/double-tap mode toggles.

signal closed

const KeybindManagerScript = preload("res://scripts/keybind_manager.gd")
const FONT_PATH := "res://assets/Fonts/Long_Cang/LongCang-Regular.ttf"

var _custom_font: Font = null
var _manager = null

var _listening_action := ""
var _listen_modal: PanelContainer = null
var _listen_hint_label: Label = null

var _action_rows: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(700, 580)
	if ResourceLoader.exists(FONT_PATH):
		_custom_font = load(FONT_PATH) as Font
	_manager = KeybindManagerScript.get_instance()
	_build_panel()
	_refresh_all_rows()


func _ready() -> void:
	_refresh_all_rows()


func _build_panel() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.12, 0.96)
	style.set_corner_radius_all(12)
	style.set_border_width_all(2)
	style.border_color = Color(0.85, 0.55, 0.18, 0.95)
	style.set_content_margin_all(18)
	add_theme_stylebox_override("panel", style)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12)
	add_child(main_vbox)

	# Header
	var title_lbl := Label.new()
	title_lbl.text = "⌨️ 战斗与身法按键重定向 (Controls Remap)"
	if _custom_font != null:
		title_lbl.add_theme_font_override("font", _custom_font)
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.modulate = Color(1.0, 0.85, 0.35)
	main_vbox.add_child(title_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = "点击【模式按钮】可直接切换「单按」与「双击」· 点击【修改按键】可录入新物理按键/鼠标按键"
	if _custom_font != null:
		desc_lbl.add_theme_font_override("font", _custom_font)
	desc_lbl.add_theme_font_size_override("font_size", 13)
	desc_lbl.modulate = Color(0.75, 0.82, 0.92)
	main_vbox.add_child(desc_lbl)

	main_vbox.add_child(HSeparator.new())

	# Scrollable Content
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll)

	var list_box := VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 14)
	scroll.add_child(list_box)

	# 1. Locomotion Group
	_build_group_section(list_box, "🏃‍♂️ 身法与移动动作 (Locomotion)", KeybindManagerScript.ACTION_GROUPS["locomotion"])

	list_box.add_child(HSeparator.new())

	# 2. Combat Group
	_build_group_section(list_box, "⚔️ 战斗与招式派生 (Combat)", KeybindManagerScript.ACTION_GROUPS["combat"])

	main_vbox.add_child(HSeparator.new())

	# Footer Buttons
	var footer_hbox := HBoxContainer.new()
	footer_hbox.add_theme_constant_override("separation", 12)
	main_vbox.add_child(footer_hbox)

	var reset_btn := Button.new()
	reset_btn.text = "🔄 恢复默认键位"
	reset_btn.custom_minimum_size = Vector2(130, 34)
	if _custom_font != null:
		reset_btn.add_theme_font_override("font", _custom_font)
	reset_btn.pressed.connect(func() -> void:
		_manager.reset_to_defaults()
		_refresh_all_rows()
	)
	footer_hbox.add_child(reset_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_hbox.add_child(spacer)

	var save_close_btn := Button.new()
	save_close_btn.text = "💾 保存并关闭 (Save & Exit)"
	save_close_btn.custom_minimum_size = Vector2(160, 34)
	var sc_style := StyleBoxFlat.new()
	sc_style.bg_color = Color(0.18, 0.45, 0.25, 0.95)
	sc_style.set_corner_radius_all(6)
	save_close_btn.add_theme_stylebox_override("normal", sc_style)
	if _custom_font != null:
		save_close_btn.add_theme_font_override("font", _custom_font)
	save_close_btn.pressed.connect(func() -> void:
		_manager.save_to_disk()
		visible = false
		closed.emit()
	)
	footer_hbox.add_child(save_close_btn)

	# Listening Modal Overlay
	_build_listening_modal()


func _build_group_section(parent: VBoxContainer, group_title: String, actions: Array) -> void:
	var sec_title := Label.new()
	sec_title.text = group_title
	if _custom_font != null:
		sec_title.add_theme_font_override("font", _custom_font)
	sec_title.add_theme_font_size_override("font_size", 15)
	sec_title.modulate = Color(0.95, 0.65, 0.25)
	parent.add_child(sec_title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(grid)

	for action in actions:
		var row := _build_action_card(str(action))
		grid.add_child(row)


func _build_action_card(action: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var c_style := StyleBoxFlat.new()
	c_style.bg_color = Color(0.10, 0.12, 0.17, 0.85)
	c_style.set_corner_radius_all(6)
	c_style.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", c_style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	card.add_child(hbox)

	var name_lbl := Label.new()
	name_lbl.text = KeybindManagerScript.action_label(action)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _custom_font != null:
		name_lbl.add_theme_font_override("font", _custom_font)
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.modulate = Color(0.9, 0.92, 0.96)
	hbox.add_child(name_lbl)

	# Direct Toggle Mode Button (Single vs Double-Tap)
	var mode_btn := Button.new()
	mode_btn.custom_minimum_size = Vector2(74, 26)
	if _custom_font != null:
		mode_btn.add_theme_font_override("font", _custom_font)
	mode_btn.add_theme_font_size_override("font_size", 11)
	mode_btn.pressed.connect(func() -> void:
		var b: Dictionary = _manager.get_binding(action)
		var cur_trig: String = b.get("trigger", "single")
		var next_trig := "single" if cur_trig == "double_tap" else "double_tap"
		_manager.set_action_trigger_mode(action, next_trig)
		_refresh_all_rows()
	)
	hbox.add_child(mode_btn)

	# Key Display Badge
	var bind_badge := PanelContainer.new()
	var b_style := StyleBoxFlat.new()
	b_style.bg_color = Color(0.18, 0.22, 0.30, 0.95)
	b_style.set_corner_radius_all(4)
	b_style.set_content_margin_all(5)
	b_style.set_border_width_all(1)
	b_style.border_color = Color(0.4, 0.5, 0.65, 0.7)
	bind_badge.add_theme_stylebox_override("panel", b_style)
	hbox.add_child(bind_badge)

	var bind_lbl := Label.new()
	bind_lbl.text = _manager.binding_key_only_text(action)
	if _custom_font != null:
		bind_lbl.add_theme_font_override("font", _custom_font)
	bind_lbl.add_theme_font_size_override("font_size", 12)
	bind_lbl.modulate = Color(0.3, 0.9, 1.0)
	bind_badge.add_child(bind_lbl)

	# Rebind Key Button
	var edit_btn := Button.new()
	edit_btn.text = "修改按键"
	edit_btn.custom_minimum_size = Vector2(62, 26)
	if _custom_font != null:
		edit_btn.add_theme_font_override("font", _custom_font)
	edit_btn.add_theme_font_size_override("font_size", 12)
	edit_btn.pressed.connect(func() -> void: _start_listening(action))
	hbox.add_child(edit_btn)

	_action_rows[action] = {
		"badge_label": bind_lbl,
		"mode_button": mode_btn,
	}
	return card


func _refresh_all_rows() -> void:
	for action in _action_rows:
		var entry: Dictionary = _action_rows[action]
		var lbl: Label = entry.get("badge_label")
		var mode_b: Button = entry.get("mode_button")
		var b: Dictionary = _manager.get_binding(action)
		var is_double: bool = (b.get("trigger", "single") == "double_tap")

		if lbl != null:
			lbl.text = _manager.binding_key_only_text(action)

		if mode_b != null:
			if is_double:
				mode_b.text = "⚡⚡ 双击"
				mode_b.modulate = Color(1.0, 0.75, 0.25)
			else:
				mode_b.text = "⚡ 单按"
				mode_b.modulate = Color(0.4, 0.85, 1.0)


func _build_listening_modal() -> void:
	_listen_modal = PanelContainer.new()
	_listen_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_listen_modal.visible = false

	var m_style := StyleBoxFlat.new()
	m_style.bg_color = Color(0.04, 0.05, 0.08, 0.96)
	m_style.set_corner_radius_all(10)
	m_style.set_content_margin_all(20)
	_listen_modal.add_theme_stylebox_override("panel", m_style)
	add_child(_listen_modal)

	var mv := VBoxContainer.new()
	mv.alignment = BoxContainer.ALIGNMENT_CENTER
	mv.add_theme_constant_override("separation", 16)
	_listen_modal.add_child(mv)

	_listen_hint_label = Label.new()
	_listen_hint_label.text = "正在修改按键...\n请直接按下目标【键盘按键】或 点击【鼠标按键】"
	_listen_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _custom_font != null:
		_listen_hint_label.add_theme_font_override("font", _custom_font)
	_listen_hint_label.add_theme_font_size_override("font_size", 20)
	_listen_hint_label.modulate = Color(1.0, 0.85, 0.3)
	mv.add_child(_listen_hint_label)

	var sub_hint := Label.new()
	sub_hint.text = "录入按键后，可在列表中随时点击模式按钮切换「单按」或「双击」"
	sub_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _custom_font != null:
		sub_hint.add_theme_font_override("font", _custom_font)
	sub_hint.add_theme_font_size_override("font_size", 13)
	sub_hint.modulate = Color(0.7, 0.75, 0.85)
	mv.add_child(sub_hint)

	var cancel_btn := Button.new()
	cancel_btn.text = "取消修改 (ESC)"
	cancel_btn.custom_minimum_size = Vector2(140, 34)
	cancel_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if _custom_font != null:
		cancel_btn.add_theme_font_override("font", _custom_font)
	cancel_btn.pressed.connect(_stop_listening)
	mv.add_child(cancel_btn)


func _start_listening(action: String) -> void:
	_listening_action = action
	var a_name := KeybindManagerScript.action_label(action)
	_listen_hint_label.text = "正在为【%s】录入新按键\n请直接按下目标【键盘按键】或【鼠标按键】..." % a_name
	_listen_modal.visible = true


func _stop_listening() -> void:
	_listening_action = ""
	_listen_modal.visible = false


func _input(event: InputEvent) -> void:
	if not _listen_modal.visible or _listening_action.is_empty():
		return

	if event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		if event.keycode == KEY_ESCAPE:
			_stop_listening()
			return

		var cur_bind: Dictionary = _manager.get_binding(_listening_action)
		var trig: String = cur_bind.get("trigger", "single")
		_manager.set_binding(_listening_action, {
			"device": "key",
			"code": event.keycode,
			"trigger": trig,
		})
		_stop_listening()
		_refresh_all_rows()
		return

	if event is InputEventMouseButton and event.pressed:
		get_viewport().set_input_as_handled()
		var cur_bind: Dictionary = _manager.get_binding(_listening_action)
		var trig: String = cur_bind.get("trigger", "single")
		_manager.set_binding(_listening_action, {
			"device": "mouse",
			"code": event.button_index,
			"trigger": trig,
		})
		_stop_listening()
		_refresh_all_rows()
		return
