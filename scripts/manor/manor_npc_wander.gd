class_name ManorNpcWander
extends IntentSource
## Autonomous wander intent source constrained to an anchor radius with stop_walking transitions.

enum State { IDLE, LOOK_AROUND, WANDER, STOP_WALK }

var anchor_pos := Vector3.ZERO
var wander_radius := 6.0
var walk_speed_factor := 0.7

var _state: State = State.IDLE
var _timer := 0.0
var _target_pos := Vector3.ZERO
var _target_heading := 0.0
var _stuck_timer := 0.0
var _last_pos := Vector3.ZERO


func _init(p_anchor := Vector3.ZERO, p_radius := 6.0) -> void:
	anchor_pos = p_anchor
	wander_radius = p_radius
	_timer = randf_range(1.0, 3.0)


func poll(body: Node, delta: float, intent: CharacterIntent) -> void:
	intent.clear()
	if body == null:
		return

	var body_3d := body as Node3D
	var cur_pos := body_3d.global_position if body_3d != null else Vector3.ZERO

	_timer -= delta

	match _state:
		State.IDLE:
			intent.move = Vector2.ZERO
			if _timer <= 0.0:
				if randf() < 0.25:
					_state = State.LOOK_AROUND
					_target_heading = randf_range(-PI, PI)
					_timer = randf_range(1.5, 3.0)
				else:
					_start_wandering(cur_pos)

		State.LOOK_AROUND:
			intent.move = Vector2.ZERO
			intent.heading = _target_heading
			if _timer <= 0.0:
				_state = State.IDLE
				_timer = randf_range(1.5, 4.0)

		State.WANDER:
			var diff := _target_pos - cur_pos
			var dist_h := Vector2(diff.x, diff.z).length()

			if dist_h <= 0.45 or _timer <= 0.0:
				_state = State.STOP_WALK
				_timer = 1.2
				_stuck_timer = 0.0
				intent.move = Vector2.ZERO
				if body.has_method("play_stop_walk"):
					body.call("play_stop_walk", 1.8)
				return

			var heading := atan2(diff.x, diff.z)
			intent.heading = heading
			intent.move = Vector2(0.0, walk_speed_factor)
			intent.run = false

			# Detect physics obstruction
			var moved_dist := (cur_pos - _last_pos).length()
			if moved_dist < 0.15 * delta:
				_stuck_timer += delta
				if _stuck_timer > 0.8:
					_state = State.STOP_WALK
					_timer = 0.8
					_stuck_timer = 0.0
					intent.move = Vector2.ZERO
					if body.has_method("play_stop_walk"):
						body.call("play_stop_walk", 2.0)
			else:
				_stuck_timer = maxf(0.0, _stuck_timer - delta * 2.0)

		State.STOP_WALK:
			intent.move = Vector2.ZERO
			if _timer <= 0.0:
				_state = State.IDLE
				_timer = randf_range(2.5, 5.0)

	_last_pos = cur_pos


func _start_wandering(cur_pos: Vector3) -> void:
	var angle := randf_range(0.0, TAU)
	var dist := randf_range(2.0, wander_radius)
	var offset := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
	_target_pos = anchor_pos + offset
	var diff := _target_pos - cur_pos
	_target_heading = atan2(diff.x, diff.z)
	_state = State.WANDER
	_timer = randf_range(5.0, 9.0)
	_stuck_timer = 0.0
	_last_pos = cur_pos
