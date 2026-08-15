extends SceneTree
## CLI step 2: collect clips into AnimationLibrary resources - the shared library
## from assets/animations/source/, plus one per character that has clips of its own.
##
##   godot --headless --path <project> --script res://tools/build_anim_library.gd

const AnimPipelineScript = preload("res://tools/anim_pipeline.gd")

func _initialize() -> void:
	var result: Dictionary = AnimPipelineScript.build_all_libraries(
		func(line: String) -> void: print(line))

	for problem in result.problems:
		printerr("  %s" % problem)

	if not result.ok:
		quit(1)
		return

	for lib in result.libraries:
		print("\nwrote %s with %d clip(s):" % [lib.path, lib.clips.size()])
		for clip in lib.clips:
			print("  - %s" % clip)
	quit(0)
