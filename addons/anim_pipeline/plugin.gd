@tool
extends EditorPlugin
## Watches the asset folders so downloaded content needs no manual work: drop a
## file in, and it gets the right BoneMap and lands where the game can use it.
##
## Flow when new files appear:
##   Godot imports them plain  ->  we detect each rig and write its .import  ->
##   Godot reimports them retargeted  ->  we rebuild the libraries and the
##   character wrapper scenes.
##
## Covers both halves of the pipeline:
##   assets/animations/source/     shared clips        (AnimPipeline)
##   assets/characters/<id>/       characters          (CharacterPipeline)
##   assets/characters/<id>/animations/   that character's own clips
##
## Also adds Project > Tools > "重建角色与动作 / Rebuild Characters & Animations".

const AnimPipelineScript = preload("res://tools/anim_pipeline.gd")
const CharacterPipelineScript = preload("res://tools/character_pipeline.gd")
const MENU_ITEM := "重建角色与动作 / Rebuild Characters & Animations"

var _fs: EditorFileSystem
## Guards the import -> reimport -> rebuild chain from re-entering itself.
var _working := false


func _enter_tree() -> void:
	add_tool_menu_item(MENU_ITEM, _run_full_pass)
	_fs = EditorInterface.get_resource_filesystem()
	_fs.filesystem_changed.connect(_on_filesystem_changed)
	_fs.resources_reimported.connect(_on_resources_reimported)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_ITEM)
	if _fs:
		if _fs.filesystem_changed.is_connected(_on_filesystem_changed):
			_fs.filesystem_changed.disconnect(_on_filesystem_changed)
		if _fs.resources_reimported.is_connected(_on_resources_reimported):
			_fs.resources_reimported.disconnect(_on_resources_reimported)


## Newly dropped files arrive here already imported (without a bone map).
func _on_filesystem_changed() -> void:
	if _working:
		return
	var pending := _configure_everything()
	if pending.is_empty():
		return

	_working = true
	print_rich("[b][Asset Pipeline][/b] retargeting %d new file(s): %s" % [
		pending.size(), ", ".join(_file_names(pending))])
	# Reimport picks up what we just wrote; _on_resources_reimported then rebuilds.
	_fs.reimport_files(pending)


## Both pipelines in one pass. Returns every path that now needs reimporting.
func _configure_everything() -> PackedStringArray:
	var pending := PackedStringArray()
	for path in AnimPipelineScript.list_all_sources():
		if AnimPipelineScript.configure(path).changed:
			pending.append(path)
	for character in CharacterPipelineScript.list_characters():
		if CharacterPipelineScript.configure(character).changed:
			pending.append(character.model)
	return pending


func _on_resources_reimported(resources: PackedStringArray) -> void:
	var touched := false
	for path in resources:
		if path.begins_with(AnimPipelineScript.SHARED_SOURCE_DIR) \
				or path.begins_with(AnimPipelineScript.CHARACTERS_DIR):
			touched = true
			break
	if not touched:
		_working = false
		return
	_rebuild()
	_working = false


## Libraries first: the character scenes reference them.
func _rebuild() -> void:
	var libraries: Dictionary = AnimPipelineScript.build_all_libraries()
	for problem in libraries.problems:
		push_warning("[Asset Pipeline] %s" % problem)
	for lib in libraries.libraries:
		_fs.update_file(lib.path)
		print_rich("[b][Asset Pipeline][/b] %s now has %d clip(s): %s" % [
			String(lib.path).get_file(), lib.clips.size(), ", ".join(lib.clips)])

	for character in CharacterPipelineScript.list_characters():
		CharacterPipelineScript.fix_character_materials(character.dir)

	var scenes: Dictionary = CharacterPipelineScript.build_scenes()
	for problem in scenes.problems:
		push_warning("[Asset Pipeline] %s" % problem)
	if scenes.scenes.is_empty():
		return
	for scene_path in scenes.scenes:
		_fs.update_file(scene_path)
	print_rich("[b][Asset Pipeline][/b] %d character scene(s): %s" % [
		scenes.scenes.size(), ", ".join(_file_names(scenes.scenes))])


## Manual pass: useful after editing a bone map, or when a rig was unrecognised
## the first time round.
func _run_full_pass() -> void:
	_working = true
	print_rich("\n[b][Asset Pipeline][/b] rig report")
	for line in CharacterPipelineScript.rig_report():
		print("  character %s" % line)
	for line in AnimPipelineScript.rig_report():
		print("  %s" % line)

	var changed := _configure_everything()
	if changed.is_empty():
		_rebuild()
		_working = false
	else:
		print_rich("[b][Asset Pipeline][/b] reimporting %s" % ", ".join(_file_names(changed)))
		_fs.reimport_files(changed)


func _file_names(paths: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for p in paths:
		out.append(p.get_file())
	return out
