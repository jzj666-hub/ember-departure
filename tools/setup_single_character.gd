extends SceneTree
## CLI step: configure a single character's .import file and its private animations.
##
##   godot --headless --path <project> --script res://tools/setup_single_character.gd -- <character_id>

const CharacterPipelineScript = preload("res://tools/character_pipeline.gd")
const AnimPipelineScript = preload("res://tools/anim_pipeline.gd")

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("[!] Usage: godot --headless --script res://tools/setup_single_character.gd -- <character_id>")
		quit(1)
		return

	var char_id := args[0].strip_edges()
	var character: Dictionary = CharacterPipelineScript.find(char_id)
	if character.is_empty():
		printerr("[!] Character not found: %s in %s" % [char_id, CharacterPipelineScript.CHARACTERS_DIR])
		quit(1)
		return

	print("--- Configuring character '%s' ---" % char_id)
	var res := CharacterPipelineScript.configure(character)
	print("  Model: %s -> %s" % [String(character.model).get_file(), res.message])

	var anim_sources := AnimPipelineScript.list_sources(character.anim_dir)
	if not anim_sources.is_empty():
		print("--- Configuring %d private animations for '%s' ---" % [anim_sources.size(), char_id])
		for anim_path in anim_sources:
			var anim_res := AnimPipelineScript.configure(anim_path)
			print("  Anim: %s -> %s" % [anim_path.get_file(), anim_res.message])

	quit(0)
