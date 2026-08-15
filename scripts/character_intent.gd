class_name CharacterIntent
extends RefCounted
## Decoupled character input intent state. Recycled in-place every physics frame.
## Sources must overwrite all fields or call clear() before polling.

## Target movement vector relative to heading (max length 1.0).
var move := Vector2.ZERO

## Target heading yaw in radians.
var heading := 0.0

## Input state flags.
var run := false
var crouch := false

## Mapping of allowed combat button names to bitmask bits.
const BUTTONS := {
	"attack": 1 << 0,
	"heavy": 1 << 1,
	"special": 1 << 2,
	"block": 1 << 3,
}

## Action trigger flags (single-frame edges, cleared after reading).
var jump := false
var roll := false

## Active combat button triggers as a bitmask of BUTTONS.
var buttons := 0


## Check if button is triggered this frame.
func pressed(button: String) -> bool:
	var bit: int = BUTTONS.get(button, 0)
	return bit != 0 and (buttons & bit) != 0


## Set button trigger flag.
func press(button: String) -> void:
	buttons |= int(BUTTONS.get(button, 0))


## Reset all intent fields to default (zero/false).
func clear() -> void:
	move = Vector2.ZERO
	run = false
	crouch = false
	jump = false
	roll = false
	buttons = 0
