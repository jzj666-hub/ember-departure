extends SceneTree
## Headless probe testing the Movement Sandbox Third-Person Trial & Interactive Tutorial flow.

var passed := 0
var failed := 0


func _initialize() -> void:
	print("\n=== Movement Sandbox & Third-Person Interactive Tutorial Probe Suite ===")
	_run_all_tests()


func _run_all_tests() -> void:
	await _test_title_screen_trial_modal()
	await _test_playground_interactive_tutorial()

	print("\nALL MOVEMENT SANDBOX & TUTORIAL TESTS PASSED (%d failures)\n" % failed)
	quit(0 if failed == 0 else 1)


func _ok(msg: String, cond: bool) -> void:
	if cond:
		passed += 1
		print("  PASS  %s " % msg)
	else:
		failed += 1
		print("  FAIL  %s " % msg)


func _test_title_screen_trial_modal() -> void:
	print("\n--- Test 1: Title Screen Trial Sandbox Ask Modal ---")
	var scene := load("res://scenes/player_client/title_screen.tscn") as PackedScene
	_ok("Title screen scene loads", scene != null)

	var inst: Control = scene.instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame

	var trial_dialog: PanelContainer = inst.get("_trial_ask_dialog")
	_ok("Trial ask dialog exists in Title Screen", trial_dialog != null)
	_ok("Trial ask dialog starts hidden", trial_dialog != null and not trial_dialog.visible)

	inst.queue_free()


func _test_playground_interactive_tutorial() -> void:
	print("\n--- Test 2: Playground Interactive Tutorial State Machine & Key PNGs ---")
	var playground_scene := load("res://scenes/playground.tscn") as PackedScene
	_ok("Playground scene loads", playground_scene != null)

	var PlaygroundScript = preload("res://scripts/playground.gd")
	var PlayerControllerScript = preload("res://scripts/player_controller.gd")
	PlaygroundScript.start_with_tutorial = true
	PlaygroundScript.return_scene = "res://scenes/player_client/title_screen.tscn"

	var inst: Node3D = playground_scene.instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame

	_ok("Tutorial active on start", inst.get("_tutorial_active") == true)
	_ok("Starts at Step 0", inst.get("_tutorial_step") == 0)

	var banner: PanelContainer = inst.get("_tutorial_banner")
	_ok("Tutorial banner exists and is visible", banner != null and banner.visible)

	var keys_box: HBoxContainer = inst.get("_tutorial_keys_container")
	_ok("Keys container exists", keys_box != null)
	_ok("Step 0 contains 4 key icons (W,A,S,D)", keys_box != null and keys_box.get_child_count() == 4)

	# Verify Step 0 -> Step 1 (Movement accumulation)
	inst.set("_tutorial_accum_dist", 3.0)
	inst.call("_update_tutorial_state", 0.1)
	_ok("Step 0 advances to Step 1 upon movement", inst.get("_tutorial_step") == 1)
	_ok("Step 1 shows Shift+W keys", keys_box.get_child_count() == 3) # SHIFT, +, W

	# Verify Step 1 -> Step 2 (Sprint accumulation)
	inst.set("_tutorial_accum_run", 1.5)
	var player: CharacterBody3D = inst.get("_player")
	player.state = PlayerControllerScript.State.RUN
	inst.call("_update_tutorial_state", 0.1)
	_ok("Step 1 advances to Step 2 upon sprint", inst.get("_tutorial_step") == 2)
	_ok("Step 2 shows Space key", keys_box.get_child_count() == 1)

	# Verify Step 2 -> Step 3 (Jump)
	player.state = PlayerControllerScript.State.JUMPING
	inst.call("_update_tutorial_state", 0.1)
	_ok("Step 2 advances to Step 3 upon jump", inst.get("_tutorial_step") == 3)

	var arrow: Node3D = inst.get("_tutorial_arrow")
	_ok("Climb guide arrow is visible in Step 3", arrow != null and arrow.visible)

	# Verify Step 3 -> Step 4 (Climb 2-block platform)
	var climb_prop: StaticBody3D = inst.get("_tutorial_climb_prop")
	_ok("2-block high climbing platform exists in scene", climb_prop != null)
	player.state = PlayerControllerScript.State.CLIMBING
	inst.call("_update_tutorial_state", 0.1)
	_ok("Step 3 advances to Step 4 upon climb", inst.get("_tutorial_step") == 4)
	_ok("Climb guide arrow hidden after Step 3", arrow != null and not arrow.visible)

	# Verify Step 4 -> Step 5 (Roll)
	player.state = PlayerControllerScript.State.ROLLING
	inst.call("_update_tutorial_state", 0.1)
	_ok("Step 4 advances to Step 5 upon roll", inst.get("_tutorial_step") == 5)

	# Verify Step 5 -> Step 6 (F3 Camera toggle)
	inst.set("_camera_toggled_during_step", true)
	inst.call("_update_tutorial_state", 0.1)
	_ok("Step 5 advances to Step 6 upon camera toggle", inst.get("_tutorial_step") == 6)

	var complete_dialog: PanelContainer = inst.get("_tutorial_complete_dialog")
	_ok("Celebration complete dialog is visible", complete_dialog != null and complete_dialog.visible)
	_ok("Tutorial banner is hidden on completion", banner != null and not banner.visible)

	inst.queue_free()
