extends SceneTree
## Renders stills of the debug scene so a retarget can be checked without
## opening the editor. Writes PNGs to .captures/ in the project folder.
##
## Every character in the scene is posed, so one shot shows whether a clip lands
## the same way on all of them.
##
##   godot --path <project> --script res://tools/capture.gd -- walk idle sprint
##
## (no --headless: it needs a real renderer)

const SCENE := "res://scenes/anim_debug.tscn"
const OUT_DIR := "res://.captures"
const DEFAULT_CLIPS := ["idle", "walk", "sword_attack"]
## Fraction through each clip to sample; mid-clip avoids neutral start frames.
const SAMPLE_AT := 0.45

func _initialize() -> void:
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	if not FileAccess.file_exists(OUT_DIR.path_join(".gdignore")):
		FileAccess.open(OUT_DIR.path_join(".gdignore"), FileAccess.WRITE).close()

	root.size = Vector2i(1280, 800)
	var scene := (load(SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	for i in 6:
		await process_frame

	var characters := _find_characters(scene)
	if characters.is_empty():
		printerr("no characters in the scene - run tools\\rebuild_assets.bat first")
		quit(1)
		return
	print("%d character(s): %s" % [characters.size(), ", ".join(_names(characters))])

	var wanted := OS.get_cmdline_user_args()
	var clips := wanted if wanted.size() > 0 else PackedStringArray(DEFAULT_CLIPS)

	var index := 0
	for name in clips:
		var posed := false
		print("\nclip '%s'" % name)
		for character in characters:
			var full := character.resolve(String(name))
			if full == "":
				print("  %s: not found" % character.name)
				continue
			var anim := character.player.get_animation(full)
			_report_binding(character, full, anim)
			character.play(full)
			character.player.pause()
			character.player.seek(anim.length * SAMPLE_AT, true)
			posed = true
		if not posed:
			printerr("  clip '%s' found on no character" % name)
			continue
		index += 1
		await _shot("%02d_%s" % [index, String(name)])

	print("\nwrote %d frame(s) to %s" % [index, OUT_DIR])
	quit(0)


func _shot(name: String) -> void:
	# Two frames: one to apply the pose, one to render it.
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var path := OUT_DIR.path_join(name + ".png")
	root.get_texture().get_image().save_png(path)
	print("  -> %s" % path)


## A clip whose tracks do not resolve plays silently and looks identical to a
## broken retarget, so count them explicitly.
func _report_binding(character: Character, clip: String, anim: Animation) -> void:
	var bound := 0
	var missing := PackedStringArray()
	for i in anim.get_track_count():
		var bone := String(anim.track_get_path(i).get_subname(0))
		if character.skeleton.find_bone(bone) != -1:
			bound += 1
		elif not missing.has(bone):
			missing.append(bone)
	print("  %s: '%s' %.2fs, %d/%d tracks bound" % [
		character.name, clip, anim.length, bound, anim.get_track_count()])
	if missing.size() > 0:
		print("    unbound: %s" % ", ".join(missing))


func _find_characters(node: Node, out: Array[Character] = []) -> Array[Character]:
	if node is Character and (node as Character).player != null:
		out.append(node as Character)
	for c in node.get_children():
		_find_characters(c, out)
	return out


func _names(characters: Array[Character]) -> PackedStringArray:
	var out := PackedStringArray()
	for c in characters:
		out.append(String(c.name))
	return out
