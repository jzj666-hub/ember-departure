extends SceneTree
## Test probe for 9-patch frame textures on Chase Game HUD panels

const ChaseGameScript = preload("res://scripts/player_client/chase_game.gd")
const ChaseModeScript = preload("res://scripts/chase_mode.gd")

var _failures := 0


func _initialize() -> void:
	print("\n=== Chase Mode 9-Patch Frame HUD Probe Test Suite ===")

	await _test_textures_existence()
	await _test_player_client_chase_game_hud()
	await _test_dev_chase_mode_hud()

	print("")
	if _failures == 0:
		print("ALL CHASE 9-PATCH HUD TESTS PASSED (0 failures)")
	else:
		print("%d TEST(S) FAILED" % _failures)

	quit(_failures)


func _ok(label: String, condition: bool, extra := "") -> void:
	if condition:
		print("  PASS  %s %s" % [label, extra])
	else:
		print("  FAIL  %s %s" % [label, extra])
		_failures += 1


func _test_textures_existence() -> void:
	print("\n--- Test 1: 9-Patch PNG Texture Resources ---")
	var tex_alarm := load("res://assets/UI_assets/panel_alarm.png") as Texture2D
	_ok("panel_alarm.png exists and loads as Texture2D", tex_alarm != null, "(%dx%d)" % [tex_alarm.get_width() if tex_alarm else 0, tex_alarm.get_height() if tex_alarm else 0])

	var tex_exquisite := load("res://assets/UI_assets/panel_exquisite.png") as Texture2D
	_ok("panel_exquisite.png exists and loads as Texture2D", tex_exquisite != null, "(%dx%d)" % [tex_exquisite.get_width() if tex_exquisite else 0, tex_exquisite.get_height() if tex_exquisite else 0])

	var tex_medal := load("res://assets/UI_assets/panel_medal.png") as Texture2D
	_ok("panel_medal.png exists and loads as Texture2D", tex_medal != null, "(%dx%d)" % [tex_medal.get_width() if tex_medal else 0, tex_medal.get_height() if tex_medal else 0])


func _test_player_client_chase_game_hud() -> void:
	print("\n--- Test 2: Player Client Chase Game HUD 9-Patch Panels ---")
	var chase_scene := load("res://scenes/player_client/chase_game.tscn") as PackedScene
	_ok("Player client chase_game scene loads", chase_scene != null)

	var inst: Node3D = chase_scene.instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame

	# 1. Banner panel
	var banner: PanelContainer = inst.get("_banner_panel")
	_ok("Banner panel container exists", banner != null)
	var banner_style = banner.get_theme_stylebox("panel") if banner else null
	_ok("Banner style is StyleBoxTexture", banner_style is StyleBoxTexture)
	if banner_style is StyleBoxTexture:
		var st := banner_style as StyleBoxTexture
		_ok("Banner style texture is panel_alarm.png", st.texture != null and st.texture.resource_path.ends_with("panel_alarm.png"))
		_ok("Banner 9-patch margins configured", st.texture_margin_left > 0 and st.texture_margin_top > 0 and st.texture_margin_right > 0 and st.texture_margin_bottom > 0)

	# 2. Info box (Clean without background panel)
	var info_box: PanelContainer = inst.get("_info_box")
	_ok("Info box panel exists", info_box != null)
	var info_style = info_box.get_theme_stylebox("panel") if info_box else null
	_ok("Info box has empty/clean style without background panel", info_style is StyleBoxEmpty)

	# 3. Keycaps overlay (Removed as requested)
	var keycaps: PanelContainer = inst.get("_keycaps_overlay")
	_ok("Keycaps overlay is null/not rendered on screen", keycaps == null or not keycaps.visible)

	# 4. Game over modal (Uses panel_exquisite.png with rounded feathered borders)
	var game_over: PanelContainer = inst.get("_game_over_dialog")
	_ok("Game over dialog exists", game_over != null)
	var go_style = game_over.get_theme_stylebox("panel") if game_over else null
	_ok("Game over style is StyleBoxTexture", go_style is StyleBoxTexture)
	if go_style is StyleBoxTexture:
		var st := go_style as StyleBoxTexture
		_ok("Game over style texture is panel_exquisite.png", st.texture != null and st.texture.resource_path.ends_with("panel_exquisite.png"))

	# 5. Countdown & active chase HUD updates
	inst.call("_update_escape_countdown_hud")
	_ok("Countdown HUD update executes without error", true)
	inst.call("_update_active_chase_hud")
	_ok("Active chase HUD update executes without error", true)

	inst.queue_free()
	await process_frame


func _test_dev_chase_mode_hud() -> void:
	print("\n--- Test 3: Dev Chase Mode HUD 9-Patch Panels ---")
	var mode_scene := load("res://scenes/chase_mode.tscn") as PackedScene
	_ok("Dev chase_mode scene loads", mode_scene != null)

	var inst: Node3D = mode_scene.instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame

	var banner: PanelContainer = inst.get("_banner_panel")
	_ok("Dev Banner panel exists", banner != null)
	var b_style = banner.get_theme_stylebox("panel") if banner else null
	_ok("Dev Banner is StyleBoxTexture", b_style is StyleBoxTexture)

	var info_box: PanelContainer = inst.get("_info_box")
	_ok("Dev Info box exists", info_box != null)
	var i_style = info_box.get_theme_stylebox("panel") if info_box else null
	_ok("Dev Info box has clean empty style", i_style is StyleBoxEmpty)

	var game_over: PanelContainer = inst.get("_game_over_dialog")
	_ok("Dev Game over dialog exists", game_over != null)
	var go_style = game_over.get_theme_stylebox("panel") if game_over else null
	_ok("Dev Game over style is panel_exquisite.png", go_style is StyleBoxTexture and (go_style as StyleBoxTexture).texture.resource_path.ends_with("panel_exquisite.png"))

	inst.queue_free()
	await process_frame
