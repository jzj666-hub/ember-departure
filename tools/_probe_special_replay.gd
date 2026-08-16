extends SceneTree
## Throwaway: does a recorded special path reach the executor, and does the
## executor play it back frame for frame? Drives NPCIntentSource's replay state
## machine directly - no physics body, `grounded` is handed in.
##
##   godot --headless --path . --script res://tools/_probe_special_replay.gd

const NavGridScript = preload("res://scripts/nav_grid.gd")
const NPCIntentSourceScript = preload("res://scripts/npc_intent_source.gd")

const TICK := 1.0 / 60.0
## Cells the recorded arc joins. 5 columns of void between them: past the plain
## gap-jump budget, so the only edge across is the recording's own.
const FROM_CELL := Vector3i(-1, 2, 0)
const TO_CELL := Vector3i(5, 2, 0)
const REST_POS := Vector3(-3.5, 2.0, 0.5)
const REST_HEADING := PI * 0.5

var _failures := 0
var _repaths := 0


func _initialize() -> void:
	_check_plan_carries_link()
	_check_replay_phases()
	_check_tape_is_fed_verbatim()
	_check_landing_center()
	_check_attempts_bounded()
	_check_multi_path_isolation()

	print("")
	if _failures == 0:
		print("special path replay holds")
		quit(0)
	else:
		print("%d special path replay rule(s) broken" % _failures)
		quit(1)


func _ok(label: String, condition: bool, detail := "") -> void:
	if condition:
		print("  PASS  %s %s" % [label, detail])
	else:
		_failures += 1
		print("  FAIL  %s %s" % [label, detail])


func _plate(grid: NavGrid, x0: int, x1: int, z0: int, z1: int, y := 1) -> void:
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			grid.set_block(Vector3i(x, y, z), true)


## A tape: `ground` frames of run-up, a jump on the last of them, then `air`
## frames of flight ending on the floor. Values are distinguishable per frame so
## a mis-ordered playback shows up.
func _tape(ground := 20, air := 40) -> Array:
	var out: Array = []
	for i in range(ground):
		out.append({
			"t": float(i) * TICK,
			"p": [REST_POS.x + float(i) * 0.05, REST_POS.y, REST_POS.z],
			"v": [0.0, 0.0, 0.0],
			"move": [0.0, 1.0],
			"heading": REST_HEADING + float(i) * 0.001,
			"run": i >= 4,
			"jump": i == ground - 1,
			"grounded": true,
		})
	for i in range(air):
		out.append({
			"t": float(ground + i) * TICK,
			"p": [REST_POS.x + float(ground + i) * 0.06, REST_POS.y + 0.5, REST_POS.z],
			"v": [0.0, 0.0, 0.0],
			"move": [0.0, 1.0],
			"heading": REST_HEADING,
			"run": true,
			"jump": false,
			"grounded": i >= air - 1,
		})
	return out


func _record(ground := 20, air := 40) -> Dictionary:
	return {
		"id": "probe_path",
		"from": [FROM_CELL.x, FROM_CELL.y, FROM_CELL.z],
		"to": [TO_CELL.x, TO_CELL.y, TO_CELL.z],
		"straight_line": true,
		"rest_pos": [REST_POS.x, REST_POS.y, REST_POS.z],
		"rest_heading": REST_HEADING,
		"ground_frames": ground,
		"trajectory": _tape(ground, air),
	}


func _grid() -> NavGrid:
	var grid = NavGridScript.new()
	grid.set_bounds(12, 8)
	grid.set_capability_direct(NavGridScript.Capability.new())
	_plate(grid, -5, -1, -1, 1)
	_plate(grid, 5, 9, -1, 1)
	return grid


func _source(grid: NavGrid) -> NPCIntentSource:
	var src = NPCIntentSourceScript.new()
	src.bind_nav_grid(grid)
	src.repath_requested.connect(func(_a: Vector3, _b: Vector3) -> void: _repaths += 1)
	return src


# --- the plan carries the recording ----------------------------------------

func _check_plan_carries_link() -> void:
	print("\n--- find_path() hands the recording to set_plan_result() ---")
	var grid := _grid()
	var bare := grid.find_path(NavGrid.foot(FROM_CELL), NavGrid.foot(TO_CELL))
	_ok("a 5-cell void is not crossable on its own", not bool(bare.complete))

	grid.add_special_path(_record())
	var res := grid.find_path(NavGrid.foot(FROM_CELL), NavGrid.foot(TO_CELL))
	_ok("the recording opens the route", bool(res.complete),
		"(%d waypoints)" % res.points.size())

	var links: Dictionary = res.get("special_links", {})
	_ok("find_path() reports one special link", links.size() == 1,
		"(%d)" % links.size())
	var idx: int = links.keys()[0] if links.size() == 1 else -1
	_ok("the link sits on a SPECIAL_JUMP leg",
		idx > 0 and idx < res.moves.size() and int(res.moves[idx]) == NavGrid.Move.SPECIAL_JUMP,
		"(index %d)" % idx)
	_ok("the link carries the tape",
		idx >= 0 and (links[idx].get("trajectory", []) as Array).size() == 60)

	var src := _source(grid)
	src.set_plan_result(res)
	_ok("set_plan_result() installs the link", src._leg_is_special(idx))
	_ok("plain legs are not special", not src._leg_is_special(1) or idx == 1)
	src.clear_target()
	_ok("clear_target() drops the links", not src._leg_is_special(idx))


# --- the phases -------------------------------------------------------------

## Runs one replay frame. Returns whether the replay claimed it.
func _step(src: NPCIntentSource, body: CharacterBody3D, pos: Vector3,
		intent: CharacterIntent, grounded: bool) -> bool:
	intent.clear()
	var claimed: bool = src._drive_special_replay(body, pos, TICK, intent, grounded)
	# poll() applies the queued jump after the driver has written the frame.
	if src._queued_jump:
		intent.jump = true
		src._queued_jump = false
	return claimed


func _armed() -> Array:
	var grid := _grid()
	grid.add_special_path(_record())
	var res := grid.find_path(NavGrid.foot(FROM_CELL), NavGrid.foot(TO_CELL))
	var src := _source(grid)
	src.set_plan_result(res)
	var links: Dictionary = res.get("special_links", {})
	var idx: int = links.keys()[0]
	src._path_index = idx
	var body := CharacterBody3D.new()
	body.rotation.y = REST_HEADING + PI  # facing exactly backwards
	return [grid, src, body, idx]


func _check_replay_phases() -> void:
	print("\n--- walk to the rest point, turn on the spot, then roll the tape ---")
	var armed := _armed()
	var src: NPCIntentSource = armed[1]
	var body: CharacterBody3D = armed[2]
	var intent := CharacterIntent.new()

	# Standing a metre and a half short of the rest point.
	var away := REST_POS - Vector3(1.5, 0.0, 0.0)
	_ok("the leg is claimed by the replay", _step(src, body, away, intent, true))
	_ok("phase is WALK_TO_REST", src._replay_phase == NPCIntentSourceScript.ReplayPhase.WALK_TO_REST)
	_ok("the walk-in asks for forward movement", intent.move == Vector2(0.0, 1.0))
	_ok("the walk-in aims at the rest point",
		absf(angle_difference(intent.heading, PI * 0.5)) < 0.001,
		"(heading %.4f)" % intent.heading)
	_ok("the walk-in runs while it is far out", intent.run)

	# Now standing on it.
	_step(src, body, REST_POS, intent, true)
	_ok("arriving switches to TURN_TO_HEADING",
		src._replay_phase == NPCIntentSourceScript.ReplayPhase.TURN_TO_HEADING)
	_ok("the turn asks for no movement", intent.move == Vector2.ZERO)
	_ok("the turn does not travel", not intent.run)
	var turned_from := body.rotation.y
	_ok("the turn moves the body's own yaw", not is_equal_approx(turned_from, REST_HEADING + PI))

	var guard := 0
	while src._replay_phase == NPCIntentSourceScript.ReplayPhase.TURN_TO_HEADING and guard < 600:
		_step(src, body, REST_POS, intent, true)
		guard += 1
	_ok("the turn completes", src._replay_phase == NPCIntentSourceScript.ReplayPhase.REPLAYING,
		"(%d frames)" % guard)
	_ok("it ends on the recorded heading",
		absf(angle_difference(body.rotation.y, REST_HEADING)) <= NPCIntentSourceScript.REPLAY_YAW_TOL,
		"(off by %.4f rad)" % angle_difference(body.rotation.y, REST_HEADING))
	body.free()


func _check_tape_is_fed_verbatim() -> void:
	print("\n--- one recorded frame per physics frame, in order ---")
	var armed := _armed()
	var src: NPCIntentSource = armed[1]
	var body: CharacterBody3D = armed[2]
	var idx: int = armed[3]
	var intent := CharacterIntent.new()
	var tape := _tape()

	# Skip the walk-in and the turn: start already on the mark and facing right.
	body.rotation.y = REST_HEADING
	_step(src, body, REST_POS, intent, true)
	_ok("starting on the mark rolls the tape straight away",
		src._replay_phase == NPCIntentSourceScript.ReplayPhase.REPLAYING)
	_ok("the first frame of the tape goes in on that same step", src._replay_frame == 1)

	var mismatches := 0
	var jump_frames := 0
	var fed := 0
	for i in range(1, 20):
		_step(src, body, REST_POS, intent, true)
		var want: Dictionary = tape[i]
		if not is_equal_approx(intent.heading, float(want.heading)) \
				or intent.run != bool(want.run) \
				or intent.move != Vector2(float(want.move[0]), float(want.move[1])):
			mismatches += 1
		if intent.jump:
			jump_frames += 1
		fed += 1
	_ok("every ground frame matches the tape", mismatches == 0,
		"(%d of %d off)" % [mismatches, fed])
	_ok("the tape's jump fires exactly once", jump_frames == 1, "(%d)" % jump_frames)
	_ok("the take-off is latched", src._replay_fired)

	# Airborne: keep feeding until the tape runs out, then land.
	var air := 0
	while src._replay_phase == NPCIntentSourceScript.ReplayPhase.REPLAYING and air < 200:
		_step(src, body, REST_POS + Vector3(0.0, 1.0, 0.0), intent, false)
		air += 1
	_ok("the tape runs out in the air", air > 0 and air < 200, "(%d air frames)" % air)

	_repaths = 0
	var landed := 0
	while src._replay_active() and landed < 60:
		_step(src, body, NavGrid.foot(TO_CELL) + Vector3(0.02, 0.0, 0.0), intent, true)
		landed += 1
	_ok("landing ends the replay", not src._replay_active(), "(%d frames)" % landed)
	_ok("the leg is marked done", src._replay_done_index == idx)
	_ok("landing central goes straight to a repath", _repaths == 1 and not src._is_centering,
		"(%d repaths)" % _repaths)
	_ok("the leg is not picked up again", not src._leg_is_special(idx))
	body.free()


# --- landing re-centring ----------------------------------------------------

func _check_landing_center() -> void:
	print("\n--- a landing near the rim walks to the middle of the block first ---")
	var grid := _grid()
	var src := _source(grid)
	var path := PackedVector3Array([
		NavGrid.foot(Vector3i(-1, 2, 0)),
		NavGrid.foot(TO_CELL),
		NavGrid.foot(Vector3i(7, 2, 0)),
	])
	src.set_plan(path, PackedInt32Array([NavGrid.Move.WALK, NavGrid.Move.JUMP,
		NavGrid.Move.WALK]), path[2])
	src._path_index = 1

	var rim := NavGrid.foot(TO_CELL) + Vector3(0.42, 0.0, 0.0)
	_ok("a rim landing is corrected", src._begin_landing_center(rim, true))
	_ok("it aims at the cell centre",
		src._center_target.is_equal_approx(Vector3(NavGrid.foot(TO_CELL).x, rim.y, NavGrid.foot(TO_CELL).z)),
		"(%v)" % src._center_target)
	_ok("the repath waits for it", src._center_repath)

	src._is_centering = false
	var central := NavGrid.foot(TO_CELL) + Vector3(0.1, 0.0, 0.0)
	_ok("a landing already central is left alone", not src._begin_landing_center(central, true))

	src._path_index = 2
	_ok("a rim landing on the goal's own cell is left alone",
		not src._begin_landing_center(NavGrid.foot(Vector3i(7, 2, 0)) + Vector3(0.42, 0.0, 0.0), true))
	_ok("the leg index does not decide it - only the cell does",
		src._begin_landing_center(rim, true))


# --- retry is bounded -------------------------------------------------------

func _check_attempts_bounded() -> void:
	print("\n--- a recording that keeps failing gives the leg back ---")
	var armed := _armed()
	var src: NPCIntentSource = armed[1]
	var started := 0
	for i in range(NPCIntentSourceScript.REPLAY_MAX_ATTEMPTS + 2):
		if src._begin_special_replay():
			started += 1
		src._reset_replay()
	_ok("replays stop after the attempt limit",
		started == NPCIntentSourceScript.REPLAY_MAX_ATTEMPTS,
		"(%d of %d tries)" % [started, NPCIntentSourceScript.REPLAY_MAX_ATTEMPTS + 2])
	(armed[2] as CharacterBody3D).free()


# --- sequential recording and multi-path isolation --------------------------

func _check_multi_path_isolation() -> void:
	print("\n--- multiple recorded paths remain isolated and never leak or mirror the latest ---")
	var SpecialPathRecorderScript = preload("res://scripts/special_path_recorder.gd")
	var rec = SpecialPathRecorderScript.new()
	var grid := _grid()
	rec.set_nav_grid(grid)
	rec.path_recorded.connect(grid.add_special_path)

	# Mock body
	var body := CharacterBody3D.new()

	# Record Path 1: Heading = 1.0, 10 frames
	rec._reset()
	rec._state = SpecialPathRecorderScript.State.GROUND_RECORDING
	rec._start_cell = Vector3i(-1, 2, 0)
	rec._rest_pos = Vector3(-1.0, 2.0, 0.0)
	rec._rest_heading = 1.0
	rec._takeoff_pos = Vector3(-0.5, 2.0, 0.0)
	rec._takeoff_speed = 3.6
	rec._takeoff_vel = Vector3(3.6, 0.0, 0.0)
	for i in range(10):
		rec._trajectory_samples.append({"p": [float(i), 2.0, 0.0], "heading": 1.0, "run": true, "jump": i == 9, "grounded": true})
	rec._state = SpecialPathRecorderScript.State.AIRBORNE_RECORDING
	rec._landing_pos = Vector3(5.0, 2.0, 0.0)
	rec._finalize_recording()

	var path1: Dictionary = grid.get_special_paths()[0]
	var path1_traj: Array = path1.get("trajectory", [])
	_ok("Path 1 recorded 10 frames", path1_traj.size() == 10)
	_ok("Path 1 heading is 1.0", is_equal_approx(float(path1_traj[0].get("heading")), 1.0))

	# Record Path 2: Heading = 2.5, 25 frames
	rec._reset()
	rec._state = SpecialPathRecorderScript.State.GROUND_RECORDING
	rec._start_cell = Vector3i(5, 2, 0)
	rec._rest_pos = Vector3(5.0, 2.0, 0.0)
	rec._rest_heading = 2.5
	rec._takeoff_pos = Vector3(5.5, 2.0, 0.0)
	rec._takeoff_speed = 3.6
	rec._takeoff_vel = Vector3(3.6, 0.0, 0.0)
	for i in range(25):
		rec._trajectory_samples.append({"p": [5.0 + float(i), 2.0, 0.0], "heading": 2.5, "run": true, "jump": i == 24, "grounded": true})
	rec._state = SpecialPathRecorderScript.State.AIRBORNE_RECORDING
	rec._landing_pos = Vector3(9.0, 2.0, 0.0)
	rec._finalize_recording()

	var paths := grid.get_special_paths()
	_ok("Both paths stored in grid", paths.size() == 2)
	var p1_after: Dictionary = paths[0]
	var p2_after: Dictionary = paths[1]
	_ok("Path 1 STILL has 10 frames after Path 2 was recorded", (p1_after.get("trajectory", []) as Array).size() == 10)
	_ok("Path 1 STILL has heading 1.0", is_equal_approx(float(p1_after["trajectory"][0].get("heading")), 1.0))
	_ok("Path 2 has 25 frames", (p2_after.get("trajectory", []) as Array).size() == 25)
	_ok("Path 2 has heading 2.5", is_equal_approx(float(p2_after["trajectory"][0].get("heading")), 2.5))

	body.free()
