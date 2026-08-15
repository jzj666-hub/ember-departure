extends SceneTree
## Throwaway: does the gap-jump edge rule match the arc the engine actually flies?
## Every number here is derived from the discrete integrator, not the textbook
## continuous one - see NavGrid.Capability._launch().
##
##   godot --headless --path . --script res://tools/_probe_gap_jump.gd

var _failures := 0


func _initialize() -> void:
	_check_ballistics()
	_check_cell_gap()
	_check_reach_table()
	_check_ortho_gaps()
	_check_diagonal_gaps()
	_check_rise_gaps()
	_check_classified_as_jump()
	_check_ceiling_blocks_arc()

	print("")
	if _failures == 0:
		print("all gap jump rules hold")
		quit(0)
	else:
		print("%d gap jump rule(s) broken" % _failures)
		quit(1)


func _ok(label: String, condition: bool, detail := "") -> void:
	if condition:
		print("  PASS  %s %s" % [label, detail])
	else:
		_failures += 1
		print("  FAIL  %s %s" % [label, detail])


func _near(a: float, b: float, tol := 0.001) -> bool:
	return absf(a - b) <= tol


func _grid(half := 12) -> NavGrid:
	var grid := NavGrid.new()
	grid.set_bounds(half, 8)
	grid.set_capability_direct(NavGrid.Capability.new())
	return grid


## A slab of blocks at level `y`, so the standable surface is y + 1. One layer
## only: a body that drops off it cannot climb back on (_connect_ortho wants the
## whole face solid), which is what leaves the arc as the only route.
func _plate(grid: NavGrid, x0: int, x1: int, z0: int, z1: int, y := 1) -> void:
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			grid.set_block(Vector3i(x, y, z), true)


func _has_move(result: Dictionary, move: int) -> bool:
	for m in result.moves:
		if m == move:
			return true
	return false


func _check_ballistics() -> void:
	print("\n--- the arc is the discrete one, not the continuous one ---")
	var cap := NavGrid.Capability.new()
	# u' = jump_speed + g*tick/2: no gravity on the frame the jump starts, and a
	# step late thereafter.
	_ok("apex 1.1665 m", _near(cap.jump_apex(), 1.16655),
		"(%.5f, continuous solution is 1.12704)" % cap.jump_apex())
	_ok("level flight 0.9759 s", _near(cap.flight_time(0.0), 0.97585),
		"(%.5f, continuous solution is 0.95918)" % cap.flight_time(0.0))
	_ok("level reach 3.5131 m", _near(cap.jump_reach(0.0, cap.run_speed), 3.51306),
		"(%.5f)" % cap.jump_reach(0.0, cap.run_speed))
	_ok("a rise past the apex has no arc", is_nan(cap.flight_time(1.4)))
	# Ascending root: when the feet first clear a lip that high.
	_ok("clears a 1 m lip at 0.3550 s", _near(cap.clear_time(1.08), 0.35502),
		"(%.5f)" % cap.clear_time(1.08))
	_ok("a lip at ground level is clear at once", _near(cap.clear_time(0.0), 0.0))


func _check_cell_gap() -> void:
	print("\n--- distance is edge to edge, nearest point to nearest point ---")
	var a := Vector3i(0, 0, 0)
	_ok("touching cells have no gap", _near(NavGrid.cell_gap(a, Vector3i(1, 0, 0)), 0.0))
	_ok("2 cells apart is a 1 m void", _near(NavGrid.cell_gap(a, Vector3i(2, 0, 0)), 1.0))
	_ok("4 cells apart is a 3 m void", _near(NavGrid.cell_gap(a, Vector3i(4, 0, 0)), 3.0))
	_ok("diagonal (3,3) is 2*sqrt(2)", _near(NavGrid.cell_gap(a, Vector3i(3, 0, 3)), 2.82843))
	_ok("diagonal (4,4) is 3*sqrt(2)", _near(NavGrid.cell_gap(a, Vector3i(4, 0, 4)), 4.24264))
	_ok("mixed (4,3) is sqrt(13)", _near(NavGrid.cell_gap(a, Vector3i(4, 0, 3)), 3.60555))
	_ok("height is not part of it", _near(NavGrid.cell_gap(a, Vector3i(2, 5, 0)), 1.0))


func _check_reach_table() -> void:
	print("\n--- what the budget admits, per height difference ---")
	var cap := NavGrid.Capability.new()
	_ok("level budget 3.153 m", _near(cap.gap_jump_budget(0.0), 3.15306),
		"(%.5f)" % cap.gap_jump_budget(0.0))
	_ok("level: 3 m void crossable", cap.can_gap_jump(3.0, 0.0))
	_ok("level: 4 m void refused", not cap.can_gap_jump(4.0, 0.0))
	_ok("level: diagonal 2.828 m crossable", cap.can_gap_jump(2.82843, 0.0))
	_ok("level: diagonal 4.243 m refused", not cap.can_gap_jump(4.24264, 0.0))
	_ok("down 1 m: budget 3.790 m", _near(cap.gap_jump_budget(-1.0), 3.79034),
		"(%.5f)" % cap.gap_jump_budget(-1.0))
	_ok("down 1 m: 3.606 m void crossable", cap.can_gap_jump(3.60555, -1.0))
	_ok("up 1 m: budget 2.060 m", _near(cap.gap_jump_budget(1.0), 2.06024),
		"(%.5f)" % cap.gap_jump_budget(1.0))
	_ok("up 1 m: 2 m void crossable", cap.can_gap_jump(2.0, 1.0))
	# The narrow case is the one a centre-to-centre rule gets wrong in the other
	# direction: the arc is still climbing when it reaches a lip this close, so
	# the body would put its shins through it.
	_ok("up 1 m: 1 m void refused, arc still climbing", not cap.can_gap_jump(1.0, 1.0))
	_ok("up 2 m: nothing crossable", not cap.can_gap_jump(1.0, 2.0))


## Two slabs on the same level with `void_cells` empty columns between them.
## Returns find_path across the void.
func _across(void_cells: int) -> Dictionary:
	var grid := _grid()
	_plate(grid, -5, -1, -1, 1)
	_plate(grid, -1 + void_cells + 1, -1 + void_cells + 5, -1, 1)
	return grid.find_path(Vector3(-1.5, 2.0, 0.5),
		Vector3(float(void_cells) + 1.5, 2.0, 0.5))


func _check_ortho_gaps() -> void:
	print("\n--- orthogonal voids: 1 to 3 cells are routes, 4 is not ---")
	for cells in [1, 2, 3]:
		var res := _across(cells)
		_ok("%d-cell void crossed" % cells,
			bool(res.complete) and _has_move(res, NavGrid.Move.JUMP),
			"(%d waypoints)" % res.points.size())
	var far := _across(4)
	_ok("4-cell void refused", not bool(far.complete))


## Two slabs whose nearest cells sit `step` apart on both axes.
func _diagonally(step: int) -> Dictionary:
	var grid := _grid()
	_plate(grid, -4, -1, -4, -1)
	_plate(grid, -1 + step, -1 + step + 3, -1 + step, -1 + step + 3)
	return grid.find_path(Vector3(-1.5, 2.0, -1.5),
		Vector3(float(step) - 0.5, 2.0, float(step) - 0.5))


func _check_diagonal_gaps() -> void:
	print("\n--- diagonal voids: the rule is a distance, not an axis ---")
	for step in [2, 3]:
		var res := _diagonally(step)
		_ok("diagonal (%d,%d) crossed" % [step, step],
			bool(res.complete) and _has_move(res, NavGrid.Move.JUMP))
	var far := _diagonally(4)
	_ok("diagonal (4,4) refused", not bool(far.complete))


func _check_rise_gaps() -> void:
	print("\n--- a void the far side of which is a cell higher ---")
	# Near slab tops at y = 2, far slab tops at y = 3, two empty columns between.
	var grid := _grid()
	_plate(grid, -5, -1, -1, 1, 1)
	for x in range(2, 7):
		for z in range(-1, 2):
			grid.set_block(Vector3i(x, 1, z), true)
			grid.set_block(Vector3i(x, 2, z), true)
	var res := grid.find_path(Vector3(-1.5, 2.0, 0.5), Vector3(3.5, 3.0, 0.5))
	_ok("2-cell void up one level is crossed",
		bool(res.complete) and _has_move(res, NavGrid.Move.JUMP),
		"(%d waypoints)" % res.points.size())


func _check_classified_as_jump() -> void:
	print("\n--- a leg that skips a column is reported as a jump ---")
	var res := _across(2)
	var jumped := false
	for i in range(1, res.points.size()):
		var a: Vector3 = res.points[i - 1]
		var b: Vector3 = res.points[i]
		if Vector2(b.x - a.x, b.z - a.z).length() > 1.2 \
				and absf(b.y - a.y) < 0.01 and int(res.moves[i]) == NavGrid.Move.JUMP:
			jumped = true
	_ok("the level leg over the void is Move.JUMP", jumped)
	_ok("no leg is reported as a plain walk over the void",
		not _walks_over_void(res))


func _walks_over_void(res: Dictionary) -> bool:
	for i in range(1, res.points.size()):
		var a: Vector3 = res.points[i - 1]
		var b: Vector3 = res.points[i]
		if Vector2(b.x - a.x, b.z - a.z).length() > 1.2 \
				and int(res.moves[i]) == NavGrid.Move.WALK:
			return true
	return false


func _check_ceiling_blocks_arc() -> void:
	print("\n--- a lid over the void is a lid over the arc ---")
	var grid := _grid()
	_plate(grid, -5, -1, -1, 1)
	_plate(grid, 2, 6, -1, 1)
	var open := grid.find_path(Vector3(-1.5, 2.0, 0.5), Vector3(2.5, 2.0, 0.5))
	_ok("open void is crossed", bool(open.complete))
	# The body's head passes through here; a cube in it has to refuse the edge.
	for z in range(-1, 2):
		grid.set_block(Vector3i(0, 3, z), true)
		grid.set_block(Vector3i(1, 3, z), true)
	var lidded := grid.find_path(Vector3(-1.5, 2.0, 0.5), Vector3(2.5, 2.0, 0.5))
	_ok("lidded void is refused", not bool(lidded.complete))
