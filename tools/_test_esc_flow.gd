extends SceneTree

func _initialize() -> void:
	print("--- Step 1: Change to main_menu.tscn ---")
	change_scene_to_file("res://scenes/main_menu.tscn")
	await process_frame
	await process_frame
	print("Current scene is:", current_scene.name if current_scene else "null")

	print("--- Step 2: Change to title_screen.tscn ---")
	change_scene_to_file("res://scenes/player_client/title_screen.tscn")
	await process_frame
	await process_frame
	print("Current scene is:", current_scene.name if current_scene else "null")

	print("--- Step 3: Launch chase_game.tscn ---")
	var chase_scene := load("res://scenes/player_client/chase_game.tscn") as PackedScene
	var inst := chase_scene.instantiate()
	root.add_child(inst)
	current_scene.queue_free()
	current_scene = inst
	await process_frame
	await process_frame
	print("Current scene is:", current_scene.name if current_scene else "null")

	print("--- Step 4: Press ESC from chase_game back to title_screen ---")
	var esc_event := InputEventKey.new()
	esc_event.keycode = KEY_ESCAPE
	esc_event.pressed = true
	current_scene._unhandled_input(esc_event)
	await process_frame
	await process_frame
	print("Current scene is:", current_scene.name if current_scene else "null")

	print("--- Step 5: Press ESC from title_screen back to main_menu ---")
	current_scene._unhandled_input(esc_event)
	await process_frame
	await process_frame
	print("Current scene is:", current_scene.name if current_scene else "null")

	print("Done test flow!")
	quit(0)
