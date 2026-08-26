class_name WeaponTrail
extends MeshInstance3D
## Blade afterimage: a three-rail ribbon, its sparks, and an optional light.
##
## Samples two HandheldItem anchors every frame into a ring and rebuilds an
## ImmediateMesh strip from it - a near-white centre rail flanked by two coloured
## ones, so a cross-section reads as volume rather than as a decal.
## Invariant: vertices are global-space, so this node's transform stays IDENTITY.
## Pre: parented to world space, never to the weapon.

## Samples the ring holds. Caps the mesh, not the life.
const MAX_SAMPLES := 48
## Squared metres the blade must cover before a second sample is laid down.
## Keeps a near-still blade from stacking coincident quads.
const MIN_STEP_SQ := 0.0009
## Sparks at density 1.0.
const SPARK_BASE_COUNT := 18
## Seconds the light takes to reach full power, and to go back out.
const LIGHT_RAMP := 12.0

var _cfg := {}
var _item: HandheldItem
var _custom_anchor_0: Node3D = null
var _custom_anchor_1: Node3D = null
var _mesh: ImmediateMesh
var _material: StandardMaterial3D
var _spark_material: StandardMaterial3D
var _particles: CPUParticles3D
var _light: OmniLight3D
var _ghost_mat: StandardMaterial3D
var _ghosts: Array[Dictionary] = []
var _last_ghost_pos := Vector3(INF, INF, INF)
var _procedural_textures := {}

## Ring of {base, tip, born, link}, oldest first. `link` is false on the first
## sample of a stroke. Invariant: size <= MAX_SAMPLES, `born` ascends.
var _samples: Array[Dictionary] = []
## Seconds since this trail started. Sample ages are measured against it rather
## than against wall time, so a paused tree freezes the ribbon instead of
## draining it.
var _clock := 0.0
## Whether new samples are being laid down.
var _open := false
## Whether the next sample starts a new stroke.
var _broken := true
## No more samples ever; frees itself once the ring and the sparks drain.
var _sealed := false
var _drain := 0.0
## Where the far anchor was at the last accepted sample, or INF before the first.
var _last_tip := Vector3(INF, INF, INF)
## Seconds since that sample. The gate divides by this rather than by one frame's
## delta, or a frame skipped for being too short would inflate the next one's
## speed by however long the gap was.
var _since_sample := 0.0
## Eased 0..1 light power, so the lamp does not pop on with the window.
var _glow := 0.0


## Builds a trail under `into` (world space) from a WeaponConfig trail block.
## Post: returns null if `into` cannot host it; otherwise a trail at identity,
## closed, waiting for bind().
static func start(into: Node, cfg: Dictionary) -> WeaponTrail:
	if into == null or not into.is_inside_tree():
		return null
	var trail := WeaponTrail.new()
	trail.name = "WeaponTrail"
	trail._init_resources()
	trail.set_config(cfg)
	into.add_child(trail)
	trail.global_transform = Transform3D.IDENTITY
	return trail


func _init_resources() -> void:
	_mesh = ImmediateMesh.new()
	mesh = _mesh

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.disable_receive_shadows = true
	# Vertex colours are 8-bit and clamp at 1, so `energy` cannot ride in them.
	# It rides in albedo_color, which is a float uniform, and multiplies every
	# rail alike. See _refresh_material().
	_material.vertex_color_use_as_albedo = true
	material_override = _material

	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_spark_material = StandardMaterial3D.new()
	_spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_spark_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_spark_material.vertex_color_use_as_albedo = true

	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The strip is rebuilt every frame and its bounds trail a frame behind the
	# blade. Cheap insurance against a swing being culled on the frame it starts.
	extra_cull_margin = 4.0


## Swaps in new settings without dropping what is already drawn. Missing keys
## fall back to WeaponConfig defaults, so `cfg` need not be a normalised block.
## Post: every trail key exists in _cfg.
func set_config(cfg: Dictionary) -> void:
	var merged: Dictionary = WeaponConfig.defaults().trail
	for key in merged:
		if cfg.has(key):
			merged[key] = cfg[key]
	_cfg = merged
	_refresh_material()
	_refresh_particles()
	_refresh_light()


## Points the trail at an equipped weapon and places its anchors.
## Pre: item.initialize() has run. Post: trail_anchor(0/1) exist on the blade.
func bind(item: HandheldItem) -> void:
	_item = item
	_custom_anchor_0 = null
	_custom_anchor_1 = null
	_broken = true
	_last_tip = Vector3(INF, INF, INF)
	_since_sample = 0.0
	if item == null:
		return
	item.set_trail_anchors(float(_cfg.base), float(_cfg.tip))
	_mount_emitters()


## Direct anchor binding without requiring a HandheldItem instance (e.g. for character feet/limbs).
func bind_anchors(near_node: Node3D, far_node: Node3D) -> void:
	_item = null
	_custom_anchor_0 = near_node
	_custom_anchor_1 = far_node
	_broken = true
	_last_tip = Vector3(INF, INF, INF)
	_since_sample = 0.0


## Starts laying down samples. Post: the next sample begins a new stroke, and is
## laid down unconditionally - the window opening is itself the reason to draw,
## whatever the blade was doing while it was shut.
func open() -> void:
	if _open:
		return
	_open = true
	_broken = true
	_last_tip = Vector3(INF, INF, INF)
	_since_sample = 0.0
	if _particles != null and float(_cfg.particles) > 0.0:
		_particles.emitting = true


## Stops laying down samples. What is already down keeps fading.
func close() -> void:
	_open = false
	_broken = true
	if _particles != null:
		_particles.emitting = false


## No more samples, ever. Post: frees itself once the ring and sparks drain.
func seal() -> void:
	close()
	_sealed = true
	# Only wait on sparks that exist: with particles off the emitter node is still
	# there but its lifetime was never set, and the default would hold the node
	# alive a second past the last thing it drew.
	_drain = _particles.lifetime if _particles != null \
		and float(_cfg.particles) > 0.0 else 0.0


## Immediately clears all samples, sparks, light, and ghosts without waiting.
func extinguish() -> void:
	close()
	_samples.clear()
	if _mesh != null:
		_mesh.clear_surfaces()
	if _light != null:
		_light.light_energy = 0.0
		_light.visible = false
	_glow = 0.0
	for g in _ghosts:
		if is_instance_valid(g.get("node")):
			g.node.queue_free()
	_ghosts.clear()
	_sealed = true
	_drain = 0.0
	queue_free()


func _process(delta: float) -> void:
	_clock += delta
	_track(delta)
	_expire()
	_rebuild()
	_drive_light(delta)
	_update_ghosts(delta)

	if not _sealed or not _samples.is_empty():
		return
	_drain -= delta
	if _drain <= 0.0:
		queue_free()


func _update_ghosts(delta: float) -> void:
	for i in range(_ghosts.size() - 1, -1, -1):
		var g: Dictionary = _ghosts[i]
		g.left -= delta
		if g.left <= 0.0:
			if is_instance_valid(g.node):
				g.node.queue_free()
			_ghosts.remove_at(i)
		else:
			var alpha: float = clampf(g.left / g.max_life, 0.0, 1.0)
			if is_instance_valid(g.node):
				g.node.transparency = 1.0 - alpha * alpha


# --- sampling ---------------------------------------------------------------

## Reads the blade and lays down at most one sample.
## Post: _samples ends with this frame's pair, or is unchanged and _broken is set
## whenever the stroke was interrupted rather than merely under-sampled.
func _track(delta: float) -> void:
	_since_sample += delta
	var near_node: Node3D = _custom_anchor_0
	var far_node: Node3D = _custom_anchor_1

	if near_node == null or far_node == null:
		if _item == null or not is_instance_valid(_item):
			_broken = true
			return
		near_node = _item.trail_anchor(0)
		far_node = _item.trail_anchor(1)

	if near_node == null or far_node == null or not is_instance_valid(near_node) or not is_instance_valid(far_node):
		_broken = true
		return

	var base := near_node.global_position
	var tip := far_node.global_position
	_drive_emitters(base, tip)

	if not _open or _sealed:
		return
	if _last_tip.is_finite():
		var step := tip - _last_tip
		# Too little movement is the same stroke under-sampled, so the run stays
		# joined across it. Too little speed is the wind-up, which is a different
		# stroke from the swing that follows - hence the break.
		if step.length_squared() < MIN_STEP_SQ:
			return
		if _since_sample > 0.0 and step.length() / _since_sample < float(_cfg.min_speed):
			_broken = true
			return
	_push(base, tip)


func _push(base: Vector3, tip: Vector3) -> void:
	_samples.append({"base": base, "tip": tip, "born": _clock, "link": not _broken})
	_broken = false
	_last_tip = tip
	_since_sample = 0.0
	while _samples.size() > MAX_SAMPLES:
		_samples.pop_front()

	var density := float(_cfg.get("ghost_density", 0.0))
	if density > 0.0 and _item != null and is_instance_valid(_item):
		var step_dist := 0.6 / maxf(density, 0.1)
		if not _last_ghost_pos.is_finite() or _last_ghost_pos.distance_squared_to(tip) >= step_dist * step_dist:
			_last_ghost_pos = tip
			_spawn_weapon_ghost()


func _spawn_weapon_ghost() -> void:
	if _item == null or not is_instance_valid(_item):
		return
	var stack: Array[Node] = [_item]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var mesh_inst := node as MeshInstance3D
		if mesh_inst != null and mesh_inst.visible and mesh_inst.mesh != null:
			var ghost := MeshInstance3D.new()
			ghost.mesh = mesh_inst.mesh
			ghost.global_transform = mesh_inst.global_transform
			ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ghost.material_override = _ghost_mat
			add_child(ghost)
			var life_val := maxf(float(_cfg.life) * 0.85, 0.05)
			_ghosts.append({"node": ghost, "left": life_val, "max_life": life_val})
		stack.append_array(node.get_children())


func _expire() -> void:
	var life := maxf(float(_cfg.life), 0.001)
	while not _samples.is_empty() and _clock - float(_samples[0].born) > life:
		_samples.pop_front()


# --- drawing ----------------------------------------------------------------

## Rebuilds the whole strip. One pair of surfaces per unbroken stroke; a stroke
## of one sample draws nothing, having no length to span.
func _rebuild() -> void:
	_mesh.clear_surfaces()
	if _samples.size() < 2:
		return
	var run: Array[Dictionary] = []
	for sample in _samples:
		if not bool(sample.link) and not run.is_empty():
			_emit_run(run)
			run = []
		run.append(sample)
	_emit_run(run)


func _emit_run(run: Array[Dictionary]) -> void:
	if run.size() < 2:
		return
	# Two strips sharing the centre rail, not one strip across the whole width:
	# the ridge has to appear in both halves or the gradient breaks at the seam.
	_emit_half(run, -1.0)
	_emit_half(run, 1.0)


## One half of the ribbon: the centre rail and the flank on `side`.
## Colours are sampled at energy 1 - the HDR gain lives in the material.
func _emit_half(run: Array[Dictionary], side: float) -> void:
	var life := maxf(float(_cfg.life), 0.001)
	var hue := float(_cfg.hue)
	var spread := float(_cfg.hue_spread)
	var width := float(_cfg.width)
	var exp_val := float(_cfg.get("fade_exponent", 2.0))

	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for sample in run:
		var age := clampf((_clock - float(sample.born)) / life, 0.0, 1.0)
		var base: Vector3 = sample.base
		var tip: Vector3 = sample.tip
		var mid := (base + tip) * 0.5
		var half := (tip - base) * 0.5 * width * TrailPalette.shrink(age)
		var uv_x := age * 6.0
		_mesh.surface_set_uv(Vector2(uv_x, 0.5))
		_mesh.surface_set_color(TrailPalette.core(hue, spread, 1.0, age, exp_val))
		_mesh.surface_add_vertex(mid)
		_mesh.surface_set_uv(Vector2(uv_x, 0.5 + side * 0.5))
		_mesh.surface_set_color(TrailPalette.edge(hue, spread, 1.0, age, side, exp_val))
		_mesh.surface_add_vertex(mid + half * side)
	_mesh.surface_end()


# --- emitters ---------------------------------------------------------------

## Hangs the sparks and the lamp off this node rather than off the anchors: the
## anchors live under a pivot scaled by item_scale, and inheriting that would
## shrink spark sizes and light range with the model. They are driven to the
## blade every frame instead, by _drive_emitters().
func _mount_emitters() -> void:
	if _particles == null:
		var spark := BoxMesh.new()
		spark.size = Vector3(0.03, 0.03, 0.03)
		spark.material = _spark_material

		_particles = CPUParticles3D.new()
		_particles.name = "TrailSparks"
		_particles.mesh = spark
		_particles.emitting = false
		# World space: a spark is shed by the blade, it does not ride along on it.
		_particles.local_coords = false
		_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_particles.direction = Vector3.UP
		_particles.spread = 180.0
		_particles.gravity = Vector3(0.0, -0.8, 0.0)
		_particles.initial_velocity_min = 0.2
		_particles.initial_velocity_max = 1.1
		_particles.scale_amount_min = 0.25
		_particles.scale_amount_max = 1.0
		add_child(_particles)

	if _light == null:
		_light = OmniLight3D.new()
		_light.name = "TrailLight"
		_light.shadow_enabled = false
		_light.visible = false
		add_child(_light)

	_refresh_particles()
	_refresh_light()


## Puts the emitters on the blade. `_particles` is turned to lie along the
## segment so its emission box hugs it; both sit at the segment's midpoint.
func _drive_emitters(base: Vector3, tip: Vector3) -> void:
	var span := tip - base
	var mid := (base + tip) * 0.5
	if _particles != null:
		_particles.global_position = mid
		_particles.emission_box_extents = Vector3(
			0.02, maxf(span.length() * 0.5, 0.01), 0.02)
		if span.length_squared() > 0.000001:
			_particles.global_basis = _blade_basis(span)
	if _light != null:
		_light.global_position = mid


## Orthonormal basis with +Y along `span`. Pre: span is not zero-length.
static func _blade_basis(span: Vector3) -> Basis:
	var up := span.normalized()
	var side := up.cross(Vector3.UP)
	if side.length_squared() < 0.000001:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	return Basis(side, up, side.cross(up)).orthonormalized()


func _refresh_material() -> void:
	if _material == null:
		return
	# Alpha stays at 1: `energy` is a brightness, and multiplying it into alpha
	# would make a brighter trail a more opaque one as well.
	var gain := float(_cfg.energy)
	_material.albedo_color = Color(gain, gain, gain, 1.0)
	
	match String(_cfg.get("blend_mode", "add")):
		"mix":
			_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
			if _spark_material != null:
				_spark_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		"sub":
			_material.blend_mode = BaseMaterial3D.BLEND_MODE_SUB
			if _spark_material != null:
				_spark_material.blend_mode = BaseMaterial3D.BLEND_MODE_SUB
		_:
			_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			if _spark_material != null:
				_spark_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD

	var tex_mode := String(_cfg.get("texture_mode", "none"))
	_material.albedo_texture = _get_procedural_texture(tex_mode)

	if _spark_material != null:
		_spark_material.albedo_color = Color(gain, gain, gain, 1.0)
	if _ghost_mat != null:
		var hue := float(_cfg.hue)
		var col := TrailPalette.plain(hue)
		_ghost_mat.albedo_color = Color(col.r * gain, col.g * gain, col.b * gain, 0.7)


func _get_procedural_texture(mode: String) -> Texture2D:
	if mode == "none":
		return null
	if _procedural_textures.has(mode):
		return _procedural_textures[mode]
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	if mode == "noise":
		for y in 64:
			for x in 64:
				var wave := 0.2 + 0.8 * (0.5 + 0.5 * sin(float(x) * 0.5) * cos(float(y) * 0.3))
				img.set_pixel(x, y, Color(wave, wave, wave, 1.0))
	elif mode == "stripes":
		for y in 64:
			for x in 64:
				var stripe := 1.0 if (x >> 2) % 2 == 0 else 0.15
				img.set_pixel(x, y, Color(stripe, stripe, stripe, 1.0))
	var tex := ImageTexture.create_from_image(img)
	_procedural_textures[mode] = tex
	return tex


func _refresh_particles() -> void:
	if _particles == null:
		return
	var density := float(_cfg.particles)
	_particles.visible = density > 0.0
	if density <= 0.0:
		_particles.emitting = false
		return
	_particles.amount = maxi(1, int(round(SPARK_BASE_COUNT * density)))
	_particles.lifetime = maxf(float(_cfg.life) * 1.6, 0.05)
	# Energy 1: the spark material carries the HDR gain, same as the ribbon.
	_particles.color_ramp = TrailPalette.gradient(
		float(_cfg.hue), float(_cfg.hue_spread), 1.0)
	if _open:
		_particles.emitting = true


func _refresh_light() -> void:
	if _light == null:
		return
	var power := float(_cfg.light)
	_light.visible = power > 0.0
	_light.light_color = TrailPalette.plain(float(_cfg.hue))
	_light.omni_range = clampf(1.2 + power * 0.6, 1.0, 8.0)


## Eases the lamp in and out with the window. Post: light_energy == cfg.light
## while open and settled, 0 once closed and settled.
func _drive_light(delta: float) -> void:
	if _light == null or not _light.visible:
		return
	var wanted := 1.0 if _open else 0.0
	_glow = lerpf(_glow, wanted, 1.0 - exp(-delta * LIGHT_RAMP))
	_light.light_energy = float(_cfg.light) * _glow
