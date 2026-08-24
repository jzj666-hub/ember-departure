class_name PvpSwordAi
extends IntentSource
## Autonomous combat AI intent source: delivers precise target tracking, forward pursuit, combos, and clean spacing.

enum AiState { CHASE, ATTACK, RETREAT, DODGE }

# State enum values from PlayerController: CLIMBING=7, ROLLING=9, ATTACKING=10, HIT_STUN=11
const STATE_CLIMBING := 7
const STATE_ROLLING := 9
const STATE_ATTACKING := 10
const STATE_HIT_STUN := 11

var target_body: Node = null
var difficulty: int = 2 # 1=Easy, 2=Normal, 3=Master
var is_active: bool = true

var _state: AiState = AiState.CHASE
var _state_timer: float = 0.0
var _attack_cooldown: float = 0.0
var _dodge_cooldown: float = 0.0

var _combo_seq: Array = []
var _combo_index: int = 0
var _last_stroke_count: int = 0
var _stroke_hit: bool = false

const ATTACK_RANGE := 2.0
const DODGE_TRIGGER_DIST := 2.3


func _init(p_target: Node = null) -> void:
	target_body = p_target


func reset() -> void:
	is_active = true
	_state = AiState.CHASE
	_state_timer = 0.0
	_attack_cooldown = 0.2
	_dodge_cooldown = 0.0
	_combo_index = 0
	_last_stroke_count = 0
	_stroke_hit = false
	_combo_seq.clear()


func poll(body: Node, delta: float, intent: CharacterIntent) -> void:
	intent.clear()

	if not is_active or body == null or target_body == null or not is_instance_valid(target_body):
		return

	var ai_body := body as CharacterBody3D
	if ai_body == null:
		return

	if _attack_cooldown > 0.0:
		_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	if _dodge_cooldown > 0.0:
		_dodge_cooldown = maxf(0.0, _dodge_cooldown - delta)
	if _state_timer > 0.0:
		_state_timer = maxf(0.0, _state_timer - delta)

	var diff: Vector3 = target_body.global_position - ai_body.global_position
	var dist_h := Vector2(diff.x, diff.z).length()
	var yaw_to_target := atan2(diff.x, diff.z)

	var body_state: int = int(ai_body.get("state"))
	var target_state: int = int(target_body.get("state"))

	# Invariant: AI strictly faces target at all times except during an active roll
	if body_state != STATE_ROLLING:
		ai_body.rotation.y = yaw_to_target
	intent.heading = yaw_to_target

	# --- 1. Hit Stun Reaction: Breakout Roll & Active Disengage ---
	if body_state == STATE_HIT_STUN:
		_combo_seq.clear()
		_combo_index = 0
		_state = AiState.RETREAT
		_state_timer = 0.5
		_attack_cooldown = maxf(_attack_cooldown, 0.3)

		# Attempt immediate breakout dodge roll as stun ends
		var breakout_chance: float = 0.40 if difficulty == 1 else (0.65 if difficulty == 2 else 0.85)
		if _dodge_cooldown <= 0.0 and randf() < breakout_chance:
			_dodge_cooldown = randf_range(2.0, 3.2) if difficulty == 3 else randf_range(2.8, 4.2)
			var side_sign: float = 1.0 if randf() < 0.5 else -1.0
			intent.heading = yaw_to_target + (side_sign * PI * 0.5 if randf() < 0.40 else PI)
			intent.move = Vector2(0.0, 1.0)
			intent.roll = true
		else:
			# Actively backpedal to exit melee reach
			intent.move = Vector2(0.0, -1.0)
		return

	# --- 2. Reaction Dodge Roll on Incoming Threat (Facing Cone + Distance Check) ---
	if _dodge_cooldown <= 0.0 and dist_h <= DODGE_TRIGGER_DIST:
		var is_threat := _is_incoming_threat(ai_body, diff, dist_h, target_state)
		var roll_chance: float = 0.35 if difficulty == 1 else (0.55 if difficulty == 2 else 0.80)
		if is_threat and randf() < roll_chance:
			_state = AiState.DODGE
			_dodge_cooldown = randf_range(2.0, 3.2) if difficulty == 3 else randf_range(2.8, 4.5)
			_state_timer = 0.55

			# Side roll vs back roll: ~35% chance to flank roll left or right
			var do_side_roll: bool = randf() < 0.35
			if do_side_roll:
				var side_sign: float = 1.0 if randf() < 0.5 else -1.0
				intent.heading = yaw_to_target + side_sign * (PI * 0.5)
			else:
				intent.heading = yaw_to_target + PI

			intent.move = Vector2(0.0, 1.0)
			intent.roll = true
			return

	if body_state == STATE_ROLLING or body_state == STATE_CLIMBING:
		return

	# --- 3. State Machine (Chase -> Attack Combo -> Spacing/Re-engage) ---
	match _state:
		AiState.CHASE:
			# Calculate predictive pre-attack trigger distance:
			# When sprinting (run_speed ~3.6m/s) with weapon windup (~0.28s), effective strike initiation
			# should happen at 2.6m~2.8m so the blade connects at optimal range (1.8m~2.0m) with priority.
			var is_sprinting := (dist_h > 1.8)
			var effective_strike_dist := (2.75 if difficulty == 3 else 2.55) if is_sprinting else ATTACK_RANGE

			if dist_h > effective_strike_dist or _attack_cooldown > 0.0:
				intent.move = Vector2(0.0, 1.0)
				intent.run = is_sprinting
			else:
				# Predictive strike: start combo attack before fully entering static melee reach
				_start_combo_sequence(ai_body, yaw_to_target, intent)

		AiState.ATTACK:
			var cur_stroke: int = int(ai_body.call("weapon_stroke_count")) if ai_body.has_method("weapon_stroke_count") else 0
			var hits: int = int(ai_body.call("weapon_hit_count")) if ai_body.has_method("weapon_hit_count") else 0
			var in_link_win: bool = bool(ai_body.call("is_weapon_in_link_window")) if ai_body.has_method("is_weapon_in_link_window") else true

			if cur_stroke != _last_stroke_count:
				_last_stroke_count = cur_stroke
				_combo_index += 1
				_stroke_hit = false

			if hits > 0:
				_stroke_hit = true

			# Always face opponent directly during swing
			intent.heading = yaw_to_target
			ai_body.rotation.y = yaw_to_target

			# Precise timing combo chaining:
			# When approaching or inside the weapon's link window, evaluate target reach:
			if _combo_index < _combo_seq.size():
				var target_in_reach := _is_target_in_attack_range(ai_body, diff, dist_h)
				if in_link_win or _stroke_hit:
					if _stroke_hit or target_in_reach:
						# Perfect link window timing: trigger next chained combo strike
						intent.press(_combo_seq[_combo_index])
						intent.move = Vector2(0.0, 0.45) if dist_h > 1.1 else Vector2.ZERO
					else:
						# Target fled outside reach during window: cancel remaining combo
						_combo_seq.clear()
						intent.move = Vector2.ZERO
				else:
					# Advancing stroke take: maintain subtle forward drive while awaiting link window
					intent.move = Vector2(0.0, 0.35) if dist_h > 1.2 else Vector2.ZERO
			else:
				intent.move = Vector2.ZERO

			# Check combo action finished: when attack animation layer completes
			if body_state != STATE_ATTACKING and _state_timer < 2.0:
				if _is_target_in_attack_range(ai_body, diff, dist_h) and randf() < (0.80 if difficulty >= 2 else 0.55):
					_state = AiState.CHASE
					_attack_cooldown = randf_range(0.08, 0.20) if difficulty == 3 else randf_range(0.15, 0.35)
				else:
					_state = AiState.CHASE if dist_h > 2.5 else AiState.RETREAT
					_state_timer = randf_range(0.20, 0.35)
					_attack_cooldown = randf_range(0.15, 0.35) if difficulty == 3 else randf_range(0.30, 0.60)

		AiState.RETREAT:
			# Fast backpedal while strictly facing the opponent to escape melee reach
			intent.move = Vector2(0.0, -1.0)
			if _state_timer <= 0.0 or _attack_cooldown <= 0.0 or dist_h > 3.2:
				_state = AiState.CHASE

		AiState.DODGE:
			if _state_timer <= 0.0:
				_state = AiState.CHASE


## Checks if target is currently within valid forward melee attack reach.
func _is_target_in_attack_range(ai_body: CharacterBody3D, diff: Vector3, dist_h: float) -> bool:
	if dist_h > 2.25:
		return false
	var ai_fwd := -ai_body.global_transform.basis.z
	var ai_fwd_2d := Vector2(ai_fwd.x, ai_fwd.z)
	if ai_fwd_2d.length_squared() < 0.001:
		return true
	ai_fwd_2d = ai_fwd_2d.normalized()

	var to_target_2d := Vector2(diff.x, diff.z).normalized()
	var front_dot := ai_fwd_2d.dot(to_target_2d)
	return front_dot >= 0.45


## Checks if target is attacking and facing AI within threat cone.
func _is_incoming_threat(_ai_body: CharacterBody3D, diff: Vector3, dist_h: float, target_state: int) -> bool:
	if target_state != STATE_ATTACKING:
		return false
	if dist_h > DODGE_TRIGGER_DIST:
		return false

	var target_3d := target_body as Node3D
	if target_3d == null:
		return true

	var target_fwd := -target_3d.global_transform.basis.z
	var target_fwd_2d := Vector2(target_fwd.x, target_fwd.z)
	if target_fwd_2d.length_squared() < 0.001:
		return true
	target_fwd_2d = target_fwd_2d.normalized()

	# Vector from target pointing to AI
	var to_ai_2d := Vector2(-diff.x, -diff.z).normalized()
	var facing_dot := target_fwd_2d.dot(to_ai_2d)

	# Target must face AI within ~66 degree cone (cos(66 deg) ≈ 0.40)
	return facing_dot > 0.40


func _start_combo_sequence(ai_body: CharacterBody3D, yaw_to_target: float, intent: CharacterIntent) -> void:
	_state = AiState.ATTACK
	_state_timer = 2.5
	_last_stroke_count = int(ai_body.call("weapon_stroke_count")) if ai_body.has_method("weapon_stroke_count") else 0
	_combo_index = 0
	_stroke_hit = false

	# Align immediately towards player
	ai_body.rotation.y = yaw_to_target
	intent.heading = yaw_to_target

	# Select combo pattern (all entry triggers must start with "attack")
	if difficulty == 1:
		_combo_seq = ["attack", "attack"]
	elif difficulty == 2:
		var patterns = [
			["attack", "heavy", "heavy"],
			["attack", "attack", "heavy"],
			["attack", "attack", "attack"],
		]
		_combo_seq = patterns[randi() % patterns.size()]
	else:
		var patterns = [
			["attack", "heavy", "heavy"],
			["attack", "heavy", "attack"],
			["attack", "attack", "heavy"],
			["attack", "attack", "attack"],
		]
		_combo_seq = patterns[randi() % patterns.size()]

	# Fire initial combo strike
	intent.press(_combo_seq[0])
