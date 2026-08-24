extends Node3D
## Player Client dedicated 1v1 Sword PVP Duel scene.
## Features fighting-game HP bars, combo multiplier notifications, dodge roll indicators, and victory flow.

const CharacterPipelineScript = preload("res://tools/character_pipeline.gd")
const PlayerControllerScript = preload("res://scripts/player_controller.gd")
const PlayerIntentSourceScript = preload("res://scripts/player_intent_source.gd")
const FollowCameraScript = preload("res://scripts/follow_camera.gd")
const EquipmentManagerScript = preload("res://scripts/equipment_manager.gd")
const BlockRegistryScript = preload("res://scripts/block_registry.gd")
const MapDataScript = preload("res://scripts/map_data.gd")
const PvpCombatManagerScript = preload("res://scripts/combat/pvp_combat_manager.gd")
const PvpSwordAiScript = preload("res://scripts/ai/pvp_sword_ai.gd")
const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const WorldBuilderScript = preload("res://scripts/world/world_builder.gd")
const ENV_PRESET = preload("res://config/env/sword_pvp.tres")

const TITLE_SCENE := "res://scenes/player_client/title_screen.tscn"
const FONT_PATH := "res://assets/Fonts/Long_Cang/LongCang-Regular.ttf"

const HURT_RADIUS := 0.45
const HURT_LOW_Y := 0.45
const HURT_HIGH_Y := 1.30
const BLADE_PAD := 0.14
const MATCH_TIME := 180.0

enum MatchState { PREPARE, FIGHTING, GAME_OVER }

var _combat_mgr: PvpCombatManager
var _ai_controller: PvpSwordAi
var _match_state: MatchState = MatchState.PREPARE

var _player: PlayerController
var _npc: PlayerController
var _player_visual: Node3D
var _npc_visual: Node3D
var _player_equip: EquipmentManager
var _npc_equip: EquipmentManager

var _camera: FollowCamera
var _custom_font: Font = null
var _match_timer: float = MATCH_TIME

var _player_prev_tip := Vector3.ZERO
var _player_has_tip := false
var _player_blade_inside := false

var _npc_prev_tip := Vector3.ZERO
var _npc_has_tip := false
var _npc_blade_inside := false

# Combo & Stats
var _combo_count := 0
var _combo_timer := 0.0
var _total_damage_dealt := 0.0
var _total_rolls_used := 0

# UI
var _hud_layer: CanvasLayer
var _player_hp_bar: ProgressBar
var _player_hp_lag_bar: ProgressBar
var _ai_hp_bar: ProgressBar
var _ai_hp_lag_bar: ProgressBar
var _player_hp_lbl: Label
var _ai_hp_lbl: Label
var _timer_lbl: Label
var _combo_lbl: Label
var _dodge_banner: Label
var _game_over_dialog: PanelContainer
var _game_over_title: Label
var _game_over_stats: Label

# VFX Pool
const VFX_POOL := 12
var _numbers: Array[Label3D] = []
var _number_tweens: Array[Tween] = []
var _number_next := 0


func _ready() -> void:
	if ResourceLoader.exists(FONT_PATH):
		_custom_font = load(FONT_PATH) as Font

	AudioManagerScript.init_pool(self)
	AudioManagerScript.play_bgm("res://assets/voice/background/song_of_the_sea.ogg", -4.0)

	_combat_mgr = PvpCombatManagerScript.new()
	_combat_mgr.stats_changed.connect(_on_stats_changed)

	_build_environment()
	_build_block_arena()
	_build_characters()
	_build_hud()
	_setup_vfx_pool()

	_equip_default_weapons()

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_match_state = MatchState.FIGHTING


func _physics_process(delta: float) -> void:
	if _match_state == MatchState.FIGHTING:
		_match_timer = maxf(0.0, _match_timer - delta)
		if _timer_lbl != null:
			var minutes := int(_match_timer) / 60
			var seconds := int(_match_timer) % 60
			_timer_lbl.text = "%02d:%02d" % [minutes, seconds]

		if _match_timer <= 0.0:
			_end_match(_combat_mgr.player_hp >= _combat_mgr.ai_hp)
			return

		if _combo_timer > 0.0:
			_combo_timer -= delta
			if _combo_timer <= 0.0:
				_combo_count = 0
				if _combo_lbl != null:
					_combo_lbl.visible = false

		_check_blade_hits()

		# Smooth lag bars update
		if _player_hp_lag_bar != null and _player_hp_bar != null:
			_player_hp_lag_bar.value = lerpf(_player_hp_lag_bar.value, _player_hp_bar.value, delta * 4.0)
		if _ai_hp_lag_bar != null and _ai_hp_bar != null:
			_ai_hp_lag_bar.value = lerpf(_ai_hp_lag_bar.value, _ai_hp_bar.value, delta * 4.0)


# --- World & Arena -----------------------------------------------------------

func _build_environment() -> void:
	WorldBuilderScript.build_environment(self, ENV_PRESET)


func _build_block_arena() -> void:
	var arena := Node3D.new()
	arena.name = "PvpArena"
	add_child(arena)

	# Main fighting floor (36x36m)
	_add_arena_block(arena, Vector3(0.0, -0.5, 0.0), Vector3(36.0, 1.0, 36.0), Color(0.15, 0.17, 0.20))
	# Perimeter stone barrier
	_add_arena_block(arena, Vector3(0.0, 1.0, -18.0), Vector3(36.0, 2.0, 1.0), Color(0.24, 0.28, 0.35))
	_add_arena_block(arena, Vector3(0.0, 1.0, 18.0), Vector3(36.0, 2.0, 1.0), Color(0.24, 0.28, 0.35))
	_add_arena_block(arena, Vector3(-18.0, 1.0, 0.0), Vector3(1.0, 2.0, 36.0), Color(0.24, 0.28, 0.35))
	_add_arena_block(arena, Vector3(18.0, 1.0, 0.0), Vector3(1.0, 2.0, 36.0), Color(0.24, 0.28, 0.35))

	# Central octagonal duel ring
	_add_arena_block(arena, Vector3(0.0, 0.3, 0.0), Vector3(14.0, 0.6, 14.0), Color(0.22, 0.26, 0.32))
	_add_arena_block(arena, Vector3(-6.5, 1.5, -6.5), Vector3(1.0, 3.0, 1.0), Color(0.32, 0.38, 0.48))
	_add_arena_block(arena, Vector3(6.5, 1.5, -6.5), Vector3(1.0, 3.0, 1.0), Color(0.32, 0.38, 0.48))
	_add_arena_block(arena, Vector3(-6.5, 1.5, 6.5), Vector3(1.0, 3.0, 1.0), Color(0.32, 0.38, 0.48))
	_add_arena_block(arena, Vector3(6.5, 1.5, 6.5), Vector3(1.0, 3.0, 1.0), Color(0.32, 0.38, 0.48))


func _add_arena_block(parent: Node, pos: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos

	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mi.mesh = box
	mi.material_override = mat
	body.add_child(mi)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)

	parent.add_child(body)


# --- Fighters Setup ----------------------------------------------------------

func _build_characters() -> void:
	_camera = FollowCameraScript.new()
	_camera.fov = 55.0
	_camera.near = 0.05
	_camera.far = 200.0
	add_child(_camera)

	var chars: Array = CharacterPipelineScript.list_characters().filter(
		func(c: Dictionary) -> bool: return ResourceLoader.exists(c.scene))

	# 1. Player
	_player = PlayerControllerScript.new()
	_player.name = "Player"
	_player.position = Vector3(0.0, 0.8, 5.0)
	_player.intent_source = PlayerIntentSourceScript.new()
	add_child(_player)

	if not chars.is_empty():
		var p_scn := load(chars[0].scene) as PackedScene
		if p_scn != null:
			_player_visual = p_scn.instantiate() as Node3D
			_player.add_child(_player_visual)

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

	# 2. AI Swordmaster
	_npc = PlayerControllerScript.new()
	_npc.name = "AI_Swordmaster"
	_npc.position = Vector3(0.0, 0.8, -5.0)
	_npc.rotation.y = deg_to_rad(180.0)
	add_child(_npc)

	var npc_idx := 1 if chars.size() > 1 else 0
	if not chars.is_empty():
		var n_scn := load(chars[npc_idx].scene) as PackedScene
		if n_scn != null:
			_npc_visual = n_scn.instantiate() as Node3D
			_npc.add_child(_npc_visual)

	var n_h: float = _npc_visual.get("body_height") if _npc_visual != null else 1.75
	_setup_capsule(_npc, n_h)

	_ai_controller = PvpSwordAiScript.new(_player)
	_ai_controller.difficulty = 2 # Normal difficulty
	_npc.intent_source = _ai_controller
	if _npc_visual != null:
		_npc.setup(_npc_visual, null)
	_npc.intent_source = _ai_controller

	_npc_equip = EquipmentManagerScript.new()
	_npc_equip.name = "NpcEquip"
	_npc.add_child(_npc_equip)


func _setup_capsule(body: CharacterBody3D, height: float) -> void:
	if height <= 0.1:
		height = 1.75
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = minf(0.3, height * 0.2)
	capsule.height = height
	collider.shape = capsule
	collider.position.y = height * 0.5
	body.add_child(collider)


func _equip_default_weapons() -> void:
	_player_equip.equip_by_id("Abyss Blade")
	_npc_equip.equip_by_id("Abyss Blade")


# --- Blade Combat & Hit Testing ---------------------------------------------

func _check_blade_hits() -> void:
	if _match_state == MatchState.GAME_OVER or _player == null or _npc == null or _combat_mgr == null:
		return

	# Player -> AI Blade Check
	var p_item = _player_equip.equipped("right_hand")
	if p_item != null and _player.state == PlayerControllerScript.State.ATTACKING:
		var pts := _get_blade_points(p_item, _player)
		var base: Vector3 = pts[0]
		var tip: Vector3 = pts[1]
		var swing: Vector3 = (tip - _player_prev_tip) if _player_has_tip else Vector3.ZERO
		var last_tip: Vector3 = _player_prev_tip if _player_has_tip else tip
		_player_prev_tip = tip
		_player_has_tip = true

		if _player.can_deal_damage():
			var hit: Dictionary = _segment_hit(base, tip, _npc.global_transform, BLADE_PAD)
			if hit.is_empty():
				hit = _segment_hit(last_tip, tip, _npc.global_transform, BLADE_PAD)

			var inside: bool = not hit.is_empty()
			if inside and not _player_blade_inside:
				_resolve_hit(true, hit.point, swing)
				_player.register_weapon_hit()
			_player_blade_inside = inside
		else:
			_player_blade_inside = false
	else:
		_player_has_tip = false
		_player_blade_inside = false

	# AI -> Player Blade Check
	var n_item = _npc_equip.equipped("right_hand")
	if n_item != null and _npc.state == PlayerControllerScript.State.ATTACKING:
		var pts := _get_blade_points(n_item, _npc)
		var base: Vector3 = pts[0]
		var tip: Vector3 = pts[1]
		var swing: Vector3 = (tip - _npc_prev_tip) if _npc_has_tip else Vector3.ZERO
		var last_tip: Vector3 = _npc_prev_tip if _npc_has_tip else tip
		_npc_prev_tip = tip
		_npc_has_tip = true

		if _npc.can_deal_damage():
			var hit: Dictionary = _segment_hit(base, tip, _player.global_transform, BLADE_PAD)
			if hit.is_empty():
				hit = _segment_hit(last_tip, tip, _player.global_transform, BLADE_PAD)

			var inside: bool = not hit.is_empty()
			if inside and not _npc_blade_inside:
				_resolve_hit(false, hit.point, swing)
				_npc.register_weapon_hit()
			_npc_blade_inside = inside
		else:
			_npc_blade_inside = false
	else:
		_npc_has_tip = false
		_npc_blade_inside = false


func _get_blade_points(item: Node, body: CharacterBody3D) -> Array[Vector3]:
	if item != null and is_instance_valid(item):
		if item.has_method("blade_base_global") and item.has_method("blade_tip_global"):
			return [item.call("blade_base_global"), item.call("blade_tip_global")]
		elif item.has_method("blade_base_world") and item.has_method("blade_tip_world"):
			return [item.call("blade_base_world"), item.call("blade_tip_world")]
	var fallback_base := body.global_position + Vector3(0.0, 1.1, 0.0)
	var fallback_tip := fallback_base - body.global_transform.basis.z * 0.9
	return [fallback_base, fallback_tip]


func _segment_hit(a: Vector3, b: Vector3, body_xf: Transform3D, pad: float) -> Dictionary:
	var lo := body_xf * Vector3(0.0, HURT_LOW_Y, 0.0)
	var hi := body_xf * Vector3(0.0, HURT_HIGH_Y, 0.0)
	var pts := Geometry3D.get_closest_points_between_segments(a, b, lo, hi)
	var offset: Vector3 = pts[0] - pts[1]
	var reach := HURT_RADIUS + maxf(pad, 0.0)
	if offset.length_squared() > reach * reach:
		return {}
	var normal := offset.normalized() if offset.length_squared() > 1e-8 else -body_xf.basis.z
	return {"point": pts[1] + normal * HURT_RADIUS, "normal": normal}


func _resolve_hit(player_attacks: bool, hit_pos: Vector3, _swing_dir: Vector3) -> void:
	var target: PlayerController = _npc if player_attacks else _player
	var target_is_rolling: bool = target.state == PlayerControllerScript.State.ROLLING

	var base_dmg := 35.0
	var dmg_info := _combat_mgr.calculate_damage(player_attacks, base_dmg, target_is_rolling)
	var rem_hp := _combat_mgr.apply_damage(player_attacks, dmg_info)

	var final_dmg: float = float(dmg_info.final_damage)
	var is_mitigated: bool = bool(dmg_info.is_roll_mitigated)

	if player_attacks:
		_total_damage_dealt += final_dmg
		_combo_count += 1
		_combo_timer = 1.6
		_show_combo_counter(_combo_count)
	else:
		if is_mitigated:
			_show_dodge_notification("★ 战术翻滚 · 伤害减半 ★")

	_show_damage_floater(hit_pos, final_dmg, is_mitigated)

	# Sound & Stagger (Roll grants 100% CC immunity)
	if is_mitigated:
		AudioManagerScript.play_hit_sound(-3.0)
	else:
		AudioManagerScript.play_hit_sound(0.0)
		target.apply_hit_reaction("hit_chest", 0.4)

	if rem_hp <= 0.0:
		_end_match(player_attacks)


# --- Game Over & Victory Flow -----------------------------------------------

func _end_match(player_won: bool) -> void:
	if _match_state == MatchState.GAME_OVER:
		return
	_match_state = MatchState.GAME_OVER

	var loser: PlayerController = _npc if player_won else _player
	if loser != null and loser.character != null and loser.character.player != null:
		loser.character.play("death", 0.15)

	if _ai_controller != null:
		_ai_controller.is_active = false

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if _game_over_dialog != null:
		_game_over_title.text = "🏆 决斗获胜 (VICTORY)" if player_won else "💀 决斗落败 (DEFEAT)"
		_game_over_title.modulate = Color(0.3, 1.0, 0.4) if player_won else Color(1.0, 0.35, 0.35)

		var time_used := MATCH_TIME - _match_timer
		_game_over_stats.text = "对决耗时: %02d:%02d\n总造成伤害: %d HP\n最大连击: %d 次" % [
			int(time_used) / 60, int(time_used) % 60,
			int(_total_damage_dealt), _combo_count
		]
		_game_over_dialog.visible = true


# --- Fighting Game HUD ------------------------------------------------------

func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 5
	add_child(_hud_layer)

	# Top Health Bars Container
	var top_panel := PanelContainer.new()
	top_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_panel.offset_left = 50
	top_panel.offset_right = -50
	top_panel.offset_top = 18
	top_panel.offset_bottom = 84

	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.06, 0.08, 0.12, 0.88)
	t_style.corner_radius_bottom_left = 10
	t_style.corner_radius_bottom_right = 10
	t_style.content_margin_left = 24
	t_style.content_margin_right = 24
	t_style.content_margin_top = 8
	t_style.content_margin_bottom = 8
	top_panel.add_theme_stylebox_override("panel", t_style)
	_hud_layer.add_child(top_panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 24)
	top_panel.add_child(hbox)

	# 1. Player Side (Left)
	var p_vbox := VBoxContainer.new()
	p_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(p_vbox)

	_player_hp_lbl = Label.new()
	_player_hp_lbl.text = "🛡 玩家 (PLAYER) · HP 1000 / 1000"
	_player_hp_lbl.add_theme_font_size_override("font_size", 15)
	_player_hp_lbl.modulate = Color(0.35, 0.85, 1.0)
	p_vbox.add_child(_player_hp_lbl)

	# Layered Progress Bar with Lag bar
	var p_bar_holder := Control.new()
	p_bar_holder.custom_minimum_size = Vector2(0, 16)
	p_vbox.add_child(p_bar_holder)

	_player_hp_lag_bar = ProgressBar.new()
	_player_hp_lag_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_player_hp_lag_bar.max_value = 1000.0
	_player_hp_lag_bar.value = 1000.0
	_player_hp_lag_bar.show_percentage = false
	p_bar_holder.add_child(_player_hp_lag_bar)

	_player_hp_bar = ProgressBar.new()
	_player_hp_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_player_hp_bar.max_value = 1000.0
	_player_hp_bar.value = 1000.0
	_player_hp_bar.show_percentage = false
	p_bar_holder.add_child(_player_hp_bar)

	# 2. Match Timer (Center)
	var center_box := VBoxContainer.new()
	center_box.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(center_box)

	_timer_lbl = Label.new()
	_timer_lbl.text = "03:00"
	_timer_lbl.add_theme_font_size_override("font_size", 24)
	_timer_lbl.modulate = Color(1.0, 0.9, 0.4)
	_timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_box.add_child(_timer_lbl)

	# 3. AI Swordmaster Side (Right)
	var ai_vbox := VBoxContainer.new()
	ai_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(ai_vbox)

	_ai_hp_lbl = Label.new()
	_ai_hp_lbl.text = "⚔ 试炼剑圣 · 艾斯兰 · HP 1000 / 1000"
	_ai_hp_lbl.add_theme_font_size_override("font_size", 15)
	_ai_hp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ai_hp_lbl.modulate = Color(1.0, 0.45, 0.4)
	ai_vbox.add_child(_ai_hp_lbl)

	var ai_bar_holder := Control.new()
	ai_bar_holder.custom_minimum_size = Vector2(0, 16)
	ai_vbox.add_child(ai_bar_holder)

	_ai_hp_lag_bar = ProgressBar.new()
	_ai_hp_lag_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ai_hp_lag_bar.max_value = 1000.0
	_ai_hp_lag_bar.value = 1000.0
	_ai_hp_lag_bar.show_percentage = false
	ai_bar_holder.add_child(_ai_hp_lag_bar)

	_ai_hp_bar = ProgressBar.new()
	_ai_hp_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ai_hp_bar.max_value = 1000.0
	_ai_hp_bar.value = 1000.0
	_ai_hp_bar.show_percentage = false
	ai_bar_holder.add_child(_ai_hp_bar)

	# Combo Counter
	_combo_lbl = Label.new()
	_combo_lbl.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_combo_lbl.offset_left = 60
	_combo_lbl.offset_top = -40
	_combo_lbl.text = ""
	_combo_lbl.add_theme_font_size_override("font_size", 28)
	_combo_lbl.modulate = Color(1.0, 0.75, 0.2)
	_combo_lbl.visible = false
	_hud_layer.add_child(_combo_lbl)

	# Dodge Notification Banner
	_dodge_banner = Label.new()
	_dodge_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_dodge_banner.offset_top = 100
	_dodge_banner.text = ""
	_dodge_banner.add_theme_font_size_override("font_size", 22)
	_dodge_banner.modulate = Color(1.0, 0.88, 0.3)
	_dodge_banner.visible = false
	_hud_layer.add_child(_dodge_banner)

	# Game Over Modal Dialog
	_build_game_over_dialog()

	# Bottom Hint Bar
	var hint_panel := PanelContainer.new()
	hint_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint_panel.offset_left = 20
	hint_panel.offset_right = -20
	hint_panel.offset_bottom = -12
	hint_panel.offset_top = -48

	var h_style := StyleBoxFlat.new()
	h_style.bg_color = Color(0.06, 0.08, 0.10, 0.75)
	h_style.corner_radius_top_left = 6
	h_style.corner_radius_top_right = 6
	h_style.corner_radius_bottom_left = 6
	h_style.corner_radius_bottom_right = 6
	h_style.content_margin_left = 16
	h_style.content_margin_right = 16
	hint_panel.add_theme_stylebox_override("panel", h_style)
	_hud_layer.add_child(hint_panel)

	var hint_lbl := Label.new()
	hint_lbl.text = "WASD 移动 · LMB 挥刀攻击 · C / Shift 翻滚(减伤50%与免控) · TAB 释放光标 · ESC 退出"
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_lbl.add_theme_font_size_override("font_size", 13)
	hint_panel.add_child(hint_lbl)


func _build_game_over_dialog() -> void:
	_game_over_dialog = PanelContainer.new()
	_game_over_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_game_over_dialog.offset_left = -220
	_game_over_dialog.offset_top = -140
	_game_over_dialog.offset_right = 220
	_game_over_dialog.offset_bottom = 140

	var d_style := StyleBoxFlat.new()
	d_style.bg_color = Color(0.08, 0.10, 0.14, 0.95)
	d_style.border_width_left = 2
	d_style.border_width_top = 2
	d_style.border_width_right = 2
	d_style.border_width_bottom = 2
	d_style.border_color = Color(0.3, 0.85, 1.0, 0.8)
	d_style.corner_radius_top_left = 10
	d_style.corner_radius_top_right = 10
	d_style.corner_radius_bottom_left = 10
	d_style.corner_radius_bottom_right = 10
	d_style.content_margin_left = 24
	d_style.content_margin_right = 24
	d_style.content_margin_top = 18
	d_style.content_margin_bottom = 18
	_game_over_dialog.add_theme_stylebox_override("panel", d_style)
	_game_over_dialog.visible = false
	_hud_layer.add_child(_game_over_dialog)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	_game_over_dialog.add_child(vbox)

	_game_over_title = Label.new()
	_game_over_title.text = "🏆 决斗获胜 (VICTORY)"
	_game_over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over_title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_game_over_title)

	_game_over_stats = Label.new()
	_game_over_stats.text = ""
	_game_over_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over_stats.add_theme_font_size_override("font_size", 14)
	_game_over_stats.modulate = Color(0.85, 0.88, 0.92)
	vbox.add_child(_game_over_stats)

	var btn_hbox := HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", 18)
	vbox.add_child(btn_hbox)

	var retry_btn := Button.new()
	retry_btn.text = "🔄 再次决斗"
	retry_btn.pressed.connect(_restart_duel)
	btn_hbox.add_child(retry_btn)

	var menu_btn := Button.new()
	menu_btn.text = "🚪 返回标题"
	menu_btn.pressed.connect(func() -> void:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file(TITLE_SCENE)
	)
	btn_hbox.add_child(menu_btn)


func _show_combo_counter(count: int) -> void:
	if _combo_lbl == null:
		return
	_combo_lbl.text = "⚔ %d 连击 COMBO!" % count
	_combo_lbl.visible = true
	var tw := create_tween()
	tw.tween_property(_combo_lbl, "scale", Vector2(1.2, 1.2), 0.08)
	tw.tween_property(_combo_lbl, "scale", Vector2.ONE, 0.12)


func _show_dodge_notification(msg: String) -> void:
	if _dodge_banner == null:
		return
	_dodge_banner.text = msg
	_dodge_banner.visible = true
	_dodge_banner.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(0.6)
	tw.tween_property(_dodge_banner, "modulate:a", 0.0, 0.4)
	tw.chain().tween_callback(func() -> void: _dodge_banner.visible = false)


func _on_stats_changed() -> void:
	if _player_hp_bar != null:
		_player_hp_bar.value = _combat_mgr.player_hp
		_player_hp_lbl.text = "🛡 玩家 (PLAYER) · HP %d / %d" % [int(_combat_mgr.player_hp), int(_combat_mgr.player_max_hp)]
	if _ai_hp_bar != null:
		_ai_hp_bar.value = _combat_mgr.ai_hp
		_ai_hp_lbl.text = "⚔ 试炼剑圣 · 艾斯兰 · HP %d / %d" % [int(_combat_mgr.ai_hp), int(_combat_mgr.ai_max_hp)]


func _restart_duel() -> void:
	_combat_mgr.reset_health()
	_match_timer = MATCH_TIME
	_total_damage_dealt = 0.0
	_combo_count = 0
	_match_state = MatchState.FIGHTING

	if _game_over_dialog != null:
		_game_over_dialog.visible = false

	if _player != null:
		_player.global_position = Vector3(0.0, 0.8, 5.0)
		_player.rotation.y = deg_to_rad(0.0)
		_player.reset_combat_state()
	if _npc != null:
		_npc.global_position = Vector3(0.0, 0.8, -5.0)
		_npc.rotation.y = deg_to_rad(180.0)
		_npc.reset_combat_state()

	if _ai_controller != null:
		_ai_controller.reset()

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- Damage Floaters ---------------------------------------------------------

func _setup_vfx_pool() -> void:
	for i in VFX_POOL:
		var lbl := Label3D.new()
		lbl.font_size = 32
		lbl.outline_size = 8
		lbl.outline_modulate = Color.BLACK
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.visible = false
		add_child(lbl)
		_numbers.append(lbl)
		_number_tweens.append(null)


func _show_damage_floater(pos: Vector3, dmg: float, is_roll_mitigated: bool) -> void:
	var idx := _number_next
	_number_next = (_number_next + 1) % VFX_POOL

	if _number_tweens[idx] != null and _number_tweens[idx].is_valid():
		_number_tweens[idx].kill()

	var lbl := _numbers[idx]
	if is_roll_mitigated:
		lbl.text = "-%d (翻滚减伤)" % int(dmg)
		lbl.modulate = Color(1.0, 0.88, 0.2, 1.0)
	else:
		lbl.text = "-%d" % int(dmg)
		lbl.modulate = Color(1.0, 0.28, 0.2, 1.0)

	lbl.global_position = pos + Vector3(randf_range(-0.15, 0.15), 0.25, randf_range(-0.15, 0.15))
	lbl.visible = true

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "global_position:y", lbl.global_position.y + 0.65, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.75).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func() -> void: lbl.visible = false)
	_number_tweens[idx] = tw


# --- Input Handling ----------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_tree().change_scene_to_file(TITLE_SCENE)
			return
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and _match_state != MatchState.GAME_OVER:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
