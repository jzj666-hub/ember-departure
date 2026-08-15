extends SceneTree
## Headless test probe for Map Editor subsystems: BlockRegistry, MapData, SpecialPathRecorder, and NavGrid special paths.
##
##   godot --headless --path . --script res://tools/_probe_map_editor.gd

const BlockRegistryScript = preload("res://scripts/block_registry.gd")
const MapDataScript = preload("res://scripts/map_data.gd")
const SpecialPathRecorderScript = preload("res://scripts/special_path_recorder.gd")
const MapEditorScript = preload("res://scripts/map_editor.gd")

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
	print("\n--- Test 3: SpecialPathRecorder Straight-Line Math ---")
	var a := Vector2(0.0, 0.0)
	var b := Vector2(0.0, 6.0) # straight line along Z axis
	var line_len := (b - a).length()

	# Perfectly straight point on line (0, 3)
	var d1: float = SpecialPathRecorderScript._point_to_line_dist(Vector2(0.0, 3.0), a, b, line_len)
	_ok("Straight line point has zero deviation", is_zero_approx(d1), "Deviation: %.4f" % d1)

	# Slight jitter within tolerance (0.05, 3)
	var d2: float = SpecialPathRecorderScript._point_to_line_dist(Vector2(0.05, 3.0), a, b, line_len)
	_ok("Small jitter within tolerance", d2 <= SpecialPathRecorderScript.STRAIGHT_LINE_TOLERANCE, "Deviation: %.4f" % d2)

	# Large curve outside tolerance (0.45, 3)
	var d3: float = SpecialPathRecorderScript._point_to_line_dist(Vector2(0.45, 3.0), a, b, line_len)
	_ok("Large deviation exceeds tolerance", d3 > SpecialPathRecorderScript.STRAIGHT_LINE_TOLERANCE, "Deviation: %.4f" % d3)

	# Diagonal line from (1, 1) to (5, 5)
	var a_diag := Vector2(1.0, 1.0)
	var b_diag := Vector2(5.0, 5.0)
	var diag_len := (b_diag - a_diag).length()
	var d_diag_straight: float = SpecialPathRecorderScript._point_to_line_dist(Vector2(3.0, 3.0), a_diag, b_diag, diag_len)
	_ok("Diagonal straight point has zero deviation", is_zero_approx(d_diag_straight), "Deviation: %.4f" % d_diag_straight)

	var d_diag_curved: float = SpecialPathRecorderScript._point_to_line_dist(Vector2(3.0, 3.5), a_diag, b_diag, diag_len)
	_ok("Diagonal offset detected", d_diag_curved > 0.3, "Deviation: %.4f" % d_diag_curved)

func _test_nav_grid_special_path() -> void:
	print("\n--- Test 4: NavGrid Special Path Integration ---")
	var nav := NavGrid.new()
	nav.set_bounds(20, 8)
	# Platform A at (0, 0, 0), Platform B at (0, 0, 6) -> 5-cell void between them
	# Standard physics cap budget is ~4m, so 5m void cannot be jumped by default
	# Platform A with runup from (0, 0, -2) to (0, 0, 0), Platform B at (0, 0, 6) -> 5-cell void
	var from_cell := Vector3i(0, 0, 0)
	var to_cell := Vector3i(0, 0, 6)

	var cell_a := Vector3i(0, 1, -2)
	var cell_b := Vector3i(0, 1, 6)
	nav.set_block(Vector3i(0, 0, -2), true)
	nav.set_block(Vector3i(0, 0, -1), true)
	nav.set_block(Vector3i(0, 0, 0), true) # solid block at (0,0,0) -> standable cell at (0,1,0)
	nav.set_block(Vector3i(0, 0, 6), true) # solid block at (0,0,6) -> standable cell at (0,1,6)

	# Now add special path from (0, 1, 0) to cell_b (0, 1, 6) with exact run-up start, takeoff and landing positions
	var s_pos := Vector3(0.5, 1.0, -1.5)
	var t_pos := Vector3(0.5, 1.0, 0.9)
	var l_pos := Vector3(0.5, 1.0, 5.7)
	var takeoff_cell := Vector3i(0, 1, 0)
	nav.add_special_path({
		"id": "special_jump_ab",
		"from": [takeoff_cell.x, takeoff_cell.y, takeoff_cell.z],
		"to": [cell_b.x, cell_b.y, cell_b.z],
		"start_pos": [s_pos.x, s_pos.y, s_pos.z],
		"takeoff_pos": [t_pos.x, t_pos.y, t_pos.z],
		"landing_pos": [l_pos.x, l_pos.y, l_pos.z],
		"runup_distance": 2.4,
		"takeoff_speed": 3.6,
		"duration": 0.88,
		"straight_line": true,
	})

	var res_special := nav.find_path(NavGrid.foot(cell_a), NavGrid.foot(cell_b))
	_ok("Special path planned successfully", res_special.complete, "Points count: %d" % res_special.points.size())

	var moves: PackedInt32Array = res_special.moves
	var found_special_move := false
	var found_start_pt := false
	var found_takeoff_pt := false
	var found_landing_pt := false
	for i in range(res_special.points.size()):
		var pt: Vector3 = res_special.points[i]
		if pt.distance_to(s_pos) < 0.01:
			found_start_pt = true
		if pt.distance_to(t_pos) < 0.01:
			found_takeoff_pt = true
		if pt.distance_to(l_pos) < 0.01:
			found_landing_pt = true
		if moves[i] == NavGrid.Move.SPECIAL_JUMP:
			found_special_move = true

	_ok("Move classified as Move.SPECIAL_JUMP", found_special_move)
	_ok("Run-up start waypoint included", found_start_pt)
	_ok("Exact takeoff waypoint included", found_takeoff_pt)
	_ok("Exact landing waypoint included", found_landing_pt)

	var valid := nav.is_path_valid(res_special.points)
	if not valid:
		for i in range(res_special.points.size() - 1):
			var sub_valid := nav.is_path_valid(PackedVector3Array([res_special.points[i], res_special.points[i+1]]))
			print("  [DEBUG] Segment %d: %s -> %s (Valid: %s)" % [i, str(res_special.points[i]), str(res_special.points[i+1]), str(sub_valid)])
	_ok("Path with special jump is valid", valid)

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
