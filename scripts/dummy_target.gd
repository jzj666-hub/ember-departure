class_name DummyTarget
extends Node3D
## Stationary hit target: HP readout, reaction clips, impact VFX.
## Hit detection belongs to the attacker - this node only answers segment_hit()
## and take_hit(). Contact bookkeeping is the attacker's too: a weapon action
## with three strikes in it must land three hits, so nothing here dedupes by
## swing, and nothing here rate-limits them either.

const CharacterPipelineScript = preload("res://tools/character_pipeline.gd")
const DashFadeScript = preload("res://scripts/dash_fade.gd")

## Animation *library keys*, not Animation.resource_name. Character.resolve()
## matches keys, and the shared library is snake_case. Getting these wrong is
## silent: resolve() returns "" and the body sits in its rest pose forever.
const CLIP_IDLE := "idle"
const CLIP_DEATH := "death_01"
const CLIP_HIT_HEAD := "hit_head"
const CLIP_HIT_BODY := "hit_chest"
## A knockdown, not a stagger: hip drops 0.63 -> 0.06 over its 0.83s. Only ever
## played on a poise break, or the dummy spends the fight on the floor.
const CLIP_KNOCKDOWN := "hit_knockback"
## The matching get-up, 0.04 -> 0.87 over 1.53s. Without it a knockdown ends
## with the body teleporting upright.
const CLIP_GETUP := "lay_to_idle"
const CLIPS := [CLIP_IDLE, CLIP_DEATH, CLIP_HIT_HEAD, CLIP_HIT_BODY,
	CLIP_KNOCKDOWN, CLIP_GETUP]

## Hurt capsule, local space. Invariant: the blocker body uses the same numbers.
const HURT_RADIUS := 0.45
const HURT_LOW_Y := 0.45
const HURT_HIGH_Y := 1.30
## Contact height that counts as a head hit. Local y of the surface point.
const HEAD_Y := 1.42

const MAX_HP := 1000.0

## Stagger budget. Damage adds to it, time drains it; crossing it knocks the
## dummy down and empties it. Invariant: 0 <= _poise <= KNOCKDOWN_POISE.
const KNOCKDOWN_POISE := 110.0
const POISE_RECOVERY := 32.0

## Cross-fades. A hard cut is what made the old get-up look instant.
const BLEND_STAGGER := 0.09
const BLEND_KNOCKDOWN := 0.12
const BLEND_GETUP := 0.16
const BLEND_IDLE := 0.22

## Death fade parameters.
const FADE_DELAY := 0.2
const FADE_DURATION := 1.2

## Reused VFX nodes: a hit re-arms a slot, it never allocates. Invariant: every
## VFX array stays at this size after _ready().
const VFX_POOL := 10
const ARC_LIFE := 0.20
const FLASH_LIFE := 0.11
const NUMBER_LIFE := 0.75

## Crescent geometry, local XY plane, arc midpoint at the origin.
const ARC_SEGMENTS := 26
const ARC_SPAN_DEG := 104.0
const ARC_RADIUS := 0.44
const ARC_HALF_WIDTH := 0.085

## For bots and telemetry: everything the dummy learns is readable without
## polling it. See ARCHITECTURE.md "接 bot / 录像 / 联机".
signal hit_taken(damage: float, hp_left: float, hit_pos: Vector3)
signal knocked_down()
signal died()

## What the body is busy doing. A hit while DOWN or GETUP still costs HP but
## does not restart a reaction - there is no stagger to play on the floor.
enum Reaction { NONE, STAGGER, DOWN, GETUP, DEAD }

## Body scene to wear. Set before add_child(); empty picks the first character.
var character_scene := ""

var hp := MAX_HP
var is_dead := false
var character: Character

## Shared across every dummy: the ramps and the crescent are the same for all.
static var _arc_texture: Texture2D
static var _flash_texture: Texture2D
static var _arc_mesh: ArrayMesh

var _reaction := Reaction.NONE
var _poise := 0.0

var _hp_label: Label3D
var _blocker_col: CollisionShape3D
var _fade_tween: Tween
var _character_meshes: Array[GeometryInstance3D] = []

var _arcs: Array[MeshInstance3D] = []
var _arc_mats: Array[StandardMaterial3D] = []
var _flashes: Array[MeshInstance3D] = []
var _flash_mats: Array[StandardMaterial3D] = []
var _vfx_tweens: Array[Tween] = []
var _vfx_next := 0

var _numbers: Array[Label3D] = []
var _number_tweens: Array[Tween] = []
var _number_next := 0


func _ready() -> void:
	_setup_character()
	_setup_blocker()
	_setup_hp_bar()
	_setup_vfx_pool()
	reset_dummy()


func _process(delta: float) -> void:
	if _poise > 0.0:
		_poise = maxf(_poise - POISE_RECOVERY * delta, 0.0)


func _setup_character() -> void:
	var path := character_scene
	if path.is_empty():
		var chars := CharacterPipelineScript.list_characters().filter(
			func(c: Dictionary) -> bool: return ResourceLoader.exists(c.scene))
		if chars.is_empty():
			push_error("%s: no character scenes - run tools\\rebuild_assets.bat" % name)
			return
		path = chars[0].scene
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("%s: '%s' is not a PackedScene" % [name, path])
		return
	character = packed.instantiate() as Character
	if character == null:
		push_error("%s: '%s' root is not a Character" % [name, path])
		return
	add_child(character)
	_prepare_clips()
	_character_meshes = DashFadeScript.collect(character)
	if character.player != null:
		character.player.animation_finished.connect(_on_anim_finished)


## Loop modes once, not per play. The library is a shared resource - every
## Character instance sees these writes, so they must agree with what
## PlayerController wants for the same key (`idle` loops there too).
## Post: every clip in CLIPS resolves, or a warning names the one that does not.
func _prepare_clips() -> void:
	if character == null or character.player == null:
		return
	for clip in CLIPS:
		var full: String = character.resolve(clip)
		if full.is_empty():
			push_warning("%s: missing clip '%s'" % [name, clip])
			continue
		character.player.get_animation(full).loop_mode = \
			Animation.LOOP_LINEAR if clip == CLIP_IDLE else Animation.LOOP_NONE


## A frozen body so the dummy cannot be walked through. No Area3D: nothing
## queries the physics server for hits, segment_hit() answers analytically.
func _setup_blocker() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = HURT_RADIUS
	shape.height = (HURT_HIGH_Y - HURT_LOW_Y) + 2.0 * HURT_RADIUS

	_blocker_col = CollisionShape3D.new()
	_blocker_col.shape = shape
	_blocker_col.position = Vector3(0.0, (HURT_LOW_Y + HURT_HIGH_Y) * 0.5, 0.0)

	var rb := RigidBody3D.new()
	rb.name = "Blocker"
	rb.freeze = true
	rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	rb.add_child(_blocker_col)
	add_child(rb)


func _setup_hp_bar() -> void:
	_hp_label = Label3D.new()
	_hp_label.name = "HpLabel"
	_hp_label.position = Vector3(0.0, 2.05, 0.0)
	_hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_label.no_depth_test = true
	_hp_label.font_size = 28
	_hp_label.outline_size = 8
	_hp_label.outline_modulate = Color.BLACK
	add_child(_hp_label)


# --- hits -------------------------------------------------------------------

## Whether a hit would land at all. Death is the only gate: no time-based
## cooldown lives here on purpose, since two strikes of one weapon action can be
## 60ms apart and any such backstop would eat the second one. Deciding when the
## blade has made a fresh contact is the attacker's job.
func can_take_hit() -> bool:
	return not is_dead


## Blade segment `a`-`b`, thickened by `pad`, against the hurt capsule.
## Returns {} on a miss, else {point, normal} with `point` on the capsule surface.
func segment_hit(a: Vector3, b: Vector3, pad: float = 0.0) -> Dictionary:
	if is_dead:
		return {}
	var lo := global_transform * Vector3(0.0, HURT_LOW_Y, 0.0)
	var hi := global_transform * Vector3(0.0, HURT_HIGH_Y, 0.0)
	var pts := Geometry3D.get_closest_points_between_segments(a, b, lo, hi)
	var offset: Vector3 = pts[0] - pts[1]
	var reach := HURT_RADIUS + maxf(pad, 0.0)
	if offset.length_squared() > reach * reach:
		return {}
	# A blade dead on the axis has no side to mark; face the mark outward instead.
	var normal := offset.normalized() if offset.length_squared() > 1e-8 \
		else -global_transform.basis.z
	return {"point": pts[1] + normal * HURT_RADIUS, "normal": normal}


## Applies `damage` at `hit_pos`. `swing_dir` orients the crescent; zero falls
## back to screen-horizontal. Returns whether the hit landed.
## Post: on landing, hit_taken fires; died() once at 0 hp; knocked_down() on a
## poise break.
func take_hit(hit_pos: Vector3, damage: float, swing_dir: Vector3 = Vector3.ZERO) -> bool:
	if not can_take_hit():
		return false

	hp = maxf(hp - damage, 0.0)
	_update_hp_bar()
	_show_impact(hit_pos, swing_dir)
	_show_damage_number(hit_pos, damage)
	hit_taken.emit(damage, hp, hit_pos)

	if hp <= 0.0:
		is_dead = true
		_reaction = Reaction.DEAD
		if _blocker_col != null:
			_blocker_col.set_deferred("disabled", true)
		var played := character != null and character.play(CLIP_DEATH, BLEND_KNOCKDOWN)
		died.emit()
		if not played:
			_start_fade_out()
		return true

	# Already on the floor: the damage counts, the reaction does not restart.
	if _reaction == Reaction.DOWN or _reaction == Reaction.GETUP:
		return true

	_poise += damage
	if _poise >= KNOCKDOWN_POISE:
		_poise = 0.0
		_reaction = Reaction.DOWN
		_play(CLIP_KNOCKDOWN, BLEND_KNOCKDOWN)
		knocked_down.emit()
		return true

	_reaction = Reaction.STAGGER
	_play(CLIP_HIT_HEAD if to_local(hit_pos).y >= HEAD_Y else CLIP_HIT_BODY,
		BLEND_STAGGER)
	return true


func reset_dummy() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
		_fade_tween = null
	hp = MAX_HP
	is_dead = false
	_poise = 0.0
	_reaction = Reaction.NONE
	if _blocker_col != null:
		_blocker_col.disabled = false
	if _character_meshes.is_empty() and character != null:
		_character_meshes = DashFadeScript.collect(character)
	if not _character_meshes.is_empty():
		DashFadeScript.clear(_character_meshes)
	if character != null:
		character.visible = true
	if _hp_label != null:
		_hp_label.visible = true
		_hp_label.modulate.a = 1.0
	_play(CLIP_IDLE)
	_update_hp_bar()


func _play(clip: String, blend: float = 0.0) -> void:
	if character == null:
		return
	if not character.play(clip, blend):
		push_warning("%s: cannot play '%s'" % [name, clip])


## Deferred: animation_finished fires from inside the mixer's own process, and
## starting the next clip there re-enters AnimationMixer mid-blend.
## Only reaction clips get me - `idle` loops, so it never finishes.
func _on_anim_finished(_anim_name: String) -> void:
	if character == null:
		return
	match _reaction:
		Reaction.STAGGER:
			_reaction = Reaction.NONE
			_play.call_deferred(CLIP_IDLE, BLEND_IDLE)
		Reaction.DOWN:
			_reaction = Reaction.GETUP
			_play.call_deferred(CLIP_GETUP, BLEND_GETUP)
		Reaction.GETUP:
			_reaction = Reaction.NONE
			_play.call_deferred(CLIP_IDLE, BLEND_IDLE)
		Reaction.DEAD:
			_start_fade_out.call_deferred()


func _start_fade_out() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	if _character_meshes.is_empty() and character != null:
		_character_meshes = DashFadeScript.collect(character)

	_fade_tween = create_tween()
	if FADE_DELAY > 0.0:
		_fade_tween.tween_interval(FADE_DELAY)
	_fade_tween.tween_method(func(a: float) -> void:
		DashFadeScript.apply(_character_meshes, a)
		if _hp_label != null:
			_hp_label.modulate.a = a
	, 1.0, 0.0, FADE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_fade_tween.chain().tween_callback(func() -> void:
		queue_free()
	)


func _update_hp_bar() -> void:
	if _hp_label == null:
		return
	if is_dead:
		_hp_label.text = "假人 [ 死亡 ]"
		_hp_label.modulate = Color.GRAY
	else:
		_hp_label.text = "假人 HP: %d / %d" % [int(hp), int(MAX_HP)]
		_hp_label.modulate = Color.GREEN.lerp(Color.RED, 1.0 - (hp / MAX_HP))


# --- vfx --------------------------------------------------------------------

func _setup_vfx_pool() -> void:
	var arc_mesh := _get_arc_mesh()
	var arc_tex := _get_arc_texture()
	var flash_tex := _get_flash_texture()
	for i in VFX_POOL:
		var arc_mat := _impact_material(arc_tex, Color(5.0, 3.2, 1.5, 1.0))
		var arc := MeshInstance3D.new()
		arc.name = "SlashArc%d" % i
		arc.mesh = arc_mesh
		# Per-instance, or ten marks would share one alpha and fade together.
		arc.material_override = arc_mat
		arc.visible = false
		arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(arc)
		_arcs.append(arc)
		_arc_mats.append(arc_mat)

		var flash_mat := _impact_material(flash_tex, Color(6.0, 4.4, 2.4, 1.0))
		var quad := QuadMesh.new()
		quad.size = Vector2(0.4, 0.4)
		var flash := MeshInstance3D.new()
		flash.name = "SlashFlash%d" % i
		flash.mesh = quad
		flash.material_override = flash_mat
		flash.visible = false
		flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(flash)
		_flashes.append(flash)
		_flash_mats.append(flash_mat)

		_vfx_tweens.append(null)

		var label := Label3D.new()
		label.name = "DamageNumber%d" % i
		label.font_size = 36
		label.outline_size = 10
		label.outline_modulate = Color.BLACK
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.visible = false
		add_child(label)
		_numbers.append(label)
		_number_tweens.append(null)


## `tint` above 1 needs Environment.glow_enabled to read as a flash rather than
## flat white. See ARCHITECTURE.md.
func _impact_material(tex: Texture2D, tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# The contact point sits on the skin; without this the near half is swallowed
	# by the body mesh.
	mat.no_depth_test = true
	mat.albedo_texture = tex
	mat.albedo_color = tint
	return mat


## Crescent strip: arc midpoint at the origin, opening along +X, bulging -Y, so
## a basis whose X is the swing direction lays the cut along the swing.
## UV.x runs tip to tip, UV.y across the blade.
static func _get_arc_mesh() -> ArrayMesh:
	if _arc_mesh != null:
		return _arc_mesh
	var span := deg_to_rad(ARC_SPAN_DEG)
	var centre := Vector3(0.0, -ARC_RADIUS, 0.0)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in ARC_SEGMENTS + 1:
		var t := float(i) / ARC_SEGMENTS
		var theta := (t - 0.5) * span
		var radial := Vector3(sin(theta), cos(theta), 0.0)
		var on_arc := centre + radial * ARC_RADIUS
		# Fat in the middle, nothing at the tips - a swipe, not a ribbon.
		var half := ARC_HALF_WIDTH * pow(sin(PI * t), 0.7)
		verts.append(on_arc - radial * half)
		uvs.append(Vector2(t, 0.0))
		verts.append(on_arc + radial * half)
		uvs.append(Vector2(t, 1.0))
		if i < ARC_SEGMENTS:
			var b := i * 2
			idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	_arc_mesh = ArrayMesh.new()
	_arc_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _arc_mesh


## Hot core down the middle of the blade, soft at both edges, easing off toward
## the tips on top of the geometric taper.
static func _get_arc_texture() -> Texture2D:
	if _arc_texture != null:
		return _arc_texture
	var w := 128
	var h := 32
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var u := (x + 0.5) / w
			var v := (y + 0.5) / h
			var across := 1.0 - absf(v * 2.0 - 1.0)
			var alpha := pow(across, 1.7) * pow(sin(PI * u), 0.4)
			# The core stays white while the edges take the material's tint.
			var core := pow(across, 6.0)
			img.set_pixel(x, y, Color(1.0, 0.72 + 0.28 * core, 0.42 + 0.58 * core, alpha))
	_arc_texture = ImageTexture.create_from_image(img)
	return _arc_texture


## Radial burst with two thin streaks through it, for the contact point itself.
static func _get_flash_texture() -> Texture2D:
	if _flash_texture != null:
		return _flash_texture
	var size := 64
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var dx := (x + 0.5) / size * 2.0 - 1.0
			var dy := (y + 0.5) / size * 2.0 - 1.0
			var r := sqrt(dx * dx + dy * dy)
			var core := pow(maxf(1.0 - r, 0.0), 3.0)
			var streak_x := pow(maxf(1.0 - absf(dy) * 9.0, 0.0), 2.0) \
				* pow(maxf(1.0 - absf(dx), 0.0), 2.5)
			var streak_y := pow(maxf(1.0 - absf(dx) * 9.0, 0.0), 2.0) \
				* pow(maxf(1.0 - absf(dy), 0.0), 2.5)
			var alpha := clampf(core + 0.7 * (streak_x + streak_y), 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_flash_texture = ImageTexture.create_from_image(img)
	return _flash_texture


## Camera-facing basis rolled onto `dir`. Billboard mode cannot be used here: it
## overwrites the model basis in the vertex shader, so both the roll and the
## scale tween would be discarded and every mark would come out horizontal.
func _impact_basis(at: Vector3, dir: Vector3) -> Basis:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Basis.IDENTITY
	var fwd := cam.global_position - at
	if fwd.length_squared() < 1e-8:
		return Basis.IDENTITY
	fwd = fwd.normalized()
	var right := dir - fwd * dir.dot(fwd)
	if right.length_squared() < 1e-6:
		var cam_right := cam.global_transform.basis.x
		right = cam_right - fwd * cam_right.dot(fwd)
	if right.length_squared() < 1e-6:
		return Basis.IDENTITY
	right = right.normalized()
	return Basis(right, fwd.cross(right), fwd)


func _show_impact(hit_pos: Vector3, swing_dir: Vector3) -> void:
	var i := _vfx_next
	_vfx_next = (_vfx_next + 1) % VFX_POOL
	if _vfx_tweens[i] != null and _vfx_tweens[i].is_valid():
		_vfx_tweens[i].kill()

	var arc := _arcs[i]
	var flash := _flashes[i]
	var arc_mat := _arc_mats[i]
	var flash_mat := _flash_mats[i]

	var basis := _impact_basis(hit_pos, swing_dir)
	# Toward the camera by a hair: two marks in one frame would z-fight.
	var at := hit_pos + basis.z * 0.02
	# Half the crescents curve the other way, or every hit reads identical.
	var flip := 1.0 if randf() < 0.5 else -1.0
	var spin := Basis.from_scale(Vector3(1.0, flip, 1.0))

	arc.visible = true
	arc_mat.albedo_color.a = 1.0
	flash.visible = true
	flash_mat.albedo_color.a = 1.0
	flash.global_transform = Transform3D(basis * Basis.from_scale(Vector3.ONE * 0.55), at)

	var tween := create_tween()
	tween.set_parallel(true)
	# Opens along the cut while thinning across it - reads as speed.
	tween.tween_method(func(s: float) -> void:
			arc.global_transform = Transform3D(
				basis * spin * Basis.from_scale(
					Vector3(0.75 + s * 0.55, (1.0 - s * 0.45) * flip, 1.0)), at),
		0.0, 1.0, ARC_LIFE).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(arc_mat, "albedo_color:a", 0.0, ARC_LIFE).set_ease(Tween.EASE_IN)
	tween.tween_method(func(s: float) -> void:
			flash.global_transform = Transform3D(
				basis * Basis.from_scale(Vector3.ONE * (0.55 + s * 1.15)), at),
		0.0, 1.0, FLASH_LIFE).set_ease(Tween.EASE_OUT)
	tween.tween_property(flash_mat, "albedo_color:a", 0.0, FLASH_LIFE)
	tween.chain().tween_callback(func() -> void:
		arc.visible = false
		flash.visible = false)
	_vfx_tweens[i] = tween


func _show_damage_number(hit_pos: Vector3, damage: float) -> void:
	var i := _number_next
	_number_next = (_number_next + 1) % VFX_POOL
	var label := _numbers[i]
	if _number_tweens[i] != null and _number_tweens[i].is_valid():
		_number_tweens[i].kill()

	label.text = "-%d HP" % int(damage)
	label.modulate = Color(1.0, 0.25, 0.15, 1.0)
	label.visible = true
	label.global_position = hit_pos + Vector3(randf_range(-0.1, 0.1), 0.2, randf_range(-0.1, 0.1))

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position:y", label.global_position.y + 0.6,
		NUMBER_LIFE).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, NUMBER_LIFE).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func() -> void: label.visible = false)
	_number_tweens[i] = tween
