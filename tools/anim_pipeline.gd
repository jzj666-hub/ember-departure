@tool
class_name AnimPipeline
extends RefCounted
## Shared logic for turning downloaded animation files into clips on a rig.
##
## Two steps, both idempotent:
##   1. configure_all()      - detect each source file's rig and write the matching
##                             BoneMap into its .import file (needs a reimport after)
##   2. build_all_libraries()- collect the clips into AnimationLibrary resources
##
## Retargeting renames every skeleton to GeneralSkeleton and every track to a
## SkeletonProfileHumanoid bone name, so a built library is not tied to the
## character it was built alongside: one shared library feeds every character.
## Clips that belong to a single character live in that character's own folder
## and get their own library on top of the shared one.
##
## Driven from the CLI by tools/rebuild_assets.bat and automatically in the
## editor by addons/anim_pipeline/plugin.gd.

## Animations every character shares.
const SHARED_SOURCE_DIR := "res://assets/animations/source"
const SHARED_LIBRARY_PATH := "res://assets/animations/shared_animations.tres"

## One folder per character. Also the canonical home of the asset layout both
## pipelines work against: tools/character_pipeline.gd reads it from here rather
## than declaring its own copy, and depends on this file rather than the reverse.
## A character folder may carry an animations/ subfolder of clips only it uses.
const CHARACTERS_DIR := "res://assets/characters"
const CHARACTER_ANIM_SUBDIR := "animations"

const EXTS := ["fbx", "glb", "gltf", "dae"]

## Every known rig mapping. Detection scores each one against the file's actual
## bone names rather than matching a prefix, so rigs whose bones carry no
## recognisable prefix (Ready Player Me, UE mannequin, plain glTF exports) still
## resolve. Adding a rig means dropping a BoneMap here - nothing else.
const BONE_MAPS := [
	"res://assets/retarget/mixamo_to_humanoid.tres",
	"res://assets/retarget/cc_base_to_humanoid.tres",
	"res://assets/retarget/rigify_def_to_humanoid.tres",
	"res://assets/retarget/ue_mannequin_to_humanoid.tres",
]

## Namespaced variants of the maps above, generated on demand.
##
## Mixamo hands out a numbered namespace - "mixamorig9:Hips" instead of
## "mixamorig:Hips" - whenever the uploaded model already carried a rig, and DCC
## round-trips add namespaces of their own. It is the same rig under a name no
## checked-in .tres can predict, so detection rewrites the prefix and writes the
## result here rather than anyone hand-adding one file per number.
##
## These have to be real files: a .import can only reference a BoneMap by path.
## Generated, so do not hand-edit - change the map in assets/retarget/ instead
## and the variant is rebuilt from it.
const GENERATED_MAP_DIR := "res://assets/retarget/generated"

## A rig must match at least this many profile bones, and must have a hip bone,
## before we trust the map. Guards against a half-matching skeleton being
## retargeted into nonsense.
const MIN_MATCHED_BONES := 12

## Arm droop above this angle means the bind pose is an A-pose and needs
## reposing to the profile's T-pose before T-pose clips will look right.
const A_POSE_THRESHOLD_DEG := 12.0

## Bones the silhouette fix must NOT touch.
##
## "retarget/rest_fixer/fix_silhouette/filter" is an exclusion list: the bones
## named here keep their own rest, everything else gets snapped onto the humanoid
## profile's reference pose. Leaving it empty - the importer's default - is what
## made the toes ride up.
##
## The profile points the foot dead flat forward at the toe. No real rig does:
## measured foot->toe droop is 25 deg on our AccuRig characters, 31 on Mixamo, 31
## on the Godot library, 56 on Warrok. Snapping only the character moved its toe
## pivot up to ankle height, about 6 cm above where the toe geometry is bound, so
## every toe rotation swung the front of the foot through the wrong arc. Bind
## pose hides it completely - skinning is the identity there - which is why it
## only shows up once something animates.
##
## LeftFoot matters as much as LeftToes: the bone the fixer rotates is the FOOT,
## aiming it at its child. Excluding the toe alone changes nothing.
##
## The arms are the opposite case, and the reason the fix is on at all: Mixamo,
## Rigify and the Godot library all rest the arm chain flat along X, exactly
## where the profile puts it, so aligning an A-pose character to the profile
## aligns it to the clips. A-pose versus T-pose is an arm difference to begin
## with. So: everything keeps getting fixed except the feet.
const SILHOUETTE_EXCLUDED := ["LeftFoot", "RightFoot", "LeftToes", "RightToes"]

## Angle below which the silhouette fix leaves a bone alone.
##
## The importer's own default is 15 deg, which is far too coarse for characters
## that have to share one clip library. Measured across three AccuRig characters
## before this was set: every deviation at or above 15 deg had been snapped to
## exactly 0 (the A-pose arm, 41.6 deg), and everything below it survived
## untouched - LeftShoulder sat at 14.1 deg on one character and 9.8 on another,
## and the spine chain carried 0 to 10.3 deg of residual curvature that nothing
## corrected.
##
## That residue is not cosmetic. An animation track overwrites a bone's rest
## ROTATION but never the offset its child sits at, so leftover curvature is
## geometry every clip inherits. The same clip therefore read as hunched on one
## character and arched on another, and differed from clip to clip because each
## one distributes the bend across Spine/Chest/UpperChest differently.
##
## At 1.0 the per-segment spread between characters collapses from 9-10 deg to
## under 2.3. The trade is deliberate: characters lose their authored posture and
## all stand on the profile's skeleton, which is the only thing that makes a
## shared clip library meaningful. The feet stay exempt through
## SILHOUETTE_EXCLUDED, and that exemption is what keeps a low threshold safe.
const SILHOUETTE_THRESHOLD_DEG := 1.0

## Bones already renamed by a previous run: the file is configured, leave it be.
const RETARGETED_SKELETON := "GeneralSkeleton"

## probe() instantiates the scene, which is too slow to repeat on every editor
## filesystem change. Keyed by path + .import mtime so a reimport invalidates it.
static var _probe_cache := {}


## Animation files in one directory.
static func list_sources(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		# Godot exposes imported binaries without the .import suffix; skip strays.
		if EXTS.has(f.get_extension().to_lower()):
			out.append(dir_path.path_join(f))
	out.sort()
	return out


## Every directory animations are read from: the shared folder first, then each
## character's own animations/ subfolder. Configuration and rig detection run
## over all of them - only library building cares which directory a clip came from.
static func source_dirs() -> PackedStringArray:
	var dirs := PackedStringArray([SHARED_SOURCE_DIR])
	var root := DirAccess.open(CHARACTERS_DIR)
	if root == null:
		return dirs
	var ids := root.get_directories()
	ids.sort()
	for id in ids:
		var own := CHARACTERS_DIR.path_join(id).path_join(CHARACTER_ANIM_SUBDIR)
		if DirAccess.dir_exists_absolute(own):
			dirs.append(own)
	return dirs


static func list_all_sources() -> PackedStringArray:
	var out := PackedStringArray()
	for dir_path in source_dirs():
		out.append_array(list_sources(dir_path))
	return out


# --- step 1: import configuration ----------------------------------------

## Writes bone maps into .import files. Returns the paths that changed and
## therefore need reimporting.
static func configure_all(log_fn: Callable = Callable()) -> PackedStringArray:
	var changed := PackedStringArray()
	for path in list_all_sources():
		var result := configure(path)
		if not log_fn.is_null():
			log_fn.call("  %-38s %s" % [path.get_file(), result.message])
		if result.changed:
			changed.append(path)
	return changed


## Returns {changed: bool, message: String}.
static func configure(res_path: String) -> Dictionary:
	var import_path := res_path + ".import"
	var cfg := ConfigFile.new()
	if cfg.load(import_path) != OK:
		return {"changed": false, "message": "no .import yet (reimport once first)"}

	# Ahead of every early return below: an .import written before the silhouette
	# settings existed still needs them, and by then the file reports as configured.
	if refresh_silhouette_settings(cfg):
		if cfg.save(import_path) != OK:
			return {"changed": false, "message": "ERROR could not write .import"}
		return {"changed": true, "message": "silhouette settings updated -> reimport"}

	var subs: Dictionary = cfg.get_value("params", "_subresources", {})
	var nodes: Dictionary = subs.get("nodes", {})

	var probed := probe(res_path)
	var skeleton_name: String = probed.skeleton
	if skeleton_name == "":
		return {"changed": false, "message": "no Skeleton3D - not an animation rig?"}
	# A retargeted skeleton gets renamed by the importer. That is the steady
	# state, and also what stops this from rewriting the same file forever.
	if skeleton_name == RETARGETED_SKELETON:
		return {"changed": false, "message": "already retargeted"}

	# Key on the node's path, not its name: a skeleton nested under a parent
	# (Rig/Skeleton3D, as glTF exports usually are) is silently ignored otherwise.
	var key := "PATH:%s" % probed.path
	var skel_cfg: Dictionary = nodes.get(key, {})
	if skel_cfg.has("retarget/bone_map"):
		return {"changed": false, "message": "already configured"}

	var match_result := detect_bone_map(probed.bones)
	if String(match_result.path) == "":
		return {"changed": false, "message": "unknown rig - see 'rig report' below"}
	# The rig may carry a namespace the checked-in map was not written for; this
	# materialises the matching variant when so, and is a no-op when not.
	var map_path := resolve_bone_map(match_result)
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
	var droop := arm_droop_degrees(probed, match_result)
	var needs_fix := droop > A_POSE_THRESHOLD_DEG
	if needs_fix:
		skel_cfg["retarget/rest_fixer/fix_silhouette/enable"] = true
		skel_cfg["retarget/rest_fixer/fix_silhouette/threshold"] = SILHOUETTE_THRESHOLD_DEG
		skel_cfg["retarget/rest_fixer/fix_silhouette/filter"] = silhouette_filter()

	nodes[key] = skel_cfg
	subs["nodes"] = nodes
	cfg.set_value("params", "_subresources", subs)
	# Mixamo takes are short; trimming can eat meaningful lead-in frames.
	cfg.set_value("params", "animation/trimming", false)

	if cfg.save(import_path) != OK:
		return {"changed": false, "message": "ERROR could not write .import"}

	var note := "-> %s (%d bones matched)" % [map_path.get_file(), match_result.score]
	if needs_fix:
		note += ", A-pose %.0f° -> fix_silhouette on" % droop
	return {"changed": true, "message": note}


## Value for "retarget/rest_fixer/fix_silhouette/filter": the bones listed in
## SILHOUETTE_EXCLUDED, in that order. Trivial, but it keeps the exclusion list
## readable as a plain constant and the StringName typing in one place.
static func silhouette_filter() -> Array[StringName]:
	var out: Array[StringName] = []
	for bone in SILHOUETTE_EXCLUDED:
		out.append(StringName(bone))
	return out


## Brings an .import written before SILHOUETTE_EXCLUDED / SILHOUETTE_THRESHOLD_DEG
## existed up to date, and keeps one in step whenever either changes. Returns
## true when cfg changed.
##
## Reads nothing but the file, which is what makes it safe to run ahead of every
## other check: a character that is already configured must never be re-probed
## or re-measured (see the guard in CharacterPipeline.configure() for what that
## would do to root_scale), and this touches neither.
static func refresh_silhouette_settings(cfg: ConfigFile) -> bool:
	var subs: Dictionary = cfg.get_value("params", "_subresources", {})
	var nodes: Dictionary = subs.get("nodes", {})
	var wanted := silhouette_filter()
	var touched := false
	for key in nodes.keys():
		var skel_cfg: Dictionary = nodes[key]
		# Only meaningful where the fix is actually on; writing settings next to a
		# disabled fix would just be noise in the file.
		if not bool(skel_cfg.get("retarget/rest_fixer/fix_silhouette/enable", false)):
			continue
		var changed := false

		var have: Variant = skel_cfg.get("retarget/rest_fixer/fix_silhouette/filter", [])
		if _as_strings(have) != _as_strings(wanted):
			skel_cfg["retarget/rest_fixer/fix_silhouette/filter"] = wanted
			changed = true

		# Defaulting to the importer's own 15 deg is what makes this self-healing:
		# an .import written before the constant existed carries no threshold key
		# at all, and 15 is the value it is silently running with.
		var threshold := float(skel_cfg.get(
			"retarget/rest_fixer/fix_silhouette/threshold", 15.0))
		if not is_equal_approx(threshold, SILHOUETTE_THRESHOLD_DEG):
			skel_cfg["retarget/rest_fixer/fix_silhouette/threshold"] = SILHOUETTE_THRESHOLD_DEG
			changed = true

		if not changed:
			continue
		nodes[key] = skel_cfg
		touched = true
	if touched:
		subs["nodes"] = nodes
		cfg.set_value("params", "_subresources", subs)
	return touched


## Compares filter values without depending on how ConfigFile round-trips a
## typed array of StringName.
static func _as_strings(value: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if value is Array:
		for v in value:
			out.append(String(v))
	return out


## One scene load per file, returning everything the rest of the pipeline needs:
## the skeleton node's name and its path from the scene root, its bone names,
## each bone's global rest position, and the union of every mesh's bounds.
##
## The path matters: the .import subresource key is "PATH:<node path>", not the
## node's name. A skeleton nested under a parent node (common in glTF, where the
## armature sits under a Rig node) is silently ignored if keyed by name alone.
static func probe(res_path: String) -> Dictionary:
	var import_path := res_path + ".import"
	var stamp := FileAccess.get_modified_time(ProjectSettings.globalize_path(import_path))
	var cache_key := "%s|%d" % [res_path, stamp]
	if _probe_cache.has(cache_key):
		return _probe_cache[cache_key]

	var result := {
		"skeleton": "", "path": "", "bones": PackedStringArray(),
		"rest": {}, "aabb": AABB(),
	}
	var packed := ResourceLoader.load(res_path, "PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		return result
	var root := packed.instantiate()
	var skel := first_of_class(root, "Skeleton3D") as Skeleton3D
	if skel != null:
		result.skeleton = String(skel.name)
		result.path = String(root.get_path_to(skel))
		var bones := PackedStringArray()
		var rest := {}
		for i in skel.get_bone_count():
			bones.append(skel.get_bone_name(i))
			rest[String(skel.get_bone_name(i))] = _global_rest(skel, i).origin
		result.bones = bones
		result.rest = rest
	result.aabb = _mesh_bounds(root)
	root.free()

	_probe_cache[cache_key] = result
	return result


## Union of every mesh's bounds, each brought into the scene root's space.
##
## For a skinned mesh the raw vertex array already holds bind-pose positions, so
## this is the model's rest bounding box. Taking the union rather than the first
## mesh matters for characters split into separate body / hair / clothing meshes.
static func _mesh_bounds(root: Node) -> AABB:
	var bounds := AABB()
	var found := false
	for node in _walk(root):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var box := _transform_from(root, mi) * mi.mesh.get_aabb()
		bounds = box if not found else bounds.merge(box)
		found = true
	return bounds


## Composite transform from `root` down to `node`. The scene is not inside the
## tree at this point, so global_transform is not available.
static func _transform_from(root: Node, node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


static func _walk(node: Node, out: Array = []) -> Array:
	out.append(node)
	for c in node.get_children():
		_walk(c, out)
	return out


static func _global_rest(skel: Skeleton3D, idx: int) -> Transform3D:
	var t := Transform3D.IDENTITY
	var i := idx
	while i != -1:
		t = skel.get_bone_rest(i) * t
		i = skel.get_bone_parent(i)
	return t


## Scores every known map against the actual bone names and returns the best fit
## as {path: String, score: int, prefix: String}. Beats prefix matching: it
## recognises rigs whose bones carry no distinctive prefix, and refuses a map
## that only half applies.
##
## `prefix` is the namespace the bones actually carry, which is not always the
## one the map was written with - see GENERATED_MAP_DIR. `path` always names the
## checked-in map; pass the whole result to resolve_bone_map() to get the
## BoneMap that belongs in a .import.
static func detect_bone_map(bones: PackedStringArray) -> Dictionary:
	var have := {}
	for b in bones:
		have[String(b)] = true

	var best := {"path": "", "score": 0, "prefix": ""}
	for map_path in BONE_MAPS:
		var bm := load(map_path) as BoneMap
		if bm == null or bm.profile == null:
			continue
		var base_prefix := map_prefix(bm)
		for prefix in _prefix_candidates(bm, have, base_prefix):
			# Without a hip bone there is no rig to speak of; skip before scoring
			# so a stray coincidental match cannot win.
			var hips := _reprefix(String(bm.get_skeleton_bone_name("Hips")),
				base_prefix, prefix)
			if hips == "" or not have.has(hips):
				continue
			var score := 0
			for i in bm.profile.bone_size:
				var target := _reprefix(
					String(bm.get_skeleton_bone_name(bm.profile.get_bone_name(i))),
					base_prefix, prefix)
				if target != "" and have.has(target):
					score += 1
			if score > best.score:
				best = {"path": map_path, "score": score, "prefix": prefix}

	if best.score < MIN_MATCHED_BONES:
		return {"path": "", "score": best.score, "prefix": ""}
	return best


## The namespace every mapped bone in a map shares: "mixamorig_", "CC_Base_",
## "DEF-". "" when they share nothing, which is the honest answer for a rig whose
## bones carry no prefix at all.
##
## Root is left out of the comparison: the CC and Rigify maps both point it at a
## bare "root" that shares nothing with the rest and would collapse this to "".
static func map_prefix(bm: BoneMap) -> String:
	if bm == null or bm.profile == null:
		return ""
	var prefix := ""
	var started := false
	for i in bm.profile.bone_size:
		var pname := String(bm.profile.get_bone_name(i))
		if pname == "Root":
			continue
		var target := String(bm.get_skeleton_bone_name(pname))
		if target == "":
			continue
		if not started:
			prefix = target
			started = true
			continue
		prefix = _common_prefix(prefix, target)
		if prefix == "":
			break
	return prefix


## Namespaces worth trying one map under: the one it was written with, plus any
## the skeleton itself suggests. A candidate is read off the skeleton by finding
## bones that end the way the map's Hips entry does - "mixamorig9_Hips" against a
## map keyed "mixamorig_Hips" yields "mixamorig9_".
##
## Two deliberate limits keep this from turning into fuzzy matching. A map whose
## bones share no prefix has nothing to substitute, and an empty candidate is
## refused: letting a map strip its own namespace would make every map match a
## rig named after the profile itself, which is exactly the coincidence
## MIN_MATCHED_BONES exists to prevent.
static func _prefix_candidates(bm: BoneMap, have: Dictionary,
		base_prefix: String) -> PackedStringArray:
	var out := PackedStringArray([base_prefix])
	if base_prefix == "":
		return out
	var hips := String(bm.get_skeleton_bone_name("Hips"))
	if not hips.begins_with(base_prefix):
		return out
	var stem := hips.substr(base_prefix.length())
	if stem == "":
		return out
	for bone in have:
		var bone_name := String(bone)
		if bone_name.length() <= stem.length() or not bone_name.ends_with(stem):
			continue
		var candidate := bone_name.substr(0, bone_name.length() - stem.length())
		if candidate != base_prefix and not out.has(candidate):
			out.append(candidate)
	return out


## `name` with the namespace `from` swapped for `to`. Names that do not carry the
## namespace - the bare "root" the CC and Rigify maps use - are left alone.
static func _reprefix(bone_name: String, from: String, to: String) -> String:
	if from == "" or to == from or not bone_name.begins_with(from):
		return bone_name
	return to + bone_name.substr(from.length())


static func _common_prefix(a: String, b: String) -> String:
	var n := mini(a.length(), b.length())
	var i := 0
	while i < n and a[i] == b[i]:
		i += 1
	return a.substr(0, i)


## The BoneMap path to write into a .import for a detect_bone_map() result,
## generating the namespaced variant on disk when the rig turned out to carry a
## namespace the checked-in map was not written for. A no-op returning the map
## itself in the ordinary case. "" means nothing usable could be produced.
##
## The variant is rebuilt whenever the map it derives from is newer, so editing
## assets/retarget/*.tres propagates without anyone having to know this folder
## exists.
static func resolve_bone_map(match_result: Dictionary) -> String:
	var base_path := String(match_result.get("path", ""))
	var bm := _matched_map(match_result)
	if bm == null or bm.profile == null:
		return ""
	var base_prefix := map_prefix(bm)
	var prefix := String(match_result.get("prefix", base_prefix))
	if prefix == base_prefix:
		return base_path

	var out_path := GENERATED_MAP_DIR.path_join("%s__%s.tres" % [
		base_path.get_file().get_basename(), _slug(prefix)])
	if _is_newer(out_path, base_path):
		return out_path

	var variant := BoneMap.new()
	# A fresh profile rather than bm.profile: the loaded one is a sub-resource of
	# the base .tres, and a second resource pointing into another file's
	# sub-resources is not something to rely on surviving a save.
	variant.profile = SkeletonProfileHumanoid.new()
	for i in variant.profile.bone_size:
		var pname := String(variant.profile.get_bone_name(i))
		variant.set_skeleton_bone_name(pname, _reprefix(
			String(bm.get_skeleton_bone_name(pname)), base_prefix, prefix))

	DirAccess.make_dir_recursive_absolute(GENERATED_MAP_DIR)
	if ResourceSaver.save(variant, out_path) != OK:
		return ""
	print("generated %s for the '%s' namespace" % [out_path.get_file(), prefix])
	return out_path


## "" when the rig carries the namespace its map was written with, otherwise the
## namespace it actually carries. For reporting only - configure() gets the same
## answer, and the file to go with it, from resolve_bone_map().
static func namespace_variant(match_result: Dictionary) -> String:
	var bm := _matched_map(match_result)
	if bm == null:
		return ""
	var prefix := String(match_result.get("prefix", ""))
	return "" if prefix == map_prefix(bm) else prefix


## The checked-in BoneMap a detect_bone_map() result points at, or null when it
## matched nothing. Every caller has to tolerate the no-match result, and load()
## on an empty path is an engine error rather than a null.
static func _matched_map(match_result: Dictionary) -> BoneMap:
	var path := String(match_result.get("path", ""))
	if path == "":
		return null
	return load(path) as BoneMap


## Filename-safe form of a namespace. Not injective - ":" and "_" both become
## "_" - but Godot has already turned every ":" in a bone name into "_" by the
## time we see one, so two namespaces cannot collide here in practice.
static func _slug(text: String) -> String:
	var out := ""
	for i in text.length():
		var c := text[i]
		out += c if c.is_valid_int() or (c.to_lower() >= "a" and c.to_lower() <= "z") else "_"
	return out


static func _is_newer(path: String, than_path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	return FileAccess.get_modified_time(ProjectSettings.globalize_path(path)) \
		>= FileAccess.get_modified_time(ProjectSettings.globalize_path(than_path))


## How far the left arm hangs below horizontal in the bind pose, in degrees.
## ~0 is a T-pose, 40-50 is a typical A-pose. Takes a detect_bone_map() result
## rather than a path so it reads the bone names detection actually matched,
## namespace and all.
static func arm_droop_degrees(probed: Dictionary, match_result: Dictionary) -> float:
	var rest: Dictionary = probed.rest
	var upper := source_bone_name(match_result, "LeftUpperArm")
	var hand := source_bone_name(match_result, "LeftHand")
	if not rest.has(upper) or not rest.has(hand):
		return 0.0
	var v: Vector3 = rest[hand] - rest[upper]
	if v.length() < 0.0001:
		return 0.0
	return rad_to_deg(asin(clampf(-v.y / v.length(), -1.0, 1.0)))


## The name a profile bone goes by on the rig a detect_bone_map() result matched,
## namespace included. "" when no map matched or the map leaves it unmapped.
static func source_bone_name(match_result: Dictionary, profile_bone: String) -> String:
	var bm := _matched_map(match_result)
	if bm == null:
		return ""
	var base_prefix := map_prefix(bm)
	return _reprefix(String(bm.get_skeleton_bone_name(profile_bone)),
		base_prefix, String(match_result.get("prefix", base_prefix)))


## The model's standing height, in whatever units its mesh is authored in.
##
## Deliberately not "the longest axis of the bounds", which is what this used to
## be. Two things break that:
##
##   - Which axis is up varies by exporter, and the mesh does not have to agree
##     with the skeleton about it. Measured on the AccuRig FBX: the bone
##     hierarchy imports Y-up while the vertex data stays Z-up, with an identity
##     transform between them. Nothing in the node tree says so.
##   - A T-posed human is about as wide as they are tall, so "longest" is a coin
##     flip between height and arm span. Get it wrong and the character imports
##     at arm-span scale, silently and permanently (see CharacterPipeline's
##     measure-once guard).
##
## What does hold is that the mesh and the skeleton describe the same body, so
## their extents have the same shape even in different spaces. So: rank the
## skeleton's own rest extents longest-first, see where Hips->Head lands, and
## take the mesh extent of that rank. A T-pose puts it second in both spaces, an
## A-pose first in both. Two extents close enough to swap ranks are close enough
## that the answer barely moves.
##
## Falls back to the longest axis when there is no skeleton to rank against.
##
## Only meaningful BEFORE retargeting. The silhouette fix reposes the rest
## without touching the vertices, so a reimported model has a T-posed skeleton
## inside an A-posed mesh - the shapes stop matching and the ranking is void.
## Measured on `hero`: rest extents (1.757, 1.568, 0.215) against mesh extents
## (1.448, 0.334, 1.750). Hence the retargeted guard below, and hence
## CharacterPipeline storing the measurement instead of retaking it.
static func body_height(probed: Dictionary, match_result: Dictionary = {}) -> float:
	var size: Vector3 = (probed.aabb as AABB).size
	if size.x + size.y + size.z < 0.0001:
		return 0.0
	var mesh_order := _axes_longest_first(size)
	return size[mesh_order[_up_axis_rank(probed, match_result)]]


## Where the skeleton's up axis ranks among its own rest extents, longest first.
## 0 when there is nothing to rank, which is what makes body_height() fall back
## to the longest mesh axis.
static func _up_axis_rank(probed: Dictionary, match_result: Dictionary) -> int:
	if String(probed.skeleton) == RETARGETED_SKELETON:
		return 0
	var rest: Dictionary = probed.rest
	var hips := source_bone_name(match_result, "Hips")
	var head := source_bone_name(match_result, "Head")
	if not rest.has(hips) or not rest.has(head):
		return 0
	var up: Vector3 = (rest[head] as Vector3) - (rest[hips] as Vector3)
	if up.length() < 0.0001:
		return 0
	var up_axis := Vector3.AXIS_X
	if absf(up.y) > absf(up[up_axis]):
		up_axis = Vector3.AXIS_Y
	if absf(up.z) > absf(up[up_axis]):
		up_axis = Vector3.AXIS_Z
	return _axes_longest_first(_rest_extents(rest)).find(up_axis)


## Bounding size of every bone's rest origin, per axis.
static func _rest_extents(rest: Dictionary) -> Vector3:
	var lo := Vector3.ZERO
	var hi := Vector3.ZERO
	var started := false
	for bone in rest:
		var p: Vector3 = rest[bone]
		if not started:
			lo = p
			hi = p
			started = true
			continue
		lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
	return hi - lo


## Axis indices ordered by descending extent.
static func _axes_longest_first(size: Vector3) -> Array:
	var axes := [Vector3.AXIS_X, Vector3.AXIS_Y, Vector3.AXIS_Z]
	axes.sort_custom(func(a: int, b: int) -> bool: return size[a] > size[b])
	return axes


static func list_bones(res_path: String) -> PackedStringArray:
	return probe(res_path).bones


# --- step 2: libraries ----------------------------------------------------

## Where a character's own clips are collected to. Kept beside the character so
## deleting the folder takes the generated library with it.
static func character_library_path(character_id: String) -> String:
	return CHARACTERS_DIR.path_join(character_id).path_join("%s_animations.tres" % character_id)


## Builds the shared library plus one per character that has its own clips.
## Returns {ok: bool, libraries: Array[{path, clips}], problems: PackedStringArray}.
static func build_all_libraries(log_fn: Callable = Callable()) -> Dictionary:
	var libraries := []
	var problems := PackedStringArray()
	var ok := true

	for dir_path in source_dirs():
		# An empty character animations/ folder is the normal case, not an error:
		# most characters only ever use the shared clips.
		if list_sources(dir_path).is_empty():
			continue
		var out_path := SHARED_LIBRARY_PATH
		if dir_path != SHARED_SOURCE_DIR:
			out_path = character_library_path(dir_path.get_base_dir().get_file())
		var result := build_library(dir_path, out_path, log_fn)
		problems.append_array(result.problems)
		if result.ok:
			libraries.append({"path": out_path, "clips": result.clips})
		else:
			ok = false

	if libraries.is_empty():
		problems.append("no clips found in %s" % SHARED_SOURCE_DIR)
		ok = false
	return {"ok": ok, "libraries": libraries, "problems": problems}


## Collects every clip in one directory into one library resource.
## Returns {ok: bool, clips: PackedStringArray, problems: PackedStringArray}.
static func build_library(source_dir: String, out_path: String,
		log_fn: Callable = Callable()) -> Dictionary:
	# Reuse the cached resource when it exists so any open scene referencing the
	# library sees the new clips without a reload.
	var lib: AnimationLibrary = null
	if ResourceLoader.exists(out_path):
		lib = ResourceLoader.load(out_path, "AnimationLibrary", ResourceLoader.CACHE_MODE_REUSE)
	if lib == null:
		lib = AnimationLibrary.new()
	for existing in lib.get_animation_list():
		lib.remove_animation(existing)

	var problems := PackedStringArray()
	for path in list_sources(source_dir):
		_harvest(path, lib, problems, log_fn)

	var clips := PackedStringArray(lib.get_animation_list())
	clips.sort()
	if clips.is_empty():
		problems.append("no clips found in %s" % source_dir)
		return {"ok": false, "clips": clips, "problems": problems}

	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	if ResourceSaver.save(lib, out_path) != OK:
		problems.append("could not write %s" % out_path)
		return {"ok": false, "clips": clips, "problems": problems}
	return {"ok": true, "clips": clips, "problems": problems}


static func _harvest(res_path: String, lib: AnimationLibrary,
		problems: PackedStringArray, log_fn: Callable) -> void:
	var packed := load(res_path) as PackedScene
	if packed == null:
		problems.append("%s: not a scene" % res_path.get_file())
		return
	var root := packed.instantiate()
	var player := first_of_class(root, "AnimationPlayer") as AnimationPlayer
	if player == null:
		problems.append("%s: no AnimationPlayer" % res_path.get_file())
		root.free()
		return

	# A single-clip file is named after itself (every Mixamo take is called
	# "mixamo_com", which is useless); a pack's internal names are meaningful,
	# so those win instead of being prefixed with the pack's filename.
	var file_name := clip_name_for(res_path)
	var unretargeted := 0
	var total := 0
	for src_lib_name in player.get_animation_library_list():
		var src := player.get_animation_library(src_lib_name)
		var multi := src.get_animation_list().size() > 1
		for clip_name in src.get_animation_list():
			var out_name := _sanitize(String(clip_name)) if multi else file_name
			if out_name.is_empty():
				out_name = file_name
			out_name = _unique(lib, out_name)
			var anim: Animation = src.get_animation(clip_name).duplicate(true)
			var dropped := _strip_node_tracks(anim)
			lib.add_animation(out_name, anim)
			total += 1
			if not _is_retargeted(anim):
				unretargeted += 1
			if not log_fn.is_null():
				var note := "" if dropped == 0 else "  (dropped %d node track(s))" % dropped
				log_fn.call("  %-38s -> '%s'  %.2fs  %d tracks%s" % [
					res_path.get_file(), out_name, anim.length,
					anim.get_track_count(), note])

	# Tracks that still name the source rig's bones will bind to nothing on the
	# character. That plays silently, so it has to be reported rather than shrugged off.
	if unretargeted > 0:
		problems.append(("%s: %d/%d clip(s) are NOT retargeted - their tracks still " +
			"use the source rig's bone names. Add a BoneMap for this rig " +
			"(see the rig report), then rebuild.") % [
			res_path.get_file(), unretargeted, total])
	root.free()


## Drops tracks that address a node instead of a bone. Returns the count removed.
##
## A shared library is attached to characters whose node layout differs from the
## source file's, so a node track can never bind - Godot logs "couldn't resolve
## track" once per clip at runtime. Blender FBX exports carry exactly one: the
## armature object's own Z-up -> Y-up rotation, which the importer has already
## baked into the bone rests.
##
## Post: every remaining track has a bone subname, which _is_retargeted() and the
## retarget check both assume - get_subname(0) on a bare node path is an error.
static func _strip_node_tracks(anim: Animation) -> int:
	var removed := 0
	for i in range(anim.get_track_count() - 1, -1, -1):
		if anim.track_get_path(i).get_subname_count() == 0:
			anim.remove_track(i)
			removed += 1
	return removed


## Retargeted clips address SkeletonProfileHumanoid bone names; anything else
## still carries the source rig's naming. Pre: node tracks already stripped.
static func _is_retargeted(anim: Animation) -> bool:
	var profile := SkeletonProfileHumanoid.new()
	for i in anim.get_track_count():
		var bone := String(anim.track_get_path(i).get_subname(0))
		if bone != "" and profile.find_bone(bone) != -1:
			return true
	return false


static func _unique(lib: AnimationLibrary, name: String) -> String:
	if not lib.has_animation(name):
		return name
	var i := 2
	while lib.has_animation("%s_%d" % [name, i]):
		i += 1
	return "%s_%d" % [name, i]


## Mixamo downloads are named "Character@Some Action.fbx" and every take inside
## is called "mixamo_com", so the clip name comes from the part after "@",
## normalised to snake_case: "Warrok W Kurniawan@Boxing.fbx" -> "boxing".
static func clip_name_for(res_path: String) -> String:
	return _sanitize(res_path.get_file().get_basename())


## Turns any source-provided name into a usable clip name. Strips the qualifier
## prefixes the common exporters add - Mixamo's "Character@Action", Blender
## glTF's "Armature|Action" - then normalises to snake_case.
## AnimationLibrary also rejects / : , [ outright, so everything that is not
## alphanumeric becomes an underscore.
static func _sanitize(raw: String) -> String:
	var base := raw
	if base.contains("@"):
		base = base.substr(base.rfind("@") + 1)
	if base.contains("|"):
		base = base.substr(base.rfind("|") + 1)

	var cleaned := ""
	for i in base.length():
		var c := base[i]
		if c.is_valid_int() or (c.to_lower() >= "a" and c.to_lower() <= "z"):
			cleaned += c
		else:
			cleaned += "_"
	cleaned = cleaned.to_snake_case()
	while cleaned.contains("__"):
		cleaned = cleaned.replace("__", "_")
	cleaned = cleaned.trim_prefix("_").trim_suffix("_")
	return cleaned


# --- diagnostics ----------------------------------------------------------

## Human-readable status for every source file; used by the plugin's menu item
## and the CLI so an unknown rig explains itself instead of failing silently.
static func rig_report() -> PackedStringArray:
	var out := PackedStringArray()
	for path in list_all_sources():
		var probed := probe(path)
		var bones: PackedStringArray = probed.bones
		if bones.is_empty():
			out.append("%s: no skeleton found" % path.get_file())
			continue

		# Already-retargeted files carry profile bone names, which match no
		# source map; reporting them as "unknown" would be actively misleading.
		if String(probed.skeleton) == RETARGETED_SKELETON:
			out.append("%s: retargeted, %d bones -> ready" % [
				path.get_file(), bones.size()])
			continue

		var match_result := detect_bone_map(bones)
		var map_path: String = match_result.path
		if map_path == "":
			var sample := PackedStringArray()
			for i in mini(8, bones.size()):
				sample.append(bones[i])
			out.append(("%s: UNKNOWN rig, %d bones (best map only matched %d, " +
				"need %d).\n    bones: %s ...\n" +
				"    -> add a mapping to tools/gen_bone_maps.gd, run it, then list " +
				"the new .tres in AnimPipeline.BONE_MAPS") % [
				path.get_file(), bones.size(), match_result.score,
				MIN_MATCHED_BONES, ", ".join(sample)])
			continue

		var line := "%s: %s, %d bones, %d matched" % [
			path.get_file(), map_path.get_file(), bones.size(), match_result.score]
		var variant := namespace_variant(match_result)
		if variant != "":
			line += " under the '%s' namespace" % variant
		var droop := arm_droop_degrees(probed, match_result)
		line += ", T-pose" if droop <= A_POSE_THRESHOLD_DEG else ", A-pose %.0f°" % droop
		out.append(line)
	return out


## First node of the given class in the tree, depth-first. Shared with the
## character pipeline and the debug viewer, which all need to reach into an
## imported model whose exact node layout depends on the exporter.
static func first_of_class(node: Node, cls: String) -> Node:
	if node.is_class(cls):
		return node
	for c in node.get_children():
		var f := first_of_class(c, cls)
		if f != null:
			return f
	return null
