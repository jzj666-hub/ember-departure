@tool
extends SceneTree

const PlayerControllerScript = preload("res://scripts/player_controller.gd")

func _init() -> void:
	print("\n--- landing roll condition probe ---")
	var pc := PlayerControllerScript.new()
	
	# Case 1: High to Low (drop 5.0m >= 1.8m), fast ground speed (4.0m/s >= 2.0m/s).
	# Pre: takeoff_drop = 5.0, ground_speed = 4.0, apex_drop = 5.0.
	# Post: returns land_roll take.
	var res1: Array = pc._landing_for(5.0, 4.0, 5.0)
	assert(res1[0] == "land_roll", "Case 1 failed: high-to-low fast should roll")
	print("  PASS  High to low with fast speed -> land_roll")

	# Case 2: High to Low (drop 5.0m >= 1.8m), slow ground speed (0.5m/s < 2.0m/s).
	# Pre: takeoff_drop = 5.0, ground_speed = 0.5, apex_drop = 5.0.
	# Post: returns land_hard take.
	var res2: Array = pc._landing_for(5.0, 0.5, 5.0)
	assert(res2[0] == "land_hard", "Case 2 failed: high-to-low slow should land_hard")
	print("  PASS  High to low with slow speed -> land_hard")

	# Case 3: Low to High (takeoff y=0, ground y=3, peak y=4.8 -> takeoff_drop = -3.0 < 1.8), fast speed (4.0m/s).
	# Pre: takeoff_drop = -3.0, ground_speed = 4.0, apex_drop = 1.8.
	# Post: returns land_hard (or jump_land), NOT land_roll.
	var res3: Array = pc._landing_for(1.8, 4.0, -3.0)
	assert(res3[0] != "land_roll", "Case 3 failed: low-to-high must not roll")
	assert(res3[0] == "land_hard", "Case 3 failed: low-to-high with 1.8m apex drop should be land_hard")
	print("  PASS  Low to high with fast speed -> land_hard (NO roll)")

	# Case 4: Flat ground jump (takeoff_drop = 0.0 < 1.8), apex drop 0.5m < 1.8m, fast speed (4.0m/s).
	# Pre: takeoff_drop = 0.0, ground_speed = 4.0, apex_drop = 0.5.
	# Post: returns jump_land, NOT land_roll.
	var res4: Array = pc._landing_for(0.5, 4.0, 0.0)
	assert(res4[0] == "jump_land", "Case 4 failed: flat ground small jump should be jump_land")
	print("  PASS  Flat ground jump -> jump_land (NO roll)")

	print("all landing roll probe tests passed!\n")
	quit(0)
