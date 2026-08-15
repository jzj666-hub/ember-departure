class_name SpecialPathRecorder
extends RefCounted
## Trajectory recorder and straight-line constraint validator for custom jump connections.

signal state_changed(state: int, message: String)
signal path_recorded(path_data: Dictionary)
signal recording_failed(reason: String)

enum State {
	IDLE,
	ARMED_WAITING_FOR_REST,
	ARMED_READY_TO_JUMP,
	AIRBORNE_RECORDING,
	COMPLETED
}

## Maximum lateral deviation in metres allowed during airborne flight for a straight jump.
const STRAIGHT_LINE_TOLERANCE := 0.18
## Maximum stationary velocity threshold at takeoff point.
const REST_SPEED_THRESHOLD := 0.15
## Minimum required jump horizontal span.
const MIN_JUMP_DISTANCE := 0.8

var _state: int = State.IDLE
var _nav_grid: NavGrid = null
var _start_cell: Vector3i = NavGrid.NO_CELL
var _target_cell: Vector3i = NavGrid.NO_CELL

var _start_pos := Vector3.ZERO
var _takeoff_pos := Vector3.ZERO
var _takeoff_vel := Vector3.ZERO
var _takeoff_speed := 0.0
var _landing_pos := Vector3.ZERO

var _trajectory_samples: Array = []
var _timer := 0.0
var _rest_timer := 0.0


func set_nav_grid(grid: NavGrid) -> void:
	_nav_grid = grid


func is_recording() -> bool:
	return _state != State.IDLE and _state != State.COMPLETED


func get_state() -> int:
	return _state


## Starts recording workflow. Start cell will be sampled when stationary.
func start_recording(suggested_start_cell := NavGrid.NO_CELL) -> void:
	_reset()
	_start_cell = suggested_start_cell
	_state = State.ARMED_WAITING_FOR_REST
	state_changed.emit(_state, "请在起点格保持完全静止...")


## Cancels recording.
func cancel_recording() -> void:
	_reset()
	_state = State.IDLE
	state_changed.emit(_state, "已取消录制")


func _reset() -> void:
	_state = State.IDLE
	_trajectory_samples.clear()
	_timer = 0.0
	_rest_timer = 0.0
	_takeoff_pos = Vector3.ZERO
	_takeoff_vel = Vector3.ZERO
	_takeoff_speed = 0.0
	_landing_pos = Vector3.ZERO


## Updates recorder state every physics frame while player character is driven.
func update_frame(body: CharacterBody3D, delta: float) -> void:
	if _state == State.IDLE or _state == State.COMPLETED or body == null:
		return

	var pos := body.global_position
	var vel := body.velocity
	var horiz_vel := Vector2(vel.x, vel.z)
	var horiz_speed := horiz_vel.length()
	var grounded := body.is_on_floor()

	match _state:
		State.ARMED_WAITING_FOR_REST:
			if grounded and horiz_speed <= REST_SPEED_THRESHOLD:
				_rest_timer += delta
				if _rest_timer >= 0.2:
					_start_pos = pos
					if _nav_grid != null:
						_start_cell = _nav_grid.standing_node(pos)
					_state = State.ARMED_READY_TO_JUMP
					state_changed.emit(_state, "已就绪！请向目标格直线起跑并起跳")
			else:
				_rest_timer = 0.0

		State.ARMED_READY_TO_JUMP:
			if not grounded:
				_state = State.AIRBORNE_RECORDING
				_takeoff_pos = pos
				_takeoff_vel = vel
				_takeoff_speed = horiz_speed
				_timer = 0.0
				_trajectory_samples.clear()
				_trajectory_samples.append({
					"t": 0.0,
					"p": [pos.x, pos.y, pos.z],
					"v": [vel.x, vel.y, vel.z],
				})
				state_changed.emit(_state, "空中飞行中... 记录直线轨迹")
			elif horiz_speed > 0.1:
				_start_pos = pos

		State.AIRBORNE_RECORDING:
			_timer += delta
			_trajectory_samples.append({
				"t": _timer,
				"p": [pos.x, pos.y, pos.z],
				"v": [vel.x, vel.y, vel.z],
			})

			if grounded and _timer >= 0.08:
				_landing_pos = pos
				_finalize_recording()


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

	# Validate straight line geometric constraint across all airborne samples
	var max_deviation := 0.0
	for sample in _trajectory_samples:
		var p_arr: Array = sample["p"]
		var pt := Vector2(float(p_arr[0]), float(p_arr[2]))
		var dev := _point_to_line_dist(pt, takeoff_2d, landing_2d, span_length)
		if dev > max_deviation:
			max_deviation = dev

	if max_deviation > STRAIGHT_LINE_TOLERANCE:
		_state = State.IDLE
		var msg := "录制失败：空中偏离直线 %.2f 米 (最大容差 %.2f 米)，必须保持直线跳跃！" % [
			max_deviation, STRAIGHT_LINE_TOLERANCE]
		recording_failed.emit(msg)
		state_changed.emit(_state, msg)
		return

	if _nav_grid != null:
		if _start_cell == NavGrid.NO_CELL:
			_start_cell = _nav_grid.standing_node(_takeoff_pos)
		_target_cell = _nav_grid.standing_node(_landing_pos)

	if _start_cell == NavGrid.NO_CELL or _target_cell == NavGrid.NO_CELL:
		_state = State.IDLE
		var msg := "录制失败：起跳点或着陆点不在有效可站立网格内"
		recording_failed.emit(msg)
		state_changed.emit(_state, msg)
		return

	if _start_cell == _target_cell:
		_state = State.IDLE
		var msg := "录制失败：起点格与终点格相同"
		recording_failed.emit(msg)
		state_changed.emit(_state, msg)
		return

	var path_id := "path_%d" % int(Time.get_unix_time_from_system() * 1000.0)
	var heading := atan2(span_vec.x, span_vec.y)

	var record := {
		"id": path_id,
		"from": [_start_cell.x, _start_cell.y, _start_cell.z],
		"to": [_target_cell.x, _target_cell.y, _target_cell.z],
		"straight_line": true,
		"max_deviation": max_deviation,
		"span_distance": span_length,
		"duration": _timer,
		"takeoff_pos": [_takeoff_pos.x, _takeoff_pos.y, _takeoff_pos.z],
		"takeoff_speed": _takeoff_speed,
		"takeoff_velocity": [_takeoff_vel.x, _takeoff_vel.y, _takeoff_vel.z],
		"landing_pos": [_landing_pos.x, _landing_pos.y, _landing_pos.z],
		"heading": heading,
		"trajectory": _trajectory_samples,
	}

	_state = State.COMPLETED
	path_recorded.emit(record)
	state_changed.emit(_state, "成功录制特殊跳跃！起点 (%d,%d,%d) -> 终点 (%d,%d,%d) · 偏离 %.3fm" % [
		_start_cell.x, _start_cell.y, _start_cell.z,
		_target_cell.x, _target_cell.y, _target_cell.z,
		max_deviation
	])


static func _point_to_line_dist(pt: Vector2, a: Vector2, b: Vector2, line_len: float) -> float:
	if line_len < 0.0001:
		return pt.distance_to(a)
	# Perpendicular distance formula |(by-ay)x - (bx-ax)y + bx*ay - by*ax| / line_len
	var numerator := absf((b.y - a.y) * pt.x - (b.x - a.x) * pt.y + b.x * a.y - b.y * a.x)
	return numerator / line_len
