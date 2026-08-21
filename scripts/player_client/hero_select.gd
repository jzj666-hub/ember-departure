extends Control
## Dynamic 3D Hero selection stage with 360-degree orbit drag and multiplayer sync.
## Discovers all characters dynamically from assets/characters/ without hardcoding.

const AnimPipelineScript = preload("res://tools/anim_pipeline.gd")
const CharacterPipelineScript = preload("res://tools/character_pipeline.gd")
const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const FONT_PATH := "res://assets/Fonts/Long_Cang/LongCang-Regular.ttf"
const FONT_GLITCH_PATH := "res://assets/Fonts/Long_Cang,Rubik_Glitch/Rubik_Glitch/RubikGlitch-Regular.ttf"
const MULTIPLAYER_CHASE_SCENE := "res://scenes/player_client/chase_multiplayer.tscn"

var _custom_font: Font = null
var _glitch_font: Font = null

# Dynamic Roster
var _roster: Array[Dictionary] = []
var _selected_idx: int = 0

# 3D Stage Nodes
var _bg_viewport: SubViewport
var _bg_camera: Camera3D
var _hero_stage_root: Node3D
var _current_hero_node: Character = null
var _target_yaw: float = 0.0
var _current_yaw: float = 0.0
var _is_mouse_dragging := false

# UI References
var _hero_card_btns: Array[Button] = []
var _lock_btn: Button
var _status_local_lbl: Label
var _status_remote_lbl: Label
var _hero_name_lbl: Label
var _hero_title_lbl: Label

# Transition
var _transition_rect: ColorRect
var _transition_mat: ShaderMaterial
var _is_transitioning := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if ResourceLoader.exists(FONT_PATH):
		_custom_font = load(FONT_PATH) as Font
	if ResourceLoader.exists(FONT_GLITCH_PATH):
		_glitch_font = load(FONT_GLITCH_PATH) as Font

	_scan_dynamic_roster()
	NetworkManager.hero_selection_changed.connect(_on_network_hero_changed)

	_build_3d_stage()
	_build_ui()
	_build_transition_overlay()

	if not _roster.is_empty():
		_select_hero(0, true)

	AudioManagerScript.play_voice_file("res://assets/voice/Voiceover Pack/Male/prepare.ogg", 0.0)


func _exit_tree() -> void:
	if NetworkManager != null and NetworkManager.hero_selection_changed.is_connected(_on_network_hero_changed):
		NetworkManager.hero_selection_changed.disconnect(_on_network_hero_changed)


func _scan_dynamic_roster() -> void:
	_roster.clear()
	var chars := CharacterPipelineScript.list_characters().filter(
		func(c: Dictionary) -> bool: return ResourceLoader.exists(c.scene))

	var fallback_avatars: Array[String] = []
	if ProfileManager != null:
		fallback_avatars = ProfileManager.available_builtin_avatars

	for i in range(chars.size()):
		var c: Dictionary = chars[i]
		var id: String = c.get("id", "hero_%d" % (i + 1))
		var scene_path: String = c.get("scene", "")

		# Search for custom avatar in character directory or fallback from avatar library
		var av_path := ""
		for av_candidate in ["avatar.png", "face.png", "%s.png" % id]:
			var custom_av_file: String = String(c.get("dir", "")).path_join(av_candidate)
			if ResourceLoader.exists(custom_av_file):
				av_path = custom_av_file
				break

		var av_key := ""
		if av_path.is_empty() and not fallback_avatars.is_empty():
			av_key = fallback_avatars[i % fallback_avatars.size()]
		elif not av_path.is_empty():
			av_key = av_path.get_file()

		var colors := [Color(0.3, 0.85, 1.0), Color(1.0, 0.45, 0.2), Color(0.95, 0.8, 0.25), Color(0.4, 0.9, 0.5), Color(0.85, 0.4, 1.0)]
		var entry := {
			"id": id,
			"display_name": id.capitalize().replace("_", " "),
			"scene": scene_path,
			"avatar_key": av_key,
			"color": colors[i % colors.size()]
		}
		_roster.append(entry)

	# Fallback if no characters found
	if _roster.is_empty():
		_roster.append({
			"id": "hero_1",
			"display_name": "Hero 1",
			"scene": "res://assets/characters/hero_1/hero_1.tscn",
			"avatar_key": "avatar_01_01.png",
			"color": Color(0.3, 0.85, 1.0)
		})


func _process(delta: float) -> void:
	if _current_hero_node != null and is_instance_valid(_current_hero_node):
		_current_yaw = lerp_angle(_current_yaw, _target_yaw, delta * 12.0)
		_current_hero_node.rotation.y = _current_yaw


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_is_mouse_dragging = event.pressed
	elif event is InputEventMouseMotion and _is_mouse_dragging:
		_target_yaw += event.relative.x * 0.008


func _build_3d_stage() -> void:
	var vp_container := SubViewportContainer.new()
	vp_container.set_anchors_preset(PRESET_FULL_RECT)
	vp_container.stretch = true
	vp_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vp_container)

	_bg_viewport = SubViewport.new()
	_bg_viewport.size = get_viewport_rect().size
	_bg_viewport.msaa_3d = Viewport.MSAA_4X
	_bg_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	_bg_viewport.use_hdr_2d = false
	_bg_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp_container.add_child(_bg_viewport)

	_hero_stage_root = Node3D.new()
	_bg_viewport.add_child(_hero_stage_root)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.25, 0.35)
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.2

	var env_node := WorldEnvironment.new()
	env_node.environment = env
	_hero_stage_root.add_child(env_node)

	var key_light := DirectionalLight3D.new()
	key_light.light_color = Color(1.0, 0.92, 0.85)
	key_light.light_energy = 1.4
	key_light.shadow_enabled = true
	key_light.transform.basis = Basis.from_euler(Vector3(deg_to_rad(-25.0), deg_to_rad(140.0), 0.0))
	_hero_stage_root.add_child(key_light)

	var rim_light := DirectionalLight3D.new()
	rim_light.light_color = Color(0.35, 0.75, 1.0)
	rim_light.light_energy = 0.9
	rim_light.transform.basis = Basis.from_euler(Vector3(deg_to_rad(-15.0), deg_to_rad(-45.0), 0.0))
	_hero_stage_root.add_child(rim_light)

	# Dais
	var dais := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.0
	cyl.bottom_radius = 2.2
	cyl.height = 0.3
	var dais_mat := StandardMaterial3D.new()
	dais_mat.albedo_color = Color(0.10, 0.12, 0.16)
	dais_mat.roughness = 0.6
	dais_mat.metallic = 0.4
	dais.mesh = cyl
	dais.material_override = dais_mat
	dais.position = Vector3(0.0, -0.15, 0.0)
	_hero_stage_root.add_child(dais)

	# Particles
	var particles := CPUParticles3D.new()
	particles.amount = 40
	particles.lifetime = 3.5
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(2.0, 0.1, 2.0)
	particles.position = Vector3(0.0, 0.05, 0.0)
	particles.direction = Vector3(0.0, 1.0, 0.0)
	particles.spread = 25.0
	particles.gravity = Vector3(0.0, 0.3, 0.0)
	particles.initial_velocity_min = 0.4
	particles.initial_velocity_max = 1.2
	particles.scale_amount_min = 0.03
	particles.scale_amount_max = 0.08
	particles.color = Color(1.0, 0.6, 0.15, 0.9)

	var p_mesh := QuadMesh.new()
	p_mesh.size = Vector2(0.05, 0.05)
	var p_mat := StandardMaterial3D.new()
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p_mat.albedo_color = Color(1.0, 0.65, 0.25, 0.95)
	p_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particles.mesh = p_mesh
	particles.material_override = p_mat
	_hero_stage_root.add_child(particles)

	_bg_camera = Camera3D.new()
	_bg_camera.fov = 42.0
	_bg_camera.near = 0.05
	_bg_camera.current = true
	_hero_stage_root.add_child(_bg_camera)
	_bg_camera.look_at_from_position(Vector3(0.0, 1.15, 3.4), Vector3(0.0, 0.95, 0.0))


func _select_hero(idx: int, broadcast: bool = false) -> void:
	if idx < 0 or idx >= _roster.size():
		return
	_selected_idx = idx
	var data: Dictionary = _roster[idx]

	if _current_hero_node != null and is_instance_valid(_current_hero_node):
		_current_hero_node.queue_free()
		_current_hero_node = null

	var scene_path: String = data["scene"]
	if ResourceLoader.exists(scene_path):
		var p_scene := load(scene_path) as PackedScene
		if p_scene != null:
			var inst := p_scene.instantiate() as Character
			if inst != null:
				_current_hero_node = inst
				_current_hero_node.position = Vector3(0.0, 0.0, 0.0)
				_current_hero_node.rotation.y = _current_yaw
				_hero_stage_root.add_child(_current_hero_node)
				if _current_hero_node.is_node_ready():
					_play_hero_walk(_current_hero_node)
				else:
					_current_hero_node.ready.connect(func(): _play_hero_walk(_current_hero_node))

	_hero_name_lbl.text = data["display_name"]
	_hero_title_lbl.text = "CHARACTER ID: %s" % data["id"].to_upper()
	_hero_name_lbl.modulate = data["color"]

	for i in range(_hero_card_btns.size()):
		var btn := _hero_card_btns[i]
		if i == idx:
			btn.modulate = Color(1.0, 1.0, 1.0)
		else:
			btn.modulate = Color(0.45, 0.45, 0.50)

	if broadcast and NetworkManager.connected_peer_id > 0:
		NetworkManager.rpc("rpc_sync_hero_pick", scene_path, NetworkManager.local_hero_locked)


func _play_hero_walk(char_node: Character) -> void:
	if char_node == null:
		return
	if char_node.player == null:
		char_node.player = AnimPipelineScript.first_of_class(char_node, "AnimationPlayer") as AnimationPlayer
		char_node.skeleton = AnimPipelineScript.first_of_class(char_node, "Skeleton3D") as Skeleton3D
		char_node.attach_libraries()

	var walk_anims := ["walk", "walk_formal", "jog_fwd", "idle"]
	for a in walk_anims:
		if char_node.has_clip(a):
			char_node.play(a)
			var resolved := char_node.resolve(a)
			if char_node.player != null and char_node.player.has_animation(resolved):
				char_node.player.get_animation(resolved).loop_mode = Animation.LOOP_LINEAR
			break


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	var root_ctrl := Control.new()
	root_ctrl.set_anchors_preset(PRESET_FULL_RECT)
	root_ctrl.mouse_filter = Control.MOUSE_FILTER_PASS
	canvas.add_child(root_ctrl)

	# Top Header
	var top_bar := PanelContainer.new()
	top_bar.set_anchors_preset(PRESET_TOP_WIDE)
	top_bar.offset_top = 16
	top_bar.offset_left = 32
	top_bar.offset_right = -32
	top_bar.offset_bottom = 76
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var top_style := StyleBoxFlat.new()
	top_style.bg_color = Color(0.06, 0.08, 0.12, 0.85)
	top_style.set_corner_radius_all(10)
	top_style.set_border_width_all(1)
	top_style.border_color = Color(0.25, 0.35, 0.50, 0.7)
	top_style.set_content_margin_all(10)
	top_bar.add_theme_stylebox_override("panel", top_style)
	root_ctrl.add_child(top_bar)

	var top_hbox := HBoxContainer.new()
	top_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	top_hbox.add_theme_constant_override("separation", 24)
	top_bar.add_child(top_hbox)

	var top_title := Label.new()
	top_title.text = "选择出战角色 (CHARACTER SELECTION)"
	if _custom_font != null:
		top_title.add_theme_font_override("font", _custom_font)
	top_title.add_theme_font_size_override("font_size", 22)
	top_title.modulate = Color(0.85, 0.75, 0.45)
	top_hbox.add_child(top_title)

	var role_str := "逃生者 (RUNNER)" if NetworkManager.local_role == NetworkManager.Role.RUNNER else "追缉者 (CHASER)"
	var top_role := Label.new()
	top_role.text = "【当前职责: %s】" % role_str
	top_role.add_theme_font_size_override("font_size", 14)
	top_role.modulate = Color(0.3, 0.85, 1.0) if NetworkManager.local_role == NetworkManager.Role.RUNNER else Color(1.0, 0.4, 0.3)
	top_hbox.add_child(top_role)

	# Left Bottom Stage Info Box
	var left_info_panel := PanelContainer.new()
	left_info_panel.set_anchors_preset(PRESET_BOTTOM_LEFT)
	left_info_panel.offset_left = 32
	left_info_panel.offset_bottom = -32
	left_info_panel.offset_right = 360
	left_info_panel.offset_top = -170
	left_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var l_style := StyleBoxFlat.new()
	l_style.bg_color = Color(0.06, 0.08, 0.12, 0.85)
	l_style.set_corner_radius_all(12)
	l_style.set_border_width_all(1)
	l_style.border_color = Color(0.3, 0.4, 0.55, 0.6)
	l_style.set_content_margin_all(16)
	left_info_panel.add_theme_stylebox_override("panel", l_style)
	root_ctrl.add_child(left_info_panel)

	var l_vbox := VBoxContainer.new()
	l_vbox.add_theme_constant_override("separation", 6)
	left_info_panel.add_child(l_vbox)

	_hero_name_lbl = Label.new()
	if _custom_font != null:
		_hero_name_lbl.add_theme_font_override("font", _custom_font)
	_hero_name_lbl.add_theme_font_size_override("font_size", 24)
	l_vbox.add_child(_hero_name_lbl)

	_hero_title_lbl = Label.new()
	if _glitch_font != null:
		_hero_title_lbl.add_theme_font_override("font", _glitch_font)
	_hero_title_lbl.add_theme_font_size_override("font_size", 13)
	_hero_title_lbl.modulate = Color(0.65, 0.75, 0.85)
	l_vbox.add_child(_hero_title_lbl)

	var drag_hint := Label.new()
	drag_hint.text = "💡 鼠标在中央按住左键拖拽可 360° 旋转视角"
	drag_hint.add_theme_font_size_override("font_size", 11)
	drag_hint.modulate = Color(0.45, 0.75, 0.95, 0.75)
	l_vbox.add_child(drag_hint)

	# Right Column: Hero Select Cards
	var right_panel := PanelContainer.new()
	right_panel.set_anchors_preset(PRESET_RIGHT_WIDE)
	right_panel.offset_left = -340
	right_panel.offset_top = 96
	right_panel.offset_right = -32
	right_panel.offset_bottom = -110

	var r_style := StyleBoxFlat.new()
	r_style.bg_color = Color(0.06, 0.08, 0.12, 0.85)
	r_style.set_corner_radius_all(12)
	r_style.set_border_width_all(1)
	r_style.border_color = Color(0.3, 0.4, 0.55, 0.6)
	r_style.set_content_margin_all(14)
	right_panel.add_theme_stylebox_override("panel", r_style)
	root_ctrl.add_child(right_panel)

	var r_vbox := VBoxContainer.new()
	r_vbox.add_theme_constant_override("separation", 10)
	right_panel.add_child(r_vbox)

	var card_title := Label.new()
	card_title.text = "候选角色列表 (ROSTER)"
	if _glitch_font != null:
		card_title.add_theme_font_override("font", _glitch_font)
	card_title.add_theme_font_size_override("font_size", 13)
	card_title.modulate = Color(0.75, 0.85, 0.95)
	r_vbox.add_child(card_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r_vbox.add_child(scroll)

	var scroll_vbox := VBoxContainer.new()
	scroll_vbox.add_theme_constant_override("separation", 8)
	scroll_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(scroll_vbox)

	_hero_card_btns.clear()
	for i in range(_roster.size()):
		var data: Dictionary = _roster[i]
		var card_btn := Button.new()
		card_btn.custom_minimum_size = Vector2(270, 64)

		var c_style := StyleBoxFlat.new()
		c_style.bg_color = Color(0.10, 0.13, 0.18, 0.9)
		c_style.set_corner_radius_all(8)
		c_style.set_border_width_all(1)
		c_style.border_color = Color(0.25, 0.35, 0.45)
		c_style.set_content_margin_all(8)
		card_btn.add_theme_stylebox_override("normal", c_style)

		var c_hover := StyleBoxFlat.new()
		c_hover.bg_color = Color(0.16, 0.20, 0.28, 0.95)
		c_hover.set_corner_radius_all(8)
		c_hover.set_border_width_all(2)
		c_hover.border_color = data["color"]
		c_hover.set_content_margin_all(8)
		card_btn.add_theme_stylebox_override("hover", c_hover)

		var c_hbox := HBoxContainer.new()
		c_hbox.set_anchors_preset(PRESET_FULL_RECT)
		c_hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
		c_hbox.add_theme_constant_override("separation", 12)
		c_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_btn.add_child(c_hbox)

		var av_holder := Control.new()
		av_holder.custom_minimum_size = Vector2(48, 48)
		av_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var av_icon := ProfileManager.create_avatar_circle(48.0, "builtin", data["avatar_key"], data["color"])
		av_holder.add_child(av_icon)
		c_hbox.add_child(av_holder)

		var info_col := VBoxContainer.new()
		info_col.alignment = BoxContainer.ALIGNMENT_CENTER
		info_col.add_theme_constant_override("separation", 2)
		info_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c_hbox.add_child(info_col)

		var n_lbl := Label.new()
		n_lbl.text = data["display_name"]
		if _custom_font != null:
			n_lbl.add_theme_font_override("font", _custom_font)
		n_lbl.add_theme_font_size_override("font_size", 16)
		n_lbl.modulate = data["color"]
		n_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info_col.add_child(n_lbl)

		var t_lbl := Label.new()
		t_lbl.text = "ID: %s" % data["id"]
		t_lbl.add_theme_font_size_override("font_size", 11)
		t_lbl.modulate = Color(0.65, 0.70, 0.78)
		t_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info_col.add_child(t_lbl)

		card_btn.pressed.connect(_on_card_selected.bind(i))
		_hero_card_btns.append(card_btn)
		scroll_vbox.add_child(card_btn)

	# Bottom Action & Lock Bar
	var bot_panel := PanelContainer.new()
	bot_panel.set_anchors_preset(PRESET_BOTTOM_WIDE)
	bot_panel.offset_left = 380
	bot_panel.offset_right = -32
	bot_panel.offset_top = -96
	bot_panel.offset_bottom = -24

	var b_style := StyleBoxFlat.new()
	b_style.bg_color = Color(0.06, 0.08, 0.12, 0.90)
	b_style.set_corner_radius_all(10)
	b_style.set_border_width_all(1)
	b_style.border_color = Color(0.3, 0.4, 0.55, 0.6)
	b_style.set_content_margin_all(12)
	bot_panel.add_theme_stylebox_override("panel", b_style)
	root_ctrl.add_child(bot_panel)

	var bot_hbox := HBoxContainer.new()
	bot_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	bot_hbox.add_theme_constant_override("separation", 24)
	bot_panel.add_child(bot_hbox)

	var status_vbox := VBoxContainer.new()
	status_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	status_vbox.add_theme_constant_override("separation", 2)
	bot_hbox.add_child(status_vbox)

	_status_local_lbl = Label.new()
	_status_local_lbl.text = "🟡 己方状态: 正在选择中..."
	_status_local_lbl.add_theme_font_size_override("font_size", 13)
	_status_local_lbl.modulate = Color(1.0, 0.85, 0.3)
	status_vbox.add_child(_status_local_lbl)

	_status_remote_lbl = Label.new()
	_status_remote_lbl.text = "⏳ 对手状态: 正在挑选角色..."
	_status_remote_lbl.add_theme_font_size_override("font_size", 13)
	_status_remote_lbl.modulate = Color(0.65, 0.75, 0.85)
	status_vbox.add_child(_status_remote_lbl)

	_lock_btn = Button.new()
	_lock_btn.text = "⚔ 确认出战 (LOCK IN)"
	_lock_btn.custom_minimum_size = Vector2(220, 48)
	if _custom_font != null:
		_lock_btn.add_theme_font_override("font", _custom_font)
	_lock_btn.add_theme_font_size_override("font_size", 18)
	_lock_btn.pressed.connect(_on_lock_in_pressed)

	var lock_style := StyleBoxFlat.new()
	lock_style.bg_color = Color(0.85, 0.45, 0.15, 0.95)
	lock_style.set_corner_radius_all(8)
	lock_style.set_content_margin_all(10)
	_lock_btn.add_theme_stylebox_override("normal", lock_style)
	bot_hbox.add_child(_lock_btn)


func _on_card_selected(idx: int) -> void:
	if NetworkManager.local_hero_locked:
		return
	AudioManagerScript.play_voice_file("res://assets/voice/sfx/swing_mid_01.wav", -6.0)
	_select_hero(idx, true)


func _on_lock_in_pressed() -> void:
	if NetworkManager.local_hero_locked or _is_transitioning:
		return
	NetworkManager.local_hero_locked = true
	_status_local_lbl.text = "🟢 己方状态: 已锁定出战！"
	_status_local_lbl.modulate = Color(0.3, 1.0, 0.5)

	_lock_btn.text = "✔ 已锁定就绪"
	_lock_btn.disabled = true
	_lock_btn.modulate = Color(0.6, 0.6, 0.6)

	AudioManagerScript.play_voice_file("res://assets/voice/sfx/swing_mid_01.wav", -2.0)
	var data: Dictionary = _roster[_selected_idx]
	NetworkManager.rpc("rpc_sync_hero_pick", data["scene"], true)

	_check_both_locked()


func _on_network_hero_changed(is_local: bool, _hero_scene: String, is_locked: bool) -> void:
	if not is_local:
		if is_locked:
			_status_remote_lbl.text = "🟢 对手状态: 已锁定出战！"
			_status_remote_lbl.modulate = Color(0.3, 1.0, 0.5)
		else:
			_status_remote_lbl.text = "⏳ 对手状态: 正在挑选角色..."
			_status_remote_lbl.modulate = Color(0.65, 0.75, 0.85)

	_check_both_locked()


func _check_both_locked() -> void:
	if NetworkManager.local_hero_locked and (NetworkManager.remote_hero_locked or NetworkManager.connected_peer_id <= 0):
		if _is_transitioning:
			return
		_is_transitioning = true

		# Slow cinematic burn transition
		if _transition_mat != null:
			_transition_mat.set_shader_parameter("progress", 0.0)
			var tw_burn := create_tween()
			tw_burn.tween_method(func(v: float): _transition_mat.set_shader_parameter("progress", v), 0.0, 1.0, 0.95).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
			tw_burn.tween_callback(func():
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				SceneLoader.change_scene(get_tree(), MULTIPLAYER_CHASE_SCENE, "双方英雄就绪，正在切入追缉战场...")
			)
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			SceneLoader.change_scene(get_tree(), MULTIPLAYER_CHASE_SCENE, "双方英雄就绪，正在切入追缉战场...")


func _build_transition_overlay() -> void:
	var trans_canvas := CanvasLayer.new()
	trans_canvas.layer = 30
	add_child(trans_canvas)

	_transition_rect = ColorRect.new()
	_transition_rect.set_anchors_preset(PRESET_FULL_RECT)
	_transition_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if ResourceLoader.exists("res://shaders/ember_burn_transition.gdshader"):
		var shader_res := load("res://shaders/ember_burn_transition.gdshader") as Shader
		_transition_mat = ShaderMaterial.new()
		_transition_mat.shader = shader_res
		_transition_mat.set_shader_parameter("progress", 0.0)
		_transition_mat.set_shader_parameter("ember_color", Color(1.0, 0.45, 0.12, 1.0))
		_transition_mat.set_shader_parameter("char_color", Color(0.04, 0.03, 0.03, 1.0))
		_transition_rect.material = _transition_mat

	trans_canvas.add_child(_transition_rect)
