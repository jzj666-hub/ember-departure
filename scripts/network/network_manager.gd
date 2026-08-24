extends Node
## Network Manager for 1v1 LAN/P2P pursuit chase mode.
## Manages ENetMultiplayerPeer, LAN discovery beacons, role assignments, and scene transitions.

signal server_created
signal connected_to_server
signal connection_failed
signal server_disconnected
signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal lobby_status_updated
signal game_start_synced(map_path: String, host_role: int)

enum Role {
	RUNNER = 0,
	CHASER = 1,
}

## Match type. Decides which battle scene hero_select launches. Host-authoritative.
enum GameMode {
	CHASE = 0,
	SWORD_PVP = 1,
}

const DEFAULT_PORT := 7777
const BROADCAST_PORT := 7778
const BROADCAST_INTERVAL := 1.0
const DISCOVERY_TIMEOUT := 3.0
## ENet gives no failure signal for an unreachable host; this bounds the wait.
const CONNECT_TIMEOUT := 8.0

const MapDataScript = preload("res://scripts/map_data.gd")

var peer: ENetMultiplayerPeer = null
var is_host := false
var local_role: Role = Role.RUNNER
var remote_role: Role = Role.CHASER
var game_mode: GameMode = GameMode.CHASE
var selected_map_path := ""
var selected_map_data: Dictionary = {}
var is_ready_local := false
var is_ready_remote := false
var connected_peer_id := -1
## True between join_game() and the handshake resolving. Invariant: never true while connected_peer_id > 0.
var is_connecting := false
## True once the peer's profile RPC has actually landed. False here + connected == version/RPC mismatch.
var remote_profile_synced := false
var _connect_elapsed := 0.0

var local_player_name := "灰烬行者"
var local_avatar_type := "builtin"
var local_avatar_key := "avatar_01_01.png"
var remote_player_name := "等待对手入场..."
var remote_avatar_type := "builtin"
var remote_avatar_key := "avatar_01_01.png"

var local_hero_scene := "res://assets/characters/hero_1/hero_1.tscn"
var remote_hero_scene := "res://assets/characters/hero_2/hero_2.tscn"
var local_hero_locked := false
var remote_hero_locked := false

signal hero_selection_changed(is_local: bool, hero_scene: String, is_locked: bool)

# UDP Beacon Discovery
var _broadcast_timer := 0.0
var _udp_server: PacketPeerUDP = null
var _udp_listener: PacketPeerUDP = null
var discovered_servers: Dictionary = {} # IP:Port -> { name, map, host_role, time }


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	if is_connecting:
		_connect_elapsed += delta
		if _connect_elapsed >= CONNECT_TIMEOUT:
			_connect_elapsed = 0.0
			is_connecting = false
			connection_failed.emit()
			close_network()
			return

	if is_host and _udp_server != null:
		_broadcast_timer += delta
		if _broadcast_timer >= BROADCAST_INTERVAL:
			_broadcast_timer = 0.0
			_send_broadcast_beacon()

	if not is_host and _udp_listener != null:
		_poll_discovery_listener()


func create_host(port: int = DEFAULT_PORT, role: Role = Role.RUNNER, map_path: String = "", mode: GameMode = GameMode.CHASE) -> Error:
	close_network()
	if ProfileManager != null:
		local_player_name = ProfileManager.player_name
		local_avatar_type = ProfileManager.avatar_type
		local_avatar_key = ProfileManager.avatar_key

	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 2)
	if err != OK:
		return err

	multiplayer.multiplayer_peer = peer
	is_host = true
	local_role = role
	game_mode = mode
	remote_role = Role.CHASER if role == Role.RUNNER else Role.RUNNER
	selected_map_path = map_path
	if not map_path.is_empty() and FileAccess.file_exists(map_path):
		selected_map_data = MapDataScript.load_map_from_file(map_path)
	else:
		selected_map_data = {}
	is_ready_local = false
	is_ready_remote = false
	connected_peer_id = -1
	remote_player_name = "等待对手入场..."

	_start_udp_beacon_server(port)
	server_created.emit()
	return OK


func join_game(ip: String, port: int = DEFAULT_PORT) -> Error:
	close_network()
	if ProfileManager != null:
		local_player_name = ProfileManager.player_name
		local_avatar_type = ProfileManager.avatar_type
		local_avatar_key = ProfileManager.avatar_key

	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err

	multiplayer.multiplayer_peer = peer
	is_host = false
	is_ready_local = false
	is_ready_remote = false
	# Handshake pending: connected_peer_id stays -1 until connected_to_server fires,
	# so the lobby cannot show a room that does not exist yet.
	connected_peer_id = -1
	is_connecting = true
	remote_profile_synced = false
	_connect_elapsed = 0.0
	remote_player_name = "正在连接房主..."
	return OK


func close_network() -> void:
	_stop_udp_discovery()
	if peer != null:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null
	is_host = false
	is_ready_local = false
	is_ready_remote = false
	connected_peer_id = -1
	is_connecting = false
	remote_profile_synced = false
	_connect_elapsed = 0.0
	selected_map_data = {}
	remote_player_name = "等待对手入场..."


func set_local_ready(ready_state: bool) -> void:
	is_ready_local = ready_state
	if multiplayer.has_multiplayer_peer() and connected_peer_id > 0:
		rpc("rpc_sync_ready", ready_state)
	lobby_status_updated.emit()


func set_host_role(role: Role) -> void:
	if not is_host:
		return
	local_role = role
	remote_role = Role.CHASER if role == Role.RUNNER else Role.RUNNER
	if multiplayer.has_multiplayer_peer() and connected_peer_id > 0:
		rpc("rpc_sync_host_role", int(role))
	lobby_status_updated.emit()


## set_host_mode(): host-only match type change. Post: remote game_mode mirrors host.
func set_host_mode(mode: GameMode) -> void:
	if not is_host:
		return
	game_mode = mode
	if multiplayer.has_multiplayer_peer() and connected_peer_id > 0:
		rpc("rpc_sync_host_mode", int(mode))
	lobby_status_updated.emit()


func set_host_map(map_path: String) -> void:
	if not is_host:
		return
	selected_map_path = map_path
	if not map_path.is_empty() and FileAccess.file_exists(map_path):
		selected_map_data = MapDataScript.load_map_from_file(map_path)
	else:
		selected_map_data = {}
	if multiplayer.has_multiplayer_peer() and connected_peer_id > 0:
		rpc("rpc_sync_host_map", map_path)
	lobby_status_updated.emit()


func start_multiplayer_match() -> void:
	if not is_host:
		return
	if not selected_map_path.is_empty() and FileAccess.file_exists(selected_map_path):
		selected_map_data = MapDataScript.load_map_from_file(selected_map_path)
	rpc("rpc_start_hero_select", selected_map_path, selected_map_data, int(local_role), int(game_mode))


# --- RPCs -------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_sync_profile(p_name: String, av_type: String, av_key: String) -> void:
	remote_player_name = p_name
	remote_avatar_type = av_type
	remote_avatar_key = av_key
	remote_profile_synced = true
	lobby_status_updated.emit()

@rpc("any_peer", "call_remote", "reliable")
func rpc_sync_ready(ready_state: bool) -> void:
	is_ready_remote = ready_state
	lobby_status_updated.emit()


@rpc("authority", "call_remote", "reliable")
func rpc_sync_host_role(role_val: int) -> void:
	var h_role := role_val as Role
	if is_host:
		return
	remote_role = h_role
	local_role = Role.CHASER if h_role == Role.RUNNER else Role.RUNNER
	lobby_status_updated.emit()


@rpc("authority", "call_remote", "reliable")
func rpc_sync_host_map(map_path: String) -> void:
	selected_map_path = map_path
	lobby_status_updated.emit()


@rpc("authority", "call_remote", "reliable")
func rpc_sync_host_mode(mode_val: int) -> void:
	if is_host:
		return
	game_mode = mode_val as GameMode
	lobby_status_updated.emit()


@rpc("authority", "call_local", "reliable")
func rpc_start_match(map_path: String, map_data_dict: Dictionary, host_role_val: int) -> void:
	selected_map_path = map_path
	selected_map_data = map_data_dict
	var h_role := host_role_val as Role
	if not is_host:
		remote_role = h_role
		local_role = Role.CHASER if h_role == Role.RUNNER else Role.RUNNER
	_stop_udp_discovery()
	game_start_synced.emit(map_path, host_role_val)


# --- Peer Signals -----------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	connected_peer_id = id
	player_connected.emit(id)
	if is_host:
		rpc_id(id, "rpc_sync_profile", local_player_name, local_avatar_type, local_avatar_key)
		rpc_id(id, "rpc_sync_host_role", int(local_role))
		rpc_id(id, "rpc_sync_host_map", selected_map_path)
		rpc_id(id, "rpc_sync_host_mode", int(game_mode))
		rpc_id(id, "rpc_sync_ready", is_ready_local)
	lobby_status_updated.emit()


func _on_peer_disconnected(id: int) -> void:
	if connected_peer_id == id:
		connected_peer_id = -1
		is_ready_remote = false
		remote_profile_synced = false
		remote_player_name = "等待对手入场..."
	player_disconnected.emit(id)
	lobby_status_updated.emit()


func _on_connected_to_server() -> void:
	connected_peer_id = 1
	is_connecting = false
	_connect_elapsed = 0.0
	remote_player_name = "房主 (信息同步中...)"
	rpc("rpc_sync_profile", local_player_name, local_avatar_type, local_avatar_key)
	connected_to_server.emit()
	lobby_status_updated.emit()


func _on_connection_failed() -> void:
	connected_peer_id = -1
	is_connecting = false
	_connect_elapsed = 0.0
	connection_failed.emit()
	close_network()


func _on_server_disconnected() -> void:
	connected_peer_id = -1
	server_disconnected.emit()
	close_network()


# --- UDP Discovery ----------------------------------------------------------

func start_discovery_listener() -> void:
	_stop_udp_discovery()
	discovered_servers.clear()
	_udp_listener = PacketPeerUDP.new()
	_udp_listener.bind(BROADCAST_PORT)


func _start_udp_beacon_server(_host_game_port: int) -> void:
	_stop_udp_discovery()
	_udp_server = PacketPeerUDP.new()
	_udp_server.set_broadcast_enabled(true)
	_udp_server.set_dest_address("255.255.255.255", BROADCAST_PORT)


func _send_broadcast_beacon() -> void:
	if _udp_server == null:
		return
	var dict := {
		"tag": "EMBER_CHASE",
		"port": DEFAULT_PORT,
		"role": int(local_role),
		"mode": int(game_mode),
		"map": selected_map_path.get_file().get_basename(),
		"time": Time.get_unix_time_from_system()
	}
	var json_str := JSON.stringify(dict)
	_udp_server.put_packet(json_str.to_utf8_buffer())


func _poll_discovery_listener() -> void:
	if _udp_listener == null:
		return
	while _udp_listener.get_available_packet_count() > 0:
		var pkt := _udp_listener.get_packet()
		var ip := _udp_listener.get_packet_ip()
		var _port := _udp_listener.get_packet_port()
		var json_str := pkt.get_string_from_utf8()
		var parsed = JSON.parse_string(json_str)
		if parsed is Dictionary and parsed.get("tag") == "EMBER_CHASE":
			var key := "%s:%d" % [ip, int(parsed.get("port", DEFAULT_PORT))]
			parsed["ip"] = ip
			parsed["seen_time"] = Time.get_unix_time_from_system()
			discovered_servers[key] = parsed

	# Prune stale beacons (> 4 seconds)
	var now := Time.get_unix_time_from_system()
	var keys_to_remove := []
	for k in discovered_servers:
		if now - discovered_servers[k].get("seen_time", now) > 4.0:
			keys_to_remove.append(k)
	for k in keys_to_remove:
		discovered_servers.erase(k)


func _stop_udp_discovery() -> void:
	if _udp_server != null:
		_udp_server.close()
		_udp_server = null
	if _udp_listener != null:
		_udp_listener.close()
		_udp_listener = null


@rpc("any_peer", "call_local", "reliable")
func rpc_start_hero_select(map_p: String = "", map_d: Dictionary = {}, host_r: int = 0, mode_v: int = 0) -> void:
	if not is_host:
		selected_map_path = map_p
		selected_map_data = map_d
		game_mode = mode_v as GameMode
		var h_role := host_r as Role
		remote_role = h_role
		local_role = Role.CHASER if h_role == Role.RUNNER else Role.RUNNER
	local_hero_locked = false
	remote_hero_locked = false
	SceneLoader.change_scene(get_tree(), "res://scenes/player_client/hero_select.tscn", "正在进入英雄出战选角舞台...")


@rpc("any_peer", "call_local", "reliable")
func rpc_sync_hero_pick(hero_scene_path: String, is_locked: bool) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	var is_local := (sender_id == multiplayer.get_unique_id())
	if is_local:
		local_hero_scene = hero_scene_path
		local_hero_locked = is_locked
	else:
		remote_hero_scene = hero_scene_path
		remote_hero_locked = is_locked
	hero_selection_changed.emit(is_local, hero_scene_path, is_locked)
