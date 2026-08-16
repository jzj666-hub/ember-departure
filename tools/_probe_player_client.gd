extends SceneTree
## Headless probe for User Client title screen, chase game, and audio dispatcher.

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const TitleScreenScript = preload("res://scripts/player_client/title_screen.gd")
const ChaseGameScript = preload("res://scripts/player_client/chase_game.gd")

var _failures := 0


func _initialize() -> void:
	print("\n=== Player Client & Audio Probe Test Suite ===")

	_test_audio_manager()
	_test_title_screen_scene()
	_test_chase_game_scene()

	print("")
	if _failures == 0:
		print("ALL PLAYER CLIENT TESTS PASSED (0 failures)")
	else:
		print("%d PLAYER CLIENT TEST(S) FAILED" % _failures)

	quit(_failures)


func _ok(label: String, condition: bool, extra := "") -> void:
	if condition:
		print("  PASS  %s %s" % [label, extra])
	else:
		print("  FAIL  %s %s" % [label, extra])
		_failures += 1


func _test_audio_manager() -> void:
	print("\n--- Test 1: AudioManager & Voice Assets ---")
	var dummy := Node.new()
	root.add_child(dummy)
	AudioManagerScript.init_pool(dummy, 4)

	_ok("AudioManager pool initialized", AudioManagerScript._player_pool.size() == 4)

	# Verify voice asset files exist
	var files_to_check := [
		"res://assets/voice/Voiceover Pack/Male/1.ogg",
		"res://assets/voice/Voiceover Pack/Male/5.ogg",
		"res://assets/voice/Voiceover Pack/Male/go.ogg",
		"res://assets/voice/Voiceover Pack/Male/you_lose.ogg",
		"res://assets/UI_assets/claw-slashes.svg",
		"res://assets/UI_assets/extra-time.svg",
		"res://assets/UI_assets/grim-reaper.svg",
		"res://assets/buttons_pattern/W.png",
		"res://assets/buttons_pattern/SPACE.png",
	]
	for f in files_to_check:
		_ok("Asset exists: %s" % f.get_file(), ResourceLoader.exists(f))

	dummy.queue_free()


func _test_title_screen_scene() -> void:
	print("\n--- Test 2: TitleScreen Scene Instantiation ---")
	var scene := load("res://scenes/player_client/title_screen.tscn") as PackedScene
	_ok("TitleScreen scene loaded", scene != null)

	var inst: Control = scene.instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame

	_ok("TitleScreen instantiated into tree", inst.is_inside_tree())

	# Test guide dialog opening
	inst.call("_open_guide_dialog")
	var guide_dialog: PanelContainer = inst.get("_guide_dialog")
	_ok("Guide dialog opens successfully", guide_dialog != null and guide_dialog.visible)

	inst.queue_free()
	await process_frame


func _test_chase_game_scene() -> void:
	print("\n--- Test 3: ChaseGame Scene & Gameplay Invariants ---")
	var scene := load("res://scenes/player_client/chase_game.tscn") as PackedScene
	_ok("ChaseGame scene loaded", scene != null)

	var inst: Node3D = scene.instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame

	_ok("ChaseGame initialized into tree", inst.is_inside_tree())
	_ok("Initial state is ESCAPE_COUNTDOWN", inst.get("_state") == ChaseGameScript.State.ESCAPE_COUNTDOWN)

	# Verify keycaps overlay is built
	var keycaps: PanelContainer = inst.get("_keycaps_overlay")
	_ok("Keycaps overlay created", keycaps != null and keycaps.visible)

	# Simulate active chase transition
	inst.call("_start_active_chase")
	_ok("State transitions to CHASE_ACTIVE", inst.get("_state") == ChaseGameScript.State.CHASE_ACTIVE)

	inst.queue_free()
	await process_frame
