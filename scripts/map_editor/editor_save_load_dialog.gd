extends RefCounted
## Save / Load map modal for MapEditor.
## Owns: name LineEdit, existing-map ItemList, confirm/cancel actions.
## Pre: ed assigned before any call; build() before open_save()/open_load().
## Invariant: is_save selects which branch _on_confirm() takes.

const MapDataScript = preload("res://scripts/map_data.gd")

var ed  # MapEditor host (untyped: breaks preload cycle)

var dialog: PanelContainer
var file_list: ItemList
var name_edit: LineEdit
var title_label: Label
var is_save := true


func _init(host) -> void:
	ed = host


func is_open() -> bool:
	return dialog != null and dialog.visible


## close(): ESC path — hides dialog and restores panel/cursor mode.
func close() -> void:
	dialog.visible = false
	ed._update_ui_panels_visibility()


## build(): creates the modal. Pre: ed._hud_canvas exists. Post: dialog hidden.
func build() -> void:
	dialog = PanelContainer.new()
	dialog.set_anchors_preset(Control.PRESET_CENTER)
	dialog.custom_minimum_size = Vector2(400, 320)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.18, 0.96)
	style.border_color = Color(0.35, 0.4, 0.5)
	style.set_border_width_all(1)
	style.set_content_margin_all(14)
	dialog.add_theme_stylebox_override("panel", style)
	dialog.visible = false
	ed._hud_canvas.add_child(dialog)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	dialog.add_child(vbox)

	title_label = Label.new()
	title_label.text = "保存地图"
	title_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title_label)

	var name_box := HBoxContainer.new()
	vbox.add_child(name_box)
	name_box.add_child(Label.new())
	(name_box.get_child(0) as Label).text = "地图名称:"

	name_edit = LineEdit.new()
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text = ed._map_name
	name_box.add_child(name_edit)

	var list_lbl := Label.new()
	list_lbl.text = "已有地图存档列表:"
	list_lbl.add_theme_font_size_override("font_size", 12)
	vbox.add_child(list_lbl)

	file_list = ItemList.new()
	file_list.custom_minimum_size = Vector2(0, 140)
	file_list.item_selected.connect(func(idx: int) -> void:
		var fn: String = file_list.get_item_text(idx)
		name_edit.text = fn.get_basename()
	)
	vbox.add_child(file_list)

	var action_box := HBoxContainer.new()
	action_box.alignment = BoxContainer.ALIGNMENT_END
	action_box.add_theme_constant_override("separation", 10)
	vbox.add_child(action_box)

	var confirm_btn := Button.new()
	confirm_btn.text = "确认"
	confirm_btn.pressed.connect(_on_confirm)
	action_box.add_child(confirm_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "取消"
	cancel_btn.pressed.connect(func() -> void:
		dialog.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	)
	action_box.add_child(cancel_btn)


func open_save() -> void:
	is_save = true
	title_label.text = "保存地图 (Save Map)"
	name_edit.text = ed._map_name
	_populate_list()
	dialog.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func open_load() -> void:
	is_save = false
	title_label.text = "加载地图 (Load Map)"
	_populate_list()
	dialog.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _populate_list() -> void:
	file_list.clear()
	var maps := MapDataScript.list_available_maps()
	for m in maps:
		var fn: String = m.get("file_name", "")
		var name_str: String = m.get("name", "")
		var b_count: int = m.get("blocks_count", 0)
		var sp_count: int = m.get("special_paths_count", 0)
		var text := "%s (%s · %d 方块 · %d 特殊路径)" % [fn, name_str, b_count, sp_count]
		file_list.add_item(text)
		file_list.set_item_metadata(file_list.item_count - 1, m.get("path", ""))


## _on_confirm(): save branch writes ed._map_name then saves; load branch prefers list selection.
func _on_confirm() -> void:
	var chosen_name := name_edit.text.strip_edges()
	if chosen_name.is_empty():
		chosen_name = "未命名地图"

	if is_save:
		ed._map_name = chosen_name
		ed.save_current_map(chosen_name)
	else:
		var selected := file_list.get_selected_items()
		if selected.size() > 0:
			var path: String = str(file_list.get_item_metadata(selected[0]))
			ed.load_map(path)
		elif not chosen_name.is_empty():
			var fallback_path := MapDataScript.USER_MAPS_DIR.path_join(chosen_name + ".json")
			ed.load_map(fallback_path)

	dialog.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
