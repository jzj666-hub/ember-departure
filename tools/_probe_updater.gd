extends SceneTree
## Probe script to test Updater logic and UpdateDialog UI instantiation.

const UpdaterScript = preload("res://scripts/updater/updater.gd")
const UpdateDialogScript = preload("res://scripts/updater/update_dialog.gd")

func _init() -> void:
	print("--- Starting Updater Probe ---")

	# 1. Test version comparison
	assert(UpdaterScript.is_newer_version("v1.0.1", "v1.0.0") == true, "v1.0.1 should be newer than v1.0.0")
	assert(UpdaterScript.is_newer_version("v2.0.0", "v1.9.9") == true, "v2.0.0 should be newer than v1.9.9")
	assert(UpdaterScript.is_newer_version("v1.0.0", "v1.0.0") == false, "v1.0.0 is not newer than v1.0.0")
	assert(UpdaterScript.is_newer_version("v0.9.0", "v1.0.0") == false, "v0.9.0 is older than v1.0.0")
	print("✔ Version comparison tests passed.")

	# 2. Test local version reader
	var local_info: Dictionary = UpdaterScript.get_local_version_info()
	print("✔ Local version info: ", local_info)
	assert(local_info.has("version"), "local info must have version")
	assert(local_info["version"] == "v1.0.0", "local version must match v1.0.0")

	# 3. Test git exe resolution
	var git_exe: String = UpdaterScript.get_git_exe_path()
	print("✔ Resolved git executable path: ", git_exe)
	assert(not git_exe.is_empty(), "git executable path must not be empty")

	# 4. Test UpdateDialog instantiation in tree
	var root_node := Control.new()
	root_node.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(root_node)

	var dialog = UpdateDialogScript.new()
	root_node.add_child(dialog)
	dialog.setup_data({
		"version": "v1.1.0",
		"release_notes": [
			"新增 Gitee 一键自动拉取更新",
			"新增武器试炼与连招演练场",
			"修复 AI 动力学寻路边缘卡顿问题"
		]
	})

	print("✔ UpdateDialog successfully created and configured with mock data.")
	print("--- All Updater Probe tests passed successfully! ---")
	quit(0)
