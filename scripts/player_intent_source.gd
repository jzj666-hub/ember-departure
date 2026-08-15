class_name PlayerIntentSource
extends IntentSource
## Keyboard/mouse input source for CharacterIntent, using raw physical key polling.

## Max double-tap interval in seconds for roll trigger.
var double_tap := 0.28

## Keyboard key mapping to CharacterIntent buttons.
const KEY_BUTTONS := {
	KEY_Q: "heavy",
	KEY_E: "special",
	KEY_X: "block",
}
## Mouse button mapping to CharacterIntent buttons. Right doubles as the look
## button in scenes that hold the pointer - see WeaponTest._release_right().
const MOUSE_BUTTONS := {
	MOUSE_BUTTON_LEFT: "attack",
	MOUSE_BUTTON_RIGHT: "heavy",
}

## Tracking state for edge detection (prevents key conflicts).
var _shift_down := false
var _space_down := false
## The same, for KEY_BUTTONS, which is a table rather than two named flags.
var _button_down := {}
## Elapsed time since last shift press.
var _since_tap := 999.0


## Get combat button name for mouse button index.
static func button_for_mouse(index: int) -> String:
	return MOUSE_BUTTONS.get(index, "")


func poll(body: Node, delta: float, intent: CharacterIntent) -> void:
	intent.move = _move_vector()
	intent.heading = float(body.call("view_yaw"))
	intent.crouch = Input.is_physical_key_pressed(KEY_CTRL)

	var shift := Input.is_key_pressed(KEY_SHIFT)
	intent.run = shift

	# Double-tap edge detection for roll.
	_since_tap += delta
	intent.roll = false
	if shift and not _shift_down:
		if _since_tap <= double_tap:
			intent.roll = true
			# Reset timer after successful roll detection.
			_since_tap = 999.0
		else:
			_since_tap = 0.0
	_shift_down = shift

	var space := Input.is_physical_key_pressed(KEY_SPACE)
	intent.jump = space and not _space_down
	_space_down = space

	# Poll keyboard buttons and press corresponding intent.
	intent.buttons = 0
	for key in KEY_BUTTONS:
		var down := Input.is_physical_key_pressed(key)
		if down and not bool(_button_down.get(key, false)):
			intent.press(KEY_BUTTONS[key])
		_button_down[key] = down


## Returns normalized 2D movement vector from WASD keys.
func _move_vector() -> Vector2:
	var out := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		out.y += 1.0
	if Input.is_physical_key_pressed(KEY_S):
		out.y -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		out.x += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		out.x -= 1.0
	return out.limit_length(1.0)
