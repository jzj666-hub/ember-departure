class_name MapData
extends RefCounted
## Map data model, JSON serialization, and file I/O manager.

const CURRENT_FORMAT_VERSION := 1
const USER_MAPS_DIR := "user://maps/"
const RES_MAPS_DIR := "res://maps/"

## Serializes map state to JSON dictionary.
static func serialize_map(
	map_name: String,
	spawn_pos: Vector3,
	bounds_half: int,
	max_block_y: int,
	blocks: Array, # Array of BlockInstance
	special_paths: Array = [] # Array of Dictionary
) -> Dictionary:
	var blocks_data: Array = []
	for b in blocks:
		if b is BlockRegistry.BlockInstance:
			blocks_data.append(b.to_dict())
		elif b is Dictionary:
			blocks_data.append(b)

	return {
		"format_version": CURRENT_FORMAT_VERSION,
		"name": map_name,
		"timestamp": int(Time.get_unix_time_from_system()),
		"spawn_pos": [spawn_pos.x, spawn_pos.y, spawn_pos.z],
		"bounds": {
			"half": bounds_half,
			"max_y": max_block_y,
		},
		"blocks": blocks_data,
		"special_paths": special_paths,
	}


## Creates an empty default map dictionary.
static func create_default_map(map_name := "新建地图") -> Dictionary:
	return serialize_map(
		map_name,
		Vector3(0.5, 0.2, 0.5),
		20,
		7,
		[],
		[]
	)


## Saves map dictionary to JSON file path.
static func save_map_to_file(path: String, data: Dictionary) -> Error:
	var dir_path := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var err := DirAccess.make_dir_recursive_absolute(dir_path)
		if err != OK:
			return err

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	var json_str := JSON.stringify(data, "\t")
	file.store_string(json_str)
	file.close()
	return OK


## Loads map dictionary from JSON file path.
static func load_map_from_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Map file not found: %s" % path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open map file: %s" % path)
		return {}

	var content := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(content)
	if err != OK:
		push_error("Failed to parse map JSON (%d): %s" % [err, json.get_error_message()])
		return {}

	var data: Variant = json.data
	if not (data is Dictionary):
		push_error("Map data root is not a dictionary: %s" % path)
		return {}

	return data as Dictionary


## Lists all available maps in user://maps/ and res://maps/.
static func list_available_maps() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var seen_names: Dictionary = {}

	# Ensure user maps directory exists
	if not DirAccess.dir_exists_absolute(USER_MAPS_DIR):
		DirAccess.make_dir_recursive_absolute(USER_MAPS_DIR)

	_scan_map_directory(USER_MAPS_DIR, results, seen_names, false)
	if DirAccess.dir_exists_absolute(RES_MAPS_DIR):
		_scan_map_directory(RES_MAPS_DIR, results, seen_names, true)

	return results


## Deletes a map file in user storage.
static func delete_user_map(file_name: String) -> Error:
	var path := USER_MAPS_DIR.path_join(file_name)
	if not path.ends_with(".json"):
		path += ".json"
	if FileAccess.file_exists(path):
		return DirAccess.remove_absolute(path)
	return ERR_FILE_NOT_FOUND


static func _scan_map_directory(dir_path: String, out_list: Array[Dictionary], seen: Dictionary, is_builtin: bool) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var full_path := dir_path.path_join(file_name)
			var base_name := file_name.get_basename()
			if not seen.has(base_name):
				seen[base_name] = true
				var map_info := _read_map_header(full_path, file_name, is_builtin)
				out_list.append(map_info)
		file_name = dir.get_next()
	dir.list_dir_end()


static func _read_map_header(path: String, file_name: String, is_builtin: bool) -> Dictionary:
	var data := load_map_from_file(path)
	var map_name: String = str(data.get("name", file_name.get_basename()))
	var timestamp: int = int(data.get("timestamp", 0))
	var blocks_count: int = (data.get("blocks", []) as Array).size()
	var special_paths_count: int = (data.get("special_paths", []) as Array).size()
	return {
		"file_name": file_name,
		"path": path,
		"name": map_name,
		"timestamp": timestamp,
		"blocks_count": blocks_count,
		"special_paths_count": special_paths_count,
		"is_builtin": is_builtin,
	}
