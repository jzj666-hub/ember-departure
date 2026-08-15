extends SceneTree
## Headless inspector: dumps node tree, skeleton, rest pose and mesh bounds
## of an imported model so we can plan retargeting.
##
## Defaults to the first character found; pass a path for anything else.
##
## Usage:
##   godot --headless --path <project> --script res://tools/inspect_model.gd -- <res-path>

const CharacterPipelineScript = preload("res://tools/character_pipeline.gd")

func _initialize() -> void:
	var target := ""
	var user_args := OS.get_cmdline_user_args()
	if user_args.size() > 0:
		target = user_args[0]
	else:
		var characters: Array = CharacterPipelineScript.list_characters()
		if characters.is_empty():
			printerr("no characters in %s, and no path given"
				% CharacterPipelineScript.CHARACTERS_DIR)
			quit(1)
			return
		target = characters[0].model

	print("=== INSPECT: %s ===" % target)
	var packed := load(target) as PackedScene
	if packed == null:
		printerr("could not load %s" % target)
		quit(1)
		return

	var root := packed.instantiate()
	_dump_tree(root, 0)

	for skel in _find_all(root, "Skeleton3D"):
		_dump_skeleton(skel)
	for ap in _find_all(root, "AnimationPlayer"):
		_dump_anim_player(ap)
	for mi in _find_all(root, "MeshInstance3D"):
		_dump_mesh(mi)

	root.free()
	quit(0)


func _dump_tree(node: Node, depth: int) -> void:
	var extra := ""
	if node is MeshInstance3D:
		extra = " [surfaces=%d]" % (node as MeshInstance3D).mesh.get_surface_count()
	elif node is Skeleton3D:
		extra = " [bones=%d]" % (node as Skeleton3D).get_bone_count()
	if node is Node3D:
		var t := (node as Node3D).transform
		extra += "  xform: origin=(%.4f,%.4f,%.4f) scale=(%.4f,%.4f,%.4f)" % [
			t.origin.x, t.origin.y, t.origin.z,
			t.basis.get_scale().x, t.basis.get_scale().y, t.basis.get_scale().z]
	print("%s- %s (%s)%s" % ["  ".repeat(depth), node.name, node.get_class(), extra])
	for c in node.get_children():
		_dump_tree(c, depth + 1)


func _find_all(node: Node, cls: String, out: Array = []) -> Array:
	if node.is_class(cls):
		out.append(node)
	for c in node.get_children():
		_find_all(c, cls, out)
	return out


func _global_rest(skel: Skeleton3D, idx: int) -> Transform3D:
	var t := Transform3D.IDENTITY
	var i := idx
	while i != -1:
		t = skel.get_bone_rest(i) * t
		i = skel.get_bone_parent(i)
	return t


func _dump_skeleton(skel: Skeleton3D) -> void:
	print("\n=== SKELETON: %s  bones=%d  motion_scale=%s ===" % [
		skel.name, skel.get_bone_count(), skel.motion_scale])

	print("--- all bone names (index:parent:name) ---")
	var names := PackedStringArray()
	for i in skel.get_bone_count():
		names.append("%d:%d:%s" % [i, skel.get_bone_parent(i), skel.get_bone_name(i)])
	print(", ".join(names))

	print("--- key bone GLOBAL rest positions (pose detection) ---")
	var keys := [
		"root", "CC_Base_Hip", "CC_Base_Pelvis", "CC_Base_Spine02", "CC_Base_Head",
		"CC_Base_L_Clavicle", "CC_Base_L_Upperarm", "CC_Base_L_Forearm", "CC_Base_L_Hand",
		"CC_Base_R_Upperarm", "CC_Base_R_Hand",
		"CC_Base_L_Thigh", "CC_Base_L_Calf", "CC_Base_L_Foot", "CC_Base_L_ToeBase",
	]
	for n in keys:
		var idx := skel.find_bone(n)
		if idx == -1:
			print("  %-22s <missing>" % n)
			continue
		var g := _global_rest(skel, idx)
		print("  %-22s pos=(%7.3f,%7.3f,%7.3f)  basisX=(%5.2f,%5.2f,%5.2f)" % [
			n, g.origin.x, g.origin.y, g.origin.z,
			g.basis.x.x, g.basis.x.y, g.basis.x.z])


func _dump_anim_player(ap: AnimationPlayer) -> void:
	print("\n=== ANIMATIONPLAYER: %s ===" % ap.name)
	for lib_name in ap.get_animation_library_list():
		var lib := ap.get_animation_library(lib_name)
		for a in lib.get_animation_list():
			var anim := lib.get_animation(a)
			print("  '%s/%s'  len=%.3fs  tracks=%d  loop=%d" % [
				lib_name, a, anim.length, anim.get_track_count(), anim.loop_mode])


func _dump_mesh(mi: MeshInstance3D) -> void:
	var aabb := mi.get_aabb()
	print("\n=== MESH: %s ===" % mi.name)
	print("  aabb pos=(%.3f,%.3f,%.3f) size=(%.3f,%.3f,%.3f)" % [
		aabb.position.x, aabb.position.y, aabb.position.z,
		aabb.size.x, aabb.size.y, aabb.size.z])
	print("  skin=%s  blend_shapes=%d" % [
		mi.skin != null, mi.mesh.get_blend_shape_count()])
	for s in mi.mesh.get_surface_count():
		var mat := mi.mesh.surface_get_material(s)
		if mat is BaseMaterial3D:
			var bm := mat as BaseMaterial3D
			print("  surf %d mat='%s' albedo_tex=%s normal_tex=%s orm=%s" % [
				s, bm.resource_name,
				bm.get_texture(BaseMaterial3D.TEXTURE_ALBEDO),
				bm.get_texture(BaseMaterial3D.TEXTURE_NORMAL),
				bm.get_texture(BaseMaterial3D.TEXTURE_ORM)])
		else:
			print("  surf %d mat=%s" % [s, mat])
