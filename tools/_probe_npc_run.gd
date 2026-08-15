@tool
extends SceneTree

const NPCIntentSourceScript = preload("res://scripts/npc_intent_source.gd")
const CharacterIntentScript = preload("res://scripts/character_intent.gd")

func _init() -> void:
	print("\n--- NPC intent source run gait probe ---")
	var source := NPCIntentSourceScript.new()
	var intent := CharacterIntentScript.new()
	
	# Pre: set a path for navigation
	source.set_path(PackedVector3Array([Vector3(0, 0, 0), Vector3(5, 0, 5)]), Vector3(5, 0, 5))
	
	# Action: poll intent
	source.poll(null, 0.016, intent)
	
	# Post: intent.run should be true by default for navigation
	assert(intent.run == true, "NPC should be in run gait by default during navigation")
	print("  PASS  NPC intent source outputs run = true during pathfinding navigation!")

	print("all NPC run probe tests passed!\n")
	quit(0)
