class_name ManorMerchant
extends Node3D

signal exchange_completed(amount_vouchers: int, gold_spent: int)

const FONT_CHINESE := "res://assets/Fonts/Long_Cang/LongCang-Regular.ttf"
const FONT_GLITCH := "res://assets/Fonts/Long_Cang,Rubik_Glitch/Rubik_Glitch/RubikGlitch-Regular.ttf"
const MERCHANT_SCENE := "res://assets/characters/cunning_merchant/cunning_merchant.tscn"
const EXCHANGE_RATE := 100 # 100 Gold = 1 Ember Voucher
const VOICE_BASE_DIR := "res://assets/voice/merchant_voice/"

const VOICE_BANK := {
	"greeting": [
		{
			"file": "可莉-2026-08-22-23-44-快来看快来看！可莉的超级杂货铺开张啦.mp3",
			"text": "快来看快来看！可莉的超级杂货铺开张啦！"
		},
		{
			"file": "可莉-2026-08-23-00-02-我爱二币！我爱二币！大哥哥大姐姐不要误会哦，这真的不是在骂人，是凯亚哥哥教可莉念的招财口号，他说.mp3",
			"text": "我爱二币！我爱二币！这真的不是在骂人，是凯亚哥哥教的招财口号哦～"
		},
	],
	"interact": [
		{
			"file": "可莉-2026-08-22-23-59-哒哒哒～只要先偷偷标贵四分之一，然后再假装亏本大甩卖打八折，客人买得高兴，可莉也拿到了想要的摩拉.mp3",
			"text": "哒哒哒～只要假装亏本大甩卖打八折，客人买得高兴，可莉也拿到摩拉～"
		},
		{
			"file": "可莉-2026-08-22-23-44-快来看快来看！可莉的超级杂货铺开张啦.mp3",
			"text": "快来看快来看！可莉的超级杂货铺开张啦！"
		},
	],
	"exchange": [
		{
			"file": "可莉-2026-08-22-23-55-嘿嘿，其实可莉刚才偷偷把价格算贵了一点点，因为真的很想买超甜的落落莓大棒棒糖吃嘛！.mp3",
			"text": "嘿嘿，其实可莉偷偷把价格算贵了一点点，因为想买超甜的大棒棒糖吃嘛！"
		},
	],
	"cancel": [
		{
			"file": "可莉-2026-08-22-23-46-唔……好吧，肯定是可莉要价太高了，早知道就说只要咬一小口小蛋糕就可以换了嘛.mp3",
			"text": "唔……好吧，肯定是可莉要价太高了，早知道说咬一小口小蛋糕就能换了嘛。"
		},
	],
	"leave": [
		{
			"file": "可莉-2026-08-22-23-50-嘟嘟可，收摊收摊！既然没人买，那今天可莉的杂货铺就宣布提早下班啦！.mp3",
			"text": "嘟嘟可，收摊收摊！既然没人买，今天可莉的杂货铺宣布提早下班啦！"
		},
	]
}

var _merchant_character: Character = null
var _voice_player: AudioStreamPlayer3D = null
var _subtitle_label: Label3D = null
var _subtitle_hide_time: float = 0.0
var _last_voice_time: float = -999.0
var _last_played_file: String = ""
var _has_traded_in_session: bool = false
var _has_opened_dialog_in_session: bool = false

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


func _process(_delta: float) -> void:
	if _subtitle_label != null and _subtitle_label.visible:
		if float(Time.get_ticks_msec()) * 0.001 >= _subtitle_hide_time:
			_subtitle_label.visible = false


func _build_merchant_visuals() -> void:
	if ResourceLoader.exists(MERCHANT_SCENE):
		var scn := load(MERCHANT_SCENE) as PackedScene
		if scn != null:
			_merchant_character = scn.instantiate() as Character
			if _merchant_character != null:
				add_child(_merchant_character)
				_merchant_character.rotation = Vector3.ZERO
				if _merchant_character.has_clip("anims/idle"):
					_merchant_character.play("anims/idle")

	_voice_player = AudioStreamPlayer3D.new()
	_voice_player.name = "MerchantVoice"
	_voice_player.max_distance = 35.0
	_voice_player.unit_size = 5.5
	_voice_player.volume_db = 6.0
	_voice_player.bus = "Master"
	_voice_player.position = Vector3(0.0, 1.6, 0.0)
	_voice_player.finished.connect(_on_voice_finished)
	add_child(_voice_player)

	_name_label = Label3D.new()
	_name_label.text = "★ 灰烬商贩 · 艾尔兰 ★"
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.position.y = 2.2
	_name_label.font_size = 28
	_name_label.outline_size = 8
	_name_label.modulate = Color(1.0, 0.85, 0.3)
	add_child(_name_label)

	_prompt_label = Label3D.new()
	_prompt_label.text = "[E] 交互交易"
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.position.y = 1.9
	_prompt_label.font_size = 24
	_prompt_label.outline_size = 6
	_prompt_label.visible = false
	add_child(_prompt_label)

	_subtitle_label = Label3D.new()
	_subtitle_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_subtitle_label.position.y = 2.55
	_subtitle_label.font_size = 18
	_subtitle_label.outline_size = 6
	_subtitle_label.modulate = Color(1.0, 0.95, 0.65)
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_label.width = 280.0
	_subtitle_label.visible = false
	if _font_chinese != null:
		_subtitle_label.font = _font_chinese
	add_child(_subtitle_label)


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
		_has_traded_in_session = true
		_message_label.text = "✓ 成功兑换 %d 张灰烬凭证！" % _buy_vouchers_amount
		_message_label.modulate = Color(0.3, 0.95, 0.5)
		if _merchant_character != null and _merchant_character.has_clip("anims/yes"):
			_merchant_character.play("anims/yes", 0.1)
		play_merchant_voice("exchange", true)
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
	_has_opened_dialog_in_session = true
	_message_label.text = ""
	_refresh_ui_labels()
	_dialog_panel.visible = true
	play_merchant_voice("interact", true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_dialog() -> void:
	if _dialog_panel == null:
		return
	_dialog_panel.visible = false
	if not _has_traded_in_session:
		play_merchant_voice("cancel", false)
	elif _merchant_character != null and _merchant_character.has_clip("anims/idle"):
		_merchant_character.play("anims/idle", 0.2)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		_player_in_range = body as CharacterBody3D
		_has_traded_in_session = false
		_has_opened_dialog_in_session = false
		if _prompt_label != null:
			_prompt_label.visible = true
		play_merchant_voice("greeting")


func _on_body_exited(body: Node3D) -> void:
	if body == _player_in_range:
		_player_in_range = null
		if _prompt_label != null:
			_prompt_label.visible = false
		if _dialog_panel != null and _dialog_panel.visible:
			_close_dialog()
		if not _has_traded_in_session and not _has_opened_dialog_in_session:
			play_merchant_voice("leave", false)


## Plays random contextual voice line based on player action.
func play_merchant_voice(category: String, force: bool = false) -> void:
	var now := float(Time.get_ticks_msec()) * 0.001
	if not force and now - _last_voice_time < 3.5:
		return
	if not force and _voice_player != null and _voice_player.playing:
		return

	var list: Array = VOICE_BANK.get(category, [])
	if list.is_empty():
		return

	var candidates := list.duplicate()
	if candidates.size() > 1:
		candidates = candidates.filter(func(item): return item.file != _last_played_file)
	if candidates.is_empty():
		candidates = list

	var chosen: Dictionary = candidates[randi() % candidates.size()]
	var file_name: String = chosen.file
	var full_path := VOICE_BASE_DIR.path_join(file_name)
	var text: String = chosen.get("text", "")

	if not ResourceLoader.exists(full_path):
		return
	var stream := load(full_path) as AudioStream
	if stream == null:
		return

	_last_voice_time = now
	_last_played_file = file_name

	if _voice_player != null:
		_voice_player.stop()
		_voice_player.stream = stream
		_voice_player.play()

	if _merchant_character != null and _merchant_character.has_clip("anims/idle_talking"):
		_merchant_character.play("anims/idle_talking", 0.2)

	if _subtitle_label != null and not text.is_empty():
		_subtitle_label.text = "「%s」" % text
		_subtitle_label.visible = true
		var duration: float = stream.get_length() if stream.has_method("get_length") else 4.0
		_subtitle_hide_time = now + maxf(duration + 1.0, 3.5)


func _on_voice_finished() -> void:
	if _dialog_panel == null or not _dialog_panel.visible:
		if _merchant_character != null and _merchant_character.has_clip("anims/idle"):
			_merchant_character.play("anims/idle", 0.2)
