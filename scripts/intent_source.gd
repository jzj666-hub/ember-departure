class_name IntentSource
extends RefCounted
## Base class for character decision/input sources (AI bot, keyboard, network, etc.).

## Poll input source and populate the intent object.
func poll(_body: Node, _delta: float, _intent: CharacterIntent) -> void:
	pass
