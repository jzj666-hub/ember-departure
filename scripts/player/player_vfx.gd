class_name PlayerVfx
extends RefCounted
## What a lunge looks like, and what the blade leaves behind.
##
## Owned by PlayerController. Holds every node the two effects allocate, so the
## controller only has to say "start", "step" and "stop". `_body` is untyped on
## purpose: typing it PlayerController would make the two classes cyclic.
## Pre: setup() before any other call.

## What a lunge looks like. NONE is also the cheap one to compare against.
enum DashVfx {NONE, BEAM, FADE}

## The PlayerController this draws for. Read for its transform, its visual, its
## dash_* exports and _stand_height.
var _body

## The ribbon this lunge is drawing, null unless dash_vfx is BEAM.
var _dash_beam: DashBeam
## Where the body was at the end of the last physics step, and whether the effect
## is still being fed. Read after move_and_slide() - see drive_dash().
var _dash_prev := Vector3.ZERO
var _dash_trailing := false
## The character's drawables, collected once per lunge, and how far into the fade
## it is: counts down through the lunge, then back up to 1 as the body returns.
var _fade_meshes: Array[GeometryInstance3D] = []
var _fade_alpha := 1.0

## The equipped blade's afterimage settings and the item its anchors sit on.
## Both are handed over by EquipmentManager; empty settings mean no trail.
var _trail_cfg := {}
var _trail_item: HandheldItem
## The ribbon the current take is drawing, null between takes.
var _trail: WeaponTrail
## Seconds into the take the ribbon may draw, from the node's `trail_window`.
## [0, 0] is the whole take. Invariant: start <= end.
var _trail_window := [0.0, 0.0]


func setup(body) -> void:
	_body = body


# --- what a lunge looks like ------------------------------------------------

## Starts the effect the current dash_vfx asks for. Post: BEAM has a ribbon,
## FADE has its mesh list, NONE has neither.
##
## Returns the lunge's remaining seconds: FADE covers the whole distance at once
## and hands back 0, everything else hands back what it was given.
func begin_dash(slide_speed: float, dash_left: float) -> float:
	match _body.dash_vfx:
		DashVfx.BEAM:
			_dash_beam = DashBeam.start(_body.get_parent(), _body.dash_beam_tint,
				_body.dash_beam_life, _body._stand_height)
			if _dash_beam != null:
				_dash_beam.extend(_body.global_position, _body.character)
			_dash_prev = _body.global_position
			_dash_trailing = true
		DashVfx.FADE:
			_fade_meshes = DashFade.collect(_body.character)
			DashFade.spawn_burst(_body.get_parent(), _body.global_position,
				_body._stand_height, _body.dash_beam_tint)

			var dist := slide_speed * dash_left
			var dir: Vector3 = _body.global_basis.z.normalized()
			var collision = _body.move_and_collide(dir * dist, true)
			if collision != null:
				_body.global_position += collision.get_travel()
			else:
				_body.global_position += dir * dist

			_body.velocity = Vector3.ZERO
			dash_left = 0.0
			_fade_alpha = 0.0
			DashFade.apply(_fade_meshes, 0.0)

			if _body.camera != null and _body.camera.has_method("snap"):
				_body.camera.snap()

			DashFade.spawn_burst(_body.get_parent(), _body.global_position,
				_body._stand_height, _body.dash_beam_tint)
			_dash_prev = _body.global_position
			_dash_trailing = true
		_:
			_dash_prev = _body.global_position
			_dash_trailing = true
	return dash_left


## Marks a take that carries no lunge. Nothing to seal - nothing was started.
func stop_trailing() -> void:
	_dash_trailing = false


## Whether there is still something to step: the lunge, or the fade coming back.
func dash_running() -> bool:
	return _dash_trailing or _fade_alpha < 1.0


## One physics step of the running effect. Runs after move_and_slide(), because
## what it wants is where the body actually got to.
##
## Pre: called while dash_running().
func drive_dash(delta: float, dashing: bool) -> void:
	if _dash_beam != null and _body.global_position.distance_squared_to(_dash_prev) > 0.0:
		_dash_beam.extend(_body.global_position, _body.character)
	_dash_prev = _body.global_position

	if not _fade_meshes.is_empty():
		if not dashing and _dash_trailing:
			DashFade.spawn_burst(_body.get_parent(), _body.global_position,
				_body._stand_height, _body.dash_beam_tint)

		var step: float = delta / maxf(_body.dash_fade_out if dashing else _body.dash_fade_in, 0.01)
		var floor_alpha: float = clampf(_body.dash_fade_floor, 0.0, 1.0)
		_fade_alpha = maxf(_fade_alpha - step, floor_alpha) if dashing \
			else minf(_fade_alpha + step, 1.0)
		DashFade.apply(_fade_meshes, _fade_alpha)
		if not dashing and _fade_alpha >= 1.0:
			_fade_meshes.clear()

	if not dashing:
		_dash_trailing = false
		seal_dash()


## Lets the ribbon start fading. Idempotent - the node frees itself.
func seal_dash() -> void:
	if _dash_beam != null:
		if is_instance_valid(_dash_beam):
			_dash_beam.seal()
		_dash_beam = null


## Everything off, now. For the paths where there is no next frame to finish in -
## a reset, or a weapon swapped mid-swing - which would otherwise leave the
## character stuck half-transparent.
func end_dash() -> void:
	_dash_trailing = false
	seal_dash()
	DashFade.clear(_fade_meshes)
	_fade_meshes.clear()
	_fade_alpha = 1.0


# --- what the blade leaves behind -------------------------------------------

func has_trail() -> bool:
	return _trail != null


## Starts a ribbon for `action`, or nothing when the weapon draws none.
## Pre: _trail == null. Post: _trail is bound and closed; the window decides when
## it opens.
func begin_trail(action: Dictionary) -> void:
	if not bool(_trail_cfg.get("enabled", false)) or not bool(action.get("trail", true)):
		return
	if _trail_item == null or not is_instance_valid(_trail_item):
		return
	_trail = WeaponTrail.start(_body.get_parent(), _trail_cfg)
	if _trail == null:
		return
	_trail.bind(_trail_item)
	_trail_window = action.get("trail_window", [0.0, 0.0])


## Opens and closes the ribbon as the take runs through its window. A [0, 0]
## window is the whole take, leaving trail.min_speed to pick the swing out of it.
func drive_trail(elapsed: float) -> void:
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
func seal_trail() -> void:
	if _trail != null:
		if is_instance_valid(_trail):
			_trail.seal()
		_trail = null


## Immediately clears and frees weapon trail and all afterimage lights.
func extinguish_trail() -> void:
	if _trail != null:
		if is_instance_valid(_trail):
			if _trail.has_method("extinguish"):
				_trail.extinguish()
			else:
				_trail.seal()
		_trail = null


## The blade the trail reads its anchors off, and what it draws.
## Pre: item.initialize() has run. Post: the take running now keeps the ribbon it
## already has; the next one picks up the new settings.
func set_trail(cfg: Dictionary, item) -> void:
	_trail_cfg = cfg
	_trail_item = item as HandheldItem
	if _trail == null or not is_instance_valid(_trail):
		return
	if _trail_item == null or cfg.is_empty() or not bool(cfg.get("enabled", false)):
		seal_trail()
		return
	# Re-tuning in the weapon panel lands here every slider tick, so the ribbon is
	# retargeted rather than rebuilt - a rebuild would drop the samples already
	# drawn and make the strip blink on every drag.
	_trail.set_config(cfg)
	_trail.bind(_trail_item)
