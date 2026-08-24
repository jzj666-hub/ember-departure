extends SceneTree
## Probe testing manor NPC loading and wandering behavior.

const SCENE := "res://scenes/manor_estate.tscn"
const ManorNpcWanderScript = preload("res://scripts/manor/manor_npc_wander.gd")

var _failed := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	print("--- 开始庄园漫步 NPC 测试 ---")
	await _test_manor_npcs()
	print("\n", "=== NPC 漫步系统全部验证通过 ===" if _failed == 0 else "=== %d 项检查未通过 ===" % _failed)
	quit(0 if _failed == 0 else 1)

func _ok(label: String, passed: bool, detail := "") -> void:
	if not passed:
		_failed += 1
	print("%s %s%s" % ["PASS" if passed else "FAIL", label, "" if detail.is_empty() else "  (%s)" % detail])

func _test_manor_npcs() -> void:
	var scn = load(SCENE) as PackedScene
	_ok("庄园场景资源加载", scn != null)
	if scn == null:
		return

	var inst = scn.instantiate() as Node3D
	_ok("庄园场景实例化", inst != null)
	root.add_child(inst)

	# Allow several physics frames for initialization
	for i in 15:
		await physics_frame

	var wandering_npcs: Array = inst.get("_wandering_npcs")
	_ok("漫步 NPC 列表非空", wandering_npcs != null and wandering_npcs.size() == 5, "count: %d" % (wandering_npcs.size() if wandering_npcs != null else 0))

	if wandering_npcs != null:
		for idx in range(wandering_npcs.size()):
			var npc: CharacterBody3D = wandering_npcs[idx] as CharacterBody3D
			_ok("NPC %d 实例化正常" % (idx + 1), npc != null and is_instance_valid(npc))
			_ok("NPC %d 配置了 ManorNpcWander 意图源" % (idx + 1), npc != null and npc.intent_source is ManorNpcWanderScript)

		# Simulate 120 physics frames (~2 seconds)
		for i in 120:
			await physics_frame

		for idx in range(wandering_npcs.size()):
			var npc: CharacterBody3D = wandering_npcs[idx] as CharacterBody3D
			var wander: RefCounted = npc.intent_source
			var anchor_pos: Vector3 = wander.get("anchor_pos")
			var wander_radius: float = float(wander.get("wander_radius"))
			var dist_to_anchor: float = (npc.global_position - anchor_pos).length()
			_ok("NPC %d 处于漫步半径内" % (idx + 1), dist_to_anchor <= wander_radius + 2.0, "dist: %.2f, max: %.2f" % [dist_to_anchor, wander_radius])
			_ok("NPC %d 未掉出地表 (Y坐标正常)" % (idx + 1), npc.global_position.y > -5.0 and npc.global_position.y < 30.0, "y: %.2f" % npc.global_position.y)

	inst.queue_free()
