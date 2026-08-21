extends SceneTree
## Test suite for SkillSlam (Skill 9).

func _initialize() -> void:
	_run()

func _run() -> void:
	Engine.max_fps = 60
	print("--- Testing SkillSlam Registry & Config ---")
	var SkillRegistryScript = load("res://scripts/skills/skill_registry.gd")
	var slam_skill = SkillRegistryScript.get_skill("slam")
	if slam_skill == null:
		print("FAIL: Skill slam not registered")
		quit(1)
		return

	print("Skill Name: ", slam_skill.call("get_name"))
	print("Skill Title: ", slam_skill.call("get_title"))

	var root_node = Node3D.new()
	root.add_child(root_node)

	var caster = CharacterBody3D.new()
	caster.name = "Caster"
	caster.position = Vector3(0, 0, 0)
	root_node.add_child(caster)

	var enemy_in = CharacterBody3D.new()
	enemy_in.name = "EnemyIn"
	enemy_in.position = Vector3(3.0, 0, 0)
	root_node.add_child(enemy_in)

	var enemy_out = CharacterBody3D.new()
	enemy_out.name = "EnemyOut"
	enemy_out.position = Vector3(15.0, 0, 0)
	root_node.add_child(enemy_out)

	for i in 3:
		await physics_frame

	var res: Dictionary = slam_skill.call("cast", caster, Vector3.ZERO, root_node, false)
	print("Cast result: ", res)

	# Simulate the tween frames (leap, hang, slam)
	for i in 60:
		await physics_frame

	print("EnemyIn velocity after impact: ", enemy_in.velocity)
	print("EnemyOut velocity after impact: ", enemy_out.velocity)

	if enemy_in.velocity.length() < 0.1:
		print("FAIL: EnemyIn was not launched!")
		quit(1)
		return

	if enemy_out.velocity.length() > 0.01:
		print("FAIL: EnemyOut outside radius was launched!")
		quit(1)
		return

	print("PASS: EnemyIn was launched and EnemyOut remained unaffected!")
	quit(0)
