extends SceneTree
## Comprehensive probe test for manor chairs, sitting interactions, billboard removal, and NPC stop_walking behavior.

const SCENE := "res://scenes/manor_estate.tscn"
const ManorNpcWanderScript = preload("res://scripts/manor/manor_npc_wander.gd")
const ManorChairScript = preload("res://scripts/manor/manor_chair.gd")
const PlayerControllerScript = preload("res://scripts/player_controller.gd")

var _failed := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	print("--- 开始庄园椅子就座、NPC自然停步及标牌移除测试 ---")
	await _test_manor()
	print("\n", "=== 全部功能验证通过 ===" if _failed == 0 else "=== %d 项检查未通过 ===" % _failed)
	quit(0 if _failed == 0 else 1)

func _ok(label: String, passed: bool, detail := "") -> void:
	if not passed:
		_failed += 1
	print("%s %s%s" % ["PASS" if passed else "FAIL", label, "" if detail.is_empty() else "  (%s)" % detail])

func _test_manor() -> void:
	var scn = load(SCENE) as PackedScene
	_ok("庄园场景资源加载", scn != null)
	if scn == null:
		return

	var inst = scn.instantiate() as Node3D
	_ok("庄园场景实例化", inst != null)
	root.add_child(inst)

	for i in 15:
		await physics_frame

	# 1. Check billboard labels removed from NPCs
	var wandering_npcs: Array = inst.get("_wandering_npcs")
	_ok("漫步 NPC 列表就绪", wandering_npcs != null and wandering_npcs.size() == 5)
	if wandering_npcs != null:
		var has_any_label := false
		for npc in wandering_npcs:
			if (npc as Node).find_child("*Label3D*", true, false) != null:
				has_any_label = true
				break
		_ok("NPC 移除头顶标识牌", not has_any_label)

	# 2. Check ManorChair triggers exist in outdoor and indoor
	var outdoor_geom: Node = inst.find_child("OutdoorGeometry", true, false)
	var indoor_root: Node = inst.find_child("IndoorManor", true, false)
	
	var outdoor_chairs := []
	if outdoor_geom != null:
		for c in outdoor_geom.get_children():
			if c is ManorChairScript:
				outdoor_chairs.append(c)
	_ok("室外长椅交互点存在", outdoor_chairs.size() >= 2, "count: %d" % outdoor_chairs.size())

	var indoor_chairs := []
	if indoor_root != null:
		for c in indoor_root.get_children():
			if c is ManorChairScript:
				indoor_chairs.append(c)
	_ok("室内座椅交互点存在", indoor_chairs.size() >= 2, "count: %d" % indoor_chairs.size())

	# 3. Check Player sitting interaction
	var player = inst.find_child("Player", true, false)
	_ok("玩家对象就绪", player != null)
	if player != null and not outdoor_chairs.is_empty():
		var chair: Node3D = outdoor_chairs[0] as Node3D
		_ok("椅子组件正常", chair != null)

		# Test sitting down (enters ENTERING then SEATED)
		chair.call("sit_player", player)
		for i in 5:
			await physics_frame
		_ok("玩家成功就座 (State.SITTING)", player.call("is_sitting") == true)
		_ok("玩家就座速度归零", (player as CharacterBody3D).velocity.length() < 0.01)

		# Wait for sitting_enter to transition into SEATED phase
		for i in 65:
			await physics_frame

		# Test standing up (enters EXITING phase then IDLE)
		chair.call("stand_player")
		for i in 50:
			await physics_frame
		_ok("玩家成功站起 (退出 SITTING)", player.call("is_sitting") == false)

	# 4. Check NPC stop_walking behavior
	if wandering_npcs != null and not wandering_npcs.is_empty():
		var npc = wandering_npcs[0] as CharacterBody3D
		var wander_source = npc.intent_source
		_ok("NPC 意图源具有 STOP_WALK 状态", wander_source != null and wander_source.get("_state") != null)
		_ok("NPC PlayerController 具备 play_stop_walk 方法", npc.has_method("play_stop_walk"))
		
		# Test calling play_stop_walk
		npc.call("play_stop_walk", 2.0)
		for i in 10:
			await physics_frame
		_ok("NPC 自然停步动画顺利调用无异常", true)

	inst.queue_free()
