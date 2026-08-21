class_name NavProvider
extends RefCounted
## Base class for navigation backends: voxel grid, navmesh, etc.
## NPCIntentSource talks only to this type - never to a concrete backend.
##
## Contract:
## - find_path() returns world-space points plus a per-leg Move classification
## - every other method answers about the map the body currently stands on
## - Capability is body-derived, not map-derived, and lives here for every backend

## Emitted when the map layout changes and planned paths may be stale.
signal changed()

## How a leg of a path is travelled. BUILD is reserved for the block-placing bot.
enum Move { WALK, CLIMB, JUMP, DROP, BUILD, SPECIAL_JUMP }

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
## Fall a drop edge may cost at most, metres. No fall damage exists; the ceiling
## is what looks deliberate rather than what survives.
const MAX_DROP := 5.0
## stand_foot() answers this when nothing standable holds the query point.
const NO_POINT := Vector3(INF, INF, INF)


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
	func can_gap_jump(gap: float, dh: float) -> bool:
		if not jump_enabled or dh < -MAX_GAP_DROP or gap > gap_jump_budget(dh):
			return false
		if dh <= 0.0:
			return true
		var lip := clear_time(dh + LIP_CLEAR)
		return not is_nan(lip)

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


var _cap := Capability.new()


# --- capability -------------------------------------------------------------

## Derives the whole edge rule set from a PlayerController's exported limits.
## Pre: body has run through setup() so _stand_height is real.
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
## Backends override to refresh whatever they derive from it.
func set_capability_direct(cap: Capability) -> void:
	_cap = cap


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


# --- contract ---------------------------------------------------------------

## Plans a route. Post: `points` are world space; `moves` is parallel to it and
## says how each leg is travelled; `complete` false means the goal was not
## reached and the route stops at the closest thing that was.
## Backends may add their own keys - consumers must not require them.
func find_path(_from_pos: Vector3, _to_pos: Vector3) -> Dictionary:
	return {
		"points": PackedVector3Array(),
		"moves": PackedInt32Array(),
		"special_links": {},
		"complete": false,
		"goal": _to_pos,
	}


## An already-planned route still holds on the current map, from `start_index` on.
func is_path_valid(_points: PackedVector3Array, _start_index := 0) -> bool:
	return true


## Foot point of the standable spot holding `pos`, the backend's own height
## included. Post: NO_POINT when nothing standable holds it.
func stand_foot(_pos: Vector3) -> Vector3:
	return NO_POINT


## Where a body at `pos` should centre itself to stand cleanly.
## Post: y is pos.y unchanged - this answers about XZ only.
func stand_center(pos: Vector3) -> Vector3:
	return Vector3(floor(pos.x) + 0.5, pos.y, floor(pos.z) + 0.5)


## There is ground to stand on at `point`.
func is_standable_at(_point: Vector3) -> bool:
	return true
