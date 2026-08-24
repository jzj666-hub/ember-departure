extends SceneTree

func _initialize() -> void:
	_run()

func _run() -> void:
	var lib = load("res://assets/animations/shared_animations.tres") as AnimationLibrary
	for name in ["sitting_enter", "sitting_idle", "sitting_exit", "stop_walking"]:
		var a = lib.get_animation(name)
		print(name, " length: ", a.length if a != null else "null", " loop: ", a.loop_mode if a != null else "null")
	quit(0)
