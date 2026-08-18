extends SceneTree
## Test probe for Main Gateway Video Background, Player Client 3D Animation Background, and Movement Sandbox HUD.

const MainMenuScript = preload("res://scripts/main_menu.gd")
const TitleScreenScript = preload("res://scripts/player_client/title_screen.gd")
const PlaygroundScript = preload("res://scripts/playground.gd")

var _failures := 0


func _initialize() -> void:
	print("\n=== Gateway Video & Title 3D BG & Movement Sandbox HUD Probe ===")

	await _test_main_menu_video_background()
	await _test_title_screen_background()
	await _test_movement_sandbox_hud_player_mode()
	await _test_movement_sandbox_hud_dev_mode()

	print("")
	if _failures == 0:
		print("ALL TESTS PASSED (0 failures)")
	else:
		print("%d TEST(S) FAILED" % _failures)

	quit(_failures)


func _ok(label: String, condition: bool, extra := "") -> void:
	if condition:
		print("  PASS  %s %s" % [label, extra])
	else:
		print("  FAIL  %s %s" % [label, extra])
		_failures += 1


func _test_main_menu_video_background() -> void:
	print("\n--- Test 1: Outermost Main Gateway Video Background ---")
	var scene := load("res://scenes/main_menu.tscn") as PackedScene
	_ok("Main menu packed scene loads", scene != null)

	var inst: Control = scene.instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame

	var video_player: VideoStreamPlayer = inst.get("_video_player")
	_ok("VideoStreamPlayer instance exists in main menu", video_player != null)
	if video_player != null:
		_ok("VideoStream is assigned", video_player.stream != null)
		_ok("VideoStream is set to loop", video_player.loop)
		_ok("VideoStream is set to expand full rect", video_player.expand)

	inst.queue_free()
	await process_frame


func _test_title_screen_background() -> void:
	print("\n--- Test 2: Player Client Title Screen 3D Background Animation ---")
	var scene := load("res://scenes/player_client/title_screen.tscn") as PackedScene
	_ok("Title screen packed scene loads", scene != null)

	var inst: Control = scene.instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame

	# Check SubViewportContainer & SubViewport
	var vp_container: SubViewportContainer = null
	for child in inst.get_children():
		if child is SubViewportContainer:
			vp_container = child
			break
	_ok("SubViewportContainer created at root", vp_container != null)

	var bg_vp: SubViewport = inst.get("_bg_viewport")
	_ok("SubViewport initialized", bg_vp != null and bg_vp.own_world_3d)

	var bg_cam: Camera3D = inst.get("_bg_camera")
	_ok("Camera3D initialized in background", bg_cam != null and bg_cam.current)

	var bg_omni: OmniLight3D = inst.get("_bg_omni")
	_ok("OmniLight3D ember pulse light initialized", bg_omni != null)

	var bg_char: Character = inst.get("_bg_character")
	_ok("Character model loaded in background", bg_char != null)
	if bg_char != null and bg_char.player != null:
		_ok("Character animation is playing", bg_char.player.is_playing() or not bg_char.player.current_animation.is_empty())

	# Test frame process camera angle rotation
	var initial_cam_x := bg_cam.position.x if bg_cam != null else 0.0
	inst.call("_process", 0.5)
	var new_cam_x := bg_cam.position.x if bg_cam != null else 0.0
	_ok("Camera position updates dynamically in process", not is_equal_approx(initial_cam_x, new_cam_x))

	inst.queue_free()
	await process_frame


func _test_movement_sandbox_hud_player_mode() -> void:
	print("\n--- Test 3: Movement Sandbox HUD in Player Mode ---")
	PlaygroundScript.show_debug_hud = false
	PlaygroundScript.return_scene = "res://scenes/player_client/title_screen.tscn"
	PlaygroundScript.start_with_tutorial = false

	var scene := load("res://scenes/playground.tscn") as PackedScene
	_ok("Playground scene loads", scene != null)

	var inst: Node3D = scene.instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame

	var debug_panel: PanelContainer = inst.get("_debug_panel")
	_ok("Debug panel exists in playground", debug_panel != null)
	_ok("Debug panel is HIDDEN in player client mode", debug_panel != null and not debug_panel.visible)

	inst.queue_free()
	await process_frame


func _test_movement_sandbox_hud_dev_mode() -> void:
	print("\n--- Test 4: Movement Sandbox HUD in Developer Mode ---")
	PlaygroundScript.show_debug_hud = true
	PlaygroundScript.return_scene = "res://scenes/main_menu.tscn"
	PlaygroundScript.start_with_tutorial = false

	var scene := load("res://scenes/playground.tscn") as PackedScene
	var inst: Node3D = scene.instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame

	var debug_panel: PanelContainer = inst.get("_debug_panel")
	_ok("Debug panel exists in playground", debug_panel != null)
	_ok("Debug panel is VISIBLE in developer sandbox mode", debug_panel != null and debug_panel.visible)

	inst.queue_free()
	await process_frame
