@tool
class_name CharacterPipeline
extends RefCounted
## Turns a character export dropped into assets/characters/<id>/ into a ready
## rig: bone map detected, A-pose corrected, height normalised, wrapper scene built.
##
## Two steps, both idempotent, mirroring AnimPipeline:
##   1. configure_all() - write each character's .import (needs a reimport after)
##   2. build_scenes()  - generate assets/characters/<id>/<id>.tscn
##
## Every judgement about a rig - which BoneMap fits, whether the bind pose is an
## A-pose - is delegated to AnimPipeline rather than reimplemented, so the two
## pipelines cannot drift apart on what counts as a known rig.
##
## Driven from the CLI by tools/rebuild_assets.bat and automatically in the
## editor by addons/anim_pipeline/plugin.gd.

const AnimPipelineScript = preload("res://tools/anim_pipeline.gd")

const CHARACTERS_DIR := AnimPipelineScript.CHARACTERS_DIR
const MODEL_EXTS := AnimPipelineScript.EXTS

## Height a character is imported at when nothing says otherwise. The debug
## scene's 1 m grid is what makes a mis-scaled character obvious, so the number
## has to be realistic.
##
## Per-character overrides live in CONFIG_FILE; this is only the default.
const TARGET_HEIGHT_M := 1.75

## Optional per-character settings, sitting in the character's own folder.
##
##   [character]
##   height = 2.40            # what you want, in metres
##   measured_height = 1.128  # what the raw model measures, in its own units
##
## `height` is yours to set. `measured_height` is written once, the first time
## the character is configured, and is the only thing that ever has to be
## measured: root_scale is always height / measured_height, so changing the
## wanted height afterwards is pure arithmetic on a number already on disk.
##
## Rewritten wholesale by write_settings(), so hand-added comments do not
## survive - the template's own comments do.
const CONFIG_FILE := "character.cfg"
const CONFIG_SECTION := "character"

## Import heights closer than this are the same height; no reimport.
const HEIGHT_EPSILON_M := 0.0005

const WRAPPER_SCRIPT := "res://scripts/character.gd"


## One folder per character, the folder name being the id.
##
## The folder - not the file - is what keeps characters apart: AccuRig names
## every export "autorig_actor", so two characters dropped side by side in one
## folder would silently overwrite each other's model, textures and .json.
##
## Returns [{id, dir, model, extra_models, scene, anim_dir, own_library,
## config, target_height, measured_height}].
static func list_characters() -> Array:
	var out := []
	var root := DirAccess.open(CHARACTERS_DIR)
	if root == null:
		return out
	var ids := root.get_directories()
	ids.sort()
	for id in ids:
		var dir := CHARACTERS_DIR.path_join(id)
		var models := _find_models(dir)
		if models.is_empty():
			continue
		var settings := read_settings(dir)
		out.append({
			"id": id,
			"dir": dir,
			"model": models[0],
			"extra_models": models.size() - 1,
			"scene": dir.path_join("%s.tscn" % id),
			"anim_dir": dir.path_join(AnimPipelineScript.CHARACTER_ANIM_SUBDIR),
			"own_library": AnimPipelineScript.character_library_path(id),
			"config": dir.path_join(CONFIG_FILE),
			"has_config": settings.present,
			"target_height": settings.height,
			"measured_height": settings.measured,
		})
	return out


## What a character folder's CONFIG_FILE says, defaulted. `measured` is 0.0 when
## the character has never been measured, which is the only state that makes the
## pipeline measure anything.
##
## `present` separates "no file yet" from "file with the measurement blanked
## out". They look the same otherwise, and they mean opposite things: the first
## is a character configured before this file existed and must be left exactly as
## it imports, the second is someone asking for a re-measure.
static func read_settings(dir_path: String) -> Dictionary:
	var out := {"height": TARGET_HEIGHT_M, "measured": 0.0, "present": false}
	var cfg := ConfigFile.new()
	if cfg.load(dir_path.path_join(CONFIG_FILE)) != OK:
		return out
	out.present = true
	var height := float(cfg.get_value(CONFIG_SECTION, "height", TARGET_HEIGHT_M))
	# A zero or negative height would divide the character down to nothing; the
	# default is a better answer than refusing to import.
	out.height = height if height > 0.0 else TARGET_HEIGHT_M
	out.measured = maxf(0.0, float(cfg.get_value(CONFIG_SECTION, "measured_height", 0.0)))
	return out


## Writes CONFIG_FILE from a fixed template rather than through ConfigFile.save().
##
## ConfigFile cannot keep comments, and the comments are the reason this file
## exists in a form a person edits: measured_height is the one number in the
## pipeline that cannot be recovered once the model has been retargeted, so it
## has to explain itself where it lives. Returns false if the write failed.
static func write_settings(character: Dictionary, height: float, measured: float) -> bool:
	var text := """; Per-character import settings. Delete this file to fall back to the defaults.

[character]

; Standing height in metres. Change it and the next pipeline pass rescales the
; model to match - nothing is re-measured, so this is safe to change at will.
height = %.4f

; What the raw model measured, in its own units, before any scaling. Written
; once, when the character was first configured, and used only as the divisor
; for the line above. Full precision on purpose - some exporters measure a
; character in hundredths of a unit.
;
; Worth checking by hand for a model authored in a T-pose: a human is about as
; wide as they are tall, so the automatic measurement can pick up arm span
; instead of height. If the character imports short, this number is too big.
measured_height = %s
""" % [height, String.num(measured, 12)]
	var file := FileAccess.open(character.config, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true


## Model files at the top level of a character folder. Not recursive: the
## animations/ subfolder holds clips, not the character, and textures/ holds
## neither.
static func _find_models(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if MODEL_EXTS.has(f.get_extension().to_lower()):
			out.append(dir_path.path_join(f))
	out.sort()
	return out


static func find(character_id: String) -> Dictionary:
	for character in list_characters():
		if character.id == character_id:
			return character
	return {}


# --- step 1: import configuration ----------------------------------------

## Writes bone maps, A-pose fixes and root scales into .import files. Returns
## the model paths that changed and therefore need reimporting.
static func configure_all(log_fn: Callable = Callable()) -> PackedStringArray:
	var changed := PackedStringArray()
	for character in list_characters():
		var result := configure(character)
		if not log_fn.is_null():
			log_fn.call("  %-24s %s" % [character.id, result.message])
		if result.changed:
			changed.append(character.model)
	return changed


## Returns {changed: bool, message: String}.
static func configure(character: Dictionary) -> Dictionary:
	var res_path: String = character.model
	var import_path := res_path + ".import"
	var cfg := ConfigFile.new()
	if cfg.load(import_path) != OK:
		return {"changed": false, "message": "no .import yet (reimport once first)"}

	# Ahead of every early return below: an .import written before the silhouette
	# settings existed still needs them, and by then the character reports as
	# configured. Safe here precisely because it re-measures nothing.
	if AnimPipelineScript.refresh_silhouette_settings(cfg):
		if cfg.save(import_path) != OK:
			return {"changed": false, "message": "ERROR could not write .import"}
		return {"changed": true, "message": "silhouette settings updated -> reimport"}

	var subs: Dictionary = cfg.get_value("params", "_subresources", {})
	var nodes: Dictionary = subs.get("nodes", {})

	var probed := AnimPipelineScript.probe(res_path)
	var skeleton_name: String = probed.skeleton
	if skeleton_name == "":
		return {"changed": false, "message": "no Skeleton3D - not a character?"}

	# Key on the node's path, not its name: a skeleton nested under a parent
	# (Rig/Skeleton3D, as glTF exports usually are) is silently ignored otherwise.
	var key := "PATH:%s" % probed.path
	var skel_cfg: Dictionary = nodes.get(key, {})

	# A retargeted skeleton gets renamed by the importer, so either of these means
	# the rig side is done. The rig is decided once and never revisited; the
	# height is a number in CONFIG_FILE that may change at any time, so it gets
	# its own pass that measures nothing.
	var retargeted := skeleton_name == AnimPipelineScript.RETARGETED_SKELETON
	if retargeted or skel_cfg.has("retarget/bone_map"):
		# Blanking measured_height in an existing CONFIG_FILE is how you ask for a
		# fresh measurement. Doable on the spot while the model is still raw;
		# once retargeted it has to go back through the importer first.
		if character.has_config and character.measured_height <= 0.0:
			if retargeted:
				return _request_remeasure(cfg, import_path, subs, nodes, key)
			_measure(character, probed, AnimPipelineScript.detect_bone_map(probed.bones), cfg)
		return _apply_height(character, cfg, import_path,
			"already retargeted" if retargeted else "already configured")

	var match_result := AnimPipelineScript.detect_bone_map(probed.bones)
	if String(match_result.path) == "":
		return {"changed": false, "message": "unknown rig - see 'rig report' below"}
	# The rig may carry a namespace the checked-in map was not written for; this
	# materialises the matching variant when so, and is a no-op when not.
	var map_path := AnimPipelineScript.resolve_bone_map(match_result)
	if map_path == "":
		return {"changed": false,
			"message": "ERROR could not generate a bone map for the '%s' namespace"
				% match_result.prefix}

	# Clear bone maps parked on a stale node path; they do nothing but mislead.
	for other_key in nodes.keys():
		if other_key != key and (nodes[other_key] as Dictionary).has("retarget/bone_map"):
			(nodes[other_key] as Dictionary).erase("retarget/bone_map")

	skel_cfg["retarget/bone_map"] = load(map_path)

	# An A-pose bind pose plus a T-pose clip puts the arms at the wrong angle.
	# Godot can repose the rest to match the profile, but only when asked, and
	# doing it to an already-T-posed rig would perturb it for nothing.
	var droop := AnimPipelineScript.arm_droop_degrees(probed, match_result)
	var needs_fix := droop > AnimPipelineScript.A_POSE_THRESHOLD_DEG
	if needs_fix:
		skel_cfg["retarget/rest_fixer/fix_silhouette/enable"] = true
		skel_cfg["retarget/rest_fixer/fix_silhouette/threshold"] = \
			AnimPipelineScript.SILHOUETTE_THRESHOLD_DEG
		skel_cfg["retarget/rest_fixer/fix_silhouette/filter"] = \
			AnimPipelineScript.silhouette_filter()

	nodes[key] = skel_cfg
	subs["nodes"] = nodes
	cfg.set_value("params", "_subresources", subs)

	# This is the last moment the height can be read off the file: the reimport
	# that follows snaps the rest pose onto the humanoid profile without touching
	# the vertices, after which the skeleton and the mesh no longer describe the
	# same shape and nothing says which mesh axis is up. See AnimPipeline.body_height().
	var measured := _measure(character, probed, match_result, cfg)
	var scale := 0.0
	if measured > 0.0:
		scale = character.target_height / measured
		cfg.set_value("params", "nodes/apply_root_scale", true)
		cfg.set_value("params", "nodes/root_scale", scale)

	if cfg.save(import_path) != OK:
		return {"changed": false, "message": "ERROR could not write .import"}

	var note := "-> %s (%d bones matched)" % [map_path.get_file(), match_result.score]
	if scale > 0.0:
		note += ", root_scale %.4f -> %.2f m" % [scale, character.target_height]
		note += _axis_warning(probed)
	if needs_fix:
		note += ", A-pose %.0f° -> fix_silhouette on" % droop
	if character.get("extra_models", 0) > 0:
		note += " (WARNING %d other model file(s) in this folder are ignored)" % character.extra_models
	return {"changed": true, "message": note}


## Hands the importer back a raw rig so it can be measured again.
##
## A retargeted model cannot be measured: the rest pose has been snapped to the
## humanoid profile while the vertices have not, so nothing is left to say which
## mesh axis is up (AnimPipeline.body_height()). Dropping the bone map is the
## only way back to a measurable model, and it costs one extra reimport - the
## pass after this one measures and puts the map straight back. Two pipeline
## runs, or one in the editor, where the plugin loops until nothing changes.
static func _request_remeasure(cfg: ConfigFile, import_path: String,
		subs: Dictionary, nodes: Dictionary, key: String) -> Dictionary:
	nodes.erase(key)
	subs["nodes"] = nodes
	cfg.set_value("params", "_subresources", subs)
	if cfg.save(import_path) != OK:
		return {"changed": false, "message": "ERROR could not write .import"}
	return {"changed": true,
		"message": "measured_height blank -> re-measuring (run the pipeline twice)"}


## Brings root_scale in line with CONFIG_FILE's height on a character whose rig
## is already settled. Measures nothing: root_scale is only ever
## height / measured_height, and measured_height is on disk.
##
## That split is what makes a per-character height safe. The old single-pass
## guard existed because apply_root_scale bakes into the vertices, so a second
## measurement of a configured model reads ~1.0 and writing it back would undo
## the scale. Storing the measurement instead of retaking it removes the hazard
## rather than guarding it, and lets the height change whenever someone edits it.
static func _apply_height(character: Dictionary, cfg: ConfigFile, import_path: String,
		base_message: String) -> Dictionary:
	var applied := float(cfg.get_value("params", "nodes/root_scale", 0.0))
	if not bool(cfg.get_value("params", "nodes/apply_root_scale", false)):
		applied = 0.0
	var measured: float = character.measured_height

	if measured <= 0.0:
		# Configured before CONFIG_FILE existed. The pipeline aimed every
		# character at TARGET_HEIGHT_M back then, so that and the scale it wrote
		# recover the measurement exactly - including a measurement that picked
		# the wrong axis. Deliberate: adopting the number keeps the character
		# importing at exactly the size it already does, and makes the suspect
		# value visible in a file instead of silently rescaling the asset.
		if applied <= 0.0:
			return {"changed": false, "message": base_message}
		measured = TARGET_HEIGHT_M / applied
		_remember(character, measured)

	var wanted_scale: float = character.target_height / measured
	if applied > 0.0 and absf(measured * applied - character.target_height) <= HEIGHT_EPSILON_M:
		return {"changed": false, "message": "%s, %.2f m" % [base_message, character.target_height]}

	cfg.set_value("params", "nodes/apply_root_scale", true)
	cfg.set_value("params", "nodes/root_scale", wanted_scale)
	if cfg.save(import_path) != OK:
		return {"changed": false, "message": "ERROR could not write .import"}
	return {"changed": true, "message": "height %.2f m -> %.2f m (root_scale %.4f) -> reimport" % [
		measured * applied, character.target_height, wanted_scale]}


## The raw model's height in its own units, remembered in CONFIG_FILE so it never
## has to be taken twice. 0.0 when there is nothing to measure.
##
## Divides out any root_scale already in force, because apply_root_scale bakes
## into the vertices: probing a model that carries one measures the scaled body.
## Only reachable before retargeting, so the mesh and the skeleton still agree.
static func _measure(character: Dictionary, probed: Dictionary,
		match_result: Dictionary, cfg: ConfigFile) -> float:
	if character.measured_height > 0.0:
		return character.measured_height
	var height := AnimPipelineScript.body_height(probed, match_result)
	if height < 0.0001:
		return 0.0
	var applied := float(cfg.get_value("params", "nodes/root_scale", 1.0))
	if not bool(cfg.get_value("params", "nodes/apply_root_scale", false)) or applied <= 0.0:
		applied = 1.0
	var measured := height / applied
	_remember(character, measured)
	return measured


## Persists a measurement and keeps the caller's character dictionary in step, so
## a single pass never measures the same model twice.
static func _remember(character: Dictionary, measured: float) -> void:
	character.measured_height = measured
	if not write_settings(character, character.target_height, measured):
		push_warning("[Asset Pipeline] %s: could not write %s" % [
			character.id, character.config])


## The factor that brings a raw measurement to a wanted height.
static func root_scale_for(target_height: float, measured_height: float) -> float:
	if measured_height < 0.0001:
		return 0.0
	return target_height / measured_height


## The root_scale currently written in a model's .import, or 0.0 if none.
static func current_root_scale(res_path: String) -> float:
	var cfg := ConfigFile.new()
	if cfg.load(res_path + ".import") != OK:
		return 0.0
	return float(cfg.get_value("params", "nodes/root_scale", 0.0))


# --- step 2: wrapper scenes -----------------------------------------------

## Returns {ok: bool, scenes: PackedStringArray, problems: PackedStringArray}.
static func build_scenes(log_fn: Callable = Callable()) -> Dictionary:
	var built := PackedStringArray()
	var problems := PackedStringArray()
	for character in list_characters():
		var problem := build_scene(character)
		if problem != "":
			problems.append(problem)
			continue
		built.append(character.scene)
		if not log_fn.is_null():
			log_fn.call("  %-24s -> %s" % [character.id, character.scene])
	return {"ok": problems.is_empty(), "scenes": built, "problems": problems}


## Writes assets/characters/<id>/<id>.tscn: the imported model wrapped in a
## Node3D carrying the animation libraries.
##
## The wrapper is the whole point - reimporting the model regenerates everything
## below it, and cannot clobber a script, collision shape or state machine added
## to the wrapper itself. Returns "" on success, or a problem description.
static func build_scene(character: Dictionary) -> String:
	var packed_model := load(character.model) as PackedScene
	if packed_model == null:
		return "%s: model will not load (%s)" % [character.id, character.model]

	var root := Node3D.new()
	root.name = String(character.id).to_pascal_case()
	var model := packed_model.instantiate()
	model.name = "Model"
	root.add_child(model)
	# Only the instance root is owned by the wrapper; its descendants keep the
	# owner instantiate() gave them, which is what preserves it as an instance.
	model.owner = root

	root.set_script(load(WRAPPER_SCRIPT))
	root.set("character_id", character.id)
	# Collision capsules, camera heights and reach are all metres, and none of
	# them scale themselves when a character is taller. Hand the number over.
	root.set("body_height", character.target_height)
	if ResourceLoader.exists(AnimPipelineScript.SHARED_LIBRARY_PATH):
		root.set("shared_animations", load(AnimPipelineScript.SHARED_LIBRARY_PATH))
	# Reference the character's own library only while its animations/ folder
	# actually holds sources. A leftover .tres from a since-emptied folder would
	# otherwise keep offering clips nothing can regenerate.
	if not AnimPipelineScript.list_sources(character.anim_dir).is_empty() \
			and ResourceLoader.exists(character.own_library):
		root.set("own_animations", load(character.own_library))

	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		root.free()
		return "%s: pack failed" % character.id
	var err := ResourceSaver.save(packed, character.scene)
	root.free()
	if err != OK:
		return "%s: could not write %s (%d)" % [character.id, character.scene, err]
	return ""


# --- diagnostics ----------------------------------------------------------

## Human-readable status for every character, so an unrecognised rig explains
## itself instead of failing silently. Same shape as AnimPipeline.rig_report().
static func rig_report() -> PackedStringArray:
	var out := PackedStringArray()
	for character in list_characters():
		var probed := AnimPipelineScript.probe(character.model)
		var bones: PackedStringArray = probed.bones
		var model_file: String = String(character.model).get_file()
		if bones.is_empty():
			out.append("%s: no skeleton in %s" % [character.id, model_file])
			continue

		# Already-retargeted models carry profile bone names, which match no
		# source map; reporting them as "unknown" would be actively misleading.
		if String(probed.skeleton) == AnimPipelineScript.RETARGETED_SKELETON:
			out.append("%s: retargeted, %d bones, imports at %.2f m -> ready" % [
				character.id, bones.size(), _imported_height(character)])
			continue

		var match_result := AnimPipelineScript.detect_bone_map(bones)
		var map_path: String = match_result.path
		if map_path == "":
			var sample := PackedStringArray()
			for i in mini(8, bones.size()):
				sample.append(bones[i])
			out.append(("%s: UNKNOWN rig in %s, %d bones (best map only matched %d, " +
				"need %d).\n    bones: %s ...\n" +
				"    -> add a mapping to tools/gen_bone_maps.gd, run it, then list " +
				"the new .tres in AnimPipeline.BONE_MAPS") % [
				character.id, model_file, bones.size(), match_result.score,
				AnimPipelineScript.MIN_MATCHED_BONES, ", ".join(sample)])
			continue

		var line := "%s: %s, %d bones, %d matched" % [
			character.id, map_path.get_file(), bones.size(), match_result.score]
		var variant := AnimPipelineScript.namespace_variant(match_result)
		if variant != "":
			line += " under the '%s' namespace" % variant
		var droop := AnimPipelineScript.arm_droop_degrees(probed, match_result)
		line += ", T-pose" if droop <= AnimPipelineScript.A_POSE_THRESHOLD_DEG \
			else ", A-pose %.0f°" % droop
		out.append(line)
	return out


## Height the model actually imports at, for spotting a bad measurement without
## opening the debug scene.
##
## Derived, not measured: the mesh keeps its vertex data across reimports, so the
## imported height is exactly the stored measurement times the scale in force.
## Re-measuring here would be worse than useless - a retargeted model's mesh and
## skeleton disagree about which way is up (see AnimPipeline.body_height()).
static func _imported_height(character: Dictionary) -> float:
	var measured: float = character.measured_height
	if measured <= 0.0:
		return 0.0
	return measured * current_root_scale(character.model)


## Flags a measurement that could have taken either of the two longest mesh
## extents, appended to the line reporting it.
##
## This is the one failure the pipeline cannot rule out for itself: a T-posed
## human is about as wide as they are tall. Said once, where the number is being
## written - the report cannot repeat it usefully, because a correct measurement
## on a T-posed model looks exactly the same afterwards. Measured on the
## characters here, an A-pose leaves a 17-60% margin, so the line falls at 10%.
static func _axis_warning(probed: Dictionary) -> String:
	var size: Vector3 = (probed.aabb as AABB).size
	var sorted := [size.x, size.y, size.z]
	sorted.sort()
	var longest: float = sorted[2]
	if longest < 0.0001 or sorted[1] / longest < 0.9:
		return ""
	return " (WARNING as wide as it is tall, %.3f vs %.3f - if it imports short, " % [
		longest, sorted[1]] + "measured_height in %s took the width)" % CONFIG_FILE
