class_name PlayerController
extends CharacterBody3D
## Character controller handling locomotion (WASD, sprint, crouch), gravity, jumps, rolls, ledges, and weapon graph states.
##
## The state machine and the body live here; four owned layers hold the rest, and
## none of them knows about any other except through this one:
##   CharacterAnimRig  the AnimationTree, the library, and every clip name
##   PlayerProbes      what the world is asked before a move is committed to
##   PlayerVfx         the lunge's ribbon / fade, and the blade's afterimage
##   PlayerWeapons     the behaviour graph and the clips a weapon needs loaded
## Invariant: _rig != null only after a successful setup(); _physics_process is a
## no-op before that.

const PlayerIntentSourceScript = preload("res://scripts/player_intent_source.gd")
const AudioManagerScript = preload("res://scripts/audio_manager.gd")

@export var footstep_enabled := true
var _footstep_distance := 0.0


enum State {
	IDLE, WALK, RUN, CROUCH, BRAKING,
	JUMPING,   ## off the ground because Space said so
	FALLING,   ## off the ground because the ground ran out
	CLIMBING,  ## pulling up onto a ledge, on a path of its own
	LANDING,   ## one of the three landings, still holding control
	ROLLING,   ## the double-tap roll
	ATTACKING, ## swinging weapon, movement restricted
	HIT_STUN,  ## hit reaction flinch and control lock
	SITTING,   ## seated on chair/bench
}


## Defaults chosen to sit close to the pace the clips were performed at, which is
## what keeps the feet from sliding.
@export var walk_speed := 1.1
@export var run_speed := 3.6
@export var crouch_speed := 0.7
## How hard the body chases its target speed, per second.
@export var acceleration := 14.0
## Radians per second the character turns towards the camera while moving.
@export var turn_rate := 24.0
## How hard the blend position chases the body, per second. Below `acceleration`
## on purpose: the pose arriving a little after the movement reads as weight.
@export var blend_rate := 10.0
## How fast the character folds into and out of a crouch, per second.
@export var crouch_rate := 9.0
## Standing height the collision capsule shrinks to while crouched.
@export var crouch_height := 0.6

## Whether running into a wall plays the skid.
@export var brake_enabled := true
## How far ahead a wall has to be for a run to start skidding, in metres.
@export var brake_distance := 1.8
## How much of that is given up to the body's own width, in metres. The probe is
## cast from the character's axis, so without this it would aim to stop with the
## wall halfway through its chest.
@export var brake_margin := 0.5
## Playback rate of the skid clip. The take is performed at a gentler stop than
## running face-first into a wall, so it is run at double speed.
@export var brake_rate := 2.0
## Seconds before a skid can fire again, so standing against a wall on the
## throttle does not stutter.
@export var brake_cooldown := 0.9

# --- jump ------------------------------------------------------------------

## Whether the jump half of the jump/climb request does anything.
@export var jump_enabled := true
## Upward jump velocity in m/s.
@export var jump_speed := 4.7
## Air control factor (fraction of ground control).
@export var air_control := 0.35
## Coyote time window in seconds.
@export var coyote_time := 0.12
## Seconds a jump asked for just before landing is remembered for.
@export var jump_buffer := 0.15
## Playback speed rate for jump launch animation.
@export var jump_start_rate := 1.8
## Seconds the launch take holds before the airborne loop takes over.
@export var jump_start_time := 0.32
## Duration control is locked during landing recovery.
@export var jump_land_recover := 0.22

# --- climb -----------------------------------------------------------------

## Whether a jump request looks for a ledge before deciding it is a jump.
@export var climb_enabled := true
## Lowest ledge worth climbing, in metres above the feet. Below this the jump
## gets there, and the climb take is far too long a commitment for a kerb.
@export var climb_min_height := 0.5
## Highest ledge the character will pull itself onto, in metres above the feet.
@export var climb_max_height := 2.2
## How far in front of the body the ledge probe looks, in metres, on top of the
## body's own radius.
@export var climb_reach := 0.45
## How flat the top of a ledge has to be before it counts as somewhere to stand:
## the dot of its normal with up.
@export var climb_floor_dot := 0.7
## Duration of the climb pull-up in seconds, for a one-cell (1 m) ledge.
@export var climb_duration_1m := 0.7
## Duration of the climb pull-up in seconds, for a two-cell (2 m) ledge.
## Heights between the two interpolate linearly.
@export var climb_duration_2m := 1.3
## What fraction of the climb is spent going up before the body starts moving in.
## A mantle is up-then-over: done together the body cuts the corner and the feet
## pass through the face of the ledge.
@export var climb_rise_share := 0.62
## How much of the character's own capsule has to fit on the ledge for the climb
## to be allowed, as a fraction of it. Under 1.0 so a ledge exactly wide enough
## is not turned down by floating point.
@export var climb_clearance := 0.9

# --- step up ----------------------------------------------------------------

## Whether the body lifts itself over kerbs too low to be worth a jump.
##
## Closes a gap that only continuous maps open. A voxel cell is 1 m, so NavGrid
## never plans a rise smaller than a whole climb, and the NPC executor asks for
## nothing under its own step tolerance (~0.4 m). A baked NavigationMesh, by
## contrast, promises agent_max_climb of step-up and routes straight over a
## 0.2 m kerb - which the body then walks into and stops at forever.
@export var step_up_enabled := true
## Tallest kerb the body will lift itself over, in metres. Keep at or below the
## navmesh bake's agent_max_climb: the mesh plans routes assuming exactly this
## much, and promising more there than the body has is what jams it.
## Must stay under climb_min_height, or kerbs steal what should be climbs.
@export var step_max_height := 0.4
## How far past its own radius the body probes for somewhere to put its feet.
@export var step_probe_ahead := 0.08

# --- fall and land ---------------------------------------------------------

## Whether walking off a platform plays the climb-down take rather than the
## airborne loop. Jumping off one always plays the loop: the difference between
## the two is the whole point.
@export var fall_climb_down := true
## Drop below which a fall lands with no take at all, in metres. A kerb is not an
## event, and animating one turns every step off the measuring lane into a
## stumble.
@export var land_min_drop := 0.55
## Drop up to which the soft landing plays, in metres.
@export var land_soft_drop := 1.8
## Drop up to which the hard landing plays. Above it, the fall rolls out.
@export var land_hard_drop := 3.4
## Ground speed at contact at or above which a fall rolls out whatever the drop
## was, in m/s.
##
## Min speed to roll out of a fall.
@export var land_roll_speed_min := 2.0
## Drop from peak at or above which a fast landing rolls out, in metres.
## Below this drop, the character lands with jump_land even if speed is high.
@export var land_roll_drop_min := 1.8
## Seconds control is held for each of the three, in the same order. The takes
## are all longer than these - the rest of each one plays out underneath the
## locomotion fading back in, which is what stops a landing feeling like a stop.
@export var land_soft_recover := 0.22
@export var land_hard_recover := 0.38
@export var land_roll_recover := 0.95
## How much of each take plays BEFORE the feet arrive, in seconds.
##
## Animation lead offset before touchdown.
@export var land_soft_lead := 0.5
@export var land_hard_lead := 0.7
@export var land_roll_lead := 0.35
## Downward vertical speed in m/s required before landing prediction triggers.
@export var land_arm_vy_min := 3.5
## Fastest a landing take may be run when there is not enough airtime left to
## give it its full lead - a short drop, or ground that only came into view late.
## Running it fast beats starting it late, and beats skipping it.
@export var land_rate_cap := 4.0
## How far below the feet the fall looks for the ground it is going to hit, in
## metres. Only has to cover the drops the level actually has in it.
@export var fall_probe := 25.0
## Peak ground speed the roll-out landing carries, in m/s.
@export var land_roll_speed := 3.4

# --- roll ------------------------------------------------------------------

## Whether the roll request does anything.
@export var roll_enabled := true
## Seconds the roll lasts before control comes back.
@export var roll_duration := 0.52
## Playback rate of the roll take.
@export var roll_rate := 1.6
## Peak velocity during roll in m/s.
@export var roll_speed := 5.2
## Seconds after a roll ends before another can start.
@export var roll_cooldown := 0.10

## Seconds the action layer takes to cross-fade, in either direction.
@export var action_blend := 0.14
## Fraction of the normal turn rate the character steers at while swinging a take
## that does not lock movement.
@export var attack_turn := 0.5

# --- the dash ---------------------------------------------------------------


## How fast every lunge is covered, in m/s. The weapon says how far
## (`dash_distance`), this says how long that takes - there is no per-action clock.
@export var dash_speed := 6.0
@export var dash_vfx: PlayerVfx.DashVfx = PlayerVfx.DashVfx.BEAM
## BEAM: the ribbon's colour and how long it hangs around after the lunge ends.
@export var dash_beam_tint := Color(0.60, 0.78, 1.0, 0.55)
@export var dash_beam_life := 0.28
## FADE: how far down the body goes, and the two ramps either side of the lunge.
@export var dash_fade_floor := 0.0
@export var dash_fade_out := 0.04
@export var dash_fade_in := 0.10


## The visual, an instance of a pipeline-generated <id>.tscn. Loosely typed: see
## the note on FollowCamera.target.
var character: Node3D
var camera: Node3D

## Decision source (IntentSource) for driving character behaviors.
var intent_source: IntentSource

var state := State.IDLE
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

## The four owned layers. Only the rig is built in setup() - the other three hold
## no node references until they are used, so equipping a weapon or setting a
## trail before setup() is harmless.
var _rig: CharacterAnimRig
var _probes := PlayerProbes.new()
var _vfx := PlayerVfx.new()
var _weapons := PlayerWeapons.new()

## This frame's decisions, whoever made them. Rewritten in place, never replaced.
var _intent := CharacterIntent.new()
## Requests that came in between physics frames, latched so they cannot be missed
## by a caller running at its own pace. Merged into `_intent` and cleared.
var _queued_jump := false
var _queued_roll := false
## The combat buttons asked for since the last frame, as a CharacterIntent.BUTTONS
## mask. A mask rather than a bool because a weapon graph may answer to several.
var _queued_buttons := 0

## How much of the swing layer is showing. Chased towards 1 while ATTACKING.
var _swing_amount := 0.0
## Current 2D blend coordinate.
var _blend := Vector2.ZERO
## Crouch transition state (0.0 to 1.0).
var _stance := 0.0

var _capsule: CollisionShape3D
var _stand_height := 1.75

## Constant deceleration the current skid is running at, in m/s^2, picked at fire
## time so the character comes to rest at the wall rather than through it.
var _brake_decel := 0.0
var _brake_left := 0.0
var _brake_cooldown_left := 0.0

## Seconds left of whatever the action layer is holding control for. One timer
## for all of them: only ever one action at a time, by construction.
var _action_left := 0.0
## Whether the action currently running carries the body forward - the roll, and
## the landing that rolls out of a long drop.
var _action_slides := false
## How fast the current slide started, in m/s. A roll entered at a walk has to
## pick that walk up rather than stop and start again - see _slide_pace().
var _slide_entry := 0.0
## How far the current slide is allowed to carry, in m/s at its peak.
var _slide_speed := 0.0
## How long that slide was given, so its taper can be read off `_action_left`.
var _slide_span := 1.0
## Seconds left of the current lunge. The take plays through it at its own rate -
## see _drive_dash(). Zero means no lunge is running.
var _dash_left := 0.0
var _roll_cooldown_left := 0.0


## Seconds of grace left in which a jump request still counts, after the ground
## has gone. Refilled every frame the character is standing on something.
var _coyote_left := 0.0
## Seconds a jump asked for in mid-air is still remembered for.
var _jump_buffered := 0.0
## The highest the body has been since it last stood on something. What the
## landing take is chosen from - a jump peaks well above where it took off, and
## it is the drop from the peak that has to be absorbed, not the take-off height.
var _air_peak_y := 0.0
var _take_off_y := 0.0
var _air_speed := 0.0
## The landing already started in mid-air, and how long it will hold control for
## once the feet arrive. Empty until _arm_landing() picks one. See _land().
var _landing_take := ""
var _landing_recover := 0.0
## Playback rate of the landing animation, used to scale physical recovery and slide.
var _landing_rate := 1.0

enum SittingPhase { NONE, ENTERING, SEATED, EXITING }
var _sitting_phase: SittingPhase = SittingPhase.NONE

var _stop_walk_sliding := false
var _stop_walk_entry_speed := 0.0
var _stop_walk_span := 1.0
var _stop_walk_dir := Vector3.ZERO

var _footstep_player_3d: AudioStreamPlayer3D = null


## Where the current pull-up started and where it ends, in world space, and how
## far along it is as a fraction. See _drive_climb().
var _climb_from := Vector3.ZERO
var _climb_to := Vector3.ZERO
var _climb_t := 0.0
## Duration the current pull-up runs for, set from its height. See _try_climb().
var _climb_span := 1.0


## Called by the playground once the character instance is parented here.
func setup(visual: Node3D, follow_camera: Node3D) -> void:
	character = visual
	camera = follow_camera
	# The one full reset. A clip only drives the bones it has tracks for, and the
	# model ships a T-pose the importer leaves in the unnamed library; without
	# this the first frame can come from whichever of the two got there first.
	# Everything after it is the tree's business - an AnimationTree blends up
	# from the rest pose every frame, so untracked bones cannot go stale.
	var skeleton := character.get("skeleton") as Skeleton3D
	if skeleton != null:
		skeleton.reset_bone_poses()

	var height: float = visual.get("body_height")
	_stand_height = height if height > 0.1 else 1.75
	_capsule = _find_capsule()

	var rig := CharacterAnimRig.new()
	if not rig.build(visual, action_blend, brake_rate):
		push_error("%s: character has no AnimationPlayer" % name)
		return
	_rig = rig
	_probes.setup(self)
	_vfx.setup(self)
	_weapons.bind(_rig)
	# The one seam for render tiering: every scene that spawns a body through
	# setup() gets distance-based culling and a throttled mixer for free.
	CharacterLOD.attach(character, _rig.tree)
	if intent_source == null:
		intent_source = PlayerIntentSourceScript.new()
	state = State.IDLE
	_blend = Vector2.ZERO
	_stance = 0.0
	_brake_cooldown_left = 0.0
	_intent.clear()
	_queued_jump = false
	_queued_roll = false
	_queued_buttons = 0
	# With nothing equipped this is the built-in single swing, so the attack path
	# works before any weapon exists and needs no "if there is a graph" branch.
	set_weapon_graph({})
	set_weapon_stance(0.0)
	_action_left = 0.0
	_action_slides = false
	_dash_left = 0.0
	_vfx.end_dash()
	_vfx.seal_trail()
	_swing_amount = 0.0
	_roll_cooldown_left = 0.0
	_coyote_left = 0.0
	_jump_buffered = 0.0
	_air_peak_y = global_position.y
	_take_off_y = global_position.y
	_air_speed = 0.0
	_landing_take = ""
	_landing_rate = 1.0
	_rig.stop_action()

	if _footstep_player_3d == null or not is_instance_valid(_footstep_player_3d):
		_footstep_player_3d = AudioStreamPlayer3D.new()
		_footstep_player_3d.name = "FootstepAudio3D"
		_footstep_player_3d.unit_size = 1.6
		_footstep_player_3d.max_distance = 15.0
		_footstep_player_3d.bus = "Master"
		_footstep_player_3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(_footstep_player_3d)


func _play_footstep_audio(vol_db: float, pitch: float) -> void:
	if not footstep_enabled:
		return
	if _footstep_player_3d != null and is_instance_valid(_footstep_player_3d):
		var stream := AudioManagerScript.get_random_footstep_stream()
		if stream != null:
			_footstep_player_3d.stream = stream
			_footstep_player_3d.volume_db = vol_db
			_footstep_player_3d.pitch_scale = pitch
			_footstep_player_3d.play()
	else:
		AudioManagerScript.play_footstep(vol_db, pitch)


func _play_land_audio(vol_db: float) -> void:
	if not footstep_enabled:
		return
	if _footstep_player_3d != null and is_instance_valid(_footstep_player_3d):
		var stream := AudioManagerScript.get_land_stream()
		if stream != null:
			_footstep_player_3d.stream = stream
			_footstep_player_3d.volume_db = vol_db
			_footstep_player_3d.pitch_scale = 0.9
			_footstep_player_3d.play()
	else:
		AudioManagerScript.play_land_sound(vol_db)


# --- what drives this character --------------------------------------------

## Directly set movement vectors (move, heading, running, crouching) for manual steering.
func drive(move: Vector2, heading: float, running := false, crouching := false) -> void:
	_intent.move = move.limit_length(1.0)
	_intent.heading = heading
	_intent.run = running
	_intent.crouch = crouching


## The edge half: jump or climb, whichever the ledge probe decides. Latched until
## the next physics frame looks at it, so a caller running at its own pace can
## neither miss the window nor have one press counted twice.
##
## Unlike drive(), this is safe to mix with an IntentSource: the two are OR-ed.
func request_jump() -> void:
	_queued_jump = true


## The other edge: roll. Latched the same way.
func request_roll() -> void:
	_queued_roll = true


## Request a sword attack. Latched until the next physics frame.
##
## Kept as the name for the primary button because plenty of callers already say
## it. What it actually asks for is whatever the equipped weapon's graph opens on
## `attack`, which for a bare-handed character is the built-in swing.
func request_attack() -> void:
	request_button("attack")


## The general form: ask for one of CharacterIntent.BUTTONS by name. Latched the
## same way, and OR-ed with whatever an IntentSource says, so a bot can drive a
## combo with no keyboard involved.
##
## An unknown name is ignored rather than an error - a weapon configured for a
## button this build does not have should be a move that never fires, not a crash.
func request_button(button: String) -> void:
	_queued_buttons |= int(CharacterIntent.BUTTONS.get(button, 0))


## The yaw a player's input is expressed in. Read by PlayerIntentSource - it
## lives here rather than there because the camera is the controller's to know
## about, and a source should not have to go looking for one.
func view_yaw() -> float:
	return float(camera.get("yaw")) if camera != null else rotation.y


## Returns world position of character head bone or calculated eye height.
func get_head_position() -> Vector3:
	if character != null and character.has_method("get_head_position"):
		var pos: Vector3 = character.call("get_head_position")
		if pos != Vector3.ZERO:
			return pos
	return global_position + Vector3.UP * (_stand_height * 0.88)


## Returns world position at the front of character head/eyes.
func get_head_front_position() -> Vector3:
	if character != null and character.has_method("get_head_front_position"):
		var pos: Vector3 = character.call("get_head_front_position")
		if pos != Vector3.ZERO:
			return pos
	return global_position + Vector3.UP * (_stand_height * 0.88)


func _find_capsule() -> CollisionShape3D:
	for child in get_children():
		var shape := child as CollisionShape3D
		if shape != null and shape.shape is CapsuleShape3D:
			return shape
	return null


## What the camera asks to decide whether it is orbiting or steering. The
## deceleration tail counts as moving: the shot should stay behind the character
## while it is still sliding to a halt.
func is_moving() -> bool:
	return state != State.IDLE or speed() > 0.1


func speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func state_name() -> String:
	match state:
		State.WALK: return "走 / walk"
		State.RUN: return "跑 / run"
		State.CROUCH: return "蹲 / crouch"
		State.BRAKING: return "刹停 / braking"
		State.JUMPING: return "跳 / jump"
		State.FALLING: return "下落 / falling"
		State.CLIMBING: return "攀爬 / climb"
		State.LANDING: return "落地 / landing"
		State.ROLLING: return "翻滚 / roll"
		State.ATTACKING: return "攻击 / attack"
		State.HIT_STUN: return "受击 / hit"
		State.SITTING: return "就座 / sitting"
		_: return "站 / idle"


## Whether the character is standing on something and doing something ordinary
## with it. The gate on every action: an action that could interrupt another one
## would need a rule for every pair of them, and there is no call for that yet.
func _grounded_state() -> bool:
	return state == State.IDLE or state == State.WALK or state == State.RUN \
		or state == State.CROUCH


func _physics_process(delta: float) -> void:
	if _rig == null:
		return
	_gather_intent(delta)
	_brake_cooldown_left = maxf(_brake_cooldown_left - delta, 0.0)
	_roll_cooldown_left = maxf(_roll_cooldown_left - delta, 0.0)
	_jump_buffered = maxf(_jump_buffered - delta, 0.0)

	if state == State.SITTING:
		_drive_sitting(delta)
		_drive_animation(delta)
		_consume_intent()
		return

	if state != State.CLIMBING:
		if not is_on_floor():
			if state == State.ATTACKING:
				velocity.y = 0.0
			else:
				velocity.y -= _gravity * delta
		_consider_actions()

	# Checked again, and after the request rather than before it: a climb that
	# started this frame has to take this frame. It is drawn onto the world rather
	# than pushed through it - see _drive_climb() - so it neither falls nor
	# slides, and the frame ends here.
	if state == State.CLIMBING:
		_drive_climb(delta)
		_drive_animation(delta)
		_consume_intent()
		return

	match state:
		State.BRAKING: _drive_brake(delta)
		State.ROLLING: _drive_roll(delta)
		State.LANDING: _drive_landing(delta)
		State.JUMPING, State.FALLING: _drive_air(delta)
		State.ATTACKING: _drive_attack(delta)
		State.HIT_STUN: _drive_hit_stun(delta)
		_: _drive_locomotion(delta)

	move_and_slide()
	if _step_up_state():
		_probes.try_step_up()
	# After the slide, all three: whether the ground is still there is only known
	# once the body has tried to move onto it, walking into a wall should stop the
	# legs too, and the effect wants where the body actually got to.
	_settle_ground(delta)
	_update_footsteps(delta)
	# Past the end of the lunge too: the fade has to come back up afterwards.
	if _vfx.dash_running():
		_vfx.drive_dash(delta, _dash_left > 0.0)
	# A swing cut short by a roll, a hit or a fall leaves the state without going
	# through _drive_attack's own ending. One guard covers every such path.
	if _vfx.has_trail() and state != State.ATTACKING:
		_vfx.seal_trail()
	_drive_animation(delta)
	_consume_intent()


## Whether a kerb is this state's business at all. See PlayerProbes.try_step_up().
func _step_up_state() -> bool:
	match state:
		State.CLIMBING, State.JUMPING, State.FALLING, State.ROLLING, State.LANDING:
			return false
	return true


# --- intent ----------------------------------------------------------------

## This frame's decisions, from the source if there is one and from whatever was
## last asked for if there is not, plus anything latched since the last frame.
func _gather_intent(delta: float) -> void:
	if intent_source != null:
		intent_source.poll(self, delta, _intent)
	if _queued_jump:
		_intent.jump = true
		_queued_jump = false
	if _queued_roll:
		_intent.roll = true
		_queued_roll = false
	if _queued_buttons != 0:
		# OR-ed rather than assigned: a source writes the keyboard's buttons every
		# poll, and the scene's mouse clicks arrive here. Both have to survive.
		_intent.buttons |= _queued_buttons
		_queued_buttons = 0


## The edges are consumed, the held state is not. A source that writes every
## field every poll will overwrite these anyway; one that fires and forgets - a
## bot, a trigger volume - relies on this to have its jump counted exactly once.
func _consume_intent() -> void:
	_intent.jump = false
	_intent.roll = false
	_intent.buttons = 0


## Everything a request can start, in the order they beat each other.
##
## Jump and climb are one request on purpose: which of the two you get is the
## ledge probe's answer, not a second key. The buffer is what makes that request
## survive being made a frame or two early - the common case being asking to
## climb while the last of a fall is still playing out.
func _consider_actions() -> void:
	if _intent.jump:
		_jump_buffered = jump_buffer
	if not _grounded_state():
		return
	var opening := _weapons.graph.begin(_intent.buttons)
	if not opening.is_empty():
		_begin_weapon_action(opening)
		_intent.buttons = 0
		return
	if _intent.roll and roll_enabled and _roll_cooldown_left <= 0.0:
		_begin_roll()
		return
	if _jump_buffered <= 0.0:
		return
	# On the ground, or close enough to it that the ledge just walked off should
	# not have cost a jump.
	if not is_on_floor() and _coyote_left <= 0.0:
		return
	if climb_enabled and _try_climb():
		return
	if jump_enabled:
		_begin_jump()


func _drive_locomotion(delta: float) -> void:
	var input := _intent.move
	var crouching := _intent.crouch

	if input == Vector2.ZERO:
		state = State.CROUCH if crouching else State.IDLE
		_fold(crouching, delta)
		if camera != null and bool(camera.get("is_first_person")):
			rotation.y = rotate_toward(rotation.y, _intent.heading, turn_rate * delta)

		if _stop_walk_sliding and _action_left > 0.0:
			_action_left -= delta
			var t: float = clampf(_action_left / maxf(_stop_walk_span, 0.01), 0.0, 1.0)
			var cur_s: float = _stop_walk_entry_speed * (t * t)
			velocity.x = _stop_walk_dir.x * cur_s
			velocity.z = _stop_walk_dir.z * cur_s
			if _action_left <= 0.0:
				_action_left = 0.0
				_stop_walk_sliding = false
				velocity.x = 0.0
				velocity.z = 0.0
				_rig.stop_action()
		else:
			var settle: float = 1.0 - exp(-delta * acceleration)
			velocity.x = lerpf(velocity.x, 0.0, settle)
			velocity.z = lerpf(velocity.z, 0.0, settle)
			if Vector2(velocity.x, velocity.z).length_squared() < 0.001:
				velocity.x = 0.0
				velocity.z = 0.0
			if _action_left > 0.0:
				_action_left -= delta
				if _action_left <= 0.0:
					_action_left = 0.0
					_rig.stop_action()
		return

	if _stop_walk_sliding:
		_stop_walk_sliding = false
		_action_left = 0.0
		_rig.stop_action()
	elif _action_left > 0.0:
		_action_left -= delta
		if _action_left <= 0.0:
			_action_left = 0.0
			_rig.stop_action()

	var running := _intent.run and not crouching
	var wanted := _wish_direction()

	var target_yaw := _intent.heading
	if camera == null or not bool(camera.get("is_first_person")):
		if wanted.length_squared() > 0.001:
			target_yaw = atan2(wanted.x, wanted.z)
	rotation.y = rotate_toward(rotation.y, target_yaw, turn_rate * delta)

	if crouching:
		wanted *= crouch_speed
	else:
		wanted *= run_speed if running else walk_speed

	var blend: float = 1.0 - exp(-delta * acceleration)
	velocity.x = lerpf(velocity.x, wanted.x, blend)
	velocity.z = lerpf(velocity.z, wanted.z, blend)

	if crouching:
		state = State.CROUCH
	else:
		state = State.RUN if running else State.WALK
	_fold(crouching, delta)

	if state == State.RUN:
		_consider_brake()


## The way the character is being asked to go, as a unit vector in world space,
## or its own facing when it is being asked for nothing. See the note above on
## why forward is +basis.z and right is -basis.x.
func _wish_direction() -> Vector3:
	if _intent.move == Vector2.ZERO:
		return global_basis.z
	var frame := Basis.from_euler(Vector3(0.0, _intent.heading, 0.0))
	return (frame.z * _intent.move.y - frame.x * _intent.move.x).normalized()


func _update_footsteps(delta: float) -> void:
	if not footstep_enabled or not is_on_floor():
		_footstep_distance = 0.0
		return

	if state != State.WALK and state != State.RUN and state != State.CROUCH and state != State.BRAKING:
		return

	var h_vel := Vector2(velocity.x, velocity.z)
	var speed_val := h_vel.length()
	if speed_val < 0.2:
		return

	# Calibrated step stride distance (meters per individual foot contact)
	var step_interval := 0.62 # Walk stride: 1 step per ~0.56s at 1.1 m/s
	var step_vol := -13.0
	var base_pitch := 1.0

	if state == State.RUN:
		step_interval = 1.15 # Sprint stride: 1 step per ~0.32s at 3.6 m/s (matches sprint animation footfalls!)
		step_vol = -7.5
		base_pitch = 1.06
	elif state == State.CROUCH:
		step_interval = 0.38
		step_vol = -18.0
		base_pitch = 0.92
	elif state == State.BRAKING:
		step_interval = 0.55
		step_vol = -10.0
		base_pitch = 0.95

	_footstep_distance += speed_val * delta
	if _footstep_distance >= step_interval:
		_footstep_distance = fmod(_footstep_distance, step_interval)
		_play_footstep_audio(step_vol, base_pitch * randf_range(0.96, 1.04))


## Puts `ground_speed` on the velocity along the character's own facing, leaving
## the vertical alone. What the scripted slides - the roll, and the landing that
## rolls out of one - move with: they are committed to a direction chosen when
## they started, and steering out of them mid-take would show a forward roll
## going sideways.
func _slide_forward(ground_speed: float) -> void:
	var forward := global_basis.z
	velocity.x = forward.x * ground_speed
	velocity.z = forward.z * ground_speed


## Folds into or out of the crouch, collision shape included. The capsule is
## resized rather than swapped so the radius, which the playground picked from
## the character's height, survives.
func _fold(crouching: bool, delta: float) -> void:
	var fold: float = 1.0 - exp(-delta * crouch_rate)
	_stance = lerpf(_stance, 1.0 if crouching else 0.0, fold)
	if _capsule == null:
		return
	var shape := _capsule.shape as CapsuleShape3D
	if shape == null:
		return
	shape.height = maxf(lerpf(_stand_height, _stand_height * crouch_height, _stance),
		shape.radius * 2.0 + 0.01)
	_capsule.position.y = shape.height * 0.5


## Fires the skid when a wall taller than the character is close enough that a
## run cannot be walked out of.
##
## Cast from the top of the head, which is what makes it "taller than the
## character" rather than "anything at all": a knee-high box does not reach the
## probe, and running into one is the physics engine's problem, not an animation.
func _consider_brake() -> void:
	if not brake_enabled or _brake_cooldown_left > 0.0:
		return
	# A body with a jump buffered is not about to skid: the run-up to a gap jump
	# aims at ground on the far side, and anything standing behind that ground is
	# inside brake_distance by the time the take-off point arrives. Skidding there
	# sheds exactly the speed the arc was planned for.
	if _jump_buffered > 0.0:
		return
	if speed() < run_speed * 0.6:
		return
	var head: float = _stand_height * lerpf(1.0, crouch_height, _stance)
	var from := global_position + Vector3.UP * head
	var query := PhysicsRayQueryParameters3D.create(
		from, from + global_basis.z * brake_distance)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	_begin_brake(from.distance_to(hit.position as Vector3))


func _begin_brake(distance: float) -> void:
	var entry := speed()
	# Constant deceleration that comes to rest exactly at the wall: v^2 / 2s.
	# Picked per skid rather than exported, so it is right whatever speed the
	# character happened to be carrying and however late the wall was spotted.
	var room := maxf(distance - brake_margin, 0.1)
	_brake_decel = maxf(entry * entry / (2.0 * room), 0.01)

	var length := _rig.clip_length(CharacterAnimRig.CLIP_BRAKE, 1.0)
	_brake_left = length / maxf(brake_rate, 0.01) + 0.1

	state = State.BRAKING
	_rig.fire_brake(brake_rate)


## The skid. Input is ignored for its duration, which is under a second at double
## speed; steering out of it would leave the take playing over a walk.
func _drive_brake(delta: float) -> void:
	var now := speed()
	var next := maxf(now - _brake_decel * delta, 0.0)
	if now > 0.001:
		var keep: float = next / now
		velocity.x *= keep
		velocity.z *= keep
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	_brake_left -= delta
	if next <= 0.05 or _brake_left <= 0.0:
		state = State.IDLE
		_brake_cooldown_left = brake_cooldown


func _drive_sitting(delta: float) -> void:
	velocity = Vector3.ZERO
	match _sitting_phase:
		SittingPhase.ENTERING:
			_action_left -= delta
			if _action_left <= 0.0:
				_sitting_phase = SittingPhase.SEATED
				_rig.play_action("sitting_idle", 1.0)
			elif _intent.move.length_squared() > 0.05 or _intent.jump or _queued_jump:
				stand_up()
		SittingPhase.SEATED:
			if _intent.move.length_squared() > 0.05 or _intent.jump or _queued_jump:
				stand_up()
		SittingPhase.EXITING:
			_action_left -= delta
			if _action_left <= 0.0:
				_sitting_phase = SittingPhase.NONE
				state = State.IDLE
				_rig.stop_action()


func play_stop_walk(rate: float = 1.8) -> void:
	var len_val := _rig.clip_length(CharacterAnimRig.CLIP_STOP_WALK, 1.2)
	_stop_walk_span = len_val / rate
	_action_left = _stop_walk_span
	_stop_walk_entry_speed = speed()
	if _stop_walk_entry_speed < 0.2:
		_stop_walk_entry_speed = walk_speed * 0.7
	var h_vel := Vector3(velocity.x, 0.0, velocity.z)
	_stop_walk_dir = h_vel.normalized() if h_vel.length_squared() > 0.01 else global_basis.z
	_stop_walk_sliding = true
	_rig.play_action("stop_walking", rate)


func sit_down(seat_pos: Vector3, seat_yaw: float) -> void:
	global_position = seat_pos
	rotation.y = seat_yaw
	velocity = Vector3.ZERO
	state = State.SITTING
	_sitting_phase = SittingPhase.ENTERING
	var len_val := _rig.clip_length(CharacterAnimRig.CLIP_SIT_ENTER, 1.3)
	var rate := 1.3
	_action_left = len_val / rate
	_rig.play_action("sitting_enter", rate)


func stand_up() -> void:
	if state != State.SITTING or _sitting_phase == SittingPhase.EXITING:
		return
	_sitting_phase = SittingPhase.EXITING
	var len_val := _rig.clip_length(CharacterAnimRig.CLIP_SIT_EXIT, 1.0)
	var rate := 1.5
	_action_left = len_val / rate
	_rig.play_action("sitting_exit", rate)


func is_sitting() -> bool:
	return state == State.SITTING


# --- off the ground --------------------------------------------------------

## Whether the ground is still there, and what that means. Runs after
## move_and_slide(), because until the body has tried to move onto it, is_on_floor()
## is answering last frame's question.
func _settle_ground(delta: float) -> void:
	if is_on_floor():
		_coyote_left = coyote_time
		if velocity.y <= 0.0 and (state == State.JUMPING or state == State.FALLING):
			_land()
		_air_peak_y = global_position.y
		_take_off_y = global_position.y
		return

	_coyote_left = maxf(_coyote_left - delta, 0.0)
	_air_peak_y = maxf(_air_peak_y, global_position.y)
	if state == State.JUMPING or state == State.FALLING or state == State.ATTACKING or state == State.HIT_STUN:
		return
	# A step down, a slope, a bump at the top of a run: all of them leave the
	# floor for a frame or two, and none of them is a fall. The grace period is
	# the same one that keeps a jump off a ledge from being eaten.
	if _coyote_left > 0.0:
		return
	_begin_fall()


func _begin_jump() -> void:
	velocity.y = jump_speed
	state = State.JUMPING
	_action_left = jump_start_time
	_coyote_left = 0.0
	_jump_buffered = 0.0
	_air_peak_y = global_position.y
	_take_off_y = global_position.y
	_air_speed = speed()
	_landing_take = ""
	_rig.play_action("jump_start", jump_start_rate)
	if footstep_enabled:
		_play_footstep_audio(-8.0, 1.0)


## Walking off something, which needs no request and gets a different take from
## jumping off it. That difference is the reason FALLING and JUMPING are two
## states rather than one with a flag.
func _begin_fall() -> void:
	state = State.FALLING
	_action_left = 0.0
	_landing_take = ""
	_rig.play_action("climb_down" if fall_climb_down else "jump_air", 1.0)


## Processes in-air velocity calculations and air steering control.
func _drive_air(delta: float) -> void:
	_air_speed = speed()
	_fold(false, delta)
	if _intent.move != Vector2.ZERO:
		var wanted := _wish_direction() * maxf(speed(), walk_speed)
		var target_yaw := _intent.heading
		if camera == null or not bool(camera.get("is_first_person")):
			if wanted.length_squared() > 0.001:
				target_yaw = atan2(wanted.x, wanted.z)
		rotation.y = rotate_toward(rotation.y, target_yaw,
			turn_rate * air_control * delta)
		var blend: float = 1.0 - exp(-delta * acceleration * air_control)
		velocity.x = lerpf(velocity.x, wanted.x, blend)
		velocity.z = lerpf(velocity.z, wanted.z, blend)

	# The launch take is anticipation for a push-off that already happened; once
	# the body is genuinely in the air the loop is the pose. Only a jump has one -
	# a walk off a ledge goes straight to its own take and leaves `_action_left`
	# at zero.
	if _action_left > 0.0 and _landing_take == "":
		_action_left -= delta
		if _action_left <= 0.0:
			_rig.play_action("jump_air", 1.0)
	# Last, so that a landing coming up beats whatever the jump was going to do.
	_arm_landing()


## Configures landing type based on drop height and contact velocity.
func _landing_for(drop: float, ground_speed: float, takeoff_drop: float = 0.0) -> Array:
	if takeoff_drop >= land_roll_drop_min and ground_speed >= land_roll_speed_min:
		return ["land_roll", land_roll_recover, land_roll_lead]
	if drop >= land_roll_drop_min:
		return ["land_hard", land_hard_recover, land_hard_lead]
	return ["jump_land", jump_land_recover, 0.0]


## Pre-triggers landing animation in mid-air based on estimated impact time.
func _arm_landing() -> void:
	if (state != State.FALLING and state != State.JUMPING) or _landing_take != "" \
			or velocity.y > -land_arm_vy_min:
		return
	var impact := _probes.predict_impact()
	if impact.is_empty():
		return
	var ground: float = (impact.pos as Vector3).y
	var eta: float = impact.time
	var drop: float = maxf(_air_peak_y, global_position.y) - ground
	if drop < land_min_drop:
		return
	var pick := _landing_for(drop, speed(), _take_off_y - ground)
	if pick[0] == "land_roll" and not _probes.roll_has_ground(impact.pos as Vector3, velocity):
		pick = ["land_hard", land_hard_recover, land_hard_lead]
	var lead: float = pick[2]
	if eta > lead:
		return
	_landing_take = pick[0]
	_landing_recover = pick[1]
	var rate_mult: float = roll_rate if _landing_take == "land_roll" else 1.0
	_landing_rate = clampf((lead / maxf(eta, 0.01)) * rate_mult, 1.0, land_rate_cap)
	_rig.play_action(_landing_take, _landing_rate)


## Transitions actor state upon landing (absorb or roll recover).
func _land() -> void:
	var jumped := state == State.JUMPING
	velocity.y = 0.0
	_action_slides = false
	var take := _landing_take
	var recover := _landing_recover
	if footstep_enabled:
		_play_land_audio(-6.0)

	if jumped and take == "":
		take = "jump_land"
		recover = jump_land_recover
		_landing_rate = 1.6
		_rig.play_action(take, _landing_rate)
	elif take == "":
		var drop: float = maxf(_air_peak_y - global_position.y, 0.0)
		if drop < land_min_drop:
			state = State.IDLE
			_rig.stop_action()
			return
		var takeoff_drop: float = _take_off_y - global_position.y
		var contact_speed: float = maxf(speed(), _air_speed)
		var pick := _landing_for(drop, contact_speed, takeoff_drop)
		take = pick[0]
		recover = pick[1]
		_landing_rate = 1.6 if take == "jump_land" else land_rate_cap
		_rig.play_action(take, _landing_rate)

	# Downgrade land_roll if jump height drop does not warrant roll or if roll would slide off an edge.
	var actual_takeoff_drop: float = _take_off_y - global_position.y
	if take == "land_roll" and (actual_takeoff_drop < land_roll_drop_min or not _probes.roll_has_ground(global_position, velocity)):
		var actual_drop: float = maxf(_air_peak_y - global_position.y, 0.0)
		take = "land_hard" if actual_drop >= land_roll_drop_min else "jump_land"
		recover = land_hard_recover if take == "land_hard" else jump_land_recover
		_landing_rate = land_rate_cap if take == "land_hard" else 1.6
		_rig.play_action(take, _landing_rate)

	if take == "land_roll":
		# Roll out along whatever the body was already doing, or its own facing if
		# it dropped straight down. Snapped, for the same reason the roll is.
		var travel := Vector2(velocity.x, velocity.z)
		if travel.length() > 0.1:
			rotation.y = atan2(travel.x, travel.y)
		_action_slides = true
		_slide_entry = speed()
		_slide_speed = maxf(land_roll_speed, _slide_entry)
		_landing_rate = maxf(_landing_rate, roll_rate)
		_slide_span = recover / _landing_rate

	state = State.LANDING
	_action_left = recover / _landing_rate
	_landing_take = ""


func _drive_landing(delta: float) -> void:
	_fold(false, delta)
	if _action_slides:
		_slide_forward(_slide_pace(_action_left, _slide_span))
	else:
		var settle: float = 1.0 - exp(-delta * acceleration)
		velocity.x = lerpf(velocity.x, 0.0, settle)
		velocity.z = lerpf(velocity.z, 0.0, settle)
	_action_left -= delta
	if _action_left <= 0.0:
		state = State.IDLE
		_action_slides = false
		_rig.stop_action()


# --- the climb -------------------------------------------------------------

func _try_climb() -> bool:
	var ledge := _probes.find_ledge()
	if ledge == PlayerProbes.NO_LEDGE:
		return false
	_climb_from = global_position
	_climb_to = ledge
	_climb_t = 0.0
	# One cell pulls up in climb_duration_1m, two in climb_duration_2m; heights
	# in between interpolate, and heights outside clamp to the nearer end.
	var rise_m: float = clampf(ledge.y - _climb_from.y, 1.0, 2.0)
	_climb_span = lerpf(climb_duration_1m, climb_duration_2m, rise_m - 1.0)
	_jump_buffered = 0.0
	velocity = Vector3.ZERO
	# Square up to it first. The take pulls the body straight along its own
	# forward, so climbing a wall at thirty degrees to it puts a shoulder through
	# the wall on the way up.
	var across := Vector2(ledge.x - _climb_from.x, ledge.z - _climb_from.z)
	if across.length() > 0.01:
		rotation.y = atan2(across.x, across.y)
	state = State.CLIMBING
	_rig.play_action("climb", _rig.fit_rate("climb", _climb_span))
	return true



## Linearly interpolates character position along the climb path (disables physics/collisions).
func _drive_climb(delta: float) -> void:
	_fold(false, delta)
	_climb_t += delta / maxf(_climb_span, 0.01)
	var t: float = clampf(_climb_t, 0.0, 1.0)
	var rise: float = _ease(clampf(t / maxf(climb_rise_share, 0.05), 0.0, 1.0))
	var start: float = climb_rise_share * 0.6
	var reach: float = _ease(clampf((t - start) / maxf(1.0 - start, 0.05), 0.0, 1.0))
	global_position = Vector3(
		lerpf(_climb_from.x, _climb_to.x, reach),
		lerpf(_climb_from.y, _climb_to.y, rise),
		lerpf(_climb_from.z, _climb_to.z, reach))
	velocity = Vector3.ZERO
	if t < 1.0:
		return
	state = State.IDLE
	_coyote_left = coyote_time
	_air_peak_y = global_position.y
	_take_off_y = global_position.y
	_rig.stop_action()


# --- the roll --------------------------------------------------------------

func _begin_roll() -> void:
	# The take is a forward roll, so the body has to be pointed wherever the roll
	# is going before it starts. Snapped rather than turned into: a roll is a
	# committed move, and turning through the first frames of one would show the
	# character rolling sideways on the way round.
	var dir := _wish_direction()
	if dir.length_squared() > 0.001:
		rotation.y = atan2(dir.x, dir.z)
	state = State.ROLLING
	_action_left = roll_duration
	_action_slides = true
	_slide_entry = speed()
	_slide_speed = maxf(roll_speed, _slide_entry)
	_slide_span = roll_duration
	# Armed now rather than on the way out, so the cooldown is a gap between
	# rolls and not a window in which a second one can be queued.
	_roll_cooldown_left = roll_duration + roll_cooldown
	_rig.play_action("roll", roll_rate)


func _drive_roll(delta: float) -> void:
	_fold(false, delta)
	_slide_forward(_slide_pace(_action_left, _slide_span))
	_action_left -= delta
	if _action_left <= 0.0:
		state = State.IDLE
		_action_slides = false
		_rig.stop_action()
		if _intent.move != Vector2.ZERO:
			_drive_locomotion(0.0)


## Processes hit stun deceleration and duration expiration.
func _drive_hit_stun(delta: float) -> void:
	_fold(false, delta)
	var settle: float = 1.0 - exp(-delta * acceleration)
	velocity.x = lerpf(velocity.x, 0.0, settle)
	velocity.z = lerpf(velocity.z, 0.0, settle)
	_action_left -= delta
	if _action_left <= 0.0:
		state = State.IDLE
		_rig.stop_action()
		if _intent.move != Vector2.ZERO:
			_drive_locomotion(0.0)


## Applies hit reaction flinch and stun to character, extinguishing weapon VFX and interrupting attacks.
func apply_hit_reaction(hit_clip: String = "hit_chest", stun_time: float = 0.4) -> void:
	if _weapons.graph != null:
		_weapons.graph.reset()
	_vfx.extinguish_trail()
	_vfx.end_dash()
	_action_slides = false
	_dash_left = 0.0
	_swing_amount = 0.0
	state = State.HIT_STUN
	_action_left = stun_time
	if _rig != null:
		_rig.set_swing_amount(0.0)
		_rig.play_action(hit_clip, 1.0)


# --- the attack ------------------------------------------------------------

## Starts one node of the weapon's graph and hands it the clock.
##
## The graph is the only clock here. Roll and the landings count down an
## `_action_left` of their own; this one asks WeaponGraph.finished(), because the
## same number also decides when a cancel window opens and two clocks that have to
## agree eventually will not.
func _begin_weapon_action(id: String) -> void:
	var slot := _weapons.graph.slot_of(id)
	if slot < 0 or slot >= _rig.slots.size():
		push_warning("%s: weapon action '%s' has no slot" % [name, id])
		return
	var action := _weapons.graph.action_of(id)

	# Any full-body take still fading out gets out of the way first, but only on
	# the way in: re-requesting it on every link of a combo would restart its
	# cross-fade and show a frame of locomotion between two hits.
	if state != State.ATTACKING:
		_rig.stop_action()
	state = State.ATTACKING
	if not is_on_floor():
		velocity.y = 0.0
	_weapons.strokes += 1
	_weapons.graph.enter(id)
	# One ribbon per node, not per combo: each link is its own stroke, and its own
	# window into it. The outgoing one is left to fade rather than cut.
	_vfx.seal_trail()
	_vfx.begin_trail(action)
	# A lunge. Zero distance - the common case - leaves the body to the
	# deceleration in _drive_attack, which is what makes a standing swing stand.
	_action_slides = action.dash_distance > 0.0
	if _action_slides:
		_slide_speed = dash_speed
		# Distance over speed, capped at the take: the lunge runs inside the swing
		# now, so it may not outlive it. A distance that does not fit is covered
		# short - turn dash_speed up rather than the distance down.
		_dash_left = minf(action.dash_distance / maxf(dash_speed, 0.01),
			_weapons.graph.span_of(id))
		# FADE covers the whole distance in one go and hands back a spent lunge.
		_dash_left = _vfx.begin_dash(_slide_speed, _dash_left)
	else:
		_dash_left = 0.0
		_vfx.stop_trailing()

	# Whole body for a take that pins the character or carries it; upper body for
	# one it can walk through, so the legs stay with the blend space instead of
	# sliding along in the swing's own stance. Decided once per node - swapping
	# the filter mid-take would snap the legs from one pose to the other.
	_rig.set_swing_filter(action.lock_move or _action_slides)
	# At its own rate whether it lunges or not: the body travels while the take
	# plays, so there is no first frame to hold and no clock to hand back.
	_rig.play_swing(slot, action.rate)


## Runs the current node and lets the graph decide what happens next.
##
## A chained node is played directly rather than going through idle: the
## transition's own cross-fade is the join between two hits, and dropping to input
## 0 in between would show a frame of the walk cycle in the middle of a combo.
func _drive_attack(delta: float) -> void:
	_fold(false, delta)

	var next := _weapons.graph.advance(delta, _intent.buttons)
	if not next.is_empty():
		_begin_weapon_action(next)
		return

	_vfx.drive_trail(_weapons.graph.elapsed)

	if _action_slides:
		_drive_dash(delta)
	elif _weapons.graph.action_of(_weapons.graph.current).get("lock_move", true):
		var settle: float = 1.0 - exp(-delta * acceleration)
		velocity.x = lerpf(velocity.x, 0.0, settle)
		velocity.z = lerpf(velocity.z, 0.0, settle)
	else:
		_drive_attack_move(delta)

	if _weapons.graph.finished():
		state = State.IDLE
		_action_slides = false
		_dash_left = 0.0
		# The ribbon is sealed here rather than dropped: it fades on its own. The
		# fade-in is left running - _physics_process keeps calling it until the
		# body is solid again.
		_vfx.seal_dash()
		_vfx.seal_trail()
		_weapons.graph.reset()
		# No _rig.stop_action(): the swing is not on the action layer any more, and
		# the layer was already handed back on the way in. _drive_animation()
		# fades _swing_amount out from here.


## Walking while a take that does not lock movement plays. Capped at the walk and
## turned at a fraction of the usual rate: there is no running attack take, and
## the legs are the blend space's while the swing owns the torso.
func _drive_attack_move(delta: float) -> void:
	if _intent.move == Vector2.ZERO:
		var settle: float = 1.0 - exp(-delta * acceleration)
		velocity.x = lerpf(velocity.x, 0.0, settle)
		velocity.z = lerpf(velocity.z, 0.0, settle)
		return
	var wanted := _wish_direction()
	var target_yaw := _intent.heading
	if camera == null or not bool(camera.get("is_first_person")):
		if wanted.length_squared() > 0.001:
			target_yaw = atan2(wanted.x, wanted.z)
	rotation.y = rotate_toward(rotation.y, target_yaw,
		turn_rate * attack_turn * delta)
	wanted *= walk_speed
	var blend: float = 1.0 - exp(-delta * acceleration)
	velocity.x = lerpf(velocity.x, wanted.x, blend)
	velocity.z = lerpf(velocity.z, wanted.z, blend)


## The lunge.
##
## Flat out along the facing at `dash_speed` until the distance is covered, then a
## dead stop for the rest of the take. No taper: what makes it read as a lunge
## rather than as a run is that the body is only ever at speed or at rest. The
## take plays through all of it.
func _drive_dash(delta: float) -> void:
	if _dash_left <= 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	_dash_left -= delta
	_slide_forward(_slide_speed)



## Calculates and returns speed for scripted slide sequences.
func _slide_pace(left: float, span: float) -> float:
	var t: float = 1.0 - clampf(left / maxf(span, 0.01), 0.0, 1.0)
	var pace: float = lerpf(_slide_entry, _slide_speed, minf(t / 0.12, 1.0))
	return pace * lerpf(1.0, 0.35, smoothstep(0.55, 1.0, t))


## Smoothstep, so a scripted path starts and finishes without a corner in it.
func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


## Maps character velocity to BlendSpace2D points and drives AnimationTree parameters.
func _drive_animation(delta: float) -> void:
	var local := global_basis.inverse() * Vector3(velocity.x, 0.0, velocity.z)
	# +Z forward, -X right, as in _drive_locomotion.
	var ground := Vector2(-local.x, local.z)
	var ground_speed := ground.length()

	var target := Vector2.ZERO
	var diamond := absf(ground.x) + absf(ground.y)
	if diamond > 0.001:
		var direction := ground / diamond
		var gait := _gait_axis(ground_speed)
		# The sidestep axis stops at the walk ring while the gait axis carries on
		# to the sprint. Same reason Shift is gated above: there is nothing out
		# there to blend towards.
		target = Vector2(direction.x * minf(gait, 1.0), direction.y * gait)

	var chase: float = 1.0 - exp(-delta * blend_rate)
	_blend = _blend.lerp(target, chase)
	_rig.set_gait(_blend)
	_rig.set_fold(_stance)

	# The stance take owns the upper body at rest and hands it back as the gait
	# comes up: by walking pace the whole pose is the locomotion clip's - the
	# weapon's own, when it configured one, otherwise the bare-handed take.
	# Read off `_blend` rather than the velocity so it inherits blend_rate's lag.
	_rig.set_stance_amount(
		_rig.stance_weight * (1.0 - clampf(_blend.length(), 0.0, 1.0)))

	# The swing layer fades on the same clock the action layer cross-fades on, so
	# a take that ends hands the pose back instead of popping off it.
	_swing_amount = move_toward(_swing_amount,
		1.0 if state == State.ATTACKING else 0.0,
		delta / maxf(action_blend, 0.01))
	_rig.set_swing_amount(_swing_amount)

	# One dimension for the crouch, so every direction of travel shows the same
	# shuffle - reversed when the travel is mostly backwards, because that is the
	# one case where playing it forwards reads as moonwalking.
	var crouch_gait: float = clampf(ground_speed / maxf(crouch_speed, 0.01), 0.0, 1.0)
	if ground.y < 0.0 and absf(ground.y) >= absf(ground.x):
		crouch_gait = -crouch_gait
	_rig.set_crouch_gait(crouch_gait)

	# The forward clips are in place and carry no travel to match a speed
	# against, so they play straight. The sidesteps were performed at a known
	# pace and the body does walk_speed, so the correction is applied at the
	# sidestep poles and faded out towards the middle - and out again towards the
	# crouch, which has no sidestep for it to be correcting.
	var sidestep: float = lerpf(1.0, walk_speed / maxf(_rig.strafe_speed, 0.01),
		absf(_blend.x))
	_rig.set_stride(lerpf(sidestep, 1.0, _stance))


## Ground speed on the blend space's gait axis: 1.0 at walking pace, 2.0 at a
## sprint. Piecewise because the two are not a fixed ratio - either @export can
## be turned without the other, and the clips sit where they sit.
func _gait_axis(ground_speed: float) -> float:
	if ground_speed <= walk_speed:
		return clampf(ground_speed / maxf(walk_speed, 0.01), 0.0, 1.0)
	return clampf(1.0 + (ground_speed - walk_speed)
		/ maxf(run_speed - walk_speed, 0.01), 1.0, 2.0)


# --- what the equipped weapon changes ---------------------------------------
#
# The façade EquipmentManager and the weapon panel talk to. Every one of these
# forwards; the layer that does the work is PlayerWeapons.

## Loads weapon behavior graph configuration into the swing layer's slots.
func set_weapon_graph(config: Dictionary) -> void:
	_weapons.set_graph(config)
	# Mid-swing when the weapon changed: the take under the character has just
	# been replaced, so hand the pose back rather than finish someone else's combo.
	if state == State.ATTACKING:
		state = State.IDLE
		_action_slides = false
		_dash_left = 0.0
		_vfx.end_dash()
		_vfx.seal_trail()


func set_weapon_stance(blend_amount: float) -> void:
	_weapons.set_stance(blend_amount)


func set_weapon_locomotion(idle_clip: String, walk_clip: String, run_clip: String) -> void:
	_weapons.set_locomotion(idle_clip, walk_clip, run_clip)


func set_weapon_stance_clip(clip: String) -> void:
	_weapons.set_stance_clip(clip)


func set_weapon_stance_filter(bone_name: String) -> void:
	_weapons.set_stance_filter(bone_name)


## The blade the trail reads its anchors off, and what it draws.
func set_weapon_trail(cfg: Dictionary, item) -> void:
	_vfx.set_trail(cfg, item)


func weapon_stroke_count() -> int:
	return _weapons.strokes


## current_weapon_action(): weapon graph node id playing now, "" at rest.
func current_weapon_action() -> String:
	return _weapons.current_action()


## Returns true if currently in ATTACKING state and current weapon action permits damage.
func can_deal_damage() -> bool:
	return _weapons.can_deal_damage(state == State.ATTACKING)


## Registers a weapon hit on the current action node.
func register_weapon_hit() -> void:
	_weapons.register_hit()


## Hits registered during current action node. 0 at rest or before any hit.
func weapon_hit_count() -> int:
	return _weapons.graph.hit_count if _weapons.graph != null else 0


## Returns true if current weapon action is within or approaching combo trigger window.
func is_weapon_in_link_window() -> bool:
	return state == State.ATTACKING and _weapons.is_in_link_window()


# --- replication -------------------------------------------------------------

## force_network_anim(): drives a replicated body's action layer + state from a snapshot.
## Pre: setup() done. Post: state mirrors state_val (<0 leaves it); action layer restarts on non-empty name.
func force_network_anim(action_name: String, state_val: int) -> void:
	if state_val >= 0:
		state = state_val as State
	if not action_name.is_empty() and _rig != null:
		_rig.play_action(action_name, 1.0)


## force_network_swing(): cosmetic weapon swing for a replicated body (no physics, no trail).
## Pre: setup() done, weapon equipped. Post: swing layer plays action_id's clip, state=ATTACKING.
func force_network_swing(action_id: String) -> void:
	if _weapons.graph == null or _rig == null:
		return
	var slot := _weapons.graph.slot_of(action_id)
	if slot < 0 or slot >= _rig.slots.size():
		return
	var action := _weapons.graph.action_of(action_id)
	_rig.set_swing_filter(bool(action.get("lock_move", true))
		or float(action.get("dash_distance", 0.0)) > 0.0)
	state = State.ATTACKING
	_rig.play_swing(slot, float(action.get("rate", 1.0)))


## force_network_action(): plays a one-shot action-layer take on a replicated body (roll, hit, death).
func force_network_action(action_name: String, rate: float = 1.0) -> void:
	if action_name.is_empty() or _rig == null:
		return
	_rig.play_action(action_name, rate)


func drive_network_step(delta: float) -> void:
	if _rig != null:
		_drive_animation(delta)


## Resets all combat states, AnimationTree overrides, and locomotion parameters.
func reset_combat_state() -> void:
	state = State.IDLE
	velocity = Vector3.ZERO
	_action_slides = false
	_dash_left = 0.0
	_roll_cooldown_left = 0.0
	_brake_cooldown_left = 0.0
	_jump_buffered = 0.0
	_blend = Vector2.ZERO
	_vfx.extinguish_trail()
	_vfx.end_dash()
	_weapons.reset()
	if character != null and character.player != null:
		character.player.stop()
	if _rig != null:
		_rig.stop_action()
		_rig.reset()
