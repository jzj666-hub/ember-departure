class_name Updater
extends RefCounted
## Version checker and in-app Git synchronization runner.

const VERSION_FILE_PATH := "res://version.json"
const DEFAULT_VERSION := "v1.0.0"

static var _cached_git_path: String = ""


## Loads local version manifest.
## Post: returns dictionary with "version", "gitee_version_url", "release_notes".
static func get_local_version_info() -> Dictionary:
	if not FileAccess.file_exists(VERSION_FILE_PATH):
		return {
			"version": DEFAULT_VERSION,
			"gitee_version_url": "",
			"release_notes": []
		}
	var f := FileAccess.open(VERSION_FILE_PATH, FileAccess.READ)
	if f == null:
		return {"version": DEFAULT_VERSION, "release_notes": []}
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) == OK and json.data is Dictionary:
		return json.data as Dictionary
	return {"version": DEFAULT_VERSION, "release_notes": []}


## Resolves git executable binary absolute path on host.
## Post: returns valid path or "git".
static func get_git_exe_path() -> String:
	if not _cached_git_path.is_empty():
		return _cached_git_path
	var candidates := [
		"D:/xunlei/Git/cmd/git.exe",
		"D:/xunlei/Git/bin/git.exe",
		"C:/Program Files/Git/cmd/git.exe",
		"C:/Program Files (x86)/Git/cmd/git.exe"
	]
	for p in candidates:
		if FileAccess.file_exists(p):
			_cached_git_path = p
			return p
	_cached_git_path = "git"
	return _cached_git_path


## Checks if remote version string is strictly newer than local version string.
## Pre: remote_ver and local_ver follow "vX.Y.Z" or "X.Y.Z".
static func is_newer_version(remote_ver: String, local_ver: String) -> bool:
	var r_clean := remote_ver.trim_prefix("v").strip_edges()
	var l_clean := local_ver.trim_prefix("v").strip_edges()
	if r_clean == l_clean or r_clean.is_empty():
		return false
	var r_parts := r_clean.split(".")
	var l_parts := l_clean.split(".")
	var max_len := maxi(r_parts.size(), l_parts.size())
	for i in range(max_len):
		var r_num := int(r_parts[i]) if i < r_parts.size() else 0
		var l_num := int(l_parts[i]) if i < l_parts.size() else 0
		if r_num > l_num:
			return true
		elif r_num < l_num:
			return false
	return false


## Fetches remote version manifest asynchronously via HTTPRequest.
## Callback sig: func(has_update: bool, remote_info: Dictionary)
static func check_for_updates(node_context: Node, callback: Callable) -> void:
	var local_info := get_local_version_info()
	var url: String = str(local_info.get("gitee_version_url", ""))
	if url.is_empty():
		callback.call(false, {})
		return

	var http := HTTPRequest.new()
	http.timeout = 4.0
	node_context.add_child(http)

	http.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		var has_update := false
		var remote_info: Dictionary = {}
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var json := JSON.new()
			var body_str := body.get_string_from_utf8()
			if json.parse(body_str) == OK and json.data is Dictionary:
				remote_info = json.data as Dictionary
				var remote_ver := str(remote_info.get("version", ""))
				var local_ver := str(local_info.get("version", DEFAULT_VERSION))
				has_update = is_newer_version(remote_ver, local_ver)
		
		callback.call(has_update, remote_info)
		http.queue_free()
	)

	var err := http.request(url)
	if err != OK:
		callback.call(false, {})
		http.queue_free()


## Runs git pull asynchronously in background thread.
## on_complete sig: func(success: bool, output: String)
static func pull_latest_code(on_complete: Callable) -> void:
	var git_exe := get_git_exe_path()
	var thread := Thread.new()
	var project_dir := ProjectSettings.globalize_path("res://")

	var task := func() -> void:
		var output: Array = []
		# 1. Fetch
		var exit_code := OS.execute(git_exe, ["pull"], output, true)
		var out_str := "\n".join(output)
		var is_ok := (exit_code == 0)
		Callable(func() -> void:
			on_complete.call(is_ok, out_str)
		).call_deferred()

	thread.start(task)
