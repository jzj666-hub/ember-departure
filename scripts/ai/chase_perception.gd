class_name ChasePerception
extends RefCounted
## What one agent knows about its opponent: line of sight, hearing, a decaying
## belief about where it is, and a short position history for delayed aiming.
##
## Invariant: `pos` is the truth only while `knows()`; otherwise it is the last
## sighting and `radius` is how far the foe could have travelled since. Brains
## read the belief, never the body.
##
## `has_los` is sight alone and `heard` is proximity alone - they are kept apart
## because the chaser's sprint rule keys on sight only, while the belief updates
## on either.
##
## The clock is accumulated from delta, not read off Time: two runs from the same
## seed have to produce the same sightings.

## Metres at which the foe is heard through geometry.
const HEAR_RADIUS := 6.0
## Confidence left after one second with no contact.
const CONFIDENCE_DECAY := 0.55
## Seconds of position history kept for delayed aiming.
const HISTORY_SECONDS := 1.2
## Height difference above which line of sight is refused outright, metres.
const LOS_MAX_RISE := 0.85
## Height the obstruction ray is cast at, metres.
const LOS_EYE := 0.8
## Floor-continuity probes taken between the two ends. A void in between breaks
## sight even when nothing blocks it: there is no ground to sprint across.
const LOS_FLOOR_SAMPLES := 4

## Believed foe position. Truth while known, last sighting otherwise.
var pos := Vector3.ZERO
## Foe velocity as of the last contact.
var vel := Vector3.ZERO
## Clear line of sight this frame. Sight only - see the class note.
var has_los := false
## Foe within HEAR_RADIUS this frame, geometry ignored.
var heard := false
## 1.0 on contact, decaying towards 0 while out of contact.
var confidence := 0.0
## Metres the foe could have moved since the last contact.
var radius := 0.0
## Seconds since the last contact. 0.0 while in contact.
var since_seen := 0.0
## Set once the foe has ever been located.
var ever_seen := false

## Truth history for delayed aiming: [{t, pos}], oldest first.
var _history: Array[Dictionary] = []
var _clock := 0.0


## Sight or hearing this frame.
func knows() -> bool:
	return has_los or heard


## Post: belief cleared, history empty, clock zeroed.
func reset() -> void:
	pos = Vector3.ZERO
	vel = Vector3.ZERO
	has_los = false
	heard = false
	confidence = 0.0
	radius = 0.0
	since_seen = 0.0
	ever_seen = false
	_history.clear()
	_clock = 0.0


## Advances the belief one physics frame.
## `foe_top_speed` is how fast the uncertainty circle grows while out of contact.
## `exclude` are RIDs the sight rays ignore - both bodies, so neither occludes
## itself.
func update(space: PhysicsDirectSpaceState3D, self_pos: Vector3, foe_pos: Vector3,
		foe_vel: Vector3, foe_top_speed: float, delta: float, exclude: Array) -> void:
	_clock += delta

	_history.append({"t": _clock, "pos": foe_pos})
	while _history.size() > 1 and (_clock - float(_history[0].t)) > HISTORY_SECONDS:
		_history.pop_front()

	heard = self_pos.distance_to(foe_pos) <= HEAR_RADIUS
	has_los = has_line_of_sight(space, self_pos, foe_pos, exclude)

	if knows():
		pos = foe_pos
		vel = foe_vel
		confidence = 1.0
		radius = 0.0
		since_seen = 0.0
		ever_seen = true
	else:
		since_seen += delta
		confidence = maxf(0.0, confidence * pow(CONFIDENCE_DECAY, delta))
		radius += maxf(foe_top_speed, 0.0) * delta


## Where the foe was `delay` seconds ago. What a chaser aims at, so its sprint
## lags the target the way a human's would.
## Post: the oldest sample when the history does not reach back that far.
func delayed_pos(delay: float) -> Vector3:
	if _history.is_empty():
		return pos
	var target_t := _clock - delay
	for i in range(_history.size() - 1, -1, -1):
		if float(_history[i].t) <= target_t:
			return _history[i].pos
	return _history[0].pos


## Something solid stands between the two foot positions at chest height.
##
## The obstruction half of has_line_of_sight() without the floor-continuity half:
## this asks "is that spot behind cover", not "can I see him". One ray, so it is
## cheap enough to run over every candidate slot every decision tick.
static func cover_between(space: PhysicsDirectSpaceState3D, from_pos: Vector3,
		to_pos: Vector3, exclude: Array) -> bool:
	if space == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(
		from_pos + Vector3(0.0, LOS_EYE, 0.0),
		to_pos + Vector3(0.0, LOS_EYE, 0.0))
	query.collide_with_areas = false
	query.exclude = exclude
	return not space.intersect_ray(query).is_empty()


## Unobstructed, floor-continuous line between two foot positions.
##
## Two tests, both required: nothing solid across the chest-height ray, and ground
## under every sample along the way. Static so both sides share one definition - a
## chaser that sees further than the evader believes is a bug, not a difficulty
## knob.
static func has_line_of_sight(space: PhysicsDirectSpaceState3D, from_pos: Vector3,
		to_pos: Vector3, exclude: Array) -> bool:
	if space == null:
		return false
	if absf(from_pos.y - to_pos.y) > LOS_MAX_RISE:
		return false

	var query := PhysicsRayQueryParameters3D.create(
		from_pos + Vector3(0.0, LOS_EYE, 0.0),
		to_pos + Vector3(0.0, LOS_EYE, 0.0))
	query.collide_with_areas = false
	query.exclude = exclude
	if not space.intersect_ray(query).is_empty():
		return false

	for i in range(1, LOS_FLOOR_SAMPLES):
		var sample_p := from_pos.lerp(to_pos, float(i) / float(LOS_FLOOR_SAMPLES))
		var down := PhysicsRayQueryParameters3D.create(
			sample_p + Vector3(0.0, 0.4, 0.0),
			sample_p + Vector3(0.0, -1.2, 0.0))
		down.collide_with_areas = false
		down.exclude = exclude
		if space.intersect_ray(down).is_empty():
			return false

	return true
