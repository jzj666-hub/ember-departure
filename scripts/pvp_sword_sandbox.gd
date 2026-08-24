extends Node3D
## Developer Sandbox for NPC Sword PVP.
## Provides real-time parameter tuning (HP, Weapon Damage, ATK Multiplier, DEF, AI Difficulty)
## and dual blade hit detection with 50% roll damage reduction & CC immunity.

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
const ENV_PRESET = preload("res://config/env/pvp_sandbox.tres")

const MENU_SCENE := "res://scenes/main_menu.tscn"
const FONT_PATH := "res://assets/Fonts/Long_Cang/LongCang-Regular.ttf"

const HURT_RADIUS := 0.45
const HURT_LOW_Y := 0.45
const HURT_HIGH_Y := 1.30
const BLADE_PAD := 0.14

var _combat_mgr: PvpCombatManager
var _ai_controller: PvpSwordAi

var _characters: Array = []
var _player_char_idx: int = 0
var _npc_char_idx: int = 1

var _player: PlayerController
var _npc: PlayerController
var _player_visual: Node3D
var _npc_visual: Node3D
var _player_equip: EquipmentManager
var _npc_equip: EquipmentManager

var _camera: FollowCamera
var _custom_font: Font = null

# Blade previous tips for swept hit detection
var _player_prev_tip := Vector3.ZERO
var _player_has_tip := false
var _player_blade_inside := false

var _npc_prev_tip := Vector3.ZERO
var _npc_has_tip := false
var _npc_blade_inside := false

# UI / HUD
var _hud_layer: CanvasLayer
var _dev_panel: PanelContainer
var _log_box: RichTextLabel
var _player_hp_bar: ProgressBar
var _ai_hp_bar: ProgressBar
var _player_hp_lbl: Label
var _ai_hp_lbl: Label
var _battle_banner: Label
var _match_over_dialog: PanelContainer
var _match_over_title: Label
var _is_match_over := false

# VFX Pool
const VFX_POOL := 12
var _numbers: Array[Label3D] = []
var _number_tweens: Array[Tween] = []
var _number_next := 0

var _available_weapons := [
	"Abyss Blade",
	"Apostle GreatSword",
	"Bone Blade",
	"Ax",
	"War Ax",
	"Two Handred Hammer",
]
var _current_weapon_idx := 0


func _ready() -> void:
	if ResourceLoader.exists(FONT_PATH):
		_custom_font = load(FONT_PATH) as Font

	AudioManagerScript.init_pool(self)

	_combat_mgr = PvpCombatManagerScript.new()
	_combat_mgr.stats_changed.connect(_on_stats_changed)

	_characters = CharacterPipelineScript.list_characters().filter(
		func(c: Dictionary) -> bool: return ResourceLoader.exists(c.scene))
	if _characters.size() > 1:
		_npc_char_idx = 1
	else:
		_npc_char_idx = 0

	_build_environment()
	_build_block_arena()
	_build_characters()
	_build_hud()
	_setup_vfx_pool()

	_equip_fighters(_available_weapons[_current_weapon_idx])

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(_delta: float) -> void:
	_check_blade_hits()


# --- World & Environment -----------------------------------------------------

func _build_environment() -> void:
	WorldBuilderScript.build_environment(self, ENV_PRESET)


## Builds block map arena with central platform, stairs, and pillars.
func _build_block_arena() -> void:
	var arena_root := Node3D.new()
	arena_root.name = "BlockArena"
	add_child(arena_root)

	# Base ground (40x40m)
	_add_block_box(arena_root, Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0), Color(0.16, 0.18, 0.22), "BaseFloor")

	# Outer boundary walls
	_add_block_box(arena_root, Vector3(0.0, 1.5, -20.0), Vector3(40.0, 3.0, 1.0), Color(0.25, 0.28, 0.35), "WallNorth")
	_add_block_box(arena_root, Vector3(0.0, 1.5, 20.0), Vector3(40.0, 3.0, 1.0), Color(0.25, 0.28, 0.35), "WallSouth")
	_add_block_box(arena_root, Vector3(-20.0, 1.5, 0.0), Vector3(1.0, 3.0, 40.0), Color(0.25, 0.28, 0.35), "WallWest")
	_add_block_box(arena_root, Vector3(20.0, 1.5, 0.0), Vector3(1.0, 3.0, 40.0), Color(0.25, 0.28, 0.35), "WallEast")

	# Central raised fighting ring
	_add_block_box(arena_root, Vector3(0.0, 0.5, 0.0), Vector3(16.0, 1.0, 16.0), Color(0.22, 0.25, 0.32), "RingPlatform")
	# Ring Corner pillars
	_add_block_box(arena_root, Vector3(-7.5, 2.0, -7.5), Vector3(1.2, 4.0, 1.2), Color(0.35, 0.40, 0.50), "PillarNW")
	_add_block_box(arena_root, Vector3(7.5, 2.0, -7.5), Vector3(1.2, 4.0, 1.2), Color(0.35, 0.40, 0.50), "PillarNE")
	_add_block_box(arena_root, Vector3(-7.5, 2.0, 7.5), Vector3(1.2, 4.0, 1.2), Color(0.35, 0.40, 0.50), "PillarSW")
	_add_block_box(arena_root, Vector3(7.5, 2.0, 7.5), Vector3(1.2, 4.0, 1.2), Color(0.35, 0.40, 0.50), "PillarSE")

	# Access stairs
	_add_block_box(arena_root, Vector3(0.0, 0.25, -9.0), Vector3(6.0, 0.5, 2.0), Color(0.28, 0.32, 0.40), "StepNorth")
	_add_block_box(arena_root, Vector3(0.0, 0.25, 9.0), Vector3(6.0, 0.5, 2.0), Color(0.28, 0.32, 0.40), "StepSouth")


func _add_block_box(parent: Node, pos: Vector3, size: Vector3, color: Color, hint: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = hint
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
	return body


# --- Characters Setup --------------------------------------------------------

func _build_characters() -> void:
	# Camera
	_camera = FollowCameraScript.new()
	_camera.fov = 58.0
	_camera.near = 0.05
	_camera.far = 200.0
	add_child(_camera)

	# 1. Player
	_player = PlayerControllerScript.new()
	_player.name = "Player"
	_player.position = Vector3(0.0, 1.1, 4.5)
	_player.intent_source = PlayerIntentSourceScript.new()
	add_child(_player)

	if not _characters.is_empty():
		var p_scn := load(_characters[_player_char_idx].scene) as PackedScene
		if p_scn != null:
			_player_visual = p_scn.instantiate() as Node3D
			_player.add_child(_player_visual)

	var p_height: float = _player_visual.get("body_height") if _player_visual != null else 1.75
	_setup_capsule_collider(_player, p_height)
	if _player_visual != null:
		_player.setup(_player_visual, _camera)

	_player_equip = EquipmentManagerScript.new()
	_player_equip.name = "PlayerEquipment"
	_player.add_child(_player_equip)

	_camera.target = _player
	_camera.frame_for(p_height)
	_camera.snap()

	# 2. AI Bot
	_npc = PlayerControllerScript.new()
	_npc.name = "NPC_Swordmaster"
	_npc.position = Vector3(0.0, 1.1, -4.5)
	_npc.rotation.y = deg_to_rad(180.0)
	add_child(_npc)

	if not _characters.is_empty():
		var npc_scn := load(_characters[_npc_char_idx].scene) as PackedScene
		if npc_scn != null:
			_npc_visual = npc_scn.instantiate() as Node3D
			_npc.add_child(_npc_visual)

	var n_height: float = _npc_visual.get("body_height") if _npc_visual != null else 1.75
	_setup_capsule_collider(_npc, n_height)

	_ai_controller = PvpSwordAiScript.new(_player)
	_npc.intent_source = _ai_controller
	if _npc_visual != null:
		_npc.setup(_npc_visual, null)
	_npc.intent_source = _ai_controller

	_npc_equip = EquipmentManagerScript.new()
	_npc_equip.name = "NpcEquipment"
	_npc.add_child(_npc_equip)


func _setup_capsule_collider(body: CharacterBody3D, height: float) -> void:
	if height <= 0.1:
		height = 1.75
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = minf(0.3, height * 0.2)
	capsule.height = height
	collider.shape = capsule
	collider.position.y = height * 0.5
	body.add_child(collider)


func _equip_fighters(weapon_id: String) -> void:
	_combat_mgr.weapon_name = weapon_id
	_combat_mgr.custom_weapon_damage = _combat_mgr.get_weapon_base_damage(weapon_id)

	_player_equip.equip_by_id(weapon_id)
	_npc_equip.equip_by_id(weapon_id)


# --- Blade Hit Detection (Player <-> AI) ------------------------------------

func _check_blade_hits() -> void:
	if _is_match_over or _player == null or _npc == null or _combat_mgr == null:
		return

	# 1. Player Blade -> AI Hit Check
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
			var hit: Dictionary = _segment_capsule_hit(base, tip, _npc.global_transform, BLADE_PAD)
			if hit.is_empty():
				hit = _segment_capsule_hit(last_tip, tip, _npc.global_transform, BLADE_PAD)

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

	# 2. AI Blade -> Player Hit Check
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
			var hit: Dictionary = _segment_capsule_hit(base, tip, _player.global_transform, BLADE_PAD)
			if hit.is_empty():
				hit = _segment_capsule_hit(last_tip, tip, _player.global_transform, BLADE_PAD)

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


func _segment_capsule_hit(a: Vector3, b: Vector3, body_xf: Transform3D, pad: float) -> Dictionary:
	var lo := body_xf * Vector3(0.0, HURT_LOW_Y, 0.0)
	var hi := body_xf * Vector3(0.0, HURT_HIGH_Y, 0.0)
	var pts := Geometry3D.get_closest_points_between_segments(a, b, lo, hi)
	var offset: Vector3 = pts[0] - pts[1]
	var reach := HURT_RADIUS + maxf(pad, 0.0)
	if offset.length_squared() > reach * reach:
		return {}
	var normal := offset.normalized() if offset.length_squared() > 1e-8 else -body_xf.basis.z
	return {"point": pts[1] + normal * HURT_RADIUS, "normal": normal}


func _resolve_hit(player_attacks: bool, hit_pos: Vector3, swing_dir: Vector3) -> void:
	var target: PlayerController = _npc if player_attacks else _player
	var target_is_rolling: bool = target.state == PlayerControllerScript.State.ROLLING

	var base_dmg: float = _combat_mgr.custom_weapon_damage
	var dmg_info := _combat_mgr.calculate_damage(player_attacks, base_dmg, target_is_rolling)
	var rem_hp := _combat_mgr.apply_damage(player_attacks, dmg_info)

	var final_dmg: float = float(dmg_info.final_damage)
	var is_mitigated: bool = bool(dmg_info.is_roll_mitigated)

	_show_damage_floater(hit_pos, final_dmg, is_mitigated)
	_log_combat_event(player_attacks, final_dmg, is_mitigated, rem_hp)

	# Sound & Stagger (Roll grants 100% CC immunity)
	if is_mitigated:
		AudioManagerScript.play_hit_sound(-3.0)
	else:
		AudioManagerScript.play_hit_sound(0.0)
		target.apply_hit_reaction("hit_chest", 0.4)

	if rem_hp <= 0.0:
		_on_fighter_died(player_attacks)


func _on_fighter_died(player_won: bool) -> void:
	if _is_match_over:
		return
	_is_match_over = true

	var loser: PlayerController = _npc if player_won else _player
	if loser != null and loser.character != null and loser.character.player != null:
		loser.character.play("death", 0.15)

	if _ai_controller != null:
		_ai_controller.is_active = false

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if _match_over_dialog != null:
		_match_over_title.text = "🏆 玩家决斗获胜 (VICTORY)" if player_won else "💀 人机剑圣获胜 (DEFEAT)"
		_match_over_title.modulate = Color(0.3, 1.0, 0.4) if player_won else Color(1.0, 0.35, 0.35)
		_match_over_dialog.visible = true


# --- HUD & Developer Tuning Panel -------------------------------------------

func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 5
	add_child(_hud_layer)

	# 1. Top Health Bars
	var top_bar := PanelContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_left = 60
	top_bar.offset_right = -60
	top_bar.offset_top = 16
	top_bar.offset_bottom = 76

	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.06, 0.08, 0.11, 0.85)
	t_style.corner_radius_bottom_left = 8
	t_style.corner_radius_bottom_right = 8
	t_style.content_margin_left = 20
	t_style.content_margin_right = 20
	t_style.content_margin_top = 8
	t_style.content_margin_bottom = 8
	top_bar.add_theme_stylebox_override("panel", t_style)
	_hud_layer.add_child(top_bar)

	var h_grid := HBoxContainer.new()
	h_grid.add_theme_constant_override("separation", 24)
	top_bar.add_child(h_grid)

	# Player HP Box (Left)
	var p_box := VBoxContainer.new()
	p_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h_grid.add_child(p_box)

	_player_hp_lbl = Label.new()
	_player_hp_lbl.text = "⚔ 玩家 (Player) HP: 1000 / 1000"
	_player_hp_lbl.add_theme_font_size_override("font_size", 14)
	_player_hp_lbl.modulate = Color(0.4, 0.9, 1.0)
	p_box.add_child(_player_hp_lbl)

	_player_hp_bar = ProgressBar.new()
	_player_hp_bar.max_value = 1000.0
	_player_hp_bar.value = 1000.0
	_player_hp_bar.show_percentage = false
	_player_hp_bar.custom_minimum_size = Vector2(0, 14)
	p_box.add_child(_player_hp_bar)

	# VS Badge
	var vs_lbl := Label.new()
	vs_lbl.text = "VS"
	vs_lbl.add_theme_font_size_override("font_size", 20)
	vs_lbl.modulate = Color(1.0, 0.85, 0.3)
	h_grid.add_child(vs_lbl)

	# AI HP Box (Right)
	var ai_box := VBoxContainer.new()
	ai_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h_grid.add_child(ai_box)

	_ai_hp_lbl = Label.new()
	_ai_hp_lbl.text = "🤖 人机剑圣 (NPC Swordmaster) HP: 1000 / 1000"
	_ai_hp_lbl.add_theme_font_size_override("font_size", 14)
	_ai_hp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ai_hp_lbl.modulate = Color(1.0, 0.45, 0.4)
	ai_box.add_child(_ai_hp_lbl)

	_ai_hp_bar = ProgressBar.new()
	_ai_hp_bar.max_value = 1000.0
	_ai_hp_bar.value = 1000.0
	_ai_hp_bar.show_percentage = false
	_ai_hp_bar.custom_minimum_size = Vector2(0, 14)
	ai_box.add_child(_ai_hp_bar)

	# 2. Victory/Defeat Banner
	_battle_banner = Label.new()
	_battle_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_battle_banner.offset_top = 110
	_battle_banner.text = ""
	_battle_banner.add_theme_font_size_override("font_size", 28)
	_battle_banner.visible = false
	_hud_layer.add_child(_battle_banner)

	# 3. Developer Real-time Tuning Panel (Right Side)
	_dev_panel = PanelContainer.new()
	_dev_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_dev_panel.offset_left = -380
	_dev_panel.offset_right = -16
	_dev_panel.offset_top = 86
	_dev_panel.offset_bottom = 680

	var d_style := StyleBoxFlat.new()
	d_style.bg_color = Color(0.08, 0.10, 0.14, 0.92)
	d_style.border_width_left = 2
	d_style.border_width_top = 2
	d_style.border_width_right = 2
	d_style.border_width_bottom = 2
	d_style.border_color = Color(0.3, 0.8, 1.0, 0.5)
	d_style.corner_radius_top_left = 8
	d_style.corner_radius_bottom_left = 8
	d_style.content_margin_left = 14
	d_style.content_margin_right = 14
	d_style.content_margin_top = 10
	d_style.content_margin_bottom = 10
	_dev_panel.add_theme_stylebox_override("panel", d_style)
	_hud_layer.add_child(_dev_panel)

	var d_scroll := ScrollContainer.new()
	d_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dev_panel.add_child(d_scroll)

	var d_vbox := VBoxContainer.new()
	d_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	d_vbox.add_theme_constant_override("separation", 8)
	d_scroll.add_child(d_vbox)

	var p_title := Label.new()
	p_title.text = "⚙ 开发者实时调节面板 (Dev Panel)"
	p_title.add_theme_font_size_override("font_size", 16)
	p_title.modulate = Color(0.3, 0.9, 1.0)
	d_vbox.add_child(p_title)

	d_vbox.add_child(HSeparator.new())

	# --- Sliders ---
	# Player Max HP
	_add_slider(d_vbox, "玩家最大生命 (Player Max HP)", 100.0, 3000.0, 50.0, _combat_mgr.player_max_hp, func(v: float) -> void:
		_combat_mgr.player_max_hp = v
		_combat_mgr.player_hp = minf(_combat_mgr.player_hp, v)
		_combat_mgr.stats_changed.emit()
	)

	# AI Max HP
	_add_slider(d_vbox, "人机最大生命 (AI Max HP)", 100.0, 3000.0, 50.0, _combat_mgr.ai_max_hp, func(v: float) -> void:
		_combat_mgr.ai_max_hp = v
		_combat_mgr.ai_hp = minf(_combat_mgr.ai_hp, v)
		_combat_mgr.stats_changed.emit()
	)

	# Weapon Base Damage
	_add_slider(d_vbox, "武器基础攻击力 (Weapon Base DMG)", 10.0, 150.0, 1.0, _combat_mgr.custom_weapon_damage, func(v: float) -> void:
		_combat_mgr.custom_weapon_damage = v
	)

	# Player ATK Multiplier
	_add_slider(d_vbox, "玩家攻击力加成 (Player ATK)", 0.2, 4.0, 0.1, _combat_mgr.player_atk_mult, func(v: float) -> void:
		_combat_mgr.player_atk_mult = v
	)

	# AI ATK Multiplier
	_add_slider(d_vbox, "人机攻击力加成 (AI ATK)", 0.2, 4.0, 0.1, _combat_mgr.ai_atk_mult, func(v: float) -> void:
		_combat_mgr.ai_atk_mult = v
	)

	# Player DEF
	_add_slider(d_vbox, "玩家防御力 (Player DEF)", 0.0, 150.0, 5.0, _combat_mgr.player_def, func(v: float) -> void:
		_combat_mgr.player_def = v
	)

	# AI DEF
	_add_slider(d_vbox, "人机防御力 (AI DEF)", 0.0, 150.0, 5.0, _combat_mgr.ai_def, func(v: float) -> void:
		_combat_mgr.ai_def = v
	)

	# AI Difficulty Picker
	var diff_lbl := Label.new()
	diff_lbl.text = "AI 难度与闪避频率:"
	diff_lbl.add_theme_font_size_override("font_size", 12)
	d_vbox.add_child(diff_lbl)

	var diff_opt := OptionButton.new()
	diff_opt.add_item("初级剑士 (Easy - 35% 翻滚闪避)")
	diff_opt.add_item("精锐试炼官 (Normal - 55% 翻滚闪避)")
	diff_opt.add_item("宗师剑圣 (Master - 80% 翻滚闪避)")
	diff_opt.selected = 1
	diff_opt.item_selected.connect(func(idx: int) -> void:
		if _ai_controller != null:
			_ai_controller.difficulty = idx + 1
	)
	d_vbox.add_child(diff_opt)

	# Weapon Switcher
	var wpn_btn := Button.new()
	wpn_btn.text = "🗡 切换双方武器 (%s)" % _combat_mgr.weapon_name
	wpn_btn.pressed.connect(func() -> void:
		_current_weapon_idx = (_current_weapon_idx + 1) % _available_weapons.size()
		_equip_fighters(_available_weapons[_current_weapon_idx])
		wpn_btn.text = "🗡 切换双方武器 (%s)" % _combat_mgr.weapon_name
	)
	d_vbox.add_child(wpn_btn)

	# Reset Health & Restart Button
	var reset_btn := Button.new()
	reset_btn.text = "🔄 重置对局并满血 (F1)"
	reset_btn.pressed.connect(_reset_match)
	d_vbox.add_child(reset_btn)

	d_vbox.add_child(HSeparator.new())

	# Combat Log
	var log_lbl := Label.new()
	log_lbl.text = "战斗命中日志 (Combat Telemetry):"
	log_lbl.add_theme_font_size_override("font_size", 12)
	d_vbox.add_child(log_lbl)

	_log_box = RichTextLabel.new()
	_log_box.custom_minimum_size = Vector2(0, 110)
	_log_box.bbcode_enabled = true
	_log_box.scroll_following = true
	d_vbox.add_child(_log_box)

	# 4. Match Over Modal Dialog
	_build_match_over_dialog()

	# 5. Bottom Hint Bar
	var hint_bar := PanelContainer.new()
	hint_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint_bar.offset_left = 20
	hint_bar.offset_right = -20
	hint_bar.offset_bottom = -12
	hint_bar.offset_top = -48

	var h_style := StyleBoxFlat.new()
	h_style.bg_color = Color(0.06, 0.08, 0.10, 0.8)
	h_style.corner_radius_top_left = 6
	h_style.corner_radius_top_right = 6
	h_style.corner_radius_bottom_left = 6
	h_style.corner_radius_bottom_right = 6
	h_style.content_margin_left = 16
	h_style.content_margin_right = 16
	hint_bar.add_theme_stylebox_override("panel", h_style)
	_hud_layer.add_child(hint_bar)

	var h_lbl := Label.new()
	h_lbl.text = "WASD 移动 · LMB 挥剑攻击 · C/Shift 翻滚(减伤50%+免控) · F1 重置对局 · J 切换调参面板 · TAB 释放光标 · ESC 返回"
	h_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h_lbl.add_theme_font_size_override("font_size", 13)
	hint_bar.add_child(h_lbl)


func _build_match_over_dialog() -> void:
	_match_over_dialog = PanelContainer.new()
	_match_over_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_match_over_dialog.offset_left = -200
	_match_over_dialog.offset_top = -110
	_match_over_dialog.offset_right = 200
	_match_over_dialog.offset_bottom = 110

	var d_style := StyleBoxFlat.new()
	d_style.bg_color = Color(0.08, 0.10, 0.14, 0.96)
	d_style.border_width_left = 2
	d_style.border_width_top = 2
	d_style.border_width_right = 2
	d_style.border_width_bottom = 2
	d_style.border_color = Color(0.3, 0.85, 1.0, 0.8)
	d_style.corner_radius_top_left = 10
	d_style.corner_radius_top_right = 10
	d_style.corner_radius_bottom_left = 10
	d_style.corner_radius_bottom_right = 10
	d_style.content_margin_left = 20
	d_style.content_margin_right = 20
	d_style.content_margin_top = 16
	d_style.content_margin_bottom = 16
	_match_over_dialog.add_theme_stylebox_override("panel", d_style)
	_match_over_dialog.visible = false
	_hud_layer.add_child(_match_over_dialog)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	_match_over_dialog.add_child(vbox)

	_match_over_title = Label.new()
	_match_over_title.text = "🏆 玩家决斗获胜 (VICTORY)"
	_match_over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_match_over_title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_match_over_title)

	var btn_hbox := HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_hbox)

	var retry_btn := Button.new()
	retry_btn.text = "🔄 重新开战 (F1)"
	retry_btn.pressed.connect(_reset_match)
	btn_hbox.add_child(retry_btn)

	var menu_btn := Button.new()
	menu_btn.text = "🚪 返回主菜单 (ESC)"
	menu_btn.pressed.connect(func() -> void:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file(MENU_SCENE)
	)
	btn_hbox.add_child(menu_btn)


func _add_slider(parent: Control, label_text: String, min_v: float, max_v: float, step_v: float, initial_v: float, callback: Callable) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)

	var title_row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(lbl)

	var val_lbl := Label.new()
	val_lbl.text = "%.1f" % initial_v
	val_lbl.add_theme_font_size_override("font_size", 12)
	val_lbl.modulate = Color(1.0, 0.85, 0.3)
	title_row.add_child(val_lbl)
	row.add_child(title_row)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_v
	slider.value = initial_v
	slider.value_changed.connect(func(v: float) -> void:
		val_lbl.text = "%.1f" % v
		callback.call(v)
	)
	row.add_child(slider)
	parent.add_child(row)


func _on_stats_changed() -> void:
	if _player_hp_bar != null:
		_player_hp_bar.max_value = _combat_mgr.player_max_hp
		_player_hp_bar.value = _combat_mgr.player_hp
		_player_hp_lbl.text = "⚔ 玩家 (Player) HP: %d / %d" % [int(_combat_mgr.player_hp), int(_combat_mgr.player_max_hp)]

	if _ai_hp_bar != null:
		_ai_hp_bar.max_value = _combat_mgr.ai_max_hp
		_ai_hp_bar.value = _combat_mgr.ai_hp
		_ai_hp_lbl.text = "🤖 人机剑圣 (NPC Swordmaster) HP: %d / %d" % [int(_combat_mgr.ai_hp), int(_combat_mgr.ai_max_hp)]


func _log_combat_event(player_attacks: bool, dmg: float, mitigated: bool, rem_hp: float) -> void:
	if _log_box == null:
		return
	var attacker := "[color=#40e0d0]玩家[/color]" if player_attacks else "[color=#ff6b6b]人机[/color]"
	var target := "[color=#ff6b6b]人机[/color]" if player_attacks else "[color=#40e0d0]玩家[/color]"
	var roll_str := " [color=#ffd700]★翻滚减伤50%[/color]" if mitigated else ""
	_log_box.append_text("%s 命中 %s 造成 [b]%.1f[/b] 伤害%s (余HP: %d)\n" % [attacker, target, dmg, roll_str, int(rem_hp)])


func _reset_match() -> void:
	_is_match_over = false
	_combat_mgr.reset_health()
	if _match_over_dialog != null:
		_match_over_dialog.visible = false
	if _battle_banner != null:
		_battle_banner.visible = false

	if _player != null:
		_player.global_position = Vector3(0.0, 1.1, 4.5)
		_player.rotation.y = deg_to_rad(0.0)
		_player.reset_combat_state()
	if _npc != null:
		_npc.global_position = Vector3(0.0, 1.1, -4.5)
		_npc.rotation.y = deg_to_rad(180.0)
		_npc.reset_combat_state()

	if _ai_controller != null:
		_ai_controller.reset()

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- VFX Floating Numbers ---------------------------------------------------

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
		lbl.text = "-%d HP (翻滚50%%)" % int(dmg)
		lbl.modulate = Color(1.0, 0.88, 0.2, 1.0)
	else:
		lbl.text = "-%d HP" % int(dmg)
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
			get_tree().change_scene_to_file(MENU_SCENE)
			return
		elif event.keycode == KEY_F1:
			_reset_match()
		elif event.keycode == KEY_J or event.keycode == KEY_H:
			if _dev_panel != null:
				_dev_panel.visible = not _dev_panel.visible
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not _is_match_over:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
