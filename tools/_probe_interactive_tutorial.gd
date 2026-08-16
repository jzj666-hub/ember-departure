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
	_ok("Tutorial starts in immersive mode (panels hidden)", not bool(editor.get("_ui_panels_visible")))
	_ok("Step 0 active", editor.get("_tutorial_step") == 0)

	var banner: PanelContainer = editor.get("_interactive_banner")
	_ok("Interactive banner visible", banner != null and banner.visible)

	# --- Step 0 -> Step 1: Place a block ---
	editor.call("_place_block_at", Vector3i(2, 1, 2))
	_ok("Placing block advances to Step 1", editor.get("_tutorial_step") == 1)

	var arrow: Node3D = editor.get("_tutorial_arrow")
	_ok("Floating arrow is visible above placed block", arrow != null and arrow.visible)

	# Try placing another block in Step 1 -> MUST BE DISALLOWED
	var block_count_before: int = (editor.get("_blocks") as Dictionary).size()
	editor.call("_place_block_at", Vector3i(4, 1, 4))
	var block_count_after: int = (editor.get("_blocks") as Dictionary).size()
	_ok("Placing block is disallowed in Step 1", block_count_after == block_count_before and editor.get("_tutorial_step") == 1)

	# --- Step 1 -> Step 2: Remove the block ---
	editor.call("_remove_block_at", Vector3i(2, 1, 2))
	_ok("Removing block advances to Step 2", editor.get("_tutorial_step") == 2)
	_ok("Floating arrow is hidden after block removal", not arrow.visible)

	# --- Step 2: NPC Pathfinding with Shift+LMB ---
	editor.call("_recalculate_npc_path", Vector3(5, 0.2, 5))
	_ok("Recalculating path in Step 2 keeps player observing movement", editor.get("_tutorial_step") == 2)

	# Simulate NPC arrival callback
	await editor.call("_on_npc_arrived_destination", Vector3(5, 0.2, 5))
	_ok("NPC arrival and 2s stay advances to Step 3", editor.get("_tutorial_step") == 3)

	# Check that 2 glowing platforms were spawned in Step 3
	var blocks: Dictionary = editor.get("_blocks")
	_ok("Step 3 generated glowing test platforms", blocks.has("tut_plat_1") and blocks.has("tut_plat_2"))

	# --- Step 3 -> Step 4: TAB into PLAY_TEST ---
	editor.call("_set_mode", MapEditorScript.EditorMode.PLAY_TEST)
	_ok("Switching to PLAY_TEST advances to Step 4", editor.get("_tutorial_step") == 4)

	# Test pressing R key to start recording
	editor.call("_set_mode", MapEditorScript.EditorMode.RECORD_SPECIAL_PATH)
	var banner_title: Label = editor.get("_interactive_banner_title")
	_ok("R key gives immediate recording feedback in banner", banner_title != null and banner_title.text.contains("正在录制"))

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

	var npc_node: Node3D = editor.get("_npc")
	_ok("Character reset back to origin platform", npc_node.global_position.distance_to(Vector3(1.0, 1.2, 1.0)) < 0.3)

	# --- Step 5 -> Step 6: Recalculate Path with AI Replay Verification ---
	editor.call("_recalculate_npc_path", Vector3(1, 1.2, 5))
	_ok("Recalculating path in Step 5 keeps player observing leap", editor.get("_tutorial_step") == 5)

	# Simulate NPC arrival on Platform 2
	await editor.call("_on_npc_arrived_destination", Vector3(1, 1.2, 5))
	_ok("NPC jump arrival and 2s stay advances to Step 6 (Delete Path Task)", editor.get("_tutorial_step") == 6)

	# --- Step 6 -> Step 7: Delete the Special Path ---
	# Simulate double tap X deletion
	editor.set("_hovered_special_path_id", "sp_tut_01")
	editor.call("_handle_x_double_tap") # first tap
	editor.call("_handle_x_double_tap") # second tap within window
	_ok("Deleting special path advances to Step 7 (Complete & Reveal)", editor.get("_tutorial_step") == 7)

	var comp_dialog: PanelContainer = editor.get("_interactive_complete_dialog")
	_ok("Celebration complete dialog is visible", comp_dialog != null and comp_dialog.visible)

	editor.queue_free()
	await process_frame
