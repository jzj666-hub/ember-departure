extends RefCounted
## Central registry of all available skills.
## Modularly extensible: instantiate and register new SkillBase subclasses here.

const SkillBaseScript = preload("res://scripts/skills/skill_base.gd")
const SkillTeleportScript = preload("res://scripts/skills/skill_teleport.gd")
const SkillStealthScript = preload("res://scripts/skills/skill_stealth.gd")
const SkillEntangleScript = preload("res://scripts/skills/skill_entangle.gd")
const SkillGrappleScript = preload("res://scripts/skills/skill_grapple.gd")
const SkillSandScript = preload("res://scripts/skills/skill_sand.gd")
const SkillWallScript = preload("res://scripts/skills/skill_wall.gd")
const SkillCloneScript = preload("res://scripts/skills/skill_clone.gd")
const SkillMistScript = preload("res://scripts/skills/skill_mist.gd")
const SkillSlamScript = preload("res://scripts/skills/skill_slam.gd")
const SkillJumpBuffScript = preload("res://scripts/skills/skill_jump_buff.gd")
const SkillCleanseScript = preload("res://scripts/skills/skill_cleanse.gd")

static var _skills: Dictionary = {}
static var _skill_order: Array[String] = []
static var _initialized: bool = false
static var _warmed_up: bool = false

static func init_registry() -> void:
	if _initialized:
		return
	_initialized = true
	_skills.clear()
	_skill_order.clear()

	register_skill(SkillTeleportScript.new())
	register_skill(SkillStealthScript.new())
	register_skill(SkillEntangleScript.new())
	register_skill(SkillGrappleScript.new())
	register_skill(SkillSandScript.new())
	register_skill(SkillWallScript.new())
	register_skill(SkillCloneScript.new())
	register_skill(SkillMistScript.new())
	register_skill(SkillSlamScript.new())
	register_skill(SkillJumpBuffScript.new())
	register_skill(SkillCleanseScript.new())

	# Preload all audio and assets across all skills
	for s in _skills.values():
		if s.has_method("preload_assets"):
			s.call("preload_assets")


## Dispels all active crowd controls, debuffs, roots, and knocks on the target actor.
static func dispel_all_debuffs(actor: CharacterBody3D) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	init_registry()
	for s in _skills.values():
		if s.has_method("dispel_actor"):
			s.call("dispel_actor", actor)

static func register_skill(skill: RefCounted) -> void:
	if skill == null:
		return
	var s_id: String = skill.call("get_id")
	_skills[s_id] = skill
	if not _skill_order.has(s_id):
		_skill_order.append(s_id)

static func get_skill(id: String) -> RefCounted:
	init_registry()
	return _skills.get(id, null)

static func get_all_skills() -> Array:
	init_registry()
	var list: Array = []
	for s_id in _skill_order:
		if _skills.has(s_id):
			list.append(_skills[s_id])
	return list

static func get_first_skill_id() -> String:
	init_registry()
	return _skill_order[0] if not _skill_order.is_empty() else ""

## Pre-compiles all skill shaders on GPU to eliminate runtime first-cast stutter.
static func warmup_all_shaders(parent_node: Node) -> void:
	init_registry()
	if _warmed_up or parent_node == null or not is_instance_valid(parent_node):
		return
	_warmed_up = true

	var warmup_root := Node3D.new()
	warmup_root.name = "SkillShaderWarmup"
	parent_node.add_child(warmup_root)

	var quad := QuadMesh.new()
	quad.size = Vector2(0.01, 0.01)

	var all_mats: Array = []
	for s in _skills.values():
		if s.has_method("get_warmup_materials"):
			var mats: Array = s.call("get_warmup_materials")
			for m in mats:
				if m is Material and not all_mats.has(m):
					all_mats.append(m)

	for mat in all_mats:
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = mat
		mi.position = Vector3(0.0, -100.0, 0.0)
		mi.extra_cull_margin = 16384.0
		warmup_root.add_child(mi)

	var tw := warmup_root.create_tween()
	tw.tween_interval(0.1)
	tw.tween_callback(warmup_root.queue_free)
