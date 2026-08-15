class_name WeaponGraphEditor
extends VBoxContainer
## UI Editor panel for managing a weapon's JSON config dictionary. Emits `changed` signal on edits.
##
## Two halves: a drawn node map (NodeMap, below) that shows the whole graph and
## picks one node, and a form beside it that edits whatever the map picked. Every
## edit still goes through _commit() -> normalise() -> changed.

## A repaired config, whenever anything in it changes.
signal changed(config: Dictionary)

const ROW_SEPARATION := 3
const FONT_SIZE := 11
## Width of the editing column. The map gets whatever is left.
const SIDE_WIDTH := 348.0
const ACCENT := Color(0.7, 0.8, 1.0)

## One colour per combat button, shared by the map's edges, entry pucks and
## cancel-window bands, so a trigger reads the same wherever it appears.
const TRIGGER_COLOURS := {
	"attack": Color(0.42, 0.72, 1.0),
	"heavy": Color(1.0, 0.56, 0.34),
	"special": Color(0.74, 0.56, 1.0),
	"block": Color(0.48, 0.86, 0.60),
}
const TRIGGER_FALLBACK := Color(0.72, 0.76, 0.82)


## The colour a trigger is drawn in everywhere.
static func colour_of(trigger: String) -> Color:
	return TRIGGER_COLOURS.get(trigger, TRIGGER_FALLBACK)


var _config := {}
## Bare clip names for the dropdowns, from Character.clip_names().
var _clips := PackedStringArray()
## Real take lengths in seconds by action id, from the controller's WeaponGraph.
## Empty until set_spans(); the map falls back to the windows it can see.
var _spans := {}
## Which action the form is editing. "" or a stale id resolves to the first entry
## target on the next _rebuild().
var _selected := ""

var _map: NodeMap
var _selected_label: Label
var _nodes_box: VBoxContainer
var _entries_box: VBoxContainer
var _json_edit: TextEdit
var _status: Label
## Mutex flag during UI element generation.
var _loading := false


func _ready() -> void:
	add_theme_constant_override("separation", 6)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	add_child(head)
	head.add_child(_label("行为树 / Behaviour", 13, Color.WHITE))
	head.add_child(_label("点节点选中它 · B 关闭", FONT_SIZE, Color(1, 1, 1, 0.5)))
	_selected_label = _label("", FONT_SIZE, ACCENT)
	head.add_child(_selected_label)

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 8)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)

	# The map is bigger than the panel as soon as there are a few nodes, so it
	# gets to be its natural size inside something that scrolls both ways.
	var map_scroll := ScrollContainer.new()
	map_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(map_scroll)

	_map = NodeMap.new()
	_map.picked.connect(_on_picked)
	map_scroll.add_child(_map)

	var side := ScrollContainer.new()
	side.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(side)

	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 6)
	side.add_child(form)

	form.add_child(_label("起手 / Entries", FONT_SIZE, ACCENT))
	_entries_box = VBoxContainer.new()
	_entries_box.add_theme_constant_override("separation", ROW_SEPARATION)
	form.add_child(_entries_box)

	form.add_child(HSeparator.new())
	form.add_child(_label("选中的节点 / Selected", FONT_SIZE, ACCENT))
	_nodes_box = VBoxContainer.new()
	_nodes_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_nodes_box.add_theme_constant_override("separation", 6)
	form.add_child(_nodes_box)

	form.add_child(HSeparator.new())
	_json_edit = TextEdit.new()
	_json_edit.custom_minimum_size = Vector2(0, 150)
	_json_edit.add_theme_font_size_override("font_size", 10)
	_json_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	form.add_child(_json_edit)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	form.add_child(row)
	row.add_child(_button("复制 JSON", _copy))
	row.add_child(_button("粘贴 JSON", _paste))
	row.add_child(_button("应用文本框", _apply_text))
	form.add_child(_status_label())


## Cached clean list of available animation clips.
func set_clips(clip_names: PackedStringArray) -> void:
	var unique := {}
	for full in clip_names:
		unique[String(full).get_file()] = true
	_clips = PackedStringArray(unique.keys())
	_clips.sort()
	_rebuild()


## Real take lengths by action id. Only the map reads them - the form shows the
## configured duration, where 0 still means "as long as the clip is".
func set_spans(spans: Dictionary) -> void:
	_spans = spans
	_redraw_map()


## Loads a config into the panel without reporting it back as an edit.
func show_config(source: Dictionary) -> void:
	_config = WeaponConfig.normalise(source)
	_rebuild()


func config() -> Dictionary:
	return _config


func _on_picked(action_id: String) -> void:
	if action_id == _selected:
		return
	_selected = action_id
	_rebuild()


# --- building the rows -----------------------------------------------------

## The index of the node the form is editing. Falls back to the first entry's
## target, then to the first node, so the form is never empty while nodes exist.
func _selected_index() -> int:
	for i in _config.actions.size():
		if _config.actions[i].id == _selected:
			return i
	if not _config.entries.is_empty():
		for i in _config.actions.size():
			if _config.actions[i].id == _config.entries[0].to:
				return i
	return 0 if not _config.actions.is_empty() else -1


func _redraw_map() -> void:
	if _map != null and not _config.is_empty():
		_map.set_graph(_config, _spans, _selected)


func _rebuild() -> void:
	# The clip list usually arrives before the first config does - the host knows
	# what the character can play before it knows which weapon is selected - so
	# there is a window where there is nothing to draw yet.
	if _nodes_box == null or _config.is_empty():
		return
	_loading = true
	_clear(_entries_box)
	_clear(_nodes_box)

	for i in _config.entries.size():
		_entries_box.add_child(_entry_row(i))
	_entries_box.add_child(_button("+ 入口", func() -> void: _add_entry()))

	var index := _selected_index()
	_selected = String(_config.actions[index].id) if index >= 0 else ""
	_selected_label.text = "编辑中: %s" % _selected if index >= 0 else "没有节点"
	if index >= 0:
		_nodes_box.add_child(_action_block(index))
	if _config.actions.size() < WeaponConfig.MAX_ACTIONS:
		_nodes_box.add_child(_button("+ 动作节点", func() -> void: _add_action()))
	else:
		_nodes_box.add_child(_label("已到 %d 个节点上限" % WeaponConfig.MAX_ACTIONS,
			FONT_SIZE, Color(1.0, 0.8, 0.5)))

	_json_edit.text = WeaponConfig.to_json(_config)
	_redraw_map()
	_loading = false


func _entry_row(index: int) -> HBoxContainer:
	var entry: Dictionary = _config.entries[index]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(_trigger_picker(entry.trigger, func(t: String) -> void:
		_config.entries[index].trigger = t
		_commit()))
	row.add_child(_label("→", FONT_SIZE, Color.WHITE))
	row.add_child(_action_picker(entry.to, func(id: String) -> void:
		_config.entries[index].to = id
		_commit()))
	row.add_child(_button("×", func() -> void:
		_config.entries.remove_at(index)
		_commit()))
	return row


func _action_block(index: int) -> VBoxContainer:
	var action: Dictionary = _config.actions[index]
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", ROW_SEPARATION)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	block.add_child(head)

	var id_edit := LineEdit.new()
	id_edit.text = action.id
	id_edit.custom_minimum_size = Vector2(84, 0)
	id_edit.add_theme_font_size_override("font_size", FONT_SIZE)
	# On submit and on losing focus, not on every keystroke: renaming a node
	# rewrites every link pointing at it and rebuilds the panel, which would take
	# the keyboard away halfway through typing the new name.
	id_edit.text_submitted.connect(func(t: String) -> void: _rename(index, t))
	id_edit.focus_exited.connect(func() -> void: _rename(index, id_edit.text))
	head.add_child(id_edit)

	head.add_child(_clip_picker(action.clip, func(clip: String) -> void:
		_config.actions[index].clip = clip
		_commit()))
	head.add_child(_button("×", func() -> void:
		_config.actions.remove_at(index)
		_commit()))

	var tuning := HBoxContainer.new()
	tuning.add_theme_constant_override("separation", 4)
	block.add_child(tuning)
	tuning.add_child(_label("速率", FONT_SIZE, Color(0.75, 0.8, 0.9)))
	tuning.add_child(_number(action.rate, 0.05, 8.0, 0.05, func(v: float) -> void:
		_config.actions[index].rate = v
		_commit()))
	tuning.add_child(_label("时长", FONT_SIZE, Color(0.75, 0.8, 0.9)))
	# 0 reads as "as long as the clip is", which is what the suffix says.
	var duration := _number(action.duration, 0.0, 10.0, 0.05,
		func(v: float) -> void:
			_config.actions[index].duration = v
			_commit())
	duration.suffix = "s" if action.duration > 0.0 else "自动"
	tuning.add_child(duration)

	var flags := HBoxContainer.new()
	flags.add_theme_constant_override("separation", 4)
	block.add_child(flags)
	flags.add_child(_picker(WeaponConfig.FLATTEN_MODES, action.flatten,
		func(mode: String) -> void:
			_config.actions[index].flatten = mode
			_commit()))
	flags.add_child(_check("锁移动", action.lock_move, func(on: bool) -> void:
		_config.actions[index].lock_move = on
		_commit()))
	flags.add_child(_label("冲刺", FONT_SIZE, Color(0.75, 0.8, 0.9)))
	# Distance only: how fast it is covered is the controller's dash_speed, and it
	# is the same for every weapon.
	var reach := _number(action.dash_distance, 0.0, 12.0, 0.1,
		func(v: float) -> void:
			_config.actions[index].dash_distance = v
			_commit())
	reach.suffix = "m" if action.dash_distance > 0.0 else "无"
	flags.add_child(reach)

	var trail := HBoxContainer.new()
	trail.add_theme_constant_override("separation", 4)
	block.add_child(trail)
	trail.add_child(_check("残影", action.trail, func(on: bool) -> void:
		_config.actions[index].trail = on
		_commit()))
	# Seconds into the take, same units as a link window. Both zero is the whole
	# take, which is what the suffix says - the blade's own speed gate picks the
	# swing out of it, so most nodes never need a narrower one.
	var whole: bool = action.trail_window[0] <= 0.0 and action.trail_window[1] <= 0.0
	for edge in 2:
		var bound := _number(action.trail_window[edge], 0.0, 10.0, 0.05,
			func(v: float) -> void:
				_config.actions[index].trail_window[edge] = v
				_commit())
		bound.suffix = "全程" if whole else "s"
		if edge == 1:
			trail.add_child(_label("~", FONT_SIZE, Color.WHITE))
		trail.add_child(bound)

	for i in action.links.size():
		block.add_child(_link_row(index, i))
	var add := _button("+ 连线", func() -> void: _add_link(index))
	add.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	block.add_child(add)
	block.add_child(HSeparator.new())
	return block


func _link_row(action_index: int, link_index: int) -> HBoxContainer:
	var link: Dictionary = _config.actions[action_index].links[link_index]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)

	row.add_child(_trigger_picker(link.trigger, func(t: String) -> void:
		_config.actions[action_index].links[link_index].trigger = t
		_commit()))
	row.add_child(_number(link.window[0], 0.0, 10.0, 0.05, func(v: float) -> void:
		_config.actions[action_index].links[link_index].window[0] = v
		_commit()))
	row.add_child(_label("~", FONT_SIZE, Color.WHITE))
	row.add_child(_number(link.window[1], 0.0, 10.0, 0.05, func(v: float) -> void:
		_config.actions[action_index].links[link_index].window[1] = v
		_commit()))
	row.add_child(_check("缓冲", link.buffer, func(on: bool) -> void:
		_config.actions[action_index].links[link_index].buffer = on
		_commit()))
	row.add_child(_label("→", FONT_SIZE, Color.WHITE))
	row.add_child(_action_picker(link.to, func(id: String) -> void:
		_config.actions[action_index].links[link_index].to = id
		_commit()))
	row.add_child(_button("×", func() -> void:
		_config.actions[action_index].links.remove_at(link_index)
		_commit()))
	return row


# --- edits -----------------------------------------------------------------

## Renames action node ID and updates referencing links/entries.
func _rename(index: int, new_id: String) -> void:
	var wanted := new_id.strip_edges()
	var old: String = _config.actions[index].id
	# Deferred for the reason in _commit(): this runs from focus_exited, and the
	# LineEdit that lost focus is one of the controls _rebuild() frees.
	if wanted.is_empty() or wanted == old:
		_rebuild.call_deferred()
		return
	for action in _config.actions:
		if action.id == wanted:
			_report("已有叫 %s 的节点" % wanted)
			_rebuild.call_deferred()
			return
	_config.actions[index].id = wanted
	if _selected == old:
		_selected = wanted
	for action in _config.actions:
		for link in action.links:
			if link.to == old:
				link.to = wanted
	for entry in _config.entries:
		if entry.to == old:
			entry.to = wanted
	_commit()


func _add_action() -> void:
	var taken := {}
	for action in _config.actions:
		taken[action.id] = true
	var n: int = _config.actions.size() + 1
	var id := "action_%d" % n
	while taken.has(id):
		n += 1
		id = "action_%d" % n
	_config.actions.append({
		"id": id,
		"clip": _clips[0] if not _clips.is_empty() else "sword_attack",
		"rate": 1.0, "flatten": "GROUND", "duration": 0.0,
		"lock_move": true, "dash_distance": 0.0, "links": [],
	})
	# Selected, or adding a node would leave the form on the old one and the new
	# one only visible as a box on the map.
	_selected = id
	_commit()


func _add_link(action_index: int) -> void:
	# Aimed at the node it comes from, because that is a link that survives
	# normalise() - a new row pointing at nothing would be dropped on the way out
	# and vanish the moment it was added.
	_config.actions[action_index].links.append({
		"trigger": "attack",
		"window": [0.25, 0.75],
		"buffer": true,
		"to": _config.actions[action_index].id,
	})
	_commit()


func _add_entry() -> void:
	if _config.actions.is_empty():
		return
	_config.entries.append({"trigger": "attack", "to": _config.actions[0].id})
	_commit()


## Repairs, reports and redraws. Every edit ends here.
##
## The redraw is deferred, and that is not optional: _rebuild() frees every
## control in the panel including the one whose signal is on the stack, and
## SpinBox starts its repeat timer immediately after emitting value_changed - on
## a node we would already have taken out of the tree. Same for the OptionButtons
## closing their popups. Letting the frame finish first costs nothing.
func _commit() -> void:
	if _loading:
		return
	_config = WeaponConfig.normalise(_config)
	changed.emit(_config)
	_rebuild.call_deferred()


# --- the text box ----------------------------------------------------------

func _copy() -> void:
	DisplayServer.clipboard_set(_json_edit.text)
	_report("已复制到剪贴板")


func _paste() -> void:
	_json_edit.text = DisplayServer.clipboard_get()
	_apply_text()


func _apply_text() -> void:
	var result := WeaponConfig.from_json(_json_edit.text)
	if not result.ok:
		_report("JSON 有问题: %s" % result.error)
		return
	_config = result.config
	_rebuild()
	changed.emit(_config)
	_report("已应用")


func _report(message: String) -> void:
	if _status != null:
		_status.text = message


# --- small controls --------------------------------------------------------

func _trigger_picker(current: String, on_pick: Callable) -> OptionButton:
	var names := PackedStringArray()
	var labels := PackedStringArray()
	for trigger in CharacterIntent.BUTTONS:
		names.append(trigger)
		labels.append("%s (%s)" % [trigger, _binding_of(trigger)])
	return _picker(names, current, on_pick, labels)


func _action_picker(current: String, on_pick: Callable) -> OptionButton:
	var ids := PackedStringArray()
	for action in _config.actions:
		ids.append(action.id)
	return _picker(ids, current, on_pick)


func _clip_picker(current: String, on_pick: Callable) -> OptionButton:
	# A clip the library no longer has still has to be selectable, or opening a
	# config written against a richer library would silently retarget the node.
	var options := _clips.duplicate()
	if not current.is_empty() and not options.has(current):
		options.append(current)
	return _picker(options, current, on_pick)


## An OptionButton over `values`, reporting the value rather than the index.
func _picker(values, current: String, on_pick: Callable,
		labels = null) -> OptionButton:
	var picker := OptionButton.new()
	picker.add_theme_font_size_override("font_size", FONT_SIZE)
	picker.fit_to_longest_item = false
	picker.custom_minimum_size = Vector2(96, 0)
	var chosen := -1
	for i in values.size():
		picker.add_item(String(labels[i]) if labels != null else String(values[i]), i)
		if String(values[i]) == current:
			chosen = i
	picker.selected = chosen
	picker.item_selected.connect(func(i: int) -> void:
		if not _loading:
			on_pick.call(String(values[i])))
	return picker


func _number(value: float, low: float, high: float, step: float,
		on_change: Callable) -> SpinBox:
	var box := SpinBox.new()
	box.min_value = low
	box.max_value = high
	box.step = step
	box.value = value
	box.custom_minimum_size = Vector2(64, 0)
	box.get_line_edit().add_theme_font_size_override("font_size", FONT_SIZE)
	box.value_changed.connect(func(v: float) -> void:
		if not _loading:
			on_change.call(v))
	return box


func _check(text: String, on: bool, on_toggle: Callable) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.button_pressed = on
	box.add_theme_font_size_override("font_size", FONT_SIZE)
	box.toggled.connect(func(pressed: bool) -> void:
		if not _loading:
			on_toggle.call(pressed))
	return box


func _button(text: String, handler: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", FONT_SIZE)
	btn.pressed.connect(handler)
	return btn


func _label(text: String, font_size: int, colour: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.modulate = colour
	return lbl


func _status_label() -> Label:
	_status = _label("", FONT_SIZE, Color(0.7, 1.0, 0.8))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return _status


## Returns physical keybind name string for intent triggers.
static func _binding_of(trigger: String) -> String:
	for index in PlayerIntentSource.MOUSE_BUTTONS:
		if PlayerIntentSource.MOUSE_BUTTONS[index] == trigger:
			match index:
				MOUSE_BUTTON_LEFT: return "左键"
				MOUSE_BUTTON_RIGHT: return "右键"
				MOUSE_BUTTON_MIDDLE: return "中键"
			return "鼠标%d" % index
	for key in PlayerIntentSource.KEY_BUTTONS:
		if PlayerIntentSource.KEY_BUTTONS[key] == trigger:
			return OS.get_keycode_string(key)
	return "未绑定"


static func _clear(box: Node) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


## The drawn half of the editor.
##
## Nodes are boxes laid out in columns by how many hits deep they are from an
## entry; links are arrows coloured by their trigger; and every box carries its
## own timeline, with each cancel window drawn as a band along it. That strip is
## the thing the form cannot show: two spin boxes say 0.30 and 1.20, the strip
## says whether the window opens before the swing lands and whether two of them
## overlap.
##
## Read-only. Clicking a box picks it; every edit happens in the form.
class NodeMap extends Control:
	signal picked(action_id: String)

	const BOX := Vector2(184.0, 84.0)
	## Space between columns, and between boxes stacked in one column.
	const GAP := Vector2(86.0, 30.0)
	const PAD := Vector2(96.0, 26.0)
	## Height of the timeline strip along the bottom of a box.
	const STRIP := 11.0
	const TEXT := 10
	## Curve resolution for a link, in segments, and the sample the label sits on.
	const CURVE_STEPS := 14
	const CURVE_MID := 7

	var _config := {}
	var _spans := {}
	var _selected := ""
	## Action id -> Rect2 it was drawn at. Rebuilt by _layout(), read by the hit
	## test and by the edge drawing. Invariant: holds every action in _config.
	var _boxes := {}
	## Entry index -> the puck drawn for it, left of the graph.
	var _pucks := []


	func set_graph(config: Dictionary, spans: Dictionary, selected: String) -> void:
		_config = config
		_spans = spans
		_selected = selected
		_layout()
		queue_redraw()


	## How long a node runs for, in seconds: the controller's measurement when it
	## has one, then the configured duration, then whatever the windows imply -
	## so a strip is never drawn against a length of zero.
	func _span_of(action: Dictionary) -> float:
		var measured := float(_spans.get(action.id, 0.0))
		if measured > 0.01:
			return measured
		if action.duration > 0.0:
			return action.duration
		var latest := 1.0
		for link in action.links:
			latest = maxf(latest, float(link.window[1]))
		return latest


	## Columns by distance from an entry. Nothing reaches an unreachable node, so
	## it gets a column of its own on the right and is drawn as dead.
	func _depths() -> Dictionary:
		var depth := {}
		var queue := []
		for entry in _config.entries:
			if not depth.has(entry.to):
				depth[entry.to] = 0
				queue.append(entry.to)
		var by_id := {}
		for action in _config.actions:
			by_id[action.id] = action
		var head := 0
		while head < queue.size():
			var id = queue[head]
			head += 1
			for link in by_id.get(id, {"links": []}).links:
				if not depth.has(link.to):
					depth[link.to] = int(depth[id]) + 1
					queue.append(link.to)
		var deepest := 0
		for id in depth:
			deepest = maxi(deepest, int(depth[id]))
		for action in _config.actions:
			if not depth.has(action.id):
				depth[action.id] = deepest + 1
		return depth


	func _layout() -> void:
		_boxes.clear()
		_pucks.clear()
		if _config.is_empty():
			custom_minimum_size = Vector2.ZERO
			return

		var depth := _depths()
		var filled := {}
		for action in _config.actions:
			var column := int(depth.get(action.id, 0))
			var row := int(filled.get(column, 0))
			filled[column] = row + 1
			_boxes[action.id] = Rect2(
				Vector2(PAD.x + column * (BOX.x + GAP.x),
					PAD.y + row * (BOX.y + GAP.y)),
				BOX)

		for i in _config.entries.size():
			_pucks.append(Rect2(Vector2(PAD.x - 78.0, PAD.y + 6.0 + i * 26.0),
				Vector2(66.0, 20.0)))

		var extent := Vector2.ZERO
		for id in _boxes:
			extent = extent.max((_boxes[id] as Rect2).end)
		custom_minimum_size = extent + PAD


	func _gui_input(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click == null or not click.pressed \
				or click.button_index != MOUSE_BUTTON_LEFT:
			return
		for id in _boxes:
			if (_boxes[id] as Rect2).has_point(click.position):
				picked.emit(String(id))
				accept_event()
				return


	func _draw() -> void:
		if _config.is_empty():
			return
		var font := get_theme_default_font()
		for i in _config.entries.size():
			_draw_entry(font, i)
		for action in _config.actions:
			for link in action.links:
				_draw_link(font, action.id, link)
		for action in _config.actions:
			_draw_box(font, action)


	func _draw_entry(font: Font, index: int) -> void:
		var entry: Dictionary = _config.entries[index]
		var rect: Rect2 = _pucks[index]
		var colour: Color = WeaponGraphEditor.colour_of(entry.trigger)
		_plate(rect, Color(colour, 0.18), colour, 1.0, 10.0)
		_text(font, "%s ▶" % entry.trigger, rect, colour, HORIZONTAL_ALIGNMENT_CENTER)
		var target: Rect2 = _boxes.get(entry.to, Rect2())
		if target.size == Vector2.ZERO:
			return
		_arrow(Vector2(rect.end.x, rect.get_center().y),
			Vector2(target.position.x, target.get_center().y), colour, 2.0)


	## One link. Three shapes, because a combo is rarely a straight line: a loop
	## over the box when it points at itself, a curve forwards, and a detour under
	## the row when it points back at a column it already passed.
	func _draw_link(font: Font, from_id: String, link: Dictionary) -> void:
		var from: Rect2 = _boxes.get(from_id, Rect2())
		var to: Rect2 = _boxes.get(link.to, Rect2())
		if from.size == Vector2.ZERO or to.size == Vector2.ZERO:
			return
		var colour: Color = WeaponGraphEditor.colour_of(link.trigger)
		var faded := Color(colour, 0.55 if _selected != from_id else 1.0)
		var label := "%s %.2f~%.2f" % [link.trigger, link.window[0], link.window[1]]

		if from_id == link.to:
			var top := Vector2(from.get_center().x, from.position.y)
			draw_arc(top - Vector2(0, 13.0), 15.0, PI * 0.15, PI * 0.85, 20,
				faded, 2.0, true)
			_arrow(top + Vector2(11.0, -20.0), top + Vector2(3.0, -2.0), faded, 2.0)
			_chip(font, label, top - Vector2(0.0, 34.0), faded)
			return

		var forward := to.position.x > from.position.x
		var start := Vector2(from.end.x, from.get_center().y) if forward \
			else Vector2(from.position.x, from.get_center().y)
		var end := Vector2(to.position.x, to.get_center().y) if forward \
			else Vector2(to.end.x, to.get_center().y)
		var bow: float = 0.0 if forward else (from.size.y * 0.5 + GAP.y * 0.7)
		var reach: float = maxf(absf(end.x - start.x) * 0.45, 34.0)
		var points := PackedVector2Array()
		for i in CURVE_STEPS + 1:
			points.append(_bezier(start, end,
				Vector2(reach if forward else -reach, bow), float(i) / CURVE_STEPS))
		draw_polyline(points, faded, 2.0, true)
		_arrow(points[CURVE_STEPS - 1], points[CURVE_STEPS], faded, 2.0)
		_chip(font, label, points[CURVE_MID] - Vector2(0.0, 9.0), faded)


	func _draw_box(font: Font, action: Dictionary) -> void:
		var rect: Rect2 = _boxes[action.id]
		var chosen: bool = action.id == _selected
		var live := false
		for entry in _config.entries:
			live = live or entry.to == action.id
		for other in _config.actions:
			for link in other.links:
				live = live or link.to == action.id
		var border := Color(0.60, 0.78, 1.0) if chosen \
			else (Color(0.42, 0.46, 0.55) if live else Color(0.72, 0.42, 0.38))
		_plate(rect, Color(0.13, 0.145, 0.18, 0.96), border,
			2.0 if chosen else 1.0, 7.0)

		var span := _span_of(action)
		var inner := rect.grow(-9.0)
		_text(font, action.id, Rect2(inner.position, Vector2(inner.size.x, 15.0)),
			Color.WHITE if chosen else Color(0.88, 0.91, 0.96))
		_text(font, "%.2fs%s" % [span, "" if _spans.has(action.id) else " ?"],
			Rect2(inner.position, Vector2(inner.size.x, 15.0)),
			Color(0.62, 0.68, 0.78), HORIZONTAL_ALIGNMENT_RIGHT)
		_text(font, action.clip,
			Rect2(inner.position + Vector2(0.0, 16.0), Vector2(inner.size.x, 14.0)),
			Color(0.60, 0.66, 0.76))
		var tags := PackedStringArray()
		if not live:
			tags.append("未接入")
		if action.dash_distance > 0.0:
			tags.append("冲 %.1fm" % action.dash_distance)
		if not action.lock_move:
			tags.append("可移动")
		if not action.trail:
			tags.append("无残影")
		if action.rate != 1.0:
			tags.append("×%.2f" % action.rate)
		_text(font, " · ".join(tags),
			Rect2(inner.position + Vector2(0.0, 31.0), Vector2(inner.size.x, 14.0)),
			Color(0.72, 0.66, 0.52) if live else Color(0.86, 0.52, 0.48))

		_draw_strip(Rect2(inner.position + Vector2(0.0, inner.size.y - STRIP),
			Vector2(inner.size.x, STRIP)), action, span)


	## The node's own clock, left to right, with every cancel window on it. Two
	## windows that overlap show up as one band over another, which is the case
	## the numbers alone hide.
	func _draw_strip(rect: Rect2, action: Dictionary, span: float) -> void:
		draw_rect(rect, Color(0.07, 0.08, 0.10), true)
		for link in action.links:
			var from: float = clampf(float(link.window[0]) / span, 0.0, 1.0)
			var to: float = clampf(float(link.window[1]) / span, 0.0, 1.0)
			var colour: Color = WeaponGraphEditor.colour_of(link.trigger)
			var band := Rect2(rect.position + Vector2(rect.size.x * from, 0.0),
				Vector2(maxf(rect.size.x * (to - from), 2.0), rect.size.y))
			draw_rect(band, Color(colour, 0.55), true)
			# The opening edge, because that is the number being tuned.
			draw_rect(Rect2(band.position, Vector2(1.0, band.size.y)), colour, true)
		draw_rect(rect, Color(0.35, 0.38, 0.45), false, 1.0)


	# --- drawing helpers ---------------------------------------------------

	func _plate(rect: Rect2, fill: Color, border: Color, width: float,
			radius: float) -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = fill
		box.border_color = border
		box.set_border_width_all(int(width))
		box.set_corner_radius_all(int(radius))
		draw_style_box(box, rect)


	## draw_string() takes a baseline, not a top edge, so every caller would have
	## to add the ascent by hand.
	func _text(font: Font, text: String, rect: Rect2, colour: Color,
			align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
		if text.is_empty():
			return
		draw_string(font, rect.position + Vector2(0.0, font.get_ascent(TEXT)),
			text, align, rect.size.x, TEXT, colour)


	## A label on its own dark plate, so an edge running under it stays readable.
	func _chip(font: Font, text: String, centre: Vector2, colour: Color) -> void:
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			TEXT).x
		var rect := Rect2(centre - Vector2(width * 0.5 + 4.0, 8.0),
			Vector2(width + 8.0, 16.0))
		_plate(rect, Color(0.09, 0.10, 0.13, 0.92), Color(colour, 0.5), 1.0, 4.0)
		_text(font, text, rect.grow(-4.0).grow_individual(0.0, 1.0, 0.0, 0.0),
			colour)


	func _arrow(from: Vector2, to: Vector2, colour: Color, width: float) -> void:
		draw_line(from, to, colour, width, true)
		var along := (to - from).normalized()
		if along == Vector2.ZERO:
			return
		var across := Vector2(-along.y, along.x) * 4.0
		draw_colored_polygon(PackedVector2Array([
			to, to - along * 9.0 + across, to - along * 9.0 - across]), colour)


	## Quadratic through a control point offset from the midpoint by `bend`.
	static func _bezier(from: Vector2, to: Vector2, bend: Vector2,
			t: float) -> Vector2:
		var mid := from.lerp(to, 0.5) + bend
		var a := from.lerp(mid, t)
		return a.lerp(mid.lerp(to, t), t)
