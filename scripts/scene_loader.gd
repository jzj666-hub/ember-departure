class_name SceneLoader
extends RefCounted
## Global scene transition and asynchronous threaded loading controller.
## Pre: target_scene_path exists in ResourceLoader. Post: changes to loading screen then target scene.

const LOADING_SCENE := "res://scenes/loading_screen.tscn"

static var target_scene_path: String = ""
static var target_hint_text: String = ""


## Requests threaded loading of target scene and transfers to loading screen.
static func change_scene(tree: SceneTree, path: String, hint: String = "") -> void:
	if tree == null or path.is_empty():
		return
	target_scene_path = path
	target_hint_text = hint
	ResourceLoader.load_threaded_request(path)
	tree.change_scene_to_file(LOADING_SCENE)


## Alias for drop-in replacement of tree.change_scene_to_file.
static func change_scene_to_file(tree: SceneTree, path: String, hint: String = "") -> void:
	change_scene(tree, path, hint)
