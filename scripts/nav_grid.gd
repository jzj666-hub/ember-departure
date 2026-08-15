class_name NavGrid
extends RefCounted
## Voxel navigation grid + capability-derived A* for CharacterBody3D agents.

## Emitted when block layout changes.
signal grid_changed()
##
## Cell c occupies the world box [c, c+1) on every axis. An agent standing in c
## has its feet at foot(c) = Vector3(c.x + 0.5, c.y, c.z + 0.5) - cell centre in
## XZ, cell floor in Y.
##
## Invariants:
## - every AStar point is a standable cell; point ids are dense from 0
## - _nodes, _columns and _astar are rebuilt together and never partially updated
## - all edges are directed: rise and drop rules are not symmetric

## How a leg of a path is travelled. BUILD is reserved for the block-placing bot.
enum Move { WALK, CLIMB, JUMP, DROP, BUILD }

const NO_CELL := Vector3i(-32768, -32768, -32768)
## Clearance a jump must keep under its own apex before a ledge counts as
## jumpable, metres. The apex is reached for one instant only.
const JUMP_CLEAR := 0.22
## Clearance the feet must keep over the far lip of a gap jump, metres. Far
## smaller than JUMP_CLEAR: a gap jump crosses the lip in mid-arc, not at the
## apex, so what it needs is that the feet are over the lip at all.
const LIP_CLEAR := 0.08
## Deepest a gap jump may end below its take-off, metres. A longer leap down is a
## fall with a run-up: walking off the rim and the drop edges under it already
## get the body there, and offering the arc as well only makes the graph dense -
## a plateau's whole rim would gain an edge to every cell of ground around it.
const MAX_GAP_DROP := 2.0
## Sample step of the string-pulling straight-line test, metres.
const LINE_STEP := 0.2
## Fall a drop edge may cost at most, metres. No fall damage exists; the ceiling
## is what looks deliberate rather than what survives.
const MAX_DROP := 5.0

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


## Motion limits read off a PlayerController. Lengths metres, times seconds.
## Every threshold the graph uses comes from here - no literals in the edge rules.
class Capability extends RefCounted:
	var gravity := 9.8
	var walk_speed := 1.1
	var run_speed := 3.6
	var jump_enabled := true
	var jump_speed := 4.7
	var climb_enabled := true
	var climb_min := 0.5
	var climb_max := 2.2
	var climb_duration := 1.5
	var climb_clearance := 0.9
	var stand_height := 1.75
	var radius := 0.3
	var max_drop := MAX_DROP
	var land_roll_drop_min := 1.8
	var land_roll_recover := 0.95
	var jump_land_recover := 0.28
	## Physics step the body is integrated with, seconds. The arc is quantised to
	## it and so is how late a take-off trigger can fire.
	var tick := 1.0 / 60.0
	var coyote_time := 0.12

	## Launch speed the arc solves for.
	##
	## PlayerController applies no gravity on the frame a jump starts (the body is
	## still on the floor) and semi-implicit Euler applies it a step late
	## thereafter, so the discrete path is exactly y(t) = u'*t - g*t*t/2 with
	## u' = jump_speed + g*tick/2 - half a step higher than the continuous
	## solution. Post: >= jump_speed.
	func _launch() -> float:
		return jump_speed + gravity * tick * 0.5

	## Peak rise of a standing jump. Post: >= 0.
	func jump_apex() -> float:
		if not jump_enabled:
			return 0.0
		var u := _launch()
		return (u * u) / (2.0 * maxf(gravity, 0.01))

	## Seconds aloft until the feet are `dh` above take-off on the way down: the
	## descending root of the arc. NAN when the arc never reaches dh.
	func flight_time(dh: float) -> float:
		var u := _launch()
		var disc: float = u * u - 2.0 * gravity * dh
		if disc < 0.0:
			return NAN
		return (u + sqrt(disc)) / maxf(gravity, 0.01)

	## Seconds until the feet first clear `dh`: the ascending root. 0 for a lip at
	## or below take-off. NAN when the arc never reaches dh.
	func clear_time(dh: float) -> float:
		if dh <= 0.0:
			return 0.0
		var u := _launch()
		var disc: float = u * u - 2.0 * gravity * dh
		if disc < 0.0:
			return NAN
		return (u - sqrt(disc)) / maxf(gravity, 0.01)

	## Horizontal metres the arc covers at ground speed `v`.
	##
	## Exact only while nothing steers in the air: _drive_air() lerps the velocity
	## towards a vector of the same magnitude in the heading's direction, and a
	## chord between two vectors of equal length is shorter than either, so any
	## misaligned air steering bleeds speed every frame. See NPCIntentSource's
	## AIRBORNE phase, which asks for no movement at all for exactly this reason.
	func jump_reach(dh: float, v: float) -> float:
		if not jump_enabled:
			return 0.0
		var t := flight_time(dh)
		return 0.0 if is_nan(t) else v * t

	## Widest void, edge to edge, a full-pace run-jump may cross for a rise of dh.
	## Accounts for rim-edge takeoff (+radius) and coyote time (body runs past
	## the rim before jumping, gaining coy_d horizontal and losing coy_fall height).
	func gap_jump_budget(dh: float) -> float:
		if not jump_enabled:
			return 0.0
		var coy_d: float = run_speed * coyote_time
		var coy_fall: float = 0.5 * gravity * coyote_time * coyote_time
		var t: float = flight_time(dh + coy_fall)
		if is_nan(t) or t <= 0.0:
			return maxf(jump_reach(dh, run_speed) + radius * 2.0 - run_speed * tick, 0.0)
		return maxf(run_speed * t + radius * 2.0 + coy_d - run_speed * tick, 0.0)

	## A void of `gap` metres, edge to edge, is crossable for a rise of dh.
	##
	## Two conditions, one per root of the arc: the descending root has to land a
	## footprint past the far lip, and the ascending root has to have cleared that
	## lip by the time the body is over it - a void too NARROW for a rise is one
	## the body clips its shins on.
	func can_gap_jump(gap: float, dh: float) -> bool:
		if not jump_enabled or dh < -MAX_GAP_DROP or gap > gap_jump_budget(dh):
			return false
		var lip := clear_time(dh + LIP_CLEAR)
		return not is_nan(lip) and gap >= run_speed * lip

	## Max horizontal run-jump distance (metres) for target height diff dh.
	func max_jump_distance(dh: float) -> float:
		if not jump_enabled:
			return 0.0
		if dh > jump_apex() - JUMP_CLEAR:
			return 0.0
		return jump_reach(dh, run_speed)

	## Rise of dh metres is jumpable (apex minus clearance) or climbable.
	func can_rise(dh: float) -> bool:
		if dh <= 0.0:
			return true
		if jump_enabled and dh <= jump_apex() - JUMP_CLEAR:
			return true
		return climb_enabled and dh >= climb_min and dh <= climb_max

	## Which take a rise of dh resolves to. Pre: can_rise(dh).
	func rise_move(dh: float) -> Move:
		if jump_enabled and dh <= jump_apex() - JUMP_CLEAR:
			return Move.JUMP
		return Move.CLIMB

	## Seconds a rise of dh costs. Pre: can_rise(dh).
	func rise_time(dh: float) -> float:
		if dh <= 0.0:
			return 0.0
		if rise_move(dh) == Move.JUMP:
			var t := flight_time(dh)
			return flight_time(0.0) if is_nan(t) else t
		return climb_duration

	## Drop of dh metres is survivable within the deliberate-looking ceiling.
	## Pre: dh >= 0.
	func can_drop(dh: float) -> bool:
		return dh <= max_drop

	## Seconds a drop of dh costs: the fall plus the landing recovery it arms.
	## Pre: dh >= 0.
	func drop_time(dh: float) -> float:
		var fall: float = sqrt(2.0 * maxf(dh, 0.0) / maxf(gravity, 0.01))
		var recover := jump_land_recover
		if dh >= land_roll_drop_min:
			recover = land_roll_recover
		return fall + recover

	## Cells of headroom a standing body needs, counted from its own cell up.
	## Post: >= 1.
	func head_cells() -> int:
		return maxi(1, int(ceil(stand_height - 0.001)))


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


var _cap := Capability.new()
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

var _half := 20
var _max_y := 8
var _head := 2
var _dirty := true


# --- configuration ----------------------------------------------------------

## Playable cell range: x,z in [-half, half), y in [0, max_y]. Marks dirty.
func set_bounds(half: int, max_y: int) -> void:
	_half = maxi(1, half)
	_max_y = maxi(0, max_y)
	_dirty = true


## Derives the whole edge rule set from a PlayerController's exported limits.
## Pre: body has run through setup() so _stand_height is real. Marks dirty.
func set_capability(body: Node) -> void:
	var cap := Capability.new()
	cap.gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	cap.tick = 1.0 / maxf(float(Engine.physics_ticks_per_second), 1.0)
	if body != null:
		cap.walk_speed = _num(body, "walk_speed", cap.walk_speed)
		cap.run_speed = _num(body, "run_speed", cap.run_speed)
		cap.jump_enabled = _flag(body, "jump_enabled", cap.jump_enabled)
		cap.jump_speed = _num(body, "jump_speed", cap.jump_speed)
		cap.climb_enabled = _flag(body, "climb_enabled", cap.climb_enabled)
		cap.climb_min = _num(body, "climb_min_height", cap.climb_min)
		cap.climb_max = _num(body, "climb_max_height", cap.climb_max)
		cap.climb_duration = _num(body, "climb_duration", cap.climb_duration)
		cap.climb_clearance = _num(body, "climb_clearance", cap.climb_clearance)
		cap.stand_height = _num(body, "_stand_height", cap.stand_height)
		cap.land_roll_drop_min = _num(body, "land_roll_drop_min", cap.land_roll_drop_min)
		cap.land_roll_recover = _num(body, "land_roll_recover", cap.land_roll_recover)
		cap.jump_land_recover = _num(body, "jump_land_recover", cap.jump_land_recover)
		cap.radius = body_radius(body, cap.radius)
		cap.coyote_time = _num(body, "coyote_time", cap.coyote_time)
	set_capability_direct(cap)


## Installs an already-built capability. What the headless probe uses.
func set_capability_direct(cap: Capability) -> void:
	_cap = cap
	_astar.cap = cap
	_head = cap.head_cells()
	_dirty = true


func capability() -> Capability:
	return _cap


static func _num(body: Node, prop: String, fallback: float) -> float:
	var v: Variant = body.get(prop)
	return float(v) if v != null else fallback


static func _flag(body: Node, prop: String, fallback: bool) -> bool:
	var v: Variant = body.get(prop)
	return bool(v) if v != null else fallback


## Radius of the body's first capsule collider, or `fallback` when it has none.
static func body_radius(body: Node, fallback: float) -> float:
	for child in body.get_children():
		var shape := child as CollisionShape3D
		if shape == null:
			continue
		var capsule := shape.shape as CapsuleShape3D
		if capsule != null:
			return capsule.radius
	return fallback


# --- world state ------------------------------------------------------------

## Adds or clears a solid cell. Marks dirty; does not rebuild. Emits grid_changed.
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
	grid_changed.emit()


func clear_blocks() -> void:
	if _blocks.is_empty():
		return
	_blocks.clear()
	_col_blocks.clear()
	_dirty = true
	grid_changed.emit()


func is_solid(coord: Vector3i) -> bool:
	return _blocks.has(coord)


## Cell is a node of the graph: a body standing there is supported and fits.
## What the executor asks to find the rim it takes off from - block solidity
## answers the wrong question at y == 0, where the floor is the world plane and
## no block exists under it.
func is_standable(coord: Vector3i) -> bool:
	rebuild()
	return _nodes.has(coord)


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
			# Climbable only against a face the ledge probe can actually hit:
			# _find_ledge() casts forward from chest height, so the neighbouring
			# column has to be solid from the feet up to just under the landing.
			if not _cap.can_rise(float(dh)):
				continue
			if not _solid_span(col, here.y, level - 1):
				continue
		elif dh < 0:
			if not _cap.can_drop(float(-dh)):
				continue
			# The body enters the column at its current height and falls from
			# there, so the whole channel it passes through has to be open.
			if not _clear_span(col, level, here.y + _head - 1):
				continue
		_astar.connect_points(_nodes[here], _nodes[there], false)


## Diagonals are level-only and may not cut a corner. A climb squares up to its
## wall before it runs (see PlayerController._try_climb), so a diagonal one puts
## a shoulder through the block. Pre: `ring` is `here`'s neighbour mask.
func _connect_diag(here: Vector3i, d: Vector2i, ring: int) -> void:
	if ring & (1 << ((d.x + 1) * 3 + d.y + 1)) == 0:
		return
	if ring & (1 << ((d.x + 1) * 3 + 1)) == 0:
		return
	if ring & (1 << (3 + d.y + 1)) == 0:
		return
	_astar.connect_points(_nodes[here],
		_nodes[Vector3i(here.x + d.x, here.y, here.z + d.y)], false)


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

	var r: float = _cap.radius + 0.15
	var min_gx := int(floor(pos.x - r))
	var max_gx := int(floor(pos.x + r))
	var min_gz := int(floor(pos.z - r))
	var max_gz := int(floor(pos.z + r))

	var best := NO_CELL
	var best_dist_sq := INF

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
				var d_sq := pos.distance_squared_to(f_pos)
				if d_sq < best_dist_sq:
					best_dist_sq = d_sq
					best = c

	if best != NO_CELL:
		return best

	var id := _astar.get_closest_point(pos)
	if id < 0:
		return NO_CELL
	var p := _astar.get_point_position(id)
	return Vector3i(int(floor(p.x)), int(round(p.y)), int(floor(p.z)))


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
	for k in _simplify(cells):
		points.append(foot(cells[k]))
		moves.append(raw[k])

	# The exact target only replaces the last waypoint when it lies inside that
	# waypoint's own cell. Snapping to a goal outside it - a point on a wall
	# face, an unreachable cell - is what walks the body into geometry.
	var last := cells[cells.size() - 1]
	if complete and Vector2i(int(floor(to_pos.x)), int(floor(to_pos.z))) == Vector2i(last.x, last.z):
		points[points.size() - 1] = Vector3(to_pos.x, float(last.y), to_pos.z)

	out.points = points
	out.moves = moves
	out.complete = complete
	out.reachable = last
	return out


## How the leg from `from_cell` to `to_cell` is travelled.
##
## A leg that skips a column is a gap jump whatever its height difference: those
## edges only exist because _connect_gaps() found an arc for them, and the
## executor has to know it is flying rather than walking off a ledge.
func _classify(from_cell: Vector3i, to_cell: Vector3i) -> int:
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
func _simplify(cells: Array[Vector3i]) -> PackedInt32Array:
	var kept := PackedInt32Array([0])
	if cells.size() <= 2:
		if cells.size() == 2:
			kept.append(1)
		return kept
	var anchor := 0
	for i in range(1, cells.size() - 1):
		var flat: bool = cells[anchor].y == cells[i].y and cells[i].y == cells[i + 1].y
		if flat and _line_walkable(cells[anchor], cells[i + 1]):
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
		if c1.y == c2.y and _line_walkable(c1, c2):
			continue
		if not _astar.are_points_connected(_nodes[c1], _nodes[c2], false):
			return false
	return true

