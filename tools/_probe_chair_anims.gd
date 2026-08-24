extends SceneTree

const PlayerControllerScript = preload("res://scripts/player_controller.gd")
const CharacterPipelineScript = preload("res://tools/character_pipeline.gd")

func _initialize() -> void:
	_run()

func _run() -> void:
	print("--- 测试 sitting 与 stop_walking 动画 ---")
	var lib = load("res://assets/animations/shared_animations.tres") as AnimationLibrary
	if lib == null:
		print("FAIL: shared_animations.tres not found")
		quit(1)
		return

	print("has stop_walking:", lib.has_animation("stop_walking"))
	print("has sitting_enter:", lib.has_animation("sitting_enter"))
	print("has sitting_idle:", lib.has_animation("sitting_idle"))
	print("has sitting_exit:", lib.has_animation("sitting_exit"))

	quit(0)
