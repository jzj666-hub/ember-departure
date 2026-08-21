class_name NavMeshProvider
extends NavProvider
## NavProvider backed by NavigationServer3D, for continuous maps: terrain, roads,
## imported building meshes - anything a 1 m voxel grid cannot represent.
##
## What differs from NavGrid, and why:
## - every leg inside a baked region is Move.WALK. A polygon corridor carries no
##   notion of "jumped a gap"; vertical traversal exists only where a
##   NavigationLink3D was authored. Nothing here infers a jump from geometry.
## - there are no cells, so stand_center() is the identity: a body on the mesh is
##   already where it should be. NavGrid centres because a cell has a middle.
## - queries are answered by distance to the mesh, not by set membership, so
##   every "is this standable" answer needs a tolerance.
##
## Pre: bind_map()/bind_region() has run and the server has synced at least one
## physics frame past the bake. Queries before that answer empty, not wrong.

## Metres a query point may sit horizontally off the mesh and still count as on
## it. About the agent radius: past that the point is over the rim, not on it.
const HORIZ_TOLERANCE := 0.35
## Metres a query point may sit above or below the mesh and still count as on it.
##
## Deliberately loose, and the reason is the callers. _void_between() and
## _runway_ahead() sample a horizontal line at the *start* point's height, which
## is exact on a voxel map where every level is flat and wrong on a slope, where
## the ground climbs out from under the samples. A tight vertical test would read
## a walkable ramp as a cliff and the executor would try to jump it. Wide enough
## to span a ramp across RIM_LIMIT, tight enough to still reject the floor of a
## storey below.
const VERT_TOLERANCE := 3.0
## Metres the route's end may sit from the requested goal and still count as
## having arrived. The server always routes to the closest reachable point, so
## this is the only thing separating "arrived" from "got as near as it could".
const GOAL_TOLERANCE := 0.5
## Metres the requested goal itself may sit off the mesh and still be treated as
## a place the body can stand. Wider than HORIZ_TOLERANCE because the mesh is
## inset by the agent radius, so a goal picked against a wall is legitimately
## that far off it. Without this test every goal snaps onto the mesh and every
## route reports complete, including one pointed off the map entirely.
const GOAL_ON_MESH_TOLERANCE := 1.0

var _map := RID()


# --- binding ----------------------------------------------------------------

## Binds the navigation map queries run against. Emits changed.
func bind_map(map: RID) -> void:
	_map = map
	changed.emit()


## Binds the map owning `region`. Pre: region is inside the tree.
func bind_region(region: NavigationRegion3D) -> void:
	bind_map(region.get_navigation_map())


func map() -> RID:
	return _map


## A bound map the server has finished syncing. False answers are safe: every
## query below degrades to "nothing known" rather than to a wrong answer.
func is_ready() -> bool:
	return _map.is_valid() and NavigationServer3D.map_is_active(_map)


# --- contract ---------------------------------------------------------------

## Post: moves is all WALK - see the class note on why nothing else can appear.
func find_path(from_pos: Vector3, to_pos: Vector3) -> Dictionary:
	var out := {
		"points": PackedVector3Array(),
		"moves": PackedInt32Array(),
		"special_links": {},
		"complete": false,
		"goal": to_pos,
		"reachable": to_pos,
	}
	if not is_ready():
		return out

	var pts := NavigationServer3D.map_get_path(_map, from_pos, to_pos, true)
	if pts.size() < 2:
		return out
	pts = _densify(pts)

	var moves := PackedInt32Array()
	moves.resize(pts.size())
	moves.fill(Move.WALK)

	var last := pts[pts.size() - 1]
	# Two separate questions. Is the goal a place the body could stand at all,
	# and did the route actually get there. Snapping the goal and then measuring
	# against the snapped copy answers yes to both for every goal, including one
	# two hundred metres off the map.
	var goal_on_mesh := NavigationServer3D.map_get_closest_point(_map, to_pos)
	var goal_is_on_map := goal_on_mesh.distance_to(to_pos) <= GOAL_ON_MESH_TOLERANCE
	out.points = pts
	out.moves = moves
	out.complete = goal_is_on_map and last.distance_to(goal_on_mesh) <= GOAL_TOLERANCE
	out.reachable = last
	return out


## Every remaining waypoint is still on the mesh. A rebake that drops geometry
## under a planned route is what this catches.
func is_path_valid(points: PackedVector3Array, start_index := 0) -> bool:
	if not is_ready():
		return false
	for i in range(maxi(0, start_index), points.size()):
		if not is_standable_at(points[i]):
			return false
	return true


## Post: NO_POINT when the mesh is not ready or `pos` is off it.
func stand_foot(pos: Vector3) -> Vector3:
	if not is_ready():
		return NO_POINT
	var p := NavigationServer3D.map_get_closest_point(_map, pos)
	return p if _within(p, pos) else NO_POINT


## Identity: continuous ground has no cell to centre in, so a body on the mesh
## is already centred. Overrides the base's arithmetic cell centre, which would
## drag the body onto a grid this map does not have.
func stand_center(pos: Vector3) -> Vector3:
	return pos


func is_standable_at(point: Vector3) -> bool:
	if not is_ready():
		return false
	return _within(NavigationServer3D.map_get_closest_point(_map, point), point)


## Mesh point `p` is close enough to query point `q` to answer for it.
## Horizontal and vertical are judged apart - see the tolerance notes.
static func _within(p: Vector3, q: Vector3) -> bool:
	return Vector2(p.x - q.x, p.z - q.z).length() <= HORIZ_TOLERANCE \
		and absf(p.y - q.y) <= VERT_TOLERANCE


## Splits any leg that climbs more than the body would take for a step, so that
## no leg of the route can be mistaken for a ledge.
##
## The executor reads a waypoint higher than itself by more than its step
## tolerance as a ledge and starts a climb (see NPCIntentSource, _step_tolerance).
## That is exact on a voxel map, where a rise really is a step. String-pulled
## navmesh corners can sit metres apart across a ramp, and the same rule then
## makes the body try to climb a slope it should simply walk up. NavGrid never
## trips this because it emits a waypoint per cell. Emitting a comparably fine
## route on rising ground is the backend's job, not the executor's problem.
##
## Post: consecutive points differ by at most _max_rise() in y; every inserted
## point is snapped back onto the mesh.
func _densify(pts: PackedVector3Array) -> PackedVector3Array:
	var max_rise := _max_rise()
	var out := PackedVector3Array()
	out.append(pts[0])
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var steps := int(ceil(absf(b.y - a.y) / max_rise))
		for s in range(1, steps):
			out.append(NavigationServer3D.map_get_closest_point(
				_map, a.lerp(b, float(s) / float(steps))))
		out.append(b)
	return out


## Biggest y step a leg may carry. Half the body's climb threshold: comfortably
## under the executor's own tolerance, which is 0.8 of that same threshold.
func _max_rise() -> float:
	return maxf(capability().climb_min * 0.5, 0.1)
