extends SceneTree

const SCENE := "res://scenes/manor_estate.tscn"

func _initialize() -> void:
	_run()

func _run() -> void:
	print("--- 测试室内商铺出口封堵与防跌落碰撞 ---")
	var scn = load(SCENE) as PackedScene
	if scn == null:
		print("FAIL: 无法加载场景")
		quit(1)
		return

	var inst = scn.instantiate() as Node3D
	root.add_child(inst)

	for i in 15:
		await physics_frame

	var indoor = inst.find_child("IndoorManor", true, false)
	if indoor == null:
		print("FAIL: 无 IndoorManor")
		quit(1)
		return

	var south_wall = indoor.find_child("WallSouth", true, false) as StaticBody3D
	if south_wall == null:
		print("FAIL: 无 WallSouth")
		quit(1)
		return
	print("PASS: WallSouth 实体存在，位置:", south_wall.position)

	var door_panel = indoor.find_child("DoorPanelWood", true, false) as StaticBody3D
	print("PASS: 装饰门板存在:", door_panel != null)

	# Raycast through the doorway to ensure full collision blocking
	var space := (indoor as Node3D).get_world_3d().direct_space_state
	var from := Vector3(300.0, 51.5, 305.0) # In front of teleporter
	var to := Vector3(300.0, 51.5, 308.0)   # Outside towards the void
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit := space.intersect_ray(query)

	if hit.is_empty():
		print("FAIL: 射线未被拦截，出口仍有缺口漏网！")
		quit(1)
		return

	print("PASS: 出口射线被实体碰撞完全阻挡！命中点:", hit.position, " 物体:", (hit.collider as Node).name)
	print("\n=== 室内商铺出口封堵验证全部通过 ===")
	inst.queue_free()
	quit(0)
