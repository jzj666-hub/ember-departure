extends SceneTree
## Guards the step-up rule against the dead zone it was written to close.
##
## Sub-metre steps cannot occur on a voxel map - every cell is 1 m - so this is a
## continuous-map case only. Before step-up, a NavigationMesh baked with
## agent_max_climb = 0.4 routed the body straight over a 0.2 m kerb that it then
## walked into and never got past: the mesh promised a capability the body did
## not have. Every height at or under step_max_height must now be walked over
## with no jump; above it the old jump/climb takes over.
##
##   godot --headless --path . --script res://tools/_probe_step_up.gd

const SCENE := "res://scenes/navmesh_test.tscn"
## Heights the body must simply walk over, all <= PlayerController.step_max_height.
const STEP_HEIGHTS := [0.10, 0.20, 0.30, 0.35, 0.40]
## Above step_max_height: no longer a kerb, and not this rule's business.
const JUMP_HEIGHT := 0.45
## Physics ticks one crossing is given.
const BUDGET := 700

var _failures := 0


func _initialize() -> void:
	_run()


func _ok(label: String, condition: bool, detail := "") -> void:
	if condition:
		print("  PASS  %s %s" % [label, detail])
	else:
		_failures += 1
		print("  FAIL  %s %s" % [label, detail])


func _run() -> void:
	var scene: PackedScene = load(SCENE)
	var node := scene.instantiate() as Node3D
	root.add_child(node)
	for i in 10:
		await physics_frame

	var npc: CharacterBody3D = node.get("_npc")
	_ok("step_up_enabled defaults on", bool(npc.get("step_up_enabled")))
	_ok("step_max_height stays under climb_min_height",
		float(npc.get("step_max_height")) < float(npc.get("climb_min_height")),
		"(%.2f < %.2f)" % [float(npc.get("step_max_height")), float(npc.get("climb_min_height"))])

	print("\n--- kerbs the body must walk over, silently ---")
	for h in STEP_HEIGHTS:
		var run := await _cross(node, npc, h)
		_ok("%.2f m kerb crossed" % h, run.on_step,
			"(ended y = %.2f, z = %.2f)" % [run.pos.y, run.pos.z])
		_ok("%.2f m kerb took no jump" % h, not run.jumped)

	print("\n--- above the kerb ceiling the old rules still own it ---")
	var tall := await _cross(node, npc, JUMP_HEIGHT)
	_ok("%.2f m is not silently stepped" % JUMP_HEIGHT, tall.jumped or not tall.on_step,
		"(jumped = %s)" % str(tall.jumped))

	print("")
	if _failures == 0:
		print("all step-up rules hold")
		quit(0)
	else:
		print("%d step-up rule(s) broken" % _failures)
		quit(1)


## Rebuilds the course at `height` and walks the body at it.
## Post: on_step true only if the body stood on the slab's top face.
func _cross(node: Node3D, npc: CharacterBody3D, height: float) -> Dictionary:
	await node.call("setup_step_course", height)
	node.call("_route_to", Vector3(0.0, height, 5.0))
	var jumped := false
	var on_step := false
	for tick in BUDGET:
		await physics_frame
		var p: Vector3 = npc.global_position
		var st := String(npc.call("state_name")) if npc.has_method("state_name") \
			else str(npc.get("state"))
		if st.contains("跳") or st.contains("爬"):
			jumped = true
		if p.y >= height - 0.08 and p.z > 1.3 and p.z < 8.7:
			on_step = true
			break
	return {"on_step": on_step, "jumped": jumped, "pos": npc.global_position}
