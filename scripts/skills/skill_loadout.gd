class_name SkillLoadout
extends Node
## One fighter's skill slot: role-filtered random draw, cooldown clock, cast entry points.
## Invariant: skill_id == "" until roll() succeeds. Pre-cast: skill_id != "" and cooldown_left <= 0.

signal skill_rolled(skill_id: String, display_name: String)
signal skill_cast_done(skill_id: String)
signal cooldown_changed(left: float, total: float)

const SkillRegistryScript = preload("res://scripts/skills/skill_registry.gd")

## Chase-role draw pools. A skill is excluded only where its effect is self-defeating for that role.
## Runner drops grapple: it drags the pursuer closer.
const RUNNER_POOL: Array[String] = [
	"teleport", "stealth", "clone", "mist", "wall", "sand", "jump_buff", "cleanse", "entangle", "slam",
]
## Chaser drops clone: a decoy has nobody to deceive.
const CHASER_POOL: Array[String] = [
	"teleport", "stealth", "grapple", "entangle", "slam", "sand", "wall", "mist", "jump_buff", "cleanse",
]

const COOLDOWNS := {
	"teleport": 8.0,
	"grapple": 10.0,
	"slam": 12.0,
	"cleanse": 14.0,
	"wall": 16.0,
	"sand": 16.0,
	"entangle": 16.0,
	"clone": 18.0,
	"jump_buff": 18.0,
	"mist": 20.0,
	"stealth": 22.0,
}
const DEFAULT_COOLDOWN := 15.0

var caster: CharacterBody3D = null
var vfx_parent: Node = null
var is_runner := true

var skill_id := ""
var cooldown_left := 0.0
var cooldown_total := DEFAULT_COOLDOWN

## Own RNG seeded off this instance: two clients launched together must not draw the same skill.
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = hash("%d_%d" % [Time.get_ticks_usec(), get_instance_id()])


func setup(body: CharacterBody3D, vfx_root: Node, runner_role: bool) -> void:
	caster = body
	vfx_parent = vfx_root
	is_runner = runner_role
	SkillRegistryScript.init_registry()


func pool() -> Array[String]:
	return RUNNER_POOL if is_runner else CHASER_POOL


## Candidate ids for the draw animation, in pool order.
func candidates() -> Array[String]:
	return pool()


func display_name_of(s_id: String) -> String:
	var skill := SkillRegistryScript.get_skill(s_id)
	return str(skill.call("get_name")) if skill != null else s_id


## roll(): draws one skill for this role. force_id overrides the draw (replication / debug).
## Post: skill_id set, cooldown cleared so the first cast is free.
func roll(force_id: String = "") -> String:
	var candidates_list := pool()
	if candidates_list.is_empty():
		return ""
	if not force_id.is_empty() and candidates_list.has(force_id):
		skill_id = force_id
	else:
		skill_id = candidates_list[_rng.randi() % candidates_list.size()]
	cooldown_total = float(COOLDOWNS.get(skill_id, DEFAULT_COOLDOWN))
	cooldown_left = 0.0
	skill_rolled.emit(skill_id, display_name_of(skill_id))
	cooldown_changed.emit(cooldown_left, cooldown_total)
	return skill_id


## draw_pair(): picks two distinct skills, one per role. Host-side helper so the two players
## never open with the same skill. Returns {"runner": id, "chaser": id}.
static func draw_pair(rng: RandomNumberGenerator = null) -> Dictionary:
	var r := rng
	if r == null:
		r = RandomNumberGenerator.new()
		r.seed = hash("%d" % Time.get_ticks_usec())
	var runner_id: String = RUNNER_POOL[r.randi() % RUNNER_POOL.size()]
	var chaser_choices: Array[String] = []
	for s_id in CHASER_POOL:
		if s_id != runner_id:
			chaser_choices.append(s_id)
	if chaser_choices.is_empty():
		chaser_choices = CHASER_POOL.duplicate()
	var chaser_id: String = chaser_choices[r.randi() % chaser_choices.size()]
	return {"runner": runner_id, "chaser": chaser_id}


func current_skill() -> RefCounted:
	return SkillRegistryScript.get_skill(skill_id) if not skill_id.is_empty() else null


## True when the drawn skill takes a ground target (implements cast_at).
func is_aimed() -> bool:
	return SkillAim.supports_aim(current_skill())


func can_cast() -> bool:
	return not skill_id.is_empty() and cooldown_left <= 0.0 \
		and caster != null and is_instance_valid(caster)


## cast_skill(): the single entry point for both the key binding and bots.
## Post: on success cooldown_left = cooldown_total. Returns false when on cooldown / unarmed.
func cast_skill() -> bool:
	if not can_cast():
		return false
	var skill := SkillRegistryScript.get_skill(skill_id)
	if skill == null:
		return false
	skill.call("cast", caster, _intent_dir(), vfx_parent, false)
	cooldown_left = cooldown_total
	cooldown_changed.emit(cooldown_left, cooldown_total)
	skill_cast_done.emit(skill_id)
	return true


## cast_skill_at(): aimed variant for skills implementing cast_at. Same cooldown contract as cast_skill.
func cast_skill_at(target_pos: Vector3) -> bool:
	if not can_cast():
		return false
	var skill := SkillRegistryScript.get_skill(skill_id)
	if skill == null:
		return false
	if not SkillAim.supports_aim(skill):
		return cast_skill()
	skill.call("cast_at", caster, target_pos, vfx_parent, false)
	cooldown_left = cooldown_total
	cooldown_changed.emit(cooldown_left, cooldown_total)
	skill_cast_done.emit(skill_id)
	return true


## cast_for_body(): runs a skill on an arbitrary body without touching this slot's cooldown.
## Used to replay a peer's cast locally so its VFX and area effects exist on this machine too.
static func cast_for_body(s_id: String, body: CharacterBody3D, vfx_root: Node) -> void:
	if s_id.is_empty() or body == null or not is_instance_valid(body):
		return
	SkillRegistryScript.init_registry()
	var skill := SkillRegistryScript.get_skill(s_id)
	if skill == null:
		return
	var dir := body.global_basis.z
	dir.y = 0.0
	# +Z is forward in this project, so the degenerate fallback is BACK, not FORWARD.
	skill.call("cast", body, dir.normalized() if dir.length_squared() > 0.001 else Vector3.BACK, vfx_root, false)


## cast_for_body_at(): aimed replay of a peer's cast. Falls back to the unaimed path when the
## skill has no cast_at, so a single RPC shape covers both kinds.
static func cast_for_body_at(s_id: String, body: CharacterBody3D, vfx_root: Node, target_pos: Vector3) -> void:
	if s_id.is_empty() or body == null or not is_instance_valid(body):
		return
	SkillRegistryScript.init_registry()
	var skill := SkillRegistryScript.get_skill(s_id)
	if skill == null:
		return
	if SkillAim.supports_aim(skill):
		skill.call("cast_at", body, target_pos, vfx_root, false)
	else:
		cast_for_body(s_id, body, vfx_root)


func _intent_dir() -> Vector3:
	var dir := Vector3(caster.velocity.x, 0.0, caster.velocity.z)
	if dir.length_squared() < 0.04:
		dir = caster.global_basis.z
		dir.y = 0.0
	return dir.normalized() if dir.length_squared() > 0.001 else Vector3.BACK


func _process(delta: float) -> void:
	if cooldown_left <= 0.0:
		return
	cooldown_left = maxf(0.0, cooldown_left - delta)
	cooldown_changed.emit(cooldown_left, cooldown_total)


## Short HUD line: "[1] 技能名 · 就绪 (按住瞄准) / 冷却 4.2s".
func hud_text(key_label: String = "1") -> String:
	if skill_id.is_empty():
		return "[%s] 未持有技能" % key_label
	var state := ""
	if cooldown_left > 0.0:
		state = "冷却 %.1fs" % cooldown_left
	elif is_aimed():
		state = "就绪 (按住选择落点)"
	else:
		state = "就绪"
	return "[%s] %s · %s" % [key_label, display_name_of(skill_id), state]
