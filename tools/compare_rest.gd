extends SceneTree
## Read-only diagnostic: compares every character's retargeted rest pose against
## the humanoid profile, bone by bone, and against each other.
##
## Why this exists: "retargeted" does not mean "identical rest". The importer's
## fix_silhouette only straightens a bone whose rest deviates from the profile by
## MORE than its threshold (15 deg unless the .import says otherwise). A bone
## that sits 10 deg off is left exactly as the artist authored it. Two characters
## from the same pipeline can therefore carry different residual torso curvature,
## and the same clip - which only supplies rotations - then lands on two
## different silhouettes: one hunched, one upright.
##
## The "delta" column is the number that matters. Bones where characters differ
## from each other are the ones a viewer sees.
##
##   godot --headless --path <project> --script res://tools/compare_rest.gd

const AnimPipelineScript = preload("res://tools/anim_pipeline.gd")
const CharacterPipelineScript = preload("res://tools/character_pipeline.gd")

## Profile bones worth comparing, in chain order. Each entry is measured as the
## direction to the NEXT entry, which is exactly the geometry an animation cannot
## change: a rotation track overwrites a bone's rest ROTATION, but never the
## offset its child sits at. So residual differences here are residual
## differences in posture under any clip.
##
## SkeletonProfileHumanoid.get_bone_tail() is not usable for this - it is empty
## for most of the spine - hence the explicit chain.
const CHAIN := [
	["Hips", "Spine"], ["Spine", "Chest"], ["Chest", "UpperChest"],
	["UpperChest", "Neck"], ["Neck", "Head"],
	["LeftShoulder", "LeftUpperArm"], ["LeftUpperArm", "LeftLowerArm"],
	["LeftLowerArm", "LeftHand"],
	["LeftUpperLeg", "LeftLowerLeg"], ["LeftLowerLeg", "LeftFoot"],
]

var _profile := SkeletonProfileHumanoid.new()


func _initialize() -> void:
	var characters: Array = CharacterPipelineScript.list_characters()
	if characters.is_empty():
		printerr("no characters in %s" % CharacterPipelineScript.CHARACTERS_DIR)
		quit(1)
		return

	# "A->B" -> {character id -> {angle, pitch}}
	var table := {}
	var ids := PackedStringArray()

	for character in characters:
		var skel := _skeleton_of(character.model)
		if skel == null:
			printerr("%s: no skeleton" % character.id)
			continue
		ids.append(character.id)
		print("\n=== %s ===" % character.id)
		print("  %d bones, %d of them profile bones, head at %.3f m" % [
			skel.get_bone_count(), _profile_bone_count(skel), _rest_height(skel)])
		print("  torso lean (Hips->Head off vertical): %.2f deg" % _torso_lean(skel))

		for pair in CHAIN:
			var key := "%s->%s" % [pair[0], pair[1]]
			var measured := _deviation(skel, String(pair[0]), String(pair[1]))
			if measured.is_empty():
				continue
			if not table.has(key):
				table[key] = {}
			table[key][character.id] = measured
		skel.get_parent().free()

	_print_table(table, ids)
	quit(0)


## How far the rest offset from `bone` to `child` departs from the profile's.
##
## Returns {angle, pitch}: `angle` is the total deviation, `pitch` is its signed
## sagittal component - positive leans the chain forward (reads as a hunch),
## negative leans it back (reads as an arch). Empty when either bone is missing,
## which is itself worth knowing: a profile bone the character lacks means the
## clip's track for it binds to nothing.
func _deviation(skel: Skeleton3D, bone_name: String, child_name: String) -> Dictionary:
	var here := skel.find_bone(bone_name)
	var there := skel.find_bone(child_name)
	if here == -1 or there == -1:
		return {}

	var actual := _global_rest(skel, there).origin - _global_rest(skel, here).origin
	var wanted := _profile_global(child_name).origin - _profile_global(bone_name).origin
	if actual.length() < 0.0001 or wanted.length() < 0.0001:
		return {}
	actual = actual.normalized()
	wanted = wanted.normalized()

	# Sagittal component only: project both onto the YZ plane and take the signed
	# angle about X. Godot characters face -Z, so a child pushed towards +Z is
	# behind the profile position and the segment above it tips forward.
	#
	# A segment that runs almost straight along X - the shoulder, the arms in a
	# T-pose - projects onto nearly nothing, and the angle between two such
	# projections is noise that prints as a confident +180. Report 0 instead.
	var a := Vector2(actual.z, actual.y)
	var w := Vector2(wanted.z, wanted.y)
	var pitch := 0.0
	if a.length() > 0.05 and w.length() > 0.05:
		pitch = rad_to_deg(w.normalized().angle_to(a.normalized()))
	return {
		"angle": rad_to_deg(actual.angle_to(wanted)),
		"pitch": pitch,
	}


## Profile bones the character actually has. A short count means clip tracks are
## silently dropping.
func _profile_bone_count(skel: Skeleton3D) -> int:
	var n := 0
	for i in _profile.bone_size:
		if skel.find_bone(_profile.get_bone_name(i)) != -1:
			n += 1
	return n


## How far the whole torso tips off vertical in the rest pose. The single number
## that best predicts "this one looks hunched next to that one".
func _torso_lean(skel: Skeleton3D) -> float:
	var hips := skel.find_bone("Hips")
	var head := skel.find_bone("Head")
	if hips == -1 or head == -1:
		return 0.0
	var v := _global_rest(skel, head).origin - _global_rest(skel, hips).origin
	if v.length() < 0.0001:
		return 0.0
	return rad_to_deg(v.normalized().angle_to(Vector3.UP))


func _rest_height(skel: Skeleton3D) -> float:
	var head := skel.find_bone("Head")
	if head == -1:
		return 0.0
	return _global_rest(skel, head).origin.y


func _print_table(table: Dictionary, ids: PackedStringArray) -> void:
	if ids.size() < 2:
		return
	print("\n=== rest offset deviation from the humanoid profile, in degrees ===")
	print("  signed = sagittal component: + tips the chain FORWARD (hunch),")
	print("           - tips it BACK (arch). delta = spread between characters,")
	print("           and the spread is what a viewer actually sees.\n")
	var header := "  %-22s" % "segment"
	for id in ids:
		header += "%14s" % id
	print(header + "%10s" % "delta")

	for pair in CHAIN:
		var key := "%s->%s" % [pair[0], pair[1]]
		if not table.has(key):
			print("  %-22s%s" % [key, "  <missing on every character>"])
			continue
		var row: Dictionary = table[key]
		var line := "  %-22s" % key
		var lo := 1e9
		var hi := -1e9
		for id in ids:
			if not row.has(id):
				line += "%14s" % "-"
				continue
			var m: Dictionary = row[id]
			line += "%14s" % ("%.1f/%+.1f" % [m.angle, m.pitch])
			lo = minf(lo, m.pitch)
			hi = maxf(hi, m.pitch)
		line += "%10.1f" % (hi - lo) if hi > -1e9 else "%10s" % "-"
		print(line)
	print("\n  cells read: total_deviation / signed_forward_tilt")


func _skeleton_of(res_path: String) -> Skeleton3D:
	var packed := ResourceLoader.load(res_path, "PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		return null
	var root := packed.instantiate()
	return AnimPipelineScript.first_of_class(root, "Skeleton3D") as Skeleton3D


func _global_rest(skel: Skeleton3D, idx: int) -> Transform3D:
	var t := Transform3D.IDENTITY
	var i := idx
	while i != -1:
		t = skel.get_bone_rest(i) * t
		i = skel.get_bone_parent(i)
	return t


func _profile_global(bone_name: String) -> Transform3D:
	var t := Transform3D.IDENTITY
	var name := bone_name
	while name != "":
		var i := _profile.find_bone(name)
		if i == -1:
			break
		t = _profile.get_reference_pose(i) * t
		name = String(_profile.get_bone_parent(i))
	return t
