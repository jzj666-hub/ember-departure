extends SceneTree
## Test suite for SkillMist (Skill 8).

func _initialize() -> void:
	_run()

func _run() -> void:
	Engine.max_fps = 60
	print("--- Testing SkillMist Registry & Config ---")
	var SkillRegistryScript = load("res://scripts/skills/skill_registry.gd")
	var mist_skill = SkillRegistryScript.get_skill("mist")
	if mist_skill == null:
		print("FAIL: Skill mist not registered")
		quit(1)
		return

	print("Skill Name: ", mist_skill.call("get_name"))
	print("Skill Title: ", mist_skill.call("get_title"))

	var root_node = Node3D.new()
	root.add_child(root_node)

	# Create dummy caster and two targets
	var caster = CharacterBody3D.new()
	caster.name = "Caster"
	caster.position = Vector3(0, 0, 0)
	root_node.add_child(caster)

	var target_near = CharacterBody3D.new()
	target_near.name = "TargetNear"
	target_near.position = Vector3(2.0, 0, 0)
	root_node.add_child(target_near)

	var target_far = CharacterBody3D.new()
	target_far.name = "TargetFar"
	target_far.position = Vector3(8.0, 0, 0)
	root_node.add_child(target_far)

	var target_outside = CharacterBody3D.new()
	target_outside.name = "TargetOutside"
	target_outside.position = Vector3(15.0, 0, 0)
	root_node.add_child(target_outside)

	for i in 3:
		await physics_frame

	var res: Dictionary = mist_skill.call("cast", caster, Vector3.ZERO, root_node, false)
	print("Cast result: ", res)

	var active_blinds: Dictionary = mist_skill.get("_active_blinds")
	print("Active blinds count: ", active_blinds.size())

	if active_blinds.has(caster.get_instance_id()):
		print("FAIL: Caster was blinded!")
		quit(1)
		return
	print("PASS: Caster is immune")

	if active_blinds.has(target_outside.get_instance_id()):
		print("FAIL: Target outside radius was blinded!")
		quit(1)
		return
	print("PASS: Target outside is unaffected")

	if not active_blinds.has(target_near.get_instance_id()) or not active_blinds.has(target_far.get_instance_id()):
		print("FAIL: Near or Far target missing from blinds!")
		quit(1)
		return

	var near_info: Dictionary = active_blinds[target_near.get_instance_id()]
	var far_info: Dictionary = active_blinds[target_far.get_instance_id()]

	print("Near target (2m): vision=%.2fm, duration=%.2fs" % [near_info.vision, near_info.remaining])
	print("Far target (8m): vision=%.2fm, duration=%.2fs" % [far_info.vision, far_info.remaining])

	if near_info.vision >= far_info.vision:
		print("FAIL: Near vision should be strictly smaller than far vision!")
		quit(1)
		return

	if near_info.remaining <= far_info.remaining:
		print("FAIL: Near duration should be strictly longer than far duration!")
		quit(1)
		return

	print("PASS: Monotonic linear scaling verified!")
	quit(0)
