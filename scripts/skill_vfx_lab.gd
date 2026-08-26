extends Node3D
## Interactive Skill and VFX Sandbox Inspector.
## Left: Skill Candidates, Right: Dedicated Configuration, [F2]: Player/Dummy Control Switch, [L]: Immersive Mode.

const CharacterPipelineScript = preload("res://tools/character_pipeline.gd")
const PlayerControllerScript = preload("res://scripts/player_controller.gd")
const PlayerIntentSourceScript = preload("res://scripts/player_intent_source.gd")
const FollowCameraScript = preload("res://scripts/follow_camera.gd")
const SkillRegistryScript = preload("res://scripts/skills/skill_registry.gd")
const SkillStealthScript = preload("res://scripts/skills/skill_stealth.gd")
const SkillCloneScript = preload("res://scripts/skills/skill_clone.gd")
const EquipmentManagerScript = preload("res://scripts/equipment_manager.gd")
const WeaponConfigScript = preload("res://scripts/weapon_config.gd")
const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const MainMenuScript = preload("res://scripts/main_menu.gd")

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const FONT_PATH := "res://assets/Fonts/Long_Cang/LongCang-Regular.ttf"
const FONT_GLITCH_PATH := "res://assets/Fonts/Long_Cang,Rubik_Glitch/Rubik_Glitch/RubikGlitch-Regular.ttf"

## 技能图标目录与映射：图片文件名（去扩展名）即面板显示的技能名。
const SKILL_ICON_DIR := "res://assets/skills_icon"
## 技能面板图标显示尺寸（px），略大于面板文字以便看清。
const SKILL_ICON_SIZE := 36
const SKILL_ICONS := {
	"teleport": "过隙.png",
	"stealth": "褪形.png",
	"entangle": "生生缚.png",
	"grapple": "牵魂引.png",
	"sand": "归墟陷.png",
	"wall": "红莲断.png",
	"clone": "镜中客.png",
	"mist": "无明夜.png",
	"slam": "撼昆仑.png",
	"jump_buff": "折桂登云.png",
	"cleanse": "洗髓还真.png",
}


## 面板显示名：有图标映射时用图片名，否则回退技能自带名。
func _panel_skill_name(skill_id: String, fallback: String) -> String:
	var fname: String = SKILL_ICONS.get(skill_id, "")
	if fname.is_empty():
		return fallback
	return fname.get_basename()


## 面板图标：按映射加载，未映射或加载失败返回 null。
func _panel_skill_icon(skill_id: String) -> Texture2D:
	var fname: String = SKILL_ICONS.get(skill_id, "")
	if fname.is_empty():
		return null
	return load(SKILL_ICON_DIR.path_join(fname)) as Texture2D

## Fly Camera constants
const LOOK_SENS := 0.0026
const PITCH_LIMIT := 1.5
const FLY_DAMP := 12.0
const FLY_SPRINT := 2.5
const FLY_MIN := 2.0
const FLY_MAX := 40.0

## Replay Phase Timing
const REPLAY_START_HOLD := 0.50

enum LabMode {
	PLAYER_CONTROL,
	GLOBAL_SPECTATE
}

enum ControlTarget {
	PLAYER,
	DUMMY
}

enum ReplayState {
	IDLE_AT_START,
	HOLD_AT_TARGET
}

## Null intent source to ensure inactive entities never receive keyboard input.
class IdleIntentSource extends IntentSource:
	func poll(_body: Node, _delta: float, intent: CharacterIntent) -> void:
		intent.clear()

# Mode & Control Target
var _mode: int = LabMode.PLAYER_CONTROL
var _control_target: int = ControlTarget.PLAYER
var _player_hero_id: String = "hero_1"
var _dummy_hero_id: String = "hero_2"

# Entity References
var _camera: FollowCameraScript
var _builder_camera: Camera3D
var _cam_yaw: float = 0.0
var _cam_pitch: float = -0.35
var _cam_velocity: Vector3 = Vector3.ZERO
var _fly_speed: float = 12.0

var _player: PlayerControllerScript
var _dummy_player: PlayerControllerScript
var _intent: PlayerIntentSourceScript
var _idle_intent: IdleIntentSource
var _player_visual: Node3D
var _dummy_visual: Node3D
var _dummy_tag_lbl: Label3D
var _player_tag_lbl: Label3D
var _vfx_root: Node3D

# Ground-targeted skill aim state (hold F + move mouse, release to cast)
var _aiming: bool = false
var _aim_pos: Vector3 = Vector3.ZERO
var _aim_cursor: Node3D = null

# Active Skill & Registry
var _current_skill_id: String = "teleport"
var _skill_buttons: Dictionary = {}

# Replay State
var _replay_state: int = ReplayState.IDLE_AT_START
var _replay_timer: float = 0.0
var _last_cast_record: Dictionary = {}

# UI & Immersive Mode
var _canvas: CanvasLayer
var _ui_root: Control
var _is_immersive: bool = false
var _sub_header_lbl: Label
var _mode_badge_lbl: Label
var _char_picker: OptionButton
var _weapon_picker: OptionButton
var _switch_target_btn: Button
var _custom_font: Font = null
var _glitch_font: Font = null

# Equipment & Weapons
var _player_equip: EquipmentManager
var _dummy_equip: EquipmentManager
var _current_weapon_id: String = ""
var _configured_weapons: Array[String] = []

# --- Health Bar & Combat System (PVP Emulation) ---
var _player_max_hp: float = 1000.0
var _player_hp: float = 1000.0
var _dummy_max_hp: float = 1000.0
var _dummy_hp: float = 1000.0

var _health_hud: PanelContainer
var _player_hp_bar: ProgressBar
var _player_hp_lbl: Label
var _dummy_hp_bar: ProgressBar
var _dummy_hp_lbl: Label

# Blade & Melee Hit Check Tracking
const BLADE_PAD := 0.20
const HURT_RADIUS := 0.40
const HURT_LOW_Y := 0.20
const HURT_HIGH_Y := 1.65
var _player_prev_tip: Vector3 = Vector3.ZERO
var _player_has_tip: bool = false
var _player_blade_inside: bool = false
var _dummy_prev_tip: Vector3 = Vector3.ZERO
var _dummy_has_tip: bool = false
var _dummy_blade_inside: bool = false

# Floating Damage Number Pool
const VFX_POOL := 20
var _numbers: Array[Label3D] = []
var _number_tweens: Array[Tween] = []
var _number_next: int = 0

# Left Sidebar (Candidate List) & Right Sidebar (Config)
var _left_sidebar: PanelContainer
var _right_sidebar: PanelContainer
var _skill_select_vbox: VBoxContainer
var _skill_panel_box: VBoxContainer
var _skill_title_lbl: Label
var _cast_btn: Button

# Sky Environment & Panorama List
var _world_env: WorldEnvironment
var _current_sky_idx: int = 0
const SKY_PRESETS: Array[Dictionary] = [
	{
		"name": "🌌 幽蓝余烬夜空 (Pure Dark Celestial)",
		"path": "res://assets/sky_image/Pure_Dark_Celestial_Sky.jpg",
		"sun_energy": 0.85,
		"sun_color": Color(0.85, 0.92, 1.0),
		"ambient_energy": 0.45,
		"ground_color": Color(0.12, 0.14, 0.18)
	},
	{
		"name": "🌅 凄美残阳暮色 (Pure Twilight Sky Dome)",
		"path": "res://assets/sky_image/Pure_Twilight_Sky_Dome.jpg",
		"sun_energy": 1.3,
		"sun_color": Color(1.0, 0.75, 0.55),
		"ambient_energy": 0.6,
		"ground_color": Color(0.16, 0.13, 0.12)
	},
	{
		"name": "☁️ 苍穹阴云雷暴 (Pure Overcast Tempest)",
		"path": "res://assets/sky_image/Pure_Overcast_Tempest_Sky.jpg",
		"sun_energy": 1.0,
		"sun_color": Color(0.92, 0.95, 1.0),
		"ambient_energy": 0.55,
		"ground_color": Color(0.14, 0.15, 0.17)
	},
	{
		"name": "🎨 默认程序化天空 (Procedural Sky)",
		"path": "",
		"sun_energy": 1.1,
		"sun_color": Color(1.0, 0.95, 0.85),
		"ambient_energy": 0.5,
		"ground_color": Color(0.14, 0.16, 0.20)
	}
]
var _sun_light: DirectionalLight3D
var _ground_mat: StandardMaterial3D

func _ready() -> void:
	AudioManagerScript.init_pool(self)
	SkillRegistryScript.init_registry()
	SkillRegistryScript.reset_all_state()
	SkillRegistryScript.warmup_all_shaders(self)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Engine.time_scale = 1.0

	_idle_intent = IdleIntentSource.new()
	_intent = PlayerIntentSourceScript.new()

	if ResourceLoader.exists(FONT_PATH):
		_custom_font = load(FONT_PATH) as Font
	if ResourceLoader.exists(FONT_GLITCH_PATH):
		_glitch_font = load(FONT_GLITCH_PATH) as Font

	_load_configured_weapons()
	_build_scene_environment()
	_build_damage_number_pool()
	_build_builder_camera()
	_build_player()
	_build_dummy()
	_build_ui()

	_set_lab_mode(LabMode.PLAYER_CONTROL)
	AudioManagerScript.play_voice_file("res://assets/voice/Voiceover Pack/Male/prepare.ogg", 0.0)


func _load_configured_weapons() -> void:
	_configured_weapons.clear()
	var raw_list := WeaponConfigScript.list_configured()
	for id in raw_list:
		if WeaponConfigScript.has_config(id) and WeaponConfigScript.mesh_scene_for(id) != null:
			_configured_weapons.append(id)

func _process(delta: float) -> void:
	_check_blade_hits()
	if _aiming:
		_update_aim()
	if _mode == LabMode.GLOBAL_SPECTATE:
		_update_builder_flight(delta)
		_update_replay_loop(delta)

func _unhandled_input(event: InputEvent) -> void:
	# F key release ends aiming and casts the ground-targeted skill at the chosen spot.
	if event is InputEventKey and not event.pressed and event.keycode == KEY_F:
		if _aiming:
			get_viewport().set_input_as_handled()
			_finish_aim(true)
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			var vp := get_viewport()
			if vp != null:
				vp.set_input_as_handled()

			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				Engine.time_scale = 1.0
				MainMenuScript.open_dev_menu_on_enter = true
				SceneLoader.change_scene(get_tree(), MAIN_MENU_SCENE, "返回开发者工作台...")
			return
		elif event.keycode == KEY_TAB:
			var vp := get_viewport()
			if vp != null:
				vp.set_input_as_handled()
			var next_mode := LabMode.GLOBAL_SPECTATE if _mode == LabMode.PLAYER_CONTROL else LabMode.PLAYER_CONTROL
			_set_lab_mode(next_mode)
			return
		elif event.keycode == KEY_F2: # Toggle Player / Dummy Control
			var vp := get_viewport()
			if vp != null:
				vp.set_input_as_handled()
			_toggle_control_target()
			return
		elif event.keycode == KEY_L: # Toggle Immersive Experience
			var vp := get_viewport()
			if vp != null:
				vp.set_input_as_handled()
			_toggle_immersive_mode()
			return
		elif event.keycode == KEY_F3: # Toggle First Person Perspective
			var vp := get_viewport()
			if vp != null:
				vp.set_input_as_handled()
			if _camera != null:
				_camera.toggle_first_person()
			return
		elif event.keycode == KEY_F4: # Switch Sky Panorama Texture
			var vp := get_viewport()
			if vp != null:
				vp.set_input_as_handled()
			_cycle_sky_panorama()
			return
		elif event.keycode == KEY_F5: # Restore / Reset HP (Heal All)
			var vp := get_viewport()
			if vp != null:
				vp.set_input_as_handled()
			_heal_all_full()
			return
		elif event.keycode == KEY_Q:
			var vp := get_viewport()
			if vp != null:
				vp.set_input_as_handled()
			_cast_current_skill()
			return
		elif event.keycode == KEY_F:
			var vp := get_viewport()
			if vp != null:
				vp.set_input_as_handled()
			if _mode == LabMode.PLAYER_CONTROL and _skill_supports_aim(_current_skill_id):
				_begin_aim()
			else:
				_cast_current_skill()
			return
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var vp := get_viewport()
			if vp != null:
				vp.set_input_as_handled()
			var idx: int = event.keycode - KEY_1
			var all_skills: Array = SkillRegistryScript.get_all_skills()
			if idx < all_skills.size():
				var s: RefCounted = all_skills[idx]
				_select_skill(s.call("get_id"))
			return
		elif event.keycode == KEY_0:
			var vp := get_viewport()
			if vp != null:
				vp.set_input_as_handled()
			var all_skills: Array = SkillRegistryScript.get_all_skills()
			if all_skills.size() >= 10:
				_select_skill(all_skills[9].call("get_id"))
			return
		elif event.keycode == KEY_MINUS:
			var vp := get_viewport()
			if vp != null:
				vp.set_input_as_handled()
			var all_skills: Array = SkillRegistryScript.get_all_skills()
			if all_skills.size() >= 11:
				_select_skill(all_skills[10].call("get_id"))
			return
		elif event.keycode == KEY_EQUAL:
			var vp := get_viewport()
			if vp != null:
				vp.set_input_as_handled()
			var all_skills: Array = SkillRegistryScript.get_all_skills()
			if all_skills.size() >= 12:
				_select_skill(all_skills[11].call("get_id"))
			return
		elif event.keycode == KEY_BRACKETLEFT or event.keycode == KEY_BACKSPACE:
			var vp := get_viewport()
			if vp != null:
				vp.set_input_as_handled()
			var all_skills: Array = SkillRegistryScript.get_all_skills()
			if all_skills.size() >= 13:
				_select_skill(all_skills[12].call("get_id"))
			return
		elif event.keycode == KEY_BRACKETRIGHT:
			var vp := get_viewport()
			if vp != null:
				vp.set_input_as_handled()
			var all_skills: Array = SkillRegistryScript.get_all_skills()
			if all_skills.size() >= 14:
				_select_skill(all_skills[13].call("get_id"))
			return
		elif event.keycode == KEY_QUOTELEFT: # Tilde to toggle mouse
			var vp := get_viewport()
			if vp != null:
				vp.set_input_as_handled()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
			return

	if _mode == LabMode.GLOBAL_SPECTATE and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseMotion:
			_cam_yaw -= event.relative.x * LOOK_SENS
			_cam_pitch = clampf(_cam_pitch - event.relative.y * LOOK_SENS, -PITCH_LIMIT, PITCH_LIMIT)
			_apply_builder_orientation()
			get_viewport().set_input_as_handled()
			return
		elif event is InputEventMouseButton and event.pressed:
			match event.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					_fly_speed = clampf(_fly_speed * 1.15, FLY_MIN, FLY_MAX)
				MOUSE_BUTTON_WHEEL_DOWN:
					_fly_speed = clampf(_fly_speed / 1.15, FLY_MIN, FLY_MAX)

func _toggle_control_target() -> void:
	if _mode == LabMode.GLOBAL_SPECTATE:
		_set_lab_mode(LabMode.PLAYER_CONTROL)

	SkillCloneScript.clear_all()

	if _control_target == ControlTarget.PLAYER:
		_control_target = ControlTarget.DUMMY
		if _player != null:
			_player.intent_source = _idle_intent
			_player.velocity = Vector3.ZERO
		if _dummy_player != null:
			_dummy_player.intent_source = _intent
			_camera.target = _dummy_player
			_camera.snap()
	else:
		_control_target = ControlTarget.PLAYER
		if _dummy_player != null:
			_dummy_player.intent_source = _idle_intent
			_dummy_player.velocity = Vector3.ZERO
		if _player != null:
			_player.intent_source = _intent
			_camera.target = _player
			_camera.snap()

	# Dynamically update stealth appearance so opposing actor sees absolute invisibility
	SkillStealthScript.update_perspective(_get_active_actor(), false)
	_update_target_labels()
	_update_header_text()
	_sync_character_picker_selection()

func _update_target_labels() -> void:
	var p_bar_str := _generate_ascii_hp_bar(_player_hp, _player_max_hp)
	var d_bar_str := _generate_ascii_hp_bar(_dummy_hp, _dummy_max_hp)

	if _player_tag_lbl != null:
		if _control_target == ControlTarget.PLAYER:
			_player_tag_lbl.text = "🕹️ 主角色 (操控中)\n%s %d/%d" % [p_bar_str, int(_player_hp), int(_player_max_hp)]
			_player_tag_lbl.modulate = Color(0.3, 0.95, 1.0)
		else:
			_player_tag_lbl.text = "👤 主角色 [按 F2 切回]\n%s %d/%d" % [p_bar_str, int(_player_hp), int(_player_max_hp)]
			_player_tag_lbl.modulate = Color(0.7, 0.8, 0.9, 0.8)

	if _dummy_tag_lbl != null:
		if _control_target == ControlTarget.DUMMY:
			_dummy_tag_lbl.text = "🎯 训练假人 (操控中)\n%s %d/%d" % [d_bar_str, int(_dummy_hp), int(_dummy_max_hp)]
			_dummy_tag_lbl.modulate = Color(1.0, 0.85, 0.2)
		else:
			_dummy_tag_lbl.text = "🎯 训练假人 [按 F2 操控]\n%s %d/%d" % [d_bar_str, int(_dummy_hp), int(_dummy_max_hp)]
			_dummy_tag_lbl.modulate = Color(1.0, 0.6, 0.2, 0.8)

	if _switch_target_btn != null:
		if _control_target == ControlTarget.PLAYER:
			_switch_target_btn.text = "🔄 当前操控: 【玩家】 (按 F2 切换假人)"
			_switch_target_btn.modulate = Color(0.5, 1.0, 1.0)
		else:
			_switch_target_btn.text = "🔄 当前操控: 【假人】 (按 F2 切回玩家)"
			_switch_target_btn.modulate = Color(1.0, 0.85, 0.3)


func _generate_ascii_hp_bar(cur: float, max_v: float) -> String:
	var ratio := clampf(cur / maxf(1.0, max_v), 0.0, 1.0)
	var filled := int(round(ratio * 10.0))
	var s := "["
	for i in range(10):
		if i < filled:
			s += "█"
		else:
			s += "░"
	s += "]"
	return s

func _get_active_actor() -> PlayerControllerScript:
	if _control_target == ControlTarget.DUMMY and _dummy_player != null and is_instance_valid(_dummy_player):
		return _dummy_player
	return _player

func _toggle_immersive_mode() -> void:
	_is_immersive = not _is_immersive
	if _left_sidebar != null:
		_left_sidebar.visible = not _is_immersive
	if _right_sidebar != null:
		_right_sidebar.visible = not _is_immersive
	_update_header_text()

func _update_header_text() -> void:
	if _sub_header_lbl == null:
		return

	if _is_immersive:
		_sub_header_lbl.text = "🌟 [沉浸式模式] [L]开关侧栏 | [F2]切假人/玩家 | [F3]第一人称 | [F4]切天空 | [Q]释放技能 | [1-9]切技能 | [TAB]全局观战"
		_sub_header_lbl.modulate = Color(1.0, 0.9, 0.4)
	else:
		if _mode == LabMode.PLAYER_CONTROL:
			var target_str := "【玩家】" if _control_target == ControlTarget.PLAYER else "【假人】"
			_sub_header_lbl.text = "WASD移动 | [Q]释放技能(%s) | [F2]切换假人/玩家 | [F3]第一人称 | [F4]切天空 | [1-9]切技能 | [L]沉浸式 | [TAB]观战" % target_str
			_sub_header_lbl.modulate = Color(0.7, 0.8, 0.9)
		else:
			_sub_header_lbl.text = "WASD自由飞行漫游 | 滚轮调速 | [Q]重触发 | [F2]切换目标 | [F4]切天空 | [L]沉浸式 | [TAB]返回控制"
			_sub_header_lbl.modulate = Color(0.7, 0.8, 0.9)

	if _mode_badge_lbl != null:
		if _mode == LabMode.PLAYER_CONTROL:
			if _control_target == ControlTarget.PLAYER:
				_mode_badge_lbl.text = "🕹️ 玩家操控视角 [按 F2 切换假人操控 | 按 TAB 进入全局视角]"
				_mode_badge_lbl.modulate = Color(0.3, 0.95, 1.0)
			else:
				_mode_badge_lbl.text = "🎯 假人操控视角 [按 F2 切回玩家操控 | 按 TAB 进入全局视角]"
				_mode_badge_lbl.modulate = Color(1.0, 0.85, 0.2)
		else:
			_mode_badge_lbl.text = "🎥 全局视角模式 (正在反复复刻最后一次技能他人视角) [按 TAB 返回操控]"
			_mode_badge_lbl.modulate = Color(1.0, 0.85, 0.2)

func _set_lab_mode(new_mode: int) -> void:
	_mode = new_mode
	_cancel_aim()
	SkillCloneScript.clear_all()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	match _mode:
		LabMode.PLAYER_CONTROL:
			_camera.current = true
			_builder_camera.current = false
			var active_actor := _get_active_actor()
			if active_actor != null:
				active_actor.intent_source = _intent
				_camera.target = active_actor
				_camera.snap()
			var inactive_actor := _dummy_player if _control_target == ControlTarget.PLAYER else _player
			if inactive_actor != null:
				inactive_actor.intent_source = _idle_intent
				inactive_actor.velocity = Vector3.ZERO
			SkillStealthScript.update_perspective(active_actor, false)
			_update_target_labels()

		LabMode.GLOBAL_SPECTATE:
			_camera.current = false
			_builder_camera.current = true
			if _player != null:
				_player.intent_source = _idle_intent
				_player.velocity = Vector3.ZERO
			if _dummy_player != null:
				_dummy_player.intent_source = _idle_intent
				_dummy_player.velocity = Vector3.ZERO

			var active_actor := _get_active_actor()
			SkillStealthScript.update_perspective(active_actor, true)

			if _last_cast_record.is_empty() and active_actor != null:
				var fwd: Vector3 = active_actor.global_basis.z
				fwd.y = 0.0
				var move_d := fwd.normalized() if fwd.length_squared() > 0.01 else Vector3(0, 0, 1)
				_last_cast_record = {
					"skill_id": _current_skill_id,
					"from_pos": active_actor.global_position,
					"direction": move_d,
					"actor": active_actor
				}

			var from_p: Vector3 = _last_cast_record.get("from_pos", Vector3.ZERO)
			var m_dir: Vector3 = _last_cast_record.get("direction", Vector3(0, 0, 1))
			var mid_p := from_p + m_dir * 3.0

			var side_offset := Vector3(m_dir.z, 0.0, -m_dir.x).normalized() * 5.2
			_builder_camera.global_position = mid_p + side_offset + Vector3.UP * 3.2 - m_dir * 1.5
			var cam_look := (mid_p + Vector3.UP * 0.9 - _builder_camera.global_position).normalized()
			_cam_yaw = atan2(-cam_look.x, -cam_look.z)
			_cam_pitch = asin(cam_look.y)
			_apply_builder_orientation()

			_replay_state = ReplayState.IDLE_AT_START
			_replay_timer = 0.0
			_reset_replay_to_start()

	_update_header_text()

func _update_builder_flight(delta: float) -> void:
	if _builder_camera == null:
		return
	var wish := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): wish += -_builder_camera.global_transform.basis.z
	if Input.is_physical_key_pressed(KEY_S): wish += _builder_camera.global_transform.basis.z
	if Input.is_physical_key_pressed(KEY_A): wish += -_builder_camera.global_transform.basis.x
	if Input.is_physical_key_pressed(KEY_D): wish += _builder_camera.global_transform.basis.x
	if Input.is_physical_key_pressed(KEY_SPACE): wish += Vector3.UP
	if Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_C): wish += Vector3.DOWN

	if wish.length_squared() > 0.001:
		wish = wish.normalized()
		var spd := _fly_speed * (FLY_SPRINT if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
		_cam_velocity = _cam_velocity.lerp(wish * spd, 1.0 - exp(-FLY_DAMP * delta))
	else:
		_cam_velocity = _cam_velocity.lerp(Vector3.ZERO, 1.0 - exp(-FLY_DAMP * delta))

	_builder_camera.global_position += _cam_velocity * delta

func _apply_builder_orientation() -> void:
	if _builder_camera != null:
		_builder_camera.global_transform = Transform3D(
			Basis.from_euler(Vector3(_cam_pitch, _cam_yaw, 0.0)),
			_builder_camera.global_position
		)

func _update_replay_loop(delta: float) -> void:
	_replay_timer += delta
	match _replay_state:
		ReplayState.IDLE_AT_START:
			if _replay_timer >= REPLAY_START_HOLD:
				_replay_timer = 0.0
				_replay_state = ReplayState.HOLD_AT_TARGET
				_execute_replay_cast()

		ReplayState.HOLD_AT_TARGET:
			var cur_skill: RefCounted = SkillRegistryScript.get_skill(_current_skill_id)
			var hold_limit: float = cur_skill.call("get_replay_hold_time", _last_cast_record) if cur_skill != null else 1.30

			if _replay_timer >= hold_limit:
				_replay_timer = 0.0
				_replay_state = ReplayState.IDLE_AT_START
				_reset_replay_to_start()

func _reset_replay_to_start() -> void:
	var actor := _get_active_actor()
	if actor == null or not is_instance_valid(actor):
		return

	SkillStealthScript.end_stealth(actor)

	var from_p: Vector3 = _last_cast_record.get("from_pos", Vector3(0.0, 0.1, 0.0))
	var m_dir: Vector3 = _last_cast_record.get("direction", Vector3(0.0, 0.0, 1.0))

	actor.global_position = from_p
	if m_dir.length_squared() > 0.001:
		actor.rotation.y = atan2(m_dir.x, m_dir.z)
	actor.velocity = Vector3.ZERO

func _execute_replay_cast() -> void:
	var actor := _get_active_actor()
	if actor == null or not is_instance_valid(actor):
		return

	var skill: RefCounted = SkillRegistryScript.get_skill(_current_skill_id)
	if skill != null:
		skill.call("replay", actor, _last_cast_record, _vfx_root)

func _cast_current_skill() -> void:
	var actor := _get_active_actor()
	if actor == null or not is_instance_valid(actor):
		return

	var skill: RefCounted = SkillRegistryScript.get_skill(_current_skill_id)
	if skill == null:
		return

	if _mode == LabMode.GLOBAL_SPECTATE:
		_reset_replay_to_start()
		_replay_state = ReplayState.HOLD_AT_TARGET
		_replay_timer = 0.0
		_execute_replay_cast()
		return

	# Calculate current movement/facing direction
	var input_vec: Vector2 = _intent._move_vector() if _intent != null else Vector2.ZERO
	var move_dir := Vector3.ZERO
	if input_vec.length_squared() > 0.01:
		var cam_yaw: float = float(_camera.yaw) if _camera != null else actor.rotation.y
		var frame := Basis.from_euler(Vector3(0.0, cam_yaw, 0.0))
		move_dir = (frame.z * input_vec.y - frame.x * input_vec.x).normalized()
	else:
		move_dir = actor.global_basis.z
		move_dir.y = 0.0
		move_dir = move_dir.normalized()

	var record: Dictionary = skill.call("cast", actor, move_dir, _vfx_root, false)
	if record.get("success", true) == false:
		if record.get("reason") == "no_target":
			if _sub_header_lbl != null:
				_sub_header_lbl.text = "⚠️ [索敌失败] 正前方射程内未命中目标，技能未触发！"
				_sub_header_lbl.modulate = Color(1.0, 0.35, 0.2)
		return

	_last_cast_record = record
	_last_cast_record["actor"] = actor

# --- Ground-targeted skills aim & cast ---

func _skill_supports_aim(id: String) -> bool:
	return id == "sand" or id == "wall" or id == "sword_rain" or id == "skyfire" or id == "hammer_beam" or id == "glass_shatter"


func _begin_aim() -> void:
	_aiming = true
	_build_aim_cursor()
	_update_aim()


func _update_aim() -> void:
	if _aim_cursor == null or not is_instance_valid(_aim_cursor):
		return
	var skill: RefCounted = SkillRegistryScript.get_skill(_current_skill_id)
	var raw_cast_r = skill.get("cast_range") if skill != null else null
	var cast_r: float = float(raw_cast_r) if raw_cast_r != null else 16.0

	var actor := _get_active_actor()
	var aim := _ground_aim_point(actor)
	var from := actor.global_position if actor != null and is_instance_valid(actor) else Vector3.ZERO
	if cast_r > 0.0:
		var dh := Vector3(aim.x - from.x, 0.0, aim.z - from.z)
		if dh.length() > cast_r:
			dh = dh.normalized() * cast_r
			aim = Vector3(from.x + dh.x, 0.03, from.z + dh.z)

	_aim_pos = aim
	_aim_cursor.global_position = aim

	match _current_skill_id:
		"sand":
			var raw_val = skill.get("sand_radius") if skill != null else null
			var skill_r: float = float(raw_val) if raw_val != null else 4.0
			_aim_cursor.scale = Vector3(skill_r, 1.0, skill_r)
		"sword_rain":
			var raw_val = skill.get("strike_radius") if skill != null else null
			var skill_r: float = float(raw_val) if raw_val != null else 4.8
			_aim_cursor.scale = Vector3(skill_r, 1.0, skill_r)
		"skyfire":
			var raw_val = skill.get("strike_radius") if skill != null else null
			var skill_r: float = float(raw_val) if raw_val != null else 4.5
			_aim_cursor.scale = Vector3(skill_r, 1.0, skill_r)
		"hammer_beam":
			var raw_val = skill.get("beam_radius") if skill != null else null
			var beam_r: float = float(raw_val) if raw_val != null else 1.1
			_aim_cursor.scale = Vector3(beam_r * 2.6, 1.0, beam_r * 2.6)
		"glass_shatter":
			_aim_cursor.scale = Vector3(2.5, 1.0, 2.5)
		"wall":
			var raw_val = skill.get("wall_length") if skill != null else null
			var wall_len: float = float(raw_val) if raw_val != null else 6.0
			var aim_dir := aim - from
			aim_dir.y = 0.0
			if aim_dir.length_squared() < 0.001:
				aim_dir = Vector3(0.0, 0.0, 1.0)
			else:
				aim_dir = aim_dir.normalized()
			# Wall runs perpendicular to the actor→aim line.
			_aim_cursor.scale = Vector3(wall_len, 1.0, 1.0)
			_aim_cursor.rotation.y = atan2(aim_dir.x, aim_dir.z)


func _finish_aim(do_cast: bool) -> void:
	if not _aiming:
		return
	var pos := _aim_pos
	_cancel_aim()
	if do_cast:
		_cast_at(pos)


func _cancel_aim() -> void:
	_aiming = false
	if _aim_cursor != null and is_instance_valid(_aim_cursor):
		_aim_cursor.visible = false


func _ground_aim_point(actor: Node3D) -> Vector3:
	var fallback := Vector3.ZERO
	if actor != null and is_instance_valid(actor):
		fallback = actor.global_position + actor.global_basis.z * 6.0
		fallback.y = 0.03
	if _camera == null or not is_instance_valid(_camera):
		return fallback
	var origin := _camera.global_position
	var dir := -_camera.global_transform.basis.z
	if dir.y > -0.001:
		return fallback
	var t := -origin.y / dir.y
	if t < 0.0:
		return fallback
	var hit := origin + dir * t
	hit.y = 0.03
	return hit


func _cast_at(pos: Vector3) -> void:
	var actor := _get_active_actor()
	if actor == null or not is_instance_valid(actor):
		return
	var skill: RefCounted = SkillRegistryScript.get_skill(_current_skill_id)
	if skill == null:
		return
	var record: Dictionary = skill.call("cast_at", actor, pos, _vfx_root, false)
	if not record.is_empty():
		_last_cast_record = record
		_last_cast_record["actor"] = actor


func _build_aim_cursor() -> void:
	if _aim_cursor != null and is_instance_valid(_aim_cursor):
		_aim_cursor.queue_free()
	_aim_cursor = null
	if _vfx_root == null or not is_instance_valid(_vfx_root):
		return

	var cursor := Node3D.new()
	cursor.name = "AimCursor"
	match _current_skill_id:
		"wall":
			cursor.add_child(_make_wall_cursor_mesh())
		_:
			cursor.add_child(_make_sand_cursor_disc())
			cursor.add_child(_make_sand_cursor_ring())
	_vfx_root.add_child(cursor)
	_aim_cursor = cursor


func _make_sand_cursor_disc() -> MeshInstance3D:
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 1.0
	dm.bottom_radius = 1.0
	dm.height = 0.04
	dm.radial_segments = 48
	disc.mesh = dm
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.albedo_color = Color(0.75, 0.6, 0.25, 0.32)
	dmat.emission_enabled = true
	dmat.emission = Color(0.85, 0.68, 0.22)
	dmat.emission_energy_multiplier = 0.7
	disc.material_override = dmat
	return disc


func _make_sand_cursor_ring() -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 0.94
	rm.outer_radius = 1.0
	rm.rings = 40
	rm.ring_segments = 5
	ring.mesh = rm
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.albedo_color = Color(0.9, 0.72, 0.3, 0.7)
	rmat.emission_enabled = true
	rmat.emission = Color(0.85, 0.68, 0.22)
	rmat.emission_energy_multiplier = 1.4
	ring.material_override = rmat
	return ring


func _make_wall_cursor_mesh() -> MeshInstance3D:
	var bar := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 0.12, 0.12)
	bar.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.albedo_color = Color(1.0, 0.45, 0.08, 0.55)
	bmat.emission_enabled = true
	bmat.emission = Color(1.0, 0.4, 0.05)
	bmat.emission_energy_multiplier = 1.5
	bar.material_override = bmat
	bar.position.y = 0.08
	return bar

func _on_skill_param_changed(key: String, val: Variant) -> void:
	var skill: RefCounted = SkillRegistryScript.get_skill(_current_skill_id)
	if skill != null:
		skill.call("set_param", key, val)
	_last_cast_record[key] = val

func _build_scene_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.2

	_world_env = WorldEnvironment.new()
	_world_env.name = "WorldEnvironment"
	_world_env.environment = env
	add_child(_world_env)

	_sun_light = DirectionalLight3D.new()
	_sun_light.name = "SunLight"
	_sun_light.shadow_enabled = true
	_sun_light.transform.basis = Basis.from_euler(Vector3(deg_to_rad(-45.0), deg_to_rad(135.0), 0.0))
	add_child(_sun_light)

	# Apply initial sky preset (Pure Dark Celestial Sky)
	_apply_sky_preset(_current_sky_idx)

	# Ground
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var g_shape := CollisionShape3D.new()
	var g_box := BoxShape3D.new()
	g_box.size = Vector3(80.0, 0.4, 80.0)
	g_shape.shape = g_box
	g_shape.position.y = -0.2
	ground.add_child(g_shape)

	var g_mesh := BoxMesh.new()
	g_mesh.size = Vector3(80.0, 0.4, 80.0)
	_ground_mat = StandardMaterial3D.new()
	_ground_mat.albedo_color = Color(0.12, 0.14, 0.18)
	_ground_mat.roughness = 0.8
	var g_inst := MeshInstance3D.new()
	g_inst.mesh = g_mesh
	g_inst.material_override = _ground_mat
	g_inst.position.y = -0.2
	ground.add_child(g_inst)
	add_child(ground)

	# Grid Lines (Created on startup)
	var imm := ImmediateMesh.new()
	imm.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(-40, 41):
		var major := i % 5 == 0
		var col := Color(0.0, 0.9, 1.0, 0.4) if major else Color(0.25, 0.35, 0.45, 0.2)
		imm.surface_set_color(col)
		imm.surface_add_vertex(Vector3(i, 0.005, -40))
		imm.surface_add_vertex(Vector3(i, 0.005, 40))
		imm.surface_set_color(col)
		imm.surface_add_vertex(Vector3(-40, 0.005, i))
		imm.surface_add_vertex(Vector3(40, 0.005, i))
	imm.surface_end()

	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.vertex_color_use_as_albedo = true
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var line_node := MeshInstance3D.new()
	line_node.mesh = imm
	line_node.material_override = line_mat
	add_child(line_node)

	_vfx_root = Node3D.new()
	_vfx_root.name = "VFXRoot"
	add_child(_vfx_root)


func _apply_sky_preset(idx: int) -> void:
	if _world_env == null or _world_env.environment == null:
		return
	if idx < 0 or idx >= SKY_PRESETS.size():
		idx = 0
	_current_sky_idx = idx
	var preset: Dictionary = SKY_PRESETS[idx]

	var sky_path: String = preset.get("path", "")
	var sky := Sky.new()

	if not sky_path.is_empty() and ResourceLoader.exists(sky_path):
		var pano_mat := PanoramaSkyMaterial.new()
		pano_mat.panorama = load(sky_path) as Texture2D
		sky.sky_material = pano_mat
	else:
		var proc_mat := ProceduralSkyMaterial.new()
		proc_mat.sky_top_color = Color(0.20, 0.28, 0.42)
		proc_mat.sky_horizon_color = Color(0.55, 0.58, 0.64)
		proc_mat.ground_bottom_color = Color(0.10, 0.12, 0.15)
		proc_mat.ground_horizon_color = Color(0.55, 0.58, 0.64)
		sky.sky_material = proc_mat

	_world_env.environment.sky = sky
	_world_env.environment.ambient_light_energy = float(preset.get("ambient_energy", 0.5))

	if _sun_light != null:
		_sun_light.light_energy = float(preset.get("sun_energy", 1.0))
		_sun_light.light_color = preset.get("sun_color", Color.WHITE)

	if _ground_mat != null:
		_ground_mat.albedo_color = preset.get("ground_color", Color(0.14, 0.16, 0.20))


func _cycle_sky_panorama() -> void:
	var next_idx := (_current_sky_idx + 1) % SKY_PRESETS.size()
	_apply_sky_preset(next_idx)
	var preset: Dictionary = SKY_PRESETS[_current_sky_idx]
	if _sub_header_lbl != null:
		_sub_header_lbl.text = "🌌 天空已切换: %s [按 F4 切换下一个]" % preset.get("name", "")
		_sub_header_lbl.modulate = Color(0.4, 0.95, 1.0)


func _build_player() -> void:
	_player = PlayerControllerScript.new()
	_player.name = "TestPlayer"
	_player.position = Vector3(0.0, 0.1, 0.0)
	_player.intent_source = _intent
	add_child(_player)

	_player.set_meta("take_hit_cb", func(hit_pos: Vector3, dmg: float, push: Vector3):
		_on_actor_hit(true, hit_pos, dmg, push)
	)

	_camera = FollowCameraScript.new()
	_camera.name = "Camera"
	_camera.fov = 55.0
	_camera.near = 0.05
	_camera.current = true
	add_child(_camera)

	_setup_character_actor(_player, _player_hero_id, false)

	_player_tag_lbl = Label3D.new()
	_player_tag_lbl.name = "PlayerTag"
	_player_tag_lbl.position = Vector3(0.0, 2.25, 0.0)
	_player_tag_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_player_tag_lbl.no_depth_test = true
	_player_tag_lbl.font_size = 22
	_player_tag_lbl.outline_size = 6
	_player_tag_lbl.outline_modulate = Color.BLACK
	_player.add_child(_player_tag_lbl)

func _build_dummy() -> void:
	_dummy_player = PlayerControllerScript.new()
	_dummy_player.name = "DummyPlayer"
	_dummy_player.position = Vector3(0.0, 0.1, -8.0)
	_dummy_player.rotation.y = 0.0
	_dummy_player.intent_source = _idle_intent
	add_child(_dummy_player)

	_dummy_player.set_meta("take_hit_cb", func(hit_pos: Vector3, dmg: float, push: Vector3):
		_on_actor_hit(false, hit_pos, dmg, push)
	)

	_setup_character_actor(_dummy_player, _dummy_hero_id, true)

	_dummy_tag_lbl = Label3D.new()
	_dummy_tag_lbl.name = "DummyTag"
	_dummy_tag_lbl.position = Vector3(0.0, 2.25, 0.0)
	_dummy_tag_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_dummy_tag_lbl.no_depth_test = true
	_dummy_tag_lbl.font_size = 22
	_dummy_tag_lbl.outline_size = 6
	_dummy_tag_lbl.outline_modulate = Color.BLACK
	_dummy_player.add_child(_dummy_tag_lbl)

	_update_target_labels()

func _build_builder_camera() -> void:
	_builder_camera = Camera3D.new()
	_builder_camera.name = "BuilderCamera"
	_builder_camera.fov = 65.0
	_builder_camera.near = 0.05
	_builder_camera.far = 400.0
	_builder_camera.current = false
	add_child(_builder_camera)
	_builder_camera.global_position = Vector3(6.0, 4.5, 6.0)
	_apply_builder_orientation()

func _setup_character_actor(body: PlayerControllerScript, hero_id: String, is_dummy: bool) -> void:
	if body == null or not is_instance_valid(body):
		return
	body.set_meta("hero_id", hero_id)

	# 挂载 / 保留 EquipmentManager 装备组件
	var equip: EquipmentManager = null
	for child in body.get_children():
		if child is EquipmentManager:
			equip = child
			break
	if equip == null:
		equip = EquipmentManagerScript.new()
		equip.name = "EquipManager"
		body.add_child(equip)

	if is_dummy:
		_dummy_equip = equip
	else:
		_player_equip = equip

	for child in body.get_children():
		if child is Node3D and child.name != "DummyTag" and child.name != "PlayerTag":
			child.queue_free()
		elif child is CollisionShape3D:
			child.queue_free()

	var scene_path := "res://assets/characters/%s/%s.tscn" % [hero_id, hero_id]
	if not ResourceLoader.exists(scene_path):
		scene_path = "res://assets/characters/hero_1/hero_1.tscn"

	var p_scene := load(scene_path) as PackedScene
	if p_scene != null:
		var visual := p_scene.instantiate() as Node3D
		if visual != null and is_instance_valid(body):
			if is_dummy:
				_dummy_visual = visual
			else:
				_player_visual = visual
			body.add_child(visual)

			var height: float = visual.get("body_height")
			if height <= 0.1:
				height = 1.75

			var collider := CollisionShape3D.new()
			var capsule := CapsuleShape3D.new()
			capsule.radius = minf(0.3, height * 0.2)
			capsule.height = height
			collider.shape = capsule
			collider.position.y = height * 0.5
			body.add_child(collider)

			body.velocity = Vector3.ZERO
			body.setup(visual, _camera)

			# 重新装备当前选中的武器
			if not _current_weapon_id.is_empty():
				equip.equip_by_id(_current_weapon_id)
			else:
				equip.unequip("right_hand")
				equip.unequip("left_hand")

			# Ensure proper intent source assignment
			if is_dummy and _control_target != ControlTarget.DUMMY:
				body.intent_source = _idle_intent
			elif not is_dummy and _control_target != ControlTarget.PLAYER:
				body.intent_source = _idle_intent
			else:
				body.intent_source = _intent

			if _camera.target == body:
				_camera.frame_for(height)
				_camera.snap()

func _switch_active_character_model(hero_id: String) -> void:
	if _control_target == ControlTarget.DUMMY:
		_dummy_hero_id = hero_id
		if _dummy_player != null:
			_setup_character_actor(_dummy_player, hero_id, true)
	else:
		_player_hero_id = hero_id
		if _player != null:
			_setup_character_actor(_player, hero_id, false)

func _sync_character_picker_selection() -> void:
	if _char_picker == null:
		return
	var cur_id := _dummy_hero_id if _control_target == ControlTarget.DUMMY else _player_hero_id
	for idx in range(_char_picker.item_count):
		if str(_char_picker.get_item_metadata(idx)) == cur_id:
			_char_picker.select(idx)
			break


func _switch_weapon(weapon_id: String) -> void:
	_current_weapon_id = weapon_id
	if _player_equip != null:
		if weapon_id.is_empty():
			_player_equip.unequip("right_hand")
			_player_equip.unequip("left_hand")
		else:
			_player_equip.equip_by_id(weapon_id)
	if _dummy_equip != null:
		if weapon_id.is_empty():
			_dummy_equip.unequip("right_hand")
			_dummy_equip.unequip("left_hand")
		else:
			_dummy_equip.equip_by_id(weapon_id)
	_sync_weapon_picker_selection()


func _sync_weapon_picker_selection() -> void:
	if _weapon_picker == null:
		return
	for idx in range(_weapon_picker.item_count):
		if str(_weapon_picker.get_item_metadata(idx)) == _current_weapon_id:
			_weapon_picker.select(idx)
			break

func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 20
	add_child(_canvas)

	_ui_root = Control.new()
	_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.add_child(_ui_root)

	_build_header(_ui_root)
	_build_health_hud(_ui_root)
	_build_left_sidebar(_ui_root)
	_build_right_sidebar(_ui_root)

func _build_header(root: Control) -> void:
	var header := PanelContainer.new()
	header.offset_left = 24
	header.offset_top = 16
	header.offset_right = 650
	header.offset_bottom = 106
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var h_style := StyleBoxFlat.new()
	h_style.bg_color = Color(0.06, 0.08, 0.12, 0.90)
	h_style.set_corner_radius_all(10)
	h_style.set_border_width_all(1)
	h_style.border_color = Color(0.0, 0.9, 1.0, 0.7)
	h_style.set_content_margin_all(12)
	header.add_theme_stylebox_override("panel", h_style)
	root.add_child(header)

	var h_vbox := VBoxContainer.new()
	h_vbox.add_theme_constant_override("separation", 4)
	header.add_child(h_vbox)

	var title := Label.new()
	title.text = "⚡ 技能与特效演练场 (SKILL & VFX LAB)"
	if _custom_font != null:
		title.add_theme_font_override("font", _custom_font)
	title.add_theme_font_size_override("font_size", 20)
	title.modulate = Color(0.0, 0.94, 1.0)
	h_vbox.add_child(title)

	_mode_badge_lbl = Label.new()
	_mode_badge_lbl.text = "🕹️ 玩家操控视角 [按 F2 切换假人操控 | 按 TAB 进入全局视角]"
	_mode_badge_lbl.add_theme_font_size_override("font_size", 13)
	_mode_badge_lbl.modulate = Color(0.3, 0.95, 1.0)
	h_vbox.add_child(_mode_badge_lbl)

	_sub_header_lbl = Label.new()
	_sub_header_lbl.text = "WASD移动 | [Q]释放技能 | [F2]切换假人/玩家 | [1-9]切技能 | [L]沉浸式 | [TAB]观战"
	_sub_header_lbl.add_theme_font_size_override("font_size", 11)
	_sub_header_lbl.modulate = Color(0.7, 0.8, 0.9)
	h_vbox.add_child(_sub_header_lbl)

func _build_left_sidebar(root: Control) -> void:
	_left_sidebar = PanelContainer.new()
	_left_sidebar.offset_left = 20
	_left_sidebar.offset_top = 110
	_left_sidebar.offset_right = 280
	_left_sidebar.offset_bottom = -20
	_left_sidebar.set_anchors_preset(Control.PRESET_LEFT_WIDE)

	var l_style := StyleBoxFlat.new()
	l_style.bg_color = Color(0.06, 0.08, 0.12, 0.94)
	l_style.set_corner_radius_all(12)
	l_style.set_border_width_all(1)
	l_style.border_color = Color(0.0, 0.85, 1.0, 0.75)
	l_style.set_content_margin_all(10)
	_left_sidebar.add_theme_stylebox_override("panel", l_style)
	root.add_child(_left_sidebar)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_theme_constant_override("separation", 8)
	_left_sidebar.add_child(outer_vbox)

	var title := Label.new()
	title.text = "📦 技能候选栏目\n(SKILL CANDIDATES)"
	if _glitch_font != null:
		title.add_theme_font_override("font", _glitch_font)
	title.add_theme_font_size_override("font_size", 13)
	title.modulate = Color(0.0, 0.92, 1.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer_vbox.add_child(title)

	var sep := HSeparator.new()
	outer_vbox.add_child(sep)

	var tip := Label.new()
	tip.text = "滚轮滑动 / 点击 / 数字键切换:"
	tip.add_theme_font_size_override("font_size", 11)
	tip.modulate = Color(0.65, 0.75, 0.85)
	outer_vbox.add_child(tip)

	# Scrollable container for skill buttons
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer_vbox.add_child(scroll)

	_skill_select_vbox = VBoxContainer.new()
	_skill_select_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skill_select_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(_skill_select_vbox)

	var all_skills: Array = SkillRegistryScript.get_all_skills()
	for i in range(all_skills.size()):
		var s: RefCounted = all_skills[i]
		if s != null:
			var s_id: String = s.call("get_id")
			var s_name: String = _panel_skill_name(s_id, s.call("get_name"))
			var btn := Button.new()
			btn.text = "[%d] %s" % [i + 1, s_name]
			var icon: Texture2D = _panel_skill_icon(s_id)
			if icon != null:
				btn.icon = icon
				btn.add_theme_constant_override("icon_max_width", SKILL_ICON_SIZE)
			btn.custom_minimum_size = Vector2(0, 36)
			btn.toggle_mode = true
			btn.focus_mode = Control.FOCUS_NONE
			if _custom_font != null:
				btn.add_theme_font_override("font", _custom_font)
			btn.add_theme_font_size_override("font_size", 13)
			btn.pressed.connect(func(): _select_skill(s_id))
			_skill_select_vbox.add_child(btn)
			_skill_buttons[s_id] = btn

	var sep2 := HSeparator.new()
	outer_vbox.add_child(sep2)

	# 提示卡
	var f2_hint := Label.new()
	f2_hint.text = "🎯 按 [F2] 切换假人操控\n💡 按 [L] 沉浸式开关边栏"
	f2_hint.add_theme_font_size_override("font_size", 11)
	f2_hint.modulate = Color(1.0, 0.85, 0.3)
	f2_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer_vbox.add_child(f2_hint)

func _build_right_sidebar(root: Control) -> void:
	_right_sidebar = PanelContainer.new()
	_right_sidebar.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_right_sidebar.offset_left = -380
	_right_sidebar.offset_top = 20
	_right_sidebar.offset_right = -24
	_right_sidebar.offset_bottom = -20

	var r_style := StyleBoxFlat.new()
	r_style.bg_color = Color(0.06, 0.08, 0.12, 0.94)
	r_style.set_corner_radius_all(12)
	r_style.set_border_width_all(1)
	r_style.border_color = Color(0.25, 0.35, 0.50, 0.85)
	r_style.set_content_margin_all(16)
	_right_sidebar.add_theme_stylebox_override("panel", r_style)
	root.add_child(_right_sidebar)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_right_sidebar.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 14)
	scroll.add_child(vbox)

	# --- 1. 假人/玩家操控切换按钮 ---
	_switch_target_btn = Button.new()
	_switch_target_btn.text = "🔄 当前操控: 【玩家】 (按 F2 切换假人)"
	_switch_target_btn.focus_mode = Control.FOCUS_NONE
	if _custom_font != null:
		_switch_target_btn.add_theme_font_override("font", _custom_font)
	_switch_target_btn.add_theme_font_size_override("font_size", 13)
	_switch_target_btn.custom_minimum_size = Vector2(0, 38)
	_switch_target_btn.pressed.connect(_toggle_control_target)
	vbox.add_child(_switch_target_btn)

	var sep0 := HSeparator.new()
	vbox.add_child(sep0)

	# --- 2. 独立参数配置面板 ---
	_skill_title_lbl = Label.new()
	_skill_title_lbl.text = "⚙️ 技能参数配置"
	_skill_title_lbl.add_theme_font_size_override("font_size", 14)
	_skill_title_lbl.modulate = Color(1.0, 0.85, 0.3)
	vbox.add_child(_skill_title_lbl)

	_skill_panel_box = VBoxContainer.new()
	_skill_panel_box.add_theme_constant_override("separation", 10)
	vbox.add_child(_skill_panel_box)

	var sep1 := HSeparator.new()
	vbox.add_child(sep1)

	# --- 3. 当前角色模型切换 ---
	var char_row := HBoxContainer.new()
	char_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(char_row)

	var c_lbl := Label.new()
	c_lbl.text = "角色模型: "
	c_lbl.add_theme_font_size_override("font_size", 13)
	char_row.add_child(c_lbl)

	_char_picker = OptionButton.new()
	_char_picker.focus_mode = Control.FOCUS_NONE
	_char_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var chars := CharacterPipelineScript.list_characters().filter(
		func(c: Dictionary) -> bool: return ResourceLoader.exists(c.scene))
	for i in range(chars.size()):
		var c_id: String = chars[i].get("id", "hero_1")
		_char_picker.add_item(c_id.capitalize())
		_char_picker.set_item_metadata(i, c_id)
	_char_picker.item_selected.connect(func(idx: int):
		var id_val = _char_picker.get_item_metadata(idx)
		if id_val != null:
			_switch_active_character_model(str(id_val))
	)
	char_row.add_child(_char_picker)
	_sync_character_picker_selection()

	# --- 3.5. 当前手持神兵切换 ---
	var weapon_row := HBoxContainer.new()
	weapon_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(weapon_row)

	var w_lbl := Label.new()
	w_lbl.text = "手持神兵: "
	w_lbl.add_theme_font_size_override("font_size", 13)
	weapon_row.add_child(w_lbl)

	_weapon_picker = OptionButton.new()
	_weapon_picker.focus_mode = Control.FOCUS_NONE
	_weapon_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weapon_picker.add_item("🚫 空手 (无武器)")
	_weapon_picker.set_item_metadata(0, "")

	for i in range(_configured_weapons.size()):
		var w_id := _configured_weapons[i]
		_weapon_picker.add_item("🗡️ %s" % w_id)
		_weapon_picker.set_item_metadata(i + 1, w_id)

	_weapon_picker.item_selected.connect(func(idx: int):
		var id_val = _weapon_picker.get_item_metadata(idx)
		_switch_weapon(str(id_val) if id_val != null else "")
	)
	weapon_row.add_child(_weapon_picker)
	_sync_weapon_picker_selection()

	# --- 4. 慢放控制 ---
	var slow_title := Label.new()
	slow_title.text = "慢放调试控制 (Time Scale):"
	slow_title.add_theme_font_size_override("font_size", 12)
	vbox.add_child(slow_title)

	var slow_hbox := HBoxContainer.new()
	slow_hbox.add_theme_constant_override("separation", 8)
	vbox.add_child(slow_hbox)

	for ts in [1.0, 0.5, 0.2]:
		var ts_btn := Button.new()
		ts_btn.text = "%.1fx" % ts
		ts_btn.custom_minimum_size = Vector2(70, 30)
		ts_btn.focus_mode = Control.FOCUS_NONE
		ts_btn.pressed.connect(func(): Engine.time_scale = ts)
		slow_hbox.add_child(ts_btn)

	# --- 5. 视角与释放控制 ---
	var tab_btn := Button.new()
	tab_btn.text = "🎥 切换全局视角 / 观战回放 [TAB]"
	tab_btn.focus_mode = Control.FOCUS_NONE
	if _custom_font != null:
		tab_btn.add_theme_font_override("font", _custom_font)
	tab_btn.add_theme_font_size_override("font_size", 14)
	tab_btn.custom_minimum_size = Vector2(0, 38)
	tab_btn.pressed.connect(func():
		var next_mode := LabMode.GLOBAL_SPECTATE if _mode == LabMode.PLAYER_CONTROL else LabMode.PLAYER_CONTROL
		_set_lab_mode(next_mode)
	)
	vbox.add_child(tab_btn)

	_cast_btn = Button.new()
	_cast_btn.text = "⚡ 立即释放选中技能 (CAST [Q])"
	_cast_btn.focus_mode = Control.FOCUS_NONE
	if _custom_font != null:
		_cast_btn.add_theme_font_override("font", _custom_font)
	_cast_btn.add_theme_font_size_override("font_size", 15)
	_cast_btn.custom_minimum_size = Vector2(0, 44)
	_cast_btn.pressed.connect(_cast_current_skill)

	var c_btn_style := StyleBoxFlat.new()
	c_btn_style.bg_color = Color(0.85, 0.45, 0.15, 0.95)
	c_btn_style.set_corner_radius_all(8)
	c_btn_style.set_content_margin_all(8)
	_cast_btn.add_theme_stylebox_override("normal", c_btn_style)
	vbox.add_child(_cast_btn)

	_select_skill(SkillRegistryScript.get_first_skill_id())

func _select_skill(skill_id: String) -> void:
	_current_skill_id = skill_id
	_cancel_aim()

	# Highlight active button in left sidebar
	for id in _skill_buttons:
		var b: Button = _skill_buttons[id]
		b.button_pressed = (id == skill_id)

	var skill: RefCounted = SkillRegistryScript.get_skill(skill_id)
	if skill == null:
		return

	var s_title: String = skill.call("get_title")
	var s_name: String = _panel_skill_name(skill_id, skill.call("get_name"))

	if _skill_title_lbl != null:
		_skill_title_lbl.text = "⚙️ %s" % s_title
	if _cast_btn != null:
		_cast_btn.text = "⚡ 立即释放：%s [Q]" % s_name

	# Rebuild dynamic config panel in right sidebar
	if _skill_panel_box != null and is_instance_valid(_skill_panel_box):
		for child in _skill_panel_box.get_children():
			child.queue_free()
		skill.call("build_config_panel", _skill_panel_box, _on_skill_param_changed)


# ============================================================
# 顶部 PVP 风格血条 HUD 与战斗伤害系统
# ============================================================

func _build_health_hud(root: Control) -> void:
	_health_hud = PanelContainer.new()
	_health_hud.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_health_hud.offset_left = -340
	_health_hud.offset_right = 340
	_health_hud.offset_top = 16
	_health_hud.offset_bottom = 82
	_health_hud.mouse_filter = Control.MOUSE_FILTER_PASS

	var h_style := StyleBoxFlat.new()
	h_style.bg_color = Color(0.05, 0.07, 0.11, 0.90)
	h_style.set_corner_radius_all(8)
	h_style.set_border_width_all(1)
	h_style.border_color = Color(0.3, 0.8, 1.0, 0.6)
	h_style.set_content_margin_all(10)
	_health_hud.add_theme_stylebox_override("panel", h_style)
	root.add_child(_health_hud)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	_health_hud.add_child(hbox)

	# 1. 玩家血条区 (左侧)
	var p_box := VBoxContainer.new()
	p_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(p_box)

	_player_hp_lbl = Label.new()
	_player_hp_lbl.text = "⚔️ 玩家 HP: 1000 / 1000"
	_player_hp_lbl.add_theme_font_size_override("font_size", 12)
	_player_hp_lbl.modulate = Color(0.35, 0.95, 1.0)
	p_box.add_child(_player_hp_lbl)

	_player_hp_bar = ProgressBar.new()
	_player_hp_bar.max_value = _player_max_hp
	_player_hp_bar.value = _player_hp
	_player_hp_bar.show_percentage = false
	_player_hp_bar.custom_minimum_size = Vector2(0, 14)
	var p_fill := StyleBoxFlat.new()
	p_fill.bg_color = Color(0.15, 0.85, 0.75)
	p_fill.set_corner_radius_all(3)
	_player_hp_bar.add_theme_stylebox_override("fill", p_fill)
	p_box.add_child(_player_hp_bar)

	# 2. 中间 VS 与一键恢复按钮
	var mid_box := VBoxContainer.new()
	mid_box.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(mid_box)

	var reset_hp_btn := Button.new()
	reset_hp_btn.text = "❤️ 满血 [F5]"
	reset_hp_btn.focus_mode = Control.FOCUS_NONE
	reset_hp_btn.add_theme_font_size_override("font_size", 11)
	reset_hp_btn.pressed.connect(_heal_all_full)
	mid_box.add_child(reset_hp_btn)

	# 3. 假人血条区 (右侧)
	var d_box := VBoxContainer.new()
	d_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(d_box)

	_dummy_hp_lbl = Label.new()
	_dummy_hp_lbl.text = "🎯 假人 HP: 1000 / 1000"
	_dummy_hp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dummy_hp_lbl.add_theme_font_size_override("font_size", 12)
	_dummy_hp_lbl.modulate = Color(1.0, 0.80, 0.25)
	d_box.add_child(_dummy_hp_lbl)

	_dummy_hp_bar = ProgressBar.new()
	_dummy_hp_bar.max_value = _dummy_max_hp
	_dummy_hp_bar.value = _dummy_hp
	_dummy_hp_bar.show_percentage = false
	_dummy_hp_bar.custom_minimum_size = Vector2(0, 14)
	var d_fill := StyleBoxFlat.new()
	d_fill.bg_color = Color(0.95, 0.55, 0.15)
	d_fill.set_corner_radius_all(3)
	_dummy_hp_bar.add_theme_stylebox_override("fill", d_fill)
	d_box.add_child(_dummy_hp_bar)

	_update_health_ui()


func _update_health_ui() -> void:
	if _player_hp_bar != null:
		_player_hp_bar.max_value = _player_max_hp
		_player_hp_bar.value = _player_hp
	if _player_hp_lbl != null:
		_player_hp_lbl.text = "⚔️ 玩家 HP: %d / %d" % [int(_player_hp), int(_player_max_hp)]

	if _dummy_hp_bar != null:
		_dummy_hp_bar.max_value = _dummy_max_hp
		_dummy_hp_bar.value = _dummy_hp
	if _dummy_hp_lbl != null:
		_dummy_hp_lbl.text = "🎯 假人 HP: %d / %d" % [int(_dummy_hp), int(_dummy_max_hp)]

	_update_target_labels()


func _heal_all_full() -> void:
	_player_hp = _player_max_hp
	_dummy_hp = _dummy_max_hp
	if _player != null and is_instance_valid(_player):
		_player.state = PlayerControllerScript.State.IDLE
		var raw_ch: Variant = _player.get("character")
		if raw_ch != null and is_instance_valid(raw_ch) and raw_ch.has_method("play"):
			raw_ch.call("play", "idle_a", 0.1)
	if _dummy_player != null and is_instance_valid(_dummy_player):
		_dummy_player.state = PlayerControllerScript.State.IDLE
		var raw_ch: Variant = _dummy_player.get("character")
		if raw_ch != null and is_instance_valid(raw_ch) and raw_ch.has_method("play"):
			raw_ch.call("play", "idle_a", 0.1)
	_update_health_ui()


func _build_damage_number_pool() -> void:
	for i in range(VFX_POOL):
		var lbl := Label3D.new()
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.font_size = 28
		lbl.outline_size = 8
		lbl.outline_modulate = Color.BLACK
		lbl.visible = false
		add_child(lbl)
		_numbers.append(lbl)
		_number_tweens.append(null)


func _show_damage_floater(pos: Vector3, dmg: float) -> void:
	if _numbers.is_empty():
		return
	var idx := _number_next
	_number_next = (_number_next + 1) % VFX_POOL

	if _number_tweens[idx] != null and _number_tweens[idx].is_valid():
		_number_tweens[idx].kill()

	var lbl := _numbers[idx]
	lbl.text = "-%d HP" % int(dmg)
	lbl.modulate = Color(1.0, 0.25, 0.25, 1.0) if dmg > 30.0 else Color(1.0, 0.85, 0.25, 1.0)
	lbl.global_position = pos + Vector3(randf_range(-0.15, 0.15), 0.25, randf_range(-0.15, 0.15))
	lbl.scale = Vector3(1.4, 1.4, 1.4)
	lbl.visible = true

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "global_position:y", lbl.global_position.y + 0.8, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "scale", Vector3(1.0, 1.0, 1.0), 0.25).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.75).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func() -> void: lbl.visible = false)
	_number_tweens[idx] = tw


## 响应普攻挥砍或技能命中（仿 PVP 结算效果）
func _on_actor_hit(is_player_target: bool, hit_pos: Vector3, damage: float, push_dir: Vector3 = Vector3.ZERO) -> void:
	var target := _player if is_player_target else _dummy_player
	if target == null or not is_instance_valid(target):
		return

	# 扣除生命值
	if is_player_target:
		_player_hp = maxf(0.0, _player_hp - damage)
	else:
		_dummy_hp = maxf(0.0, _dummy_hp - damage)

	_update_health_ui()
	_show_damage_floater(hit_pos, damage)
	AudioManagerScript.play_hit_sound(0.0)

	# 击退与受击受挫硬直
	target.apply_hit_reaction("hit_chest", 0.35)
	if push_dir.length_squared() > 0.01:
		target.velocity += push_dir.normalized() * minf(damage * 0.12, 5.0)

	# 受击火花特效
	_spawn_hit_spark(hit_pos, push_dir)

	# 死亡判定
	var cur_hp := _player_hp if is_player_target else _dummy_hp
	if cur_hp <= 0.0:
		var raw_ch: Variant = target.get("character")
		if raw_ch != null and is_instance_valid(raw_ch) and raw_ch.has_method("play"):
			raw_ch.call("play", "death", 0.15)


# --- 武器普攻与挥砍物理碰撞判定 (仿 PVP 判定) ---

func _check_blade_hits() -> void:
	if _player == null or _dummy_player == null:
		return

	# 1. 玩家普攻/挥砍判定击中假人
	if _player.state == PlayerControllerScript.State.ATTACKING:
		var p_item = _player_equip.equipped("right_hand") if _player_equip != null else null
		var hit_info: Dictionary = {}
		var swing_dir := Vector3.ZERO
		if p_item != null:
			var pts := _get_blade_points(p_item, _player)
			var base: Vector3 = pts[0]
			var tip: Vector3 = pts[1]
			swing_dir = (tip - _player_prev_tip) if _player_has_tip else Vector3.ZERO
			var last_tip: Vector3 = _player_prev_tip if _player_has_tip else tip
			_player_prev_tip = tip
			_player_has_tip = true

			if _player.can_deal_damage():
				hit_info = _segment_capsule_hit(base, tip, _dummy_player.global_transform, BLADE_PAD)
				if hit_info.is_empty():
					hit_info = _segment_capsule_hit(last_tip, tip, _dummy_player.global_transform, BLADE_PAD)
		else:
			# 徒手/空手近战普攻判定
			if _player.can_deal_damage():
				var fwd := -_player.global_transform.basis.z
				var p_to_d := _dummy_player.global_position - _player.global_position
				p_to_d.y = 0.0
				if p_to_d.length() <= 2.2 and fwd.dot(p_to_d.normalized()) > 0.5:
					hit_info = {"point": _dummy_player.global_position + Vector3(0, 1.1, 0), "normal": -fwd}

		var inside: bool = not hit_info.is_empty()
		if inside and not _player_blade_inside:
			var dmg: float = 35.0
			_on_actor_hit(false, hit_info.get("point", _dummy_player.global_position + Vector3.UP), dmg, swing_dir)
			_player.register_weapon_hit()
		_player_blade_inside = inside
	else:
		_player_has_tip = false
		_player_blade_inside = false

	# 2. 假人普攻/挥砍判定击中玩家
	if _dummy_player.state == PlayerControllerScript.State.ATTACKING:
		var d_item = _dummy_equip.equipped("right_hand") if _dummy_equip != null else null
		var hit_info: Dictionary = {}
		var swing_dir := Vector3.ZERO
		if d_item != null:
			var pts := _get_blade_points(d_item, _dummy_player)
			var base: Vector3 = pts[0]
			var tip: Vector3 = pts[1]
			swing_dir = (tip - _dummy_prev_tip) if _dummy_has_tip else Vector3.ZERO
			var last_tip: Vector3 = _dummy_prev_tip if _dummy_has_tip else tip
			_dummy_prev_tip = tip
			_dummy_has_tip = true

			if _dummy_player.can_deal_damage():
				hit_info = _segment_capsule_hit(base, tip, _player.global_transform, BLADE_PAD)
				if hit_info.is_empty():
					hit_info = _segment_capsule_hit(last_tip, tip, _player.global_transform, BLADE_PAD)
		else:
			if _dummy_player.can_deal_damage():
				var fwd := -_dummy_player.global_transform.basis.z
				var d_to_p := _player.global_position - _dummy_player.global_position
				d_to_p.y = 0.0
				if d_to_p.length() <= 2.2 and fwd.dot(d_to_p.normalized()) > 0.5:
					hit_info = {"point": _player.global_position + Vector3(0, 1.1, 0), "normal": -fwd}

		var inside: bool = not hit_info.is_empty()
		if inside and not _dummy_blade_inside:
			var dmg: float = 35.0
			_on_actor_hit(true, hit_info.get("point", _player.global_position + Vector3.UP), dmg, swing_dir)
			_dummy_player.register_weapon_hit()
		_dummy_blade_inside = inside
	else:
		_dummy_has_tip = false
		_dummy_blade_inside = false


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


func _spawn_hit_spark(pos: Vector3, push_dir: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos

	for s in range(6):
		var spark := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.06, 0.28)
		spark.mesh = qm
		spark.rotation = Vector3(randf_range(-PI, PI), randf_range(-PI, PI), randf_range(-PI, PI))
		root.add_child(spark)

		var mat := StandardMaterial3D.new()
		mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(2.5, 2.0, 0.8, 1.0)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		spark.material_override = mat

		var spread := push_dir + Vector3(randf_range(-0.8, 0.8), randf_range(-0.3, 0.8), randf_range(-0.8, 0.8))
		var end_p := spark.global_position + spread * randf_range(0.8, 1.8)

		var tw := spark.create_tween()
		tw.set_parallel(true)
		tw.tween_property(spark, "global_position", end_p, 0.22).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.22).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(spark.queue_free)

	var clean_tw := root.create_tween()
	clean_tw.tween_interval(0.3)
	clean_tw.tween_callback(root.queue_free)
