class_name CharacterAnimRig
extends RefCounted
## The runtime AnimationTree of one character: clip preparation, tree construction, layer playback.
##
## Owned by PlayerController; holds no game state, only the mixer and the node
## references needed to drive it. Pre: build() before any other call.
## Invariant: tree != null and player != null after a successful build().

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
const CLIP_HIT_CHEST := "hit_chest"
const CLIP_SWORD_IDLE := "sword_idle"
const CLIP_STOP_WALK := "stop_walking"
const CLIP_SIT_ENTER := "sitting_enter"
const CLIP_SIT_IDLE := "sitting_idle"
const CLIP_SIT_EXIT := "sitting_exit"

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
## it. See flatten().
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
	["hit_chest", CLIP_HIT_CHEST, Flatten.KEEP, false],
	["stop_walking", CLIP_STOP_WALK, Flatten.GROUND, false],
	["sitting_enter", CLIP_SIT_ENTER, Flatten.KEEP, false],
	["sitting_idle", CLIP_SIT_IDLE, Flatten.KEEP, true],
	["sitting_exit", CLIP_SIT_EXIT, Flatten.KEEP, false],
]
## What input 0 is called: the locomotion tree, i.e. no action at all.
const ACTION_NONE := "loco"

## Pre-allocated weapon action slots (wpn_0 to wpn_7) on the action layer.
const WEAPON_SLOTS := WeaponConfig.MAX_ACTIONS
const WEAPON_SLOT_PREFIX := "wpn_"

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

## Cache config for auto-reversing/baking clips like crouch backpedals.
const GEN_LIB := "gen"
const REVERSED := {
	CLIP_CROUCH_WALK: "crouch_back",
}

## The visual this rig was built against, its AnimationPlayer, and the mixer.
var visual: Node3D
var player: AnimationPlayer
var tree: AnimationTree

## The generic weapon takes on the swing layer, in slot order, kept by reference
## so equipping does not have to look them up by name every time.
var slots: Array[AnimationNodeAnimation] = []
## Gait poles in POINTS order, by reference, so a weapon can replace what one
## plays. Invariant: size == POINTS.size() after _build_tree().
var poles: Array[AnimationNodeAnimation] = []
## Strafe clip speed in meters per second, measured off the library.
var strafe_speed := 1.5
## Stance layer weight at rest. 0 = bare-handed. Written by the weapon layer;
## the controller scales it by gait before it reaches the tree.
var stance_weight := 0.0

## The take the upper body holds while carrying something, and the filtered blend
## that mixes it over locomotion. Both are rewritten per weapon.
var _stance_node: AnimationNodeAnimation
var _stance_blend: AnimationNodeBlend2
## The filtered blend the swing layer is mixed through, and the two filters it
## picks between: every bone, or the stance's subtree. See set_swing_filter().
var _swing_blend: AnimationNodeBlend2
var _swing_filter_full: PackedStringArray = []
var _swing_filter_upper: PackedStringArray = []
## How long each action take is, by input name. Recorded because some rates are
## derived from a take's length rather than exported - see fit_rate().
var _take_length := {}

## Horizontal travel per second of each measured clip, in the animation's own
## normalised units. Static, and measured once: the flattening in _prepare_clips()
## is permanent, and one cached AnimationLibrary sits behind every character, so
## by the time the second character spawns there is no travel left to measure.
static var _clip_travel := {}


## Prepares the library and builds the mixer under `character`.
## Post: tree is parented to the visual and active. False when the visual ships
## no AnimationPlayer, in which case nothing was built.
func build(character: Node3D, action_blend: float, brake_rate: float) -> bool:
	visual = character
	player = character.get("player") as AnimationPlayer
	if player == null:
		return false
	_prepare_clips()
	_bake_reversals()
	_build_tree(action_blend, brake_rate)
	return true


# --- the library ------------------------------------------------------------

## Gets the library's clips into a state the tree can use: looped where they are
## cycles, flattened where they travel. See flatten().
func _prepare_clips() -> void:
	var skeleton := visual.get("skeleton") as Skeleton3D
	var motion_scale: float = skeleton.motion_scale if skeleton != null else 1.0
	for clip in CLIPS:
		var full: String = visual.call("resolve", clip)
		if full == "":
			push_warning("%s: missing clip '%s'" % [visual.name, clip])
			continue
		var anim := player.get_animation(full)
		anim.loop_mode = Animation.LOOP_NONE if ONE_SHOT_CLIPS.has(clip) \
			else Animation.LOOP_LINEAR
		if MEASURED_CLIPS.has(clip):
			_measure(clip, anim)
			if _clip_travel.has(clip):
				strafe_speed = float(_clip_travel[clip]) * motion_scale
		if CLIPS[clip]:
			flatten(anim)

	for entry in ACTIONS:
		var take_name := resolve_take(entry[1])
		if take_name == "":
			push_warning("%s: missing clip '%s'" % [visual.name, entry[1]])
			continue
		var take := player.get_animation(take_name)
		take.loop_mode = Animation.LOOP_LINEAR if entry[3] else Animation.LOOP_NONE
		flatten(take, entry[2])
		_take_length[entry[0]] = take.length


## The name the AnimationPlayer knows a take by, following ALTERNATES when the
## first choice is not in the library. "" when neither is there.
func resolve_take(clip: String) -> String:
	var full: String = visual.call("resolve", clip)
	if full == "" and ALTERNATES.has(clip):
		full = visual.call("resolve", ALTERNATES[clip])
	return full


## How fast a clip was performed, before flatten() takes the evidence away.
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
func flatten(anim: Animation, mode: Flatten = Flatten.GROUND) -> void:
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


## The Flatten mode a config names.
##
## WeaponConfig validates the string against its own list, so this only has to
## survive the two lists drifting apart - which it does by flattening the way
## nearly every take wants anyway.
static func flatten_mode(mode_name: String) -> Flatten:
	match mode_name:
		"KEEP": return Flatten.KEEP
		"SETTLE": return Flatten.SETTLE
		"ALL": return Flatten.ALL
	return Flatten.GROUND


## Bakes reversed animation keys at runtime to support backward blend movement.
func _bake_reversals() -> void:
	var lib := AnimationLibrary.new()
	for clip in REVERSED:
		var full: String = visual.call("resolve", clip)
		if full == "":
			continue
		lib.add_animation(REVERSED[clip], _reversed(player.get_animation(full)))
	if player.has_animation_library(GEN_LIB):
		player.remove_animation_library(GEN_LIB)
	player.add_animation_library(GEN_LIB, lib)


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


# --- the tree ---------------------------------------------------------------

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
func _build_tree(action_blend: float, brake_rate: float) -> void:
	var space := AnimationNodeBlendSpace2D.new()
	space.min_space = Vector2(-1.0, -1.0)
	space.max_space = Vector2(1.0, 2.0)
	space.auto_triangles = false
	space.sync_mode = AnimationNodeBlendSpace2D.SYNC_MODE_CYCLIC_MUTABLE
	poles.clear()
	for point in POINTS:
		var pole := _clip_node(point[1], point[3]) as AnimationNodeAnimation
		space.add_blend_point(pole, point[2], -1, point[0])
		poles.append(pole)
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
	# set_stance_filter() - so the filter is built by a function.
	# Weight is not constant: the controller fades it out with gait, so a run
	# is the locomotion clip's own arms. See stance_weight.
	_stance_blend = AnimationNodeBlend2.new()
	_stance_blend.filter_enabled = true
	_stance_blend.filters = stance_filter("Spine")
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
	_add_action_layer(root, action_blend)
	_add_swing_layer(root, action_blend)
	root.connect_node("output", 0, NODE_SWING_BLEND)

	tree = AnimationTree.new()
	tree.name = "Locomotion"
	tree.tree_root = root
	# The blend position is written in _physics_process, so the mixer has to
	# advance there too or the pose lags the body by a variable frame.
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	tree.root_motion_track = NodePath("")
	visual.add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	tree.active = true

	tree.set(PARAM_BRAKE_RATE, brake_rate)


## Every track the stance layer is allowed to drive: one bone and everything
## under it.
##
## A one-handed weapon filters on Spine, which is the torso and both arms - the
## legs stay with locomotion, so the character can walk while holding a sword. A
## two-hander that has to turn the hips wants a bone further down. An empty result
## means the filter matched nothing and the blend would replace the whole pose,
## which is why an unknown bone name falls back to Spine rather than to nothing.
func stance_filter(bone_name: String) -> PackedStringArray:
	var filters := PackedStringArray()
	var skeleton := visual.get("skeleton") as Skeleton3D
	if skeleton == null:
		return filters
	var root_bone := skeleton.find_bone(bone_name)
	if root_bone == -1:
		if bone_name == "Spine":
			return filters
		push_warning("%s: no bone '%s', stance filtered on Spine instead" % [visual.name, bone_name])
		return stance_filter("Spine")
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
	var skeleton := visual.get("skeleton") as Skeleton3D
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
func _add_action_layer(root: AnimationNodeBlendTree, action_blend: float) -> void:
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
## filter's answer, and the filter is chosen per node by the weapon layer.
##
## The slots are still pre-allocated once, for the reason they always were: an
## AnimationNodeTransition rebuilds every input when input_count changes, which
## would knock the pose back to its first frame on every draw.
func _add_swing_layer(root: AnimationNodeBlendTree, action_blend: float) -> void:
	var swing := AnimationNodeTransition.new()
	swing.input_count = WEAPON_SLOTS
	swing.xfade_time = action_blend
	swing.allow_transition_to_self = true
	swing.sync = true
	root.add_node(NODE_SWING, swing)

	# Left pointing at the idle clip until something is equipped: an
	# AnimationNodeAnimation with no animation set warns on every process tick.
	slots.clear()
	for i in WEAPON_SLOTS:
		var slot_name := "%s%d" % [WEAPON_SLOT_PREFIX, i]
		var clip := _clip_node(CLIP_IDLE, false) as AnimationNodeAnimation
		swing.set_input_name(i, slot_name)
		root.add_node("%s_clip" % slot_name, clip)
		root.add_node("%s_rate" % slot_name, AnimationNodeTimeScale.new())
		root.connect_node("%s_rate" % slot_name, 0, "%s_clip" % slot_name)
		root.connect_node(NODE_SWING, i, "%s_rate" % slot_name)
		slots.append(clip)

	_swing_filter_full = _all_bones_filter()
	_swing_filter_upper = stance_filter("Spine")
	_swing_blend = AnimationNodeBlend2.new()
	_swing_blend.filter_enabled = true
	_swing_blend.filters = _swing_filter_full
	root.add_node(NODE_SWING_BLEND, _swing_blend)
	root.connect_node(NODE_SWING_BLEND, 0, NODE_ACTION)
	root.connect_node(NODE_SWING_BLEND, 1, NODE_SWING)


## One blend point. `backward` picks the baked reversal from _bake_reversals()
## rather than asking the blend graph to run the clip in reverse, which it will
## accept and then not do.
func _clip_node(clip: String, backward: bool) -> AnimationRootNode:
	var node := AnimationNodeAnimation.new()
	var full := ""
	if backward and REVERSED.has(clip):
		var baked := "%s/%s" % [GEN_LIB, REVERSED[clip]]
		if player.has_animation(baked):
			full = baked
	if full == "":
		full = resolve_take(clip)
	if full == "":
		full = visual.call("resolve", CLIP_IDLE)
	node.animation = full
	return node


# --- playback ---------------------------------------------------------------

## Puts the swing layer on `slot`, from its first frame, at `rate`.
func play_swing(slot: int, rate: float) -> void:
	if tree == null:
		return
	tree.set("parameters/%s%d_rate/scale" % [WEAPON_SLOT_PREFIX, slot], rate)
	tree.set(PARAM_SWING_REQUEST, "%s%d" % [WEAPON_SLOT_PREFIX, slot])


## Puts the action layer on `action`, from its first frame, at `rate`.
func play_action(action: String, rate: float) -> void:
	if tree == null:
		return
	tree.set("parameters/%s_rate/scale" % action, rate)
	tree.set(PARAM_ACTION_REQUEST, action)


## Hands the pose back to locomotion. The fade is the transition's, so control
## can come back well before the take has finished and the rest of it plays out
## underneath the walk coming back in.
func stop_action() -> void:
	if tree == null:
		return
	tree.set(PARAM_ACTION_REQUEST, ACTION_NONE)


## Fires the skid one-shot at `rate`.
func fire_brake(rate: float) -> void:
	if tree == null:
		return
	tree.set(PARAM_BRAKE_RATE, rate)
	tree.set(PARAM_BRAKE_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## The playback rate that fits exactly one pass of `take` into `span` seconds.
## 1.0 when the take's length is not known, which only happens if the library has
## neither the take nor its alternate.
func fit_rate(take: String, span: float) -> float:
	var length: float = _take_length.get(take, 0.0)
	if length <= 0.01:
		return 1.0
	return length / maxf(span, 0.01)


## Length of a library clip in seconds, or `fallback` when it is not there.
func clip_length(clip: String, fallback: float) -> float:
	if player == null or visual == null:
		return fallback
	var full: String = visual.call("resolve", clip)
	if full == "" or not player.has_animation(full):
		return fallback
	return player.get_animation(full).length


# --- per-frame parameters ---------------------------------------------------

func set_gait(blend: Vector2) -> void:
	tree.set(PARAM_BLEND, blend)


## The crouch fold, 0 standing to 1 crouched: which of the two blend spaces shows.
func set_fold(amount: float) -> void:
	tree.set(PARAM_STANCE, amount)


func set_crouch_gait(amount: float) -> void:
	tree.set(PARAM_CROUCH, amount)


func set_stride(scale: float) -> void:
	tree.set(PARAM_STRIDE, scale)


func set_stance_amount(amount: float) -> void:
	tree.set(PARAM_WEAPON_STANCE_BLEND, amount)


func set_swing_amount(amount: float) -> void:
	if tree != null:
		tree.set(PARAM_SWING_BLEND, amount)


## Back to a clean mixer: nothing swinging, no gait, active again.
func reset() -> void:
	if tree == null:
		return
	tree.active = true
	tree.set(PARAM_SWING_BLEND, 0.0)
	tree.set(PARAM_BLEND, Vector2.ZERO)


# --- what the equipped weapon changes ---------------------------------------

## Points one pole at `clip`, or back at `fallback` when it is empty or not in the
## library. Pre: build() has run. A substituted clip is looped and pinned in
## place; the defaults are left as _prepare_clips() set them.
func set_pole(index: int, clip: String, fallback: String) -> void:
	if player == null or index >= poles.size():
		return
	var full := ""
	var wanted := clip.strip_edges()
	if not wanted.is_empty():
		full = String(visual.call("resolve", wanted))
		if full.is_empty():
			push_warning("%s: no locomotion clip '%s'" % [visual.name, wanted])
		else:
			var anim := player.get_animation(full)
			anim.loop_mode = Animation.LOOP_LINEAR
			# Idempotent. A clip that travels would otherwise walk the model out of
			# its collision shape - the tree runs no root motion. See flatten().
			flatten(anim)
	if full.is_empty():
		full = resolve_take(fallback)
	if not full.is_empty():
		poles[index].animation = full


## Updates upper body holding stance animation clip dynamically.
func set_stance_clip(clip: String) -> void:
	if _stance_node == null or clip.is_empty():
		return
	var full: String = visual.call("resolve", clip)
	if full == "":
		push_warning("%s: no stance clip '%s'" % [visual.name, clip])
		return
	player.get_animation(full).loop_mode = Animation.LOOP_LINEAR
	_stance_node.animation = full


## Which bone's subtree the stance take may drive. See stance_filter().
##
## The swing layer's upper-body half divides the body the same way, so a weapon
## that hangs its stance lower also swings from lower down.
func set_stance_filter(bone_name: String) -> void:
	if bone_name.is_empty():
		return
	var filter := stance_filter(bone_name)
	if _stance_blend != null:
		_stance_blend.filters = filter
	_swing_filter_upper = filter


## Whole body, or the stance's subtree. Decided once per weapon node - swapping
## the filter mid-take would snap the legs from one pose to the other.
func set_swing_filter(full_body: bool) -> void:
	if _swing_blend != null:
		_swing_blend.filters = _swing_filter_full if full_body else _swing_filter_upper
