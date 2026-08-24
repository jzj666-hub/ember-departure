extends SceneTree
## Throwaway: checks the blade trail's config clamps, its palette, its anchor
## maths and its sampling gates. No scene and no rendering - headless safe.
##
## Exits 0 on success. The RID/ObjectDB leak lines it prints on the way out are
## the three BoxMesh resources _fake_item() builds outside any scene, not
## anything WeaponTrail holds: the trail's own resources go with it when it frees
## itself, which the last check asserts.

const HandheldItemScript = preload("res://scripts/handheld_item.gd")

var _failed := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	_check_config()
	_check_palette()
	await _check_anchors()
	await _check_sampling()
	await _check_wiring()
	# One frame so the trail's own queue_free() lands before the engine counts
	# what is still alive; the probe's own nodes are freed outright.
	await process_frame
	print("\n", "所有检查通过" if _failed == 0 else "%d 项失败" % _failed)
	quit(0 if _failed == 0 else 1)


func _ok(label: String, passed: bool, detail := "") -> void:
	if not passed:
		_failed += 1
	print("%s %s%s" % ["PASS" if passed else "FAIL", label,
		"" if detail.is_empty() else "  (%s)" % detail])


# --- the config block -------------------------------------------------------

func _check_config() -> void:
	print("--- config")

	var wild := WeaponConfig.normalise({"trail": {
		"base": 9.0, "tip": -3.0, "hue": 730.0, "hue_spread": 900.0,
		"energy": 99.0, "life": 0.0, "width": 0.0, "particles": -5.0,
		"light": 99.0, "min_speed": -4.0, "blend_mode": "INVALID",
		"fade_exponent": 10.0, "ghost_density": -2.0, "texture_mode": "INVALID",
	}})
	var t: Dictionary = wild.trail
	_ok("base/tip clamped and straightened", t.base == 0.0 and t.tip == 1.0,
		"base %.2f tip %.2f" % [t.base, t.tip])
	_ok("hue wraps rather than clamps", is_equal_approx(t.hue, 10.0), "%.1f" % t.hue)
	_ok("spread capped at half a turn", t.hue_spread == 180.0)
	_ok("energy capped", t.energy == 8.0)
	_ok("life floored", t.life > 0.0)
	_ok("width floored", t.width >= 0.1)
	_ok("particles floored at 0", t.particles == 0.0)
	_ok("min_speed floored at 0", t.min_speed == 0.0)
	_ok("blend_mode defaulted to add", t.blend_mode == "add")
	_ok("fade_exponent clamped", t.fade_exponent == 4.0)
	_ok("ghost_density floored at 0", t.ghost_density == 0.0)
	_ok("texture_mode defaulted to none", t.texture_mode == "none")

	# A config written before the trail block existed. Nothing to migrate: the
	# missing keys are filled and the file is legal again.
	var legacy := WeaponConfig.normalise({
		"grip": {"scale": 0.8},
		"actions": [{"id": "a", "clip": "sword_attack"}],
	})
	_ok("a config with no trail block gets one", legacy.has("trail")
		and legacy.trail.has("min_speed"))
	_ok("a legacy action gets a trail window",
		legacy.actions[0].get("trail_window") == [0.0, 0.0]
		and legacy.actions[0].get("trail") == true)

	var once := WeaponConfig.normalise(legacy)
	_ok("normalise is idempotent", WeaponConfig.to_json(once)
		== WeaponConfig.to_json(WeaponConfig.normalise(once)))

	var inverted := WeaponConfig.normalise({"actions": [
		{"id": "a", "clip": "c", "trail_window": [0.9, 0.2]}]})
	_ok("an inverted trail window is straightened",
		inverted.actions[0].trail_window == [0.2, 0.9])

	var data := WeaponConfig.to_item_data("probe", {"trail": {"hue": 300.0}})
	_ok("to_item_data carries the trail across",
		is_equal_approx(float(data.trail.get("hue", -1.0)), 300.0))


# --- the palette ------------------------------------------------------------

func _check_palette() -> void:
	print("\n--- palette")

	var hue := 200.0
	var spread := 40.0

	var falling := true
	var previous := 2.0
	for i in 11:
		var a := TrailPalette.fade(float(i) / 10.0)
		if a > previous:
			falling = false
		previous = a
	_ok("alpha falls monotonically over a life", falling
		and is_equal_approx(TrailPalette.fade(0.0), 1.0)
		and is_equal_approx(TrailPalette.fade(1.0), 0.0))

	_ok("width shrinks towards the tail",
		is_equal_approx(TrailPalette.shrink(0.0), 1.0)
		and TrailPalette.shrink(1.0) < TrailPalette.shrink(0.5)
		and TrailPalette.shrink(0.5) < 1.0)

	var brighter := true
	var in_band := true
	for i in 11:
		var age := float(i) / 10.0
		var mid := TrailPalette.core(hue, spread, 1.0, age)
		for side in [-1.0, 1.0]:
			var flank := TrailPalette.edge(hue, spread, 1.0, age, side)
			if mid.get_luminance() <= flank.get_luminance():
				brighter = false
			# Bit depth, not taste: a vertex colour is 8-bit, so anything the
			# palette hands a rail at energy 1 has to already be inside 0..1.
			if flank.r > 1.0 or flank.g > 1.0 or flank.b > 1.0:
				in_band = false
			var drift := absf(wrapf(flank.h * 360.0 - hue, -180.0, 180.0))
			if drift > spread + 0.6:
				in_band = false
		if mid.r > 1.0 or mid.g > 1.0 or mid.b > 1.0:
			in_band = false
	_ok("the core rail outshines both flanks", brighter)
	_ok("at energy 1 every rail fits an 8-bit sink, hue inside the family", in_band)

	var hot := TrailPalette.core(hue, spread, 4.0, 0.0)
	_ok("energy above 1 leaves the 0..1 range on purpose", hot.r > 1.0
		or hot.g > 1.0 or hot.b > 1.0)

	var ramp := TrailPalette.gradient(hue, spread, 1.0)
	var ascending := true
	for i in range(1, ramp.get_point_count()):
		if ramp.get_offset(i) <= ramp.get_offset(i - 1):
			ascending = false
	_ok("the ramp has ascending stops", ramp.get_point_count() == TrailPalette.STOPS
		and ascending, "%d stops" % ramp.get_point_count())

	_ok("every preset resolves", TrailPalette.preset("frost").size() == 2
		and TrailPalette.preset("nope").is_empty())


# --- anchors on the blade ---------------------------------------------------

## A bare blade `length` metres long at `item_scale`, grip at the origin.
func _fake_item(length: float, item_scale: float) -> HandheldItem:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.05, length, 0.05)
	mesh.mesh = box
	var packed := PackedScene.new()
	packed.pack(mesh)

	var data := ItemData.new()
	data.item_id = "probe_blade"
	data.mesh_scene = packed
	data.item_scale = item_scale

	var item := HandheldItemScript.new()
	root.add_child(item)
	item.initialize(data)
	return item


func _check_anchors() -> void:
	print("\n--- anchors")

	var item := _fake_item(1.0, 1.0)
	await process_frame
	_ok("the blade measures its own length",
		is_equal_approx(item.measured_length(), 1.0),
		"%.3f m" % item.measured_length())

	item.set_trail_anchors(0.0, 1.0)
	await process_frame
	var grip: Vector3 = item.trail_anchor(0).global_position
	var tip: Vector3 = item.trail_anchor(1).global_position
	_ok("t=0 sits at the grip", grip.length() < 0.001, str(grip))
	_ok("t=1 sits at the tip", absf(tip.y - 1.0) < 0.001, str(tip))

	item.set_trail_anchors(0.5, 0.5)
	await process_frame
	_ok("a collapsed pair lands mid-blade",
		absf(item.trail_anchor(0).global_position.y - 0.5) < 0.001)

	item.free()

	var half := _fake_item(1.0, 0.5)
	half.set_trail_anchors(0.0, 1.0)
	await process_frame
	var scaled_tip: Vector3 = half.trail_anchor(1).global_position
	_ok("anchors scale with item_scale", absf(scaled_tip.y - 0.5) < 0.001,
		"%.3f m at scale 0.5" % scaled_tip.y)
	half.set_item_scale(2.0)
	await process_frame
	_ok("and follow it when it changes",
		absf(half.trail_anchor(1).global_position.y - 2.0) < 0.001)
	half.free()


# --- the ring and its gates -------------------------------------------------

## Drags `item` `step` metres per frame for `frames` frames, letting the trail
## sample it. Returns how many samples the ring ended up holding.
func _sweep(item: HandheldItem, trail: WeaponTrail, step: float,
		frames: int) -> int:
	for i in frames:
		item.position += Vector3(step, 0.0, 0.0)
		await process_frame
	return trail._samples.size()


func _check_sampling() -> void:
	print("\n--- sampling")

	var item := _fake_item(1.0, 1.0)
	var holder := Node3D.new()
	root.add_child(holder)
	var trail := WeaponTrail.start(holder, {"enabled": true, "life": 5.0,
		"min_speed": 0.0, "particles": 0.0, "light": 0.0})
	trail.bind(item)
	await process_frame

	var closed := await _sweep(item, trail, 0.2, 5)
	_ok("a closed trail lays nothing down", closed == 0, "%d samples" % closed)

	trail.open()
	var open_count := await _sweep(item, trail, 0.2, 10)
	_ok("an open trail lays samples down", open_count > 0,
		"%d samples" % open_count)

	var still := trail._samples.size()
	await _sweep(item, trail, 0.0, 5)
	_ok("a still blade adds nothing", trail._samples.size() == still,
		"%d -> %d" % [still, trail._samples.size()])

	var capped := await _sweep(item, trail, 0.2, WeaponTrail.MAX_SAMPLES * 2)
	_ok("the ring is capped", capped <= WeaponTrail.MAX_SAMPLES,
		"%d of %d" % [capped, WeaponTrail.MAX_SAMPLES])

	# Far above any speed a 0.2 m step can reach at any plausible frame rate.
	trail.set_config({"enabled": true, "life": 5.0, "min_speed": 100000.0,
		"particles": 0.0, "light": 0.0})
	var before := trail._samples.size()
	await _sweep(item, trail, 0.2, 10)
	_ok("below min_speed nothing is laid down",
		trail._samples.size() == before,
		"%d -> %d" % [before, trail._samples.size()])

	trail.set_config({"enabled": true, "life": 0.05, "min_speed": 0.0,
		"particles": 0.0, "light": 0.0})
	await create_timer(0.4).timeout
	_ok("samples past their life are dropped", trail._samples.is_empty(),
		"%d left" % trail._samples.size())

	trail.seal()
	await create_timer(0.3).timeout
	_ok("a sealed trail frees itself", not is_instance_valid(trail))

	item.free()
	holder.free()


# --- the whole chain, in the real scene -------------------------------------

## Config -> ItemData -> EquipmentManager -> PlayerController -> a ribbon on a
## swing. Nothing is written to disk: only the in-memory config is switched on.
func _check_wiring() -> void:
	print("\n--- wiring")

	var scene: Node = load("res://scenes/weapon_test.tscn").instantiate()
	root.add_child(scene)
	for i in 20:
		await physics_frame
	scene._select_weapon("Ax.fbx")
	for i in 30:
		await physics_frame

	# Through the panel's own push path, exactly as a slider would.
	scene._config.trail.enabled = true
	scene._config.trail.min_speed = 0.0
	scene._update_weapon_behaviour()
	for i in 5:
		await physics_frame

	var player = scene._player
	_ok("the controller got the settings",
		bool(player._vfx._trail_cfg.get("enabled", false)))
	_ok("and the blade they anchor to", player._vfx._trail_item != null)

	var item = scene._equipped()
	_ok("the panel put markers on the blade", item != null
		and item.trail_anchor(0) != null
		and item.trail_anchor(0).get_node_or_null("Gizmo") != null)

	player.request_button("attack")
	var started := false
	var drew := 0
	for i in 90:
		await physics_frame
		if player._vfx._trail != null and is_instance_valid(player._vfx._trail):
			started = true
			drew = maxi(drew, player._vfx._trail._samples.size())
	_ok("a swing starts a ribbon", started)
	_ok("and the ribbon lays samples down", drew > 0, "%d at most" % drew)

	scene.queue_free()
	await process_frame
