extends SceneTree
## Probe test suite for MapEditor B-key panels toggle, multi-page tutorial guide, and input invariants.

const MapEditorScript = preload("res://scripts/map_editor.gd")

var _failures := 0


func _initialize() -> void:
	print("\n=== Map Editor B-Key Toggle & Paginated Guide Probe Suite ===")

	var scene := load("res://scenes/map_editor.tscn") as PackedScene
	_ok("MapEditor scene loads successfully", scene != null)

	var editor: Node3D = scene.instantiate()
	root.add_child(editor)
	await process_frame
	await process_frame

	_test_b_key_toggle(editor)
	_test_paginated_tutorial(editor)
	_test_esc_navigation(editor)

	editor.queue_free()
	await process_frame

	print("")
	if _failures == 0:
		print("ALL MAP EDITOR B-KEY & GUIDE TESTS PASSED (0 failures)")
	else:
		print("%d TEST(S) FAILED" % _failures)

	quit(_failures)


func _ok(label: String, condition: bool, extra := "") -> void:
	if condition:
		print("  PASS  %s %s" % [label, extra])
	else:
		print("  FAIL  %s %s" % [label, extra])
		_failures += 1


func _test_b_key_toggle(editor: Node3D) -> void:
	print("\n--- Test 1: B-Key UI Panels & Mouse Cursor Toggle ---")
	var init_visible: bool = editor.get("_ui_panels_visible")
	_ok("Initial _ui_panels_visible is true", init_visible)

	# Simulate B press -> toggles to FALSE (Immersive mode)
	var b_event := InputEventKey.new()
	b_event.keycode = KEY_B
	b_event.pressed = true
	editor._unhandled_input(b_event)

	var now_visible: bool = editor.get("_ui_panels_visible")
	_ok("Pressing B toggles _ui_panels_visible to false", not now_visible)

	var top_panel: PanelContainer = editor.get("_top_panel")
	var left_panel: PanelContainer = editor.get("_left_panel")
	var right_panel: PanelContainer = editor.get("_right_panel")
	_ok("Top panel hidden in immersive mode", top_panel != null and not top_panel.visible)
	_ok("Left panel hidden in immersive mode", left_panel != null and not left_panel.visible)
	_ok("Right panel hidden in immersive mode", right_panel != null and not right_panel.visible)
	_ok("Cursor free is false in immersive mode", not bool(editor.get("_cursor_free")))

	# Simulate B press again -> toggles back to TRUE (Panel mode)
	editor._unhandled_input(b_event)
	_ok("Pressing B again restores _ui_panels_visible to true", bool(editor.get("_ui_panels_visible")))
	_ok("Top panel restored visible", top_panel.visible)
	_ok("Left panel restored visible", left_panel.visible)
	_ok("Right panel restored visible", right_panel.visible)
	_ok("Cursor free is true in panel mode", bool(editor.get("_cursor_free")))


func _test_paginated_tutorial(editor: Node3D) -> void:
	print("\n--- Test 2: Paginated Multi-Page Tutorial Dialog ---")
	var tut_dialog: PanelContainer = editor.get("_tutorial_dialog")
	_ok("Tutorial dialog exists in HUD", tut_dialog != null)

	# Open tutorial dialog at page 0
	editor.call("_open_tutorial_dialog", 0)
	_ok("Tutorial dialog opens", tut_dialog.visible)
	_ok("Page 0: _tutorial_page is 0", editor.get("_tutorial_page") == 0)

	var prev_btn: Button = editor.get("_tutorial_prev_btn")
	var next_btn: Button = editor.get("_tutorial_next_btn")
	var page_lbl: Label = editor.get("_tutorial_page_lbl")

	_ok("Page 0: Prev button is disabled", prev_btn.disabled)
	_ok("Page 0: Page label shows 1/4", "1 / 4" in page_lbl.text)

	# Flip to Page 1
	editor.call("_render_tutorial_page", 1)
	_ok("Page 1: Prev button is enabled", not prev_btn.disabled)
	_ok("Page 1: Page label shows 2/4", "2 / 4" in page_lbl.text)

	# Flip to Page 2
	editor.call("_render_tutorial_page", 2)
	_ok("Page 2: Page label shows 3/4", "3 / 4" in page_lbl.text)

	# Flip to Page 3 (Final Page)
	editor.call("_render_tutorial_page", 3)
	_ok("Page 3: Page label shows 4/4", "4 / 4" in page_lbl.text)
	_ok("Page 3: Next button text changes to Start", "开始" in next_btn.text or "Start" in next_btn.text)

	# Close tutorial dialog
	editor.call("_close_tutorial_dialog")
	_ok("Tutorial dialog closes cleanly", not tut_dialog.visible)


func _test_esc_navigation(editor: Node3D) -> void:
	print("\n--- Test 3: ESC Closes Open Dialogs First ---")
	# Reopen tutorial dialog
	editor.call("_open_tutorial_dialog", 0)
	var tut_dialog: PanelContainer = editor.get("_tutorial_dialog")
	_ok("Tutorial dialog is open", tut_dialog.visible)

	var esc_event := InputEventKey.new()
	esc_event.keycode = KEY_ESCAPE
	esc_event.pressed = true
	editor._unhandled_input(esc_event)

	_ok("ESC closes tutorial dialog first without leaving editor", not tut_dialog.visible and editor.is_inside_tree())
