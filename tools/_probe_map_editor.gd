extends SceneTree
## Headless test probe for Map Editor subsystems: BlockRegistry, MapData, SpecialPathRecorder, and NavGrid special paths.
##
##   godot --headless --path . --script res://tools/_probe_map_editor.gd

const BlockRegistryScript = preload("res://scripts/block_registry.gd")
const MapDataScript = preload("res://scripts/map_data.gd")
const SpecialPathRecorderScript = preload("res://scripts/special_path_recorder.gd")
const MapEditorScript = preload("res://scripts/map_editor.gd")
const NavGridScript = preload("res://scripts/nav_grid.gd")

var _failures := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	print("=== Map Editor Subsystems Test ===")
	_test_block_registry()
	_test_map_data()
	_test_special_path_straight_line_check()
	_test_nav_grid_special_path()
	await _test_map_editor_scene()

	print("")
	if _failures == 0:
		print("ALL MAP EDITOR TESTS PASSED (0 failures)")
		quit(0)
	else:
		print("%d MAP EDITOR TEST(S) FAILED" % _failures)
		quit(1)

func _ok(label: String, condition: bool, detail := "") -> void:
	if condition:
		print("  PASS  %s %s" % [label, detail])
	else:
		_failures += 1
		print("  FAIL  %s %s" % [label, detail])

func _test_block_registry() -> void:
	print("\n--- Test 1: BlockRegistry ---")
	BlockRegistryScript.init_registry()
	var types: Array = BlockRegistryScript.list_types()
	_ok("Block types registered", types.size() >= 5, "Count: %d" % types.size())

	var cube_type = BlockRegistryScript.get_type("cube")
	_ok("Default cube type found", cube_type != null and cube_type.id == "cube")

	var stone_type = BlockRegistryScript.get_type("stone")
	_ok("Stone type found", stone_type != null and stone_type.id == "stone")

	var inst = BlockRegistryScript.BlockInstance.new()
	inst.id = "blk_test"
	inst.type_id = "stone"
	inst.grid_pos = Vector3i(2, 1, 3)
	inst.size = Vector3i(2, 3, 4)

	var occupied: Array = inst.get_occupied_cells()
	_ok("Multi-cell occupied cell count", occupied.size() == 2 * 3 * 4, "Expected: 24, Got: %d" % occupied.size())
	_ok("First occupied cell", occupied[0] == Vector3i(2, 1, 3))
	_ok("Last occupied cell", occupied[occupied.size() - 1] == Vector3i(3, 3, 6))

	var body: StaticBody3D = BlockRegistryScript.create_body(inst)
	_ok("StaticBody3D created", body != null and body is StaticBody3D)
	body.queue_free()

func _test_map_data() -> void:
	print("\n--- Test 2: MapData Save/Load ---")
	var b1 = BlockRegistryScript.BlockInstance.new()
	b1.id = "b1"
	b1.type_id = "cube"
	b1.grid_pos = Vector3i(0, 0, 0)
	b1.size = Vector3i(2, 1, 2)

	var sp := [{
		"id": "path_test_1",
		"from": [0, 0, 0],
		"to": [0, 0, 6],
		"straight_line": true,
		"duration": 0.9,
	}]

	var map_dict: Dictionary = MapDataScript.serialize_map("Test Map 1", Vector3(1, 0, 1), 20, 7, [b1], sp)
	_ok("Serialized map structure", map_dict.has("blocks") and map_dict.has("special_paths"))

	var test_file := "user://maps/_probe_test_map.json"
	var err: int = MapDataScript.save_map_to_file(test_file, map_dict)
	_ok("Save map to file", err == OK, "File: %s" % test_file)

	var loaded: Dictionary = MapDataScript.load_map_from_file(test_file)
	_ok("Loaded map name match", str(loaded.get("name")) == "Test Map 1")
	var loaded_blocks: Array = loaded.get("blocks", [])
	_ok("Loaded blocks count", loaded_blocks.size() == 1)
	var loaded_paths: Array = loaded.get("special_paths", [])
	_ok("Loaded special paths count", loaded_paths.size() == 1)

	# Clean up probe test map file
	DirAccess.remove_absolute(test_file)

func _test_special_path_straight_line_check() -> void:
	print("\n--- Test 3: SpecialPathRecorder Freeform Trajectory & Deviation Math ---")
	var a := Vector2(0.0, 0.0)
	var b := Vector2(0.0, 6.0)
	var line_len := (b - a).length()

	# Perfectly straight point on line (0, 3)
	var d1: float = SpecialPathRecorderScript._point_to_line_dist(Vector2(0.0, 3.0), a, b, line_len)
	_ok("Straight line point has zero deviation", is_zero_approx(d1), "Deviation: %.4f" % d1)

	# Curved point (0.45, 3)
	var d3: float = SpecialPathRecorderScript._point_to_line_dist(Vector2(0.45, 3.0), a, b, line_len)
	_ok("Curved offset detected accurately", d3 > 0.4, "Deviation: %.4f" % d3)

	# Diagonal line from (1, 1) to (5, 5)
	var a_diag := Vector2(1.0, 1.0)
	var b_diag := Vector2(5.0, 5.0)
	var diag_len := (b_diag - a_diag).length()
	var d_diag_straight: float = SpecialPathRecorderScript._point_to_line_dist(Vector2(3.0, 3.0), a_diag, b_diag, diag_len)
	_ok("Diagonal straight point has zero deviation", is_zero_approx(d_diag_straight), "Deviation: %.4f" % d_diag_straight)

	var d_diag_curved: float = SpecialPathRecorderScript._point_to_line_dist(Vector2(3.0, 3.5), a_diag, b_diag, diag_len)
	_ok("Diagonal curved offset calculated properly", d_diag_curved > 0.3, "Deviation: %.4f" % d_diag_curved)

func _test_nav_grid_special_path() -> void:
	print("\n--- Test 4: NavGrid Special Path Integration ---")
	var nav := NavGridScript.new()
	nav.set_bounds(20, 8)
	# Platform A at (0, 0, 0), Platform B at (0, 0, 6) -> 5-cell void between them
	# Standard physics cap budget is ~4m, so 5m void cannot be jumped by default
	var from_cell := Vector3i(0, 0, 0)
	var to_cell := Vector3i(0, 0, 6)

	var cell_a := Vector3i(0, 1, 0)
	var cell_b := Vector3i(0, 1, 6)
	nav.set_block(Vector3i(0, 0, 0), true) # solid block at (0,0,0) -> standable cell at (0,1,0)
	nav.set_block(Vector3i(0, 0, 6), true) # solid block at (0,0,6) -> standable cell at (0,1,6)

	# Now add special path from cell_a to cell_b
	nav.add_special_path({
		"id": "special_jump_ab",
		"from": [cell_a.x, cell_a.y, cell_a.z],
		"to": [cell_b.x, cell_b.y, cell_b.z],
		"straight_line": true,
	})

	var res_special := nav.find_path(NavGrid.foot(cell_a), NavGrid.foot(cell_b))
	_ok("Special path planned successfully", res_special.complete, "Points count: %d" % res_special.points.size())

	var moves: PackedInt32Array = res_special.moves
	var found_special_move := false
	for m in moves:
		if m == NavGridScript.Move.SPECIAL_JUMP:
			found_special_move = true
			break
	_ok("Move classified as Move.SPECIAL_JUMP", found_special_move)

	var valid := nav.is_path_valid(res_special.points)
	_ok("Path with special jump is valid", valid)

	# Multi-path registration test: Add second path B->C
	var cell_c := Vector3i(6, 1, 6)
	nav.set_block(Vector3i(6, 0, 6), true)
	nav.add_special_path({
		"id": "special_jump_bc",
		"from": [cell_b.x, cell_b.y, cell_b.z],
		"to": [cell_c.x, cell_c.y, cell_c.z],
		"trajectory": [{"p": [0, 1, 6]}, {"p": [3, 2, 6]}, {"p": [6, 1, 6]}],
	})
	_ok("Two distinct special paths stored", nav.get_special_paths().size() == 2)

	# Replacement test: re-record A->B with updated trajectory
	nav.add_special_path({
		"id": "special_jump_ab_v2",
		"from": [cell_a.x, cell_a.y, cell_a.z],
		"to": [cell_b.x, cell_b.y, cell_b.z],
		"trajectory": [{"p": [0, 1, 0]}, {"p": [0, 2, 3]}, {"p": [0, 1, 6]}],
	})
	_ok("Replacement maintains 2 total paths", nav.get_special_paths().size() == 2)
	var ab_updated := nav.get_special_path_between(cell_a, cell_b)
	_ok("Updated trajectory retrieved", str(ab_updated.get("id")) == "special_jump_ab_v2")

func _test_map_editor_scene() -> void:
	print("\n--- Test 5: MapEditor Scene Instantiation ---")
	var scene := load("res://scenes/map_editor.tscn") as PackedScene
	_ok("MapEditor scene loaded", scene != null)
	if scene != null:
		var instance: Node = scene.instantiate()
		_ok("MapEditor instantiated", instance != null)
		root.add_child(instance)
		await process_frame
		await process_frame
		_ok("MapEditor executed _ready() without errors", instance.is_inside_tree())
		instance.queue_free()
		await process_frame
