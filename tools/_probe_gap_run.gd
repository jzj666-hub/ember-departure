extends SceneTree
## Throwaway: drive the real body across real voids, over and over.
##
## The graph probe checks what the rules say; this checks what the physics does.
## Repeats every crossing, because the landing bug this replaced was phase
## dependent - it needed the frame the arc happened to be on to line up, and
## showed roughly one crossing in three.
##
##   godot --headless --path . --script res://tools/_probe_gap_run.gd

const SCENE := "res://scenes/npc_test.tscn"
## Physics ticks one crossing is given before it counts as failed.
const BUDGET := 420
## Crossings per case. One round trip is two.
const CROSSINGS := 10
## Standable surface of every plate: blocks at y = 1 only, so the body cannot
## climb back up from the ground and the arc is the only way across.
const TOP := 2.0

var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	# `void` is the number of empty columns between the two slabs, which for an
	# orthogonal pair is the edge-to-edge distance in metres and for a diagonal
	# one is that distance over sqrt(2). The widest the shipped body can take is
	# 3.15 m, so 3 and 2 are the last rungs of each ladder.
	await _case("orthogonal 1 m void", 1, false)
	await _case("orthogonal 2 m void", 2, false)
	await _case("orthogonal 3 m void", 3, false)
	await _case("diagonal 1.41 m void", 1, true)
	await _case("diagonal 2.83 m void", 2, true)

	print("")
	if _failures == 0:
		print("every crossing landed")
		quit(0)
	else:
		print("%d crossing check(s) failed" % _failures)
		quit(1)


func _ok(label: String, condition: bool, detail := "") -> void:
	if condition:
		print("  PASS  %s %s" % [label, detail])
	else:
		_failures += 1
		print("  FAIL  %s %s" % [label, detail])


func _open() -> Node3D:
	var scene: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.call("_set_possession", false)
	return scene


## A 6x5 slab whose near corner is (x0, z0) and which extends away from the void.
func _plate(scene: Node3D, x0: int, z0: int, sx: int, sz: int) -> void:
	for i in range(0, 6):
		for j in range(0, 5):
			scene.call("_place_block", Vector3i(x0 + i * sx, 1, z0 + j * sz))


## Runs one crossing. Returns what the body did on the way.
func _cross(scene: Node3D, target: Vector3) -> Dictionary:
	var npc: CharacterBody3D = scene.get("_npc")
	var src = scene.get("_npc_intent_source")
	scene.call("_recalculate_npc_path", target)
	var rolled := false
	var low := INF
	for tick in BUDGET:
		await physics_frame
		if int(npc.get("state")) == PlayerController.State.LANDING \
				and bool(npc.get("_action_slides")):
			rolled = true
		if int(npc.get("state")) == PlayerController.State.ROLLING:
			rolled = true
		low = minf(low, npc.global_position.y)
		if bool(src.call("has_reached_target")):
			break
	return {
		"pos": npc.global_position,
		"rolled": rolled,
		"low": low,
		"gap": Vector2(target.x - npc.global_position.x,
			target.z - npc.global_position.z).length(),
	}


## `void_cells` empty columns between two slabs, laid out along x or along both
## axes. Drives the body back and forth across it CROSSINGS times.
##
## The near slab's last cell is x = -1, so a far slab starting at x = void_cells
## leaves exactly that many columns of nothing in between.
func _case(label: String, void_cells: int, diagonal: bool) -> void:
	print("\n--- %s ---" % label)
	var scene := await _open()
	var far := void_cells
	if diagonal:
		_plate(scene, -1, -1, -1, -1)
		_plate(scene, far, far, 1, 1)
	else:
		_plate(scene, -1, -2, -1, 1)
		_plate(scene, far, -2, 1, 1)
	await process_frame

	var npc: CharacterBody3D = scene.get("_npc")
	var here := Vector3(-3.5, TOP, -3.5 if diagonal else 0.5)
	var there := Vector3(float(far) + 2.5, TOP, float(far) + 2.5 if diagonal else 0.5)
	npc.global_position = here
	npc.velocity = Vector3.ZERO
	await process_frame

	var arrived := 0
	var rolls := 0
	var fell := 0
	var worst := 0.0
	for i in CROSSINGS:
		var to := there if i % 2 == 0 else here
		var run := await _cross(scene, to)
		if bool(run.rolled):
			rolls += 1
		# TOP - 0.5 rather than TOP: a landing settles a few centimetres. Anything
		# that actually left the plates is on the ground plane at 0.
		if float(run.low) < TOP - 0.5:
			fell += 1
		if float(run.gap) < 1.2:
			arrived += 1
		worst = maxf(worst, float(run.gap))
		# A failed crossing leaves the body wherever it ended up; put it back so
		# the next one starts from a known place.
		npc.global_position = to
		npc.velocity = Vector3.ZERO
		await physics_frame

	_ok("arrived %d/%d" % [arrived, CROSSINGS], arrived == CROSSINGS,
		"(worst approach %.2f m)" % worst)
	_ok("never left the plates", fell == 0, "(%d fell)" % fell)
	_ok("never rolled out of a landing", rolls == 0, "(%d rolled)" % rolls)
	scene.queue_free()
	await process_frame
