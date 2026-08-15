extends SceneTree
## Exports an imported animation scene back out as .glb, to test the pipeline
## against glTF input without needing an external download.
##
## The exported rig carries the retargeted (profile) bone names - Hips, Spine,
## LeftUpperArm - which is also how most non-Mixamo glTF packs name their bones,
## so this doubles as a test of the unprefixed-rig case.
##
##   godot --headless --path <project> --script res://tools/make_test_glb.gd

const SOURCE := "res://assets/animations/source/draw_great_sword.fbx"
const OUT := "res://.captures/test_export.glb"

func _initialize() -> void:
	var packed := load(SOURCE) as PackedScene
	if packed == null:
		printerr("cannot load %s" % SOURCE)
		quit(1)
		return
	var root := packed.instantiate()
	# append_from_scene walks the live tree, so the node must be inside one.
	get_root().add_child(root)

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	if err != OK:
		printerr("append_from_scene failed: %d" % err)
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	err = doc.write_to_filesystem(state, OUT)
	if err != OK:
		printerr("write_to_filesystem failed: %d" % err)
		quit(1)
		return

	print("wrote %s (%d bytes)" % [OUT, FileAccess.get_file_as_bytes(OUT).size()])
	quit(0)
