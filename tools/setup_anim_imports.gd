extends SceneTree
## CLI step 1: detect each animation's rig and write the matching BoneMap into
## its .import file. Run Godot with --import afterwards to apply.
##
## Covers the shared folder and every character's own animations/ subfolder.
##
##   godot --headless --path <project> --script res://tools/setup_anim_imports.gd

const AnimPipelineScript = preload("res://tools/anim_pipeline.gd")

func _initialize() -> void:
	var sources := AnimPipelineScript.list_all_sources()
	print("--- %d animation source file(s) in %s ---" % [
		sources.size(), ", ".join(AnimPipelineScript.source_dirs())])

	var changed := AnimPipelineScript.configure_all(func(line: String) -> void: print(line))

	var unknown := false
	for line in AnimPipelineScript.rig_report():
		if line.contains("UNKNOWN"):
			if not unknown:
				print("\n--- unrecognised rigs ---")
				unknown = true
			print("  %s" % line)

	print("\n%d .import file(s) updated" % changed.size())
	quit(0)
