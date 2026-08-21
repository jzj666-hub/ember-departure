class_name PlayerController
extends CharacterBody3D
## Character controller handling locomotion (WASD, sprint, crouch), gravity, jumps, rolls, ledges, and weapon graph states.
## Drives a runtime AnimationTree.

const PlayerIntentSourceScript = preload("res://scripts/player_intent_source.gd")
const AudioManagerScript = preload("res://scripts/audio_manager.gd")

@export var footstep_enabled := true
var _footstep_distance := 0.0

const CLIP_IDLE := "idle"
const CLIP_WALK := "walk"
const CLIP_WALK_BACK := "standing_torch_walk_back"
const CLIP_RUN := "sprint"
const CLIP_STRAFE_LEFT := "left_strafe_walking"
const CLIP_STRAFE_RIGHT := "right_strafe_walking"
const CLIP_CROUCH_IDLE := "crouch_idle"
const CLIP_CROUCH_WALK := "crouch_fwd"
const CLIP_BRAKE := "run_to_stop"

## The action layer's takes. None of these is a cycle and none of them blends
## with anything - one plays at a time, over the top of everything else.
const CLIP_JUMP_START := "jump_start"
const CLIP_JUMP_AIR := "jump"
const CLIP_JUMP_LAND := "jump_land"
const CLIP_CLIMB := "braced_hang_to_crouch"
const CLIP_CLIMB_DOWN := "climbing_down"
const CLIP_LAND := "landing"
const CLIP_LAND_HARD := "hard_landing"
const CLIP_LAND_ROLL := "falling_to_roll"
const CLIP_ROLL := "roll"
## What the upper body does while simply holding something, until a weapon's own
## configuration replaces it. See set_weapon_stance_clip().
const CLIP_SWORD_IDLE := "sword_idle"

## Alternate clip fallbacks for missing animation assets.
const ALTERNATES := {
	CLIP_CLIMB: "climbing",
}

## Lower blend tree clips with root translation flattening flags.
const CLIPS := {
	CLIP_IDLE: false,
	CLIP_WALK: false,
	CLIP_WALK_BACK: true,
	CLIP_RUN: false,
	CLIP_STRAFE_LEFT: true,
	CLIP_STRAFE_RIGHT: true,
	CLIP_CROUCH_IDLE: false,
	CLIP_CROUCH_WALK: true,
	CLIP_BRAKE: true,
}
## The one clip that is a take, not a cycle.
const ONE_SHOT_CLIPS := [CLIP_BRAKE]
## The two whose pace has to be known, because the body moves at a speed of its
## own while they play and the two have to be reconciled.
const MEASURED_CLIPS := [CLIP_STRAFE_LEFT, CLIP_STRAFE_RIGHT]

## The retargeted skeleton's hips, as every clip in the library addresses it.
const HIPS_TRACK := "%GeneralSkeleton:Hips"

## Gait points in 2D blend space (x=strafe, y=gait speed).
const POINTS := [
	["idle", CLIP_IDLE, Vector2(0.0, 0.0), false],
	["walk", CLIP_WALK, Vector2(0.0, 1.0), false],
	["sprint", CLIP_RUN, Vector2(0.0, 2.0), false],
	["back", CLIP_WALK_BACK, Vector2(0.0, -1.0), false],
	["left", CLIP_STRAFE_LEFT, Vector2(-1.0, 0.0), false],
	["right", CLIP_STRAFE_RIGHT, Vector2(1.0, 0.0), false],
]
const P_IDLE := 0
const P_WALK := 1
const P_RUN := 2
const P_BACK := 3
const P_LEFT := 4
const P_RIGHT := 5

## Spelled out rather than left to auto_triangles. Four of the six points are
## collinear on x = 0, which is exactly the input a Delaunay triangulation has no
## single right answer for.
const TRIANGLES := [
	Vector3i(P_IDLE, P_WALK, P_LEFT), Vector3i(P_IDLE, P_WALK, P_RIGHT),
	Vector3i(P_IDLE, P_BACK, P_LEFT), Vector3i(P_IDLE, P_BACK, P_RIGHT),
	Vector3i(P_WALK, P_RUN, P_LEFT), Vector3i(P_WALK, P_RUN, P_RIGHT),
]

## 1D blendspace points for crouching (no strafe support).
const CROUCH_POINTS := [
	["back", CLIP_CROUCH_WALK, -1.0, true],
	["idle", CLIP_CROUCH_IDLE, 0.0, false],
	["fwd", CLIP_CROUCH_WALK, 1.0, false],
]

const NODE_MOVE := "move"
const NODE_CROUCH := "crouch"
const NODE_STANCE := "stance"
const NODE_STRIDE := "stride"
const NODE_BRAKE := "brake"
const NODE_BRAKE_CLIP := "brake_clip"
const NODE_BRAKE_RATE := "brake_rate"
const NODE_ACTION := "action"
## The swing layer, kept off the action layer so it can be filtered. See
## _add_swing_layer().
const NODE_SWING := "swing"
const NODE_SWING_BLEND := "swing_blend"

## How much of a clip's own hip travel has to come out before the tree can use
## it. See _flatten().
enum Flatten {
	KEEP,    ## nothing. The clip is already in place, or its travel is the point
	GROUND,  ## x and z, leaving the vertical alone, because that is the bob
	SETTLE,  ## x and z, and the hips may not rise above where the take ends
	ALL,     ## x, y and z: the body's whole path through the world is code's
}

## Action layer transitions config: [name, clip, flatten_mode, loops].
const ACTIONS := [
	["jump_start", CLIP_JUMP_START, Flatten.KEEP, false],
	["jump_air", CLIP_JUMP_AIR, Flatten.KEEP, true],
	["jump_land", CLIP_JUMP_LAND, Flatten.KEEP, false],
	["climb", CLIP_CLIMB, Flatten.ALL, false],
	["climb_down", CLIP_CLIMB_DOWN, Flatten.ALL, false],
	["land", CLIP_LAND, Flatten.SETTLE, false],
	["land_hard", CLIP_LAND_HARD, Flatten.SETTLE, false],
	["land_roll", CLIP_LAND_ROLL, Flatten.SETTLE, false],
	["roll", CLIP_ROLL, Flatten.KEEP, false],
]
## What input 0 is called: the locomotion tree, i.e. no action at all.
const ACTION_NONE := "loco"

## Pre-allocated weapon action slots (wpn_0 to wpn_7) on the action layer.
const WEAPON_SLOTS := WeaponConfig.MAX_ACTIONS
const WEAPON_SLOT_PREFIX := "wpn_"

## What _find_ledge() answers with when there is nothing to climb, which is what
## makes the same request an ordinary jump.
const NO_LEDGE := Vector3.INF
## How far above the highest reachable ledge that probe starts its cast down, in
## metres. Only has to clear the ledge, not the character.
const LEDGE_PROBE_RISE := 0.25

## Physics ticks per sample of the landing prediction's arc march. Coarser than
## the step the body is integrated at - every sample costs a raycast - but the
## segment it spans is well under a cube, so nothing can be tunnelled through.
const PREDICT_TICKS := 3
## Cap on those samples, so an arc that never meets anything cannot walk the
## probe forever. At 3 ticks each this covers 4.5 s of flight.
const PREDICT_SAMPLES := 90

const PARAM_BLEND := "parameters/%s/blend_position" % NODE_MOVE
const PARAM_CROUCH := "parameters/%s/blend_position" % NODE_CROUCH
const PARAM_STANCE := "parameters/%s/blend_amount" % NODE_STANCE
const PARAM_STRIDE := "parameters/%s/scale" % NODE_STRIDE
const PARAM_BRAKE_RATE := "parameters/%s/scale" % NODE_BRAKE_RATE
const PARAM_BRAKE_REQUEST := "parameters/%s/request" % NODE_BRAKE
const PARAM_BRAKE_ACTIVE := "parameters/%s/active" % NODE_BRAKE
const PARAM_ACTION_REQUEST := "parameters/%s/transition_request" % NODE_ACTION
const PARAM_ACTION_STATE := "parameters/%s/current_state" % NODE_ACTION
const NODE_WEAPON_STANCE := "weapon_stance"
const NODE_WEAPON_CLIP := "weapon_clip"
const PARAM_WEAPON_STANCE_BLEND := "parameters/%s/blend_amount" % NODE_WEAPON_STANCE
const PARAM_SWING_REQUEST := "parameters/%s/transition_request" % NODE_SWING
const PARAM_SWING_BLEND := "parameters/%s/blend_amount" % NODE_SWING_BLEND

enum State {
	IDLE, WALK, RUN, CROUCH, BRAKING,
	JUMPING,   ## off the ground because Space said so
	FALLING,   ## off the ground because the ground ran out
	CLIMBING,  ## pulling up onto a ledge, on a path of its own
	LANDING,   ## one of the three landings, still holding control
	ROLLING,   ## the double-tap roll
	ATTACKING, ## swinging weapon, movement restricted
}

## Cache config for auto-reversing/baking clips like crouch backpedals.
const GEN_LIB := "gen"
const REVERSED := {
	CLIP_CROUCH_WALK: "crouch_back",
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
@export var jump_land_recover := 0.28

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
## Duration of the climb pull-up in seconds.
@export var climb_duration := 1.5
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
@export var land_hard_recover := 0.5
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
@export var land_rate_cap := 2.5
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

## What a lunge looks like. NONE is also the cheap one to compare against.
enum DashVfx {NONE, BEAM, FADE}

## How fast every lunge is covered, in m/s. The weapon says how far
## (`dash_distance`), this says how long that takes - there is no per-action clock.
@export var dash_speed := 6.0
@export var dash_vfx: DashVfx = DashVfx.BEAM
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
var _player: AnimationPlayer
var _tree: AnimationTree
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

## This frame's decisions, whoever made them. Rewritten in place, never replaced.
var _intent := CharacterIntent.new()
## Requests that came in between physics frames, latched so they cannot be missed
## by a caller running at its own pace. Merged into `_intent` and cleared.
var _queued_jump := false
var _queued_roll := false
## The combat buttons asked for since the last frame, as a CharacterIntent.BUTTONS
## mask. A mask rather than a bool because a weapon graph may answer to several.
var _queued_buttons := 0

## The equipped weapon's behaviour graph: which take is playing and what chains
## into what. Never null once setup() has run - with nothing equipped it holds
## WeaponConfig.defaults(), a single sword swing, so the attack path has one code
## path rather than a branch for "no weapon".
var _weapon_graph: WeaponGraph
## The generic weapon takes on the action layer, in slot order, kept by reference
## so equipping does not have to look them up by name every time.
var _weapon_slots: Array[AnimationNodeAnimation] = []
## The filtered blend the swing layer is mixed through, and the two filters it
## picks between: every bone, or the stance's subtree. See _begin_weapon_action().
var _swing_blend: AnimationNodeBlend2
var _swing_filter_full: PackedStringArray = []
var _swing_filter_upper: PackedStringArray = []
## How much of the swing layer is showing. Chased towards 1 while ATTACKING.
var _swing_amount := 0.0
## The take the upper body holds while carrying something, and the filtered blend
## that mixes it over locomotion. Both are rewritten per weapon.
var _stance_node: AnimationNodeAnimation
var _stance_blend: AnimationNodeBlend2
## Gait poles in POINTS order, by reference, so a weapon can replace what one
## plays. Invariant: size == POINTS.size() after _build_tree().
var _move_points: Array[AnimationNodeAnimation] = []
## Stance layer weight at rest. 0 = bare-handed. Written by set_weapon_stance();
## _drive_animation() scales it by gait before it reaches the tree.
var _stance_weight := 0.0

## Strafe clip speed in meters per second.
var _strafe_speed := 1.5
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
## Where the body was at the end of the last physics step, and whether the effect
## is still being fed. Read after move_and_slide() - see _drive_dash_vfx().
var _dash_prev := Vector3.ZERO
var _dash_trailing := false
## The ribbon this lunge is drawing, null unless dash_vfx is BEAM.
var _dash_beam: DashBeam
## The character's drawables, collected once per lunge, and how far into the fade
## it is: counts down through the lunge, then back up to 1 as the body returns.
var _fade_meshes: Array[GeometryInstance3D] = []
var _fade_alpha := 1.0
var _roll_cooldown_left := 0.0

## The equipped blade's afterimage settings and the item its anchors sit on.
## Both are handed over by EquipmentManager; empty settings mean no trail.
var _trail_cfg := {}
var _trail_item: HandheldItem
## The ribbon the current take is drawing, null between takes.
var _trail: WeaponTrail
## Seconds into the take the ribbon may draw, from the node's `trail_window`.
## [0, 0] is the whole take. Invariant: start <= end.
var _trail_window := [0.0, 0.0]
var _weapon_stroke_count := 0

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


## Where the current pull-up started and where it ends, in world space, and how
## far along it is as a fraction. See _drive_climb().
var _climb_from := Vector3.ZERO
var _climb_to := Vector3.ZERO
var _climb_t := 0.0
## How long each action take is, by input name. Recorded because some rates are
## derived from a take's length rather than exported - see _fit_rate().
var _take_length := {}
## Reused by the ledge probe's clearance test, so a check that runs on every
## press of Space does not allocate a shape each time.
var _clearance: CapsuleShape3D

## Horizontal travel per second of each measured clip, in the animation's own
## normalised units. Static, and measured once: the flattening in _prepare_clips()
## is permanent, and one cached AnimationLibrary sits behind every character, so
## by the time the second character spawns there is no travel left to measure.
static var _clip_travel := {}


## Called by the playground once the character instance is parented here.
func setup(visual: Node3D, follow_camera: Node3D) -> void:
	character = visual
	camera = follow_camera
	_player = visual.get("player") as AnimationPlayer
	if _player == null:
		push_error("%s: character has no AnimationPlayer" % name)
		return
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

	_prepare_clips()
	_bake_reversals()
	_build_tree()
	# The one seam for render tiering: every scene that spawns a body through
	# setup() gets distance-based culling and a throttled mixer for free.
	CharacterLOD.attach(character, _tree)
	if intent_source == null:
		intent_source = PlayerIntentSourceScript.new()
	if _clearance == null:
		_clearance = CapsuleShape3D.new()
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
	_end_dash_vfx()
	_seal_trail()
	_swing_amount = 0.0
	_roll_cooldown_left = 0.0
	_coyote_left = 0.0
	_jump_buffered = 0.0
	_air_peak_y = global_position.y
	_take_off_y = global_position.y
	_air_speed = 0.0
	_landing_take = ""
	_landing_rate = 1.0
	_stop_action()


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


## Gets the library's clips into a state the tree can use: looped where they are
## cycles, flattened where they travel. See _flatten().
func _prepare_clips() -> void:
	var skeleton := character.get("skeleton") as Skeleton3D
	var motion_scale: float = skeleton.motion_scale if skeleton != null else 1.0
	for clip in CLIPS:
		var full: String = character.call("resolve", clip)
		if full == "":
			push_warning("%s: missing clip '%s'" % [name, clip])
			continue
		var anim := _player.get_animation(full)
		anim.loop_mode = Animation.LOOP_NONE if ONE_SHOT_CLIPS.has(clip) \
			else Animation.LOOP_LINEAR
		if MEASURED_CLIPS.has(clip):
			_measure(clip, anim)
			if _clip_travel.has(clip):
				_strafe_speed = float(_clip_travel[clip]) * motion_scale
		if CLIPS[clip]:
			_flatten(anim)

	for entry in ACTIONS:
		var take_name := _resolve_take(entry[1])
		if take_name == "":
			push_warning("%s: missing clip '%s'" % [name, entry[1]])
			continue
		var take := _player.get_animation(take_name)
		take.loop_mode = Animation.LOOP_LINEAR if entry[3] else Animation.LOOP_NONE
		_flatten(take, entry[2])
		_take_length[entry[0]] = take.length


## The name the AnimationPlayer knows a take by, following ALTERNATES when the
## first choice is not in the library. "" when neither is there.
func _resolve_take(clip: String) -> String:
	var full: String = character.call("resolve", clip)
	if full == "" and ALTERNATES.has(clip):
		full = character.call("resolve", ALTERNATES[clip])
	return full


## How fast a clip was performed, before _flatten() takes the evidence away.
## Skipped once known - the answer is a property of the clip, and the clip is
## shared by every character.
func _measure(clip: String, anim: Animation) -> void:
	if _clip_travel.has(clip):
		return
	var track := anim.find_track(NodePath(HIPS_TRACK), Animation.TYPE_POSITION_3D)
	if track < 0 or anim.length < 0.01:
		return
	var first := anim.position_track_interpolate(track, 0.0)
	var last := anim.position_track_interpolate(track, anim.length)
	var travelled := Vector2(last.x - first.x, last.z - first.z).length()
	if travelled > 0.01:
		_clip_travel[clip] = travelled / anim.length


## Pins a clip's hips horizontally, and does as much to the vertical as `mode`
## asks for.
##
## The sidesteps and the skid are the clips whose hips actually travel, and
## something has to stop that travel from sliding the model out of its collision
## shape. Root motion is the usual answer and is not available here: an
## AnimationTree has one root_motion_track for the whole tree, and everything in
## this one is blended together every frame, so switching it on for the sidesteps
## switches it on for the walk too - which flattens the walk's 5.2 cm of hip rise
## and 4 degrees of sway to nothing.
##
## So the travel comes out of the clip instead, once, and the tree needs no root
## motion at all. Normally only x and z: y is the bob, and the bob is the
## animation. The two vertical modes are both about the same mistake, which is
## that a clip's hip height is measured from the body and the body is being moved
## by this script at the same time - so any vertical the clip has of its own gets
## added to the body's, not substituted for it. See ACTIONS.
##
## Idempotent, which it has to be - Tab respawns the character against the same
## cached AnimationLibrary, so this runs again on clips it has already flattened.
## SETTLE included: a track already capped at its own last value is unchanged by
## capping it again.
func _flatten(anim: Animation, mode: Flatten = Flatten.GROUND) -> void:
	if mode == Flatten.KEEP:
		return
	var track := anim.find_track(NodePath(HIPS_TRACK), Animation.TYPE_POSITION_3D)
	if track < 0:
		return
	var keys := anim.track_get_key_count(track)
	if keys == 0:
		return
	var origin: Vector3 = anim.track_get_key_value(track, 0)
	# Where the take leaves the character standing. Keys are sorted by time, so
	# the last one is the end.
	var settled: float = (anim.track_get_key_value(track, keys - 1) as Vector3).y
	for key in keys:
		var value: Vector3 = anim.track_get_key_value(track, key)
		var height := value.y
		match mode:
			Flatten.ALL:
				height = origin.y
			Flatten.SETTLE:
				height = minf(value.y, settled)
		anim.track_set_key_value(track, key, Vector3(origin.x, height, origin.z))


## Bakes reversed animation keys at runtime to support backward blend movement.
func _bake_reversals() -> void:
	var lib := AnimationLibrary.new()
	for clip in REVERSED:
		var full: String = character.call("resolve", clip)
		if full == "":
			continue
		lib.add_animation(REVERSED[clip], _reversed(_player.get_animation(full)))
	if _player.has_animation_library(GEN_LIB):
		_player.remove_animation_library(GEN_LIB)
	_player.add_animation_library(GEN_LIB, lib)


## A copy of `anim` running the other way: every key moved to `length - t`, in
## reverse order so the track stays sorted.
func _reversed(anim: Animation) -> Animation:
	var out: Animation = anim.duplicate(true)
	for track in out.get_track_count():
		var count := out.track_get_key_count(track)
		var times := []
		var values := []
		var easings := []
		for key in count:
			times.append(out.track_get_key_time(track, key))
			values.append(out.track_get_key_value(track, key))
			easings.append(out.track_get_key_transition(track, key))
		for key in range(count - 1, -1, -1):
			out.track_remove_key(track, key)
		for key in range(count - 1, -1, -1):
			out.track_insert_key(track, out.length - times[key], values[key], easings[key])
	out.loop_mode = Animation.LOOP_LINEAR
	return out


## Builds the tree and hands the AnimationPlayer over to it.
##
## Made in code rather than saved as a .tres for the same reason the playground
## is: the character scenes are generated, the AnimationPlayer lives inside one,
## and a resource pointing into a regenerated node tree is a resource that breaks
## quietly. It is parented to the character so that Tab frees it along with
## everything else.
##
## SYNC_MODE_CYCLIC_MUTABLE is not optional. Left at the default, every blend
## point runs on its own clock, and these clips are not the same length: the walk
## is 1.333 s and the sidesteps are 1.033 s. Blended half and half they drift
## apart and back together with a beat period of
## 1 / (1/1.033 - 1/1.333) = 4.6 s - a diagonal that looks right, goes wrong in
## the middle, and comes good again, on a four-and-a-half second cycle. Cyclic
## sync locks them to a shared normalised phase; MUTABLE rather than CONSTANT so
## each pole still plays at the pace it was performed at and only the blends in
## between interpolate a cycle length.
func _build_tree() -> void:
	var space := AnimationNodeBlendSpace2D.new()
	space.min_space = Vector2(-1.0, -1.0)
	space.max_space = Vector2(1.0, 2.0)
	space.auto_triangles = false
	space.sync_mode = AnimationNodeBlendSpace2D.SYNC_MODE_CYCLIC_MUTABLE
	_move_points.clear()
	for point in POINTS:
		var pole := _clip_node(point[1], point[3]) as AnimationNodeAnimation
		space.add_blend_point(pole, point[2], -1, point[0])
		_move_points.append(pole)
	for triangle in TRIANGLES:
		space.add_triangle(triangle.x, triangle.y, triangle.z)

	var crouch := AnimationNodeBlendSpace1D.new()
	crouch.min_space = -1.0
	crouch.max_space = 1.0
	crouch.sync_mode = AnimationNodeBlendSpace1D.SYNC_MODE_CYCLIC_MUTABLE
	for point in CROUCH_POINTS:
		crouch.add_blend_point(_clip_node(point[1], point[3]), point[2], -1, point[0])

	var root := AnimationNodeBlendTree.new()
	# The stance layer: an upper-body take mixed over whatever the legs are doing.
	# Filtered rather than blended whole, or holding a sword would also replace the
	# walk. Which bones it is allowed to drive is per weapon - see
	# set_weapon_stance_filter() - so the filter is built by a function.
	# Weight is not constant: _drive_animation() fades it out with gait, so a run
	# is the locomotion clip's own arms. See set_weapon_stance().
	_stance_blend = AnimationNodeBlend2.new()
	_stance_blend.filter_enabled = true
	_stance_blend.filters = _stance_filter("Spine")
	_stance_node = _clip_node(CLIP_SWORD_IDLE, false) as AnimationNodeAnimation

	root.add_node(NODE_MOVE, space)
	root.add_node(NODE_CROUCH, crouch)
	root.add_node(NODE_STANCE, AnimationNodeBlend2.new())
	root.add_node(NODE_STRIDE, AnimationNodeTimeScale.new())
	root.add_node(NODE_BRAKE_CLIP, _clip_node(CLIP_BRAKE, false))
	root.add_node(NODE_BRAKE_RATE, AnimationNodeTimeScale.new())
	root.add_node(NODE_BRAKE, AnimationNodeOneShot.new())
	root.add_node(NODE_WEAPON_STANCE, _stance_blend)
	root.add_node(NODE_WEAPON_CLIP, _stance_node)
	root.connect_node(NODE_STANCE, 0, NODE_MOVE)
	root.connect_node(NODE_STANCE, 1, NODE_CROUCH)
	root.connect_node(NODE_STRIDE, 0, NODE_STANCE)
	root.connect_node(NODE_BRAKE_RATE, 0, NODE_BRAKE_CLIP)
	root.connect_node(NODE_BRAKE, 0, NODE_STRIDE)
	root.connect_node(NODE_BRAKE, 1, NODE_BRAKE_RATE)
	root.connect_node(NODE_WEAPON_STANCE, 0, NODE_BRAKE)
	root.connect_node(NODE_WEAPON_STANCE, 1, NODE_WEAPON_CLIP)
	_add_action_layer(root)
	_add_swing_layer(root)
	root.connect_node("output", 0, NODE_SWING_BLEND)

	_tree = AnimationTree.new()
	_tree.name = "Locomotion"
	_tree.tree_root = root
	# The blend position is written in _physics_process, so the mixer has to
	# advance there too or the pose lags the body by a variable frame.
	_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	_tree.root_motion_track = NodePath("")
	character.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_player)
	_tree.active = true

	_tree.set(PARAM_BRAKE_RATE, brake_rate)


## Every track the stance layer is allowed to drive: one bone and everything
## under it.
##
## A one-handed weapon filters on Spine, which is the torso and both arms - the
## legs stay with locomotion, so the character can walk while holding a sword. A
## two-hander that has to turn the hips wants a bone further down. An empty result
## means the filter matched nothing and the blend would replace the whole pose,
## which is why an unknown bone name falls back to Spine rather than to nothing.
func _stance_filter(bone_name: String) -> PackedStringArray:
	var filters := PackedStringArray()
	var skeleton := character.get("skeleton") as Skeleton3D
	if skeleton == null:
		return filters
	var root_bone := skeleton.find_bone(bone_name)
	if root_bone == -1:
		if bone_name == "Spine":
			return filters
		push_warning("%s: no bone '%s', stance filtered on Spine instead" % [name, bone_name])
		return _stance_filter("Spine")
	for i in skeleton.get_bone_count():
		var parent := i
		while parent != -1:
			if parent == root_bone:
				filters.append(_bone_track(skeleton, i))
				break
			parent = skeleton.get_bone_parent(parent)
	return filters


## Every bone track. A filtered blend given this filter drives the whole pose,
## which is how the swing layer plays a take full-body without a second node.
func _all_bones_filter() -> PackedStringArray:
	var filters := PackedStringArray()
	var skeleton := character.get("skeleton") as Skeleton3D
	if skeleton == null:
		return filters
	for i in skeleton.get_bone_count():
		filters.append(_bone_track(skeleton, i))
	return filters


## The track path every clip in the library addresses a bone by.
func _bone_track(skeleton: Skeleton3D, bone: int) -> String:
	return "%GeneralSkeleton:" + skeleton.get_bone_name(bone)


## The action layer: one transition whose input 0 is everything below it.
##
## A Transition rather than a OneShot per take, because these are mutually
## exclusive and each has to start from its first frame. A OneShot fires over
## whatever is underneath and eight of them would have to be talked out of each
## other by hand; a Transition is one request, and it resets the take it moves to
## and cross-fades the one it moves off - including back to input 0, which is why
## "no action" is an input rather than a blend amount to drive.
func _add_action_layer(root: AnimationNodeBlendTree) -> void:
	var action := AnimationNodeTransition.new()
	action.input_count = ACTIONS.size() + 1
	action.xfade_time = action_blend
	# Re-requesting a take restarts it. Nothing here should ever run into itself,
	# but a roll cut short by a landing that rolls out would otherwise be ignored
	# rather than restarted, and silently doing nothing is the worse failure.
	action.allow_transition_to_self = true
	# Inputs that are not current still advance. Without this the walk cycle
	# freezes for the length of a climb and resumes mid-stride, on a foot that has
	# been in the air for a second and a half.
	action.sync = true
	action.set_input_name(0, ACTION_NONE)
	# Everything else resets when it is transitioned to, which is the point.
	# Locomotion must not: restarting the blend space on every landing would put
	# the walk cycle back on the same foot every single time.
	action.set_input_reset(0, false)
	root.add_node(NODE_ACTION, action)
	root.connect_node(NODE_ACTION, 0, NODE_WEAPON_STANCE)

	for i in ACTIONS.size():
		var entry: Array = ACTIONS[i]
		var clip_node := "%s_clip" % entry[0]
		var rate_node := "%s_rate" % entry[0]
		action.set_input_name(i + 1, entry[0])
		root.add_node(clip_node, _clip_node(entry[1], false))
		root.add_node(rate_node, AnimationNodeTimeScale.new())
		root.connect_node(rate_node, 0, clip_node)
		root.connect_node(NODE_ACTION, i + 1, rate_node)


## The swing layer: the weapon takes, on a filtered blend of their own.
##
## Not inputs of the action layer, which replaces the whole pose - that is right
## for a jump and wrong for a swing, because a take that lets the character keep
## walking has to leave the legs to the walk. Which half a swing owns is the
## filter's answer, and the filter is chosen per node in _begin_weapon_action().
##
## The slots are still pre-allocated once, for the reason they always were: an
## AnimationNodeTransition rebuilds every input when input_count changes, which
## would knock the pose back to its first frame on every draw.
func _add_swing_layer(root: AnimationNodeBlendTree) -> void:
	var swing := AnimationNodeTransition.new()
	swing.input_count = WEAPON_SLOTS
	swing.xfade_time = action_blend
	swing.allow_transition_to_self = true
	swing.sync = true
	root.add_node(NODE_SWING, swing)

	# Left pointing at the idle clip until something is equipped: an
	# AnimationNodeAnimation with no animation set warns on every process tick.
	_weapon_slots.clear()
	for i in WEAPON_SLOTS:
		var slot_name := "%s%d" % [WEAPON_SLOT_PREFIX, i]
		var clip := _clip_node(CLIP_IDLE, false) as AnimationNodeAnimation
		swing.set_input_name(i, slot_name)
		root.add_node("%s_clip" % slot_name, clip)
		root.add_node("%s_rate" % slot_name, AnimationNodeTimeScale.new())
		root.connect_node("%s_rate" % slot_name, 0, "%s_clip" % slot_name)
		root.connect_node(NODE_SWING, i, "%s_rate" % slot_name)
		_weapon_slots.append(clip)

	_swing_filter_full = _all_bones_filter()
	_swing_filter_upper = _stance_filter("Spine")
	_swing_blend = AnimationNodeBlend2.new()
	_swing_blend.filter_enabled = true
	_swing_blend.filters = _swing_filter_full
	root.add_node(NODE_SWING_BLEND, _swing_blend)
	root.connect_node(NODE_SWING_BLEND, 0, NODE_ACTION)
	root.connect_node(NODE_SWING_BLEND, 1, NODE_SWING)


## Puts the swing layer on `slot`, from its first frame, at `rate`.
func _play_swing(slot: int, rate: float) -> void:
	if _tree == null:
		return
	_tree.set("parameters/%s%d_rate/scale" % [WEAPON_SLOT_PREFIX, slot], rate)
	_tree.set(PARAM_SWING_REQUEST, "%s%d" % [WEAPON_SLOT_PREFIX, slot])


## Puts the action layer on `action`, from its first frame, at `rate`.
func _play_action(action: String, rate: float) -> void:
	if _tree == null:
		return
	_tree.set("parameters/%s_rate/scale" % action, rate)
	_tree.set(PARAM_ACTION_REQUEST, action)


## Hands the pose back to locomotion. The fade is the transition's, so control
## can come back well before the take has finished and the rest of it plays out
## underneath the walk coming back in.
func _stop_action() -> void:
	if _tree == null:
		return
	_tree.set(PARAM_ACTION_REQUEST, ACTION_NONE)


## One blend point. `backward` picks the baked reversal from _bake_reversals()
## rather than asking the blend graph to run the clip in reverse, which it will
## accept and then not do.
func _clip_node(clip: String, backward: bool) -> AnimationRootNode:
	var node := AnimationNodeAnimation.new()
	var full := ""
	if backward and REVERSED.has(clip):
		var baked := "%s/%s" % [GEN_LIB, REVERSED[clip]]
		if _player.has_animation(baked):
			full = baked
	if full == "":
		full = _resolve_take(clip)
	if full == "":
		full = character.call("resolve", CLIP_IDLE)
	node.animation = full
	return node


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
		_: return "站 / idle"


## Whether the character is standing on something and doing something ordinary
## with it. The gate on every action: an action that could interrupt another one
## would need a rule for every pair of them, and there is no call for that yet.
func _grounded_state() -> bool:
	return state == State.IDLE or state == State.WALK or state == State.RUN \
		or state == State.CROUCH


func _physics_process(delta: float) -> void:
	if _tree == null:
		return
	_gather_intent(delta)
	_brake_cooldown_left = maxf(_brake_cooldown_left - delta, 0.0)
	_roll_cooldown_left = maxf(_roll_cooldown_left - delta, 0.0)
	_jump_buffered = maxf(_jump_buffered - delta, 0.0)

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
		_: _drive_locomotion(delta)

	move_and_slide()
	_try_step_up()
	# After the slide, all three: whether the ground is still there is only known
	# once the body has tried to move onto it, walking into a wall should stop the
	# legs too, and the effect wants where the body actually got to.
	_settle_ground(delta)
	_update_footsteps(delta)
	# Past the end of the lunge too: the fade has to come back up afterwards.
	if _dash_trailing or _fade_alpha < 1.0:
		_drive_dash_vfx(delta)
	# A swing cut short by a roll, a hit or a fall leaves the state without going
	# through _drive_attack's own ending. One guard covers every such path.
	if _trail != null and state != State.ATTACKING:
		_seal_trail()
	_drive_animation(delta)
	_consume_intent()


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
	var opening := _weapon_graph.begin(_intent.buttons)
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
		velocity.x = 0.0
		velocity.z = 0.0
		state = State.CROUCH if crouching else State.IDLE
		_fold(crouching, delta)
		if camera != null and bool(camera.get("is_first_person")):
			rotation.y = rotate_toward(rotation.y, _intent.heading, turn_rate * delta)
		return

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
		AudioManagerScript.play_footstep(step_vol, base_pitch * randf_range(0.96, 1.04))


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

	var full: String = character.call("resolve", CLIP_BRAKE)
	var length: float = _player.get_animation(full).length if full != "" else 1.0
	_brake_left = length / maxf(brake_rate, 0.01) + 0.1

	state = State.BRAKING
	_tree.set(PARAM_BRAKE_RATE, brake_rate)
	_tree.set(PARAM_BRAKE_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


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
	if state == State.JUMPING or state == State.FALLING or state == State.ATTACKING:
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
	_play_action("jump_start", jump_start_rate)
	if footstep_enabled:
		AudioManagerScript.play_footstep(-8.0)


## Walking off something, which needs no request and gets a different take from
## jumping off it. That difference is the reason FALLING and JUMPING are two
## states rather than one with a flag.
func _begin_fall() -> void:
	state = State.FALLING
	_action_left = 0.0
	_landing_take = ""
	_play_action("climb_down" if fall_climb_down else "jump_air", 1.0)


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
			_play_action("jump_air", 1.0)
	# Last, so that a landing coming up beats whatever the jump was going to do.
	_arm_landing()


## Configures landing type based on drop height and contact velocity.
func _landing_for(drop: float, ground_speed: float, takeoff_drop: float = 0.0) -> Array:
	if takeoff_drop >= land_roll_drop_min and ground_speed >= land_roll_speed_min:
		return ["land_roll", land_roll_recover, land_roll_lead]
	if drop >= land_roll_drop_min:
		return ["land_hard", land_hard_recover, land_hard_lead]
	return ["jump_land", jump_land_recover, 0.0]


## Whether enough ground exists ahead of a landing point for a roll-out.
## Probes forward along horizontal velocity at half the estimated slide distance.
func _roll_has_ground(landing_pos: Vector3, vel: Vector3) -> bool:
	var dir := Vector3(vel.x, 0.0, vel.z)
	if dir.length_squared() < 0.01:
		dir = global_basis.z
	else:
		dir = dir.normalized()
	var dist: float = land_roll_speed * land_roll_recover / maxf(roll_rate, 0.01) * 0.5
	var probe_from := landing_pos + dir * dist + Vector3.UP * 0.5
	var probe_to := landing_pos + dir * dist - Vector3.UP * 0.5
	var hit := _cast(get_world_3d().direct_space_state, probe_from, probe_to)
	if hit.is_empty():
		return false
	return (hit.normal as Vector3).y >= climb_floor_dot and absf((hit.position as Vector3).y - landing_pos.y) <= 0.4


## Pre-triggers landing animation in mid-air based on estimated impact time.
func _arm_landing() -> void:
	if (state != State.FALLING and state != State.JUMPING) or _landing_take != "" \
			or velocity.y > -land_arm_vy_min:
		return
	var impact := _predict_impact()
	if impact.is_empty():
		return
	var ground: float = (impact.pos as Vector3).y
	var eta: float = impact.time
	var drop: float = maxf(_air_peak_y, global_position.y) - ground
	if drop < land_min_drop:
		return
	var pick := _landing_for(drop, speed(), _take_off_y - ground)
	if pick[0] == "land_roll" and not _roll_has_ground(impact.pos as Vector3, velocity):
		pick = ["land_hard", land_hard_recover, land_hard_lead]
	var lead: float = pick[2]
	if eta > lead:
		return
	_landing_take = pick[0]
	_landing_recover = pick[1]
	var rate_mult: float = roll_rate if _landing_take == "land_roll" else 1.0
	_landing_rate = clampf((lead / maxf(eta, 0.01)) * rate_mult, 1.0, land_rate_cap)
	_play_action(_landing_take, _landing_rate)


## Where the arc the body is on meets ground, and how long until it does:
## {pos: Vector3, time: float}, or {} when nothing is hit inside `fall_probe`.
##
## Marches the arc and casts every segment of it, rather than extrapolating the
## horizontal velocity in a straight line and looking straight down from the end
## of that line. Over a void the shortcut reports whatever lies at the BOTTOM of
## the void, so a level gap jump reads as a fall from the platform's full height:
## `takeoff_drop` comes out as the platform height, _landing_for() answers with
## the roll-out landing, and its forward slide then carries the body off the far
## side. The gate that should have rejected it is computed from the same wrong
## ground, so it lets it through. Here both numbers come out of one solve.
##
## Pre: airborne. Post: pos is on a surface flat enough to stand on.
func _predict_impact() -> Dictionary:
	var space := get_world_3d().direct_space_state
	var tick: float = 1.0 / maxf(float(Engine.physics_ticks_per_second), 1.0)
	var span: float = PREDICT_TICKS * tick
	var at := global_position
	var v := velocity
	var elapsed := 0.0
	var give_up: float = global_position.y - fall_probe
	for _sample in PREDICT_SAMPLES:
		# One sample is PREDICT_TICKS steps of the same semi-implicit Euler the
		# physics step runs, so the arc marched here is the arc actually flown.
		var rise := 0.0
		for _t in PREDICT_TICKS:
			v.y -= _gravity * tick
			rise += v.y * tick
		var next := at + Vector3(v.x * span, rise, v.z * span)
		var hit := _cast(space, at, next)
		if hit.is_empty() and (v.x * v.x + v.z * v.z) > 0.01:
			var forward := Vector3(v.x, 0.0, v.z).normalized() * (_capsule_radius() * 0.8)
			hit = _cast(space, at + forward, next + forward)
		if hit.is_empty():
			at = next
			elapsed += span
			if at.y < give_up:
				return {}
			continue
		var pos: Vector3 = hit.position
		if (hit.normal as Vector3).y >= climb_floor_dot:
			var length := at.distance_to(next)
			var into: float = 0.0 if length < 0.0001 else clampf(at.distance_to(pos) / length, 0.0, 1.0)
			return {"pos": pos, "time": elapsed + span * into}
		# A face rather than a floor: move_and_slide would kill the horizontal
		# component against it and the body would drop down the face from there.
		at = pos
		v.x = 0.0
		v.z = 0.0
		elapsed += span
	return {}


## Transitions actor state upon landing (absorb or roll recover).
func _land() -> void:
	var jumped := state == State.JUMPING
	velocity.y = 0.0
	_action_slides = false
	var take := _landing_take
	var recover := _landing_recover
	if footstep_enabled:
		AudioManagerScript.play_land_sound(-6.0)

	if jumped and take == "":
		take = "jump_land"
		recover = jump_land_recover
		_landing_rate = 1.0
		_play_action(take, 1.0)
	elif take == "":
		var drop: float = maxf(_air_peak_y - global_position.y, 0.0)
		if drop < land_min_drop:
			state = State.IDLE
			_stop_action()
			return
		var takeoff_drop: float = _take_off_y - global_position.y
		var contact_speed: float = maxf(speed(), _air_speed)
		var pick := _landing_for(drop, contact_speed, takeoff_drop)
		take = pick[0]
		recover = pick[1]
		_landing_rate = 1.0 if take == "jump_land" else land_rate_cap
		_play_action(take, _landing_rate)

	# Downgrade land_roll if jump height drop does not warrant roll or if roll would slide off an edge.
	var actual_takeoff_drop: float = _take_off_y - global_position.y
	if take == "land_roll" and (actual_takeoff_drop < land_roll_drop_min or not _roll_has_ground(global_position, velocity)):
		var actual_drop: float = maxf(_air_peak_y - global_position.y, 0.0)
		take = "land_hard" if actual_drop >= land_roll_drop_min else "jump_land"
		recover = land_hard_recover if take == "land_hard" else jump_land_recover
		_landing_rate = land_rate_cap if take == "land_hard" else 1.0
		_play_action(take, _landing_rate)

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
		_stop_action()


# --- the climb -------------------------------------------------------------

func _try_climb() -> bool:
	var ledge := _find_ledge()
	if ledge == NO_LEDGE:
		return false
	_climb_from = global_position
	_climb_to = ledge
	_climb_t = 0.0
	_jump_buffered = 0.0
	velocity = Vector3.ZERO
	# Square up to it first. The take pulls the body straight along its own
	# forward, so climbing a wall at thirty degrees to it puts a shoulder through
	# the wall on the way up.
	var across := Vector2(ledge.x - _climb_from.x, ledge.z - _climb_from.z)
	if across.length() > 0.01:
		rotation.y = atan2(across.x, across.y)
	state = State.CLIMBING
	_play_action("climb", _fit_rate("climb", climb_duration))
	return true


## The playback rate that fits exactly one pass of `take` into `span` seconds.
## 1.0 when the take's length is not known, which only happens if the library has
## neither the take nor its alternate.
func _fit_rate(take: String, span: float) -> float:
	var length: float = _take_length.get(take, 0.0)
	if length <= 0.01:
		return 1.0
	return length / maxf(span, 0.01)


## Lifts the body onto a kerb the slide just stopped against. See step_up_enabled
## for why this case exists at all.
##
## Probe is the standard three: rise, move in, come back down. Each leg must be
## clear or the kerb is really a wall. Pre: called straight after
## move_and_slide(), before the ground state is settled.
## Post: position on top of the step, or untouched. Velocity is never modified -
## the body keeps the pace it was already walking at.
func _try_step_up() -> void:
	if not step_up_enabled or step_max_height <= 0.0:
		return
	if not is_on_floor() or not is_on_wall():
		return
	match state:
		State.CLIMBING, State.JUMPING, State.FALLING, State.ROLLING, State.LANDING:
			return

	# The direction asked for, not the one left over. move_and_slide() has already
	# zeroed the velocity against the very kerb this is trying to get over, so
	# reading velocity here says "not going anywhere" exactly when it matters.
	# Same input _find_ledge() probes along, for the same reason.
	if _intent.move == Vector2.ZERO:
		return

	var rise := Vector3.UP * step_max_height
	var forward := _wish_direction() * (_capsule_radius() + step_probe_ahead)
	var from := global_transform

	# Headroom to rise into, then room to move in over the kerb once lifted.
	if test_move(from, rise):
		return
	var lifted := from.translated(rise)
	if test_move(lifted, forward):
		return

	# Something to come back down onto. No hit at all means the body was about to
	# be dropped into a gap, which is a fall, not a step.
	var over := lifted.translated(forward)
	var landing := KinematicCollision3D.new()
	if not test_move(over, -rise, landing):
		return
	if landing.get_normal().y < climb_floor_dot:
		return

	# Only commit to a genuine rise. Without this the same probe succeeds while
	# scraping along a flat wall, where it would teleport the body sideways.
	var settled := over.origin + landing.get_travel()
	if settled.y - global_position.y <= 0.02:
		return
	global_position = settled


## Probes area in front of character to find a climbable ledge. Returns target foot position or NO_LEDGE.
func _find_ledge() -> Vector3:
	var space := get_world_3d().direct_space_state
	var reach: float = _capsule_radius() + climb_reach
	var wish := _wish_direction()

	var dirs: Array[Vector3] = [global_basis.z]
	if wish.length_squared() > 0.01 and wish.dot(global_basis.z) < 0.99:
		dirs.append(wish)

	for forward in dirs:
		var ahead := global_position + forward * reach
		var hit := _cast(space,
			Vector3(ahead.x, global_position.y + climb_max_height + LEDGE_PROBE_RISE, ahead.z),
			Vector3(ahead.x, global_position.y + climb_min_height, ahead.z))
		if hit.is_empty():
			continue
		if (hit.normal as Vector3).y < climb_floor_dot:
			continue
		var stand: Vector3 = hit.position
		if _fits(stand):
			return stand

	return NO_LEDGE


## Whether this character, standing, would fit with its feet at `foot`.
##
## A shape query rather than a handful of rays: what makes a ledge unclimbable is
## usually a low ceiling over it or a second wall just past it, and both are easy
## for three rays to thread.
func _fits(foot: Vector3) -> bool:
	var radius: float = maxf(_capsule_radius() * climb_clearance, 0.05)
	_clearance.radius = radius
	_clearance.height = maxf(_stand_height * climb_clearance, radius * 2.0 + 0.01)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _clearance
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	query.transform = Transform3D(Basis.IDENTITY,
		foot + Vector3.UP * (_clearance.height * 0.5 + 0.02))
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _cast(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	return space.intersect_ray(query)


func _capsule_radius() -> float:
	if _capsule == null:
		return 0.3
	var shape := _capsule.shape as CapsuleShape3D
	return shape.radius if shape != null else 0.3


## Linearly interpolates character position along the climb path (disables physics/collisions).
func _drive_climb(delta: float) -> void:
	_fold(false, delta)
	_climb_t += delta / maxf(climb_duration, 0.01)
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
	_stop_action()


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
	_play_action("roll", roll_rate)


func _drive_roll(delta: float) -> void:
	_fold(false, delta)
	_slide_forward(_slide_pace(_action_left, _slide_span))
	_action_left -= delta
	if _action_left <= 0.0:
		state = State.IDLE
		_action_slides = false
		_stop_action()
		if _intent.move != Vector2.ZERO:
			_drive_locomotion(0.0)


# --- the attack ------------------------------------------------------------

## Starts one node of the weapon's graph and hands it the clock.
##
## The graph is the only clock here. Roll and the landings count down an
## `_action_left` of their own; this one asks WeaponGraph.finished(), because the
## same number also decides when a cancel window opens and two clocks that have to
## agree eventually will not.
func _begin_weapon_action(id: String) -> void:
	var slot := _weapon_graph.slot_of(id)
	if slot < 0 or slot >= _weapon_slots.size():
		push_warning("%s: weapon action '%s' has no slot" % [name, id])
		return
	var action := _weapon_graph.action_of(id)

	# Any full-body take still fading out gets out of the way first, but only on
	# the way in: re-requesting it on every link of a combo would restart its
	# cross-fade and show a frame of locomotion between two hits.
	if state != State.ATTACKING:
		_stop_action()
	state = State.ATTACKING
	if not is_on_floor():
		velocity.y = 0.0
	_weapon_stroke_count += 1
	_weapon_graph.enter(id)
	# One ribbon per node, not per combo: each link is its own stroke, and its own
	# window into it. The outgoing one is left to fade rather than cut.
	_seal_trail()
	_begin_trail(action)
	# A lunge. Zero distance - the common case - leaves the body to the
	# deceleration in _drive_attack, which is what makes a standing swing stand.
	_action_slides = action.dash_distance > 0.0
	if _action_slides:
		_slide_speed = dash_speed
		# Distance over speed, capped at the take: the lunge runs inside the swing
		# now, so it may not outlive it. A distance that does not fit is covered
		# short - turn dash_speed up rather than the distance down.
		_dash_left = minf(action.dash_distance / maxf(dash_speed, 0.01),
			_weapon_graph.span_of(id))
		_dash_prev = global_position
		_dash_trailing = true
		_begin_dash_vfx()
	else:
		_dash_left = 0.0
		_dash_trailing = false

	# Whole body for a take that pins the character or carries it; upper body for
	# one it can walk through, so the legs stay with the blend space instead of
	# sliding along in the swing's own stance. Decided once per node - swapping
	# the filter mid-take would snap the legs from one pose to the other.
	if _swing_blend != null:
		_swing_blend.filters = _swing_filter_full \
			if (action.lock_move or _action_slides) else _swing_filter_upper
	# At its own rate whether it lunges or not: the body travels while the take
	# plays, so there is no first frame to hold and no clock to hand back.
	_play_swing(slot, action.rate)


## Runs the current node and lets the graph decide what happens next.
##
## A chained node is played directly rather than going through idle: the
## transition's own cross-fade is the join between two hits, and dropping to input
## 0 in between would show a frame of the walk cycle in the middle of a combo.
func _drive_attack(delta: float) -> void:
	_fold(false, delta)

	var next := _weapon_graph.advance(delta, _intent.buttons)
	if not next.is_empty():
		_begin_weapon_action(next)
		return

	_drive_trail(_weapon_graph.elapsed)

	if _action_slides:
		_drive_dash(delta)
	elif _weapon_graph.action_of(_weapon_graph.current).get("lock_move", true):
		var settle: float = 1.0 - exp(-delta * acceleration)
		velocity.x = lerpf(velocity.x, 0.0, settle)
		velocity.z = lerpf(velocity.z, 0.0, settle)
	else:
		_drive_attack_move(delta)

	if _weapon_graph.finished():
		state = State.IDLE
		_action_slides = false
		_dash_left = 0.0
		# The ribbon is sealed here rather than dropped: it fades on its own. The
		# fade-in is left running - _physics_process keeps calling it until the
		# body is solid again.
		_seal_dash_vfx()
		_seal_trail()
		_weapon_graph.reset()
		# No _stop_action(): the swing is not on the action layer any more, and
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


# --- what a lunge looks like ------------------------------------------------

## Starts the effect the current dash_vfx asks for. Post: BEAM has a ribbon,
## FADE has its mesh list, NONE has neither.
func _begin_dash_vfx() -> void:
	match dash_vfx:
		DashVfx.BEAM:
			_dash_beam = DashBeam.start(get_parent(), dash_beam_tint,
				dash_beam_life, _stand_height)
			if _dash_beam != null:
				_dash_beam.extend(global_position, character)
		DashVfx.FADE:
			_fade_meshes = DashFade.collect(character)
			DashFade.spawn_burst(get_parent(), global_position, _stand_height, dash_beam_tint)
			
			var dist := _slide_speed * _dash_left
			var dir := global_basis.z.normalized()
			var collision := move_and_collide(dir * dist, true)
			if collision != null:
				global_position += collision.get_travel()
			else:
				global_position += dir * dist
			
			velocity = Vector3.ZERO
			_dash_left = 0.0
			_fade_alpha = 0.0
			DashFade.apply(_fade_meshes, 0.0)
			
			if camera != null and camera.has_method("snap"):
				camera.snap()
			
			DashFade.spawn_burst(get_parent(), global_position, _stand_height, dash_beam_tint)



## One physics step of the running effect. Runs after move_and_slide(), because
## what it wants is where the body actually got to.
##
## Pre: called while _dash_trailing, and afterwards until the fade is back at 1.
func _drive_dash_vfx(delta: float) -> void:
	var dashing := _dash_left > 0.0
	if _dash_beam != null and global_position.distance_squared_to(_dash_prev) > 0.0:
		_dash_beam.extend(global_position, character)
	_dash_prev = global_position

	if not _fade_meshes.is_empty():
		if not dashing and _dash_trailing:
			DashFade.spawn_burst(get_parent(), global_position, _stand_height, dash_beam_tint)

		var step: float = delta / maxf(dash_fade_out if dashing else dash_fade_in, 0.01)
		var floor_alpha: float = clampf(dash_fade_floor, 0.0, 1.0)
		_fade_alpha = maxf(_fade_alpha - step, floor_alpha) if dashing \
			else minf(_fade_alpha + step, 1.0)
		DashFade.apply(_fade_meshes, _fade_alpha)
		if not dashing and _fade_alpha >= 1.0:
			_fade_meshes.clear()

	if not dashing:
		_dash_trailing = false
		_seal_dash_vfx()


## Lets the ribbon start fading. Idempotent - the node frees itself.
func _seal_dash_vfx() -> void:
	if _dash_beam != null:
		if is_instance_valid(_dash_beam):
			_dash_beam.seal()
		_dash_beam = null


## Everything off, now. For the paths where there is no next frame to finish in -
## a reset, or a weapon swapped mid-swing - which would otherwise leave the
## character stuck half-transparent.
func _end_dash_vfx() -> void:
	_dash_trailing = false
	_seal_dash_vfx()
	DashFade.clear(_fade_meshes)
	_fade_meshes.clear()
	_fade_alpha = 1.0


# --- what the blade leaves behind -------------------------------------------

## Starts a ribbon for `action`, or nothing when the weapon draws none.
## Pre: _trail == null. Post: _trail is bound and closed; the window decides when
## it opens.
func _begin_trail(action: Dictionary) -> void:
	if not bool(_trail_cfg.get("enabled", false)) or not bool(action.get("trail", true)):
		return
	if _trail_item == null or not is_instance_valid(_trail_item):
		return
	_trail = WeaponTrail.start(get_parent(), _trail_cfg)
	if _trail == null:
		return
	_trail.bind(_trail_item)
	_trail_window = action.get("trail_window", [0.0, 0.0])


## Opens and closes the ribbon as the take runs through its window. A [0, 0]
## window is the whole take, leaving trail.min_speed to pick the swing out of it.
func _drive_trail(elapsed: float) -> void:
	if _trail == null or not is_instance_valid(_trail):
		return
	var start := float(_trail_window[0])
	var end := float(_trail_window[1])
	var inside := end <= start or (elapsed >= start and elapsed <= end)
	if inside:
		_trail.open()
	else:
		_trail.close()


## Lets the ribbon fade on its own. Idempotent - the node frees itself.
func _seal_trail() -> void:
	if _trail != null:
		if is_instance_valid(_trail):
			_trail.seal()
		_trail = null


## The blade the trail reads its anchors off, and what it draws.
## Pre: item.initialize() has run. Post: the take running now keeps the ribbon it
## already has; the next one picks up the new settings.
func set_weapon_trail(cfg: Dictionary, item) -> void:
	_trail_cfg = cfg
	_trail_item = item as HandheldItem
	if _trail == null or not is_instance_valid(_trail):
		return
	if _trail_item == null or cfg.is_empty() or not bool(cfg.get("enabled", false)):
		_seal_trail()
		return
	# Re-tuning in the weapon panel lands here every slider tick, so the ribbon is
	# retargeted rather than rebuilt - a rebuild would drop the samples already
	# drawn and make the strip blink on every drag.
	_trail.set_config(cfg)
	_trail.bind(_trail_item)


# --- what the equipped weapon changes ---------------------------------------

## Stance layer weight at rest. 0 is bare-handed.
##
## Not written to the tree here: _drive_animation() scales it by gait every frame,
## because a stance take that stays at full strength while the character runs
## replaces the run's arms with a standing pose.
func set_weapon_stance(blend_amount: float) -> void:
	_stance_weight = clampf(blend_amount, 0.0, 1.0)


## Replaces the idle / walk / sprint poles of the gait blend space with the
## weapon's own clips. Empty or missing names restore the bare-handed defaults.
##
## This is what lets an armed idle reach the legs: filtering the stance layer onto
## the Spine subtree can only ever reach the torso, so the lower body has to come
## from the pole itself.
func set_weapon_locomotion(idle_clip: String, walk_clip: String, run_clip: String) -> void:
	_set_pole(P_IDLE, idle_clip, CLIP_IDLE)
	_set_pole(P_WALK, walk_clip, CLIP_WALK)
	_set_pole(P_RUN, run_clip, CLIP_RUN)


## Points one pole at `clip`, or back at `fallback` when it is empty or not in the
## library. Pre: _build_tree() has run. A substituted clip is looped and pinned in
## place; the defaults are left as _prepare_clips() set them.
func _set_pole(index: int, clip: String, fallback: String) -> void:
	if _player == null or index >= _move_points.size():
		return
	var full := ""
	var wanted := clip.strip_edges()
	if not wanted.is_empty():
		full = String(character.call("resolve", wanted))
		if full.is_empty():
			push_warning("%s: no locomotion clip '%s'" % [name, wanted])
		else:
			var anim := _player.get_animation(full)
			anim.loop_mode = Animation.LOOP_LINEAR
			# Idempotent. A clip that travels would otherwise walk the model out of
			# its collision shape - the tree runs no root motion. See _flatten().
			_flatten(anim)
	if full.is_empty():
		full = _resolve_take(fallback)
	if not full.is_empty():
		_move_points[index].animation = full


## Updates upper body holding stance animation clip dynamically.
func set_weapon_stance_clip(clip: String) -> void:
	if _stance_node == null or clip.is_empty():
		return
	var full: String = character.call("resolve", clip)
	if full == "":
		push_warning("%s: no stance clip '%s'" % [name, clip])
		return
	_player.get_animation(full).loop_mode = Animation.LOOP_LINEAR
	_stance_node.animation = full


## Which bone's subtree the stance take may drive. See _stance_filter().
##
## The swing layer's upper-body half divides the body the same way, so a weapon
## that hangs its stance lower also swings from lower down.
func set_weapon_stance_filter(bone_name: String) -> void:
	if bone_name.is_empty():
		return
	var filter := _stance_filter(bone_name)
	if _stance_blend != null:
		_stance_blend.filters = filter
	_swing_filter_upper = filter


## Loads weapon behavior graph configuration into action layer slots.
func set_weapon_graph(config: Dictionary) -> void:
	_weapon_graph = WeaponGraph.parse(config if not config.is_empty()
		else WeaponConfig.defaults())
	if _player == null:
		return

	var lengths := {}
	for i in _weapon_graph.order.size():
		if i >= _weapon_slots.size():
			break
		var id: String = _weapon_graph.order[i]
		var action := _weapon_graph.action_of(id)
		var full: String = character.call("resolve", action.clip)
		if full == "":
			push_warning("%s: weapon action '%s' wants missing clip '%s'" % [
				name, id, action.clip])
			continue
		var take := _player.get_animation(full)
		# A take that loops never reaches its own end, and the transition would
		# hold it there for as long as the node runs.
		take.loop_mode = Animation.LOOP_NONE
		# Idempotent, which matters: the same clip is re-flattened every time any
		# weapon using it is equipped. See _flatten().
		_flatten(take, _flatten_mode(action.flatten))
		_weapon_slots[i].animation = full
		lengths[id] = take.length
	# The blink's own time is added on top of these by resolve_spans().
	_weapon_graph.resolve_spans(lengths)

	# Mid-swing when the weapon changed: the take under the character has just
	# been replaced, so hand the pose back rather than finish someone else's combo.
	if state == State.ATTACKING:
		state = State.IDLE
		_action_slides = false
		_dash_left = 0.0
		_end_dash_vfx()
		_seal_trail()


## The Flatten mode a config names.
##
## WeaponConfig validates the string against its own list, so this only has to
## survive the two lists drifting apart - which it does by flattening the way
## nearly every take wants anyway.
func _flatten_mode(mode_name: String) -> Flatten:
	match mode_name:
		"KEEP": return Flatten.KEEP
		"SETTLE": return Flatten.SETTLE
		"ALL": return Flatten.ALL
	return Flatten.GROUND


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
	_tree.set(PARAM_BLEND, _blend)
	_tree.set(PARAM_STANCE, _stance)

	# The stance take owns the upper body at rest and hands it back as the gait
	# comes up: by walking pace the whole pose is the locomotion clip's - the
	# weapon's own, when it configured one, otherwise the bare-handed take.
	# Read off `_blend` rather than the velocity so it inherits blend_rate's lag.
	_tree.set(PARAM_WEAPON_STANCE_BLEND,
		_stance_weight * (1.0 - clampf(_blend.length(), 0.0, 1.0)))

	# The swing layer fades on the same clock the action layer cross-fades on, so
	# a take that ends hands the pose back instead of popping off it.
	_swing_amount = move_toward(_swing_amount,
		1.0 if state == State.ATTACKING else 0.0,
		delta / maxf(action_blend, 0.01))
	_tree.set(PARAM_SWING_BLEND, _swing_amount)

	# One dimension for the crouch, so every direction of travel shows the same
	# shuffle - reversed when the travel is mostly backwards, because that is the
	# one case where playing it forwards reads as moonwalking.
	var crouch_gait: float = clampf(ground_speed / maxf(crouch_speed, 0.01), 0.0, 1.0)
	if ground.y < 0.0 and absf(ground.y) >= absf(ground.x):
		crouch_gait = -crouch_gait
	_tree.set(PARAM_CROUCH, crouch_gait)

	# The forward clips are in place and carry no travel to match a speed
	# against, so they play straight. The sidesteps were performed at a known
	# pace and the body does walk_speed, so the correction is applied at the
	# sidestep poles and faded out towards the middle - and out again towards the
	# crouch, which has no sidestep for it to be correcting.
	var sidestep: float = lerpf(1.0, walk_speed / maxf(_strafe_speed, 0.01),
		absf(_blend.x))
	_tree.set(PARAM_STRIDE, lerpf(sidestep, 1.0, _stance))


## Ground speed on the blend space's gait axis: 1.0 at walking pace, 2.0 at a
## sprint. Piecewise because the two are not a fixed ratio - either @export can
## be turned without the other, and the clips sit where they sit.
func _gait_axis(ground_speed: float) -> float:
	if ground_speed <= walk_speed:
		return clampf(ground_speed / maxf(walk_speed, 0.01), 0.0, 1.0)
	return clampf(1.0 + (ground_speed - walk_speed)
		/ maxf(run_speed - walk_speed, 0.01), 1.0, 2.0)


func weapon_stroke_count() -> int:
	return _weapon_stroke_count


func force_network_anim(action_name: String, _state_val: int) -> void:
	if not action_name.is_empty():
		_play_action(action_name, 1.0)


func drive_network_step(delta: float) -> void:
	if _tree != null:
		_drive_animation(delta)
