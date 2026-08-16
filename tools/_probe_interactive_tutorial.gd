extends SceneTree
## Probe test suite for Map Studio Onboarding: Ask Modal & Full 6-Step Interactive Tutorial State Machine.

const MapEditorScript = preload("res://scripts/map_editor.gd")
const TitleScreenScript = preload("res://scripts/player_client/title_screen.gd")

var _failures := 0


func _initialize() -> void:
	print("\n=== Interactive Tutorial & Workshop Ask Modal Probe Suite ===")

	await _test_title_screen_ask_modal()
	await _test_interactive_tutorial_flow()

	print("")
	if _failures == 0:
		print("ALL INTERACTIVE TUTORIAL TESTS PASSED (0 failures)")
	else:
		print("%d TEST(S) FAILED" % _failures)

	quit(_failures)


func _ok(label: String, condition: bool, extra := "") -> void:
	if condition:
		print("  PASS  %s %s" % [label, extra])
	else:
		print("  FAIL  %s %s" % [label, extra])
		_failures += 1


func _test_title_screen_ask_modal() -> void:
	print("\n--- Test 1: Title Screen Workshop Ask Modal ---")
	var t_scene := load("res://scenes/player_client/title_screen.tscn") as PackedScene
	_ok("Title screen scene loads", t_scene != null)

	var title_node: Control = t_scene.instantiate()
	root.add_child(title_node)
	await process_frame

	var ask_dialog: PanelContainer = title_node.get("_workshop_ask_dialog")
	_ok("Workshop ask dialog exists in Title Screen", ask_dialog != null)
	_ok("Workshop ask dialog starts hidden", not ask_dialog.visible)

	title_node.queue_free()
	await process_frame


func _test_interactive_tutorial_flow() -> void:
	print("\n--- Test 2: Full 6-Step Interactive Tutorial State Machine ---")
	var scene := load("res://scenes/map_editor.tscn") as PackedScene
	_ok("MapEditor scene loads successfully", scene != null)

	var editor: Node3D = scene.instantiate()
	root.add_child(editor)
	await process_frame
	await process_frame

	# Start interactive tutorial
	editor.call("start_interactive_tutorial")
	_ok("Interactive tutorial active", bool(editor.get("_interactive_tutorial_active")))
	_ok("Step 0 active", editor.get("_tutorial_step") == 0)

	var banner: PanelContainer = editor.get("_interactive_banner")
	_ok("Interactive banner visible", banner != null and banner.visible)

	# --- Step 0 -> Step 1: Place a block ---
	editor.call("_place_block_at", Vector3i(2, 1, 2))
	_ok("Placing block advances to Step 1", editor.get("_tutorial_step") == 1)

	# --- Step 1 -> Step 2: Remove the block ---
	editor.call("_remove_block_at", Vector3i(2, 1, 2))
	_ok("Removing block advances to Step 2", editor.get("_tutorial_step") == 2)

	# --- Step 2 -> Step 3: NPC Pathfinding with Shift+LMB ---
	editor.call("_recalculate_npc_path", Vector3(5, 0.2, 5))
	_ok("NPC pathfinding test advances to Step 3", editor.get("_tutorial_step") == 3)

	# Check that 2 glowing platforms were spawned in Step 3
	var blocks: Dictionary = editor.get("_blocks")
	_ok("Step 3 generated glowing test platforms", blocks.has("tut_plat_1") and blocks.has("tut_plat_2"))

	# --- Step 3 -> Step 4: TAB into PLAY_TEST ---
	editor.call("_set_mode", MapEditorScript.EditorMode.PLAY_TEST)
	_ok("Switching to PLAY_TEST advances to Step 4", editor.get("_tutorial_step") == 4)

	# --- Step 4 -> Step 5: Special Path Recorded ---
	var dummy_path := {
		"id": "sp_tut_01",
		"from": [1, 1, 1],
		"to": [1, 1, 5],
		"trajectory": [Vector3(1, 1.2, 1), Vector3(1, 2.5, 3), Vector3(1, 1.2, 5)],
		"jump_origin": Vector3(1, 1.2, 1),
		"launch_vel": Vector3(0, 5, 4),
		"landing_pos": Vector3(1, 1.2, 5),
		"apex_pos": Vector3(1, 2.5, 3),
		"air_duration": 0.6,
		"rest_pos": Vector3(1, 1.2, 1),
		"rest_time": 0.3
	}
	editor.call("_on_special_path_recorded", dummy_path)
	_ok("Recording special jump advances to Step 5", editor.get("_tutorial_step") == 5)

	# --- Step 5 -> Step 6: Recalculate Path with AI Replay Verification ---
	editor.call("_recalculate_npc_path", Vector3(1, 1.2, 5))
	_ok("Testing AI special jump execution advances to Step 6 (Complete)", editor.get("_tutorial_step") == 6)

	var comp_dialog: PanelContainer = editor.get("_interactive_complete_dialog")
	_ok("Celebration complete dialog is visible", comp_dialog != null and comp_dialog.visible)

	editor.queue_free()
	await process_frame
