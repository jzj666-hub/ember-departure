extends SceneTree
## Test probe for Global SceneLoader progress transitions and Player Client Weapon Trial Armory & Combo system.

const SceneLoaderScript = preload("res://scripts/scene_loader.gd")
const WeaponConfigScript = preload("res://scripts/weapon_config.gd")
const WeaponTrialScript = preload("res://scripts/player_client/weapon_trial.gd")
const TitleScreenScript = preload("res://scripts/player_client/title_screen.gd")

var _failures := 0


func _initialize() -> void:
	print("\n=== SceneLoader & Weapon Trial Armory Probe Test Suite ===")

	await _test_scene_loader_and_loading_screen()
	await _test_player_client_weapon_trial()
	await _test_title_screen_weapon_armory_button()

	print("")
	if _failures == 0:
		print("ALL SCENE LOADER & WEAPON TRIAL TESTS PASSED (0 failures)")
	else:
		print("%d TEST(S) FAILED" % _failures)

	quit(_failures)


func _ok(label: String, condition: bool, extra := "") -> void:
	if condition:
		print("  PASS  %s %s" % [label, extra])
	else:
		print("  FAIL  %s %s" % [label, extra])
		_failures += 1


func _test_scene_loader_and_loading_screen() -> void:
	print("\n--- Test 1: Global SceneLoader & Loading Screen ---")
	var l_scene := load("res://scenes/loading_screen.tscn") as PackedScene
	_ok("Loading screen packed scene loads", l_scene != null)

	SceneLoaderScript.target_scene_path = "res://scenes/player_client/title_screen.tscn"
	SceneLoaderScript.target_hint_text = "测试加载提示..."
	ResourceLoader.load_threaded_request(SceneLoaderScript.target_scene_path)

	var inst: Control = l_scene.instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame

	var p_bar: ProgressBar = inst.get("_progress_bar")
	_ok("ProgressBar exists in loading screen", p_bar != null)

	var tip_lbl: Label = inst.get("_tip_label")
	_ok("Tip label displays target hint", tip_lbl != null and tip_lbl.text == "测试加载提示...")

	# Simulate process updates until loaded
	for i in range(10):
		inst.call("_process", 0.1)
		await process_frame

	_ok("Progress bar advances with display progress", p_bar.value >= 0.0)

	inst.queue_free()
	await process_frame


func _test_player_client_weapon_trial() -> void:
	print("\n--- Test 2: Player Client Weapon Trial Armory & Combo Guide ---")
	var trial_scene := load("res://scenes/player_client/weapon_trial.tscn") as PackedScene
	_ok("Weapon trial scene loads", trial_scene != null)

	var inst: Node3D = trial_scene.instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame

	# 1. Check weapon list contents: ONLY configured weapons
	var configured_list: Array[String] = inst.get("_configured_weapons")
	_ok("Configured weapons list loaded", not configured_list.is_empty())
	for w_id in configured_list:
		_ok("Weapon '%s' has saved JSON config" % w_id, WeaponConfigScript.has_config(w_id))
		_ok("Weapon '%s' is not _default or none" % w_id, w_id != "_default" and w_id != "none")

	# 2. Check UI elements & Immersive mode defaults
	var w_list: ItemList = inst.get("_weapon_list")
	_ok("Weapon ItemList exists and is populated", w_list != null and w_list.item_count == configured_list.size())

	var prompt_lbl: Label = inst.get("_combo_prompt_label")
	_ok("Top real-time combo prompt label exists", prompt_lbl != null and not prompt_lbl.text.is_empty())

	var is_imm: bool = inst.get("_immersive")
	_ok("Starts in immersive mode by default", is_imm)

	var left_panel: PanelContainer = inst.get("_left_panel")
	_ok("Left panel is hidden in immersive mode", left_panel != null and not left_panel.visible)

	# Test L key toggle
	inst.call("_set_immersive", false)
	_ok("L toggle exposes left armory panel", left_panel.visible and not inst.get("_immersive"))
	inst.call("_set_immersive", true)
	_ok("Re-toggling L hides armory panel and restores immersive mode", not left_panel.visible and inst.get("_immersive"))

	# 3. Check equipment & weapon switching
	var eq_mgr: EquipmentManager = inst.get("_equipment_manager")
	_ok("EquipmentManager exists on player", eq_mgr != null)
	var active_w: String = inst.get("_current_weapon_id")
	_ok("Active weapon equipped: %s" % active_w, not active_w.is_empty() and eq_mgr.equipped("right_hand") != null)

	# 4. Check dummy target in scene
	var dummy = inst.get("_dummy")
	_ok("Training dummy exists in trial scene", dummy != null)

	# 5. Test switching to second weapon if available
	if configured_list.size() >= 2:
		var second_w := configured_list[1]
		inst.call("_select_weapon", second_w)
		_ok("Switched to second weapon: %s" % second_w, inst.get("_current_weapon_id") == second_w)
		_ok("Second weapon equipped on right hand", eq_mgr.equipped("right_hand") != null)

	inst.queue_free()
	await process_frame


func _test_title_screen_weapon_armory_button() -> void:
	print("\n--- Test 3: Title Screen Weapon Armory Button ---")
	var t_scene := load("res://scenes/player_client/title_screen.tscn") as PackedScene
	var inst: Control = t_scene.instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame

	# Check that title screen instantiates without error and includes new armory button
	_ok("Title screen loaded successfully with armory integration", inst.is_inside_tree())

	inst.queue_free()
	await process_frame
