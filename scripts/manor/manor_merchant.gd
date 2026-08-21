class_name ManorMerchant
extends Node3D

signal exchange_completed(amount_vouchers: int, gold_spent: int)

const FONT_CHINESE := "res://assets/Fonts/Long_Cang/LongCang-Regular.ttf"
const FONT_GLITCH := "res://assets/Fonts/Long_Cang,Rubik_Glitch/Rubik_Glitch/RubikGlitch-Regular.ttf"
const EXCHANGE_RATE := 100 # 100 Gold = 1 Ember Voucher

var _area: Area3D
var _prompt_label: Label3D
var _name_label: Label3D
var _player_in_range: CharacterBody3D = null

var _ui_layer: CanvasLayer
var _dialog_panel: PanelContainer
var _gold_label: Label
var _voucher_label: Label
var _voucher_count_label: Label
var _gold_cost_label: Label
var _message_label: Label

var _buy_vouchers_amount: int = 1
var _font_chinese: Font
var _font_glitch: Font


func _ready() -> void:
	if ResourceLoader.exists(FONT_CHINESE):
		_font_chinese = load(FONT_CHINESE) as Font
	if ResourceLoader.exists(FONT_GLITCH):
		_font_glitch = load(FONT_GLITCH) as Font

	_build_merchant_visuals()
	_build_trigger()
	_build_ui()


func _build_merchant_visuals() -> void:
	# Name & Prompt Label
	_name_label = Label3D.new()
	_name_label.text = "★ 灰烬商贩 · 艾尔兰 ★"
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.position.y = 2.4
	_name_label.font_size = 28
	_name_label.outline_size = 8
	_name_label.modulate = Color(1.0, 0.85, 0.3)
	add_child(_name_label)

	_prompt_label = Label3D.new()
	_prompt_label.text = "[E] 交互交易"
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.position.y = 2.05
	_prompt_label.font_size = 24
	_prompt_label.outline_size = 6
	_prompt_label.visible = false
	add_child(_prompt_label)


func _build_trigger() -> void:
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 1

	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 2.5
	cyl.height = 2.5
	col.shape = cyl
	col.position.y = 1.2
	_area.add_child(col)
	add_child(_area)

	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)


func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 10
	add_child(_ui_layer)

	_dialog_panel = PanelContainer.new()
	_dialog_panel.set_anchors_preset(Control.PRESET_CENTER)
	_dialog_panel.offset_left = -300
	_dialog_panel.offset_right = 300
	_dialog_panel.offset_top = -220
	_dialog_panel.offset_bottom = 220
	_dialog_panel.custom_minimum_size = Vector2(600, 440)
	_dialog_panel.visible = false

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.07, 0.08, 0.11, 0.95)
	bg_style.border_width_left = 2
	bg_style.border_width_top = 2
	bg_style.border_width_right = 2
	bg_style.border_width_bottom = 2
	bg_style.border_color = Color(1.0, 0.78, 0.28, 0.8)
	bg_style.corner_radius_top_left = 10
	bg_style.corner_radius_top_right = 10
	bg_style.corner_radius_bottom_left = 10
	bg_style.corner_radius_bottom_right = 10
	bg_style.content_margin_left = 24
	bg_style.content_margin_right = 24
	bg_style.content_margin_top = 20
	bg_style.content_margin_bottom = 20
	_dialog_panel.add_theme_stylebox_override("panel", bg_style)
	_ui_layer.add_child(_dialog_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	_dialog_panel.add_child(vbox)

	# Title header
	var title_box := HBoxContainer.new()
	vbox.add_child(title_box)

	var title := Label.new()
	title.text = "灰烬秘契商舍 · 艾尔兰"
	if _font_chinese != null:
		title.add_theme_font_override("font", _font_chinese)
	title.add_theme_font_size_override("font_size", 26)
	title.modulate = Color(1.0, 0.85, 0.3)
	title_box.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = " ✕ "
	close_btn.pressed.connect(_close_dialog)
	title_box.add_child(close_btn)

	var subtitle := Label.new()
	subtitle.text = "「凡尘铸币，亦可炼为烬土通行之契。」"
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.modulate = Color(0.7, 0.75, 0.82)
	vbox.add_child(subtitle)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Balance display
	var balance_row := HBoxContainer.new()
	balance_row.add_theme_constant_override("separation", 24)
	vbox.add_child(balance_row)

	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", 18)
	_gold_label.modulate = Color(1.0, 0.9, 0.4)
	balance_row.add_child(_gold_label)

	_voucher_label = Label.new()
	_voucher_label.add_theme_font_size_override("font_size", 18)
	_voucher_label.modulate = Color(0.3, 0.9, 1.0)
	balance_row.add_child(_voucher_label)

	# Exchange Panel
	var ex_box := VBoxContainer.new()
	ex_box.add_theme_constant_override("separation", 10)
	vbox.add_child(ex_box)

	var rate_hint := Label.new()
	rate_hint.text = "兑换牌价: 100 金币 ➔ 1 灰烬凭证"
	rate_hint.add_theme_font_size_override("font_size", 15)
	rate_hint.modulate = Color(0.9, 0.9, 0.9)
	ex_box.add_child(rate_hint)

	var count_row := HBoxContainer.new()
	count_row.add_theme_constant_override("separation", 10)
	ex_box.add_child(count_row)

	var lbl_tag := Label.new()
	lbl_tag.text = "兑换凭证数量:"
	lbl_tag.add_theme_font_size_override("font_size", 16)
	count_row.add_child(lbl_tag)

	var btn_m10 := Button.new()
	btn_m10.text = "-10"
	btn_m10.pressed.connect(func(): _adjust_amount(-10))
	count_row.add_child(btn_m10)

	var btn_m1 := Button.new()
	btn_m1.text = "-1"
	btn_m1.pressed.connect(func(): _adjust_amount(-1))
	count_row.add_child(btn_m1)

	_voucher_count_label = Label.new()
	_voucher_count_label.custom_minimum_size = Vector2(60, 0)
	_voucher_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_voucher_count_label.add_theme_font_size_override("font_size", 20)
	_voucher_count_label.modulate = Color(0.3, 0.9, 1.0)
	count_row.add_child(_voucher_count_label)

	var btn_p1 := Button.new()
	btn_p1.text = "+1"
	btn_p1.pressed.connect(func(): _adjust_amount(1))
	count_row.add_child(btn_p1)

	var btn_p10 := Button.new()
	btn_p10.text = "+10"
	btn_p10.pressed.connect(func(): _adjust_amount(10))
	count_row.add_child(btn_p10)

	var btn_max := Button.new()
	btn_max.text = "最大 (MAX)"
	btn_max.pressed.connect(_set_max_amount)
	count_row.add_child(btn_max)

	_gold_cost_label = Label.new()
	_gold_cost_label.add_theme_font_size_override("font_size", 16)
	_gold_cost_label.modulate = Color(1.0, 0.6, 0.4)
	ex_box.add_child(_gold_cost_label)

	# Message feedback label
	_message_label = Label.new()
	_message_label.add_theme_font_size_override("font_size", 14)
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_message_label)

	# Action Row
	var act_row := HBoxContainer.new()
	act_row.add_theme_constant_override("separation", 16)
	vbox.add_child(act_row)

	var btn_debug_gold := Button.new()
	btn_debug_gold.text = "🪙 增资测试 (+500金币)"
	btn_debug_gold.pressed.connect(_on_debug_add_gold)
	act_row.add_child(btn_debug_gold)

	var act_spacer := Control.new()
	act_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	act_row.add_child(act_spacer)

	var btn_confirm := Button.new()
	btn_confirm.text = " 确认兑换 (Exchange) "
	btn_confirm.custom_minimum_size = Vector2(160, 40)
	btn_confirm.add_theme_font_size_override("font_size", 16)
	btn_confirm.pressed.connect(_on_confirm_exchange)
	act_row.add_child(btn_confirm)

	_refresh_ui_labels()


func _get_profile() -> Node:
	if has_node("/root/ProfileManager"):
		return get_node("/root/ProfileManager")
	return null


func _refresh_ui_labels() -> void:
	var prof := _get_profile()
	var cur_gold := 1000
	var cur_vouchers := 0
	if prof != null:
		cur_gold = prof.gold
		cur_vouchers = prof.ember_vouchers

	if _gold_label != null:
		_gold_label.text = "🪙 当前金币: %d" % cur_gold
	if _voucher_label != null:
		_voucher_label.text = "📜 灰烬凭证: %d" % cur_vouchers
	if _voucher_count_label != null:
		_voucher_count_label.text = str(_buy_vouchers_amount)
	if _gold_cost_label != null:
		var cost := _buy_vouchers_amount * EXCHANGE_RATE
		_gold_cost_label.text = "需消耗: %d 金币  ➔  获得: %d 灰烬凭证" % [cost, _buy_vouchers_amount]


func _adjust_amount(delta: int) -> void:
	_buy_vouchers_amount = maxi(1, _buy_vouchers_amount + delta)
	_refresh_ui_labels()


func _set_max_amount() -> void:
	var prof := _get_profile()
	var cur_gold := 1000
	if prof != null:
		cur_gold = prof.gold
	var max_vouchers := int(cur_gold / EXCHANGE_RATE)
	_buy_vouchers_amount = maxi(1, max_vouchers)
	_refresh_ui_labels()


func _on_debug_add_gold() -> void:
	var prof := _get_profile()
	if prof != null:
		prof.add_gold(500)
	_message_label.text = "✓ 已添加 500 金币"
	_message_label.modulate = Color(0.4, 0.9, 0.4)
	_refresh_ui_labels()


func _on_confirm_exchange() -> void:
	var prof := _get_profile()
	var cost := _buy_vouchers_amount * EXCHANGE_RATE
	if prof == null:
		_message_label.text = "ProfileManager 尚未就绪"
		_message_label.modulate = Color(1.0, 0.4, 0.4)
		return

	if prof.gold < cost:
		_message_label.text = "✗ 金币不足！需要 %d 金币，当前仅有 %d" % [cost, prof.gold]
		_message_label.modulate = Color(1.0, 0.4, 0.4)
		return

	var success: bool = prof.exchange_gold_to_vouchers(cost, EXCHANGE_RATE)
	if success:
		_message_label.text = "✓ 成功兑换 %d 张灰烬凭证！" % _buy_vouchers_amount
		_message_label.modulate = Color(0.3, 0.95, 0.5)
		exchange_completed.emit(_buy_vouchers_amount, cost)
		_refresh_ui_labels()
	else:
		_message_label.text = "✗ 兑换失败"
		_message_label.modulate = Color(1.0, 0.4, 0.4)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and _dialog_panel != null and _dialog_panel.visible:
			_close_dialog()
			get_viewport().set_input_as_handled()
			return

		if event.keycode == KEY_E and _player_in_range != null:
			if _dialog_panel != null and not _dialog_panel.visible:
				_open_dialog()
				get_viewport().set_input_as_handled()


func _open_dialog() -> void:
	if _dialog_panel == null:
		return
	_message_label.text = ""
	_refresh_ui_labels()
	_dialog_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_dialog() -> void:
	if _dialog_panel == null:
		return
	_dialog_panel.visible = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		_player_in_range = body as CharacterBody3D
		if _prompt_label != null:
			_prompt_label.visible = true


func _on_body_exited(body: Node3D) -> void:
	if body == _player_in_range:
		_player_in_range = null
		if _prompt_label != null:
			_prompt_label.visible = false
		if _dialog_panel != null and _dialog_panel.visible:
			_close_dialog()
