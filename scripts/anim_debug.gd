extends Node3D
## Character and Animation debug inspector scene.

const CharacterPipelineScript = preload("res://tools/character_pipeline.gd")

const MENU_SCENE := "res://scenes/main_menu.tscn"

## Discovers and loads character models from `assets/characters/`.
@export var characters_root: Node3D

@export_group("Camera")
@export var start_yaw := 0.55
@export var start_pitch := -0.18
@export var start_distance := 3.6
@export var focus_height := 1.0

const ORBIT_SPEED := 0.008
const PAN_SPEED := 0.0022
const ZOOM_STEP := 1.12
const MIN_DISTANCE := 0.4
const MAX_DISTANCE := 40.0
const PITCH_LIMIT := 1.45

## Metres between characters when all of them are shown.
const SPACING := 1.2
## Index 0 of the character picker; every other index is a character.
const SHOW_ALL := 0

var _characters: Array[Character] = []
var _bone_views: Array[MeshInstance3D] = []
var _clips: PackedStringArray = []
var _current_clip := ""
var _character_index := SHOW_ALL

var _yaw := 0.0
var _pitch := 0.0
var _distance := 4.0
var _focus := Vector3.ZERO
var _orbiting := false
var _panning := false

var _scrubbing := false
var _resume_after_scrub := false
var _loop := true

## Retargeted bones carry profile names; used to colour the bone overlay.
var _profile := SkeletonProfileHumanoid.new()

@onready var _camera: Camera3D = $CameraRig/Pitch/Camera3D
@onready var _rig: Node3D = $CameraRig

var _character_picker: OptionButton
var _clip_picker: OptionButton
var _play_button: Button
var _time_slider: HSlider
var _time_label: Label
var _speed_slider: HSlider
var _speed_label: Label
var _info_label: Label
var _bones_toggle: CheckBox


func _ready() -> void:
	_yaw = start_yaw
	_pitch = start_pitch
	_distance = start_distance
	_focus = Vector3(0.0, focus_height, 0.0)

	_load_characters()
	if _characters.is_empty():
		push_error("no character scenes found - run tools\\rebuild_assets.bat first")
		return

	_build_grid()
	_build_bone_overlays()
	_refresh_clips()
	_build_ui()
	_apply_layout()
	_update_camera()

	if not _clips.is_empty():
		_play(_clips[0])


## Scans character folders for generated `.tscn` scenes.
func _load_characters() -> void:
	if characters_root == null:
		push_error("characters_root is not assigned")
		return
	for character in CharacterPipelineScript.list_characters():
		if not ResourceLoader.exists(character.scene):
			push_warning("%s has no scene yet (%s) - run tools\\rebuild_assets.bat" % [
				character.id, character.scene])
			continue
		var instance := (load(character.scene) as PackedScene).instantiate() as Character
		if instance == null:
			push_warning("%s: scene root is not a Character" % character.id)
			continue
		characters_root.add_child(instance)
		# add_child() runs the character's _ready(), so its player is resolved
		# by the time we get here.
		if instance.player == null:
			push_warning("%s: no AnimationPlayer in the imported model" % character.id)
			continue
		_characters.append(instance)


## Returns union list of all available clips.
func _refresh_clips() -> void:
	var seen := {}
	for character in _characters:
		for clip in character.clip_names():
			seen[clip] = true
	_clips = PackedStringArray(seen.keys())
	_clips.sort()


func _shown() -> Array[Character]:
	if _character_index == SHOW_ALL:
		return _characters
	var one: Array[Character] = [_characters[_character_index - 1]]
	return one


## Organizes character node positions (stacked or side-by-side).
func _apply_layout() -> void:
	var shown := _shown()
	for character in _characters:
		character.visible = shown.has(character)
	for i in shown.size():
		var offset := (i - (shown.size() - 1) * 0.5) * SPACING
		shown[i].position = Vector3(offset, 0.0, 0.0)


## Synchronously plays clip on all loaded character AnimationPlayers.
func _play(clip: String) -> void:
	_current_clip = clip
	var longest := 0.0
	for character in _characters:
		var full := character.resolve(clip)
		if full == "" or character.player == null or not character.player.has_animation(full):
			continue
		var anim := character.player.get_animation(full)
		if anim == null:
			continue
		anim.loop_mode = Animation.LOOP_LINEAR if _loop else Animation.LOOP_NONE
		character.play(clip)
		longest = maxf(longest, anim.length)
	if _time_slider:
		_time_slider.max_value = maxf(longest, 0.001)
		_time_slider.step = 0.001
	_refresh_info(clip)
	_sync_play_button()


## The player the time readout follows; _play() keeps the others in step.
func _lead() -> AnimationPlayer:
	for character in _shown():
		if character.player.current_animation != "":
			return character.player
	return null


func _refresh_info(clip: String) -> void:
	if _info_label == null:
		return
	var lines := PackedStringArray([clip])
	for character in _shown():
		lines.append(_binding_line(character, clip))
	_info_label.text = "\n".join(lines)


## Count and print resolved animation track count.
func _binding_line(character: Character, clip: String) -> String:
	var full := character.resolve(clip)
	if full == "" or character.player == null or not character.player.has_animation(full):
		return "%s: 没有这个动作 / no such clip" % character.name
	var anim := character.player.get_animation(full)
	if anim == null:
		return "%s: 没有这个动作 / no such clip" % character.name
	var bound := 0
	var unbound := PackedStringArray()
	for i in anim.get_track_count():
		var bone := String(anim.track_get_path(i).get_subname(0))
		if character.skeleton.find_bone(bone) != -1:
			bound += 1
		elif not unbound.has(bone):
			unbound.append(bone)
	var line := "%s: %.3f s  |  %d/%d 轨道已绑定  |  %d 骨骼" % [
		character.name, anim.length, bound, anim.get_track_count(),
		character.skeleton.get_bone_count()]
	if not unbound.is_empty():
		line += "\n  未匹配: %s" % ", ".join(unbound)
	return line


func _process(_delta: float) -> void:
	var lead := _lead()
	if lead and lead.is_playing() and not _scrubbing and _time_slider:
		_time_slider.set_value_no_signal(lead.current_animation_position)
		_time_label.text = "%5.2f / %5.2f s" % [
			lead.current_animation_position, lead.current_animation_length]
	_draw_bones()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				_orbiting = mb.pressed
			MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
				_panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_distance = maxf(MIN_DISTANCE, _distance / ZOOM_STEP)
					_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_distance = minf(MAX_DISTANCE, _distance * ZOOM_STEP)
					_update_camera()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			_yaw -= mm.relative.x * ORBIT_SPEED
			_pitch = clampf(_pitch - mm.relative.y * ORBIT_SPEED, -PITCH_LIMIT, PITCH_LIMIT)
			_update_camera()
		elif _panning:
			var frame := _camera.global_transform.basis
			_focus -= frame.x * mm.relative.x * PAN_SPEED * _distance
			_focus += frame.y * mm.relative.y * PAN_SPEED * _distance
			_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_ESCAPE:
				SceneLoader.change_scene(get_tree(), MENU_SCENE, "返回主菜单...")
			KEY_F:
				_focus = Vector3(0.0, focus_height, 0.0)
				_distance = start_distance
				_update_camera()
			KEY_SPACE:
				_toggle_play()
			KEY_B:
				_bones_toggle.button_pressed = not _bones_toggle.button_pressed
			KEY_TAB:
				# Cycle characters: quickest way to A/B the same clip on two rigs.
				if _character_picker:
					_character_picker.select((_character_index + 1) % _character_picker.item_count)
					_on_character_selected(_character_picker.selected)


func _update_camera() -> void:
	_rig.position = _focus
	_rig.rotation = Vector3(0.0, _yaw, 0.0)
	($CameraRig/Pitch as Node3D).rotation = Vector3(_pitch, 0.0, 0.0)
	_camera.position = Vector3(0.0, 0.0, _distance)


# --- bone overlay ---------------------------------------------------------

func _build_grid() -> void:
	# 1 m squares: if a character ever imports at the wrong scale again, it is
	# immediately obvious against this.
	const HALF := 6
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(-HALF, HALF + 1):
		var major := i == 0
		var col := Color(0.45, 0.5, 0.6, 0.9) if major else Color(0.3, 0.32, 0.36, 0.6)
		mesh.surface_set_color(col)
		mesh.surface_add_vertex(Vector3(i, 0.0, -HALF))
		mesh.surface_add_vertex(Vector3(i, 0.0, HALF))
		mesh.surface_set_color(col)
		mesh.surface_add_vertex(Vector3(-HALF, 0.0, i))
		mesh.surface_add_vertex(Vector3(HALF, 0.0, i))
	mesh.surface_end()

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var view := MeshInstance3D.new()
	view.name = "Grid"
	view.mesh = mesh
	view.material_override = mat
	view.position.y = 0.002  # avoid z-fighting with the ground plane
	add_child(view)


func _build_bone_overlays() -> void:
	# Drawn on top of the mesh so the rig stays readable inside the body.
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.disable_receive_shadows = true

	for character in _characters:
		var view := MeshInstance3D.new()
		view.name = "BoneOverlay"
		view.mesh = ImmediateMesh.new()
		view.visible = false
		view.material_override = mat
		character.skeleton.add_child(view)
		_bone_views.append(view)


func _draw_bones() -> void:
	for i in _characters.size():
		_draw_character_bones(_characters[i], _bone_views[i])


func _draw_character_bones(character: Character, view: MeshInstance3D) -> void:
	var mesh := view.mesh as ImmediateMesh
	mesh.clear_surfaces()
	var skeleton := character.skeleton
	if not view.visible or not character.visible or skeleton.get_bone_count() == 0:
		return
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(i)
		if parent == -1:
			continue
		# Green where the humanoid profile drives the bone, dim for the leftovers
		# (twist helpers, face rig). Testing the profile rather than a rig-specific
		# name prefix keeps the colours right whatever the character was made in.
		var mapped := _profile.find_bone(skeleton.get_bone_name(i)) != -1
		mesh.surface_set_color(Color(0.2, 1.0, 0.55) if mapped else Color(0.5, 0.5, 0.6, 0.5))
		mesh.surface_add_vertex(skeleton.get_bone_global_pose(parent).origin)
		mesh.surface_add_vertex(skeleton.get_bone_global_pose(i).origin)
	mesh.surface_end()


# --- overlay UI -----------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DebugUI"
	add_child(layer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(380, 0)
	layer.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var title := Label.new()
	title.text = "动作调试 / Animation Debug"
	box.add_child(title)

	_info_label = Label.new()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.add_theme_font_size_override("font_size", 12)
	box.add_child(_info_label)

	box.add_child(HSeparator.new())

	_character_picker = OptionButton.new()
	_character_picker.item_selected.connect(_on_character_selected)
	box.add_child(_character_picker)
	_refill_character_picker()

	_clip_picker = OptionButton.new()
	_clip_picker.item_selected.connect(func(idx: int) -> void: _play(_clips[idx]))
	box.add_child(_clip_picker)
	_refill_clip_picker()

	var row := HBoxContainer.new()
	box.add_child(row)

	_play_button = Button.new()
	_play_button.text = "❚❚ Pause"
	_play_button.pressed.connect(_toggle_play)
	row.add_child(_play_button)

	var reload_button := Button.new()
	reload_button.text = "⟳ 重载"
	reload_button.tooltip_text = "重新从磁盘读取动作库（新角色需要按 F5 重开）" \
		+ "\nReload the animation libraries from disk (a new character needs F5)"
	reload_button.pressed.connect(_reload_libraries)
	row.add_child(reload_button)

	var loop_box := CheckBox.new()
	loop_box.text = "Loop"
	loop_box.button_pressed = _loop
	loop_box.toggled.connect(func(on: bool) -> void:
		_loop = on
		if _current_clip != "":
			_play(_current_clip))
	row.add_child(loop_box)

	_bones_toggle = CheckBox.new()
	_bones_toggle.text = "Bones"
	_bones_toggle.toggled.connect(func(on: bool) -> void:
		for view in _bone_views:
			view.visible = on)
	row.add_child(_bones_toggle)

	_time_label = Label.new()
	_time_label.text = "0.00 / 0.00 s"
	box.add_child(_time_label)

	_time_slider = HSlider.new()
	_time_slider.min_value = 0.0
	_time_slider.max_value = 1.0
	_time_slider.step = 0.001
	_time_slider.value_changed.connect(func(v: float) -> void:
		if not _scrubbing:
			return
		for character in _characters:
			if character.player.current_animation != "":
				character.player.seek(v, true))
	_time_slider.drag_started.connect(func() -> void:
		_scrubbing = true
		_resume_after_scrub = _lead() != null and _lead().is_playing()
		for character in _characters:
			character.player.pause())
	_time_slider.drag_ended.connect(func(_changed: bool) -> void:
		_scrubbing = false
		if _resume_after_scrub:
			for character in _characters:
				if character.player.current_animation != "":
					character.player.play()
		_sync_play_button())
	box.add_child(_time_slider)

	var speed_row := HBoxContainer.new()
	box.add_child(speed_row)
	_speed_label = Label.new()
	_speed_label.text = "Speed 1.00x"
	_speed_label.custom_minimum_size = Vector2(110, 0)
	speed_row.add_child(_speed_label)

	_speed_slider = HSlider.new()
	_speed_slider.min_value = 0.0
	_speed_slider.max_value = 2.0
	_speed_slider.step = 0.05
	_speed_slider.value = 1.0
	_speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speed_slider.value_changed.connect(func(v: float) -> void:
		# Every character, not just the shown ones: switching the picker should
		# not silently hand you a character running at a different speed.
		for character in _characters:
			character.player.speed_scale = v
		_speed_label.text = "Speed %.2fx" % v)
	speed_row.add_child(_speed_slider)

	box.add_child(HSeparator.new())

	var help := Label.new()
	help.add_theme_font_size_override("font_size", 11)
	help.text = "左键拖动 旋转 · 中/右键拖动 平移 · 滚轮 缩放\n" \
		+ "F 复位视角 · 空格 播放/暂停 · B 骨骼线框 · Tab 切换角色 · Esc 返回菜单"
	box.add_child(help)


func _refill_character_picker() -> void:
	_character_picker.clear()
	_character_picker.add_item("全部 / All (%d)" % _characters.size())
	for character in _characters:
		_character_picker.add_item(String(character.name))
	_character_picker.select(_character_index)


func _refill_clip_picker() -> void:
	_clip_picker.clear()
	for clip in _clips:
		_clip_picker.add_item(clip)


func _on_character_selected(index: int) -> void:
	_character_index = index
	_apply_layout()
	if _current_clip != "":
		_play(_current_clip)


## Re-scans and re-caches active animation library resources.
func _reload_libraries() -> void:
	var previous := _current_clip
	for character in _characters:
		character.shared_animations = _reread(character.shared_animations)
		character.own_animations = _reread(character.own_animations)
		character.attach_libraries()
	_refresh_clips()
	_refill_clip_picker()

	var idx := Array(_clips).find(previous)
	if idx == -1:
		idx = 0
	if not _clips.is_empty():
		_clip_picker.select(idx)
		_play(_clips[idx])


## CACHE_MODE_IGNORE forces a real read from disk rather than the cached copy.
func _reread(lib: AnimationLibrary) -> AnimationLibrary:
	if lib == null or lib.resource_path.is_empty():
		return lib
	var fresh := ResourceLoader.load(lib.resource_path, "AnimationLibrary",
		ResourceLoader.CACHE_MODE_IGNORE) as AnimationLibrary
	return fresh if fresh != null else lib


func _toggle_play() -> void:
	if _current_clip == "":
		return
	var lead := _lead()
	var pausing := lead != null and lead.is_playing()
	for character in _characters:
		var player := character.player
		if player.current_animation == "":
			continue
		if pausing:
			player.pause()
		else:
			# play() restarts a finished non-looping clip instead of stalling at the end.
			if is_equal_approx(player.current_animation_position, player.current_animation_length):
				player.seek(0.0, true)
			player.play()
	_sync_play_button()


func _sync_play_button() -> void:
	if _play_button == null:
		return
	var lead := _lead()
	_play_button.text = "❚❚ Pause" if lead != null and lead.is_playing() else "▶ Play"
