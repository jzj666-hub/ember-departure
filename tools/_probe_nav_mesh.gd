extends SceneTree
## Drives the continuous-map scene end to end: bake a NavigationMesh, route an
## NPC over it, and confirm the executor - untouched, still NPCIntentSource -
## arrives without knowing the map stopped being voxels.
##
##   godot --headless --path . --script res://tools/_probe_nav_mesh.gd

const SCENE := "res://scenes/navmesh_test.tscn"
## Physics ticks a run is given before it counts as failed.
const BUDGET := 1400

var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await _case_ready()
	await _case_flat_detour()
	await _case_up_the_ramp()
	await _case_unreachable()
	await _case_contract_on_mesh()

	print("")
	if _failures == 0:
		print("all navmesh navigation runs arrived")
		quit(0)
	else:
		print("%d navmesh run(s) failed" % _failures)
		quit(1)


func _ok(label: String, condition: bool, detail := "") -> void:
	if condition:
		print("  PASS  %s %s" % [label, detail])
	else:
		_failures += 1
		print("  FAIL  %s %s" % [label, detail])


## The scene bakes in _ready() and binds two physics frames later, so the open
## has to outlast both before anything is asked of the provider.
func _open() -> Node3D:
	var scene: PackedScene = load(SCENE)
	var node := scene.instantiate() as Node3D
	root.add_child(node)
	for i in 8:
		await physics_frame
	return node


func _drive(scene: Node3D, target: Vector3) -> Dictionary:
	scene.call("_route_to", target)
	var npc: CharacterBody3D = scene.get("_npc")
	var best := INF
	var initial_status := String(scene.get("_nav_status"))
	for tick in BUDGET:
		await physics_frame
		var p: Vector3 = npc.global_position
		var gap: float = Vector2(target.x - p.x, target.z - p.z).length()
		best = minf(best, gap)
		if gap < 1.2:
			break
	return {
		"gap": best,
		"pos": npc.global_position,
		"status": String(scene.get("_nav_status")),
		"initial_status": initial_status,
	}


func _case_ready() -> void:
	print("\n--- the mesh bakes and the provider binds ---")
	var scene := await _open()
	var nav = scene.get("_nav")
	_ok("provider is a NavProvider", nav is NavProvider)
	_ok("provider is NOT a NavGrid", not (nav is NavGrid))
	_ok("navigation map is ready", bool(nav.call("is_ready")))
	var src = scene.get("_npc_intent_source")
	_ok("executor bound to the mesh provider", src.get("_nav_grid") == nav)
	scene.queue_free()
	await process_frame


## Flat ground with a rotated wall in the way: proves ordinary routing works and
## that the detour comes from the mesh, not from a grid.
func _case_flat_detour() -> void:
	print("\n--- across the field, around a wall rotated 28 degrees ---")
	var scene := await _open()
	var target := Vector3(-12.0, 0.0, 10.0)
	var run := await _drive(scene, target)
	print("    ended at (%.1f, %.1f, %.1f), %s" % [
		run.pos.x, run.pos.y, run.pos.z, run.status])
	_ok("planned a route", not run.initial_status.contains("无法"),
		"(%s)" % run.initial_status)
	_ok("every leg is WALK", run.initial_status.contains("全程 WALK"))
	_ok("reached the target", run.gap < 1.5, "(closest %.2f m)" % run.gap)
	scene.queue_free()
	await process_frame


## The one NavGrid could never plan: a 16-degree slope has no integer height, so
## the voxel graph cannot hold it. Arriving 2 m up proves the seam does its job.
func _case_up_the_ramp() -> void:
	print("\n--- up the ramp onto the platform (impossible for a voxel graph) ---")
	var scene := await _open()
	var target := Vector3(4.0, 2.0, 6.0)
	var run := await _drive(scene, target)
	print("    ended at (%.1f, %.1f, %.1f), %s" % [
		run.pos.x, run.pos.y, run.pos.z, run.status])
	_ok("planned a climbing route", run.initial_status.contains("累计爬升"),
		"(%s)" % run.initial_status)
	_ok("arrived on top of the platform", run.pos.y > 1.5, "(y = %.2f)" % run.pos.y)
	_ok("reached the target", run.gap < 1.5, "(closest %.2f m)" % run.gap)
	_ok("still no jump leg was invented", run.initial_status.contains("全程 WALK"))
	scene.queue_free()
	await process_frame


## Off the mesh entirely: the server routes to the closest reachable point, and
## the provider must report that as incomplete rather than as arrival.
func _case_unreachable() -> void:
	print("\n--- a goal well outside the mesh ---")
	var scene := await _open()
	var nav = scene.get("_nav")
	var npc: CharacterBody3D = scene.get("_npc")
	var result: Dictionary = nav.call("find_path", npc.global_position, Vector3(200.0, 0.0, 200.0))
	_ok("a route was still produced", (result.points as PackedVector3Array).size() >= 2,
		"(%d points)" % (result.points as PackedVector3Array).size())
	_ok("reported incomplete", not bool(result.complete))
	scene.queue_free()
	await process_frame


## Contract behaviour that differs from NavGrid on purpose.
func _case_contract_on_mesh() -> void:
	print("\n--- contract answers on a continuous map ---")
	var scene := await _open()
	var nav = scene.get("_nav")

	var on_mesh := Vector3(-8.0, 0.0, -8.0)
	var off_mesh := Vector3(80.0, 0.0, 80.0)
	var high_up := Vector3(-8.0, 25.0, -8.0)

	_ok("stand_center() is the identity", nav.call("stand_center", on_mesh) == on_mesh,
		"(no cells to centre in)")
	_ok("is_standable_at() true on the mesh", bool(nav.call("is_standable_at", on_mesh)))
	_ok("is_standable_at() false off the mesh", not bool(nav.call("is_standable_at", off_mesh)))
	_ok("is_standable_at() false high above it", not bool(nav.call("is_standable_at", high_up)))
	_ok("stand_foot() is NO_POINT off the mesh",
		nav.call("stand_foot", off_mesh) == NavProvider.NO_POINT)
	var foot: Vector3 = nav.call("stand_foot", on_mesh)
	_ok("stand_foot() lands on the mesh near the query", foot.distance_to(on_mesh) < 0.5,
		"(%.2f m away)" % foot.distance_to(on_mesh))

	scene.queue_free()
	await process_frame
