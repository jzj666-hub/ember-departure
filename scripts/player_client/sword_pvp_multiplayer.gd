extends "res://scripts/player_client/sword_pvp_game.gd"
## LAN 1v1 sword duel. Extends the AI duel scene: reuses arena, HUD, floaters, game-over flow.
## Authority: host owns HP + match clock. Hit detection is attacker-local (each peer tests only its own blade).
## Invariant: on BOTH peers _combat_mgr.player_hp == host fighter HP, _combat_mgr.ai_hp == client fighter HP.

const SnapshotInterpolatorScript = preload("res://scripts/network/snapshot_interpolator.gd")

const SNAPSHOT_INTERVAL := 0.033 # 30Hz
const PREPARE_TIME := 3.0
const PVP_BASE_DMG := 35.0
const HOST_SPAWN := Vector3(0.0, 0.8, 5.0)
const CLIENT_SPAWN := Vector3(0.0, 0.8, -5.0)

var _remote_interp: SnapshotInterpolator
var _snapshot_timer := 0.0
var _prepare_timer := PREPARE_TIME
var _last_prep_voice := -1
var _local_scene_ready := false
var _remote_scene_ready := false
var _fight_started := false
var _prev_stroke := 0
var _prev_state := 0


func _ready() -> void:
	super()
	_match_state = MatchState.PREPARE
	_apply_network_spawns()
	if _timer_lbl != null:
		_timer_lbl.text = "等待对手"
	_on_stats_changed()

	_local_scene_ready = true
	if multiplayer.has_multiplayer_peer():
		rpc("rpc_peer_scene_ready")
		if NetworkManager.is_host and _remote_scene_ready and not _fight_started:
			rpc("rpc_start_fight")
	else:
		rpc_start_fight() # solo fallback when the scene is opened without a peer


func _exit_tree() -> void:
	NetworkManager.close_network()


func _process(delta: float) -> void:
	if _remote_interp != null:
		_remote_interp.update_interpolation(delta)


func _physics_process(delta: float) -> void:
	match _match_state:
		MatchState.PREPARE:
			if _fight_started:
				_prepare_timer = maxf(0.0, _prepare_timer - delta)
				var sec := int(ceil(_prepare_timer))
				if sec > 0 and sec != _last_prep_voice:
					_last_prep_voice = sec
					AudioManagerScript.play_countdown(sec, true)
				if _dodge_banner != null:
					_dodge_banner.visible = true
					_dodge_banner.modulate.a = 1.0
					_dodge_banner.text = "决斗开始 %d" % maxi(sec, 1)
				if _prepare_timer <= 0.0:
					_begin_fighting()

		MatchState.FIGHTING:
			if NetworkManager.is_host:
				_match_timer = maxf(0.0, _match_timer - delta)
			_update_timer_label()

			if _combo_timer > 0.0:
				_combo_timer -= delta
				if _combo_timer <= 0.0:
					_combo_count = 0
					if _combo_lbl != null:
						_combo_lbl.visible = false

			_check_blade_hits()

			if _player_hp_lag_bar != null and _player_hp_bar != null:
				_player_hp_lag_bar.value = lerpf(_player_hp_lag_bar.value, _player_hp_bar.value, delta * 4.0)
			if _ai_hp_lag_bar != null and _ai_hp_bar != null:
				_ai_hp_lag_bar.value = lerpf(_ai_hp_lag_bar.value, _ai_hp_bar.value, delta * 4.0)

			if NetworkManager.is_host and _match_timer <= 0.0:
				rpc("rpc_match_over", _combat_mgr.player_hp >= _combat_mgr.ai_hp, "时间耗尽 · 血量高者判胜")
				return

	_send_anim_events()
	_pump_snapshots(delta)


func _update_timer_label() -> void:
	if _timer_lbl == null:
		return
	_timer_lbl.text = "%02d:%02d" % [int(_match_timer) / 60, int(_match_timer) % 60]


func _begin_fighting() -> void:
	_match_state = MatchState.FIGHTING
	if _dodge_banner != null:
		_dodge_banner.text = "开始!"
		var tw := create_tween()
		tw.tween_interval(0.4)
		tw.tween_property(_dodge_banner, "modulate:a", 0.0, 0.3)
		tw.chain().tween_callback(func() -> void: _dodge_banner.visible = false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- Fighters ----------------------------------------------------------------

## Overrides the AI build: fighter #2 is a network-interpolated body, not a bot.
func _build_characters() -> void:
	_camera = FollowCameraScript.new()
	_camera.fov = 55.0
	_camera.near = 0.05
	_camera.far = 200.0
	add_child(_camera)

	var chars: Array = CharacterPipelineScript.list_characters().filter(
		func(c: Dictionary) -> bool: return ResourceLoader.exists(c.scene))
	var i_host := NetworkManager.is_host

	# Local fighter
	_player = PlayerControllerScript.new()
	_player.name = "LocalFighter"
	_player.position = HOST_SPAWN if i_host else CLIENT_SPAWN
	_player.rotation.y = 0.0 if i_host else deg_to_rad(180.0)
	_player.intent_source = PlayerIntentSourceScript.new()
	add_child(_player)
	_player_visual = _spawn_hero_visual(_player, chars, true)

	var p_h: float = _player_visual.get("body_height") if _player_visual != null else 1.75
	_setup_capsule(_player, p_h)
	if _player_visual != null:
		_player.setup(_player_visual, _camera)

	_player_equip = EquipmentManagerScript.new()
	_player_equip.name = "PlayerEquip"
	_player.add_child(_player_equip)

	_camera.target = _player
	_camera.frame_for(p_h)
	_camera.snap()

	# Remote fighter: driven purely by snapshots, no physics, no input.
	_npc = PlayerControllerScript.new()
	_npc.name = "RemoteFighter"
	_npc.position = CLIENT_SPAWN if i_host else HOST_SPAWN
	_npc.rotation.y = deg_to_rad(180.0) if i_host else 0.0
	add_child(_npc)
	_npc_visual = _spawn_hero_visual(_npc, chars, false)

	var n_h: float = _npc_visual.get("body_height") if _npc_visual != null else 1.75
	_setup_capsule(_npc, n_h)
	if _npc_visual != null:
		_npc.setup(_npc_visual, null)
	_npc.set_physics_process(false)
	_npc.set_process_unhandled_input(false)

	_npc_equip = EquipmentManagerScript.new()
	_npc_equip.name = "NpcEquip"
	_npc.add_child(_npc_equip)

	_remote_interp = SnapshotInterpolatorScript.new()
	_remote_interp.setup(_npc)


## Loads the lobby-picked hero for one side. Falls back to the pipeline roster.
func _spawn_hero_visual(body: CharacterBody3D, chars: Array, is_local: bool) -> Node3D:
	var path := NetworkManager.local_hero_scene if is_local else NetworkManager.remote_hero_scene
	var scene: PackedScene = null
	if not path.is_empty() and ResourceLoader.exists(path):
		scene = load(path) as PackedScene
	if scene == null and not chars.is_empty():
		var idx := 0 if is_local else mini(1, chars.size() - 1)
		scene = load(chars[idx].scene) as PackedScene
	if scene == null:
		return null
	var visual := scene.instantiate() as Node3D
	body.add_child(visual)
	return visual


func _apply_network_spawns() -> void:
	var i_host := NetworkManager.is_host
	if _player != null:
		_player.global_position = HOST_SPAWN if i_host else CLIENT_SPAWN
		_player.rotation.y = 0.0 if i_host else deg_to_rad(180.0)
	if _npc != null:
		_npc.global_position = CLIENT_SPAWN if i_host else HOST_SPAWN
		_npc.rotation.y = deg_to_rad(180.0) if i_host else 0.0
	if _remote_interp != null:
		_remote_interp.clear()
	if _camera != null:
		_camera.snap()


# --- Snapshots & anim replication -------------------------------------------

func _pump_snapshots(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or _player == null:
		return
	_snapshot_timer += delta
	if _snapshot_timer < SNAPSHOT_INTERVAL:
		return
	_snapshot_timer = 0.0
	var snap := {
		"pos": _player.global_position,
		"yaw": _player.rotation.y,
		"vel": _player.velocity,
		"action": "",
		"state": int(_player.state),
	}
	if NetworkManager.is_host:
		snap["h_timer"] = _match_timer
	rpc("rpc_receive_snapshot", snap)


## Discrete anim replication: swings and rolls fire once per event, the rest rides the snapshot state.
func _send_anim_events() -> void:
	if not multiplayer.has_multiplayer_peer() or _player == null:
		return
	var strokes := _player.weapon_stroke_count()
	if strokes != _prev_stroke:
		_prev_stroke = strokes
		rpc("rpc_anim_swing", _player.current_weapon_action())
	var st := int(_player.state)
	if st != _prev_state:
		_prev_state = st
		if st == int(PlayerControllerScript.State.ROLLING):
			rpc("rpc_anim_roll")


@rpc("any_peer", "call_remote", "unreliable")
func rpc_receive_snapshot(snap: Dictionary) -> void:
	if _remote_interp != null:
		_remote_interp.push_snapshot(snap)
	if not NetworkManager.is_host and snap.has("h_timer"):
		_match_timer = float(snap["h_timer"])


@rpc("any_peer", "call_remote", "reliable")
func rpc_anim_swing(action_id: String) -> void:
	if _npc != null:
		_npc.force_network_swing(action_id)


@rpc("any_peer", "call_remote", "reliable")
func rpc_anim_roll() -> void:
	if _npc != null:
		_npc.force_network_action("roll", _npc.roll_rate)


# --- Match flow --------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func rpc_peer_scene_ready() -> void:
	_remote_scene_ready = true
	if NetworkManager.is_host and _local_scene_ready and not _fight_started:
		rpc("rpc_start_fight")


@rpc("authority", "call_local", "reliable")
func rpc_start_fight() -> void:
	_fight_started = true
	_prepare_timer = PREPARE_TIME
	_last_prep_voice = -1
	_match_state = MatchState.PREPARE
	if _player != null:
		_prev_stroke = _player.weapon_stroke_count()
		_prev_state = int(_player.state)


@rpc("authority", "call_local", "reliable")
func rpc_match_over(host_won: bool, reason: String) -> void:
	if _match_state == MatchState.GAME_OVER:
		return
	_end_match(host_won == NetworkManager.is_host)
	if _game_over_stats != null:
		_game_over_stats.text += "\n" + reason


# --- Damage: attacker-local detection, host-authoritative resolution ---------

## Overrides the two-sided AI check: only the local blade is tested here.
## The opponent's blade is resolved on their machine and arrives via rpc_claim_hit / rpc_apply_hit.
func _check_blade_hits() -> void:
	if _match_state != MatchState.FIGHTING or _player == null or _npc == null:
		return

	var item = _player_equip.equipped("right_hand")
	if item == null or _player.state != PlayerControllerScript.State.ATTACKING:
		_player_has_tip = false
		_player_blade_inside = false
		return

	var pts := _get_blade_points(item, _player)
	var base: Vector3 = pts[0]
	var tip: Vector3 = pts[1]
	var last_tip: Vector3 = _player_prev_tip if _player_has_tip else tip
	_player_prev_tip = tip
	_player_has_tip = true

	if _player.can_deal_damage():
		var hit: Dictionary = _segment_hit(base, tip, _npc.global_transform, BLADE_PAD)
		if hit.is_empty():
			hit = _segment_hit(last_tip, tip, _npc.global_transform, BLADE_PAD)

		var inside: bool = not hit.is_empty()
		if inside and not _player_blade_inside:
			_report_local_hit(hit.point)
			_player.register_weapon_hit()
		_player_blade_inside = inside
	else:
		_player_blade_inside = false


func _report_local_hit(hit_pos: Vector3) -> void:
	var rolling: bool = _npc.state == PlayerControllerScript.State.ROLLING
	if NetworkManager.is_host:
		_host_resolve_hit(true, hit_pos, rolling)
	else:
		rpc_id(1, "rpc_claim_hit", hit_pos, rolling)


@rpc("any_peer", "call_remote", "reliable")
func rpc_claim_hit(hit_pos: Vector3, target_rolling: bool) -> void:
	if not NetworkManager.is_host:
		return
	_host_resolve_hit(false, hit_pos, target_rolling)


## Host only. Post: HP mutated once, broadcast as absolute values, match ends at 0.
func _host_resolve_hit(attacker_is_host: bool, hit_pos: Vector3, target_rolling: bool) -> void:
	if _match_state != MatchState.FIGHTING:
		return
	var info := _combat_mgr.calculate_damage(attacker_is_host, PVP_BASE_DMG, target_rolling)
	_combat_mgr.apply_damage(attacker_is_host, info)
	rpc("rpc_apply_hit", attacker_is_host, float(info.final_damage), bool(info.is_roll_mitigated),
		hit_pos, _combat_mgr.player_hp, _combat_mgr.ai_hp)
	if _combat_mgr.player_hp <= 0.0 or _combat_mgr.ai_hp <= 0.0:
		rpc("rpc_match_over", _combat_mgr.ai_hp <= 0.0, "对手力竭倒下 · KO")


@rpc("authority", "call_local", "reliable")
func rpc_apply_hit(attacker_is_host: bool, dmg: float, mitigated: bool, hit_pos: Vector3,
		host_hp: float, client_hp: float) -> void:
	_combat_mgr.player_hp = host_hp
	_combat_mgr.ai_hp = client_hp
	_combat_mgr.stats_changed.emit()

	var i_attacked: bool = (attacker_is_host == NetworkManager.is_host)
	var target: PlayerController = _npc if i_attacked else _player

	if i_attacked:
		_total_damage_dealt += dmg
		_combo_count += 1
		_combo_timer = 1.6
		_show_combo_counter(_combo_count)
	elif mitigated:
		_show_dodge_notification("★ 战术翻滚 · 伤害减半 ★")

	_show_damage_floater(hit_pos, dmg, mitigated)

	if mitigated:
		AudioManagerScript.play_hit_sound(-3.0)
	else:
		AudioManagerScript.play_hit_sound(0.0)
		if target != null:
			target.apply_hit_reaction("hit_chest", 0.4)


# --- Rematch & HUD -----------------------------------------------------------

## Rematch is host-driven; a client press asks the host for one.
func _restart_duel() -> void:
	if not multiplayer.has_multiplayer_peer():
		super()
		return
	if NetworkManager.is_host:
		rpc("rpc_rematch")
	else:
		rpc_id(1, "rpc_request_rematch")
		_show_dodge_notification("已请求再战 · 等待房主确认...")


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_rematch() -> void:
	if NetworkManager.is_host and _match_state == MatchState.GAME_OVER:
		rpc("rpc_rematch")


@rpc("authority", "call_local", "reliable")
func rpc_rematch() -> void:
	super._restart_duel()
	_apply_network_spawns()
	rpc_start_fight()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_stats_changed() -> void:
	if _combat_mgr == null:
		return
	var i_host := NetworkManager.is_host
	var my_hp: float = _combat_mgr.player_hp if i_host else _combat_mgr.ai_hp
	var op_hp: float = _combat_mgr.ai_hp if i_host else _combat_mgr.player_hp
	if _player_hp_bar != null:
		_player_hp_bar.value = my_hp
		_player_hp_lbl.text = "🛡 %s · HP %d / 1000" % [NetworkManager.local_player_name, int(my_hp)]
	if _ai_hp_bar != null:
		_ai_hp_bar.value = op_hp
		_ai_hp_lbl.text = "⚔ %s · HP %d / 1000" % [NetworkManager.remote_player_name, int(op_hp)]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_tree().change_scene_to_file(TITLE_SCENE)
			return
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and _match_state != MatchState.GAME_OVER:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
