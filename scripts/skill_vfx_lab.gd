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
var _switch_target_btn: Button
var _custom_font: Font = null
var _glitch_font: Font = null

# Left Sidebar (Candidate List) & Right Sidebar (Config)
var _left_sidebar: PanelContainer
var _right_sidebar: PanelContainer
var _skill_select_vbox: VBoxContainer
var _skill_panel_box: VBoxContainer
var _skill_title_lbl: Label
var _cast_btn: Button

func _ready() -> void:
	AudioManagerScript.init_pool(self)
	SkillRegistryScript.init_registry()
	SkillRegistryScript.warmup_all_shaders(self)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Engine.time_scale = 1.0

	_idle_intent = IdleIntentSource.new()
	_intent = PlayerIntentSourceScript.new()

	if ResourceLoader.exists(FONT_PATH):
		_custom_font = load(FONT_PATH) as Font
	if ResourceLoader.exists(FONT_GLITCH_PATH):
		_glitch_font = load(FONT_GLITCH_PATH) as Font

	_build_scene_environment()
	_build_builder_camera()
	_build_player()
	_build_dummy()
	_build_ui()

	_set_lab_mode(LabMode.PLAYER_CONTROL)
	AudioManagerScript.play_voice_file("res://assets/voice/Voiceover Pack/Male/prepare.ogg", 0.0)

func _process(delta: float) -> void:
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
	if _player_tag_lbl != null:
		if _control_target == ControlTarget.PLAYER:
			_player_tag_lbl.text = "🕹️ 主角色 (操控中)"
			_player_tag_lbl.modulate = Color(0.3, 0.95, 1.0)
		else:
			_player_tag_lbl.text = "👤 主角色 [按 F2 切回]"
			_player_tag_lbl.modulate = Color(0.7, 0.8, 0.9, 0.8)

	if _dummy_tag_lbl != null:
		if _control_target == ControlTarget.DUMMY:
			_dummy_tag_lbl.text = "🎯 训练假人 (操控中)"
			_dummy_tag_lbl.modulate = Color(1.0, 0.85, 0.2)
		else:
			_dummy_tag_lbl.text = "🎯 训练假人 [按 F2 操控]"
			_dummy_tag_lbl.modulate = Color(1.0, 0.6, 0.2, 0.8)

	if _switch_target_btn != null:
		if _control_target == ControlTarget.PLAYER:
			_switch_target_btn.text = "🔄 当前操控: 【玩家】 (按 F2 切换假人)"
			_switch_target_btn.modulate = Color(0.5, 1.0, 1.0)
		else:
			_switch_target_btn.text = "🔄 当前操控: 【假人】 (按 F2 切回玩家)"
			_switch_target_btn.modulate = Color(1.0, 0.85, 0.3)

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
		_sub_header_lbl.text = "🌟 [沉浸式模式] [L]开关侧栏 | [F2]切假人/玩家 | [Q]释放技能 | [1-9]切技能 | [TAB]全局观战"
		_sub_header_lbl.modulate = Color(1.0, 0.9, 0.4)
	else:
		if _mode == LabMode.PLAYER_CONTROL:
			var target_str := "【玩家】" if _control_target == ControlTarget.PLAYER else "【假人】"
			_sub_header_lbl.text = "WASD移动 | [Q]释放技能(%s) | [F2]切换假人/玩家 | [1-9]切技能 | [L]沉浸式 | [TAB]观战" % target_str
			_sub_header_lbl.modulate = Color(0.7, 0.8, 0.9)
		else:
			_sub_header_lbl.text = "WASD自由飞行漫游 | 滚轮调速 | [Q]重触发 | [F2]切换目标 | [L]沉浸式 | [TAB]返回控制"
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
	return id == "sand" or id == "wall"


func _begin_aim() -> void:
	_aiming = true
	_build_aim_cursor()
	_update_aim()


func _update_aim() -> void:
	if _aim_cursor == null or not is_instance_valid(_aim_cursor):
		return
	var skill: RefCounted = SkillRegistryScript.get_skill(_current_skill_id)
	var cast_r: float = float(skill.get("cast_range")) if skill != null else 16.0

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
			var skill_r: float = float(skill.get("sand_radius")) if skill != null else 4.0
			_aim_cursor.scale = Vector3(skill_r, 1.0, skill_r)
		"wall":
			var wall_len: float = float(skill.get("wall_length")) if skill != null else 6.0
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
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.20, 0.28, 0.42)
	sky_mat.sky_horizon_color = Color(0.55, 0.58, 0.64)
	sky_mat.ground_bottom_color = Color(0.10, 0.12, 0.15)
	sky_mat.ground_horizon_color = Color(0.55, 0.58, 0.64)

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.2

	var env_node := WorldEnvironment.new()
	env_node.environment = env
	add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.transform.basis = Basis.from_euler(Vector3(deg_to_rad(-45.0), deg_to_rad(135.0), 0.0))
	add_child(sun)

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
	var g_mat := StandardMaterial3D.new()
	g_mat.albedo_color = Color(0.14, 0.16, 0.20)
	g_mat.roughness = 0.8
	var g_inst := MeshInstance3D.new()
	g_inst.mesh = g_mesh
	g_inst.material_override = g_mat
	g_inst.position.y = -0.2
	ground.add_child(g_inst)
	add_child(ground)

	# Grid Lines
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

func _build_player() -> void:
	_player = PlayerControllerScript.new()
	_player.name = "TestPlayer"
	_player.position = Vector3(0.0, 0.1, 0.0)
	_player.intent_source = _intent
	add_child(_player)

	_camera = FollowCameraScript.new()
	_camera.name = "Camera"
	_camera.fov = 55.0
	_camera.near = 0.05
	_camera.current = true
	add_child(_camera)

	_setup_character_actor(_player, _player_hero_id, false)

	_player_tag_lbl = Label3D.new()
	_player_tag_lbl.name = "PlayerTag"
	_player_tag_lbl.position = Vector3(0.0, 2.15, 0.0)
	_player_tag_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_player_tag_lbl.no_depth_test = true
	_player_tag_lbl.font_size = 24
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

	_setup_character_actor(_dummy_player, _dummy_hero_id, true)

	_dummy_tag_lbl = Label3D.new()
	_dummy_tag_lbl.name = "DummyTag"
	_dummy_tag_lbl.position = Vector3(0.0, 2.15, 0.0)
	_dummy_tag_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_dummy_tag_lbl.no_depth_test = true
	_dummy_tag_lbl.font_size = 24
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

func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 20
	add_child(_canvas)

	_ui_root = Control.new()
	_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.add_child(_ui_root)

	_build_header(_ui_root)
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
		ts_btn.pressed.connect(func(): Engine.time_scale = ts)
		slow_hbox.add_child(ts_btn)

	# --- 5. 视角与释放控制 ---
	var tab_btn := Button.new()
	tab_btn.text = "🎥 切换全局视角 / 观战回放 [TAB]"
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