extends SceneTree
## CLI step: detect each character's rig and write its BoneMap, A-pose fix and
## root_scale into the .import file. Run Godot with --import afterwards to apply.
##
##   godot --headless --path <project> --script res://tools/setup_character_imports.gd

const CharacterPipelineScript = preload("res://tools/character_pipeline.gd")

func _initialize() -> void:
	var characters: Array = CharacterPipelineScript.list_characters()
	print("--- %d character folder(s) in %s ---" % [
		characters.size(), CharacterPipelineScript.CHARACTERS_DIR])
	if characters.is_empty():
		print("  drop a character export into %s/<name>/ - one folder per character"
			% CharacterPipelineScript.CHARACTERS_DIR)

	var changed: PackedStringArray = CharacterPipelineScript.configure_all(
		func(line: String) -> void: print(line))

	var unknown := false
	for line in CharacterPipelineScript.rig_report():
		if line.contains("UNKNOWN"):
			if not unknown:
				print("\n--- unrecognised rigs ---")
				unknown = true
			print("  %s" % line)

	print("\n%d .import file(s) updated" % changed.size())
	quit(0)
