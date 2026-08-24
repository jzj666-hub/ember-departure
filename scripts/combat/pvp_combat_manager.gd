class_name PvpCombatManager
extends RefCounted
## Shared combat formulas, stat tuning values, and roll mitigation logic for PVP duel modes.

signal stats_changed()
signal hit_resolved(hit_info: Dictionary)

const DEFAULT_WEAPON_DAMAGES := {
	"none": 15.0,
	"Abyss Blade": 40.0,
	"Apostle GreatSword": 65.0,
	"Bone Blade": 35.0,
	"Ax": 45.0,
	"War Ax": 55.0,
	"Two Handred Hammer": 68.0,
	"Basic Dagger": 25.0,
	"Black Steel Sword": 38.0,
}

var player_max_hp: float = 1000.0
var player_hp: float = 1000.0
var ai_max_hp: float = 1000.0
var ai_hp: float = 1000.0

var player_atk_mult: float = 1.0
var ai_atk_mult: float = 1.0

var player_def: float = 0.0
var ai_def: float = 0.0

var custom_weapon_damage: float = 40.0
var weapon_name: String = "Abyss Blade"


func reset_health() -> void:
	player_hp = player_max_hp
	ai_hp = ai_max_hp
	stats_changed.emit()


func get_weapon_base_damage(w_id: String) -> float:
	if w_id == "custom":
		return custom_weapon_damage
	for key in DEFAULT_WEAPON_DAMAGES:
		if w_id.contains(key) or key.contains(w_id):
			return float(DEFAULT_WEAPON_DAMAGES[key])
	return 35.0


## Calculates combat damage and roll mitigation.
## Invariant: If target_is_rolling is true, damage is strictly halved and immune_to_cc is true.
func calculate_damage(attacker_is_player: bool, base_damage: float, target_is_rolling: bool) -> Dictionary:
	var atk_mult: float = player_atk_mult if attacker_is_player else ai_atk_mult
	var def_val: float = ai_def if attacker_is_player else player_def

	var raw_damage: float = base_damage * atk_mult
	var mitigated_damage: float = raw_damage * (100.0 / (100.0 + maxf(def_val, 0.0)))

	var final_damage: float = mitigated_damage
	var is_roll_mitigated: bool = false
	var immune_to_cc: bool = false

	if target_is_rolling:
		final_damage = mitigated_damage * 0.5
		is_roll_mitigated = true
		immune_to_cc = true

	final_damage = maxf(1.0, snappedf(final_damage, 0.1))

	return {
		"raw_damage": raw_damage,
		"mitigated_damage": mitigated_damage,
		"final_damage": final_damage,
		"is_roll_mitigated": is_roll_mitigated,
		"immune_to_cc": immune_to_cc,
		"attacker_is_player": attacker_is_player,
	}


## Applies damage to player or AI and updates HP.
func apply_damage(attacker_is_player: bool, damage_info: Dictionary) -> float:
	var dmg: float = float(damage_info.get("final_damage", 0.0))
	if attacker_is_player:
		ai_hp = maxf(0.0, ai_hp - dmg)
	else:
		player_hp = maxf(0.0, player_hp - dmg)
	stats_changed.emit()
	hit_resolved.emit(damage_info)
	return ai_hp if attacker_is_player else player_hp
