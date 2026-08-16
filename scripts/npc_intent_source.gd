class_name NPCIntentSource
extends IntentSource
## Standardized NPC intent source: follows a NavGrid plan, climbs what the body
## can climb, steers around what blocks it, and runs scripted task sequences.
##
## Invariant: every capability threshold used here is read off the driven body,
## never written as a literal - the plan and the execution have to agree.

## Path could not be advanced for `repath_after` seconds. Owner recomputes.
signal repath_requested(from_pos: Vector3, target: Vector3)
## Last waypoint reached.
signal path_finished(target: Vector3)
## Plan handed over was already known to fall short of the target.
signal path_blocked(target: Vector3, reachable: Vector3)
## Reserved for the block-placing bot: a BUILD leg came up at `coord`.
@warning_ignore("unused_signal")
signal build_requested(coord: Vector3i)

## Target path points in world space.
var _path := PackedVector3Array()
## How each point is reached, as NavGrid.Move. Parallel to _path when present.
var _moves := PackedInt32Array()
var _path_index := 0
var _target_pos := Vector3.ZERO
var _has_target := false
var _plan_complete := true

## Movement gait state.
var _run := true
var _crouch := false

## Horizontal distance at which a waypoint counts as reached.
var _arrival_distance := 0.45
## Height difference a waypoint tolerates before it counts as a step to take
## rather than a place already stood. Set from the body's climb_min_height.
var _step_tolerance := 0.45

## Action triggers.
var _queued_jump := false
var _queued_roll := false
var _queued_buttons := 0

## Body limits, cached on first poll. See _cache_limits().
var _limits_ready := false
var _climb_min := 0.5
var _climb_max := 2.2
var _jump_rise := 0.9
var _walk_speed := 1.1
var _run_speed := 3.6
var _reach := 0.75
## Body radius and the rate it chases its target speed at. Both are needed to
## work out where a run-jump has to leave the ground from.
var _radius := 0.3
var _accel := 14.0

## Seconds between climb requests, so a body walking up to a wall does not
## re-arm the jump buffer every frame.
var _climb_cooldown := 0.0
const CLIMB_INTERVAL := 0.35

## Obstruction handling. See _drive_avoidance().
## Fraction of the asked-for speed below which the body counts as obstructed.
const STUCK_SPEED_RATIO := 0.3
## Seconds of obstruction before immediate repath.
const AVOID_AFTER := 0.35
const REPATH_AFTER := 0.5
## Seconds a chosen detour direction is committed to.
const AVOID_HOLD := 0.6

var _stuck_time := 0.0
var _avoid_dir := Vector3.ZERO
var _avoid_left := 0.0
var _repath_cooldown := 0.0
var _repath_queued := false
var _is_climbing := false
var _was_climbing := false
var _repath_pending_during_climb := false
var _nav_grid: NavGrid = null
var _last_body_pos := Vector3.ZERO

## Gap-jump execution. See _drive_jump().
enum JumpPhase { NONE, CENTER, BACK_UP, APPROACH, AIRBORNE }
## How far past the rim a take-off may still be triggered, metres.
const RIM_SLACK := 0.12
## Sample step of the runway probe, metres.
const RIM_STEP := 0.1
## Furthest that probe looks, metres.
const RIM_LIMIT := 6.0
## Cosine of the widest angle between the body's travel and the jump line that
## still counts as lined up.
const JUMP_ALIGN := 0.97
## Fraction of run_speed a run-up may be asked to deliver. The chase approaches
## its target asymptotically and never arrives, so asking for the whole of it
## would make every run-up look infinitely long.
const RUN_ASYMPTOTE := 0.98
## Seconds an approach or a retreat may take before the plan is given up on.
const JUMP_APPROACH_MAX := 3.0
const JUMP_BACK_UP_MAX := 1.2
## Seconds a fired jump is held airborne before a floor reading is believed. The
## body is still standing on the frame the request goes in.
const AIRBORNE_GRACE := 0.1

var _jump_phase := JumpPhase.NONE
## Waypoint index the current jump is aimed at. -1 when no jump is in hand.
var _jump_index := -1
var _jump_done_index := -1
## Set once the arc has been seen to fall SHORT of the waypoint during this
## approach. The take-off fires on the crossing from short to long, so that the
## landing overshoots by at most one frame of travel; without the latch a body
## that arrives already too fast fires on its first frame and lands long.
var _jump_armed := false
## A retreat has already been tried for this leg.
var _jump_backed := false
var _jump_timer := 0.0
var _coyote_pending := false
var _coyote_timer := 0.0

## Zero-speed jump recovery state.
var _jump_tracking := false
var _jump_start_pos := Vector3.ZERO
var _jump_start_speed := 0.0
var _jump_air_time := 0.0
var _zero_jump_centered := false

## Landing re-centring. See _begin_landing_center().
## Offset from the landing cell's centre a landing has to beat, metres.
const LAND_CENTER_TOL := 0.15
## Offset at which the correction counts as done, metres.
const CENTER_ARRIVE := 0.08
## Seconds the correction may take before it is given up on.
const CENTER_MAX := 1.2

var _is_centering := false
var _center_target := Vector3.ZERO
var _center_timer := 0.0
## A repath held back until the correction finishes.
var _center_repath := false

## Recorded special-path replay. See _drive_special_replay().
enum ReplayPhase { NONE, WALK_TO_REST, TURN_TO_HEADING, REPLAYING, SETTLE }
## Horizontal distance at which the recorded rest point counts as reached, m.
const REPLAY_REST_TOL := 0.1
## Yaw error at which the recorded start facing counts as matched, radians.
const REPLAY_YAW_TOL := 0.02
## Distance from the rest point under which the walk-in drops to a walk, metres.
const REPLAY_WALK_SLOW := 1.0
## Seconds a phase may take before the recording is abandoned for ordinary
## gap-jump steering.
const REPLAY_WALK_MAX := 6.0
const REPLAY_TURN_MAX := 2.0
const REPLAY_SETTLE_MAX := 3.0
## Replays of one recording before ordinary steering takes the leg instead.
const REPLAY_MAX_ATTEMPTS := 3

## Waypoint index -> recorded path dict, from NavGrid.find_path().special_links.
var _special_links := {}
var _replay_phase := ReplayPhase.NONE
var _replay_traj: Array = []
## Next tape frame to feed. One recorded frame per physics frame: the recorder
## sampled on the same tick, so frame index and elapsed time are one clock.
var _replay_frame := 0
var _replay_timer := 0.0
## Waypoint index the replay is aimed at. -1 when none is in hand.
var _replay_index := -1
var _replay_done_index := -1
var _replay_rest := Vector3.ZERO
var _replay_heading := 0.0
## Seconds off the ground since the tape's jump frame went in.
var _replay_air := 0.0
## The tape's jump frame has been played.
var _replay_fired := false
## Recorded path id -> replays started. Bounds retry after a short landing.
var _replay_attempts := {}

## Automated task sequence state.
var _task_queue: Array = []
var _current_task_index := -1
var _task_timer := 0.0
var _is_sequence_running := false
var _sequence_status := "Idle"


## Bind NavGrid instance for map change observation and proactive path validation.
func bind_nav_grid(nav: NavGrid) -> void:
	if _nav_grid != null and _nav_grid.is_connected("grid_changed", _on_grid_changed):
		_nav_grid.grid_changed.disconnect(_on_grid_changed)
	_nav_grid = nav
	if _nav_grid != null:
		_nav_grid.grid_changed.connect(_on_grid_changed)


func _on_grid_changed() -> void:
	if not _has_target:
		return
	if _is_climbing:
		_repath_pending_during_climb = true
	elif not _repath_queued:
		_repath_queued = true
		call_deferred("_deferred_repath")


## A replay owns its own timing; re-planning under it would swap the tape out
## mid-arc. The landing repaths anyway, so the grid change is only deferred.
func _deferred_repath() -> void:
	_repath_queued = false
	if _has_target and not _is_climbing and not _replay_active():
		_repath_cooldown = 0.0
		repath_requested.emit(_last_body_pos, _target_pos)
	elif _has_target and _is_climbing:
		_repath_pending_during_climb = true


## Set navigation path to target position.
func set_path(path: PackedVector3Array, target: Vector3) -> void:
	set_plan(path, PackedInt32Array(), target, true)


## Install a NavGrid plan. `moves` may be empty; `complete` false means the path
## stops at the nearest reachable cell instead of `target`. `special_links` maps
## a waypoint index to the recording its leg is replayed from.
## Post: _path_index == 0, obstruction state cleared.
func set_plan(path: PackedVector3Array, moves: PackedInt32Array, target: Vector3,
		complete := true, special_links := {}) -> void:
	_path = path
	_moves = moves
	_special_links = special_links
	_target_pos = target
	_path_index = 0
	_has_target = not _path.is_empty()
	_plan_complete = complete
	_reset_obstruction()
	_reset_jump()
	_reset_replay()
	_replay_done_index = -1
	_zero_jump_centered = false
	_is_centering = false
	_center_repath = false
	_jump_tracking = false
	_jump_air_time = 0.0


## Install a plan straight from NavGrid.find_path().
func set_plan_result(result: Dictionary) -> void:
	set_plan(result.get("points", PackedVector3Array()),
		result.get("moves", PackedInt32Array()),
		result.get("goal", Vector3.ZERO),
		bool(result.get("complete", true)),
		result.get("special_links", {}))


## Clear current navigation target.
func clear_target() -> void:
	_path.clear()
	_moves.clear()
	_special_links = {}
	_path_index = 0
	_has_target = false
	_reset_obstruction()
	_reset_jump()
	_reset_replay()
	_replay_done_index = -1
	_replay_attempts.clear()
	_zero_jump_centered = false
	_is_centering = false
	_center_repath = false
	_jump_tracking = false
	_jump_air_time = 0.0


func _reset_obstruction() -> void:
	_stuck_time = 0.0
	_avoid_left = 0.0
	_avoid_dir = Vector3.ZERO


func _reset_jump() -> void:
	_jump_phase = JumpPhase.NONE
	_jump_index = -1
	_jump_done_index = -1
	_jump_armed = false
	_jump_backed = false
	_jump_timer = 0.0
	_coyote_pending = false
	_coyote_timer = 0.0


## Drops the tape in hand. Leaves _replay_done_index alone: it is what stops the
## leg just replayed from being picked up again on the very next frame.
func _reset_replay() -> void:
	_replay_phase = ReplayPhase.NONE
	_replay_traj = []
	_replay_frame = 0
	_replay_timer = 0.0
	_replay_index = -1
	_replay_air = 0.0
	_replay_fired = false


## A recording is being walked into, aligned to or played back.
func _replay_active() -> bool:
	return _replay_phase != ReplayPhase.NONE


## Check if navigation target is active.
func has_target() -> bool:
	return _has_target


## Check if target position has been reached.
func has_reached_target() -> bool:
	return not _has_target


## Whether the installed plan actually reaches the requested target.
func plan_is_complete() -> bool:
	return _plan_complete


## Get active target position.
func get_target_position() -> Vector3:
	return _target_pos


## Get active navigation path points.
func get_path() -> PackedVector3Array:
	return _path


## Index of the waypoint being walked to. -1 when idle.
func get_path_index() -> int:
	return _path_index if _has_target else -1


## Seconds the body has been failing to make progress. 0.0 when moving freely.
func obstructed_time() -> float:
	return _stuck_time


## Toggle sprint gait.
func set_run(enabled: bool) -> void:
	_run = enabled


## Toggle crouch gait.
func set_crouch(enabled: bool) -> void:
	_crouch = enabled


## Queue single jump action.
func request_jump() -> void:
	_queued_jump = true


## Queue single roll action.
func request_roll() -> void:
	_queued_roll = true


## Queue combat button action.
func request_button(button: String) -> void:
	_queued_buttons |= int(CharacterIntent.BUTTONS.get(button, 0))


## Execute predefined sequence of task dictionaries.
func execute_sequence(tasks: Array) -> void:
	_task_queue = tasks.duplicate(true)
	_current_task_index = 0
	_task_timer = 0.0
	_is_sequence_running = not _task_queue.is_empty()
	if _is_sequence_running:
		_start_current_task()
	else:
		_sequence_status = "Idle"


## Stop running task sequence.
func stop_sequence() -> void:
	_is_sequence_running = false
	_task_queue.clear()
	_current_task_index = -1
	_sequence_status = "Stopped"
	clear_target()


## Check if task sequence is executing.
func is_sequence_running() -> bool:
	return _is_sequence_running


## Get human readable status of task sequence.
func get_sequence_status() -> String:
	return _sequence_status


func _start_current_task() -> void:
	if _current_task_index < 0 or _current_task_index >= _task_queue.size():
		_is_sequence_running = false
		_sequence_status = "Completed"
		return

	var task: Dictionary = _task_queue[_current_task_index]
	var type: String = task.get("type", "")
	_sequence_status = "Task %d/%d: %s" % [_current_task_index + 1, _task_queue.size(), type]

	match type:
		"move_to":
			var target: Vector3 = task.get("target", Vector3.ZERO)
			var path: PackedVector3Array = task.get("path", PackedVector3Array([target]))
			_run = task.get("run", true)
			set_plan(path, task.get("moves", PackedInt32Array()), target,
				bool(task.get("complete", true)))
		"wait":
			_task_timer = float(task.get("duration", 1.0))
			clear_target()
		"jump":
			request_jump()
			_task_timer = 0.5
		"crouch":
			_crouch = task.get("enabled", true)
			_task_timer = float(task.get("duration", 1.0))
		"attack":
			request_button(task.get("button", "attack"))
			_task_timer = 0.8
		_:
			_advance_task()


func _advance_task() -> void:
	_current_task_index += 1
	if _current_task_index < _task_queue.size():
		_start_current_task()
	else:
		_is_sequence_running = false
		_sequence_status = "Completed"


func _update_sequence(delta: float) -> void:
	if not _is_sequence_running or _current_task_index < 0:
		return

	var task: Dictionary = _task_queue[_current_task_index]
	var type: String = task.get("type", "")

	match type:
		"move_to":
			if has_reached_target():
				_advance_task()
		"wait", "jump", "crouch", "attack":
			_task_timer -= delta
			if _task_timer <= 0.0:
				if type == "crouch":
					_crouch = false
				_advance_task()


## Reads the body's own movement limits once. Everything the navigation decides
## - what counts as a step, when to ask for a climb, how close to a wall it has
## to be - is derived from these rather than written down twice.
func _cache_limits(body: Node) -> void:
	if _limits_ready or body == null:
		return
	_limits_ready = true
	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	_climb_min = _num(body, "climb_min_height", _climb_min)
	_climb_max = _num(body, "climb_max_height", _climb_max)
	_walk_speed = _num(body, "walk_speed", _walk_speed)
	_run_speed = _num(body, "run_speed", _run_speed)
	var jump_speed: float = _num(body, "jump_speed", 4.7)
	_jump_rise = maxf((jump_speed * jump_speed) / (2.0 * maxf(gravity, 0.01)) - NavGrid.JUMP_CLEAR, 0.0)
	# The distance _find_ledge() reaches forward from the body's centre.
	_radius = NavGrid.body_radius(body, _radius)
	_accel = _num(body, "acceleration", _accel)
	_reach = _radius + _num(body, "climb_reach", 0.45)
	# A rise under this is a place already stood on, not a step to take.
	_step_tolerance = minf(_climb_min, _jump_rise) * 0.8
	_arrival_distance = maxf(_radius + 0.15, 0.45)


static func _num(body: Node, prop: String, fallback: float) -> float:
	var v: Variant = body.get(prop)
	return float(v) if v != null else fallback


## Whether a rise of dh is something the body can take at all.
func _can_rise(dh: float) -> bool:
	if dh <= _jump_rise:
		return true
	return dh >= _climb_min and dh <= _climb_max


## Poll decision source to update intent object.
func poll(body: Node, delta: float, intent: CharacterIntent) -> void:
	_cache_limits(body)
	_update_sequence(delta)
	_climb_cooldown = maxf(_climb_cooldown - delta, 0.0)
	_repath_cooldown = maxf(_repath_cooldown - delta, 0.0)
	_avoid_left = maxf(_avoid_left - delta, 0.0)

	# A climb draws the body along its own path; steering it mid-take puts a
	# shoulder through the ledge. Freeze until the state clears.
	var state_val: int = int(body.get("state")) if body != null else -1
	_is_climbing = (state_val == PlayerController.State.CLIMBING)
	if _is_climbing:
		if _repath_queued:
			_repath_pending_during_climb = true
			_repath_queued = false
		intent.move = Vector2.ZERO
		intent.run = false
		_stuck_time = 0.0
		_was_climbing = true
		return

	var body_3d := body as Node3D
	var body_pos := body_3d.global_position if body_3d != null else Vector3.ZERO
	var char_body := body as CharacterBody3D

	if _was_climbing:
		_was_climbing = false
		_last_body_pos = body_pos
		_repath_cooldown = 0.0
		if _has_target:
			_repath_cooldown = 0.1
			repath_requested.emit(_last_body_pos, _target_pos)

	_last_body_pos = body_pos

	var grounded: bool = char_body == null or char_body.is_on_floor()

	if _jump_tracking:
		if not grounded:
			_jump_air_time += delta
		elif _jump_air_time >= AIRBORNE_GRACE:
			_jump_tracking = false
			var horiz_disp := Vector2(body_pos.x - _jump_start_pos.x, body_pos.z - _jump_start_pos.z).length()
			# A replay lands on its own terms - see _finish_special_replay().
			if _replay_active():
				pass
			elif _jump_start_speed < 0.1 and horiz_disp < 0.25 and not _zero_jump_centered:
				# Jumped straight up and got nowhere: it was standing on a rim.
				# Square up before the leg is tried again.
				_zero_jump_centered = true
				_begin_landing_center(body_pos, false)
			elif _has_target and not _begin_landing_center(body_pos, true):
				_repath_cooldown = 0.1
				repath_requested.emit(body_pos, _target_pos)
	elif not grounded and state_val == PlayerController.State.JUMPING:
		_jump_tracking = true
		_jump_start_pos = body_pos
		_jump_start_speed = float(body.get("_air_speed")) if body != null and body.get("_air_speed") != null else 0.0
		_jump_air_time = delta

	intent.crouch = _crouch
	intent.move = Vector2.ZERO
	intent.run = false

	if _has_target:
		_drive_navigation(char_body, body_pos, delta, intent)

	if _queued_jump:
		intent.jump = true
		_queued_jump = false
	if _queued_roll:
		intent.roll = true
		_queued_roll = false
	if _queued_buttons != 0:
		intent.buttons |= _queued_buttons
		_queued_buttons = 0

	if (intent.jump or _jump_phase == JumpPhase.AIRBORNE) and grounded and not _jump_tracking:
		_jump_tracking = true
		_jump_start_pos = body_pos
		_jump_start_speed = Vector2(char_body.velocity.x, char_body.velocity.z).length() if char_body != null else 0.0
		_jump_air_time = 0.0


func _drive_navigation(char_body: CharacterBody3D, body_pos: Vector3, delta: float,
		intent: CharacterIntent) -> void:
	if _path_index >= _path.size():
		_finish()
		return

	var grounded: bool = char_body == null or char_body.is_on_floor()

	# A recording owns every frame of its own run-up and arc, so it is asked
	# before anything below can repath, steer or re-time it.
	if _drive_special_replay(char_body, body_pos, delta, intent, grounded):
		return

	if _nav_grid != null and not _nav_grid.is_path_valid(_path, _path_index) and _repath_cooldown <= 0.0:
		_repath_cooldown = 0.5
		repath_requested.emit(body_pos, _target_pos)

	# A committed arc owns the frame. Consuming its waypoint from mid-air would
	# hand the body back to ordinary steering while it is still flying, and
	# ordinary steering asks for movement - which is the one thing that must not
	# happen up there. See _drive_flight().
	if _jump_phase == JumpPhase.AIRBORNE or (_jump_tracking and not grounded and _jump_start_speed < 0.1):
		_jump_timer += delta
		if not grounded or _jump_timer < AIRBORNE_GRACE:
			_drive_flight(intent)
			return
		_jump_phase = JumpPhase.NONE
		_jump_done_index = _path_index
		_repath_cooldown = 0.0
		# Square up on the landing cell before the next leg is planned: a body
		# still on the rim reads as about to fall off it, and plans a hurried
		# take-off it has no runway for.
		if _has_target and not _is_centering and not _begin_landing_center(body_pos, true):
			_repath_cooldown = 0.1
			repath_requested.emit(body_pos, _target_pos)

	if _is_centering:
		_center_timer += delta
		var to_center := Vector3(_center_target.x - body_pos.x, 0.0, _center_target.z - body_pos.z)
		var dist_to_center := to_center.length()
		if dist_to_center > CENTER_ARRIVE and _center_timer < CENTER_MAX:
			var dir := _steer(char_body, body_pos, to_center / dist_to_center, delta)
			intent.heading = atan2(dir.x, dir.z)
			intent.move = Vector2(0.0, 1.0)
			intent.run = false
			return
		_is_centering = false
		_reset_jump()
		if _center_repath:
			_center_repath = false
			if _has_target:
				_repath_cooldown = 0.1
				repath_requested.emit(body_pos, _target_pos)
				return

	var wp := _path[_path_index]
	var flat := Vector3(wp.x - body_pos.x, 0.0, wp.z - body_pos.z)
	var horiz := flat.length()
	var dy := wp.y - body_pos.y

	# Arrival is a 3D test. Zeroing the height first - which is what this used to
	# do - calls a waypoint at the top of a wall reached while still standing at
	# its foot, and the body then walks diagonally into the wall chasing the one
	# after it.
	if horiz <= _arrival_distance and absf(dy) <= _step_tolerance:
		_path_index += 1
		_reset_obstruction()
		if _path_index >= _path.size():
			_finish()
			return
		wp = _path[_path_index]
		flat = Vector3(wp.x - body_pos.x, 0.0, wp.z - body_pos.z)
		horiz = flat.length()
		dy = wp.y - body_pos.y

	if horiz <= 0.01:
		return

	var wanted := flat / horiz

	if _drive_jump(char_body, body_pos, wanted, horiz, delta, intent, grounded):
		return

	# Close to the wall the next waypoint sits on top of, and the rise is one the
	# body can take: ask. The controller's own ledge probe decides climb or jump.
	if dy > _step_tolerance and _can_rise(dy) and _climb_cooldown <= 0.0:
		var at_wall: bool = char_body != null and char_body.is_on_wall()
		if horiz <= _reach or at_wall:
			request_jump()
			_climb_cooldown = CLIMB_INTERVAL

	var dir := _steer(char_body, body_pos, wanted, delta)
	intent.heading = atan2(dir.x, dir.z)
	intent.move = Vector2(0.0, 1.0)
	intent.run = _run and _avoid_left <= 0.0


## The committed arc: asks for nothing at all.
##
## _drive_air() only touches the horizontal velocity while a move is being asked
## for, and what it does then is lerp it towards a vector of the SAME magnitude
## in the heading's direction - a chord between two equal-length vectors, which
## is shorter than either. Every misaligned frame of air steering therefore bleeds
## speed, which is why a jump that left the ground at full pace could still come
## up short. Asking for nothing freezes the horizontal velocity, and the flight
## is then exactly the arc NavGrid planned.
func _drive_flight(intent: CharacterIntent) -> void:
	if _path_index < _path.size() and _jump_start_speed >= 0.1:
		var wp := _path[_path_index]
		var flat := Vector3(wp.x - _last_body_pos.x, 0.0, wp.z - _last_body_pos.z)
		if flat.length_squared() > 0.001:
			intent.heading = atan2(flat.x, flat.z)
			intent.move = Vector2(0.0, 1.0)
			intent.run = true
			_stuck_time = 0.0
			return
	intent.move = Vector2.ZERO
	intent.run = false
	_stuck_time = 0.0


# --- landing re-centring ----------------------------------------------------

## Starts a walk to the centre of the cell just landed on when the landing sat
## near its rim. `then_repath` holds the leg's repath back until the correction
## finishes, so the next plan is made from the middle of the block rather than
## from its edge.
## Pre: body grounded. Post: _is_centering iff true was returned.
func _begin_landing_center(body_pos: Vector3, then_repath: bool) -> bool:
	# Landed on the goal's own cell: the point to stand on there is the one the
	# caller picked, not the cell centre, and nothing follows it to line up for.
	# The test is the cell rather than the waypoint index - a straight run is one
	# leg however many cells long, so the last index is reached early.
	if not _path.is_empty():
		var goal := _path[_path.size() - 1]
		if Vector2i(int(floor(goal.x)), int(floor(goal.z))) \
				== Vector2i(int(floor(body_pos.x)), int(floor(body_pos.z))):
			return false
	var center := _cell_center(body_pos)
	if Vector2(center.x - body_pos.x, center.z - body_pos.z).length() <= LAND_CENTER_TOL:
		return false
	_center_target = center
	_center_timer = 0.0
	_center_repath = then_repath
	_is_centering = true
	return true


## Centre of the cell the body stands in, at the body's own height.
func _cell_center(pos: Vector3) -> Vector3:
	if _nav_grid != null:
		var node := _nav_grid.standing_node(pos)
		if node != NavGrid.NO_CELL:
			var f := NavGrid.foot(node)
			return Vector3(f.x, pos.y, f.z)
	return Vector3(floor(pos.x) + 0.5, pos.y, floor(pos.z) + 0.5)


# --- recorded special-path replay -------------------------------------------

## Leg `idx` is crossed by replaying a recording rather than by a planned arc.
func _leg_is_special(idx: int) -> bool:
	if idx <= 0 or idx >= _path.size():
		return false
	if idx == _replay_done_index:
		return false
	return _special_links.has(idx)


## Replays a recorded special path in place of ordinary steering. Returns true
## when it has written this frame's intent and nothing else may.
##
## The recording is a tape of what the player's hands did, one entry per physics
## frame, from a standstill through the run-up to the landing. Reproducing the
## take-off therefore means reproducing the state the body was in when it left
## the ground, which means starting from the same place, facing the same way and
## feeding the same keys on the same frames - hence the two phases before the
## tape rolls. Phases fall through within one frame, so none is spent idling on
## a transition.
func _drive_special_replay(char_body: CharacterBody3D, body_pos: Vector3,
		delta: float, intent: CharacterIntent, grounded: bool) -> bool:
	if _replay_phase == ReplayPhase.NONE and not _begin_special_replay():
		return false

	_replay_timer += delta
	_stuck_time = 0.0
	if not grounded:
		_replay_air += delta

	if _replay_phase == ReplayPhase.WALK_TO_REST:
		var flat := Vector3(_replay_rest.x - body_pos.x, 0.0, _replay_rest.z - body_pos.z)
		var dist := flat.length()
		if dist > REPLAY_REST_TOL:
			if _replay_timer >= REPLAY_WALK_MAX:
				_abort_special_replay()
				return false
			# Steered straight rather than through _steer(): the walk-in is a couple
			# of metres on the block already stood on, and _steer()'s stuck handling
			# would repath out from under the tape.
			intent.heading = atan2(flat.x, flat.z)
			intent.move = Vector2(0.0, 1.0)
			intent.run = _run and dist > REPLAY_WALK_SLOW
			return true
		_replay_phase = ReplayPhase.TURN_TO_HEADING
		_replay_timer = 0.0

	if _replay_phase == ReplayPhase.TURN_TO_HEADING:
		# Asking for no movement stops the body dead - see
		# PlayerController._drive_locomotion() - which is also why the turn is
		# written onto the rotation directly: a standing body does not chase the
		# intent's heading in third person, so there is no other way to turn on
		# the spot without travelling.
		intent.move = Vector2.ZERO
		intent.run = false
		intent.heading = _replay_heading
		if char_body != null:
			char_body.rotation.y = rotate_toward(char_body.rotation.y, _replay_heading,
				_num(char_body, "turn_rate", 24.0) * delta)
			if absf(angle_difference(char_body.rotation.y, _replay_heading)) > REPLAY_YAW_TOL \
					and _replay_timer < REPLAY_TURN_MAX:
				return true
		_replay_phase = ReplayPhase.REPLAYING
		_replay_frame = 0
		_replay_timer = 0.0
		_replay_air = 0.0

	if _replay_phase == ReplayPhase.REPLAYING:
		if _replay_fired and grounded and _replay_air >= AIRBORNE_GRACE:
			_finish_special_replay(body_pos, intent)
			return true
		if _replay_frame < _replay_traj.size():
			var sample: Dictionary = _replay_traj[_replay_frame]
			_replay_frame += 1
			var mv: Array = sample.get("move", [0.0, 0.0])
			intent.move = Vector2(float(mv[0]), float(mv[1])).limit_length(1.0)
			intent.heading = float(sample.get("heading", _replay_heading))
			intent.run = bool(sample.get("run", false))
			if bool(sample.get("jump", false)):
				request_jump()
				_replay_fired = true
			return true
		_replay_phase = ReplayPhase.SETTLE
		_replay_timer = 0.0

	# Tape run out with the body still in the air: ask for nothing, which freezes
	# the horizontal velocity the arc was launched with. See _drive_flight().
	intent.move = Vector2.ZERO
	intent.run = false
	# Grounded with airtime behind it is the landing. Grounded without any is a
	# take-off that never happened - a jump eaten by the climb probe, say - and
	# waiting out the full settle for one would stall the plan.
	if (grounded and (_replay_air >= AIRBORNE_GRACE or _replay_timer >= 0.3)) \
			or _replay_timer >= REPLAY_SETTLE_MAX:
		_finish_special_replay(body_pos, intent)
	return true


## Picks up the recording for the leg in hand.
## Post: _replay_phase past NONE iff true was returned.
func _begin_special_replay() -> bool:
	if not _leg_is_special(_path_index):
		return false
	var data: Dictionary = _special_links[_path_index]
	var traj: Array = data.get("trajectory", [])
	if traj.size() < 2:
		return false
	# A recording that keeps landing short would otherwise be re-walked forever:
	# every landing repaths, and the new plan hands back the same leg.
	var path_id := str(data.get("id", "?"))
	var tries := int(_replay_attempts.get(path_id, 0))
	if tries >= REPLAY_MAX_ATTEMPTS:
		return false
	_replay_attempts[path_id] = tries + 1

	var first: Dictionary = traj[0]
	_replay_traj = traj
	_replay_rest = _to_vec3(data.get("rest_pos"), _to_vec3(first.get("p"), _path[_path_index - 1]))
	_replay_heading = float(data.get("rest_heading", first.get("heading", 0.0)))
	_replay_index = _path_index
	_replay_frame = 0
	_replay_timer = 0.0
	_replay_air = 0.0
	_replay_fired = false
	_replay_phase = ReplayPhase.WALK_TO_REST
	return true


## Hands the leg back to ordinary steering once the tape is done with it.
func _finish_special_replay(body_pos: Vector3, intent: CharacterIntent) -> void:
	_replay_done_index = _replay_index
	_jump_done_index = _replay_index
	_reset_replay()
	intent.move = Vector2.ZERO
	intent.run = false
	if _has_target and not _is_centering and not _begin_landing_center(body_pos, true):
		_repath_cooldown = 0.1
		repath_requested.emit(body_pos, _target_pos)


## Gives up on the recording. The leg is still a gap jump, so _drive_jump() takes
## it from here - a recorded arc always counts as an extreme one, see
## _is_extreme_gap_jump().
func _abort_special_replay() -> void:
	_replay_done_index = _replay_index
	_reset_replay()


## Vector3 out of a recorded [x, y, z] array. Post: `fallback` when unreadable.
static func _to_vec3(raw: Variant, fallback: Vector3) -> Vector3:
	if raw is Vector3:
		return raw
	if raw is Array and (raw as Array).size() >= 3:
		var a: Array = raw
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback


## Runs the gap-jump legs of the plan. Returns true when it has written this
## frame's intent and ordinary steering must not.
##
## The take-off point is derived, not guessed: the arc covers `speed * t` metres
## and has to end on the waypoint, so the moment to leave the ground is when
## exactly that much distance is left. Firing on the crossing from short to long
## puts the landing within one frame of travel of the waypoint - which sits at
## the target cell's centre, leaving half a cell of margin on either side. A void
## at the limit of the body's range crosses over only at the rim, so the ledge
## take-off the longest jumps need falls out of the same rule rather than being a
## second one.
func _drive_jump(char_body: CharacterBody3D, body_pos: Vector3, wanted: Vector3,
		horiz: float, delta: float, intent: CharacterIntent, grounded: bool) -> bool:
	if not _leg_is_gap_jump(_path_index):
		_jump_phase = JumpPhase.NONE
		_jump_index = -1
		return false
	if char_body == null or _nav_grid == null:
		return false
	var cap := _nav_grid.capability()
	var land := _path[_path_index]
	var start_wp := _path[_path_index - 1] if _path_index > 0 else body_pos
	var nominal_dh := land.y - start_wp.y
	var t: float = cap.flight_time(nominal_dh)
	if is_nan(t) or t <= 0.0:
		t = cap.flight_time(land.y - body_pos.y)
	if is_nan(t) or t <= 0.0:
		return false

	if _jump_done_index == _path_index:
		return false

	if _jump_index != _path_index:
		_jump_index = _path_index
		_jump_phase = JumpPhase.CENTER if _is_extreme_gap_jump(_path_index) else JumpPhase.APPROACH
		_jump_armed = false
		_jump_backed = false
		_jump_timer = 0.0
	_jump_timer += delta

	var center_pt := start_wp
	if _nav_grid != null:
		var node := _nav_grid.standing_node(body_pos)
		if node != NavGrid.NO_CELL:
			center_pt = NavGrid.foot(node)

	var is_extreme := _is_extreme_gap_jump(_path_index)
	var is_offset_extreme := _is_offset_extreme_gap_jump(_path_index)

	var jump_wanted := wanted
	var jump_horiz := horiz

	# Offset jumps: only for Case 3 (3-cell void up 1m with secondary offset).
	if is_offset_extreme:
		var dx: float = land.x - start_wp.x
		var dz: float = land.z - start_wp.z
		var adx: float = absf(dx)
		var adz: float = absf(dz)
		if adx >= 3.5 and adz >= 0.5 and adx > adz:
			jump_wanted = Vector3(signf(dx), 0.0, 0.0)
			jump_horiz = absf(land.x - body_pos.x)
			center_pt = Vector3(center_pt.x, center_pt.y, center_pt.z + signf(dz) * 0.35)
		elif adz >= 3.5 and adx >= 0.5 and adz > adx:
			jump_wanted = Vector3(0.0, 0.0, signf(dz))
			jump_horiz = absf(land.z - body_pos.z)
			center_pt = Vector3(center_pt.x + signf(dx) * 0.35, center_pt.y, center_pt.z)

	var travel := Vector2(char_body.velocity.x, char_body.velocity.z)
	var speed := travel.length()
	var reach := speed * t
	var runway := _runway_ahead(body_pos, jump_wanted)
	# Speed the arc would need to land dead on the waypoint if it left from the
	# rim rather than from here, capped at what the chase can actually deliver.
	# A void at the limit of the body's range cannot be landed centrally at all -
	# it is crossed by leaving at the rim flat out and landing just inside the far
	# lip - and an uncapped figure would make that run-up look impossible.
	var wanted_v: float = minf(maxf(jump_horiz - runway, 0.0) / t, _run_speed * RUN_ASYMPTOTE)

	if _jump_phase == JumpPhase.CENTER:
		var to_center := Vector3(center_pt.x - body_pos.x, 0.0, center_pt.z - body_pos.z)
		var dist_to_center := to_center.length()
		if dist_to_center <= 0.08 or _jump_timer >= 1.0:
			_jump_phase = JumpPhase.APPROACH
			_jump_timer = 0.0
		else:
			var dir := _steer(char_body, body_pos, to_center / dist_to_center, delta)
			intent.heading = atan2(dir.x, dir.z)
			intent.move = Vector2(0.0, 1.0)
			intent.run = false
			return true

	if _jump_phase == JumpPhase.BACK_UP:
		var behind := _runway_ahead(body_pos, -jump_wanted)
		if runway >= _runup_distance(0.0, wanted_v) + RIM_SLACK \
				or behind <= RIM_SLACK or _jump_timer >= JUMP_BACK_UP_MAX:
			_jump_phase = JumpPhase.APPROACH
		else:
			# Facing the jump line while walking backwards down it, so no turn is
			# left to make once the run starts.
			intent.heading = atan2(jump_wanted.x, jump_wanted.z)
			intent.move = Vector2(0.0, -1.0)
			intent.run = false
			return true

	if reach < jump_horiz:
		_jump_armed = true

	var aligned: bool = speed < 0.05 \
		or travel.normalized().dot(Vector2(jump_wanted.x, jump_wanted.z)) >= JUMP_ALIGN
	var at_rim: bool = runway <= RIM_SLACK

	# Coyote run: ONLY for extreme jumps that cannot reach from the rim.
	if is_extreme and grounded and at_rim and not (_jump_armed and aligned and reach >= jump_horiz):
		intent.heading = atan2(jump_wanted.x, jump_wanted.z)
		intent.move = Vector2(0.0, 1.0)
		intent.run = true
		_coyote_pending = true
		_coyote_timer = 0.0
		return true

	# Coyote fire: keep running in air during coyote window, fire near the end.
	if not grounded and _coyote_pending:
		_coyote_timer += delta
		var delay_limit: float = 0.08
		if _coyote_timer >= delay_limit:
			request_jump()
			_coyote_pending = false
			_jump_phase = JumpPhase.AIRBORNE
			_jump_timer = 0.0
			_drive_flight(intent)
			return true
		else:
			intent.heading = atan2(jump_wanted.x, jump_wanted.z)
			intent.move = Vector2(0.0, 1.0)
			intent.run = true
			return true

	if grounded and (at_rim or (_jump_armed and aligned and reach >= jump_horiz)):
		request_jump()
		_coyote_pending = false
		_coyote_timer = 0.0
		_climb_cooldown = CLIMB_INTERVAL
		_jump_phase = JumpPhase.AIRBORNE
		_jump_timer = 0.0
		intent.heading = atan2(jump_wanted.x, jump_wanted.z)
		intent.move = Vector2.ZERO
		intent.run = false
		return true

	# No room to wind up before the rim: retreat down the jump line first. Tried
	# once per leg - a retreat that found no room will not find any on a second
	# go, and alternating the two is how a body ends up pacing on the spot.
	if grounded and not _jump_backed and _jump_timer <= 0.25 \
			and _runup_distance(speed, wanted_v) > runway:
		_jump_backed = true
		_jump_phase = JumpPhase.BACK_UP

	if _jump_timer >= JUMP_APPROACH_MAX and _repath_cooldown <= 0.0:
		_repath_cooldown = REPATH_AFTER
		_reset_jump()
		repath_requested.emit(body_pos, _target_pos)

	intent.heading = atan2(jump_wanted.x, jump_wanted.z)
	intent.move = Vector2(0.0, 1.0)
	# Sprint while the arc still falls short of the waypoint, ease off once it
	# would overshoot. Easing off is what lets the crossing be met from below: the
	# chase decelerates far harder than the closing distance shrinks, so an arc
	# that is too long drops back under the waypoint within a frame or two.
	# Alignment is deliberately not part of this - a body still turning onto the
	# line is a body that needs the throttle, and the velocity chase turns towards
	# the heading whether or not it is already there.
	intent.run = _run and reach < jump_horiz
	return true


## Leg `idx` of the plan is an arc across a void rather than a step or a walk.
## Falls back to reading the ground when the plan came with no `moves` array.
func _leg_is_gap_jump(idx: int) -> bool:
	if idx <= 0 or idx >= _path.size():
		return false
	var a := _path[idx - 1]
	var b := _path[idx]
	# Waypoints in touching cells are a step, whatever the plan calls them.
	if Vector2(b.x - a.x, b.z - a.z).length() < 1.2:
		return false
	if idx < _moves.size() and (_moves[idx] == NavGrid.Move.JUMP or _moves[idx] == NavGrid.Move.SPECIAL_JUMP):
		return true
	return _void_between(a, b)


## Leg `idx` spans an extreme void (4-cell flat/down void, 3-cell void up 1 block, or offset jumps, or special jump).
func _is_extreme_gap_jump(idx: int) -> bool:
	if idx <= 0 or idx >= _path.size():
		return false
	if idx < _moves.size() and _moves[idx] == NavGrid.Move.SPECIAL_JUMP:
		return true
	var a := _path[idx - 1]
	var b := _path[idx]
	var horiz_dist := Vector2(b.x - a.x, b.z - a.z).length()
	var dy := b.y - a.y
	var dx := absf(b.x - a.x)
	var dz := absf(b.z - a.z)

	# Case 1: 4-cell void flat or down (span >= 4.5m)
	if horiz_dist >= 4.5:
		return true

	# Case 2: 3-cell void up 1m (span >= 3.5m, dy >= 0.5m)
	if dy >= 0.5 and (dx >= 3.5 or dz >= 3.5):
		return true

	# Case 3: 2-forward 2-offset up 1m diagonal (dx >= 2.5 and dz >= 2.5 and dy >= 0.5)
	if dy >= 0.5 and dx >= 2.5 and dz >= 2.5 and horiz_dist >= 3.8:
		return true

	return false


func _is_offset_extreme_gap_jump(idx: int) -> bool:
	if idx <= 0 or idx >= _path.size():
		return false
	var a := _path[idx - 1]
	var b := _path[idx]
	var dy := b.y - a.y
	var dx := absf(b.x - a.x)
	var dz := absf(b.z - a.z)

	# Case 3: 3-cell void up 1m with secondary axis offset
	if dy >= 0.5:
		if dx >= 3.5 and dz >= 0.5 and dx > dz:
			return true
		if dz >= 3.5 and dx >= 0.5 and dz > dx:
			return true

	return false


## Some column strictly between `a` and `b` has nowhere to stand at `a`'s level.
func _void_between(a: Vector3, b: Vector3) -> bool:
	if _nav_grid == null:
		return false
	var span := Vector2(b.x - a.x, b.z - a.z)
	var samples := int(ceil(span.length() / RIM_STEP))
	var level := int(floor(a.y + 0.05))
	for i in range(1, samples):
		var p := Vector2(a.x, a.z) + span * (float(i) / float(samples))
		if not _nav_grid.is_standable(Vector3i(int(floor(p.x)), level, int(floor(p.y)))):
			return true
	return false


## Metres of standable ground ahead of `pos` along `dir` before the rim, capped
## at RIM_LIMIT. Measured from the body's centre, which is where it stops being
## held up. Pre: dir is a horizontal unit vector.
func _runway_ahead(pos: Vector3, dir: Vector3) -> float:
	if _nav_grid == null:
		return RIM_LIMIT
	var level := int(floor(pos.y + 0.05))
	var s := 0.0
	while s < RIM_LIMIT:
		var p := pos + dir * (s + RIM_STEP)
		if not _nav_grid.is_standable(Vector3i(int(floor(p.x)), level, int(floor(p.z)))):
			return s
		s += RIM_STEP
	return RIM_LIMIT


## Metres covered accelerating from `v0` to `v1` under the controller's own
## chase, dv/dt = acceleration * (run_speed - v). Post: >= 0; INF when v1 is at
## or past the asymptote and so never actually arrives.
func _runup_distance(v0: float, v1: float) -> float:
	if v1 <= v0:
		return 0.0
	if v1 >= _run_speed:
		return INF
	var a: float = maxf(_accel, 0.01)
	return _run_speed * log((_run_speed - v0) / (_run_speed - v1)) / a - (v1 - v0) / a


## The direction actually asked for this frame: `wanted` while the body is
## making progress, a wall-tangent detour while it is not.
##
## Pushing `wanted` into a wall is what produces the scrape - one velocity
## component gets eaten and the body inches along the face. Once obstruction is
## detected the wall's own tangent is followed instead, on the side that shortens
## the way to the waypoint, and held for AVOID_HOLD seconds so the two do not
## alternate every frame.
func _steer(char_body: CharacterBody3D, body_pos: Vector3, wanted: Vector3,
		delta: float) -> Vector3:
	if char_body == null:
		return wanted

	var expected: float = (_run_speed if _run else _walk_speed) * STUCK_SPEED_RATIO
	var actual := Vector2(char_body.velocity.x, char_body.velocity.z).length()
	var airborne := not char_body.is_on_floor()
	var landing := int(char_body.get("state")) == PlayerController.State.LANDING if char_body != null else false
	if actual >= expected or airborne or landing or _is_centering:
		_stuck_time = 0.0
	else:
		_stuck_time += delta

	if _avoid_left > 0.0 and _avoid_dir != Vector3.ZERO:
		return _avoid_dir

	if _stuck_time >= AVOID_AFTER and _repath_cooldown <= 0.0:
		_repath_cooldown = 0.5
		_stuck_time = 0.0
		repath_requested.emit(body_pos, _target_pos)
		return wanted

	if _stuck_time < AVOID_AFTER:
		return wanted

	var normal := _wall_normal(char_body)
	if normal == Vector3.ZERO:
		return wanted
	var tangent := Vector3.UP.cross(normal)
	tangent.y = 0.0
	if tangent.length_squared() < 0.0001:
		return wanted
	tangent = tangent.normalized()
	# Whichever way along the face heads more like the way the body wanted to go.
	# A dead-on wall makes both equal; the sign is then arbitrary and the next
	# hold picks up whatever the first one exposed.
	if tangent.dot(wanted) < 0.0:
		tangent = -tangent
	# Kept slightly off the face so the detour peels away instead of hugging it.
	_avoid_dir = (tangent + normal * 0.25).normalized()
	_avoid_left = AVOID_HOLD
	return _avoid_dir


## Normal of the first wall in last frame's slide collisions, or ZERO when the
## body only touched floor. Pre: called after the body's move_and_slide().
func _wall_normal(char_body: CharacterBody3D) -> Vector3:
	for i in char_body.get_slide_collision_count():
		var collision := char_body.get_slide_collision(i)
		var normal := collision.get_normal()
		if absf(normal.y) < 0.7:
			return normal
	return Vector3.ZERO


func _finish() -> void:
	var target := _target_pos
	var complete := _plan_complete
	var last := _path[_path.size() - 1] if not _path.is_empty() else target
	clear_target()
	if complete:
		path_finished.emit(target)
	else:
		path_blocked.emit(target, last)
