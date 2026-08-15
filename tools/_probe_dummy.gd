extends SceneTree
## Throwaway: drives the F1 dummy in weapon_test headless. Checks that reaction
## clips reach the skeleton, that hits are counted per contact rather than per
## swing, that a knockdown gets up instead of teleporting, and that the crescent
## is oriented to the swing rather than billboarded flat.

func _initialize() -> void:
	_run()


func _run() -> void:
	# Headless spins uncapped, so a process frame advances almost no animation
	# time and every clip looks frozen. Pin it or the timelines below are noise.
	Engine.max_fps = 60
	var scene: Node = load("res://scenes/weapon_test.tscn").instantiate()
	root.add_child(scene)
	for i in 40:
		await physics_frame
	scene._select_weapon("Abyss Blade.fbx")
	for i in 40:
		await physics_frame

	scene._spawn_or_reset_dummy()
	for i in 5:
		await physics_frame

	var dummy: DummyTarget = scene._dummy
	var ch: Character = dummy.character
	var skel: Skeleton3D = ch.skeleton
	var hips := skel.find_bone("Hips")

	print("--- clips resolve ---")
	for clip in DummyTarget.CLIPS:
		print("  %-16s -> '%s'" % [clip, ch.resolve(clip)])

	print("--- regions ---")
	var c := dummy.global_position
	print("  far miss: ", dummy.segment_hit(c + Vector3(3, 1, 0), c + Vector3(3, 2, 0)))
	var head := dummy.segment_hit(c + Vector3(-1, 1.6, 0), c + Vector3(1, 1.6, 0))
	var chest := dummy.segment_hit(c + Vector3(-1, 1.0, 0), c + Vector3(1, 1.0, 0))
	var legs := dummy.segment_hit(c + Vector3(-1, 0.5, 0), c + Vector3(1, 0.5, 0))
	for probe in [["head", head], ["chest", chest], ["legs", legs]]:
		dummy.reset_dummy()
		await process_frame
		dummy.take_hit(probe[1].point, 20.0, Vector3(1, 0, 0))
		await process_frame
		print("  %-5s local_y=%.2f -> '%s'" % [
			probe[0], dummy.to_local(probe[1].point).y, ch.player.current_animation])

	print("--- poise: low hits stagger, they do not knock down ---")
	dummy.reset_dummy()
	var downs := [0]
	dummy.knocked_down.connect(func() -> void: downs[0] += 1)
	for i in 5:
		dummy.take_hit(legs.point, 20.0, Vector3(1, 0, 0))
		print("    hit %d -> '%s'" % [i + 1, ch.player.current_animation])
		for j in 8:
			await process_frame
	print("  knockdowns from 5 spaced 20-dmg hits: %d" % downs[0])

	print("--- poise break knocks down, then gets up ---")
	dummy.reset_dummy()
	downs[0] = 0
	for i in 6:
		dummy.take_hit(chest.point, 20.0, Vector3(1, 0, 0))
		for j in 3:
			await process_frame
	print("  knockdowns from 6 fast hits: %d, clip '%s'" % [
		downs[0], ch.player.current_animation])

	var t0 := Time.get_ticks_msec()
	var seen := []
	var trace := []
	for i in 300:
		await process_frame
		var el := (Time.get_ticks_msec() - t0) * 0.001
		var cur: String = ch.player.current_animation
		var y: float = (skel.global_transform * skel.get_bone_global_pose(hips)).origin.y
		if seen.is_empty() or seen[-1] != cur:
			seen.append(cur)
			print("    t=%5.2fs  enters '%s'  hip Y=%.2f" % [el, cur, y])
		if i % 25 == 0:
			trace.append("%.2fs:%.2f" % [el, y])
		if cur == ch.resolve(DummyTarget.CLIP_IDLE) and el > 0.5:
			print("    t=%5.2fs  standing again, hip Y=%.2f" % [el, y])
			break
	print("  clip chain: ", seen)
	print("  hip Y over time: ", trace)

	print("--- crescent orientation ---")
	dummy.take_hit(chest.point, 20.0, Vector3(1, 0, 0))
	await process_frame
	var arc: MeshInstance3D = null
	for m in dummy._arcs:
		if m.visible:
			arc = m
			break
	if arc == null:
		print("  NO VISIBLE ARC")
	else:
		var b := arc.global_transform.basis
		var cam := scene._camera as Camera3D
		var to_cam := (cam.global_position - arc.global_position).normalized()
		var mat: StandardMaterial3D = arc.material_override
		print("  faces camera: %.3f (1.0 == exactly)" % b.z.normalized().dot(to_cam))
		print("  billboard_mode: %d (0 == disabled, roll survives)" % mat.billboard_mode)
		print("  mesh surfaces: %d, verts: %d" % [
			arc.mesh.get_surface_count(),
			arc.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()])
		print("  mesh shared across pool: ", dummy._arcs[0].mesh == dummy._arcs[1].mesh)
		print("  material per instance: ", dummy._arcs[0].material_override \
			!= dummy._arcs[1].material_override)

	print("--- multi-contact: one swing, blade in and out twice ---")
	dummy.reset_dummy()
	var hits := [0]
	dummy.hit_taken.connect(func(_d: float, _l: float, _p: Vector3) -> void: hits[0] += 1)
	var inside_a := c + Vector3(-1, 1.0, 0)
	var inside_b := c + Vector3(1, 1.0, 0)
	var outside := c + Vector3(4, 1.0, 0)
	for pass_i in 3:
		scene._blade_inside = false
		# in
		var h := dummy.segment_hit(inside_a, inside_b, 0.12)
		if not h.is_empty():
			dummy.take_hit(h.point, 20.0, Vector3(1, 0, 0))
		for j in 8:
			await process_frame
	print("  3 separate contacts -> %d hits, hp %d" % [hits[0], dummy.hp])

	print("--- swinging for real ---")
	dummy.reset_dummy()
	hits[0] = 0
	scene._player.global_position = dummy.global_position \
		+ dummy.global_transform.basis.z * -1.1
	for i in 10:
		await physics_frame
	for i in 3:
		scene._player.request_button("attack")
		for j in 70:
			await physics_frame
	print("  hits from 3 swings: %d, hp %d" % [hits[0], dummy.hp])

	print("--- out of range ---")
	dummy.reset_dummy()
	hits[0] = 0
	scene._player.global_position = dummy.global_position \
		+ dummy.global_transform.basis.z * -2.5
	for i in 10:
		await physics_frame
	scene._player.request_button("attack")
	for j in 90:
		await physics_frame
	print("  hits: %d (expect 0), hp %d" % [hits[0], dummy.hp])

	print("--- children ---")
	var kinds := {}
	for c2 in dummy.get_children():
		kinds[c2.get_class()] = int(kinds.get(c2.get_class(), 0)) + 1
	print("  ", kinds)
	quit()
