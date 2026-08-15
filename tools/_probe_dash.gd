extends SceneTree
## Throwaway: drives the weapon test scene headless, fires the Ax's lunge node
## (heavy_1, dash_distance 2.6), and reports what the body actually did.

func _initialize() -> void:
	_run()


func _run() -> void:
	var scene: Node = load("res://scenes/weapon_test.tscn").instantiate()
	root.add_child(scene)
	for i in 20:
		await physics_frame

	scene._select_weapon("Ax.fbx")
	for i in 30:
		await physics_frame

	var player: CharacterBody3D = scene._player
	print("vfx: ", player.dash_vfx, "  speed: ", player.dash_speed)

	player.request_button("attack")
	for i in 30:
		await physics_frame

	var start: Vector3 = player.global_position
	player.request_button("heavy")
	var beams := 0
	var frozen := 0
	var moved := 0.0
	for i in 120:
		await physics_frame
		moved = maxf(moved, start.distance_to(player.global_position))
		for child in scene.get_children():
			if child is DashBeam:
				beams += 1
		if player._dash_left > 0.0 and player._tree != null:
			var slot: int = player._weapon_graph.slot_of(player._weapon_graph.current)
			var scale_val = player._tree.get("parameters/weapon_%d_rate/scale" % slot)
			if slot >= 0 and scale_val != null and float(scale_val) <= 0.001:
				frozen += 1

	print("travelled: %.2f m (config says 2.6)" % moved)
	print("beam nodes seen while dashing: ", beams > 0)
	print("frames with a frozen take: ", frozen)
	print("left transparent: ", _transparent(scene._visual))
	quit()


func _transparent(source: Node) -> bool:
	var stack: Array[Node] = [source]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var drawable := node as GeometryInstance3D
		if drawable != null and drawable.transparency > 0.001:
			return true
		stack.append_array(node.get_children())
	return false
