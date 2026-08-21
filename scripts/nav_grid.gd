class_name NavGrid
extends NavProvider
## Voxel navigation grid + capability-derived A* for CharacterBody3D agents.
## The `changed` signal fires when the block layout changes.
##
## Cell c occupies the world box [c, c+1) on every axis. An agent standing in c
## has its feet at foot(c) = Vector3(c.x + 0.5, c.y, c.z + 0.5) - cell centre in
## XZ, cell floor in Y.
##
## Invariants:
## - every AStar point is a standable cell; point ids are dense from 0
## - _nodes, _columns and _astar are rebuilt together and never partially updated
## - all edges are directed: rise and drop rules are not symmetric

const NO_CELL := Vector3i(-32768, -32768, -32768)
## Sample step of the string-pulling straight-line test, metres.
const LINE_STEP := 0.2

const DIR_ORTHO := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const DIR_DIAG := [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
## The eight XZ neighbours, in the order the ring mask indexes them: the bit a
## neighbour (sx, sz) owns is 1 << ((sx + 1) * 3 + sz + 1). See _connect().
const DIR_RING := [
	Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1),
	Vector2i(0, -1), Vector2i(0, 1),
	Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
]
## Every ring bit but the centre's: a cell that can be walked out of in all eight
## directions.
const RING_FULL := 0x1EF


## A* whose costs are seconds of travel, so the heuristic (straight line at top
## speed) can never exceed the real cost. Pre: cap is set before any search.
class NavAStar extends AStar3D:
	var cap: Capability = Capability.new()

	func _compute_cost(from_id: int, to_id: int) -> float:
		var a := get_point_position(from_id)
		var b := get_point_position(to_id)
		var horiz := Vector2(b.x - a.x, b.z - a.z).length()
		var dh := b.y - a.y
		var seconds := horiz / maxf(cap.run_speed, 0.01)
		if dh > 0.01:
			seconds += cap.rise_time(dh)
		elif dh < -0.01:
			seconds += cap.drop_time(-dh)
		return seconds

	func _estimate_cost(from_id: int, to_id: int) -> float:
		var d := get_point_position(from_id).distance_to(get_point_position(to_id))
		return d / maxf(cap.run_speed, 0.01)


var _astar := NavAStar.new()

## Solid cells. Keys are Vector3i, values unused.
var _blocks := {}
## Vector2i column -> Dictionary of its occupied y levels. Derived from _blocks
## and written only alongside it. Invariant: a column absent here holds nothing,
## which is what lets rebuild() skip the per-level scan over open ground.
var _col_blocks := {}
## Standable cell -> astar id.
var _nodes := {}
## Vector2i column -> PackedInt32Array of standable levels, ascending.
var _columns := {}
## Scratch for _gap_clear()'s duplicate-column filter. Cleared per call, never
## read outside it.
var _span_seen := {}
var _special_paths: Array = []

var _half := 20
var _max_y := 8
var _head := 2
var _dirty := true


# --- configuration ----------------------------------------------------------

## Registers a custom recorded special jump connection between two cells.
## If an existing path between the same cells or with the same id exists, it is replaced.
func add_special_path(path_dict: Dictionary) -> void:
	var from_c := _parse_coord(path_dict.get("from"))
	var to_c := _parse_coord(path_dict.get("to"))
	var path_id := str(path_dict.get("id", ""))
	for i in range(_special_paths.size() - 1, -1, -1):
		var old_id := str(_special_paths[i].get("id", ""))
		var f := _parse_coord(_special_paths[i].get("from"))
		var t := _parse_coord(_special_paths[i].get("to"))
		if (path_id != "" and old_id == path_id) or (f == from_c and t == to_c):
			_special_paths.remove_at(i)
	_special_paths.append(path_dict.duplicate(true))
	_dirty = true
	changed.emit()


## Removes recorded special path by its id.
func remove_special_path(path_id: String) -> void:
	for i in range(_special_paths.size() - 1, -1, -1):
		if str(_special_paths[i].get("id", "")) == path_id:
			_special_paths.remove_at(i)
			_dirty = true
			changed.emit()
			return


## Clears all recorded special paths.
func clear_special_paths() -> void:
	_special_paths.clear()
	_dirty = true
	changed.emit()


## Sets complete array of special paths.
func set_special_paths(paths: Array) -> void:
	_special_paths = paths.duplicate(true)
	_dirty = true
	changed.emit()


## Returns array of registered special paths.
func get_special_paths() -> Array:
	return _special_paths


## Finds special path matching from_cell -> to_cell.
func get_special_path_between(from_cell: Vector3i, to_cell: Vector3i) -> Dictionary:
	for i in range(_special_paths.size() - 1, -1, -1):
		var p: Dictionary = _special_paths[i]
		var f := _parse_coord(p.get("from"))
		var t := _parse_coord(p.get("to"))
		if f == from_cell and t == to_cell:
			return p.duplicate(true)
	return {}


static func _parse_coord(v: Variant) -> Vector3i:
	if v is Vector3i:
		return v
	if v is Vector3:
		return Vector3i(int(floor(v.x)), int(round(v.y)), int(floor(v.z)))
	if v is Array and v.size() >= 3:
		return Vector3i(int(v[0]), int(v[1]), int(v[2]))
	return NO_CELL


## Playable cell range: x,z in [-half, half), y in [0, max_y]. Marks dirty.
func set_bounds(half: int, max_y: int) -> void:
	_half = maxi(1, half)
	_max_y = maxi(0, max_y)
	_dirty = true


## Also refreshes the A* cost model and the headroom the graph requires.
## Marks dirty.
func set_capability_direct(cap: Capability) -> void:
	super(cap)
	_astar.cap = cap
	_head = cap.head_cells()
	_dirty = true


# --- world state ------------------------------------------------------------

## Adds or clears a solid cell. Marks dirty; does not rebuild. Emits changed.
func set_block(coord: Vector3i, solid: bool) -> void:
	var col := Vector2i(coord.x, coord.z)
	if solid:
		if _blocks.has(coord):
			return
		_blocks[coord] = true
		if not _col_blocks.has(col):
			_col_blocks[col] = {}
		_col_blocks[col][coord.y] = true
	else:
		if not _blocks.erase(coord):
			return
		var levels: Dictionary = _col_blocks.get(col, {})
		levels.erase(coord.y)
		if levels.is_empty():
			_col_blocks.erase(col)
	_dirty = true
	changed.emit()


func clear_blocks() -> void:
	if _blocks.is_empty():
		return
	_blocks.clear()
	_col_blocks.clear()
	_dirty = true
	changed.emit()


func is_solid(coord: Vector3i) -> bool:
	return _blocks.has(coord)


## Cell is a node of the graph: a body standing there is supported and fits.
## What the executor asks to find the rim it takes off from - block solidity
## answers the wrong question at y == 0, where the floor is the world plane and
## no block exists under it.
func is_standable(coord: Vector3i) -> bool:
	rebuild()
	return _nodes.has(coord)


## NavProvider contract, world-space. Level is floor(y + 0.05): the sample point
## carries the level its caller derived, so a horizontal sweep stays on one level.
func is_standable_at(point: Vector3) -> bool:
	return is_standable(Vector3i(int(floor(point.x)), int(floor(point.y + 0.05)), int(floor(point.z))))


## NavProvider contract. Centre of the cell the body stands in, at its own height.
## Falls back to the bare arithmetic centre when no cell of the graph holds it.
func stand_center(pos: Vector3) -> Vector3:
	var f := stand_foot(pos)
	if f == NO_POINT:
		return super(pos)
	return Vector3(f.x, pos.y, f.z)


## NavProvider contract. Foot of the standing cell, cell floor included.
func stand_foot(pos: Vector3) -> Vector3:
	var node := standing_node(pos)
	return NO_POINT if node == NO_CELL else foot(node)


func block_count() -> int:
	return _blocks.size()


func is_dirty() -> bool:
	return _dirty


## Cell c is in bounds. Y is allowed one past the block ceiling: that is the
## surface a block on the top layer creates.
func in_bounds(c: Vector3i) -> bool:
	return c.x >= -_half and c.x < _half and c.z >= -_half and c.z < _half \
		and c.y >= 0 and c.y <= _max_y


## Feet of an agent standing in cell c: cell centre in XZ, cell floor in Y.
## Cell centres, not cell corners - a corner waypoint sits on the seam between
## four cells and scrapes the body along block edges on the way through.
static func foot(c: Vector3i) -> Vector3:
	return Vector3(float(c.x) + 0.5, float(c.y), float(c.z) + 0.5)


## Cell whose XZ footprint contains `pos`, at the given level.
static func cell_of(pos: Vector3, level: int) -> Vector3i:
	return Vector3i(int(floor(pos.x)), level, int(floor(pos.z)))


# --- graph ------------------------------------------------------------------

## A body standing in c is supported and fits. Post: true implies c in bounds.
func _standable(c: Vector3i) -> bool:
	if not in_bounds(c):
		return false
	# y == 0 rests on the ground plane; anything higher needs a block under it.
	if c.y > 0 and not _blocks.has(c + Vector3i.DOWN):
		return false
	for i in _head:
		if _blocks.has(c + Vector3i(0, i, 0)):
			return false
	return true


## Every cell of `col` in [lo, hi] is free. Cells out of the block range count
## as free: nothing can be placed there.
func _clear_span(col: Vector2i, lo: int, hi: int) -> bool:
	for y in range(lo, hi + 1):
		if _blocks.has(Vector3i(col.x, y, col.y)):
			return false
	return true


## Every cell of `col` in [lo, hi] is solid. An empty span counts as solid.
func _solid_span(col: Vector2i, lo: int, hi: int) -> bool:
	for y in range(lo, hi + 1):
		if not _blocks.has(Vector3i(col.x, y, col.y)):
			return false
	return true


## Rebuilds nodes and edges from the block set. No-op when clean.
func rebuild() -> void:
	if not _dirty:
		return
	_dirty = false
	_astar.clear()
	_nodes.clear()
	_columns.clear()

	var next_id := 0
	for gx in range(-_half, _half):
		for gz in range(-_half, _half):
			var col := Vector2i(gx, gz)
			var levels := PackedInt32Array()
			if _col_blocks.has(col):
				for gy in range(0, _max_y + 1):
					if _standable(Vector3i(gx, gy, gz)):
						levels.append(gy)
			else:
				# Bare ground: one surface at y == 0 and nothing that could be
				# overhead. Most of the field, on most rebuilds.
				levels.append(0)
			if levels.is_empty():
				continue
			for gy in levels:
				var c := Vector3i(gx, gy, gz)
				_astar.add_point(next_id, foot(c))
				_nodes[c] = next_id
				next_id += 1
			_columns[col] = levels
	_connect()


func _connect() -> void:
	for col_key in _columns:
		var col: Vector2i = col_key
		var levels: PackedInt32Array = _columns[col]
		for level in levels:
			var here := Vector3i(col.x, level, col.y)
			# The eight neighbours at this level as one bitmask, built once. The
			# corner-cut rule and the gap-jump prune both ask the same question of
			# it, and asking it twice is what a rebuild cannot afford.
			var ring := 0
			for n in DIR_RING:
				if _nodes.has(Vector3i(here.x + n.x, level, here.z + n.y)):
					ring |= 1 << ((n.x + 1) * 3 + n.y + 1)
			for d in DIR_ORTHO:
				_connect_ortho(here, col + d)
			for d in DIR_DIAG:
				_connect_diag(here, d, ring)
			_connect_gaps(here, ring)

	# Connect recorded special paths
	for p in _special_paths:
		var from_c := _parse_coord(p.get("from"))
		var to_c := _parse_coord(p.get("to"))
		if _nodes.has(from_c) and _nodes.has(to_c):
			_astar.connect_points(_nodes[from_c], _nodes[to_c], false)


## Links `here` to every level of the neighbouring column the body could reach.
## Directed: the reverse leg is offered its own test when that node is walked.
func _connect_ortho(here: Vector3i, col: Vector2i) -> void:
	if not _columns.has(col):
		return
	var levels: PackedInt32Array = _columns[col]
	for level in levels:
		var there := Vector3i(col.x, level, col.y)
		var dh: int = level - here.y
		if dh > 0:
			if not _cap.can_rise(float(dh)):
				continue
			if not _clear_span(col, level, level + _head - 1):
				continue
		elif dh < 0:
			if not _cap.can_drop(float(-dh)):
				continue
			# The body enters the column at its current height and falls from
			# there, so the whole channel it passes through has to be open.
			if not _clear_span(col, level, here.y + _head - 1):
				continue
		_astar.connect_points(_nodes[here], _nodes[there], false)


## Links `here` to every level of the diagonally neighbouring column (d.x, d.y)
## that the body can reach (level walk/hop, climb/rise up to 2m, or drop).
func _connect_diag(here: Vector3i, d: Vector2i, _ring: int) -> void:
	var col := Vector2i(here.x + d.x, here.z + d.y)
	if not _columns.has(col):
		return
	var col_a := Vector2i(here.x + d.x, here.z)
	var col_b := Vector2i(here.x, here.z + d.y)

	var levels: PackedInt32Array = _columns[col]
	for level in levels:
		var there := Vector3i(col.x, level, col.y)
		var dh: int = level - here.y
		if dh == 0:
			# Diagonal level transition: allow unless pinched between two solid walls at here.y
			if _blocks.has(Vector3i(col_a.x, here.y, col_a.y)) and _blocks.has(Vector3i(col_b.x, here.y, col_b.y)):
				continue
			if not _clear_span(col, here.y, here.y + _head - 1):
				continue
		elif dh > 0:
			# Diagonal climb/rise: 1m or 2m ledge
			if not _cap.can_rise(float(dh)):
				continue
			if not _clear_span(col, level, level + _head - 1):
				continue
		elif dh < 0:
			# Diagonal drop:
			if not _cap.can_drop(float(-dh)):
				continue
			if not _clear_span(col, level, here.y + _head - 1):
				continue
		_astar.connect_points(_nodes[here], _nodes[there], false)


## Links `here` across a void to every platform a run-jump reaches, in any XZ
## direction - orthogonal, diagonal or neither.
##
## Distance is edge to edge, not centre to centre: the body takes off at its own
## rim and has to put a whole footprint down past the far one, so what the arc
## has to cover is the void itself. See cell_gap().
##
## Pre: `ring` is `here`'s neighbour mask, as built by _connect().
func _connect_gaps(here: Vector3i, ring: int) -> void:
	# Two prunes, both out of the mask. A cell that can be walked out of in all
	# eight directions has no void beside it to jump; and a target whose first
	# step is walkable is better jumped at from that step - same direction,
	# shorter void, so nothing becomes unreachable by refusing it here.
	if ring == RING_FULL or not _cap.jump_enabled:
		return
	# Reach is measured for a level jump. A drop can carry further, but a leap
	# that long is a fall with extra steps, and capping the search is what keeps a
	# rebuild inside a frame.
	var span := maxi(2, int(floor(_cap.gap_jump_budget(0.0))) + 1)
	var from_id: int = _nodes[here]
	for dx in range(-span, span + 1):
		var tx: int = here.x + dx
		if tx < -_half or tx >= _half:
			continue
		var row: int = (signi(dx) + 1) * 3 + 1
		for dz in range(-span, span + 1):
			# The ring of cells reachable by walking belongs to _connect_ortho and
			# _connect_diag; only genuine voids are jumped.
			if absi(dx) <= 1 and absi(dz) <= 1:
				continue
			if ring & (1 << (row + signi(dz))) != 0:
				continue
			var col := Vector2i(tx, here.z + dz)
			if not _columns.has(col):
				continue
			var levels: PackedInt32Array = _columns[col]
			for level in levels:
				var there := Vector3i(col.x, level, col.y)
				if not _cap.can_gap_jump(cell_gap(here, there), float(level - here.y)):
					continue
				if not _gap_clear(here, there):
					continue
				_astar.connect_points(from_id, _nodes[there], false)


## Edge-to-edge XZ distance between two unit cells: the point of `a` nearest `b`
## to the point of `b` nearest `a`. 0 when they touch or share a column.
## Post: >= 0. Orthogonal k cells apart gives k - 1; diagonal (k, k) gives
## (k - 1) * sqrt(2).
static func cell_gap(a: Vector3i, b: Vector3i) -> float:
	return Vector2(maxf(float(absi(b.x - a.x)) - 1.0, 0.0),
		maxf(float(absi(b.z - a.z)) - 1.0, 0.0)).length()


## The channel the arc flies through is open, and there is a real void under it.
##
## Samples the straight XZ line between the two cell centres, and at every sample
## the four corners of the body's own footprint as well - a diagonal line leaves
## its cell through a corner, and a centre-line test walks the body's shoulder
## straight through whatever stands on the other side of it. Each column found
## has to be clear from the lower of the two levels up through the body at its
## apex.
##
## At least one column on the centre line has to be unstandable at `here`'s level
## too: two platforms joined by ground are walked between, and an edge saying
## otherwise only gives A* a more expensive way to do the same thing.
func _gap_clear(here: Vector3i, there: Vector3i) -> bool:
	var from := Vector2(float(here.x) + 0.5, float(here.z) + 0.5)
	var to := Vector2(float(there.x) + 0.5, float(there.z) + 0.5)
	var span := to - from
	var samples := int(ceil(span.length() / LINE_STEP))
	if samples < 1:
		return false
	var step := span / float(samples)
	var lo: int = mini(here.y, there.y)
	var hi: int = here.y + int(floor(_cap.jump_apex())) + _head - 1
	var r: float = _cap.radius
	# Reused rather than allocated: this runs for every candidate arc of every
	# rim cell of every rebuild.
	_span_seen.clear()
	var void_seen := false
	for i in range(1, samples):
		var p := from + step * float(i)
		if not _nodes.has(Vector3i(int(floor(p.x)), here.y, int(floor(p.y)))):
			void_seen = true
		for ox in [-r, r]:
			for oz in [-r, r]:
				var col := Vector2i(int(floor(p.x + ox)), int(floor(p.y + oz)))
				# The two ends are the ground the body leaves and lands on; testing
				# them as if they were void is what would refuse every drop jump.
				if col.x == here.x and col.y == here.z:
					continue
				if col.x == there.x and col.y == there.z:
					continue
				if _span_seen.has(col):
					continue
				_span_seen[col] = true
				if not _clear_span(col, lo, hi):
					return false
	return void_seen


## The standable cell under or touched by feet at `pos`: selects closest standable cell.
## Falls back to the nearest node in the whole graph when radius scan is empty.
## Returns NO_CELL only when the graph is empty.
func standing_node(pos: Vector3) -> Vector3i:
	rebuild()
	if _nodes.is_empty():
		return NO_CELL

	var r: float = _cap.radius + 0.25
	var min_gx := int(floor(pos.x - r))
	var max_gx := int(floor(pos.x + r))
	var min_gz := int(floor(pos.z - r))
	var max_gz := int(floor(pos.z + r))

	var best := NO_CELL
	var best_dist_sq := INF

	var best_supported := NO_CELL
	var best_supported_horiz_sq := INF

	for gx in range(min_gx, max_gx + 1):
		for gz in range(min_gz, max_gz + 1):
			var col := Vector2i(gx, gz)
			if not _columns.has(col):
				continue
			var levels: PackedInt32Array = _columns[col]
			for level in levels:
				var c := Vector3i(gx, level, gz)
				if not _nodes.has(c):
					continue
				var f_pos := foot(c)
				var dy := pos.y - f_pos.y
				if dy >= -0.35 and dy <= 0.65:
					var h_sq := (pos.x - f_pos.x) * (pos.x - f_pos.x) + (pos.z - f_pos.z) * (pos.z - f_pos.z)
					if h_sq < best_supported_horiz_sq:
						best_supported_horiz_sq = h_sq
						best_supported = c

				var d_sq := pos.distance_squared_to(f_pos)
				if d_sq < best_dist_sq:
					best_dist_sq = d_sq
					best = c

	if best_supported != NO_CELL:
		return best_supported

	if best != NO_CELL:
		return best

	var id := _astar.get_closest_point(pos)
	if id < 0:
		return NO_CELL
	var p := _astar.get_point_position(id)
	return Vector3i(int(floor(p.x)), int(round(p.y)), int(floor(p.z)))


## Returns true if cell_a and cell_b are on the same level platform connected
## strictly by continuous flat walkable steps (Move.WALK, dh == 0, adjacent),
## without requiring any jumping, dropping, climbing, or gap crosses.
func is_same_flat_platform(cell_a: Vector3i, cell_b: Vector3i) -> bool:
	if cell_a == NO_CELL or cell_b == NO_CELL:
		return false
	if cell_a == cell_b:
		return true
	if cell_a.y != cell_b.y:
		return false

	rebuild()
	if not _nodes.has(cell_a) or not _nodes.has(cell_b):
		return false

	var target_y := cell_a.y
	var visited: Dictionary = {}
	var queue: Array[Vector3i] = [cell_a]
	visited[cell_a] = true

	while not queue.is_empty():
		var curr: Vector3i = queue.pop_front()
		if curr == cell_b:
			return true

		for d in DIR_ORTHO:
			var nxt := Vector3i(curr.x + d.x, target_y, curr.z + d.y)
			if not visited.has(nxt) and _nodes.has(nxt):
				visited[nxt] = true
				queue.push_back(nxt)

		for d in DIR_DIAG:
			var nxt := Vector3i(curr.x + d.x, target_y, curr.z + d.y)
			if not visited.has(nxt) and _nodes.has(nxt):
				var c1 := Vector3i(curr.x + d.x, target_y, curr.z)
				var c2 := Vector3i(curr.x, target_y, curr.z + d.y)
				if _nodes.has(c1) and _nodes.has(c2):
					visited[nxt] = true
					queue.push_back(nxt)

	return false


# --- search -----------------------------------------------------------------

## Path from `from_pos` to `to_pos`.
##
## Returns {points, moves, complete, goal, reachable}:
## - points[i]: waypoint in world space, feet height
## - moves[i]: how points[i] is reached from points[i-1]; moves[0] is WALK
## - complete: the goal cell itself was reached
## - reachable: the cell the path actually ends on, NO_CELL when there is none
##
## When the goal is out of the body's reach the path runs to the reachable cell
## nearest it instead, with complete == false.
func find_path(from_pos: Vector3, to_pos: Vector3) -> Dictionary:
	rebuild()
	var out := {
		"points": PackedVector3Array(),
		"moves": PackedInt32Array(),
		"complete": false,
		"goal": to_pos,
		"reachable": NO_CELL,
	}
	var start := standing_node(from_pos)
	var goal := standing_node(to_pos)
	if start == NO_CELL or goal == NO_CELL:
		return out

	var start_id: int = _nodes[start]
	var goal_id: int = _nodes[goal]
	var ids := _astar.get_id_path(start_id, goal_id)
	var complete := not ids.is_empty()
	if not complete:
		var fallback := _closest_reachable(start_id, foot(goal))
		ids = _astar.get_id_path(start_id, fallback)
		if ids.is_empty():
			return out

	var cells: Array[Vector3i] = []
	for id in ids:
		var p := _astar.get_point_position(id)
		cells.append(Vector3i(int(floor(p.x)), int(round(p.y)), int(floor(p.z))))

	# Classified on the raw chain, before string pulling. Once a straight run has
	# been collapsed into a single leg that leg spans many cells and says nothing
	# about how it is crossed - reading "skips a column" off it would call every
	# long walk a jump. A gap jump is never collapsed (the void in the middle is
	# not walkable), so its leg keeps its own answer.
	var raw := PackedInt32Array()
	raw.resize(cells.size())
	raw[0] = Move.WALK
	for i in range(1, cells.size()):
		raw[i] = _classify(cells[i - 1], cells[i])

	var points := PackedVector3Array()
	var moves := PackedInt32Array()
	var special_links := {}
	var simplified_indices := _simplify(cells, raw)
	for k_idx in range(simplified_indices.size()):
		var k: int = simplified_indices[k_idx]
		points.append(foot(cells[k]))
		moves.append(raw[k])
		if raw[k] == Move.SPECIAL_JUMP and k > 0:
			var sp_data := get_special_path_between(cells[k - 1], cells[k])
			if not sp_data.is_empty():
				special_links[k_idx] = sp_data

	# The exact target only replaces the last waypoint when it lies inside that
	# waypoint's own cell. Snapping to a goal outside it - a point on a wall
	# face, an unreachable cell - is what walks the body into geometry.
	var last := cells[cells.size() - 1]
	if complete and Vector2i(int(floor(to_pos.x)), int(floor(to_pos.z))) == Vector2i(last.x, last.z):
		points[points.size() - 1] = Vector3(to_pos.x, float(last.y), to_pos.z)

	out.points = points
	out.moves = moves
	out.special_links = special_links
	out.complete = complete
	out.reachable = last
	return out


## How the leg from `from_cell` to `to_cell` is travelled.
##
## A leg that skips a column is a gap jump whatever its height difference: those
## edges only exist because _connect_gaps() found an arc for them, and the
## executor has to know it is flying rather than walking off a ledge.
func _classify(from_cell: Vector3i, to_cell: Vector3i) -> int:
	if not get_special_path_between(from_cell, to_cell).is_empty():
		return Move.SPECIAL_JUMP
	if absi(to_cell.x - from_cell.x) > 1 or absi(to_cell.z - from_cell.z) > 1:
		return Move.JUMP
	var dh := float(to_cell.y - from_cell.y)
	if dh > 0.01:
		return _cap.rise_move(dh)
	if dh < -0.01:
		return Move.DROP
	return Move.WALK


## Node of the component containing `start_id` that sits nearest `goal_pos`.
## Post: a valid id; `start_id` itself when nothing is closer.
func _closest_reachable(start_id: int, goal_pos: Vector3) -> int:
	var seen := {start_id: true}
	var queue: Array[int] = [start_id]
	var best := start_id
	var best_d := _astar.get_point_position(start_id).distance_squared_to(goal_pos)
	var head := 0
	while head < queue.size():
		var id: int = queue[head]
		head += 1
		for n in _astar.get_point_connections(id):
			if seen.has(n):
				continue
			seen[n] = true
			queue.append(n)
			var d := _astar.get_point_position(n).distance_squared_to(goal_pos)
			if d < best_d:
				best_d = d
				best = n
	return best


## Indices of the waypoints a straight run cannot absorb. Grid paths staircase
## around diagonals; every retained corner is one more chance to graze a block
## edge. Pre: cells non-empty. Post: the first and last indices survive.
func _simplify(cells: Array[Vector3i], raw_moves := PackedInt32Array()) -> PackedInt32Array:
	var kept := PackedInt32Array([0])
	if cells.size() <= 2:
		if cells.size() == 2:
			kept.append(1)
		return kept
	var anchor := 0
	for i in range(1, cells.size() - 1):
		var is_special := false
		if raw_moves.size() > i + 1:
			if raw_moves[i] == Move.SPECIAL_JUMP or raw_moves[i + 1] == Move.SPECIAL_JUMP:
				is_special = true
		var flat: bool = cells[anchor].y == cells[i].y and cells[i].y == cells[i + 1].y
		if not is_special and flat and _line_walkable(cells[anchor], cells[i + 1]):
			continue
		kept.append(i)
		anchor = i
	kept.append(cells.size() - 1)
	return kept

## A body of the capability's radius can walk the straight line a -> b without
## leaving standable cells. Pre: a.y == b.y.
func _line_walkable(a: Vector3i, b: Vector3i) -> bool:
	var from := foot(a)
	var to := foot(b)
	var span := Vector2(to.x - from.x, to.z - from.z)
	var length := span.length()
	if length < 0.001:
		return true
	var step := span / length * LINE_STEP
	var r: float = _cap.radius
	var samples := int(ceil(length / LINE_STEP))
	var at := Vector2(from.x, from.z)
	for i in range(samples + 1):
		var p: Vector2 = at if i < samples else Vector2(to.x, to.z)
		# The four corners of the body's footprint, so a radius that overhangs
		# into the next cell is tested against that cell too.
		for ox in [-r, r]:
			for oz in [-r, r]:
				var c := Vector3i(int(floor(p.x + ox)), a.y, int(floor(p.y + oz)))
				if not _nodes.has(c):
					return false
		at += step
	return true


## Checks if remaining waypoints from start_index are still traversable.
##
## A leg is either a straight run the string pulling collapsed into one, or a
## single graph edge - a climb, a drop, a gap jump. Either one satisfies it: a
## gap jump is not line-walkable by construction (the void in the middle is not
## standable), so testing only the line would call every plan with a jump in it
## invalid and repath on every frame.
func is_path_valid(points: PackedVector3Array, start_index := 0) -> bool:
	rebuild()
	if points.size() < 2 or start_index >= points.size() - 1:
		return true
	var idx := maxi(0, start_index)
	for i in range(idx, points.size() - 1):
		var p1 := points[i]
		var p2 := points[i + 1]
		var c1 := Vector3i(int(floor(p1.x)), int(round(p1.y)), int(floor(p1.z)))
		var c2 := Vector3i(int(floor(p2.x)), int(round(p2.y)), int(floor(p2.z)))
		if not _nodes.has(c1) or not _nodes.has(c2):
			return false
		if not get_special_path_between(c1, c2).is_empty() and _astar.are_points_connected(_nodes[c1], _nodes[c2], false):
			continue
		if c1.y == c2.y and _line_walkable(c1, c2):
			continue
		if not _astar.are_points_connected(_nodes[c1], _nodes[c2], false):
			return false
	return true

