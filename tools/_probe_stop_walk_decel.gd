extends SceneTree

const SCENE := "res://scenes/manor_estate.tscn"

func _initialize() -> void:
	_run()

func _run() -> void:
	print("--- 测试 NPC 停步过程中的速度连续衰减 (非直接清零) ---")
	var scn = load(SCENE) as PackedScene
	var inst = scn.instantiate() as Node3D
	root.add_child(inst)

	for i in 15:
		await physics_frame

	var wandering_npcs: Array = inst.get("_wandering_npcs")
	if wandering_npcs != null and not wandering_npcs.is_empty():
		var npc = wandering_npcs[0] as CharacterBody3D
		# Give NPC initial velocity and stop at rate 2.0
		npc.velocity = Vector3(0.0, 0.0, 1.2)
		npc.call("play_stop_walk", 2.0)

		var velocities: Array[float] = []
		for i in 90:
			await physics_frame
			velocities.append(npc.velocity.length())

		print("停步采样 (首5帧):", velocities.slice(0, 5))
		print("停步采样 (末5帧):", velocities.slice(-5))
		var is_smooth: bool = true
		for j in range(velocities.size() - 1):
			if velocities[j+1] > velocities[j] + 0.001:
				is_smooth = false
		var initial_preserved: bool = velocities[0] > 0.5
		var final_stopped: bool = velocities[-1] < 0.01

		print("初始速度得到保持:", initial_preserved)
		print("速度单调平滑衰减:", is_smooth)
		print("最终自然归零:", final_stopped)

		if initial_preserved and is_smooth and final_stopped:
			print("PASS: 停步动画完美带动物理速度衰减！")
			quit(0)
		else:
			print("FAIL: 速度衰减曲线异常")
			quit(1)
	else:
		print("FAIL: 无 NPC")
		quit(1)
