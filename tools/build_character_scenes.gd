extends SceneTree
## CLI step: generate assets/characters/<id>/<id>.tscn for every character.
##
## Run after the animation libraries exist - the scenes reference them.
##
##   godot --headless --path <project> --script res://tools/build_character_scenes.gd

const CharacterPipelineScript = preload("res://tools/character_pipeline.gd")

func _initialize() -> void:
	print("--- rig status ---")
	for line in CharacterPipelineScript.rig_report():
		print("  %s" % line)

	print("\n--- wrapper scenes ---")
	var result: Dictionary = CharacterPipelineScript.build_scenes(
		func(line: String) -> void: print(line))

	for problem in result.problems:
		printerr("  %s" % problem)
	if not result.ok:
		quit(1)
		return

	print("\nwrote %d character scene(s)" % result.scenes.size())
	quit(0)
