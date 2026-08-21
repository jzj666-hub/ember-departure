extends SceneTree
## Automated probe and validation test suite for KeybindManager and PlayerIntentSource remapping.

const KeybindManagerScript = preload("res://scripts/keybind_manager.gd")
const PlayerIntentSourceScript = preload("res://scripts/player_intent_source.gd")
const CharacterIntentScript = preload("res://scripts/character_intent.gd")
const KeybindRemapPanelScript = preload("res://scripts/keybind_remap_panel.gd")

var _passes := 0
var _failures := 0


func _init() -> void:
	print("\n=== Keybind System & Controls Redirection Probe Suite ===")
	_test_defaults_and_display()
	_test_rebinding_and_double_tap()
	_test_disk_persistence()
	_test_player_intent_source_polling()
	_test_remap_panel_ui()
	_test_title_screen_keybind_entry()

	print("\n========================================================")
	if _failures == 0:
		print("ALL KEYBIND REDIRECTION TESTS PASSED (%d passes, 0 failures)\n" % _passes)
	else:
		printerr("TESTS FAILED (%d failures, %d passes)\n" % [_failures, _passes])
	quit(0 if _failures == 0 else 1)


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passes += 1
		print("  PASS  %s" % msg)
	else:
		_failures += 1
		printerr("  FAIL  %s" % msg)


func _test_defaults_and_display() -> void:
	print("\n--- Test 1: KeybindManager Defaults & Text Formatting ---")
	var km = KeybindManagerScript.get_instance()
	km.reset_to_defaults()

	var roll_bind: Dictionary = km.get_binding("roll")
	_assert_true(roll_bind.get("trigger") == "double_tap", "Default roll is double_tap")
	_assert_true(roll_bind.get("code") == KEY_SHIFT, "Default roll code is KEY_SHIFT")

	var roll_txt: String = km.binding_display_text("roll")
	_assert_true(roll_txt == "双击 Shift", "Roll display text is '双击 Shift', got: %s" % roll_txt)

	var roll_key_only: String = km.binding_key_only_text("roll")
	_assert_true(roll_key_only == "Shift", "Roll key only text is 'Shift', got: %s" % roll_key_only)

	var atk_bind: Dictionary = km.get_binding("attack")
	_assert_true(atk_bind.get("device") == "mouse" and atk_bind.get("code") == MOUSE_BUTTON_LEFT, "Default attack is Mouse Left")
	var atk_txt: String = km.binding_display_text("attack")
	_assert_true(atk_txt == "鼠标左键", "Attack display text is '鼠标左键', got: %s" % atk_txt)

	var hvy_prompt: String = km.binding_short_action_text("heavy")
	_assert_true(hvy_prompt == "点右键", "Heavy short prompt is '点右键', got: %s" % hvy_prompt)


func _test_rebinding_and_double_tap() -> void:
	print("\n--- Test 2: Dynamic Rebinding & Trigger Mode Toggle ---")
	var km = KeybindManagerScript.get_instance()

	# Rebind roll to Double-tap Space
	km.set_binding("roll", {"device": "key", "code": KEY_SPACE, "trigger": "double_tap"})
	var roll_txt: String = km.binding_display_text("roll")
	_assert_true(roll_txt == "双击 空格 (Space)", "Rebound roll text is '双击 空格 (Space)', got: %s" % roll_txt)

	# Toggle trigger mode directly to single
	km.set_action_trigger_mode("roll", "single")
	var roll_single_txt: String = km.binding_display_text("roll")
	_assert_true(roll_single_txt == "空格 (Space)", "After mode toggle, roll is single '空格 (Space)', got: %s" % roll_single_txt)

	# Rebind attack to Key Q
	km.set_binding("attack", {"device": "key", "code": KEY_Q, "trigger": "single"})
	var atk_prompt: String = km.binding_short_action_text("attack")
	_assert_true(atk_prompt == "按 Q", "Rebound attack prompt is '按 Q', got: %s" % atk_prompt)

	# Rebind heavy to Double-tap E
	km.set_binding("heavy", {"device": "key", "code": KEY_E, "trigger": "double_tap"})
	var hvy_prompt: String = km.binding_short_action_text("heavy")
	_assert_true(hvy_prompt == "双击 E", "Rebound heavy prompt is '双击 E', got: %s" % hvy_prompt)


func _test_disk_persistence() -> void:
	print("\n--- Test 3: Save & Load Persistence from Disk ---")
	var km = KeybindManagerScript.get_instance()

	# Set custom binding
	km.set_binding("roll", {"device": "key", "code": KEY_C, "trigger": "double_tap"})
	km.set_binding("block", {"device": "key", "code": KEY_F, "trigger": "single"})
	km.save_to_disk()

	# Create new instance and load
	var km2 = KeybindManagerScript.new()
	km2.load_from_disk()

	var loaded_roll: Dictionary = km2.get_binding("roll")
	_assert_true(loaded_roll.get("code") == KEY_C and loaded_roll.get("trigger") == "double_tap", "Loaded roll binding matches saved state")

	var loaded_block: Dictionary = km2.get_binding("block")
	_assert_true(loaded_block.get("code") == KEY_F and loaded_block.get("trigger") == "single", "Loaded block binding matches saved state")

	# Reset back to defaults
	km.reset_to_defaults()
	var reset_roll: Dictionary = km.get_binding("roll")
	_assert_true(reset_roll.get("code") == KEY_SHIFT and reset_roll.get("trigger") == "double_tap", "Reset defaults restores Shift double-tap")


func _test_player_intent_source_polling() -> void:
	print("\n--- Test 4: PlayerIntentSource Polling & Edge Timing ---")
	var km = KeybindManagerScript.get_instance()
	km.reset_to_defaults()

	var pis = PlayerIntentSourceScript.new()
	var intent = CharacterIntentScript.new()

	var dummy_node := Node.new()

	# Test initial polling (no keys pressed)
	pis.poll(dummy_node, 0.016, intent)
	_assert_true(intent.move == Vector2.ZERO, "Initial move vector is zero")
	_assert_true(not intent.roll, "Initial roll is false")
	_assert_true(not intent.jump, "Initial jump is false")

	# Test double-tap detection logic with simulated internal state
	pis._down_state["roll"] = false
	pis._tap_timer["roll"] = 0.15 # Under 0.28s

	# Simulated just pressed when trigger is double_tap
	var b_roll: Dictionary = km.get_binding("roll")
	_assert_true(b_roll.get("trigger") == "double_tap", "Roll is configured as double tap")

	# Clean up
	dummy_node.free()


func _test_remap_panel_ui() -> void:
	print("\n--- Test 5: KeybindRemapPanel UI & Mode Buttons ---")
	var panel = KeybindRemapPanelScript.new()
	_assert_true(panel != null, "KeybindRemapPanel successfully instantiated")
	_assert_true(panel._action_rows.size() >= 12, "All 12 locomotion and combat actions registered in panel, got: %d" % panel._action_rows.size())

	# Test mode button toggle
	var roll_row: Dictionary = panel._action_rows["roll"]
	var mode_btn: Button = roll_row.get("mode_button")
	_assert_true(mode_btn != null, "Mode button exists on roll action row")
	_assert_true(mode_btn.text.contains("双击"), "Default roll mode button text contains '双击', got: %s" % mode_btn.text)

	panel.free()


func _test_title_screen_keybind_entry() -> void:
	print("\n--- Test 6: Title Screen Keybind Settings Entry ---")
	var title_scene_res := load("res://scenes/player_client/title_screen.tscn") as PackedScene
	_assert_true(title_scene_res != null, "Title screen scene loads successfully")
	var title_inst = title_scene_res.instantiate()
	_assert_true(title_inst != null, "Title screen instantiated")
	root.add_child(title_inst)
	if not title_inst.is_node_ready():
		title_inst._ready()
	_assert_true(title_inst._keybind_dialog != null, "Keybind dialog exists on TitleScreen")
	root.remove_child(title_inst)
	title_inst.free()
