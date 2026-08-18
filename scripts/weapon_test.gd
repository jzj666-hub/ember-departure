extends Node3D
## Interactive weapon tuning and configuration tester scene.
## Saves resulting configurations to JSON files in `assets/combat_tools/configs/`.

const CharacterPipelineScript = preload("res://tools/character_pipeline.gd")
const PlayerControllerScript = preload("res://scripts/player_controller.gd")
const PlayerIntentSourceScript = preload("res://scripts/player_intent_source.gd")
const FollowCameraScript = preload("res://scripts/follow_camera.gd")
const EquipmentManagerScript = preload("res://scripts/equipment_manager.gd")
const DummyTargetScript = preload("res://scripts/dummy_target.gd")

const MENU_SCENE := "res://scenes/main_menu.tscn"
const SPAWN := Vector3(0.0, 0.2, 0.0)

const LIST_WIDTH := 232.0
const TUNER_WIDTH := 300.0
const MARGIN := 12.0

## Target ratio of weapon length to character height.
const FIT_RATIO := 0.6

## The right button does two jobs: held it turns the view, tapped it swings the
## heavy attack. Longest a press may last, and furthest the pointer may drift
## while it does, and still count as a tap rather than a look.
const RIGHT_TAP_TIME := 0.22
const RIGHT_TAP_DRIFT := 6.0

## Indicator character for custom configured weapons.
const CONFIGURED_MARK := "● "

## Flat damage the F1 dummy takes per stroke. Not per weapon yet - when
## WeaponConfig grows a damage field, read it here instead.
const HIT_DAMAGE := 20.0
## The blade is a segment between two anchors, but a real one has width, and the
## anchors sit inside the mesh. Thickens the segment for the hit test.
const BLADE_PAD := 0.12

## Clip pickers on the tuner: [stance field, section label, may be empty].
## idle_clip is not optional - it is the stance take and the armed idle pole.
const STANCE_PICKERS := [
	["idle_clip", "持械站姿 / Stance idle", false],
	["walk_clip", "持械走 / Stance walk", true],
	["run_clip", "持械跑 / Stance run", true],
]
## What an empty optional clip reads as: that pole keeps the bare-handed take.
const CLIP_INHERIT := "（沿用空手动作）"

## Panel names, as _panels is keyed and _toggle_panel() addresses them.
const PANEL_LIST := "list"
const PANEL_TUNER := "tuner"
const PANEL_STATUS := "status"
const PANEL_GRAPH := "graph"
## Key -> panel it shows and hides. L is not here: it takes all of them at once.
const PANEL_KEYS := {
	KEY_J: PANEL_LIST,
	KEY_K: PANEL_TUNER,
	KEY_B: PANEL_GRAPH,
}

## Slider widgets config for adjusting grip offsets and scales.
const TUNER := [
	["tx", "X 偏移", -0.4, 0.4, 0.001, "m"],
	["ty", "Y 偏移", -0.4, 0.4, 0.001, "m"],
	["tz", "Z 偏移", -0.4, 0.4, 0.001, "m"],
	["rx", "Pitch X", -180.0, 180.0, 1.0, "°"],
	["ry", "Yaw Y", -180.0, 180.0, 1.0, "°"],
	["rz", "Roll Z", -180.0, 180.0, 1.0, "°"],
	["scale", "缩放", 0.05, 2.0, 0.005, "x"],
]

## Trail sliders, same row shape as TUNER. Keys are the `trail` block's own, so
## _read_trail() copies them across by name and no mapping table is needed.
## Ranges mirror WeaponConfig._normalise_trail()'s clamps.
const TRAIL_TUNER := [
	["base", "近端", 0.0, 1.0, 0.01, ""],
	["tip", "远端", 0.0, 1.0, 0.01, ""],
	["hue", "色相", 0.0, 359.0, 1.0, "°"],
	["hue_spread", "展宽", 0.0, 180.0, 1.0, "°"],
	["energy", "亮度", 0.5, 8.0, 0.1, "x"],
	["life", "拖尾", 0.03, 1.5, 0.01, "s"],
	["width", "带宽", 0.1, 4.0, 0.05, "x"],
	["particles", "粒子", 0.0, 4.0, 0.05, "x"],
	["light", "光源", 0.0, 8.0, 0.1, ""],
	["min_speed", "刃速", 0.0, 30.0, 0.5, "m/s"],
	["fade_exponent", "衰减", 0.5, 4.0, 0.1, "x"],
	["ghost_density", "残影", 0.0, 2.0, 0.1, "x"],
]

## Colour family buttons: [TrailPalette.PRESETS id, label]. Each fills hue and
## hue_spread; everything else about the gradient is derived from those two.
const TRAIL_PRESETS := [
	["ember", "余烬"],
	["frost", "霜蓝"],
	["void", "虚空"],
	["blood", "血红"],
	["gold", "圣金"],
	["toxic", "剧毒"],
]

## Dash effect labels, in PlayerController.DashVfx order. Item index == enum value.
const DASH_VFX_NAMES := ["无", "光束残影", "淡出淡回"]
const BLEND_MODE_NAMES := [["add", "加色 (ADD)"], ["mix", "混合 (MIX)"], ["sub", "减色 (SUB)"]]
const TEXTURE_MODE_NAMES := [["none", "无纹理"], ["noise", "能量噪声"], ["stripes", "光线条纹"]]

var _characters: Array = []
var _index := 0
var _player: CharacterBody3D
var _camera: Camera3D
var _visual: Node3D
var _equipment_manager: EquipmentManager

var _weapons: Array[String] = []
var _selected_weapon_file := ""
## Currently active weapon configuration dictionary.
var _config := {}
## Mutex flag to prevent slider change events during config loads.
var _loading := false
## Flag tracking active mouse capture status.
var _looking := false
## Seconds the right button has been down, and how far the pointer has travelled
## since it went down. Negative time means the button is up.
var _right_held := -1.0
var _right_drift := 0.0

var _state_label: Label
var _hint_label: Label
var _measure_label: Label
var _save_label: Label
var _list_box: VBoxContainer
var _filter_edit: LineEdit
## OptionButton per STANCE_PICKERS entry, keyed by its stance field.
var _stance_pickers := {}
var _reference_picker: OptionButton
## Dash widgets. Bound to the controller, not to _config - see _build_dash().
var _dash_picker: OptionButton
var _dash_speed: HSlider
var _dash_speed_label: Label
## Trail widgets. Bound to _config.trail, so they are saved with the weapon.
var _trail_toggle: CheckBox
var _trail_ramp: TextureRect
var _blend_picker: OptionButton
var _texture_picker: OptionButton
## Whether the two blade markers are drawn. Off is for looking at the weapon.
var _show_anchors := true
var _graph_editor: WeaponGraphEditor
var _sliders := {}
var _slider_labels := {}
## Every toggleable HUD panel, keyed by PANELS name. Filled by _panel().
var _panels := {}
## Whether every panel is hidden for a clean look at the character.
var _immersive := false
## Per-panel visibility from before immersive mode, so L restores the layout that
## was there rather than a default one. Invariant: only read while _immersive.
var _restore := {}
## Config fingerprints for the copy-from list: weapon id -> [modified time, key].
## See _fingerprint_of().
var _fingerprints := {}

var _dummy: DummyTarget
## Blade tip last frame, for the swing direction the crescent is drawn along.
## Invariant: only meaningful while _has_prev_tip.
var _prev_tip := Vector3.ZERO
var _has_prev_tip := false
## Whether the blade was overlapping the dummy last frame. A hit is the rising
## edge, so a weapon action that strikes three times lands three hits, and a
## blade that rests inside the capsule still lands one.
var _blade_inside := false
## Last stroke seen, only to re-arm the edge: a fresh swing always may hit.
var _last_stroke := -1


func _ready() -> void:
	_characters = CharacterPipelineScript.list_characters().filter(
		func(c: Dictionary) -> bool: return ResourceLoader.exists(c.scene))
	if _characters.is_empty():
		push_error("no character scenes - run tools\\rebuild_assets.bat first")
		return

	_scan_weapons()
	_build_environment()
	_build_ground()
	_build_hud()
	_build_player()

	# After the camera, not before: FollowCamera captures the pointer in its own
	# _ready(), and this scene wants it visible so the panels can be clicked.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if not _weapons.is_empty():
		_select_weapon(_weapons[1] if _weapons.size() > 1 else _weapons[0])


func _scan_weapons() -> void:
	_weapons.clear()
	_weapons.append("none")
	var fbx_files := PackedStringArray()
	var dir := DirAccess.open("res://assets/combat_tools")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			var clean_name := file_name.trim_suffix(".import").trim_suffix(".remap")
			if not dir.current_is_dir() and (clean_name.ends_with(".fbx") or clean_name.ends_with(".glb")):
				if not fbx_files.has(clean_name):
					fbx_files.append(clean_name)
			file_name = dir.get_next()
	fbx_files.sort()
	_weapons.append_array(fbx_files)


func _weapon_id() -> String:
	return _selected_weapon_file.get_basename()


# --- world setup -----------------------------------------------------------

func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.24, 0.32, 0.47)
	sky_material.sky_horizon_color = Color(0.58, 0.60, 0.63)
	sky_material.ground_bottom_color = Color(0.12, 0.12, 0.14)
	sky_material.ground_horizon_color = Color(0.58, 0.60, 0.63)

	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.6
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled = true
	# Without this the trail's `energy` above 1 is indistinguishable from 1: the
	# HDR headroom is where the whole bright-core look lives.
	environment.glow_enabled = true
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	environment.glow_intensity = 0.9
	environment.glow_bloom = 0.15
	environment.glow_hdr_threshold = 1.0

	var node := WorldEnvironment.new()
	node.name = "WorldEnvironment"
	node.environment = environment
	add_child(node)

	add_child(_make_light("KeyLight", -45.0, -30.0, 2.0, true))
	add_child(_make_light("FillLight", -15.0, 150.0, 0.5, false))


func _make_light(light_name: String, pitch_deg: float, yaw_deg: float,
		energy: float, shadows: bool) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = light_name
	light.light_energy = energy
	light.shadow_enabled = shadows
	light.transform.basis = Basis.from_euler(
		Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0.0))
	light.position = Vector3(0.0, 6.0, 0.0)
	return light


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"

	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80.0, 80.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.15, 0.16, 0.18)
	material.roughness = 0.95
	plane.material = material
	mesh.mesh = plane
	body.add_child(mesh)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 0.4, 80.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.2, 0.0)
	body.add_child(shape)
	add_child(body)

	# Simple grid
	var grid := ImmediateMesh.new()
	grid.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(-40, 41):
		var major := i % 10 == 0
		var colour := Color(0.42, 0.47, 0.56, 0.5) if major else Color(0.30, 0.32, 0.36, 0.2)
		grid.surface_set_color(colour)
		grid.surface_add_vertex(Vector3(i, 0.003, -40))
		grid.surface_add_vertex(Vector3(i, 0.003, 40))
		grid.surface_set_color(colour)
		grid.surface_add_vertex(Vector3(-40, 0.003, i))
		grid.surface_add_vertex(Vector3(40, 0.003, i))
	grid.surface_end()

	var grid_material := StandardMaterial3D.new()
	grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_material.vertex_color_use_as_albedo = true
	grid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var grid_node := MeshInstance3D.new()
	grid_node.name = "Grid"
	grid_node.mesh = grid
	grid_node.material_override = grid_material
	add_child(grid_node)


# --- player setup ----------------------------------------------------------

func _build_player() -> void:
	_player = PlayerControllerScript.new()
	_player.name = "Player"
	_player.position = SPAWN
	_player.intent_source = PlayerIntentSourceScript.new()
	add_child(_player)

	_camera = FollowCameraScript.new()
	_camera.name = "Camera"
	_camera.fov = 55.0
	_camera.near = 0.05
	_camera.current = true
	add_child(_camera)

	_spawn_character()
	# The panel is built before the controller exists, so its dash widgets start
	# blank and are filled from the controller's own defaults here.
	_sync_dash()


func _spawn_character() -> void:
	if _visual != null:
		_visual.queue_free()
		_visual = null
	for child in _player.get_children():
		if child is CollisionShape3D:
			child.queue_free()
		elif child is EquipmentManager:
			child.queue_free()

	_equipment_manager = EquipmentManagerScript.new()
	_equipment_manager.name = "EquipmentManager"
	_player.add_child(_equipment_manager)

	var entry: Dictionary = _characters[_index]
	var scene := load(entry.scene) as PackedScene
	if scene == null:
		push_error("%s: scene will not load" % entry.id)
		return
	_visual = scene.instantiate() as Node3D
	_player.add_child(_visual)

	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	var height := _body_height()
	capsule.radius = minf(0.3, height * 0.2)
	capsule.height = height
	collider.shape = capsule
	collider.position.y = height * 0.5
	_player.add_child(collider)

	_player.velocity = Vector3.ZERO
	_player.setup(_visual, _camera)
	_camera.target = _player
	_camera.frame_for(height)
	_camera.snap()

	_refresh_clip_choices()
	_refresh_hud_text()
	_equip_current_weapon()


func _body_height() -> float:
	if _visual == null:
		return 1.75
	var height: float = _visual.get("body_height")
	return height if height > 0.1 else 1.75


## Cached animation clip list for current character.
func _refresh_clip_choices() -> void:
	if _visual == null:
		return
	var names: PackedStringArray = _visual.call("clip_names")
	var bare := {}
	for full in names:
		bare[String(full).get_file()] = true
	var sorted := PackedStringArray(bare.keys())
	sorted.sort()

	if _graph_editor != null:
		_graph_editor.set_clips(sorted)
	for field in _stance_pickers:
		var picker: OptionButton = _stance_pickers[field]
		picker.clear()
		if _optional_clip(field):
			picker.add_item(CLIP_INHERIT)
		for clip in sorted:
			picker.add_item(clip)
	_select_stance_items()


# --- the configuration -----------------------------------------------------

## Loads and activates weapon config from disk.
##
## The list redraw is deferred: this runs from a list button's own `pressed`, and
## _rebuild_list() frees that button. Same hazard as WeaponGraphEditor._commit().
func _select_weapon(weapon_file: String) -> void:
	_selected_weapon_file = weapon_file
	_config = WeaponConfig.load_for(_weapon_id())
	_apply_config()
	_rebuild_list.call_deferred()


## Pushes `_config` into every control, then onto the character.
func _apply_config() -> void:
	_loading = true
	var offset := WeaponConfig.offset_of(_config)
	var rot: Array = _config.grip.rot_deg
	_set_value("tx", offset.x)
	_set_value("ty", offset.y)
	_set_value("tz", offset.z)
	_set_value("rx", rot[0])
	_set_value("ry", rot[1])
	_set_value("rz", rot[2])
	_set_value("scale", _config.grip.scale)
	for row in TUNER:
		_format_slider_label(row[0])
	for row in TRAIL_TUNER:
		var key := String(row[0])
		_set_value(key, float(_config.trail.get(key, 0.0)))
		_format_slider_label(key)
	if _trail_toggle != null:
		_trail_toggle.button_pressed = bool(_config.trail.enabled)
	_sync_trail_pickers()
	_refresh_trail_ramp()
	_select_stance_items()
	if _graph_editor != null:
		_graph_editor.show_config(_config)
	_loading = false
	_equip_current_weapon()


func _sync_trail_pickers() -> void:
	if _config.is_empty():
		return
	if _blend_picker != null:
		var mode := String(_config.trail.get("blend_mode", "add"))
		for i in BLEND_MODE_NAMES.size():
			if BLEND_MODE_NAMES[i][0] == mode:
				_blend_picker.selected = i
				break
	if _texture_picker != null:
		var tex := String(_config.trail.get("texture_mode", "none"))
		for i in TEXTURE_MODE_NAMES.size():
			if TEXTURE_MODE_NAMES[i][0] == tex:
				_texture_picker.selected = i
				break


## The reverse: whatever the sliders say, into `_config`.
func _read_sliders() -> void:
	_config.grip.offset = [_value("tx"), _value("ty"), _value("tz")]
	_config.grip.rot_deg = [_value("rx"), _value("ry"), _value("rz")]
	_config.grip.scale = _value("scale")


func _equip_current_weapon() -> void:
	if _equipment_manager == null or _selected_weapon_file.is_empty():
		return
	var mesh: PackedScene = null
	if _selected_weapon_file != "none":
		mesh = load("res://assets/combat_tools/" + _selected_weapon_file) as PackedScene
	_equipment_manager.equip(
		WeaponConfig.to_item_data(_weapon_id(), _config, mesh))
	_refresh_readouts()


## Pushes the sliders onto the item already equipped, without rebuilding it.
func _update_weapon_transform() -> void:
	var item := _equipped()
	if item != null:
		item.set_grip(WeaponConfig.grip_transform(_config))
		item.set_item_scale(_config.grip.scale)
		item.set_flip(_config.grip.flip)
	_refresh_readouts()


## Updates stance and graph behaviors on controller dynamically.
func _update_weapon_behaviour() -> void:
	if _equipment_manager == null:
		return
	_equipment_manager.apply_behaviour(
		WeaponConfig.to_item_data(_weapon_id(), _config, null))
	_refresh_readouts()


func _equipped() -> HandheldItem:
	return _equipment_manager.equipped("right_hand") if _equipment_manager != null else null


## Whether what is on screen matches what is on disk.
func _is_saved() -> bool:
	return WeaponConfig.has_config(_weapon_id()) \
		and WeaponConfig.load_for(_weapon_id()) == _config


func _save() -> void:
	var error := WeaponConfig.save_for(_weapon_id(), _config)
	if error.is_empty():
		_report("已保存 %s.json" % _weapon_id())
		_rebuild_list()
	else:
		# res:// is only writable from a project directory. Said out loud, because
		# a silent failure here looks exactly like a successful save.
		_report("保存失败: %s" % error)
	_refresh_readouts()


func _revert() -> void:
	_config = WeaponConfig.load_for(_weapon_id())
	_apply_config()
	_report("已还原到磁盘上的版本")


## Pastes copy-reference weapon config over current config.
func _copy_from(other_id: String) -> void:
	if other_id.is_empty() or other_id == _weapon_id():
		return
	_config = WeaponConfig.load_for(other_id)
	_apply_config()
	_report("已粘贴 %s 的配置，按保存写盘" % other_id)


func _reset_tuner() -> void:
	_config = WeaponConfig.baseline()
	_apply_config()
	_report("已复位到基线 _default.json")


## Re-scales weapon model to match FIT_RATIO of character height.
func _fit_to_height() -> void:
	var item := _equipped()
	if item == null or item.measured_length() <= 0.0:
		return
	_set_value("scale", _body_height() * FIT_RATIO / item.measured_length())


func _toggle_flip() -> void:
	_config.grip.flip = not _config.grip.flip
	_update_weapon_transform()


# --- hud construction ------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)

	_build_weapon_list(_panel(layer, PANEL_LIST, MARGIN, MARGIN,
		MARGIN + LIST_WIDTH, -MARGIN, Vector2(0, 0), Vector2(0, 1)))
	_build_tuner(_panel(layer, PANEL_TUNER, -(MARGIN + TUNER_WIDTH), MARGIN,
		-MARGIN, -MARGIN, Vector2(1, 0), Vector2(1, 1)))
	_build_status(_panel(layer, PANEL_STATUS, LIST_WIDTH + MARGIN * 2, MARGIN,
		LIST_WIDTH + MARGIN * 2 + 460.0, MARGIN, Vector2(0, 0), Vector2(0, 0)))
	_build_graph_panel(layer)

	_refresh_hud_text()


## One anchored panel, registered under `key` so J/K/B/L can show and hide it.
## Returns the box its contents go in.
func _panel(layer: CanvasLayer, key: String, left: float, top: float,
		right: float, bottom: float, anchor_min: Vector2,
		anchor_max: Vector2) -> VBoxContainer:
	var panel := PanelContainer.new()
	layer.add_child(panel)
	panel.anchor_left = anchor_min.x
	panel.anchor_top = anchor_min.y
	panel.anchor_right = anchor_max.x
	panel.anchor_bottom = anchor_max.y
	panel.offset_left = left
	panel.offset_top = top
	panel.offset_right = right
	panel.offset_bottom = bottom
	# Containers pass clicks through by default, so without this a click on the
	# panel's background also reaches _unhandled_input and swings the sword.
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panels[key] = panel

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	return box


## Shows or hides one panel. Asking for a panel while immersive leaves immersive
## rather than doing nothing, or the key looks dead.
func _toggle_panel(key: String) -> void:
	var panel := _panels.get(key) as PanelContainer
	if panel == null:
		return
	if _immersive:
		_set_immersive(false)
		panel.visible = true
	else:
		panel.visible = not panel.visible
	_refresh_hud_text()


## Hides every panel, or puts back exactly what was showing before. Immersive also
## takes the pointer, so the view turns on mouse move with nothing held down.
## Leaving hands it back - the panels are unclickable without a cursor.
func _set_immersive(on: bool) -> void:
	if on == _immersive:
		return
	_immersive = on
	for key in _panels:
		var panel := _panels[key] as PanelContainer
		if on:
			_restore[key] = panel.visible
			panel.visible = false
		else:
			panel.visible = bool(_restore.get(key, true))
	# Same reason _set_looking() does it: capturing warps the pointer, and the
	# delta that arrives with the warp would snap the view a screen's width.
	if on and _camera != null:
		_camera.set("_swallow_first_motion", true)
	_refresh_mouse_mode()
	_refresh_hud_text()


## The behaviour graph panel. Full screen and drawn last, so it sits over the
## other three - it is an editor, not a sidebar, and the node map needs the room.
## Starts hidden. Toggled by B like the others, through _panels.
func _build_graph_panel(layer: CanvasLayer) -> void:
	var box := _panel(layer, PANEL_GRAPH, MARGIN, MARGIN, -MARGIN, -MARGIN,
		Vector2(0, 0), Vector2(1, 1))
	(_panels[PANEL_GRAPH] as PanelContainer).visible = false

	_graph_editor = WeaponGraphEditor.new()
	_graph_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph_editor.changed.connect(_on_graph_changed)
	box.add_child(_graph_editor)


func _on_graph_changed(config: Dictionary) -> void:
	_config = config
	_update_weapon_behaviour()


func _build_weapon_list(box: VBoxContainer) -> void:
	box.add_child(_title("武器列表 / Weapons  (J, %d)" % _weapons.size()))
	box.add_child(HSeparator.new())

	_filter_edit = LineEdit.new()
	_filter_edit.placeholder_text = "筛选 / filter"
	_filter_edit.clear_button_enabled = true
	_filter_edit.add_theme_font_size_override("font_size", 11)
	_filter_edit.text_changed.connect(func(_t: String) -> void: _rebuild_list())
	box.add_child(_filter_edit)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 1)
	scroll.add_child(_list_box)
	_rebuild_list()


func _rebuild_list() -> void:
	if _list_box == null:
		return
	for child in _list_box.get_children():
		_list_box.remove_child(child)
		child.queue_free()

	var configured := {}
	for id in WeaponConfig.list_configured():
		configured[id] = true
	_refresh_reference_choices(configured)

	var needle := _filter_edit.text.strip_edges().to_lower() if _filter_edit else ""
	for weapon_file in _weapons:
		if not needle.is_empty() and not weapon_file.to_lower().contains(needle):
			continue
		var id := weapon_file.get_basename()
		var display_label := "none (空手)" if weapon_file == "none" else id
		var btn := Button.new()
		btn.text = (CONFIGURED_MARK if configured.has(id) else "") + display_label
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 11)
		btn.toggle_mode = true
		btn.button_pressed = weapon_file == _selected_weapon_file
		btn.pressed.connect(func() -> void: _select_weapon(weapon_file))
		_list_box.add_child(btn)


## The copy-from list: one row per distinct config, not per configured weapon.
##
## Weapons whose files agree in every field but the note collapse onto whichever
## of them sorts first, with the others counted in the label - picking between
## two identical references is a choice with no consequence, and the list is long
## enough already. The row carries the real id in its metadata, because the label
## may have a "+N 把相同" tail on it.
func _refresh_reference_choices(configured: Dictionary) -> void:
	if _reference_picker == null:
		return
	var previous := _selected_reference()
	_reference_picker.clear()

	var ids := PackedStringArray(configured.keys())
	ids.sort()
	var shown := {}   ## fingerprint -> the id standing for it
	var others := {}  ## that id -> how many more agree with it
	for id in ids:
		if id == _weapon_id():
			continue
		var key := _fingerprint_of(id)
		if shown.has(key):
			var stands_for: String = shown[key]
			others[stands_for] = int(others.get(stands_for, 0)) + 1
			continue
		shown[key] = id

	for key in shown:
		var id: String = shown[key]
		var extra := int(others.get(id, 0))
		_reference_picker.add_item(id if extra == 0
			else "%s (+%d 把相同)" % [id, extra])
		var at := _reference_picker.item_count - 1
		_reference_picker.set_item_metadata(at, id)
		if id == previous:
			_reference_picker.selected = at


## The weapon id behind the selected row, or "".
func _selected_reference() -> String:
	if _reference_picker == null or _reference_picker.selected < 0:
		return ""
	var meta = _reference_picker.get_item_metadata(_reference_picker.selected)
	return String(meta) if meta != null else ""


## What makes two weapons "the same config": everything but the note, which
## describes the file rather than the weapon. Cached against the file's modified
## time - _rebuild_list() runs on every keystroke in the filter box, and this
## would otherwise re-read and re-parse every config file each time.
func _fingerprint_of(weapon_id: String) -> String:
	var stamp := FileAccess.get_modified_time(WeaponConfig.path_for(weapon_id))
	var cached: Array = _fingerprints.get(weapon_id, [])
	if cached.size() == 2 and int(cached[0]) == stamp:
		return String(cached[1])
	var config := WeaponConfig.load_for(weapon_id)
	config.note = ""
	var key := WeaponConfig.to_json(config)
	_fingerprints[weapon_id] = [stamp, key]
	return key


func _build_tuner(box: VBoxContainer) -> void:
	box.add_child(_title("武器配置 / Weapon Config  (K)"))
	box.add_child(HSeparator.new())

	_measure_label = Label.new()
	_measure_label.add_theme_font_size_override("font_size", 11)
	_measure_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_measure_label.modulate = Color(0.75, 0.85, 1.0)
	box.add_child(_measure_label)

	# Everything below the readout scrolls, so a group can be added without
	# having to find room for it. The panel is full height whatever the window is.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	scroll.add_child(body)

	var grip := _fold(body, "握持 / Grip", true)
	grip.add_child(_section("位移 / Translation (m)"))
	for row in TUNER.slice(0, 3):
		_add_slider(grip, row)
	grip.add_child(_section("旋转 / Rotation (Euler °)"))
	for row in TUNER.slice(3, 6):
		_add_slider(grip, row)
	grip.add_child(_section("缩放 / Scale"))
	_add_slider(grip, TUNER[6])

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	grip.add_child(buttons)
	buttons.add_child(_button("适配身高 (G)", _fit_to_height))
	buttons.add_child(_button("翻转 (F)", _toggle_flip))
	buttons.add_child(_button("复位 (R)", _reset_tuner))

	var stance := _fold(body, "持械动作 / Stance", true)
	for row in STANCE_PICKERS:
		stance.add_child(_section(row[1]))
		stance.add_child(_clip_picker(row[0]))

	_build_dash(_fold(body, "冲刺 / Dash", true))
	_build_trail(_fold(body, "残影 / Trail", true))

	# Open by default: _save_label is also where _report() says whether a save
	# landed, and a folded-away failure reads exactly like a successful one.
	var save := _fold(body, "存盘 / Save", true)
	_save_label = Label.new()
	_save_label.add_theme_font_size_override("font_size", 11)
	_save_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	save.add_child(_save_label)

	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 4)
	save.add_child(save_row)
	save_row.add_child(_button("保存 (Ctrl+S)", _save))
	save_row.add_child(_button("还原", _revert))

	save.add_child(_section("参考别的武器 / Copy from"))
	var copy_row := HBoxContainer.new()
	copy_row.add_theme_constant_override("separation", 4)
	save.add_child(copy_row)
	_reference_picker = OptionButton.new()
	_reference_picker.add_theme_font_size_override("font_size", 11)
	_reference_picker.fit_to_longest_item = false
	_reference_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy_row.add_child(_reference_picker)
	copy_row.add_child(_button("整份粘贴", func() -> void:
		_copy_from(_selected_reference())))


## Controller-level dash knobs: the same for every weapon, so nothing here is
## saved to the weapon's JSON. Written straight to the controller.
## Pre: _player may still be null - the panel is built first. See _sync_dash().
func _build_dash(box: VBoxContainer) -> void:
	box.add_child(_section("特效 / Effect"))
	_dash_picker = OptionButton.new()
	_dash_picker.add_theme_font_size_override("font_size", 11)
	_dash_picker.fit_to_longest_item = false
	for label in DASH_VFX_NAMES:
		_dash_picker.add_item(label)
	# Item index is the DashVfx value, which is what keeps this list honest.
	_dash_picker.item_selected.connect(func(index: int) -> void:
		if _player != null:
			_player.dash_vfx = index)
	box.add_child(_dash_picker)

	box.add_child(_section("速度 / Speed (m/s)"))
	var row := HBoxContainer.new()
	box.add_child(row)

	_dash_speed = HSlider.new()
	_dash_speed.min_value = 2.0
	_dash_speed.max_value = 14.0
	_dash_speed.step = 0.1
	_dash_speed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_dash_speed)

	_dash_speed_label = Label.new()
	_dash_speed_label.custom_minimum_size = Vector2(56, 0)
	_dash_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dash_speed_label.add_theme_font_size_override("font_size", 11)
	row.add_child(_dash_speed_label)

	_dash_speed.value_changed.connect(func(v: float) -> void:
		_dash_speed_label.text = "%.1f" % v
		if _player != null:
			_player.dash_speed = v)


## Fills the dash widgets from the controller's own defaults, once it exists.
func _sync_dash() -> void:
	if _player == null or _dash_picker == null:
		return
	_dash_picker.selected = int(_player.dash_vfx)
	_dash_speed.value = _player.dash_speed
	_dash_speed_label.text = "%.1f" % _player.dash_speed


## The blade afterimage group. Unlike the dash group above, everything here is
## per-weapon and is written to the weapon's own JSON.
func _build_trail(box: VBoxContainer) -> void:
	_trail_toggle = CheckBox.new()
	_trail_toggle.text = "开启残影"
	_trail_toggle.add_theme_font_size_override("font_size", 11)
	_trail_toggle.toggled.connect(func(on: bool) -> void:
		if _loading:
			return
		_config.trail.enabled = on
		_update_weapon_behaviour())
	box.add_child(_trail_toggle)

	box.add_child(_section("色系 / Family"))
	var presets := GridContainer.new()
	presets.columns = 3
	presets.add_theme_constant_override("h_separation", 2)
	presets.add_theme_constant_override("v_separation", 2)
	box.add_child(presets)
	for row in TRAIL_PRESETS:
		presets.add_child(_button(String(row[1]), _apply_trail_preset.bind(String(row[0]))))

	# What the algorithm derives from hue and spread alone, head on the left and
	# tail on the right. Drawn at energy 1: this is meant to be read, not bloomed.
	_trail_ramp = TextureRect.new()
	_trail_ramp.custom_minimum_size = Vector2(0.0, 16.0)
	_trail_ramp.stretch_mode = TextureRect.STRETCH_SCALE
	box.add_child(_trail_ramp)

	for row in TRAIL_TUNER:
		_add_slider(box, row, _on_trail_slider)

	box.add_child(_section("混合模式 / Blend Mode"))
	_blend_picker = OptionButton.new()
	_blend_picker.add_theme_font_size_override("font_size", 11)
	for row in BLEND_MODE_NAMES:
		_blend_picker.add_item(String(row[1]))
	_blend_picker.item_selected.connect(func(idx: int) -> void:
		if _loading or _config.is_empty():
			return
		_config.trail.blend_mode = BLEND_MODE_NAMES[idx][0]
		_update_weapon_behaviour())
	box.add_child(_blend_picker)

	box.add_child(_section("纹理模式 / Texture Mode"))
	_texture_picker = OptionButton.new()
	_texture_picker.add_theme_font_size_override("font_size", 11)
	for row in TEXTURE_MODE_NAMES:
		_texture_picker.add_item(String(row[1]))
	_texture_picker.item_selected.connect(func(idx: int) -> void:
		if _loading or _config.is_empty():
			return
		_config.trail.texture_mode = TEXTURE_MODE_NAMES[idx][0]
		_update_weapon_behaviour())
	box.add_child(_texture_picker)

	var marker := CheckBox.new()
	marker.text = "显示刃上两点"
	marker.button_pressed = _show_anchors
	marker.add_theme_font_size_override("font_size", 11)
	marker.toggled.connect(func(on: bool) -> void:
		_show_anchors = on
		_refresh_trail_gizmos())
	box.add_child(marker)


## Fills hue and hue_spread from a colour family. The sliders' own signal carries
## it the rest of the way, so nothing is pushed here.
func _apply_trail_preset(family: String) -> void:
	var pair := TrailPalette.preset(family)
	if pair.size() < 2:
		return
	_set_value("hue", float(pair[0]))
	_set_value("hue_spread", float(pair[1]))
	# Both may already hold those values, in which case no signal fired.
	_on_trail_slider()


func _on_trail_slider() -> void:
	_read_trail()
	_refresh_trail_ramp()
	_update_weapon_behaviour()


## Whatever the trail sliders say, into `_config.trail`. Keys match by name.
func _read_trail() -> void:
	if _config.is_empty():
		return
	for row in TRAIL_TUNER:
		_config.trail[String(row[0])] = _value(String(row[0]))


func _refresh_trail_ramp() -> void:
	if _trail_ramp == null or _config.is_empty():
		return
	var tex := GradientTexture2D.new()
	tex.gradient = TrailPalette.gradient(float(_config.trail.hue),
		float(_config.trail.hue_spread), 1.0)
	tex.width = 256
	tex.height = 1
	tex.fill_from = Vector2.ZERO
	tex.fill_to = Vector2(1.0, 0.0)
	_trail_ramp.texture = tex


## Two markers where the trail samples the blade. Parented to the item's own
## anchors, so grip, flip and scale reach them for free; counter-scaled, or a
## small item_scale would shrink them out of sight.
## Post: the equipped item's anchors match `_config.trail`, gizmos or not.
func _refresh_trail_gizmos() -> void:
	var item := _equipped()
	if item == null or _config.is_empty():
		return
	item.set_trail_anchors(float(_config.trail.base), float(_config.trail.tip))
	var counter := Vector3.ONE / maxf(item.data.item_scale, 0.0001)
	var hue := float(_config.trail.hue)
	for i in 2:
		var anchor := item.trail_anchor(i)
		if anchor == null:
			continue
		var ball := anchor.get_node_or_null("Gizmo") as MeshInstance3D
		if ball == null:
			ball = _make_gizmo()
			anchor.add_child(ball)
		ball.visible = _show_anchors
		ball.scale = counter
		# Near end dimmed, far end at full: which is which has to be readable at a
		# glance, or dragging the two sliders is guesswork.
		var mat := (ball.mesh as SphereMesh).material as StandardMaterial3D
		mat.albedo_color = TrailPalette.plain(hue) if i == 1 \
			else TrailPalette.plain(hue).darkened(0.55)


func _make_gizmo() -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Drawn through the model: the anchor may sit inside the blade, and a marker
	# that is hidden exactly when it matters is no marker at all.
	mat.no_depth_test = true

	var sphere := SphereMesh.new()
	sphere.radius = 0.018
	sphere.height = 0.036
	sphere.radial_segments = 8
	sphere.rings = 4
	sphere.material = mat

	var ball := MeshInstance3D.new()
	ball.name = "Gizmo"
	ball.mesh = sphere
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ball


## A collapsible group inside the tuner. Returns the box its contents go in.
func _fold(parent: VBoxContainer, text: String, open: bool) -> VBoxContainer:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	body.visible = open

	var head := Button.new()
	head.toggle_mode = true
	head.button_pressed = open
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_theme_font_size_override("font_size", 12)
	head.text = ("▾ " if open else "▸ ") + text
	head.toggled.connect(func(on: bool) -> void:
		body.visible = on
		head.text = ("▾ " if on else "▸ ") + text)
	parent.add_child(head)
	parent.add_child(body)
	return body


## One picker bound to `_config.stance[field]`, registered in _stance_pickers.
func _clip_picker(field: String) -> OptionButton:
	var picker := OptionButton.new()
	picker.add_theme_font_size_override("font_size", 11)
	picker.fit_to_longest_item = false
	picker.item_selected.connect(func(index: int) -> void: _on_stance_picked(field, index))
	_stance_pickers[field] = picker
	return picker


## Whether "" is a legal value for that field, i.e. whether it gets a CLIP_INHERIT
## item.
func _optional_clip(field: String) -> bool:
	for row in STANCE_PICKERS:
		if row[0] == field:
			return bool(row[2])
	return false


func _on_stance_picked(field: String, index: int) -> void:
	var picker: OptionButton = _stance_pickers.get(field)
	if _loading or picker == null:
		return
	var text := picker.get_item_text(index)
	_config.stance[field] = "" if text == CLIP_INHERIT else text
	_update_weapon_behaviour()


func _select_stance_items() -> void:
	if _config.is_empty():
		return
	for field in _stance_pickers:
		_select_stance_item(field, String(_config.stance.get(field, "")))


## Points one picker at what the config says. A clip this character does not have
## is added as an item rather than silently swapped, or Tab onto a character with
## a smaller library would rewrite the config behind your back.
func _select_stance_item(field: String, clip: String) -> void:
	var picker: OptionButton = _stance_pickers[field]
	var wanted := CLIP_INHERIT if clip.is_empty() else clip
	for i in picker.item_count:
		if picker.get_item_text(i) == wanted:
			picker.selected = i
			return
	picker.add_item(wanted)
	picker.selected = picker.item_count - 1


func _build_status(box: VBoxContainer) -> void:
	box.add_theme_constant_override("separation", 4)
	_state_label = Label.new()
	_state_label.add_theme_font_size_override("font_size", 12)
	box.add_child(_state_label)
	box.add_child(HSeparator.new())
	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", 11)
	_hint_label.modulate = Color(1, 1, 1, 0.75)
	box.add_child(_hint_label)


func _title(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	return lbl


func _section(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.modulate = Color(0.7, 0.8, 1.0, 0.9)
	return lbl


func _button(text: String, handler: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 11)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(handler)
	return btn


## One slider bound to `row` from TUNER or TRAIL_TUNER. `on_change` replaces the
## grip write-back, for rows that belong to another block.
func _add_slider(box: VBoxContainer, row: Array, on_change := Callable()) -> void:
	var key: String = row[0]
	var h_box := HBoxContainer.new()
	box.add_child(h_box)

	var lbl := Label.new()
	lbl.text = row[1]
	lbl.custom_minimum_size = Vector2(58, 0)
	lbl.add_theme_font_size_override("font_size", 11)
	h_box.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = row[2]
	slider.max_value = row[3]
	slider.step = row[4]
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h_box.add_child(slider)

	var value_lbl := Label.new()
	value_lbl.custom_minimum_size = Vector2(56, 0)
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_lbl.add_theme_font_size_override("font_size", 11)
	h_box.add_child(value_lbl)

	_sliders[key] = slider
	_slider_labels[key] = value_lbl
	_format_slider_label(key)
	slider.value_changed.connect(func(_v: float) -> void:
		_format_slider_label(key)
		if _loading:
			return
		if on_change.is_valid():
			on_change.call()
			return
		_read_sliders()
		_update_weapon_transform())


## A slider's value, or 0 before the panel exists.
func _value(key: String) -> float:
	var slider := _sliders.get(key) as HSlider
	return slider.value if slider != null else 0.0


func _set_value(key: String, v: float) -> void:
	var slider := _sliders.get(key) as HSlider
	if slider != null:
		slider.value = v


func _format_slider_label(key: String) -> void:
	var lbl := _slider_labels.get(key) as Label
	if lbl == null:
		return
	var row := _tuner_row(key)
	if row.is_empty():
		return
	var text: String = "%.3f" % _value(key) if float(row[4]) < 0.1 \
		else "%.1f" % _value(key)
	lbl.text = text + String(row[5])


## The TUNER or TRAIL_TUNER row named `key`, or [] if neither has one.
static func _tuner_row(key: String) -> Array:
	for row in TUNER:
		if row[0] == key:
			return row
	for row in TRAIL_TUNER:
		if row[0] == key:
			return row
	return []


# --- hud text --------------------------------------------------------------

func _refresh_hud_text() -> void:
	if _hint_label == null or _characters.is_empty():
		return
	var entry: Dictionary = _characters[_index]
	# One % over the whole string, not over the last line of it: % binds tighter
	# than +, so writing it per-line formats only the fragment it touches and
	# leaves the placeholders in the others as literal text.
	_hint_label.text = ("WASD 移动 · 双击 Shift 翻滚 · 空格 跳跃\n"
		+ "左键 攻击 · 右键 单击重击 / 按住转视角 · Q 重击 · E 特殊 · X 格挡\n"
		+ "J 武器列表 · K 武器配置 · B 行为树（全屏）· L 沉浸/锁鼠标%s · Ctrl+S 保存\n"
		+ "Tab 换角色 (%s, %d/%d) · G 适配身高 · F 翻转 · R 复位 · Esc 返回") % [
			"（开）" if _immersive else "", entry.id, _index + 1, _characters.size()]


func _report(message: String) -> void:
	if _save_label != null:
		_save_label.text = message


func _refresh_readouts() -> void:
	var item := _equipped()
	if _measure_label != null:
		if item == null:
			_measure_label.text = "未装备"
		else:
			var raw := item.measured_length()
			_measure_label.text = "%s\n模型原长 %.2f m → 当前 %.2f m (角色身高 %.2f m)%s" % [
				item.data.item_id, raw, raw * _config.grip.scale, _body_height(),
				"  [已翻转]" if _config.grip.flip else ""]
	if _save_label != null and not _config.is_empty():
		_save_label.text = "● 与磁盘一致" if _is_saved() else "○ 有未保存的改动"
	# Here rather than at each caller: every path that rebuilds or re-tunes the
	# item ends up in this function, and the markers hang off the item.
	_refresh_trail_gizmos()
	_push_spans()


## The real take lengths, from the controller's own graph, so the node map draws
## its timelines in seconds. The config only knows `duration`, where 0 means
## "as long as the clip is" and the clip is the controller's to measure.
func _push_spans() -> void:
	if _graph_editor == null or _player == null:
		return
	var graph: WeaponGraph = _player.get("_weapon_graph")
	if graph == null:
		return
	var spans := {}
	for id in graph.order:
		spans[id] = graph.span_of(id)
	_graph_editor.set_spans(spans)


func _process(delta: float) -> void:
	if _right_held >= 0.0:
		_right_held += delta
	# The pointer is only ours while the button is held. A release that lands on
	# a panel, or off the window entirely, never reaches _unhandled_input, and
	# without this check the view would stay captured with nothing holding it.
	# No swing on that path: a click a panel swallowed should not reach the sword.
	if _looking and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_release_right(false)
	_check_dummy_hit()
	if _state_label == null or _player == null:
		return
	_state_label.text = "%s   %.2f m/s   已装备: %s" % [
		_player.state_name(), _player.speed(),
		_weapon_id() if not _selected_weapon_file.is_empty() else "无"]


func _spawn_or_reset_dummy() -> void:
	if _player == null:
		return
	if _dummy == null or not is_instance_valid(_dummy):
		_dummy = DummyTargetScript.new()
		# Before add_child(): _ready() reads it. Same body as the one being tested,
		# not whatever character happens to sort first.
		_dummy.character_scene = _characters[_index].scene
		add_child(_dummy)
	var spawn_pos := _player.global_position + _player.global_transform.basis.z * -2.0
	_dummy.global_position = spawn_pos
	# look_at() errors on a zero-length aim, and the two can coincide if the
	# player is standing where the dummy is about to be.
	if spawn_pos.distance_squared_to(_player.global_position) > 1e-4:
		_dummy.look_at(_player.global_position, Vector3.UP)
		_dummy.rotation.x = 0.0
		_dummy.rotation.z = 0.0
	_has_prev_tip = false
	_blade_inside = false
	_last_stroke = -1
	_dummy.reset_dummy()
	_report("假人已重置/放置于面前")


## Hits on contact, not on swings: an action whose clip strikes several times
## must score several times, so the gate is the blade entering the capsule, not
## the stroke counter.
func _check_dummy_hit() -> void:
	if _dummy == null or not is_instance_valid(_dummy) or _player == null:
		return
	if _player.state != PlayerControllerScript.State.ATTACKING or _dummy.is_dead:
		_has_prev_tip = false
		_blade_inside = false
		return

	# A new stroke re-arms the edge even if the blade never left the capsule -
	# two swings that both start in contact are still two hits.
	var stroke: int = _player.weapon_stroke_count()
	if stroke != _last_stroke:
		_last_stroke = stroke
		_blade_inside = false
		_has_prev_tip = false

	var base := Vector3.ZERO
	var tip := Vector3.ZERO
	var item := _equipped()
	# trail_anchor() is null until set_trail_anchors() has run, which never
	# happens for a weapon with no config on disk yet.
	if item != null and item.trail_anchor(0) != null and item.trail_anchor(1) != null:
		base = item.trail_anchor(0).global_position
		tip = item.trail_anchor(1).global_position
	else:
		base = _player.global_position + Vector3(0.0, 1.1, 0.0)
		tip = base + _player.global_transform.basis.z * -0.7

	var swing := (tip - _prev_tip) if _has_prev_tip else Vector3.ZERO
	var last_tip := _prev_tip if _has_prev_tip else tip
	_prev_tip = tip
	_has_prev_tip = true

	# The blade where it is now, then the ground the tip covered since last
	# frame: a fast swing can step clean over a 0.45 m capsule in one frame.
	var hit := _dummy.segment_hit(base, tip, BLADE_PAD)
	if hit.is_empty():
		hit = _dummy.segment_hit(last_tip, tip, BLADE_PAD)

	var inside := not hit.is_empty()
	if inside and not _blade_inside:
		_dummy.take_hit(hit.point, HIT_DAMAGE, swing)
	_blade_inside = inside


# --- inputs ----------------------------------------------------------------

func _set_looking(on: bool) -> void:
	if on == _looking:
		return
	_looking = on
	_refresh_mouse_mode()
	if on and _camera != null:
		_camera.set("_swallow_first_motion", true)


## The pointer is ours while immersive, or while the right button holds the view.
## Post: mouse_mode == CAPTURED iff (_looking or _immersive). Single writer, so
## releasing one of the two never steals the pointer from the other.
func _refresh_mouse_mode() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _looking or _immersive \
		else Input.MOUSE_MODE_VISIBLE


## Ends a right-button press. `fire` is false on the paths where the release was
## swallowed - a panel, or the window losing focus - and a swing would be a
## surprise. Otherwise a tap swings and a hold only turned the view.
func _release_right(fire: bool) -> void:
	var tapped := _right_held >= 0.0 and _right_held <= RIGHT_TAP_TIME \
		and _right_drift <= RIGHT_TAP_DRIFT
	_right_held = -1.0
	_set_looking(false)
	if not fire or not tapped or _player == null:
		return
	var combat := PlayerIntentSourceScript.button_for_mouse(MOUSE_BUTTON_RIGHT)
	if not combat.is_empty():
		_player.request_button(combat)


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null:
		# Immersive already holds the view, so the right button has no look duty
		# there and falls through to the plain combat path below: press swings, no
		# tap-versus-hold test. Guarding here rather than inside _release_right()
		# keeps _right_held/_right_drift untouched while immersive.
		if button.button_index == MOUSE_BUTTON_RIGHT and not _immersive:
			if button.pressed:
				_right_held = 0.0
				_right_drift = 0.0
				_set_looking(true)
			else:
				_release_right(true)
			return
		# Read here rather than polled in PlayerIntentSource, so that a click that
		# landed on a panel - which stops the event before this runs - does not
		# also swing the weapon. The binding itself still lives in the source.
		if button.pressed and _player != null:
			var combat := PlayerIntentSourceScript.button_for_mouse(button.button_index)
			if not combat.is_empty():
				_player.request_button(combat)
		return

	# Only measured while the right button is down, and only to tell a tap from a
	# look. FollowCamera reads the same events for the view and consumes neither.
	var motion := event as InputEventMouseMotion
	if motion != null:
		if _right_held >= 0.0:
			_right_drift += motion.relative.length()
		return

	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	# A focused text field owns the keyboard, or typing "axe" into the filter box
	# would also flip the grip and reset the tuner.
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit or focused is SpinBox:
		return
	if PANEL_KEYS.has(key.keycode):
		_toggle_panel(PANEL_KEYS[key.keycode])
		return
	match key.keycode:
		KEY_F1:
			_spawn_or_reset_dummy()
		KEY_ESCAPE:
			# Both, or the menu inherits a captured pointer from immersive.
			_set_immersive(false)
			_set_looking(false)
			SceneLoader.change_scene(get_tree(), MENU_SCENE, "返回主菜单...")
		KEY_TAB:
			_index = (_index + 1) % _characters.size()
			_spawn_character()
		KEY_L:
			_set_immersive(not _immersive)
		KEY_S:
			# Ctrl+S, not a bare S: S is the backpedal, and PlayerIntentSource polls
			# it every frame. Ctrl is the crouch, so the gesture also ducks for a
			# moment - harmless next to a save that silently never happened.
			if key.ctrl_pressed:
				_save()
		KEY_F:
			_toggle_flip()
		KEY_G:
			_fit_to_height()
		KEY_R:
			_reset_tuner()
