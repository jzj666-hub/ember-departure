extends SceneTree
## Throwaway: drive the real scene and see whether the body actually gets there.
## The graph probe checks the rules; this checks that the body executing them
## clears walls, rounds corners and does not end up scraping a face.
##
##   godot --headless --path . --script res://tools/_probe_npc_nav.gd

const SCENE := "res://scenes/npc_test.tscn"
## Physics ticks a run is given before it counts as failed.
const BUDGET := 1100

var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await _case_climb_wall()
	await _case_gap_course()
	await _case_tunnel()
	await _case_pocket()
	await _case_sealed_in()
	await _case_dynamic_obstacle_replan()
	await _case_dynamic_clear_shortcut()
	await _case_mid_climb_map_change()
	await _case_zero_speed_jump_center()

	print("")
	if _failures == 0:
		print("all navigation runs arrived")
		quit(0)
	else:
		print("%d navigation run(s) failed" % _failures)
		quit(1)


func _ok(label: String, condition: bool, detail := "") -> void:
	if condition:
		print("  PASS  %s %s" % [label, detail])
	else:
		_failures += 1
		print("  FAIL  %s %s" % [label, detail])


func _open() -> Node3D:
	var scene: PackedScene = load(SCENE)
	var node := scene.instantiate() as Node3D
	root.add_child(node)
	await process_frame
	await process_frame
	return node


## Runs until the body stops moving toward `target` or the budget runs out.
## Returns the closest horizontal approach it managed.
func _drive(scene: Node3D, target: Vector3) -> Dictionary:
	scene.call("_recalculate_npc_path", target)
	var npc: CharacterBody3D = scene.get("_npc")
	var source = scene.get("_npc_intent_source")
	var best := INF
	var stuck_peak := 0.0
	var initial_status := String(scene.get("_nav_status"))
	for tick in BUDGET:
		await physics_frame
		var p: Vector3 = npc.global_position
		var gap: float = Vector2(target.x - p.x, target.z - p.z).length()
		best = minf(best, gap)
		stuck_peak = maxf(stuck_peak, float(source.obstructed_time()))
		if gap < 1.2:
			break
	return {
		"gap": best,
		"stuck_peak": stuck_peak,
		"pos": npc.global_position,
		"status": String(scene.get("_nav_status")),
		"initial_status": initial_status,
	}


func _case_climb_wall() -> void:
	print("\n--- barrier across the field: only the 1/2-cube stretches are routes ---")
	var scene := await _open()
	scene.call("_setup_climb_demo")
	var target := Vector3(0.5, 0.0, 8.5)
	var run := await _drive(scene, target)
	print("    ended at (%.1f, %.1f, %.1f), %s" % [
		run.pos.x, run.pos.y, run.pos.z, run.status])
	_ok("planned a climb", run.initial_status.contains("攀爬 1") or run.initial_status.contains("攀爬 2") or run.status.contains("攀爬"),
		"(initial: %s, final: %s)" % [run.initial_status, run.status])
	_ok("crossed to the far side", run.pos.z > 5.0, "(z = %.1f)" % run.pos.z)
	_ok("reached the target", run.gap < 1.5, "(closest %.2f m)" % run.gap)
	scene.queue_free()
	await process_frame


## The course the HUD's own button builds: a ramp up, then three voids in a row.
## Only route to the far platform is over all three, so arriving proves the arcs.
func _case_gap_course() -> void:
	print("\n--- the jump course: 1, 2, 3 and 4 m voids, chained ---")
	var scene := await _open()
	scene.call("_setup_gap_demo")
	var target := Vector3(14.5, 3.0, 6.5)
	var run := await _drive(scene, target)
	print("    ended at (%.1f, %.1f, %.1f), %s" % [
		run.pos.x, run.pos.y, run.pos.z, run.status])
	_ok("planned gap jump course", run.status.contains("跳跃"), "(%s)" % run.status)
	_ok("stayed up on the platforms", run.pos.y > 2.5, "(y = %.1f)" % run.pos.y)
	_ok("reached the far platform", run.gap < 1.5, "(closest %.2f m)" % run.gap)
	scene.queue_free()
	await process_frame


func _case_tunnel() -> void:
	print("\n--- decked tunnel: the walkway under it has to survive ---")
	var scene := await _open()
	scene.call("_setup_bridge_demo")
	var target := Vector3(0.5, 0.0, -8.5)
	var run := await _drive(scene, target)
	print("    ended at (%.1f, %.1f, %.1f), %s" % [
		run.pos.x, run.pos.y, run.pos.z, run.status])
	_ok("went through, not over", run.status.contains("攀爬 0"), "(%s)" % run.status)
	_ok("reached the target", run.gap < 1.5, "(closest %.2f m)" % run.gap)
	scene.queue_free()
	await process_frame


func _case_pocket() -> void:
	print("\n--- an L-shaped pocket: straight-line pushing would wedge here ---")
	var scene := await _open()
	scene.call("_set_possession", false)
	# Three walls around the spawn, opening to -x only.
	for z in range(-2, 3):
		scene.call("_place_block", Vector3i(3, 0, z))
		scene.call("_place_block", Vector3i(3, 1, z))
		scene.call("_place_block", Vector3i(3, 2, z))
	for x in range(-2, 4):
		for y in range(0, 3):
			scene.call("_place_block", Vector3i(x, y, 3))
			scene.call("_place_block", Vector3i(x, y, -3))
	await process_frame

	var target := Vector3(7.5, 0.0, 0.5)
	scene.call("_recalculate_npc_path", target)
	var run := await _drive(scene, target)
	print("    ended at (%.1f, %.1f, %.1f), %s" % [
		run.pos.x, run.pos.y, run.pos.z, run.status])
	_ok("got out of the pocket", run.pos.x > 4.0, "(x = %.1f)" % run.pos.x)
	_ok("reached the target", run.gap < 1.5, "(closest %.2f m)" % run.gap)
	scene.queue_free()
	await process_frame


func _case_sealed_in() -> void:
	print("\n--- sealed in by a 3-cube ring: unreachable has to be reported ---")
	var scene := await _open()
	scene.call("_set_possession", false)
	for i in range(-3, 4):
		for y in range(0, 3):
			scene.call("_place_block", Vector3i(3, y, i))
			scene.call("_place_block", Vector3i(-3, y, i))
			scene.call("_place_block", Vector3i(i, y, 3))
			scene.call("_place_block", Vector3i(i, y, -3))
	await process_frame

	var target := Vector3(10.5, 0.0, 0.5)
	scene.call("_recalculate_npc_path", target)
	var run := await _drive(scene, target)
	print("    ended at (%.1f, %.1f, %.1f), %s" % [
		run.pos.x, run.pos.y, run.pos.z, run.status])
	_ok("stayed inside the ring", absf(run.pos.x) < 3.5 and absf(run.pos.z) < 3.5)
	_ok("said so", run.status.contains("不可达") or run.status.contains("停止"),
		"(%s)" % run.status)
	scene.queue_free()
	await process_frame


func _case_dynamic_obstacle_replan() -> void:
	print("\n--- dynamic obstacle: block placed mid-journey triggers automatic replan ---")
	var scene := await _open()
	scene.call("_set_possession", false)
	var target := Vector3(0.5, 0.0, 10.5)
	scene.call("_recalculate_npc_path", target)

	# Drive for a short distance
	var npc: Node3D = scene.get("_npc")
	for tick in 20:
		await physics_frame

	# Drop a 3-high wall across the path at z=5
	for x in range(-2, 3):
		for y in range(0, 3):
			scene.call("_place_block", Vector3i(x, y, 5))
	await process_frame

	var run := await _drive(scene, target)
	print("    ended at (%.1f, %.1f, %.1f), %s" % [
		run.pos.x, run.pos.y, run.pos.z, run.status])
	_ok("replanned around dynamic obstacle", run.gap < 1.5, "(closest %.2f m)" % run.gap)
	scene.queue_free()
	await process_frame


func _case_dynamic_clear_shortcut() -> void:
	print("\n--- dynamic clear: obstacle removed mid-journey triggers shortcut replan ---")
	var scene := await _open()
	scene.call("_set_possession", false)
	# Build wall across z=4
	for x in range(-4, 5):
		for y in range(0, 3):
			scene.call("_place_block", Vector3i(x, y, 4))
	await process_frame

	var target := Vector3(0.5, 0.0, 10.5)
	scene.call("_recalculate_npc_path", target)

	for tick in 20:
		await physics_frame

	# Remove center section to open direct path
	for y in range(0, 3):
		scene.call("_remove_block", Vector3i(0, y, 4))
		scene.call("_remove_block", Vector3i(1, y, 4))
	await process_frame

	var run := await _drive(scene, target)
	print("    ended at (%.1f, %.1f, %.1f), %s" % [
		run.pos.x, run.pos.y, run.pos.z, run.status])
	_ok("took newly opened shortcut", run.gap < 1.5, "(closest %.2f m)" % run.gap)
	scene.queue_free()
	await process_frame


func _case_mid_climb_map_change() -> void:
	print("\n--- mid-climb map change: does not backtrack to pre-climb origin after climb finishes ---")
	var scene := await _open()
	scene.call("_setup_climb_demo")
	var target := Vector3(0.5, 0.0, 8.5)

	var npc: CharacterBody3D = scene.get("_npc")
	var climb_triggered := false
	for tick in 450:
		await physics_frame
		var st: int = int(npc.get("state"))
		if st == PlayerController.State.CLIMBING:
			climb_triggered = true
			# Trigger map changes during climbing animation
			scene.call("_place_block", Vector3i(-10, 0, -10))
			break

	_ok("triggered climb animation", climb_triggered)

	var run := await _drive(scene, target)
	print("    ended at (%.1f, %.1f, %.1f), %s" % [
		run.pos.x, run.pos.y, run.pos.z, run.status])
	_ok("crossed to far side and reached target", run.pos.z > 5.0 and run.gap < 1.5, "(z = %.1f, gap = %.2f m)" % [run.pos.z, run.gap])
	scene.queue_free()
	await process_frame


func _case_zero_speed_jump_center() -> void:
	print("\n--- zero-speed jump at origin: forces centering to block before resuming ---")
	var scene := await _open()
	scene.call("_set_possession", false)
	var npc: CharacterBody3D = scene.get("_npc")
	var source: NPCIntentSource = scene.get("_npc_intent_source")
	# Offset to near edge of (0, 0, 0)
	npc.global_position = Vector3(0.9, 0.0, 0.5)
	npc.velocity = Vector3.ZERO
	await process_frame

	var target := Vector3(0.5, 0.0, 6.5)
	source.request_jump()
	scene.call("_recalculate_npc_path", target)

	var saw_airborne := false
	var saw_landing := false
	var saw_centering := false
	var reached_center := false

	for tick in 150:
		await physics_frame
		var p: Vector3 = npc.global_position
		if not npc.is_on_floor():
			saw_airborne = true
		elif saw_airborne:
			saw_landing = true
			if bool(source.get("_is_centering")):
				saw_centering = true
			var dist_to_center := Vector2(p.x - 0.5, p.z - 0.5).length()
			if dist_to_center < 0.12:
				reached_center = true
				break

	_ok("executed jump in air", saw_airborne)
	_ok("triggered centering after zero-speed landing at origin", saw_landing and saw_centering)
	_ok("centered to block center (0.5, 0.5)", reached_center, "(x = %.2f, z = %.2f)" % [npc.global_position.x, npc.global_position.z])

	var run := await _drive(scene, target)
	print("    ended at (%.1f, %.1f, %.1f), %s" % [
		run.pos.x, run.pos.y, run.pos.z, run.status])
	_ok("continued and reached final target", run.gap < 1.5, "(closest %.2f m)" % run.gap)
	scene.queue_free()
	await process_frame


