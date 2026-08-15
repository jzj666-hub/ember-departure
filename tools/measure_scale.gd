extends SceneTree
## Reports what height every character is set to, what it was measured at, and
## whether the two still agree with the root_scale in its .import.
##
## Diagnostic only. The pipeline writes root_scale itself (tools/character_pipeline.gd)
## - this is for checking its work, or for working out why someone imports at the
## wrong size.
##
##   godot --headless --path <project> --script res://tools/measure_scale.gd

const AnimPipelineScript = preload("res://tools/anim_pipeline.gd")
const CharacterPipelineScript = preload("res://tools/character_pipeline.gd")

## Mixamo's reference rig, for sanity-checking hip height after scaling.
const MIXAMO_HIP_HEIGHT_M := 0.969

func _initialize() -> void:
	var characters: Array = CharacterPipelineScript.list_characters()
	if characters.is_empty():
		print("no characters in %s" % CharacterPipelineScript.CHARACTERS_DIR)
		quit(0)
		return

	for character in characters:
		var probed := AnimPipelineScript.probe(character.model)
		var box: AABB = probed.aabb
		var applied: float = CharacterPipelineScript.current_root_scale(character.model)
		var measured: float = character.measured_height
		var wanted: float = character.target_height

		print("\n=== %s  (%s) ===" % [character.id, String(character.model).get_file()])
		print("  mesh bounds size = (%.6f, %.6f, %.6f)" % [
			box.size.x, box.size.y, box.size.z])
		print("  wants %.3f m%s" % [
			wanted, "" if wanted == CharacterPipelineScript.TARGET_HEIGHT_M else "  (per-character)"])

		if measured <= 0.0:
			print("  !! never measured - no %s yet; the next pipeline pass writes one" %
				CharacterPipelineScript.CONFIG_FILE)
			continue

		# apply_root_scale bakes the factor into the vertices, so the bounds above
		# are already scaled and cannot be re-measured. The stored measurement is
		# the raw size, and imported height is just the two multiplied.
		var imported := measured * applied
		print("  raw measurement %.6f x root_scale %.4f = %.3f m  %s" % [
			measured, applied, imported,
			"OK" if absf(imported - wanted) < 0.02 else "!! not %.2f m" % wanted])
		var needed: float = CharacterPipelineScript.root_scale_for(wanted, measured)
		# Compared as heights, not as scales: a model measured in hundredths of a
		# unit carries a root_scale in the hundreds, where a scale difference too
		# small to see is still a large number.
		if absf(needed * measured - imported) > CharacterPipelineScript.HEIGHT_EPSILON_M:
			print("     .import is stale; wants root_scale %.4f - run the pipeline" % needed)
		print("     (Mixamo reference rig hip height = %.3f m at 1.75 m tall)" % MIXAMO_HIP_HEIGHT_M)
	quit(0)
