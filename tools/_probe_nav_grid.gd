extends SceneTree
## Throwaway: does the navigation graph agree with the controller's real limits?
## Every case here is a rule the old height-map graph got wrong.
##
##   godot --headless --path . --script res://tools/_probe_nav_grid.gd

var _failures := 0


func _initialize() -> void:
	_check_capability()
	_check_flat()
	_check_steps()
	_check_detour_cheaper()
	_check_unreachable()
	_check_bridge()
	_check_ceiling()
	_check_corner_cut()
	_check_rebuild_cost()

	print("")
	if _failures == 0:
		print("all nav grid rules hold")
		quit(0)
	else:
		print("%d nav grid rule(s) broken" % _failures)
		quit(1)


func _ok(label: String, condition: bool, detail := "") -> void:
	if condition:
		print("  PASS  %s %s" % [label, detail])
	else:
		_failures += 1
		print("  FAIL  %s %s" % [label, detail])


## A grid with the shipped PlayerController limits and nothing built on it.
func _grid(half := 8) -> NavGrid:
	var grid := NavGrid.new()
	grid.set_bounds(half, 8)
	grid.set_capability_direct(NavGrid.Capability.new())
	return grid


func _wall(grid: NavGrid, z: int, x_from: int, x_to: int, height: int) -> void:
	for x in range(x_from, x_to + 1):
		for y in range(0, height):
			grid.set_block(Vector3i(x, y, z), true)


func _has_move(result: Dictionary, move: int) -> bool:
	for m in result.moves:
		if m == move:
			return true
	return false


func _check_capability() -> void:
	print("\n--- rise limits come from jump_speed / climb_max_height ---")
	var cap := NavGrid.Capability.new()
	print("  jump apex %.3f m, climb range [%.2f, %.2f] m" % [
		cap.jump_apex(), cap.climb_min, cap.climb_max])
	_ok("0.8 m rise is a jump", cap.can_rise(0.8) and cap.rise_move(0.8) == NavGrid.Move.JUMP)
	_ok("1.0 m rise is a climb", cap.can_rise(1.0) and cap.rise_move(1.0) == NavGrid.Move.CLIMB)
	_ok("2.0 m rise is a climb", cap.can_rise(2.0) and cap.rise_move(2.0) == NavGrid.Move.CLIMB)
	_ok("2.3 m rise is refused", not cap.can_rise(2.3))
	_ok("3.0 m rise is refused", not cap.can_rise(3.0))
	_ok("5.0 m drop is allowed", cap.can_drop(5.0))
	_ok("6.0 m drop is refused", not cap.can_drop(6.0))


func _check_flat() -> void:
	print("\n--- open ground: string pulling leaves a straight run ---")
	var grid := _grid()
	var result := grid.find_path(Vector3(0.5, 0.0, 0.5), Vector3(5.5, 0.0, 5.5))
	_ok("path found", result.complete)
	_ok("collapsed to a straight line", result.points.size() == 2,
		"(%d waypoints)" % result.points.size())


func _check_steps() -> void:
	print("\n--- walls of one and two cubes are routes, three is not ---")
	for height in [1, 2, 3]:
		# Spans the whole grid, so going round is not on offer and the answer is
		# purely about what the body can get up.
		var grid := _grid(3)
		_wall(grid, 0, -3, 2, height)
		var result := grid.find_path(Vector3(0.5, 0.0, -2.5), Vector3(0.5, 0.0, 2.5))
		if height <= 2:
			_ok("%d-cube wall is climbed over" % height,
				result.complete and _has_move(result, NavGrid.Move.CLIMB))
		else:
			_ok("%d-cube wall is impassable" % height, not result.complete)


func _check_detour_cheaper() -> void:
	print("\n--- costs are seconds: a short wall is walked round, not climbed ---")
	var grid := _grid()
	_wall(grid, 2, -2, 2, 1)
	var result := grid.find_path(Vector3(0.5, 0.0, 0.5), Vector3(0.5, 0.0, 4.5))
	_ok("path found", result.complete)
	_ok("walked round rather than climbed", not _has_move(result, NavGrid.Move.CLIMB))


func _check_unreachable() -> void:
	print("\n--- a wall too high to climb and too wide to pass ---")
	var grid := _grid(4)
	_wall(grid, 1, -4, 3, 3)
	var result := grid.find_path(Vector3(0.5, 0.0, -1.5), Vector3(0.5, 0.0, 3.5))
	_ok("reported unreachable", not result.complete)
	_ok("stops on the near side", not result.points.is_empty()
		and result.points[result.points.size() - 1].z < 1.0,
		"(ends at z=%.1f)" % (result.points[result.points.size() - 1].z
			if not result.points.is_empty() else NAN))


func _check_bridge() -> void:
	print("\n--- a deck on pillars: the span underneath stays walkable ---")
	var grid := _grid(4)
	for x in range(-4, 4):
		grid.set_block(Vector3i(x, 3, 1), true)
	for y in range(0, 3):
		grid.set_block(Vector3i(-4, y, 1), true)
		grid.set_block(Vector3i(3, y, 1), true)
	var result := grid.find_path(Vector3(0.5, 0.0, -1.5), Vector3(0.5, 0.0, 3.5))
	_ok("walks under the deck", result.complete)
	_ok("never leaves the ground", not _has_move(result, NavGrid.Move.CLIMB))


func _check_ceiling() -> void:
	print("\n--- a cube overhead removes the cell under it ---")
	var grid := _grid()
	grid.set_block(Vector3i(0, 1, 0), true)
	_ok("cell under the overhang is not standable",
		grid.standing_node(Vector3(0.5, 0.0, 0.5)) != Vector3i(0, 0, 0))
	var result := grid.find_path(Vector3(-2.5, 0.0, 0.5), Vector3(2.5, 0.0, 0.5))
	_ok("path detours around it", result.complete and result.points.size() > 2,
		"(%d waypoints)" % result.points.size())


func _check_corner_cut() -> void:
	print("\n--- diagonals may not squeeze between two blocks ---")
	var grid := _grid()
	grid.set_block(Vector3i(1, 0, 0), true)
	grid.set_block(Vector3i(0, 0, 1), true)
	var result := grid.find_path(Vector3(0.5, 0.0, 0.5), Vector3(1.5, 0.0, 1.5))
	_ok("no single diagonal hop", result.points.size() > 2,
		"(%d waypoints)" % result.points.size())


## The scene rebuilds the whole graph on every cube placed. At the playfield's
## real size that has to stay inside a frame.
func _check_rebuild_cost() -> void:
	print("\n--- full rebuild at the scene's own size (40 x 40 x 9) ---")
	var grid := _grid(20)
	for x in range(-6, 7):
		for y in range(0, 3):
			grid.set_block(Vector3i(x, y, 4), true)
	grid.rebuild()

	var start := Time.get_ticks_usec()
	for i in 10:
		grid.set_block(Vector3i(0, 5, 0), i % 2 == 0)
		grid.rebuild()
	var each := float(Time.get_ticks_usec() - start) / 10000.0
	_ok("rebuild under 16 ms", each < 16.0, "(%.1f ms each)" % each)

	start = Time.get_ticks_usec()
	var path := grid.find_path(Vector3(-18.5, 0.0, -18.5), Vector3(18.5, 0.0, 18.5))
	var search := float(Time.get_ticks_usec() - start) / 1000.0
	_ok("corner-to-corner search under 16 ms", search < 16.0 and path.complete,
		"(%.1f ms, %d waypoints)" % [search, path.points.size()])
