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

const DEFAULT_PORT := 7777
const BROADCAST_PORT := 7778
const BROADCAST_INTERVAL := 1.0
const DISCOVERY_TIMEOUT := 3.0

var peer: ENetMultiplayerPeer = null
var is_host := false
var local_role: Role = Role.RUNNER
var remote_role: Role = Role.CHASER
var selected_map_path := ""
var is_ready_local := false
var is_ready_remote := false
var connected_peer_id := -1

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
	if is_host and _udp_server != null:
		_broadcast_timer += delta
		if _broadcast_timer >= BROADCAST_INTERVAL:
			_broadcast_timer = 0.0
			_send_broadcast_beacon()

	if not is_host and _udp_listener != null:
		_poll_discovery_listener()


func create_host(port: int = DEFAULT_PORT, role: Role = Role.RUNNER, map_path: String = "") -> Error:
	close_network()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 2)
	if err != OK:
		return err

	multiplayer.multiplayer_peer = peer
	is_host = true
	local_role = role
	remote_role = Role.CHASER if role == Role.RUNNER else Role.RUNNER
	selected_map_path = map_path
	is_ready_local = false
	is_ready_remote = false
	connected_peer_id = -1

	_start_udp_beacon_server(port)
	server_created.emit()
	return OK


func join_game(ip: String, port: int = DEFAULT_PORT) -> Error:
	close_network()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err

	multiplayer.multiplayer_peer = peer
	is_host = false
	is_ready_local = false
	is_ready_remote = false
	connected_peer_id = 1
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


func set_local_ready(ready: bool) -> void:
	is_ready_local = ready
	if multiplayer.has_multiplayer_peer() and connected_peer_id > 0:
		rpc("rpc_sync_ready", ready)
	lobby_status_updated.emit()


func set_host_role(role: Role) -> void:
	if not is_host:
		return
	local_role = role
	remote_role = Role.CHASER if role == Role.RUNNER else Role.RUNNER
	if multiplayer.has_multiplayer_peer() and connected_peer_id > 0:
		rpc("rpc_sync_host_role", int(role))
	lobby_status_updated.emit()


func set_host_map(map_path: String) -> void:
	if not is_host:
		return
	selected_map_path = map_path
	if multiplayer.has_multiplayer_peer() and connected_peer_id > 0:
		rpc("rpc_sync_host_map", map_path)
	lobby_status_updated.emit()


func start_multiplayer_match() -> void:
	if not is_host:
		return
	rpc("rpc_start_match", selected_map_path, int(local_role))


# --- RPCs -------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_sync_ready(ready: bool) -> void:
	is_ready_remote = ready
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


@rpc("authority", "call_local", "reliable")
func rpc_start_match(map_path: String, host_role_val: int) -> void:
	selected_map_path = map_path
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
		rpc_id(id, "rpc_sync_host_role", int(local_role))
		rpc_id(id, "rpc_sync_host_map", selected_map_path)
		rpc_id(id, "rpc_sync_ready", is_ready_local)
	lobby_status_updated.emit()


func _on_peer_disconnected(id: int) -> void:
	if connected_peer_id == id:
		connected_peer_id = -1
		is_ready_remote = false
	player_disconnected.emit(id)
	lobby_status_updated.emit()


func _on_connected_to_server() -> void:
	connected_peer_id = 1
	connected_to_server.emit()
	lobby_status_updated.emit()


func _on_connection_failed() -> void:
	connected_peer_id = -1
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


func _start_udp_beacon_server(host_game_port: int) -> void:
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
		var port := _udp_listener.get_packet_port()
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
