class_name PlayerIntentSource
extends IntentSource
## Keyboard/mouse input source for CharacterIntent, driven by KeybindManager.

const KeybindManagerScript = preload("res://scripts/keybind_manager.gd")

## Max double-tap interval in seconds for double-tap triggers.
var double_tap := 0.28

## Fallback tables for backwards compatibility.
const KEY_BUTTONS := {
	KEY_Q: "heavy",
	KEY_E: "special",
	KEY_X: "block",
}
const MOUSE_BUTTONS := {
	MOUSE_BUTTON_LEFT: "attack",
	MOUSE_BUTTON_RIGHT: "heavy",
}

var keybind_manager = null

## Internal state tracking for edge detection and double-tap timing.
var _down_state: Dictionary = {}
var _tap_timer: Dictionary = {}


func _init() -> void:
	keybind_manager = KeybindManagerScript.get_instance()


## Get combat button name for mouse button index.
static func button_for_mouse(index: int) -> String:
	var km = KeybindManagerScript.get_instance()
	var act: String = km.get_action_for_mouse_button(index, false)
	if not act.is_empty():
		return act
	return MOUSE_BUTTONS.get(index, "")


func poll(body: Node, delta: float, intent: CharacterIntent) -> void:
	if keybind_manager == null:
		keybind_manager = KeybindManagerScript.get_instance()

	# 1. Update double tap timers
	for act in _tap_timer:
		_tap_timer[act] = float(_tap_timer[act]) + delta

	# 2. Movement & Stances
	intent.move = _move_vector()
	if body != null and is_instance_valid(body) and body.has_meta("confusion_debuff"):
		intent.move = -intent.move
	intent.heading = float(body.call("view_yaw")) if body != null and body.has_method("view_yaw") else 0.0
	intent.crouch = _is_action_held("crouch")
	intent.run = _is_action_held("run")

	# 3. Actions (Jump, Roll)
	intent.jump = _check_action_triggered("jump")
	intent.roll = _check_action_triggered("roll")

	# 4. Combat Buttons
	intent.buttons = 0
	for btn in CharacterIntent.BUTTONS:
		if _check_action_triggered(btn):
			intent.press(btn)


func _is_raw_pressed(binding: Dictionary) -> bool:
	var dev: String = binding.get("device", "none")
	var code: int = int(binding.get("code", 0))
	if code == 0:
		return false
	if dev == "key":
		if code == KEY_SHIFT:
			return Input.is_key_pressed(KEY_SHIFT) or Input.is_physical_key_pressed(KEY_SHIFT)
		return Input.is_physical_key_pressed(code)
	elif dev == "mouse":
		return Input.is_mouse_button_pressed(code)
	return false


func _is_action_held(action: String) -> bool:
	var b: Dictionary = keybind_manager.get_binding(action)
	return _is_raw_pressed(b)


func _check_action_triggered(action: String) -> bool:
	var b: Dictionary = keybind_manager.get_binding(action)
	var is_down := _is_raw_pressed(b)
	var was_down: bool = bool(_down_state.get(action, false))
	_down_state[action] = is_down

	var just_pressed := is_down and not was_down
	var is_double: bool = (b.get("trigger", "single") == "double_tap")

	if not is_double:
		return just_pressed

	# Double-tap trigger logic
	var triggered := false
	if just_pressed:
		var elapsed: float = float(_tap_timer.get(action, 999.0))
		if elapsed <= double_tap:
			triggered = true
			_tap_timer[action] = 999.0
		else:
			_tap_timer[action] = 0.0

	return triggered


func _move_vector() -> Vector2:
	var out := Vector2.ZERO
	if _is_action_held("move_forward"):
		out.y += 1.0
	if _is_action_held("move_backward"):
		out.y -= 1.0
	if _is_action_held("move_right"):
		out.x += 1.0
	if _is_action_held("move_left"):
		out.x -= 1.0
	return out.limit_length(1.0)
