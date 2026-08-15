@tool
extends SceneTree

const PlayerControllerScript = preload("res://scripts/player_controller.gd")

func _init() -> void:
	print("\n--- full physics state landing simulation probe ---")
	var pc := PlayerControllerScript.new()
	
	# Simulate taking off from high ground y = 5.0m with speed 4.0m/s
	pc._take_off_y = 5.0
	pc._air_peak_y = 5.0
	pc._air_speed = 4.0
	pc.state = PlayerControllerScript.State.FALLING
	pc.global_position = Vector3(0.0, 0.0, 0.0) # landed at y = 0.0
	
	# Pre: _take_off_y = 5.0, global_position.y = 0.0, _air_speed = 4.0
	# Action: call _land()
	pc._land()
	
	assert(pc.state == PlayerControllerScript.State.LANDING, "State should be LANDING")
	assert(pc._action_slides == true, "_action_slides should be true for land_roll")
	print("  PASS  Falling from 5.0m to 0.0m with speed 4.0m/s successfully triggers land_roll and sliding!")

	# Simulate low-to-high jump: takeoff y = 0.0m, landed on y = 3.0m, apex = 4.8m, speed = 4.0m/s
	pc._take_off_y = 0.0
	pc._air_peak_y = 4.8
	pc._air_speed = 4.0
	pc.state = PlayerControllerScript.State.JUMPING
	pc.global_position = Vector3(0.0, 3.0, 0.0)

	pc._land()

	assert(pc._action_slides == false, "_action_slides must be false for low-to-high (no roll slide)")
	print("  PASS  Jumping from 0.0m to 3.0m (low-to-high) does NOT trigger land_roll slide!")

	print("all full physics landing probe tests passed!\n")
	quit(0)
