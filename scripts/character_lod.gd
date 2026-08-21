class_name CharacterLOD
extends Node
## Per-character compute tier, picked from camera distance and on-screen state.
## Pre: attach() gets a character visual already inside the tree, and that visual's
## meshes carry no visibility_range of their own.
## Post: meshes cull engine-side past cull_end; the animation mixer only advances
## at the tier's rate.
## Invariant: only rendering and pose evaluation are throttled. The body's
## _physics_process, navigation and netcode are never touched, so a tier change
## can never alter gameplay.

enum Tier { NEAR, MID, FAR, CULLED }

## HUD labels, indexed by Tier.
const TIER_NAMES := ["近", "中", "远", "隐"]

## Meters of stickiness on every tier edge. Stops an edge-parked body flipping.
const HYSTERESIS := 2.0
## Seconds between subtree rescans. Picks up weapons and vfx added after attach.
const RESCAN_INTERVAL := 1.0
## Cap on one resumed advance, seconds. Bounds the catch-up after a frozen spell.
const MAX_STEP := 0.25

## Global gate. Defaults off headless: no renderer there, and every
## tools/_probe_*.gd expects full-rate animation.
static var enabled := DisplayServer.get_name() != "headless"
## Every live controller. Read by HUDs and bots.
static var instances: Array[CharacterLOD] = []

## Tier edges, meters from camera to body centre. Must ascend.
@export var near_end := 15.0
@export var mid_end := 35.0
@export var cull_end := 150.0
## Mixer advance rate per tier, Hz. NEAR is engine-driven, CULLED is frozen.
@export var mid_hz := 30.0
@export var far_hz := 10.0
## Last tier still casting shadows.
@export var shadow_tier: int = Tier.MID
## Off-screen bodies sink to at least this tier; shadows keep animating there.
@export var offscreen_tier: int = Tier.FAR
@export var offscreen_throttle := true
## Engine-side dissolve width before cull_end, meters.
@export var fade_margin := 8.0
## lod_bias multiplier per tier. Below 1 makes the engine drop to coarser mesh
## LODs sooner; no effect on meshes the importer could not build LODs for.
@export var lod_bias_scale := PackedFloat32Array([1.0, 0.8, 0.4, 0.4])

## Distance tier. Drives what the meshes are set to. Read-only for callers.
var tier: int = Tier.NEAR
## Compute tier: the distance tier, sunk further while the body is off screen.
## Drives the mixer rate only, never the meshes - an off-screen body still casts
## its shadow into frame, so shadows follow distance alone. Never below `tier`.
var anim_tier: int = Tier.NEAR
## >= 0 pins both tiers and ignores distance. Test and bot hook.
var forced := -1

var _visual: Node3D
var _mixer: AnimationMixer
var _mode0 := AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
var _notifier: VisibleOnScreenNotifier3D
## Local Y of the point distances are measured to.
var _centre := 0.9
var _geo: Array[GeometryInstance3D] = []
## Values as found, parallel to _geo. Restored whenever a tier allows them.
var _shadow0 := PackedInt32Array()
var _bias0 := PackedFloat32Array()
## instance_id -> index into _geo. Carries originals across a rescan.
var _index := {}
var _accum := 0.0
var _since_scan := 0.0


# --- entry points -----------------------------------------------------------

## Builds and parents a tier controller under `visual`. Idempotent: an existing
## one is rescanned and returned. `mixer` defaults to the first AnimationTree,
## else the first AnimationPlayer.
static func attach(visual: Node3D, mixer: AnimationMixer = null) -> CharacterLOD:
	if visual == null or not visual.is_inside_tree():
		return null
	var found := visual.get_node_or_null("CharacterLOD") as CharacterLOD
	if found != null:
		found.rescan()
		return found
	var node := CharacterLOD.new()
	node.name = "CharacterLOD"
	# After the controller, so a tier advance reads the blend it just wrote.
	node.process_physics_priority = 100
	visual.add_child(node)
	node.bind(visual, mixer)
	return node


## Global on/off. Off restores every live character to what attach() found.
static func set_enabled(on: bool) -> void:
	enabled = on
	for node in instances:
		if not is_instance_valid(node):
			continue
		if on:
			node.rescan()
		else:
			node.tier = Tier.NEAR
			node.anim_tier = Tier.NEAR
			node._restore()


## One-line compute-tier census for a HUD, e.g. "LOD 近1 中0 远1 隐0".
static func debug_line() -> String:
	var counts := [0, 0, 0, 0]
	for node in instances:
		if is_instance_valid(node):
			counts[clampi(node.anim_tier, 0, 3)] += 1
	var parts := PackedStringArray()
	for i in counts.size():
		parts.append("%s%d" % [TIER_NAMES[i], counts[i]])
	return "LOD " + " ".join(parts) + ("" if enabled else " (关)")


static func tier_name(t: int) -> String:
	return TIER_NAMES[clampi(t, 0, 3)]


# --- wiring -----------------------------------------------------------------

func _enter_tree() -> void:
	if not instances.has(self):
		instances.append(self)


func _exit_tree() -> void:
	instances.erase(self)
	_restore()


## Binds to a visual. Post: geometry collected, screen notifier sized to the body.
func bind(visual: Node3D, mixer: AnimationMixer = null) -> void:
	_visual = visual
	var raw: Variant = visual.get("body_height")
	var height: float = float(raw) if raw != null else 0.0
	if height <= 0.1:
		height = 1.75
	_centre = height * 0.5

	_mixer = mixer if mixer != null else _find_mixer(visual)
	if _mixer != null:
		_mode0 = _mixer.callback_mode_process

	_notifier = VisibleOnScreenNotifier3D.new()
	_notifier.name = "LODScreenNotifier"
	_notifier.aabb = AABB(Vector3(-0.6, 0.0, -0.6), Vector3(1.2, height, 1.2))
	visual.add_child(_notifier)

	rescan()


## First AnimationTree under `visual`, else first AnimationPlayer. A tree wins
## because when one is bound the player is only a clip source.
func _find_mixer(visual: Node3D) -> AnimationMixer:
	var fallback: AnimationMixer = null
	var stack: Array[Node] = [visual]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is AnimationTree:
			return node as AnimationMixer
		if fallback == null and node is AnimationPlayer:
			fallback = node as AnimationMixer
	return fallback


## Rebuilds the geometry list from the live subtree. Originals are captured the
## first time a node is seen, so a rescan never records a value this node wrote.
func rescan() -> void:
	if _visual == null or not is_instance_valid(_visual):
		return
	var fresh: Array[GeometryInstance3D] = []
	var shadow := PackedInt32Array()
	var bias := PackedFloat32Array()
	var stack: Array[Node] = [_visual]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		var geo := node as GeometryInstance3D
		if geo == null:
			continue
		var was: int = _index.get(geo.get_instance_id(), -1)
		if was >= 0:
			shadow.append(_shadow0[was])
			bias.append(_bias0[was])
		else:
			shadow.append(geo.cast_shadow)
			bias.append(geo.lod_bias)
		fresh.append(geo)

	_geo = fresh
	_shadow0 = shadow
	_bias0 = bias
	_index.clear()
	for i in _geo.size():
		_index[_geo[i].get_instance_id()] = i
	# While gated off the meshes are left exactly as found; set_enabled(true)
	# comes back through here and paints them.
	if enabled or forced >= 0:
		_paint(tier)


# --- per frame --------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _visual == null or not is_instance_valid(_visual):
		return
	if not enabled and forced < 0:
		return
	_since_scan += delta
	if _since_scan >= RESCAN_INTERVAL:
		_since_scan = 0.0
		rescan()
	var render := _pick()
	_apply(render, maxi(render, _offscreen_floor()))
	_pump(delta)


## Distance from the active camera to the body centre, or -1 with no camera.
func distance() -> float:
	if _visual == null or not _visual.is_inside_tree():
		return -1.0
	var cam := _visual.get_viewport().get_camera_3d()
	if cam == null:
		return -1.0
	return (_visual.global_position + Vector3.UP * _centre).distance_to(cam.global_position)


func _pick() -> int:
	if forced >= 0:
		return clampi(forced, Tier.NEAR, Tier.CULLED)
	if not enabled:
		return Tier.NEAR
	var dist := distance()
	if dist < 0.0:
		return Tier.NEAR
	return tier_for(dist)


## Floor the compute tier is held at while the body is outside every camera
## frustum. NEAR when the clamp is off or the tier is pinned.
func _offscreen_floor() -> int:
	if forced >= 0 or not enabled or not offscreen_throttle:
		return Tier.NEAR
	if _notifier == null or _notifier.is_on_screen():
		return Tier.NEAR
	return offscreen_tier


## Tier for a camera distance. The edge being crossed outward is widened by
## HYSTERESIS and the ones already behind are narrowed by it, so a body sitting
## on an edge cannot flip every frame.
func tier_for(dist: float) -> int:
	var edges := PackedFloat32Array([near_end, mid_end, cull_end])
	for i in edges.size():
		var edge: float = edges[i]
		if i == tier:
			edge += HYSTERESIS
		elif i < tier:
			edge -= HYSTERESIS
		if dist <= edge:
			return i
	return Tier.CULLED


## Commits one frame's pair: `render` onto the meshes, `animate` onto the mixer.
## Pre: animate >= render.
func _apply(render: int, animate: int) -> void:
	if animate != anim_tier:
		anim_tier = animate
		_accum = 0.0
		if _mixer != null and is_instance_valid(_mixer):
			_mixer.callback_mode_process = (_mode0 if animate == Tier.NEAR
				else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL)
	if render != tier:
		tier = render
		_paint(render)


## Advances a manual-mode mixer at the compute tier's rate. No-op at NEAR (the
## engine still drives it) and at CULLED (nothing to look at).
func _pump(delta: float) -> void:
	if _mixer == null or not is_instance_valid(_mixer):
		return
	if anim_tier == Tier.NEAR or anim_tier == Tier.CULLED:
		return
	var hz: float = mid_hz if anim_tier == Tier.MID else far_hz
	if hz <= 0.0:
		return
	_accum = minf(_accum + delta, MAX_STEP)
	if _accum >= 1.0 / hz:
		_mixer.advance(_accum)
		_accum = 0.0


## Writes the tier's render settings onto every collected mesh.
func _paint(t: int) -> void:
	var keeps_shadow := t <= shadow_tier
	var scale: float = lod_bias_scale[clampi(t, 0, lod_bias_scale.size() - 1)]
	for i in _geo.size():
		var geo := _geo[i]
		if not is_instance_valid(geo):
			continue
		geo.cast_shadow = (_shadow0[i] as GeometryInstance3D.ShadowCastingSetting if keeps_shadow
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		geo.lod_bias = _bias0[i] * scale
		geo.visibility_range_end = cull_end
		geo.visibility_range_end_margin = fade_margin
		geo.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


## Puts the mixer and every mesh back the way bind() found them.
func _restore() -> void:
	if _mixer != null and is_instance_valid(_mixer):
		_mixer.callback_mode_process = _mode0
	for i in _geo.size():
		var geo := _geo[i]
		if not is_instance_valid(geo):
			continue
		geo.cast_shadow = _shadow0[i] as GeometryInstance3D.ShadowCastingSetting
		geo.lod_bias = _bias0[i]
		geo.visibility_range_end = 0.0
		geo.visibility_range_end_margin = 0.0
		geo.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
