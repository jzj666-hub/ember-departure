extends Control
## Multiplayer LAN Lobby UI.
## Supports hosting, joining, UDP beacon discovery, role selection, map picking, and match launch.

const CHASE_MULTIPLAYER_SCENE := "res://scenes/player_client/chase_multiplayer.tscn"
const TITLE_SCENE := "res://scenes/player_client/title_screen.tscn"
const FONT_PATH := "res://assets/Fonts/Long_Cang/LongCang-Regular.ttf"
const MapDataScript = preload("res://scripts/map_data.gd")
const AudioManagerScript = preload("res://scripts/audio_manager.gd")

var _custom_font: Font = null
var _main_box: PanelContainer
var _tab_host_btn: Button
var _tab_join_btn: Button
var _host_panel: VBoxContainer
var _join_panel: VBoxContainer

# Host controls
var _ip_info_label: Label
var _port_edit: LineEdit
var _role_runner_chk: CheckBox
var _role_chaser_chk: CheckBox
var _map_option_btn: OptionButton
var _host_start_listen_btn: Button

# Join controls
var _join_ip_edit: LineEdit
var _join_port_edit: LineEdit
var _join_direct_btn: Button
var _server_list: ItemList
var _refresh_discovery_btn: Button

# Lobby status / Ready bar
var _lobby_status_panel: PanelContainer
var _status_info_label: Label
var _local_ready_btn: Button
var _host_launch_btn: Button
var _disconnect_btn: Button

var _available_maps: Array = []


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if ResourceLoader.exists(FONT_PATH):
		_custom_font = load(FONT_PATH) as Font

	NetworkManager.server_created.connect(_on_server_created)
	NetworkManager.connected_to_server.connect(_on_connected_to_server)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.lobby_status_updated.connect(_update_lobby_status_ui)
	NetworkManager.game_start_synced.connect(_on_game_start_synced)

	_build_ui()
	_load_map_options()
	_update_local_ip_display()
	_switch_tab(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_back_pressed()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.06, 0.08, 0.96)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)

	_main_box = PanelContainer.new()
	_main_box.custom_minimum_size = Vector2(720, 520)
	var style := _create_9patch_style("res://assets/UI_assets/panel_exquisite.png", 50.0, 45.0, 50.0, 45.0, 28.0, 24.0, 28.0, 24.0)
	_main_box.add_theme_stylebox_override("panel", style)
	center.add_child(_main_box)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 16)
	_main_box.add_child(root_vbox)

	# Header Title
	var title_hbox := HBoxContainer.new()
	title_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	title_hbox.add_theme_constant_override("separation", 12)
	root_vbox.add_child(title_hbox)

	var icon_tex := TextureRect.new()
	if ResourceLoader.exists("res://assets/UI_assets/daemon-skull.svg"):
		icon_tex.texture = load("res://assets/UI_assets/daemon-skull.svg")
	icon_tex.custom_minimum_size = Vector2(36, 36)
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.modulate = Color(0.25, 0.85, 1.0)
	title_hbox.add_child(icon_tex)

	var title_lbl := Label.new()
	title_lbl.text = "🌐 追缉模式 · 局域网联机对决大厅"
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
	_tab_host_btn.text = "👑 我要创建房间 (Host)"
	_tab_host_btn.custom_minimum_size = Vector2(220, 38)
	_tab_host_btn.pressed.connect(func(): _switch_tab(true))
	tab_hbox.add_child(_tab_host_btn)

	_tab_join_btn = Button.new()
	_tab_join_btn.text = "⚔️ 加入他人房间 (Join)"
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
	_ip_info_label.text = "本机局域网 IP: 获取中..."
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

	var r_lbl := Label.new()
	r_lbl.text = "房主身份:"
	host_grid.add_child(r_lbl)
	var role_box := HBoxContainer.new()
	role_box.add_theme_constant_override("separation", 20)
	host_grid.add_child(role_box)

	var bgroup := ButtonGroup.new()
	_role_runner_chk = CheckBox.new()
	_role_runner_chk.text = "🏃 逃生者 (Runner)"
	_role_runner_chk.button_group = bgroup
	_role_runner_chk.button_pressed = true
	_role_runner_chk.toggled.connect(func(on): if on: NetworkManager.set_host_role(NetworkManager.Role.RUNNER))
	role_box.add_child(_role_runner_chk)

	_role_chaser_chk = CheckBox.new()
	_role_chaser_chk.text = "👿 追缉者 (Chaser)"
	_role_chaser_chk.button_group = bgroup
	_role_chaser_chk.toggled.connect(func(on): if on: NetworkManager.set_host_role(NetworkManager.Role.CHASER))
	role_box.add_child(_role_chaser_chk)

	var m_lbl := Label.new()
	m_lbl.text = "对战地图:"
	host_grid.add_child(m_lbl)
	_map_option_btn = OptionButton.new()
	_map_option_btn.custom_minimum_size = Vector2(260, 32)
	_map_option_btn.item_selected.connect(_on_map_selected)
	host_grid.add_child(_map_option_btn)

	_host_start_listen_btn = Button.new()
	_host_start_listen_btn.text = "🚀 创建房间并广播等待加入"
	_host_start_listen_btn.custom_minimum_size = Vector2(260, 38)
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
	_join_direct_btn.text = "🔗 IP直连"
	_join_direct_btn.custom_minimum_size = Vector2(90, 32)
	_join_direct_btn.pressed.connect(_on_join_direct_pressed)
	direct_hbox.add_child(_join_direct_btn)

	var disc_hbox := HBoxContainer.new()
	disc_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_join_panel.add_child(disc_hbox)
	var disc_lbl := Label.new()
	disc_lbl.text = "📡 局域网自动发现房间列表 (点击直接加入):"
	disc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	disc_lbl.modulate = Color(0.3, 0.9, 1.0)
	disc_hbox.add_child(disc_lbl)
	_refresh_discovery_btn = Button.new()
	_refresh_discovery_btn.text = "🔄 刷新"
	_refresh_discovery_btn.pressed.connect(func(): NetworkManager.start_discovery_listener(); _update_discovered_servers_list())
	disc_hbox.add_child(_refresh_discovery_btn)

	_server_list = ItemList.new()
	_server_list.custom_minimum_size = Vector2(0, 110)
	_server_list.item_activated.connect(_on_server_item_activated)
	_join_panel.add_child(_server_list)

	# Bottom Status Bar & Ready Panel
	_lobby_status_panel = PanelContainer.new()
	var bot_style := StyleBoxFlat.new()
	bot_style.bg_color = Color(0.08, 0.10, 0.14, 0.8)
	bot_style.set_corner_radius_all(8)
	bot_style.content_margin_left = 12
	bot_style.content_margin_top = 8
	bot_style.content_margin_right = 12
	bot_style.content_margin_bottom = 8
	_lobby_status_panel.add_theme_stylebox_override("panel", bot_style)
	root_vbox.add_child(_lobby_status_panel)

	var bot_hbox := HBoxContainer.new()
	bot_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	bot_hbox.add_theme_constant_override("separation", 14)
	_lobby_status_panel.add_child(bot_hbox)

	_status_info_label = Label.new()
	_status_info_label.text = "未连接网络"
	_status_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_info_label.modulate = Color(0.8, 0.85, 0.9)
	bot_hbox.add_child(_status_info_label)

	_local_ready_btn = Button.new()
	_local_ready_btn.text = "✔ 准备就绪"
	_local_ready_btn.custom_minimum_size = Vector2(110, 36)
	_local_ready_btn.pressed.connect(_on_toggle_ready_pressed)
	_local_ready_btn.visible = false
	bot_hbox.add_child(_local_ready_btn)

	_host_launch_btn = Button.new()
	_host_launch_btn.text = "🔥 开始对战！"
	_host_launch_btn.custom_minimum_size = Vector2(130, 36)
	_host_launch_btn.modulate = Color(0.3, 1.0, 0.5)
	_host_launch_btn.pressed.connect(_on_host_launch_pressed)
	_host_launch_btn.visible = false
	bot_hbox.add_child(_host_launch_btn)

	_disconnect_btn = Button.new()
	_disconnect_btn.text = "❌ 断开/取消"
	_disconnect_btn.custom_minimum_size = Vector2(100, 36)
	_disconnect_btn.pressed.connect(_on_disconnect_pressed)
	_disconnect_btn.visible = false
	bot_hbox.add_child(_disconnect_btn)

	var back_btn := Button.new()
	back_btn.text = "返回主界面 (ESC)"
	back_btn.custom_minimum_size = Vector2(130, 36)
	back_btn.pressed.connect(_on_back_pressed)
	bot_hbox.add_child(back_btn)


func _process(_delta: float) -> void:
	if _join_panel != null and _join_panel.visible:
		_update_discovered_servers_list()


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
	_map_option_btn.add_item("默认空旷平地地图 (Default Flat Map)")
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

	_ip_info_label.text = "\n".join(lines) + "\n💡 提示: 同WiFi对手直接在'加入房间'列表点击即可; 异地联机请用Tailscale/ZeroTier虚拟IP"


func _on_create_host_pressed() -> void:
	var port := int(_port_edit.text)
	if port <= 0:
		port = NetworkManager.DEFAULT_PORT
	var role: NetworkManager.Role = NetworkManager.Role.RUNNER if _role_runner_chk.button_pressed else NetworkManager.Role.CHASER
	var map_path := str(_map_option_btn.get_selected_metadata())
	var err := NetworkManager.create_host(port, role, map_path)
	if err != OK:
		_status_info_label.text = "❌ 创建房间失败 (错误码: %d)，请检查端口占用" % err
		_status_info_label.modulate = Color(1.0, 0.4, 0.4)
		return
	_status_info_label.text = "👑 房间已创建！广播等待对手连接..."
	_status_info_label.modulate = Color(0.3, 1.0, 0.5)


func _on_join_direct_pressed() -> void:
	var ip := _join_ip_edit.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	var port := int(_join_port_edit.text)
	if port <= 0:
		port = NetworkManager.DEFAULT_PORT
	_status_info_label.text = "⏳ 正在连接目标主机 %s:%d..." % [ip, port]
	_status_info_label.modulate = Color(1.0, 0.85, 0.3)
	var err := NetworkManager.join_game(ip, port)
	if err != OK:
		_status_info_label.text = "❌ 连接发起失败: %d" % err
		_status_info_label.modulate = Color(1.0, 0.4, 0.4)


func _on_server_item_activated(idx: int) -> void:
	var key := _server_list.get_item_text(idx)
	if NetworkManager.discovered_servers.has(key):
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
		var r_str := "逃生者" if d.get("role", 0) == 0 else "追缉者"
		var text := "%s (房主身份: %s | 地图: %s)" % [k, r_str, d.get("map", "默认")]
		_server_list.add_item(text)


func _update_lobby_status_ui() -> void:
	var has_peer := multiplayer.has_multiplayer_peer()
	_disconnect_btn.visible = has_peer

	if not has_peer:
		_status_info_label.text = "未连接网络"
		_local_ready_btn.visible = false
		_host_launch_btn.visible = false
		_host_start_listen_btn.disabled = false
		return

	_host_start_listen_btn.disabled = true
	var role_str := "🏃 逃生者" if NetworkManager.local_role == NetworkManager.Role.RUNNER else "👿 追缉者"
	var opponent_role_str := "👿 追缉者" if NetworkManager.local_role == NetworkManager.Role.RUNNER else "🏃 逃生者"

	if NetworkManager.is_host:
		if NetworkManager.connected_peer_id <= 0:
			_status_info_label.text = "👑 [房主] 我的身份: %s | 等待对手加入中..." % role_str
			_status_info_label.modulate = Color(1.0, 0.85, 0.3)
			_local_ready_btn.visible = false
			_host_launch_btn.visible = false
		else:
			var opp_ready := "已就绪 ✔" if NetworkManager.is_ready_remote else "未就绪 ⏳"
			_status_info_label.text = "👑 [房主] 我的身份: %s | 对手(%s): %s" % [role_str, opponent_role_str, opp_ready]
			_status_info_label.modulate = Color(0.3, 1.0, 0.5) if NetworkManager.is_ready_remote else Color(1.0, 0.85, 0.3)
			_local_ready_btn.visible = false
			_host_launch_btn.visible = true
			_host_launch_btn.disabled = not NetworkManager.is_ready_remote
	else:
		var my_ready_str := "已就绪 ✔ (点击取消)" if NetworkManager.is_ready_local else "点击准备就绪"
		_status_info_label.text = "⚔️ [客机] 已连接房主！我的分配身份: %s | 状态: %s" % [role_str, "等待房主发车" if NetworkManager.is_ready_local else "请点击就绪"]
		_status_info_label.modulate = Color(0.3, 1.0, 0.5) if NetworkManager.is_ready_local else Color(1.0, 0.85, 0.3)
		_local_ready_btn.visible = true
		_local_ready_btn.text = my_ready_str
		_host_launch_btn.visible = false


func _on_toggle_ready_pressed() -> void:
	NetworkManager.set_local_ready(not NetworkManager.is_ready_local)


func _on_host_launch_pressed() -> void:
	if not NetworkManager.is_host or not NetworkManager.is_ready_remote:
		return
	NetworkManager.start_multiplayer_match()


func _on_game_start_synced(map_path: String, _host_role_val: int) -> void:
	SceneLoader.change_scene(get_tree(), CHASE_MULTIPLAYER_SCENE, "双方就绪！正在同步载入追缉战场...")


func _on_disconnect_pressed() -> void:
	NetworkManager.close_network()
	_update_lobby_status_ui()


func _on_back_pressed() -> void:
	NetworkManager.close_network()
	SceneLoader.change_scene(get_tree(), TITLE_SCENE, "返回主界面...")


func _on_server_created() -> void:
	_update_lobby_status_ui()


func _on_connected_to_server() -> void:
	_update_lobby_status_ui()


func _on_connection_failed() -> void:
	_status_info_label.text = "❌ 连接失败，无法连接至该目标主机！"
	_status_info_label.modulate = Color(1.0, 0.4, 0.4)
	_update_lobby_status_ui()


func _on_server_disconnected() -> void:
	_status_info_label.text = "⚠️ 与房主的网络连接已断开！"
	_status_info_label.modulate = Color(1.0, 0.4, 0.4)
	_update_lobby_status_ui()


func _create_9patch_style(texture_path: String, ml: float, mt: float, mr: float, mb: float, cl: float = 16.0, ct: float = 14.0, cr: float = 16.0, cb: float = 14.0) -> StyleBoxTexture:
	var sbox := StyleBoxTexture.new()
	if ResourceLoader.exists(texture_path):
		sbox.texture = load(texture_path)
	sbox.texture_margin_left = ml
	sbox.texture_margin_top = mt
	sbox.texture_margin_right = mr
	sbox.texture_margin_bottom = mb
	sbox.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sbox.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sbox.content_margin_left = cl
	sbox.content_margin_top = ct
	sbox.content_margin_right = cr
	sbox.content_margin_bottom = cb
	return sbox
