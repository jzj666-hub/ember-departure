class_name WeaponConfig
extends RefCounted
## Reads, writes, and normalizes per-weapon JSON configurations.
## baseline settings are inherited from `_default.json`.
## Invariant: load_for() and normalise() always return a complete schema structure.

const DIR := "res://assets/combat_tools/configs"
const MESH_DIR := "res://assets/combat_tools"
const DEFAULT_ID := "_default"
const EXT := ".json"

## Bumped when a field changes meaning rather than when one is added - a missing
## field is filled by normalise() and needs no version at all.
const VERSION := 1

## Maximum action nodes per weapon graph (matches PlayerController transition count).
const MAX_ACTIONS := 8

## Accepted flatten mode strings, mirroring PlayerController.Flatten.
const FLATTEN_MODES := ["KEEP", "GROUND", "SETTLE", "ALL"]

## Default weapon model alignment roll in degrees (-90.0 about Z).
const DEFAULT_ROLL_DEG := -90.0


## Returns fallback weapon configuration dictionary.
static func defaults() -> Dictionary:
	return {
		"version": VERSION,
		"note": "",
		"grip": {
			"offset": [0.0, 0.0, 0.0],
			"rot_deg": [0.0, 0.0, DEFAULT_ROLL_DEG],
			"scale": 1.0,
			"flip": false,
			"socket": "right_hand",
		},
		"stance": {
			"idle_clip": "sword_idle",
			"blend": 1.0,
			"filter_bone": "Spine",
			"walk_clip": "",
			"run_clip": "",
		},
		# Blade afterimage. `base`/`tip` are fractions of the blade's length, not
		# metres: HandheldItem re-anchors every model to grip-at-origin/blade-up,
		# so the same pair lands correctly on any weapon at any item_scale.
		"trail": {
			"enabled": false,
			"base": 0.35,
			"tip": 1.0,
			"hue": 210.0,
			"hue_spread": 45.0,
			"energy": 2.4,
			"life": 0.22,
			"width": 1.0,
			"particles": 1.0,
			"light": 0.0,
			"min_speed": 3.0,
			"blend_mode": "add",
			"fade_exponent": 2.0,
			"ghost_density": 0.0,
			"texture_mode": "none",
		},
		"entries": [
			{"trigger": "attack", "to": "slash_1"},
		],
		"actions": [
			{
				"id": "slash_1",
				"clip": "sword_attack",
				"rate": 1.0,
				"flatten": "GROUND",
				"duration": 0.0,
				"lock_move": true,
				"dash_distance": 0.0,
				"trail": true,
				"trail_window": [0.0, 0.0],
				"links": [],
			},
		],
	}


# --- paths -----------------------------------------------------------------

static func path_for(weapon_id: String) -> String:
	return DIR.path_join(weapon_id + EXT)


static func has_config(weapon_id: String) -> bool:
	return FileAccess.file_exists(path_for(weapon_id))


## Returns names of all weapons with configured override files.
static func list_configured() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(EXT):
			var id := file_name.get_basename()
			if id != DEFAULT_ID:
				out.append(id)
		file_name = dir.get_next()
	out.sort()
	return out


## Loads and returns mesh PackedScene (FBX or GLB).
static func mesh_scene_for(weapon_id: String) -> PackedScene:
	for ext in [".fbx", ".glb"]:
		var path := MESH_DIR.path_join(weapon_id + ext)
		if ResourceLoader.exists(path):
			return load(path) as PackedScene
	return null


# --- reading ---------------------------------------------------------------

## Returns baseline weapon configuration.
static func baseline() -> Dictionary:
	return _merge(defaults(), _read_raw(path_for(DEFAULT_ID)))


## Returns complete configuration for a weapon (overrides baseline).
static func load_for(weapon_id: String) -> Dictionary:
	var own := _read_raw(path_for(weapon_id))
	return normalise(_own_note(_merge(baseline(), own), own))


## Parses weapon config from JSON text. Returns {ok, config, error}.
static func from_json(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"ok": false, "config": {}, "error": "第 %d 行: %s" % [
			json.get_error_line(), json.get_error_message()]}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {"ok": false, "config": {}, "error": "顶层必须是一个 JSON 对象 {...}"}
	var own: Dictionary = json.data
	return {"ok": true, "error": "",
		"config": normalise(_own_note(_merge(baseline(), own), own))}


## Merges note field directly from source without inheritance.
static func _own_note(merged: Dictionary, own: Dictionary) -> Dictionary:
	merged["note"] = String(own.get("note", ""))
	return merged


static func to_json(config: Dictionary) -> String:
	# sort_keys off: normalise() already fixed the key order, and its order groups
	# related fields together where alphabetical would scatter them. Stable either
	# way, which is what matters for the diff.
	return JSON.stringify(normalise(config), "\t", false)


## Reads raw JSON file content into Dictionary. Returns {} if missing/malformed.
static func _read_raw(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("WeaponConfig: %s is not a JSON object, ignoring it" % path)
		return {}
	return parsed


## Merges Dictionary fields recursively; overrides array/value fields.
static func _merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for key in over:
		var incoming = over[key]
		if typeof(incoming) == TYPE_DICTIONARY and typeof(out.get(key)) == TYPE_DICTIONARY:
			out[key] = _merge(out[key], incoming)
		else:
			out[key] = incoming
	return out


# --- writing ---------------------------------------------------------------

## Saves weapon configuration to JSON file. Returns error string or "".
static func save_for(weapon_id: String, config: Dictionary) -> String:
	if weapon_id.is_empty():
		return "没有选中武器"
	if DirAccess.make_dir_recursive_absolute(DIR) != OK and not DirAccess.dir_exists_absolute(DIR):
		return "无法创建 %s" % DIR
	var path := path_for(weapon_id)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "无法写入 %s (错误 %d)" % [path, FileAccess.get_open_error()]
	file.store_string(to_json(config) + "\n")
	file.close()
	return ""


# --- repair ----------------------------------------------------------------

## Normalizes configuration schema. Fills defaults, validates and clamps values. Idempotent.
static func normalise(config: Dictionary) -> Dictionary:
	var grip: Dictionary = config.get("grip", {}) if typeof(config.get("grip")) == TYPE_DICTIONARY else {}
	var stance: Dictionary = config.get("stance", {}) if typeof(config.get("stance")) == TYPE_DICTIONARY else {}
	var trail: Dictionary = config.get("trail", {}) if typeof(config.get("trail")) == TYPE_DICTIONARY else {}
	var fallback := defaults()

	var actions := []
	var seen := {}
	var raw_actions = config.get("actions")
	if typeof(raw_actions) == TYPE_ARRAY:
		for raw in raw_actions:
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var action := _normalise_action(raw, seen)
			if action.is_empty():
				continue
			if actions.size() >= MAX_ACTIONS:
				push_warning(("WeaponConfig: a weapon may hold %d action nodes, "
					+ "'%s' and everything after it were dropped") % [MAX_ACTIONS, action.id])
				break
			seen[action.id] = true
			actions.append(action)
	if actions.is_empty():
		actions = fallback.actions

	# Second pass: a link may point forwards, so targets can only be checked once
	# every id is known.
	var ids := {}
	for action in actions:
		ids[action.id] = true
	for action in actions:
		var kept := []
		for link in action.links:
			if ids.has(link.to):
				kept.append(link)
			else:
				push_warning("WeaponConfig: %s -> %s goes nowhere, dropped" % [
					action.id, link.to])
		action.links = kept

	var entries := []
	var claimed := {}
	var raw_entries = config.get("entries")
	if typeof(raw_entries) == TYPE_ARRAY:
		for raw in raw_entries:
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var trigger := _trigger(raw.get("trigger", ""))
			var to := String(raw.get("to", ""))
			# One entry per button: two would make the opening move depend on
			# array order, which is not something the editor shows.
			if trigger.is_empty() or claimed.has(trigger) or not ids.has(to):
				continue
			claimed[trigger] = true
			entries.append({"trigger": trigger, "to": to})
	if entries.is_empty():
		entries = [{"trigger": "attack", "to": actions[0].id}]

	return {
		"version": VERSION,
		# JSON cannot hold comments and these files are meant to be copied between
		# weapons and hand-edited, so one free-text line survives normalise() on
		# purpose. It is the only place a config can say why it is the way it is.
		"note": String(config.get("note", "")),
		"grip": {
			"offset": _vec3(grip.get("offset"), Vector3.ZERO),
			"rot_deg": _vec3(grip.get("rot_deg"), Vector3(0.0, 0.0, DEFAULT_ROLL_DEG)),
			"scale": clampf(float(grip.get("scale", 1.0)), 0.001, 100.0),
			"flip": bool(grip.get("flip", false)),
			"socket": String(grip.get("socket", "right_hand")),
		},
		"stance": {
			"idle_clip": String(stance.get("idle_clip", fallback.stance.idle_clip)),
			"blend": clampf(float(stance.get("blend", 1.0)), 0.0, 1.0),
			"filter_bone": String(stance.get("filter_bone", fallback.stance.filter_bone)),
			# Empty means "keep the bare-handed clip on that pole". The armed idle is
			# not optional in the same way: it is also the stance layer's take.
			"walk_clip": String(stance.get("walk_clip", "")),
			"run_clip": String(stance.get("run_clip", "")),
		},
		"trail": _normalise_trail(trail, fallback.trail),
		"entries": entries,
		"actions": actions,
	}


## The blade afterimage block. Every field is clamped to a range the runtime can
## draw, so WeaponTrail never has to check one. Post: base <= tip.
static func _normalise_trail(raw: Dictionary, fallback: Dictionary) -> Dictionary:
	var base := clampf(float(raw.get("base", fallback.base)), 0.0, 1.0)
	var tip := clampf(float(raw.get("tip", fallback.tip)), 0.0, 1.0)
	# Straightened out rather than rejected, same as an inverted link window: the
	# pair still names the segment that was meant, only end-first.
	if tip < base:
		var swap := base
		base = tip
		tip = swap
	return {
		"enabled": bool(raw.get("enabled", fallback.enabled)),
		"base": base,
		"tip": tip,
		# Wrapped, not clamped: hue is an angle, and 370 means 10.
		"hue": wrapf(float(raw.get("hue", fallback.hue)), 0.0, 360.0),
		# Half a turn is the whole family already - past that the two flanks meet
		# again on the other side and the gradient stops reading as one colour.
		"hue_spread": clampf(float(raw.get("hue_spread", fallback.hue_spread)), 0.0, 180.0),
		# Below 1 there is nothing for glow to pick up; the floor is only there to
		# keep the strip visible at all.
		"energy": clampf(float(raw.get("energy", fallback.energy)), 0.5, 8.0),
		"life": clampf(float(raw.get("life", fallback.life)), 0.03, 1.5),
		"width": clampf(float(raw.get("width", fallback.width)), 0.1, 4.0),
		"particles": clampf(float(raw.get("particles", fallback.particles)), 0.0, 4.0),
		"light": clampf(float(raw.get("light", fallback.light)), 0.0, 8.0),
		# Blade speed below which no sample is laid down, in m/s. 0 draws
		# everything, including the wind-up.
		"min_speed": clampf(float(raw.get("min_speed", fallback.min_speed)), 0.0, 30.0),
		"blend_mode": _normalise_choice(raw.get("blend_mode", fallback.blend_mode), ["add", "mix", "sub"], "add"),
		"fade_exponent": clampf(float(raw.get("fade_exponent", fallback.fade_exponent)), 0.5, 4.0),
		"ghost_density": clampf(float(raw.get("ghost_density", fallback.ghost_density)), 0.0, 2.0),
		"texture_mode": _normalise_choice(raw.get("texture_mode", fallback.texture_mode), ["none", "noise", "stripes"], "none"),
	}


## One action node, or {} if it cannot be salvaged. `seen` holds the ids already
## taken, because a duplicate id would make slot_of() ambiguous.
static func _normalise_action(raw: Dictionary, seen: Dictionary) -> Dictionary:
	var id := String(raw.get("id", "")).strip_edges()
	var clip := String(raw.get("clip", "")).strip_edges()
	if id.is_empty() or clip.is_empty() or seen.has(id):
		return {}

	var flatten := String(raw.get("flatten", "GROUND")).to_upper()
	if not FLATTEN_MODES.has(flatten):
		flatten = "GROUND"

	var links := []
	var raw_links = raw.get("links")
	if typeof(raw_links) == TYPE_ARRAY:
		for raw_link in raw_links:
			if typeof(raw_link) != TYPE_DICTIONARY:
				continue
			var link := _normalise_link(raw_link)
			if not link.is_empty():
				links.append(link)

	return {
		"id": id,
		"clip": clip,
		# A rate of zero would make the take never end and the duration divide by
		# it, so the floor is small rather than absent.
		"rate": clampf(float(raw.get("rate", 1.0)), 0.05, 8.0),
		"flatten": flatten,
		# 0 means "as long as the clip is". Resolved by the controller, which is
		# the only thing that knows how long that is.
		"duration": maxf(0.0, float(raw.get("duration", 0.0))),
		"lock_move": bool(raw.get("lock_move", true)),
		# How far the lunge carries, in metres. A distance rather than a speed: how
		# fast it is covered is PlayerController.dash_speed, one number for every
		# weapon. 0 - the common case - is no lunge at all.
		"dash_distance": clampf(float(raw.get("dash_distance",
			_legacy_distance(raw))), 0.0, 12.0),
		"trail": bool(raw.get("trail", true)),
		# Seconds into the take the blade afterimage is allowed to draw. [0, 0] -
		# the default - is the whole take, leaving trail.min_speed to decide which
		# part of it actually reads as a swing.
		"trail_window": _window(raw.get("trail_window")),
		"links": links,
	}


## A [start, end] pair in seconds, or `fallback` when the file holds no usable
## one. Post: 0 <= start <= end. An inverted pair is straightened out rather than
## dropped - it would otherwise accept nothing and read as a broken trigger
## rather than as a typo.
static func _window(value, fallback := [0.0, 0.0]) -> Array:
	var start := float(fallback[0])
	var end := float(fallback[1])
	if typeof(value) == TYPE_ARRAY and value.size() >= 2:
		start = maxf(0.0, float(value[0]))
		end = maxf(0.0, float(value[1]))
	if end < start:
		var swap := start
		start = end
		end = swap
	return [start, end]


## What a lunge covered back when it was a peak speed held for a duration.
## Configs written before those two fields became one distance land here once,
## and are written back in the new shape the next time they are saved.
static func _legacy_distance(raw: Dictionary) -> float:
	return maxf(0.0, float(raw.get("slide_speed", 0.0))
		* float(raw.get("slide_time", 0.0)))


## One link, or {} if it names no trigger or no target. The target's existence is
## checked by the caller, once every id is known.
static func _normalise_link(raw: Dictionary) -> Dictionary:
	var trigger := _trigger(raw.get("trigger", ""))
	var to := String(raw.get("to", "")).strip_edges()
	if trigger.is_empty() or to.is_empty():
		return {}

	return {
		"trigger": trigger,
		"window": _window(raw.get("window"), [0.0, 1.0]),
		"buffer": bool(raw.get("buffer", true)),
		"to": to,
	}


## A button name, or "" if it is not one CharacterIntent knows.
static func _trigger(value) -> String:
	var name := String(value).strip_edges()
	return name if CharacterIntent.BUTTONS.has(name) else ""


## Three floats out of whatever was in the file - an array, a Vector3, or
## nothing.
static func _vec3(value, fallback: Vector3) -> Array:
	if typeof(value) == TYPE_VECTOR3:
		return [value.x, value.y, value.z]
	if typeof(value) == TYPE_ARRAY and value.size() >= 3:
		return [float(value[0]), float(value[1]), float(value[2])]
	return [fallback.x, fallback.y, fallback.z]


static func _normalise_choice(value, choices: Array, fallback: String) -> String:
	var val := String(value).strip_edges().to_lower()
	return val if choices.has(val) else fallback


# --- handing over to the runtime -------------------------------------------

static func offset_of(config: Dictionary) -> Vector3:
	var v: Array = config.grip.offset
	return Vector3(v[0], v[1], v[2])


static func rotation_of(config: Dictionary) -> Vector3:
	var v: Array = config.grip.rot_deg
	return Vector3(deg_to_rad(v[0]), deg_to_rad(v[1]), deg_to_rad(v[2]))


static func grip_transform(config: Dictionary) -> Transform3D:
	return Transform3D(Basis.from_euler(rotation_of(config)), offset_of(config))


## The runtime handoff. ItemData is what HandheldItem and EquipmentManager
## already speak; this is the only place that turns a file into one.
static func to_item_data(weapon_id: String, config: Dictionary,
		mesh_scene: PackedScene = null) -> ItemData:
	var normalised := normalise(config)
	var data := ItemData.new()
	data.item_id = weapon_id
	data.display_name = weapon_id
	data.mesh_scene = mesh_scene if mesh_scene != null else mesh_scene_for(weapon_id)
	data.grip_transform = grip_transform(normalised)
	data.item_scale = normalised.grip.scale
	data.flip_grip = normalised.grip.flip
	data.default_socket = normalised.grip.socket
	data.stance_clip = normalised.stance.idle_clip
	data.stance_blend = normalised.stance.blend
	data.stance_filter_bone = normalised.stance.filter_bone
	data.stance_walk_clip = normalised.stance.walk_clip
	data.stance_run_clip = normalised.stance.run_clip
	data.trail = normalised.trail
	data.graph = normalised
	return data
