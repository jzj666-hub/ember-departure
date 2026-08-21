extends SceneTree
## CLI step: build a single character's animation library (if any) and wrapper scene (.tscn).
##
##   godot --headless --path <project> --script res://tools/build_single_character.gd -- <character_id>

const CharacterPipelineScript = preload("res://tools/character_pipeline.gd")
const AnimPipelineScript = preload("res://tools/anim_pipeline.gd")

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("[!] Usage: godot --headless --script res://tools/build_single_character.gd -- <character_id>")
		quit(1)
		return

	var char_id := args[0].strip_edges()
	var character: Dictionary = CharacterPipelineScript.find(char_id)
	if character.is_empty():
		printerr("[!] Character not found: %s in %s" % [char_id, CharacterPipelineScript.CHARACTERS_DIR])
		quit(1)
		return

	# Build character's private animation library if clips exist
	var anim_sources := AnimPipelineScript.list_sources(character.anim_dir)
	if not anim_sources.is_empty():
		print("--- Building private animations library for '%s' ---" % char_id)
		var anim_res := AnimPipelineScript.build_library(
			character.anim_dir, character.own_library,
			func(line: String) -> void: print("  %s" % line))
		for p in anim_res.problems:
			printerr("  [!] %s" % p)
		if anim_res.ok:
			print("  Wrote %s (%d clips)" % [character.own_library, anim_res.clips.size()])

	print("--- Building scene for '%s' ---" % char_id)
	var problem := CharacterPipelineScript.build_scene(character)
	if problem != "":
		printerr("  [!] Failed: %s" % problem)
		quit(1)
		return

	print("  Wrote %s" % character.scene)
	quit(0)
