extends RefCounted
## Abstract base class for all playable and VFX sandbox skills.
## Defines uniform lifecycle for cast, configuration panel, snapshot recording, and replay.

func get_id() -> String:
	return "base"

func get_name() -> String:
	return "基础技能"

func get_title() -> String:
	return "技能配置"

## Returns default or current parameters dictionary.
func get_params() -> Dictionary:
	return {}

func set_param(_key: String, _value: Variant) -> void:
	pass

## Executes skill in player view (is_spectator = false) or global spectator view (is_spectator = true).
## Returns snapshot dictionary for record/replay.
func cast(_caster: CharacterBody3D, _intent_dir: Vector3, _vfx_parent: Node, _is_spectator: bool = false) -> Dictionary:
	return {}

## Executes replay from recorded snapshot in spectator mode.
func replay(_caster: CharacterBody3D, _record: Dictionary, _vfx_parent: Node) -> void:
	pass

## Duration to hold after skill execution in spectator replay before resetting.
func get_replay_hold_time(_record: Dictionary) -> float:
	return 1.3

## Preloads sound effects, textures, scenes, and shaders needed by this skill.
func preload_assets() -> void:
	pass

## Returns Array of Materials/ShaderMaterials to compile on GPU during warmup.
func get_warmup_materials() -> Array:
	return []

## Dispels/cancels any active crowd control or debuff applied by this skill on the actor.
func dispel_actor(_actor: CharacterBody3D) -> void:
	pass

## Drops this skill's cross-scene static state: active buff/debuff registries and dangling
## effect-node references. Asset caches (meshes, materials, loaded scenes) are deliberately kept.
## Pre: SCENE ENTRY ONLY. This discards bookkeeping, it does not undo effects on live actors —
## calling it mid-scene strands anything currently frozen/blinded/bound.
func reset_state() -> void:
	pass

## Builds the dedicated tuning UI widgets into the inspector container.
func build_config_panel(_container: VBoxContainer, _on_changed: Callable) -> void:
	pass
