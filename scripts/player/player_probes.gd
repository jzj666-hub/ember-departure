class_name PlayerProbes
extends RefCounted
## Everything PlayerController asks the world before it commits to a move:
## ledges, kerbs, and where a fall is going to land.
##
## Owned by PlayerController. Reads its exports and transform, writes nothing
## except the one position change try_step_up() exists for. `_body` is untyped on
## purpose: typing it PlayerController would make the two classes cyclic.
## Pre: setup() before any other call.

## What find_ledge() answers with when there is nothing to climb, which is what
## makes the same request an ordinary jump.
const NO_LEDGE := Vector3.INF
## How far above the highest reachable ledge that probe starts its cast down, in
## metres. Only has to clear the ledge, not the character.
const LEDGE_PROBE_RISE := 0.25

## Physics ticks per sample of the landing prediction's arc march. Coarser than
## the step the body is integrated at - every sample costs a raycast - but the
## segment it spans is well under a cube, so nothing can be tunnelled through.
const PREDICT_TICKS := 3
## Cap on those samples, so an arc that never meets anything cannot walk the
## probe forever. At 3 ticks each this covers 4.5 s of flight.
const PREDICT_SAMPLES := 90

var _body
## Reused by the ledge probe's clearance test, so a check that runs on every
## press of Space does not allocate a shape each time.
var _clearance: CapsuleShape3D


func setup(body) -> void:
	_body = body
	if _clearance == null:
		_clearance = CapsuleShape3D.new()


# --- the ledge ---------------------------------------------------------------

## Probes area in front of character to find a climbable ledge. Returns target
## foot position or NO_LEDGE.
func find_ledge() -> Vector3:
	var space: PhysicsDirectSpaceState3D = _body.get_world_3d().direct_space_state
	var reach: float = capsule_radius() + _body.climb_reach
	var wish: Vector3 = _body._wish_direction()
	var origin: Vector3 = _body.global_position

	var facing: Vector3 = _body.global_basis.z
	var dirs: Array[Vector3] = [facing]
	if wish.length_squared() > 0.01 and wish.dot(facing) < 0.99:
		dirs.append(wish)

	for forward in dirs:
		var ahead := origin + forward * reach
		var hit := cast(space,
			Vector3(ahead.x, origin.y + _body.climb_max_height + LEDGE_PROBE_RISE, ahead.z),
			Vector3(ahead.x, origin.y + _body.climb_min_height, ahead.z))
		if hit.is_empty():
			continue
		if (hit.normal as Vector3).y < _body.climb_floor_dot:
			continue
		var stand: Vector3 = hit.position
		if fits(stand):
			return stand

	return NO_LEDGE


## Whether this character, standing, would fit with its feet at `foot`.
##
## A shape query rather than a handful of rays: what makes a ledge unclimbable is
## usually a low ceiling over it or a second wall just past it, and both are easy
## for three rays to thread.
func fits(foot: Vector3) -> bool:
	var radius: float = maxf(capsule_radius() * _body.climb_clearance, 0.05)
	_clearance.radius = radius
	_clearance.height = maxf(_body._stand_height * _body.climb_clearance, radius * 2.0 + 0.01)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _clearance
	query.collide_with_areas = false
	query.exclude = [_body.get_rid()]
	query.transform = Transform3D(Basis.IDENTITY,
		foot + Vector3.UP * (_clearance.height * 0.5 + 0.02))
	return _body.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func cast(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_body.get_rid()]
	return space.intersect_ray(query)


func capsule_radius() -> float:
	var capsule: CollisionShape3D = _body._capsule
	if capsule == null:
		return 0.3
	var shape := capsule.shape as CapsuleShape3D
	return shape.radius if shape != null else 0.3


# --- the kerb ----------------------------------------------------------------

## Lifts the body onto a kerb the slide just stopped against. See
## PlayerController.step_up_enabled for why this case exists at all.
##
## Probe is the standard three: rise, move in, come back down. Each leg must be
## clear or the kerb is really a wall. Pre: called straight after
## move_and_slide(), before the ground state is settled, and only in a state that
## walks - the caller owns that gate.
## Post: position on top of the step, or untouched. Velocity is never modified -
## the body keeps the pace it was already walking at.
func try_step_up() -> void:
	if not _body.step_up_enabled or _body.step_max_height <= 0.0:
		return
	if not _body.is_on_floor() or not _body.is_on_wall():
		return

	# The direction asked for, not the one left over. move_and_slide() has already
	# zeroed the velocity against the very kerb this is trying to get over, so
	# reading velocity here says "not going anywhere" exactly when it matters.
	# Same input find_ledge() probes along, for the same reason.
	if _body._intent.move == Vector2.ZERO:
		return

	var rise: Vector3 = Vector3.UP * _body.step_max_height
	var forward: Vector3 = _body._wish_direction() * (capsule_radius() + _body.step_probe_ahead)
	var from: Transform3D = _body.global_transform

	# Headroom to rise into, then room to move in over the kerb once lifted.
	if _body.test_move(from, rise):
		return
	var lifted := from.translated(rise)
	if _body.test_move(lifted, forward):
		return

	# Something to come back down onto. No hit at all means the body was about to
	# be dropped into a gap, which is a fall, not a step.
	var over := lifted.translated(forward)
	var landing := KinematicCollision3D.new()
	if not _body.test_move(over, -rise, landing):
		return
	if landing.get_normal().y < _body.climb_floor_dot:
		return

	# Only commit to a genuine rise. Without this the same probe succeeds while
	# scraping along a flat wall, where it would teleport the body sideways.
	var settled: Vector3 = over.origin + landing.get_travel()
	if settled.y - _body.global_position.y <= 0.02:
		return
	_body.global_position = settled


# --- where the fall ends -----------------------------------------------------

## Whether enough ground exists ahead of a landing point for a roll-out.
## Probes forward along horizontal velocity at half the estimated slide distance.
func roll_has_ground(landing_pos: Vector3, vel: Vector3) -> bool:
	var dir := Vector3(vel.x, 0.0, vel.z)
	if dir.length_squared() < 0.01:
		dir = _body.global_basis.z
	else:
		dir = dir.normalized()
	var dist: float = _body.land_roll_speed * _body.land_roll_recover \
		/ maxf(_body.roll_rate, 0.01) * 0.5
	var probe_from := landing_pos + dir * dist + Vector3.UP * 0.5
	var probe_to := landing_pos + dir * dist - Vector3.UP * 0.5
	var hit := cast(_body.get_world_3d().direct_space_state, probe_from, probe_to)
	if hit.is_empty():
		return false
	return (hit.normal as Vector3).y >= _body.climb_floor_dot \
		and absf((hit.position as Vector3).y - landing_pos.y) <= 0.4


## Where the arc the body is on meets ground, and how long until it does:
## {pos: Vector3, time: float}, or {} when nothing is hit inside fall_probe.
##
## Marches the arc and casts every segment of it, rather than extrapolating the
## horizontal velocity in a straight line and looking straight down from the end
## of that line. Over a void the shortcut reports whatever lies at the BOTTOM of
## the void, so a level gap jump reads as a fall from the platform's full height:
## `takeoff_drop` comes out as the platform height, _landing_for() answers with
## the roll-out landing, and its forward slide then carries the body off the far
## side. The gate that should have rejected it is computed from the same wrong
## ground, so it lets it through. Here both numbers come out of one solve.
##
## Pre: airborne. Post: pos is on a surface flat enough to stand on.
func predict_impact() -> Dictionary:
	var space: PhysicsDirectSpaceState3D = _body.get_world_3d().direct_space_state
	var tick: float = 1.0 / maxf(float(Engine.physics_ticks_per_second), 1.0)
	var span: float = PREDICT_TICKS * tick
	var at: Vector3 = _body.global_position
	var v: Vector3 = _body.velocity
	var gravity: float = _body._gravity
	var elapsed := 0.0
	var give_up: float = _body.global_position.y - _body.fall_probe
	for _sample in PREDICT_SAMPLES:
		# One sample is PREDICT_TICKS steps of the same semi-implicit Euler the
		# physics step runs, so the arc marched here is the arc actually flown.
		var rise := 0.0
		for _t in PREDICT_TICKS:
			v.y -= gravity * tick
			rise += v.y * tick
		var next := at + Vector3(v.x * span, rise, v.z * span)
		var hit := cast(space, at, next)
		if hit.is_empty() and (v.x * v.x + v.z * v.z) > 0.01:
			var forward := Vector3(v.x, 0.0, v.z).normalized() * (capsule_radius() * 0.8)
			hit = cast(space, at + forward, next + forward)
		if hit.is_empty():
			at = next
			elapsed += span
			if at.y < give_up:
				return {}
			continue
		var pos: Vector3 = hit.position
		if (hit.normal as Vector3).y >= _body.climb_floor_dot:
			var length := at.distance_to(next)
			var into: float = 0.0 if length < 0.0001 else clampf(at.distance_to(pos) / length, 0.0, 1.0)
			return {"pos": pos, "time": elapsed + span * into}
		# A face rather than a floor: move_and_slide would kill the horizontal
		# component against it and the body would drop down the face from there.
		at = pos
		v.x = 0.0
		v.z = 0.0
		elapsed += span
	return {}
