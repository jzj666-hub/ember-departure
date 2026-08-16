class_name SpecialPathRecorder
extends RefCounted
## Full-trajectory recorder: captures ground run-up + airborne + landing from
## last rest point. Each frame stores player intent for exact NPC replay.
## Freeform trajectories supported (no straight-line restriction).

signal state_changed(state: int, message: String)
signal path_recorded(path_data: Dictionary)
signal recording_failed(reason: String)

enum State {
	IDLE,
	ARMED_WAITING_FOR_REST,
	GROUND_RECORDING,
	AIRBORNE_RECORDING,
	COMPLETED
}

## Velocity threshold below which body counts as stationary.
const REST_SPEED_THRESHOLD := 0.15
## Minimum required horizontal span between takeoff and landing.
const MIN_JUMP_DISTANCE := 0.6

var _state: int = State.IDLE
var _nav_grid: NavGrid = null
var _start_cell: Vector3i = NavGrid.NO_CELL
var _target_cell: Vector3i = NavGrid.NO_CELL

## Rest point: last position where body was stationary for >= 0.2s.
var _rest_pos := Vector3.ZERO
var _rest_heading := 0.0

## Takeoff/landing world positions.
var _takeoff_pos := Vector3.ZERO
var _takeoff_vel := Vector3.ZERO
var _takeoff_speed := 0.0
var _landing_pos := Vector3.ZERO

## Per-frame samples covering ground run-up + airborne + landing.
var _trajectory_samples: Array = []
var _timer := 0.0
var _rest_timer := 0.0
## Airborne-only elapsed time (for minimum flight duration check).
var _air_timer := 0.0

## Own edge detection state for jump key (prevents double-poll with PlayerIntentSource).
var _space_was_down := false


func set_nav_grid(grid: NavGrid) -> void:
	_nav_grid = grid


func is_recording() -> bool:
	return _state != State.IDLE and _state != State.COMPLETED


func get_state() -> int:
	return _state


## Start recording workflow. Waits for body to become stationary.
func start_recording(suggested_start_cell := NavGrid.NO_CELL) -> void:
	_reset()
	_start_cell = suggested_start_cell
	_state = State.ARMED_WAITING_FOR_REST
	state_changed.emit(_state, "请在起点格保持完全静止...")


## Cancel recording.
func cancel_recording() -> void:
	_reset()
	_state = State.IDLE
	state_changed.emit(_state, "已取消录制")


func _reset() -> void:
	_state = State.IDLE
	_trajectory_samples = []
	_timer = 0.0
	_rest_timer = 0.0
	_air_timer = 0.0
	_rest_pos = Vector3.ZERO
	_rest_heading = 0.0
	_takeoff_pos = Vector3.ZERO
	_takeoff_vel = Vector3.ZERO
	_takeoff_speed = 0.0
	_landing_pos = Vector3.ZERO
	_space_was_down = false


## Call every physics frame. Polls Input directly for intent snapshot.
func update_frame(body: CharacterBody3D, delta: float) -> void:
	if _state == State.IDLE or _state == State.COMPLETED or body == null:
		return

	var pos := body.global_position
	var vel := body.velocity
	var horiz_vel := Vector2(vel.x, vel.z)
	var horiz_speed := horiz_vel.length()
	var grounded := body.is_on_floor()

	# Snapshot player intent from raw Input (own edge detection).
	var snap := _snapshot_intent(body)

	match _state:
		State.ARMED_WAITING_FOR_REST:
			if grounded and horiz_speed <= REST_SPEED_THRESHOLD:
				_rest_timer += delta
				if _rest_timer >= 0.2:
					_rest_pos = pos
					_rest_heading = snap.heading
					if _nav_grid != null:
						_start_cell = _nav_grid.standing_node(pos)
					_state = State.GROUND_RECORDING
					_timer = 0.0
					_trajectory_samples = [_make_sample(0.0, pos, vel, snap, grounded)]
					state_changed.emit(_state, "已就绪！开始录制（将自动以起跳前最后一次静止点为起点）")
			else:
				_rest_timer = 0.0

		State.GROUND_RECORDING:
			if grounded and horiz_speed <= REST_SPEED_THRESHOLD and snap.move == Vector2.ZERO and not snap.jump:
				# Continuous rest tracking: reset starting origin to the player's LAST stationary frame
				_rest_pos = pos
				_rest_heading = snap.heading
				if _nav_grid != null:
					_start_cell = _nav_grid.standing_node(pos)
				_timer = 0.0
				_trajectory_samples = [_make_sample(0.0, pos, vel, snap, grounded)]
			else:
				_timer += delta
				_trajectory_samples.append(_make_sample(_timer, pos, vel, snap, grounded))

			if not grounded:
				_takeoff_pos = pos
				_takeoff_vel = vel
				_takeoff_speed = horiz_speed
				_air_timer = 0.0
				_state = State.AIRBORNE_RECORDING
				state_changed.emit(_state, "空中飞行中... 记录跳跃轨迹")

		State.AIRBORNE_RECORDING:
			_timer += delta
			_air_timer += delta
			_trajectory_samples.append(_make_sample(_timer, pos, vel, snap, grounded))

			if grounded and _air_timer >= 0.08:
				_landing_pos = pos
				_finalize_recording()


## Snapshot player input state. Uses own edge detection for jump.
func _snapshot_intent(body: CharacterBody3D) -> Dictionary:
	var move := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		move.y += 1.0
	if Input.is_physical_key_pressed(KEY_S):
		move.y -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		move.x += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		move.x -= 1.0
	move = move.limit_length(1.0)

	var heading: float = float(body.call("view_yaw")) if body.has_method("view_yaw") else body.rotation.y
	var run: bool = Input.is_key_pressed(KEY_SHIFT)

	var space_down := Input.is_physical_key_pressed(KEY_SPACE)
	var jump: bool = space_down and not _space_was_down
	_space_was_down = space_down

	return {"move": move, "heading": heading, "run": run, "jump": jump}


## Build one trajectory sample dict.
func _make_sample(t: float, pos: Vector3, vel: Vector3,
		snap: Dictionary, grounded: bool) -> Dictionary:
	var mv: Vector2 = snap.move
	return {
		"t": t,
		"p": [pos.x, pos.y, pos.z],
		"v": [vel.x, vel.y, vel.z],
		"move": [mv.x, mv.y],
		"heading": snap.heading,
		"run": snap.run,
		"jump": snap.jump,
		"grounded": grounded,
	}


func _finalize_recording() -> void:
	var takeoff_2d := Vector2(_takeoff_pos.x, _takeoff_pos.z)
	var landing_2d := Vector2(_landing_pos.x, _landing_pos.z)
	var span_vec := landing_2d - takeoff_2d
	var span_length := span_vec.length()

	if span_length < MIN_JUMP_DISTANCE:
		_state = State.IDLE
		var msg := "录制失败：跳跃水平距离过短 (%.2fm < %.2fm)" % [span_length, MIN_JUMP_DISTANCE]
		recording_failed.emit(msg)
		state_changed.emit(_state, msg)
		return

	if _nav_grid != null:
		if _start_cell == NavGrid.NO_CELL:
			_start_cell = _nav_grid.standing_node(_takeoff_pos)
		if _start_cell == NavGrid.NO_CELL:
			_start_cell = _nav_grid.standing_node(_rest_pos)
		_target_cell = _nav_grid.standing_node(_landing_pos)

	if _start_cell == NavGrid.NO_CELL or _target_cell == NavGrid.NO_CELL:
		_state = State.IDLE
		var msg := "录制失败：起跳点或着陆点不在有效可站立网格内"
		recording_failed.emit(msg)
		state_changed.emit(_state, msg)
		return

	if _start_cell == _target_cell:
		_state = State.IDLE
		var msg := "录制失败：起点格与终点格相同 (%d,%d,%d)" % [_start_cell.x, _start_cell.y, _start_cell.z]
		recording_failed.emit(msg)
		state_changed.emit(_state, msg)
		return

	# Calculate max lateral deviation for informational / visual metrics only (no rejection).
	var max_deviation := 0.0
	for sample in _trajectory_samples:
		if bool(sample.get("grounded", true)):
			continue
		var p_arr: Array = sample["p"]
		var pt := Vector2(float(p_arr[0]), float(p_arr[2]))
		var dev := _point_to_line_dist(pt, takeoff_2d, landing_2d, span_length)
		if dev > max_deviation:
			max_deviation = dev

	var path_id := "path_%d" % int(Time.get_unix_time_from_system() * 1000.0)
	var heading := atan2(span_vec.x, span_vec.y)

	# Count ground frames (grounded prefix of trajectory).
	var ground_frames := 0
	for sample in _trajectory_samples:
		if bool(sample.get("grounded", true)):
			ground_frames += 1
		else:
			break

	var record := {
		"id": path_id,
		"from": [_start_cell.x, _start_cell.y, _start_cell.z],
		"to": [_target_cell.x, _target_cell.y, _target_cell.z],
		"straight_line": max_deviation <= 0.18,
		"max_deviation": max_deviation,
		"span_distance": span_length,
		"duration": _timer,
		"takeoff_pos": [_takeoff_pos.x, _takeoff_pos.y, _takeoff_pos.z],
		"takeoff_speed": _takeoff_speed,
		"takeoff_velocity": [_takeoff_vel.x, _takeoff_vel.y, _takeoff_vel.z],
		"landing_pos": [_landing_pos.x, _landing_pos.y, _landing_pos.z],
		"heading": heading,
		"rest_pos": [_rest_pos.x, _rest_pos.y, _rest_pos.z],
		"rest_heading": _rest_heading,
		"ground_frames": ground_frames,
		"trajectory": _trajectory_samples.duplicate(true),
	}

	_state = State.COMPLETED
	path_recorded.emit(record)
	state_changed.emit(_state, "成功录制特殊路径！起点 (%d,%d,%d) -> 终点 (%d,%d,%d) · %d 帧轨迹" % [
		_start_cell.x, _start_cell.y, _start_cell.z,
		_target_cell.x, _target_cell.y, _target_cell.z,
		_trajectory_samples.size()
	])


static func _point_to_line_dist(pt: Vector2, a: Vector2, b: Vector2, line_len: float) -> float:
	if line_len < 0.0001:
		return pt.distance_to(a)
	var numerator := absf((b.y - a.y) * pt.x - (b.x - a.x) * pt.y + b.x * a.y - b.y * a.x)
	return numerator / line_len
