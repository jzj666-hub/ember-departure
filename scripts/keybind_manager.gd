class_name KeybindManager
extends Node
## Global keybinding and input redirection manager.
## Handles persistence to user://keybindings.json, action rebinding, and double-tap trigger resolution.

signal keybindings_changed

const SAVE_PATH := "user://keybindings.json"

const ACTION_GROUPS := {
	"locomotion": ["move_forward", "move_backward", "move_left", "move_right", "run", "crouch", "jump", "roll"],
	"combat": ["attack", "heavy", "special", "block"],
	"skills": ["skill_1"],
}

const ACTION_NAMES := {
	"move_forward": "向前移动",
	"move_backward": "向后移动",
	"move_left": "向左移动",
	"move_right": "向右移动",
	"run": "疾跑 (按住)",
	"crouch": "下蹲 (按住)",
	"jump": "跳跃 / 攀爬",
	"roll": "翻滚躲避",
	"attack": "普通挥击",
	"heavy": "重击 / 连招派生",
	"special": "特殊技能",
	"block": "格挡防御",
	"skill_1": "释放抽取技能",
}

const DEFAULT_BINDINGS := {
	"move_forward": {"device": "key", "code": KEY_W, "trigger": "single"},
	"move_backward": {"device": "key", "code": KEY_S, "trigger": "single"},
	"move_left": {"device": "key", "code": KEY_A, "trigger": "single"},
	"move_right": {"device": "key", "code": KEY_D, "trigger": "single"},
	"run": {"device": "key", "code": KEY_SHIFT, "trigger": "single"},
	"crouch": {"device": "key", "code": KEY_CTRL, "trigger": "single"},
	"jump": {"device": "key", "code": KEY_SPACE, "trigger": "single"},
	"roll": {"device": "key", "code": KEY_SHIFT, "trigger": "double_tap"},
	"attack": {"device": "mouse", "code": MOUSE_BUTTON_LEFT, "trigger": "single"},
	"heavy": {"device": "mouse", "code": MOUSE_BUTTON_RIGHT, "trigger": "single"},
	"special": {"device": "key", "code": KEY_E, "trigger": "single"},
	"block": {"device": "key", "code": KEY_X, "trigger": "single"},
	"skill_1": {"device": "key", "code": KEY_1, "trigger": "single"},
}

var _bindings: Dictionary = {}
static var _instance = null


func _init() -> void:
	if _instance == null:
		_instance = self
	_reset_memory_bindings()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_from_disk()


static func get_instance():
	if _instance == null:
		var script = load("res://scripts/keybind_manager.gd")
		_instance = script.new()
		_instance.load_from_disk()
	return _instance


func _reset_memory_bindings() -> void:
	_bindings.clear()
	for action in DEFAULT_BINDINGS:
		_bindings[action] = (DEFAULT_BINDINGS[action] as Dictionary).duplicate()


func get_all_bindings() -> Dictionary:
	var out := {}
	for k in _bindings:
		out[k] = (_bindings[k] as Dictionary).duplicate()
	return out


func get_binding(action: String) -> Dictionary:
	if _bindings.has(action):
		return (_bindings[action] as Dictionary).duplicate()
	if DEFAULT_BINDINGS.has(action):
		return (DEFAULT_BINDINGS[action] as Dictionary).duplicate()
	return {"device": "none", "code": 0, "trigger": "single"}


func set_binding(action: String, binding: Dictionary) -> void:
	_bindings[action] = {
		"device": str(binding.get("device", "key")),
		"code": int(binding.get("code", 0)),
		"trigger": str(binding.get("trigger", "single")),
	}
	keybindings_changed.emit()


func reset_to_defaults() -> void:
	_reset_memory_bindings()
	save_to_disk()
	keybindings_changed.emit()


func save_to_disk() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_bindings, "  "))
		f.close()


func load_from_disk() -> void:
	_reset_memory_bindings()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		for action in parsed:
			var entry = parsed[action]
			if entry is Dictionary:
				_bindings[str(action)] = {
					"device": str(entry.get("device", "key")),
					"code": int(entry.get("code", 0)),
					"trigger": str(entry.get("trigger", "single")),
				}


static func action_label(action: String) -> String:
	return ACTION_NAMES.get(action, action)


func set_action_trigger_mode(action: String, trigger_mode: String) -> void:
	var b: Dictionary = get_binding(action)
	b["trigger"] = trigger_mode
	set_binding(action, b)


func binding_key_only_text(action: String) -> String:
	var b := get_binding(action)
	var dev: String = b.get("device", "none")
	var code: int = int(b.get("code", 0))

	if dev == "mouse":
		match code:
			MOUSE_BUTTON_LEFT: return "鼠标左键"
			MOUSE_BUTTON_RIGHT: return "鼠标右键"
			MOUSE_BUTTON_MIDDLE: return "鼠标中键"
			_: return "鼠标按键%d" % code
	elif dev == "key":
		match code:
			KEY_SHIFT: return "Shift"
			KEY_CTRL: return "Ctrl"
			KEY_ALT: return "Alt"
			KEY_SPACE: return "空格 (Space)"
			KEY_ENTER: return "Enter"
			KEY_TAB: return "Tab"
			KEY_ESCAPE: return "ESC"
			_:
				var key_text := OS.get_keycode_string(code)
				return key_text if not key_text.is_empty() else "Key#%d" % code
	return "未绑定"


func binding_display_text(action: String) -> String:
	var b := get_binding(action)
	var trig: String = b.get("trigger", "single")
	var key_text := binding_key_only_text(action)
	if trig == "double_tap":
		return "双击 " + key_text
	return key_text


func binding_short_action_text(action: String) -> String:
	var b := get_binding(action)
	var dev: String = b.get("device", "none")
	var code: int = int(b.get("code", 0))
	var is_double: bool = (b.get("trigger", "single") == "double_tap")

	var prompt := ""
	if dev == "mouse":
		match code:
			MOUSE_BUTTON_LEFT: prompt = "点左键" if not is_double else "双击左键"
			MOUSE_BUTTON_RIGHT: prompt = "点右键" if not is_double else "双击右键"
			MOUSE_BUTTON_MIDDLE: prompt = "点中键" if not is_double else "双击中键"
			_: prompt = ("双击鼠标%d" if is_double else "点鼠标%d") % code
	elif dev == "key":
		var k := ""
		match code:
			KEY_SHIFT: k = "Shift"
			KEY_CTRL: k = "Ctrl"
			KEY_SPACE: k = "空格"
			_: k = OS.get_keycode_string(code)
		prompt = ("双击 %s" if is_double else "按 %s") % k
	else:
		prompt = "未绑定"
	return prompt


func get_action_for_mouse_button(index: int, is_double: bool = false) -> String:
	var trig := "double_tap" if is_double else "single"
	for action in _bindings:
		var b: Dictionary = _bindings[action]
		if b.get("device") == "mouse" and int(b.get("code")) == index and b.get("trigger") == trig:
			return action
	return ""
