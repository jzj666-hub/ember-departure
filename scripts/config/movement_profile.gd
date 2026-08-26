class_name MovementProfile
extends Resource
## Tunable locomotion/jump/climb/land/roll/dash values for one character archetype.
## Applied by PlayerController.apply_movement_profile(): every field here is copied onto
## the identically-named @export on the controller.
##
## Field names MUST match PlayerController's exports exactly. nav_provider.gd reads several
## of them off the body by string name ("walk_speed", "jump_speed", "climb_enabled", ...),
## so the copy target stays on the controller and this stays an override layer.
## Defaults are byte-identical to the controller's, so an empty .tres is a no-op.
##
## Full design rationale for each value lives on the matching export in player_controller.gd.
##
## Usage from a scene that builds its characters in code:
##   _npc = PlayerControllerScript.new()
##   _npc.movement_profile = preload("res://config/movement/npc_heavy.tres")
##   add_child(_npc)
##   _npc.setup(visual, camera)     # <- profile is applied here

@export var footstep_enabled := true
## Defaults chosen to sit close to the pace the clips were performed at, which is
@export var walk_speed := 1.1
@export var run_speed := 3.6
@export var crouch_speed := 0.7
## How hard the body chases its target speed, per second.
@export var acceleration := 14.0
## Radians per second the character turns towards the camera while moving.
@export var turn_rate := 24.0
## How hard the blend position chases the body, per second. Below `acceleration`
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
@export var brake_margin := 0.5
## Playback rate of the skid clip. The take is performed at a gentler stop than
@export var brake_rate := 2.0
## Seconds before a skid can fire again, so standing against a wall on the
@export var brake_cooldown := 0.9

@export_group("jump")
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

@export_group("climb")
## Whether a jump request looks for a ledge before deciding it is a jump.
@export var climb_enabled := true
## Lowest ledge worth climbing, in metres above the feet. Below this the jump
@export var climb_min_height := 0.5
## Highest ledge the character will pull itself onto, in metres above the feet.
@export var climb_max_height := 2.2
## How far in front of the body the ledge probe looks, in metres, on top of the
@export var climb_reach := 0.45
## How flat the top of a ledge has to be before it counts as somewhere to stand:
@export var climb_floor_dot := 0.7
## Duration of the climb pull-up in seconds, for a one-cell (1 m) ledge.
@export var climb_duration_1m := 0.7
## Duration of the climb pull-up in seconds, for a two-cell (2 m) ledge.
@export var climb_duration_2m := 1.3
## What fraction of the climb is spent going up before the body starts moving in.
@export var climb_rise_share := 0.62
## How much of the character's own capsule has to fit on the ledge for the climb
@export var climb_clearance := 0.9

@export_group("step up")
## Whether the body lifts itself over kerbs too low to be worth a jump.
@export var step_up_enabled := true
## Tallest kerb the body will lift itself over, in metres. Keep at or below the
@export var step_max_height := 0.4
## How far past its own radius the body probes for somewhere to put its feet.
@export var step_probe_ahead := 0.08

@export_group("fall and land")
## Whether walking off a platform plays the climb-down take rather than the
@export var fall_climb_down := true
## Drop below which a fall lands with no take at all, in metres. A kerb is not an
@export var land_min_drop := 0.55
## Drop up to which the soft landing plays, in metres.
@export var land_soft_drop := 1.8
## Drop up to which the hard landing plays. Above it, the fall rolls out.
@export var land_hard_drop := 3.4
## Ground speed at contact at or above which a fall rolls out whatever the drop
@export var land_roll_speed_min := 2.0
## Drop from peak at or above which a fast landing rolls out, in metres.
@export var land_roll_drop_min := 1.8
## Seconds control is held for each of the three, in the same order. The takes
@export var land_soft_recover := 0.22
@export var land_hard_recover := 0.38
@export var land_roll_recover := 0.95
## How much of each take plays BEFORE the feet arrive, in seconds.
@export var land_soft_lead := 0.5
@export var land_hard_lead := 0.7
@export var land_roll_lead := 0.35
## Downward vertical speed in m/s required before landing prediction triggers.
@export var land_arm_vy_min := 3.5
## Fastest a landing take may be run when there is not enough airtime left to
@export var land_rate_cap := 4.0
## How far below the feet the fall looks for the ground it is going to hit, in
@export var fall_probe := 25.0
## Peak ground speed the roll-out landing carries, in m/s.
@export var land_roll_speed := 3.4

@export_group("roll")
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
@export var attack_turn := 0.5

@export_group("the dash")
## How fast every lunge is covered, in m/s. The weapon says how far
@export var dash_speed := 6.0
@export var dash_vfx: PlayerVfx.DashVfx = PlayerVfx.DashVfx.BEAM
## BEAM: the ribbon's colour and how long it hangs around after the lunge ends.
@export var dash_beam_tint := Color(0.60, 0.78, 1.0, 0.55)
@export var dash_beam_life := 0.28
## FADE: how far down the body goes, and the two ramps either side of the lunge.
@export var dash_fade_floor := 0.0
@export var dash_fade_out := 0.04
@export var dash_fade_in := 0.10
