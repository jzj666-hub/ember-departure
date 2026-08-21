extends SceneTree

const SCENE := "res://scenes/manor_estate.tscn"
const ProfileManagerScript = preload("res://scripts/profile_manager.gd")
const ManorTeleporterScript = preload("res://scripts/manor/manor_teleporter.gd")
const ManorMerchantScript = preload("res://scripts/manor/manor_merchant.gd")

var _failed := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	print("--- 开始庄园与自动草地地表验证 ---")
	_test_currency_system()
	await _test_manor_scene()

	print("\n", "=== 庄园系统全部验证通过 ===" if _failed == 0 else "=== %d 项检查未通过 ===" % _failed)
	quit(0 if _failed == 0 else 1)

func _ok(label: String, passed: bool, detail := "") -> void:
	if not passed:
		_failed += 1
	print("%s %s%s" % ["PASS" if passed else "FAIL", label, "" if detail.is_empty() else "  (%s)" % detail])

func _test_currency_system() -> void:
	print("--- 1. ProfileManager 经济系统测试")
	var prof: Node = root.get_node_or_null("ProfileManager")
	if prof == null:
		prof = ProfileManagerScript.new()
		prof.name = "ProfileManager"
		root.add_child(prof)

	_ok("ProfileManager 单例就绪", prof != null)
	if prof == null:
		return

	prof.set("gold", 500)
	prof.set("ember_vouchers", 0)
	_ok("初始金币设置", int(prof.get("gold")) == 500)

	# Test adding currency
	prof.call("add_gold", 200)
	_ok("add_gold 增加金币", int(prof.get("gold")) == 700)

	prof.call("add_ember_vouchers", 5)
	_ok("add_ember_vouchers 增加凭证", int(prof.get("ember_vouchers")) == 5)

	# Test valid exchange
	var success: bool = bool(prof.call("exchange_gold_to_vouchers", 300, 100)) # 300 gold -> 3 vouchers
	_ok("300金币兑换3张凭证", success and int(prof.get("gold")) == 400 and int(prof.get("ember_vouchers")) == 8)


func _test_manor_scene() -> void:
	print("--- 2. 庄园场景、着色器与自动植被草地测试")
	var scn = load(SCENE) as PackedScene
	_ok("庄园场景资源加载", scn != null)
	if scn == null:
		return

	var inst = scn.instantiate() as Node3D
	_ok("庄园场景实例化", inst != null)
	root.add_child(inst)

	for i in 12:
		await physics_frame

	# Check terrain and shader
	var terrain = inst.find_child("ContinuousTerrain", true, false)
	_ok("连续地形节点存在", terrain != null)

	var grass_mm = inst.find_child("GrassMultiMesh", true, false) as MultiMeshInstance3D
	_ok("自动草地 MultiMesh 覆盖就绪", grass_mm != null and grass_mm.multimesh != null and grass_mm.multimesh.instance_count > 1000)

	var flower_mm = inst.find_child("FlowerMultiMesh", true, false) as MultiMeshInstance3D
	_ok("野花丛 MultiMesh 覆盖就绪", flower_mm != null and flower_mm.multimesh != null and flower_mm.multimesh.instance_count > 500)

	var outdoor_geom = inst.find_child("OutdoorGeometry", true, false)
	_ok("室外建筑与环境群存在", outdoor_geom != null and outdoor_geom.get_child_count() > 5)

	var indoor_root = inst.find_child("IndoorManor", true, false)
	_ok("室内建筑与家具群存在", indoor_root != null and indoor_root.get_child_count() > 5)

	var outdoor_tp: Node3D = inst.find_child("OutdoorTeleporter", true, false) as Node3D
	var indoor_tp: Node3D = inst.find_child("IndoorTeleporter", true, false) as Node3D
	_ok("室外传送点存在", outdoor_tp != null)
	_ok("室内传送点存在", indoor_tp != null)

	var merchant: Node3D = inst.find_child("EmberMerchant", true, false) as Node3D
	_ok("灰烬商贩存在", merchant != null)

	var player: CharacterBody3D = inst.find_child("Player", true, false) as CharacterBody3D
	_ok("玩家角色存在", player != null)

	if outdoor_tp != null and player != null:
		var target_indoor: Vector3 = outdoor_tp.get("target_position")
		outdoor_tp.emit_signal("teleport_requested", target_indoor, 0.0)
		for i in 40:
			await physics_frame
		_ok("室外传送至室内目标位置", player.global_position.distance_to(target_indoor) < 1.0)

	inst.queue_free()
