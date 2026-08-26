extends Control
## Multiplayer LAN Lobby UI & Room Waiting Chamber.
## Supports hosting, direct IP joining, UDP beacon discovery, profile sync, and full-screen Room Chamber view.

const CHASE_MULTIPLAYER_SCENE := "res://scenes/player_client/chase_multiplayer.tscn"
const PVP_MULTIPLAYER_SCENE := "res://scenes/player_client/sword_pvp_multiplayer.tscn"
const TITLE_SCENE := "res://scenes/player_client/title_screen.tscn"
const FONT_PATH := "res://assets/Fonts/Long_Cang/LongCang-Regular.ttf"
const FONT_GLITCH_PATH := "res://assets/Fonts/Long_Cang,Rubik_Glitch/Rubik_Glitch/RubikGlitch-Regular.ttf"
const MapDataScript = preload("res://scripts/map_data.gd")
const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const HudKitScript = preload("res://scripts/ui/hud_kit.gd")

var _custom_font: Font = null
var _glitch_font: Font = null

# View 1: Browser / Matchmaker (Host or Join)
var _browser_view: Control
var _tab_host_btn: Button
var _tab_join_btn: Button
var _host_panel: VBoxContainer
var _join_panel: VBoxContainer

var _ip_info_label: Label
var _port_edit: LineEdit
var _role_runner_chk: CheckBox
var _role_chaser_chk: CheckBox
var _map_option_btn: OptionButton
var _mode_option_btn: OptionButton
var _role_row_lbl: Label
var _role_box: HBoxContainer
var _map_row_lbl: Label
var _join_status_lbl: Label
var _sync_wait := 0.0
var _host_start_listen_btn: Button

var _join_ip_edit: LineEdit
var _join_port_edit: LineEdit
var _join_direct_btn: Button
var _server_list: ItemList
var _refresh_discovery_btn: Button

# View 2: Room Waiting Chamber (Once in a room)
var _chamber_view: Control
var _chamber_title_lbl: Label
var _chamber_sub_lbl: Label
var _card_host: PanelContainer
var _card_remote: PanelContainer
var _host_avatar_holder: Control
var _host_name_lbl: Label
var _host_role_badge: TextureRect
var _host_role_name_lbl: Label

var _remote_avatar_holder: Control
var _remote_name_lbl: Label
var _remote_role_badge: TextureRect
var _remote_role_name_lbl: Label
var _remote_ready_status_lbl: Label
var _remote_ready_icon: TextureRect

var _is_in_chamber := false

var _chamber_ready_btn: Button
var _chamber_launch_btn: Button
var _chamber_leave_btn: Button
var _chamber_map_name_lbl: Label

var _available_maps: Array = []


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if ResourceLoader.exists(FONT_PATH):
		_custom_font = load(FONT_PATH) as Font
	if ResourceLoader.exists(FONT_GLITCH_PATH):
		_glitch_font = load(FONT_GLITCH_PATH) as Font

	NetworkManager.server_created.connect(_on_server_created)
	NetworkManager.connected_to_server.connect(_on_connected_to_server)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.lobby_status_updated.connect(_update_all_views)
	NetworkManager.game_start_synced.connect(_on_game_start_synced)

	# If returning from active match, stay inside the chamber
	if multiplayer.has_multiplayer_peer() and (NetworkManager.is_host or NetworkManager.connected_peer_id > 0):
		_is_in_chamber = true
		NetworkManager.is_ready_local = false
		NetworkManager.is_ready_remote = false
		NetworkManager.local_hero_locked = false
		NetworkManager.remote_hero_locked = false
	else:
		_is_in_chamber = false
		NetworkManager.close_network()

	_build_ui()
	_load_map_options()
	_apply_mode_visibility()
	_update_local_ip_display()
	_switch_tab(true)
	_update_all_views()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_back_pressed()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.05, 0.07, 0.98)
	add_child(bg)

	_build_browser_view()
	_build_chamber_view()


func _build_browser_view() -> void:
	_browser_view = Control.new()
	_browser_view.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_browser_view)

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	_browser_view.add_child(center)

	var main_box := PanelContainer.new()
	main_box.custom_minimum_size = Vector2(740, 530)
	var style := _create_9patch_style("res://assets/UI_assets/panel_exquisite.png", 50.0, 45.0, 50.0, 45.0, 28.0, 24.0, 28.0, 24.0)
	main_box.add_theme_stylebox_override("panel", style)
	center.add_child(main_box)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 16)
	main_box.add_child(root_vbox)

	# Header Title
	var title_hbox := HBoxContainer.new()
	title_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	title_hbox.add_theme_constant_override("separation", 12)
	root_vbox.add_child(title_hbox)

	var icon_tex := TextureRect.new()
	if ResourceLoader.exists("res://assets/UI_assets/wyvern.svg"):
		icon_tex.texture = load("res://assets/UI_assets/wyvern.svg")
	icon_tex.custom_minimum_size = Vector2(36, 36)
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.modulate = Color(0.25, 0.85, 1.0)
	title_hbox.add_child(icon_tex)

	var title_lbl := Label.new()
	title_lbl.text = "追缉模式 · 局域网与远程对决大厅"
	if _custom_font != null:
		title_lbl.add_theme_font_override("font", _custom_font)
	title_lbl.add_theme_font_size_override("font_size", 24)
	title_lbl.modulate = Color(0.3, 0.9, 1.0)
	title_hbox.add_child(title_lbl)

	# Tabs (Host vs Join)
	var tab_hbox := HBoxContainer.new()
	tab_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_hbox.add_theme_constant_override("separation", 20)
	root_vbox.add_child(tab_hbox)

	_tab_host_btn = Button.new()
	_tab_host_btn.text = "创建对决房间 (HOST)"
	_tab_host_btn.custom_minimum_size = Vector2(220, 38)
	_tab_host_btn.pressed.connect(func(): _switch_tab(true))
	tab_hbox.add_child(_tab_host_btn)

	_tab_join_btn = Button.new()
	_tab_join_btn.text = "加入对决房间 (JOIN)"
	_tab_join_btn.custom_minimum_size = Vector2(220, 38)
	_tab_join_btn.pressed.connect(func(): _switch_tab(false))
	tab_hbox.add_child(_tab_join_btn)

	# Content Area
	var content_area := PanelContainer.new()
	content_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var inner_style := StyleBoxFlat.new()
	inner_style.bg_color = Color(0.04, 0.05, 0.07, 0.5)
	inner_style.set_corner_radius_all(10)
	inner_style.content_margin_left = 16
	inner_style.content_margin_top = 14
	inner_style.content_margin_right = 16
	inner_style.content_margin_bottom = 14
	content_area.add_theme_stylebox_override("panel", inner_style)
	root_vbox.add_child(content_area)

	# Host Panel
	_host_panel = VBoxContainer.new()
	_host_panel.add_theme_constant_override("separation", 12)
	content_area.add_child(_host_panel)

	_ip_info_label = Label.new()
	_ip_info_label.text = "本机 IP 检测中..."
	_ip_info_label.modulate = Color(1.0, 0.85, 0.3)
	_ip_info_label.add_theme_font_size_override("font_size", 13)
	_host_panel.add_child(_ip_info_label)

	var host_grid := GridContainer.new()
	host_grid.columns = 2
	host_grid.add_theme_constant_override("h_separation", 16)
	host_grid.add_theme_constant_override("v_separation", 10)
	_host_panel.add_child(host_grid)

	var p_lbl := Label.new()
	p_lbl.text = "监听端口:"
	host_grid.add_child(p_lbl)
	_port_edit = LineEdit.new()
	_port_edit.text = "7777"
	_port_edit.custom_minimum_size = Vector2(140, 30)
	host_grid.add_child(_port_edit)

	var mode_lbl := Label.new()
	mode_lbl.text = "对战模式:"
	host_grid.add_child(mode_lbl)
	_mode_option_btn = OptionButton.new()
	_mode_option_btn.custom_minimum_size = Vector2(260, 32)
	_mode_option_btn.add_item("追缉逃生 (Chase)", NetworkManager.GameMode.CHASE)
	_mode_option_btn.add_item("刀剑决斗 (Sword PVP)", NetworkManager.GameMode.SWORD_PVP)
	_mode_option_btn.item_selected.connect(_on_mode_selected)
	host_grid.add_child(_mode_option_btn)

	var r_lbl := Label.new()
	r_lbl.text = "房主身份:"
	host_grid.add_child(r_lbl)
	var role_box := HBoxContainer.new()
	role_box.add_theme_constant_override("separation", 20)
	host_grid.add_child(role_box)
	_role_row_lbl = r_lbl
	_role_box = role_box

	var bgroup := ButtonGroup.new()
	_role_runner_chk = CheckBox.new()
	_role_runner_chk.text = "逃生者 (Runner)"
	_role_runner_chk.button_group = bgroup
	_role_runner_chk.button_pressed = true
	_role_runner_chk.toggled.connect(func(on): if on: NetworkManager.set_host_role(NetworkManager.Role.RUNNER))
	role_box.add_child(_role_runner_chk)

	_role_chaser_chk = CheckBox.new()
	_role_chaser_chk.text = "追缉者 (Chaser)"
	_role_chaser_chk.button_group = bgroup
	_role_chaser_chk.toggled.connect(func(on): if on: NetworkManager.set_host_role(NetworkManager.Role.CHASER))
	role_box.add_child(_role_chaser_chk)

	var m_lbl := Label.new()
	m_lbl.text = "对战地图:"
	host_grid.add_child(m_lbl)
	_map_row_lbl = m_lbl
	_map_option_btn = OptionButton.new()
	_map_option_btn.custom_minimum_size = Vector2(260, 32)
	_map_option_btn.item_selected.connect(_on_map_selected)
	host_grid.add_child(_map_option_btn)

	_host_start_listen_btn = Button.new()
	_host_start_listen_btn.text = "创建房间并广播 (CREATE ROOM)"
	_host_start_listen_btn.custom_minimum_size = Vector2(260, 40)
	_host_start_listen_btn.pressed.connect(_on_create_host_pressed)
	_host_panel.add_child(_host_start_listen_btn)

	# Join Panel
	_join_panel = VBoxContainer.new()
	_join_panel.add_theme_constant_override("separation", 10)
	_join_panel.visible = false
	content_area.add_child(_join_panel)

	var direct_hbox := HBoxContainer.new()
	direct_hbox.add_theme_constant_override("separation", 10)
	_join_panel.add_child(direct_hbox)

	var ip_lbl := Label.new()
	ip_lbl.text = "目标 IP:"
	direct_hbox.add_child(ip_lbl)
	_join_ip_edit = LineEdit.new()
	_join_ip_edit.text = "127.0.0.1"
	_join_ip_edit.placeholder_text = "输入房主 IP (局域网/Tailscale)"
	_join_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	direct_hbox.add_child(_join_ip_edit)

	var port_lbl := Label.new()
	port_lbl.text = "端口:"
	direct_hbox.add_child(port_lbl)
	_join_port_edit = LineEdit.new()
	_join_port_edit.text = "7777"
	_join_port_edit.custom_minimum_size = Vector2(70, 30)
	direct_hbox.add_child(_join_port_edit)

	_join_direct_btn = Button.new()
	_join_direct_btn.text = "IP直连"
	_join_direct_btn.custom_minimum_size = Vector2(90, 32)
	_join_direct_btn.pressed.connect(_on_join_direct_pressed)
	direct_hbox.add_child(_join_direct_btn)

	_join_status_lbl = Label.new()
	_join_status_lbl.text = ""
	_join_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_join_status_lbl.add_theme_font_size_override("font_size", 13)
	_join_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_join_panel.add_child(_join_status_lbl)

	var disc_hbox := HBoxContainer.new()
	disc_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_join_panel.add_child(disc_hbox)
	var disc_lbl := Label.new()
	disc_lbl.text = "局域网自动发现房间列表 (点击加入):"
	disc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	disc_lbl.modulate = Color(0.3, 0.9, 1.0)
	disc_hbox.add_child(disc_lbl)
	_refresh_discovery_btn = Button.new()
	_refresh_discovery_btn.text = "刷新列表"
	_refresh_discovery_btn.pressed.connect(func(): NetworkManager.start_discovery_listener(); _update_discovered_servers_list())
	disc_hbox.add_child(_refresh_discovery_btn)

	_server_list = ItemList.new()
	_server_list.custom_minimum_size = Vector2(0, 110)
	_server_list.item_activated.connect(_on_server_item_activated)
	_join_panel.add_child(_server_list)

	# Bottom Bar
	var back_btn := Button.new()
	back_btn.text = "返回主界面 (ESC)"
	back_btn.custom_minimum_size = Vector2(140, 36)
	back_btn.pressed.connect(_on_back_pressed)
	root_vbox.add_child(back_btn)


func _build_chamber_view() -> void:
	_chamber_view = Control.new()
	_chamber_view.set_anchors_preset(PRESET_FULL_RECT)
	_chamber_view.visible = false
	add_child(_chamber_view)

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	_chamber_view.add_child(center)

	var main_box := PanelContainer.new()
	main_box.custom_minimum_size = Vector2(860, 540)
	var style := _create_9patch_style("res://assets/UI_assets/panel_exquisite.png", 50.0, 45.0, 50.0, 45.0, 28.0, 24.0, 28.0, 24.0)
	main_box.add_theme_stylebox_override("panel", style)
	center.add_child(main_box)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 18)
	main_box.add_child(root_vbox)

	# Top Room Header
	var top_box := VBoxContainer.new()
	top_box.alignment = BoxContainer.ALIGNMENT_CENTER
	top_box.add_theme_constant_override("separation", 2)
	root_vbox.add_child(top_box)

	_chamber_title_lbl = Label.new()
	_chamber_title_lbl.text = "对决准备室 (BATTLE CHAMBER)"
	_chamber_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _glitch_font != null:
		_chamber_title_lbl.add_theme_font_override("font", _glitch_font)
	_chamber_title_lbl.add_theme_font_size_override("font_size", 22)
	_chamber_title_lbl.modulate = Color(0.3, 0.85, 1.0)
	top_box.add_child(_chamber_title_lbl)

	_chamber_sub_lbl = Label.new()
	_chamber_sub_lbl.text = "双方确认就绪后，由房主发车启动对决"
	_chamber_sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chamber_sub_lbl.add_theme_font_size_override("font_size", 13)
	_chamber_sub_lbl.modulate = Color(0.7, 0.75, 0.85, 0.75)
	top_box.add_child(_chamber_sub_lbl)

	# Middle VS Cards Area
	var vs_hbox := HBoxContainer.new()
	vs_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vs_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vs_hbox.add_theme_constant_override("separation", 24)
	root_vbox.add_child(vs_hbox)

	# Card 1: Host Card
	_card_host = _build_player_card(true)
	vs_hbox.add_child(_card_host)

	# Center VS & Map Info
	var center_info := VBoxContainer.new()
	center_info.alignment = BoxContainer.ALIGNMENT_CENTER
	center_info.custom_minimum_size = Vector2(180, 0)
	center_info.add_theme_constant_override("separation", 10)
	vs_hbox.add_child(center_info)

	var vs_lbl := Label.new()
	vs_lbl.text = "VS"
	vs_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _glitch_font != null:
		vs_lbl.add_theme_font_override("font", _glitch_font)
	vs_lbl.add_theme_font_size_override("font_size", 48)
	vs_lbl.modulate = Color(1.0, 0.35, 0.25)
	center_info.add_child(vs_lbl)

	var map_tag := Label.new()
	map_tag.text = "对战地图"
	map_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_tag.add_theme_font_size_override("font_size", 12)
	map_tag.modulate = Color(0.6, 0.65, 0.75)
	center_info.add_child(map_tag)

	_chamber_map_name_lbl = Label.new()
	_chamber_map_name_lbl.text = "默认平地"
	_chamber_map_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _custom_font != null:
		_chamber_map_name_lbl.add_theme_font_override("font", _custom_font)
	_chamber_map_name_lbl.add_theme_font_size_override("font_size", 16)
	_chamber_map_name_lbl.modulate = Color(1.0, 0.85, 0.3)
	center_info.add_child(_chamber_map_name_lbl)

	# Card 2: Remote Card
	_card_remote = _build_player_card(false)
	vs_hbox.add_child(_card_remote)

	# Bottom Action Bar
	var bot_hbox := HBoxContainer.new()
	bot_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	bot_hbox.add_theme_constant_override("separation", 24)
	root_vbox.add_child(bot_hbox)

	_chamber_ready_btn = Button.new()
	_chamber_ready_btn.text = "准备就绪 (READY)"
	_chamber_ready_btn.custom_minimum_size = Vector2(160, 44)
	_chamber_ready_btn.pressed.connect(_on_toggle_ready_pressed)
	bot_hbox.add_child(_chamber_ready_btn)

	_chamber_launch_btn = Button.new()
	_chamber_launch_btn.text = "发车对战 (LAUNCH BATTLE)"
	_chamber_launch_btn.custom_minimum_size = Vector2(200, 44)
	_chamber_launch_btn.modulate = Color(0.3, 1.0, 0.5)
	_chamber_launch_btn.pressed.connect(_on_host_launch_pressed)
	bot_hbox.add_child(_chamber_launch_btn)

	_chamber_leave_btn = Button.new()
	_chamber_leave_btn.text = "离开房间 (LEAVE)"
	_chamber_leave_btn.custom_minimum_size = Vector2(130, 44)
	_chamber_leave_btn.pressed.connect(_on_disconnect_pressed)
	bot_hbox.add_child(_chamber_leave_btn)


func _build_player_card(is_host_slot: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(260, 260)
	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color(0.07, 0.09, 0.13, 0.85)
	p_style.set_corner_radius_all(14)
	p_style.set_border_width_all(2)
	p_style.border_color = Color(0.25, 0.85, 1.0, 0.4) if is_host_slot else Color(0.3, 0.4, 0.5, 0.3)
	p_style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", p_style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title_tag := Label.new()
	title_tag.text = "👑 房主 (HOST)" if is_host_slot else "⚔️ 挑战者 (PEER)"
	title_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_tag.add_theme_font_size_override("font_size", 12)
	title_tag.modulate = Color(1.0, 0.85, 0.3) if is_host_slot else Color(0.3, 0.85, 1.0)
	vbox.add_child(title_tag)

	var av_holder := Control.new()
	av_holder.custom_minimum_size = Vector2(72, 72)
	vbox.add_child(av_holder)
	if is_host_slot:
		_host_avatar_holder = av_holder
	else:
		_remote_avatar_holder = av_holder

	var name_lbl := Label.new()
	name_lbl.text = "选手昵称"
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _custom_font != null:
		name_lbl.add_theme_font_override("font", _custom_font)
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.modulate = Color(1.0, 0.95, 0.8)
	vbox.add_child(name_lbl)
	if is_host_slot:
		_host_name_lbl = name_lbl
	else:
		_remote_name_lbl = name_lbl

	var role_hbox := HBoxContainer.new()
	role_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	role_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(role_hbox)

	var r_icon := TextureRect.new()
	r_icon.custom_minimum_size = Vector2(24, 24)
	r_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	role_hbox.add_child(r_icon)

	var r_lbl := Label.new()
	r_lbl.text = "逃生者"
	r_lbl.add_theme_font_size_override("font_size", 14)
	role_hbox.add_child(r_lbl)

	if is_host_slot:
		_host_role_badge = r_icon
		_host_role_name_lbl = r_lbl
	else:
		_remote_role_badge = r_icon
		_remote_role_name_lbl = r_lbl

	if not is_host_slot:
		var status_box := HBoxContainer.new()
		status_box.alignment = BoxContainer.ALIGNMENT_CENTER
		status_box.add_theme_constant_override("separation", 6)
		vbox.add_child(status_box)

		_remote_ready_icon = TextureRect.new()
		_remote_ready_icon.custom_minimum_size = Vector2(20, 20)
		_remote_ready_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_remote_ready_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		status_box.add_child(_remote_ready_icon)

		_remote_ready_status_lbl = Label.new()
		_remote_ready_status_lbl.text = "未就绪"
		_remote_ready_status_lbl.add_theme_font_size_override("font_size", 13)
		status_box.add_child(_remote_ready_status_lbl)

	return panel


func _update_all_views() -> void:
	var in_room := _is_in_chamber and multiplayer.has_multiplayer_peer()
	_browser_view.visible = not in_room
	_chamber_view.visible = in_room

	if not in_room:
		_update_discovered_servers_list()
		return

	# Update Chamber Elements
	var mode_tag := "刀剑决斗" if NetworkManager.game_mode == NetworkManager.GameMode.SWORD_PVP else "追缉逃生"
	var map_tag_txt := NetworkManager.selected_map_path.get_file().get_basename() if not NetworkManager.selected_map_path.is_empty() else "默认平地地图"
	_chamber_map_name_lbl.text = "%s · %s" % [mode_tag, map_tag_txt]

	var host_name := NetworkManager.local_player_name if NetworkManager.is_host else NetworkManager.remote_player_name
	var host_av_type := NetworkManager.local_avatar_type if NetworkManager.is_host else NetworkManager.remote_avatar_type
	var host_av_key := NetworkManager.local_avatar_key if NetworkManager.is_host else NetworkManager.remote_avatar_key
	var host_is_runner := (NetworkManager.local_role == NetworkManager.Role.RUNNER) if NetworkManager.is_host else (NetworkManager.remote_role == NetworkManager.Role.RUNNER)

	_host_name_lbl.text = host_name
	for c in _host_avatar_holder.get_children():
		c.queue_free()
	_host_avatar_holder.add_child(ProfileManager.create_avatar_circle(72.0, host_av_type, host_av_key, Color(1.0, 0.85, 0.2)))

	if host_is_runner:
		_apply_role_badge(_host_role_name_lbl, _host_role_badge, true)
	else:
		_apply_role_badge(_host_role_name_lbl, _host_role_badge, false)

	# Remote Peer slot
	var peer_connected := (NetworkManager.connected_peer_id > 0)
	var peer_name := NetworkManager.remote_player_name if NetworkManager.is_host else NetworkManager.local_player_name
	var peer_av_type := NetworkManager.remote_avatar_type if NetworkManager.is_host else NetworkManager.local_avatar_type
	var peer_av_key := NetworkManager.remote_avatar_key if NetworkManager.is_host else NetworkManager.local_avatar_key
	var peer_is_runner := not host_is_runner

	_remote_name_lbl.text = peer_name if peer_connected else "等待对手加入..."
	for c in _remote_avatar_holder.get_children():
		c.queue_free()
	if peer_connected:
		_remote_avatar_holder.add_child(ProfileManager.create_avatar_circle(72.0, peer_av_type, peer_av_key, Color(0.3, 0.85, 1.0)))
	else:
		var empty_disc := Panel.new()
		empty_disc.set_anchors_preset(PRESET_FULL_RECT)
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.1, 0.12, 0.16, 0.5)
		s.set_corner_radius_all(36)
		empty_disc.add_theme_stylebox_override("panel", s)
		_remote_avatar_holder.add_child(empty_disc)

	if not peer_connected:
		_remote_role_name_lbl.text = "待分配 (PENDING)"
		_remote_role_name_lbl.modulate = Color(0.6, 0.65, 0.75, 0.6)
		_remote_role_badge.texture = load("res://assets/UI_assets/extra-time.svg")
		_remote_role_badge.modulate = Color(0.6, 0.65, 0.75, 0.6)
	else:
		_apply_role_badge(_remote_role_name_lbl, _remote_role_badge, peer_is_runner)

	if _remote_ready_status_lbl != null:
		if not peer_connected:
			_remote_ready_status_lbl.text = "虚位以待..."
			_remote_ready_status_lbl.modulate = Color(0.6, 0.65, 0.75, 0.5)
			_remote_ready_icon.texture = load("res://assets/UI_assets/extra-time.svg")
			_remote_ready_icon.modulate = Color(0.6, 0.65, 0.75, 0.5)
		else:
			var is_ready := NetworkManager.is_ready_remote if NetworkManager.is_host else NetworkManager.is_ready_local
			if is_ready:
				_remote_ready_status_lbl.text = "已就绪 (READY)"
				_remote_ready_status_lbl.modulate = Color(0.3, 1.0, 0.5)
				_remote_ready_icon.texture = load("res://assets/UI_assets/check-mark.svg")
				_remote_ready_icon.modulate = Color(0.3, 1.0, 0.5)
			else:
				_remote_ready_status_lbl.text = "准备中 (WAITING)"
				_remote_ready_status_lbl.modulate = Color(1.0, 0.85, 0.3)
				_remote_ready_icon.texture = load("res://assets/UI_assets/extra-time.svg")
				_remote_ready_icon.modulate = Color(1.0, 0.85, 0.3)

	# Action Buttons
	if NetworkManager.is_host:
		_chamber_ready_btn.visible = false
		_chamber_launch_btn.visible = true
		_chamber_launch_btn.disabled = not (peer_connected and NetworkManager.is_ready_remote)
	else:
		_chamber_ready_btn.visible = true
		_chamber_ready_btn.text = "取消就绪 (CANCEL)" if NetworkManager.is_ready_local else "确认就绪 (READY)"
		_chamber_launch_btn.visible = false


## Paints one player card's role slot. Sword PVP is symmetric: both sides read 决斗者.
func _apply_role_badge(name_lbl: Label, badge: TextureRect, is_runner: bool) -> void:
	if name_lbl == null or badge == null:
		return
	if NetworkManager.game_mode == NetworkManager.GameMode.SWORD_PVP:
		name_lbl.text = "决斗者 (DUELIST)"
		name_lbl.modulate = Color(1.0, 0.82, 0.35)
		badge.texture = load("res://assets/UI_assets/winged-sword.svg")
		badge.modulate = Color(1.0, 0.82, 0.35)
	elif is_runner:
		name_lbl.text = "逃生者 (RUNNER)"
		name_lbl.modulate = Color(0.3, 1.0, 0.5)
		badge.texture = load("res://assets/UI_assets/running-shoe.svg")
		badge.modulate = Color(0.3, 1.0, 0.5)
	else:
		name_lbl.text = "追缉者 (CHASER)"
		name_lbl.modulate = Color(1.0, 0.35, 0.25)
		badge.texture = load("res://assets/UI_assets/wyvern.svg")
		badge.modulate = Color(1.0, 0.35, 0.25)


func _switch_tab(is_host_tab: bool) -> void:
	_host_panel.visible = is_host_tab
	_join_panel.visible = not is_host_tab
	_tab_host_btn.modulate = Color(0.3, 0.9, 1.0) if is_host_tab else Color(0.7, 0.7, 0.7)
	_tab_join_btn.modulate = Color(0.3, 0.9, 1.0) if not is_host_tab else Color(0.7, 0.7, 0.7)
	if not is_host_tab:
		NetworkManager.start_discovery_listener()


func _load_map_options() -> void:
	_map_option_btn.clear()
	_available_maps = MapDataScript.list_available_maps()
	_map_option_btn.add_item("默认平地地图 (Default Flat Map)")
	_map_option_btn.set_item_metadata(0, "")
	for i in range(_available_maps.size()):
		var m: Dictionary = _available_maps[i]
		var display_name := "%s (%s)" % [m.get("name", "未命名"), m.get("file_name", "map")]
		_map_option_btn.add_item(display_name)
		_map_option_btn.set_item_metadata(i + 1, m.get("path", ""))
	_map_option_btn.select(0)


func _on_map_selected(idx: int) -> void:
	var path: String = str(_map_option_btn.get_item_metadata(idx))
	NetworkManager.set_host_map(path)


## _on_mode_selected(): host picks match type. Post: NetworkManager.game_mode synced to client.
func _on_mode_selected(idx: int) -> void:
	NetworkManager.set_host_mode(_mode_option_btn.get_item_id(idx) as NetworkManager.GameMode)
	_apply_mode_visibility()


## Sword PVP is symmetric and uses its own fixed arena: role and map rows do not apply.
func _apply_mode_visibility() -> void:
	if _mode_option_btn == null:
		return
	var is_pvp := _mode_option_btn.get_selected_id() == int(NetworkManager.GameMode.SWORD_PVP)
	if _role_row_lbl != null:
		_role_row_lbl.visible = not is_pvp
	if _role_box != null:
		_role_box.visible = not is_pvp
	if _map_row_lbl != null:
		_map_row_lbl.visible = not is_pvp
	if _map_option_btn != null:
		_map_option_btn.visible = not is_pvp


func _update_local_ip_display() -> void:
	var raw_ips := IP.get_local_addresses()
	var wifi_ips: Array[String] = []
	var tailscale_ips: Array[String] = []
	var other_ips: Array[String] = []

	for ip_str in raw_ips:
		if ip_str.find(":") != -1 or ip_str == "127.0.0.1" or ip_str.begins_with("169.254"):
			continue
		if ip_str.begins_with("192.168.") or ip_str.begins_with("10."):
			wifi_ips.append(ip_str)
		elif ip_str.begins_with("100."):
			tailscale_ips.append(ip_str)
		else:
			other_ips.append(ip_str)

	var lines: Array[String] = []
	if not wifi_ips.is_empty():
		lines.append("📶 局域网/Wi-Fi IP (同网络联机): %s" % ", ".join(wifi_ips))
	if not tailscale_ips.is_empty():
		lines.append("🌐 异地组网/Tailscale IP (远程联机): %s" % ", ".join(tailscale_ips))
	if lines.is_empty():
		if not other_ips.is_empty():
			lines.append("🖥️ 适配器 IP: %s" % ", ".join(other_ips))
		else:
			lines.append("🖥️ 本机 IP: 127.0.0.1 (单机双开测试)")

	_ip_info_label.text = "\n".join(lines)


func _on_create_host_pressed() -> void:
	var port := int(_port_edit.text)
	if port <= 0:
		port = NetworkManager.DEFAULT_PORT
	var role: NetworkManager.Role = NetworkManager.Role.RUNNER if _role_runner_chk.button_pressed else NetworkManager.Role.CHASER
	var map_path := str(_map_option_btn.get_selected_metadata())
	var mode: NetworkManager.GameMode = _mode_option_btn.get_selected_id() as NetworkManager.GameMode
	var err := NetworkManager.create_host(port, role, map_path, mode)
	if err == OK:
		_is_in_chamber = true
		_update_all_views()
	else:
		_host_start_listen_btn.text = "创建失败 (错误码 %d) · 端口可能被占用" % err
		_host_start_listen_btn.modulate = Color(1.0, 0.4, 0.35)


## Join never enters the chamber optimistically: create_client() only opens a socket.
## The chamber opens from _on_connected_to_server(); failure/timeout reports back here.
func _on_join_direct_pressed() -> void:
	var ip := _join_ip_edit.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	var port := int(_join_port_edit.text)
	if port <= 0:
		port = NetworkManager.DEFAULT_PORT
	var err := NetworkManager.join_game(ip, port)
	if err == OK:
		_set_join_status("⏳ 正在连接 %s:%d ..." % [ip, port], Color(1.0, 0.85, 0.35))
		_join_direct_btn.disabled = true
	else:
		_set_join_status("❌ 无法创建连接 (错误码 %d)，请检查端口是否被占用" % err, Color(1.0, 0.4, 0.35))
	_update_all_views()


func _set_join_status(msg: String, tint: Color) -> void:
	if _join_status_lbl == null:
		return
	_join_status_lbl.text = msg
	_join_status_lbl.modulate = tint


func _on_server_item_activated(idx: int) -> void:
	var key = _server_list.get_item_metadata(idx)
	if key != null and NetworkManager.discovered_servers.has(key):
		var info: Dictionary = NetworkManager.discovered_servers[key]
		var ip: String = info.get("ip", "127.0.0.1")
		var port: int = int(info.get("port", NetworkManager.DEFAULT_PORT))
		_join_ip_edit.text = ip
		_join_port_edit.text = str(port)
		_on_join_direct_pressed()


func _update_discovered_servers_list() -> void:
	_server_list.clear()
	for k in NetworkManager.discovered_servers:
		var d: Dictionary = NetworkManager.discovered_servers[k]
		var is_pvp: bool = int(d.get("mode", 0)) == int(NetworkManager.GameMode.SWORD_PVP)
		var text := ""
		if is_pvp:
			text = "%s (刀剑决斗)" % k
		else:
			var r_str := "逃生者" if d.get("role", 0) == 0 else "追缉者"
			text = "%s (追缉逃生 | 房主: %s | 地图: %s)" % [k, r_str, d.get("map", "默认")]
		_server_list.add_item(text)
		# Metadata holds the raw "ip:port" key; the display text is decorated and must not be parsed back.
		_server_list.set_item_metadata(_server_list.item_count - 1, k)


func _on_toggle_ready_pressed() -> void:
	NetworkManager.set_local_ready(not NetworkManager.is_ready_local)


func _on_host_launch_pressed() -> void:
	if not NetworkManager.is_host or not NetworkManager.is_ready_remote:
		return
	NetworkManager.start_multiplayer_match()


func _on_game_start_synced(_map_path: String, _host_role_val: int) -> void:
	if NetworkManager.game_mode == NetworkManager.GameMode.SWORD_PVP:
		SceneLoader.change_scene(get_tree(), PVP_MULTIPLAYER_SCENE, "双方就绪！正在同步载入刀剑决斗场...")
	else:
		SceneLoader.change_scene(get_tree(), CHASE_MULTIPLAYER_SCENE, "双方就绪！正在同步载入追缉战场...")


func _on_disconnect_pressed() -> void:
	_is_in_chamber = false
	NetworkManager.close_network()
	_update_all_views()


func _on_back_pressed() -> void:
	_is_in_chamber = false
	NetworkManager.close_network()
	SceneLoader.change_scene(get_tree(), TITLE_SCENE, "返回主界面...")


func _on_server_created() -> void:
	_is_in_chamber = true
	_update_all_views()


func _on_connected_to_server() -> void:
	_is_in_chamber = true
	_sync_wait = 0.0
	_join_direct_btn.disabled = false
	_set_join_status("✅ 已连接房主", Color(0.35, 1.0, 0.5))
	_update_all_views()


func _on_connection_failed() -> void:
	_is_in_chamber = false
	_join_direct_btn.disabled = false
	_set_join_status("❌ 连接失败或超时。请确认：房主已点击「创建房间」· IP/端口正确 · 双方防火墙放行 UDP 7777 · 两台机器运行同一版本代码",
		Color(1.0, 0.4, 0.35))
	_update_all_views()


func _on_server_disconnected() -> void:
	_is_in_chamber = false
	_join_direct_btn.disabled = false
	_set_join_status("⚠ 与房主的连接已断开", Color(1.0, 0.65, 0.3))
	_update_all_views()


## Connected but no profile RPC arriving means the two builds disagree on RPC ids.
func _process(delta: float) -> void:
	if not _is_in_chamber or NetworkManager.is_host or _chamber_sub_lbl == null:
		return
	if NetworkManager.remote_profile_synced:
		return
	_sync_wait += delta
	if _sync_wait > 5.0:
		_chamber_sub_lbl.text = "⚠ 已连上房主但房间信息同步失败 —— 两台机器的代码版本很可能不一致，请同步后重试"
		_chamber_sub_lbl.modulate = Color(1.0, 0.6, 0.25)


func _create_9patch_style(texture_path: String, ml: float, mt: float, mr: float, mb: float, cl: float = 16.0, ct: float = 14.0, cr: float = 16.0, cb: float = 14.0) -> StyleBoxTexture:
	return HudKitScript.nine_patch(texture_path, ml, mt, mr, mb, cl, ct, cr, cb)
