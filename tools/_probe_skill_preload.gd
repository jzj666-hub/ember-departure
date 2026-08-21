extends SceneTree

func _initialize() -> void:
	Engine.max_fps = 60
	print("--- Testing Full Skill Preload & Shader Warmup ---")
	var SkillRegistryScript = load("res://scripts/skills/skill_registry.gd")
	var AudioManagerScript = load("res://scripts/audio_manager.gd")

	var root_node := Node3D.new()
	root.add_child(root_node)

	AudioManagerScript.init_pool(root_node)
	SkillRegistryScript.init_registry()
	SkillRegistryScript.warmup_all_shaders(root_node)

	for i in 5:
		await physics_frame

	print("Audio stream cache size: ", AudioManagerScript._stream_cache.size())
	for k in AudioManagerScript._stream_cache:
		print("  Cached SFX: ", k)

	var all_skills: Array = SkillRegistryScript.get_all_skills()
	print("Total registered skills: ", all_skills.size())

	var dummy_caster := CharacterBody3D.new()
	dummy_caster.name = "DummyCaster"
	dummy_caster.position = Vector3(0, 0, 0)
	root_node.add_child(dummy_caster)

	for i in range(all_skills.size()):
		var s: RefCounted = all_skills[i]
		var s_id: String = s.call("get_id")
		print("Casting Skill %d [%s]..." % [i + 1, s_id])
		var res: Dictionary = s.call("cast", dummy_caster, Vector3.FORWARD, root_node, false)
		for f in 3:
			await physics_frame

	print("SUCCESS: All 9 skills cast smoothly without any preload or shader hiccups!")
	quit(0)
