@tool
extends SceneTree
## Contract probe: NavGrid satisfies NavProvider, and the world-space wrappers
## added by the interface extraction answer identically to the voxel calls they
## replaced. Guards the "two map modes" refactor against silent drift.

const NavGridScript = preload("res://scripts/nav_grid.gd")
const NavProviderScript = preload("res://scripts/nav_provider.gd")

var _fails := 0


func _ok(cond: bool, label: String) -> void:
	if cond:
		print("  PASS  %s" % label)
	else:
		print("  FAIL  %s" % label)
		_fails += 1


func _init() -> void:
	print("\n--- NavProvider contract ---")
	_subtype()
	_surface()
	_base_defaults()
	_equivalence()
	_capability_moved()

	if _fails > 0:
		print("\n%d nav provider contract rule(s) broken\n" % _fails)
		quit(1)
	else:
		print("\nall nav provider contract tests passed!\n")
		quit(0)


## NavGrid is usable wherever a NavProvider is asked for.
func _subtype() -> void:
	var nav := NavGridScript.new()
	_ok(nav is NavProvider, "NavGrid is a NavProvider")


## Every method NPCIntentSource calls through the interface exists.
func _surface() -> void:
	var nav := NavGridScript.new()
	for m in [
		"find_path", "is_path_valid", "capability",
		"set_capability", "set_capability_direct",
		"stand_center", "stand_foot", "is_standable_at",
	]:
		_ok(nav.has_method(m), "contract method %s()" % m)
	_ok(nav.has_signal("changed"), "contract signal changed")


## The bare base answers neutrally: no map, so nothing is known and nothing lies.
func _base_defaults() -> void:
	var base := NavProviderScript.new()
	_ok(base.stand_foot(Vector3(3.3, 1.0, 4.7)) == NavProviderScript.NO_POINT,
		"base stand_foot() is NO_POINT")
	_ok(base.stand_center(Vector3(3.3, 1.25, 4.7)) == Vector3(3.5, 1.25, 4.5),
		"base stand_center() is the arithmetic centre, y untouched")
	_ok(base.is_standable_at(Vector3(3.3, 1.0, 4.7)), "base is_standable_at() is true")
	var p: Dictionary = base.find_path(Vector3.ZERO, Vector3.ONE)
	_ok(p.get("points", null) != null and (p["points"] as PackedVector3Array).is_empty(),
		"base find_path() returns an empty route")
	_ok(not bool(p.get("complete", true)), "base find_path() is not complete")


## The wrappers equal the voxel calls they replaced, position by position.
## stand_center keeps the query's own y; stand_foot keeps the cell floor.
func _equivalence() -> void:
	var nav := NavGridScript.new()
	nav.set_bounds(10, 5)
	nav.set_block(Vector3i(0, 0, 0), true)
	nav.set_block(Vector3i(1, 0, 0), true)
	nav.set_block(Vector3i(1, 1, 0), true)
	nav.set_block(Vector3i(4, 0, 0), true)

	var probes := [
		Vector3(0.9, 2.0, 0.5),    # on the tall block
		Vector3(0.4, 1.0, 0.5),    # on the short block
		Vector3(5.5, 0.0, 5.5),    # open ground
		Vector3(4.5, 1.0, 0.5),    # on the lone block
		Vector3(-3.5, 0.0, 2.5),   # open ground, negative quadrant
		Vector3(50.0, 0.0, 50.0),  # out of bounds
	]

	var foot_ok := true
	var center_ok := true
	for p in probes:
		var node: Vector3i = nav.standing_node(p)
		var want_foot: Vector3 = NavProviderScript.NO_POINT
		var want_center := Vector3(floor(p.x) + 0.5, p.y, floor(p.z) + 0.5)
		if node != NavGridScript.NO_CELL:
			want_foot = NavGridScript.foot(node)
			want_center = Vector3(want_foot.x, p.y, want_foot.z)
		if nav.stand_foot(p) != want_foot:
			foot_ok = false
			print("        stand_foot%s got %s want %s" % [p, nav.stand_foot(p), want_foot])
		if nav.stand_center(p) != want_center:
			center_ok = false
			print("        stand_center%s got %s want %s" % [p, nav.stand_center(p), want_center])
	_ok(foot_ok, "stand_foot() == foot(standing_node()) at every probe")
	_ok(center_ok, "stand_center() keeps the query's own y at every probe")

	# is_standable_at derives level as floor(y + 0.05): the caller's level source.
	var stand_ok := true
	for x in range(-2, 6):
		for z in range(-2, 3):
			for y in [0.0, 1.0, 2.0]:
				var w := Vector3(float(x) + 0.5, y, float(z) + 0.5)
				var want: bool = nav.is_standable(
					Vector3i(int(floor(w.x)), int(floor(w.y + 0.05)), int(floor(w.z))))
				if nav.is_standable_at(w) != want:
					stand_ok = false
					print("        is_standable_at%s got %s want %s"
						% [w, nav.is_standable_at(w), want])
	_ok(stand_ok, "is_standable_at() == is_standable() over the sample volume")


## Move/Capability/thresholds now live on the base and stay reachable both ways.
func _capability_moved() -> void:
	_ok(NavGridScript.Move.WALK == NavProviderScript.Move.WALK
		and NavGridScript.Move.SPECIAL_JUMP == NavProviderScript.Move.SPECIAL_JUMP,
		"Move resolves through both the base and the subclass")
	_ok(NavGridScript.JUMP_CLEAR == NavProviderScript.JUMP_CLEAR
		and NavGridScript.MAX_DROP == NavProviderScript.MAX_DROP,
		"jump thresholds resolve through both")

	# set_capability_direct still refreshes what the graph derives from it.
	var nav := NavGridScript.new()
	nav.set_bounds(10, 5)
	var cap := NavProviderScript.Capability.new()
	cap.stand_height = 2.4
	nav.set_capability_direct(cap)
	_ok(nav.capability() == cap, "set_capability_direct() installs on the base")
	_ok(nav.is_dirty(), "set_capability_direct() marks the graph dirty")
	nav.set_block(Vector3i(0, 0, 0), true)
	nav.set_block(Vector3i(0, 1, 0), true)
	nav.rebuild()
	# stand_height 2.4 needs 3 cells of headroom, so the cell right under the
	# 2-high stack's top is not standable.
	_ok(not nav.is_standable(Vector3i(0, 1, 0)), "head_cells() from the new capability is in force")
