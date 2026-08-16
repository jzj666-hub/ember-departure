extends Node3D

const CharacterPipelineScript = preload("res://tools/character_pipeline.gd")
const PlayerControllerScript = preload("res://scripts/player_controller.gd")
const PlayerIntentSourceScript = preload("res://scripts/player_intent_source.gd")
const FollowCameraScript = preload("res://scripts/follow_camera.gd")
const AudioManagerScript = preload("res://scripts/audio_manager.gd")

const MENU_SCENE := "res://scenes/main_menu.tscn"
const FONT_PATH := "res://assets/Fonts/Long_Cang/LongCang-Regular.ttf"

## Half-width of the floor, in metres.
const GROUND_HALF := 40.0
const SPAWN := Vector3(0.0, 0.2, -6.0)

## Height difference in meters between stair treads.
const CLIMB_STEP := 1.4

static var start_with_tutorial: bool = false
static var return_scene: String = "res://scenes/main_menu.tscn"

var _characters: Array = []
var _index := 0
var _player: CharacterBody3D
var _camera: Camera3D
var _visual: Node3D
var _custom_font: Font = null

var _state_label: Label
var _hint_label: Label

# Tutorial State
var _tutorial_active := false
var _tutorial_step := 0
var _tutorial_accum_dist := 0.0
var _tutorial_accum_run := 0.0
var _camera_toggled_during_step := false
var _hud_layer: CanvasLayer

var _tutorial_banner: PanelContainer
var _tutorial_banner_style: StyleBoxFlat
var _tutorial_step_label: Label
var _tutorial_title_label: Label
var _tutorial_sub_label: Label
var _tutorial_keys_container: HBoxContainer
var _tutorial_complete_dialog: PanelContainer
var _tutorial_climb_prop: StaticBody3D
var _tutorial_arrow: Node3D


func _ready() -> void:
	if ResourceLoader.exists(FONT_PATH):
		_custom_font = load(FONT_PATH) as Font

	AudioManagerScript.init_pool(self)

	_characters = CharacterPipelineScript.list_characters().filter(
		func(c: Dictionary) -> bool: return ResourceLoader.exists(c.scene))
	if _characters.is_empty():
		push_error("no character scenes - run tools\\rebuild_assets.bat first")
		return

	_build_environment()
	_build_ground()
	_build_props()
	_build_player()
	_build_hud()

	if start_with_tutorial:
		_start_interactive_tutorial()


# --- world ----------------------------------------------------------------

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
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled = true
	# Without this the trail's `energy` above 1 is indistinguishable from 1: the
	# HDR headroom is where the whole bright-core look lives.
	environment.glow_enabled = true
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	environment.glow_intensity = 0.9
	environment.glow_bloom = 0.15
	environment.glow_hdr_threshold = 1.0
	# Distance haze: the far pillars fading is another cue that the near ones are
	# rushing past.
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.55, 0.59, 0.66)
	environment.fog_density = 0.006

	var node := WorldEnvironment.new()
	node.name = "WorldEnvironment"
	node.environment = environment
	add_child(node)

	add_child(_make_light("KeyLight", -48.0, -35.0, 2.4, true))
	add_child(_make_light("FillLight", -18.0, 145.0, 0.5, false))


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


## Ground plane with collision and 1m grid shader.
func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"

	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_HALF * 2.0, GROUND_HALF * 2.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.19, 0.20, 0.22)
	material.roughness = 0.95
	plane.material = material
	mesh.mesh = plane
	body.add_child(mesh)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(GROUND_HALF * 2.0, 0.4, GROUND_HALF * 2.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.2, 0.0)
	body.add_child(shape)
	add_child(body)

	add_child(_make_grid())


func _make_grid() -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	var half := int(GROUND_HALF)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(-half, half + 1):
		var major := i % 10 == 0
		var colour := Color(0.42, 0.47, 0.56, 0.55) if major else Color(0.30, 0.32, 0.36, 0.25)
		mesh.surface_set_color(colour)
		mesh.surface_add_vertex(Vector3(i, 0.0, -half))
		mesh.surface_add_vertex(Vector3(i, 0.0, half))
		mesh.surface_set_color(colour)
		mesh.surface_add_vertex(Vector3(-half, 0.0, i))
		mesh.surface_add_vertex(Vector3(half, 0.0, i))
	mesh.surface_end()

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var node := MeshInstance3D.new()
	node.name = "Grid"
	node.mesh = mesh
	node.material_override = material
	node.position.y = 0.003  # clear of the ground plane, or they z-fight
	return node


## Generates static test environment props layout.
func _build_props() -> void:
	var props := Node3D.new()
	props.name = "Props"
	add_child(props)

	# A measuring lane: one marker every 2 m straight ahead of the spawn, so the
	# ground covered can be read off in metres instead of eyeballed.
	for i in 12:
		var post := _make_box(Vector3(0.16, 0.5 + (0.35 if i % 5 == 0 else 0.0), 0.16),
			Color(0.62, 0.55, 0.34) if i % 5 == 0 else Color(0.34, 0.36, 0.40))
		post.position = Vector3(2.6, 0.0, SPAWN.z + 2.0 * (i + 1))
		props.add_child(post)

	# Near clutter, both sides of the lane.
	var clutter := [
		[Vector3(-3.4, 0.0, -2.0), Vector3(1.2, 0.9, 1.2)],
		[Vector3(-5.2, 0.0, 3.5), Vector3(0.8, 1.9, 0.8)],
		[Vector3(4.6, 0.0, -0.5), Vector3(1.6, 0.6, 2.4)],
		[Vector3(-2.2, 0.0, 8.0), Vector3(2.2, 0.4, 2.2)],
		[Vector3(6.0, 0.0, 7.0), Vector3(0.9, 2.6, 0.9)],
		[Vector3(-7.0, 0.0, -5.5), Vector3(1.4, 1.4, 1.4)],
		[Vector3(1.5, 0.0, 13.0), Vector3(3.0, 0.3, 3.0)],
		[Vector3(-4.0, 0.0, 16.0), Vector3(1.0, 3.2, 1.0)],
	]
	for entry in clutter:
		var box := _make_box(entry[1] as Vector3, Color(0.30, 0.33, 0.38))
		box.position = entry[0] as Vector3
		props.add_child(box)

	# A low block to walk onto, so the ground is not the only height in the scene.
	var step := _make_box(Vector3(4.0, 0.35, 4.0), Color(0.36, 0.34, 0.30))
	step.position = Vector3(-10.0, 0.0, 6.0)
	props.add_child(step)

	_build_parkour(props)

	# Far ring: sweeps past when you turn, and marks how big the floor is.
	for i in 14:
		var angle := TAU * i / 14.0
		var pillar := _make_cylinder(0.55, 5.0 + 1.5 * (i % 3), Color(0.26, 0.28, 0.33))
		pillar.position = Vector3(sin(angle) * 26.0, 0.0, cos(angle) * 26.0)
		props.add_child(pillar)


## Spawns test stairs and platforms to verify ledge detection, climbing, and fall landing logic.
func _build_parkour(props: Node3D) -> void:
	for i in 4:
		var tread := _make_box(Vector3(3.4, CLIMB_STEP * (i + 1), 3.0),
			Color(0.33, 0.30, 0.27))
		tread.position = Vector3(-13.0, 0.0, 1.0 + 3.0 * i)
		props.add_child(tread)

	for i in 3:
		var pad := _make_box(Vector3(2.2, 0.35 + 0.6 * i, 2.2), Color(0.38, 0.35, 0.30))
		pad.position = Vector3(9.5, 0.0, -2.0 + 4.0 * i)
		props.add_child(pad)


## Utility to align mesh pivot bottom to the floor plane.
func _make_box(size: Vector3, colour: Color) -> StaticBody3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var shape := BoxShape3D.new()
	shape.size = size
	return _make_prop(mesh, shape, size.y, colour)


func _make_cylinder(radius: float, height: float, colour: Color) -> StaticBody3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	return _make_prop(mesh, shape, height, colour)


func _make_prop(mesh: Mesh, shape: Shape3D, height: float, colour: Color) -> StaticBody3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.9
	(mesh as PrimitiveMesh).material = material

	var body := StaticBody3D.new()
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.position.y = height * 0.5
	body.add_child(view)

	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = height * 0.5
	body.add_child(collider)
	return body


# --- player ---------------------------------------------------------------

## Spawns character and wraps it in a PlayerController.
func _build_player() -> void:
	_player = PlayerControllerScript.new()
	_player.name = "Player"
	_player.position = SPAWN
	# The seam a bot goes through later: the controller reads a CharacterIntent
	# and does not care who filled it in. Swap this for another IntentSource, or
	# set it to null and drive the controller through drive() / request_jump() /
	# request_roll() instead.
	_player.intent_source = PlayerIntentSourceScript.new()
	add_child(_player)

	_camera = FollowCameraScript.new()
	_camera.name = "Camera"
	_camera.fov = 55.0
	_camera.near = 0.05
	_camera.current = true
	_camera.connect("mode_changed", func(_fp: bool) -> void:
		_refresh_hint()
		if _tutorial_active and _tutorial_step == 5:
			_camera_toggled_during_step = true
	)
	add_child(_camera)

	_spawn_character()


func _spawn_character() -> void:
	if _visual != null:
		_visual.queue_free()
		_visual = null
	for child in _player.get_children():
		child.queue_free()

	var entry: Dictionary = _characters[_index]
	var scene := load(entry.scene) as PackedScene
	if scene == null:
		push_error("%s: scene will not load" % entry.id)
		return
	_visual = scene.instantiate() as Node3D
	_player.add_child(_visual)

	var height: float = _visual.get("body_height")
	if height <= 0.1:
		height = 1.75

	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
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
	_refresh_hint()


# --- hud & tutorial --------------------------------------------------------

func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "HUD"
	add_child(_hud_layer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(300, 0)
	panel.modulate = Color(1, 1, 1, 0.9)
	_hud_layer.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	_state_label = Label.new()
	_state_label.add_theme_font_size_override("font_size", 13)
	box.add_child(_state_label)

	box.add_child(HSeparator.new())

	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", 11)
	_hint_label.modulate = Color(1, 1, 1, 0.7)
	box.add_child(_hint_label)
	_refresh_hint()


func _refresh_hint() -> void:
	if _hint_label == null:
		return
	var entry: Dictionary = _characters[_index]
	var mode_str := "第一视角" if (_camera != null and bool(_camera.get("is_first_person"))) else "第三视角"
	_hint_label.text = "WASD 移动 · 鼠标 转向 · Shift 跑（仅直行 W）· Ctrl 蹲\n" \
		+ "空格 跳跃 / 攀爬 · F3 切换视角（当前: %s）\n" % mode_str \
		+ "双击 Shift 翻滚 · 走下平台自动下落，落地按落差分三档\n" \
		+ "Tab 换角色 (%s, %d/%d) · Esc 返回菜单" % [
			entry.id, _index + 1, _characters.size()]


func _start_interactive_tutorial() -> void:
	_tutorial_active = true
	_tutorial_step = 0
	_build_tutorial_arrow()
	_setup_tutorial_world()
	_build_tutorial_banner()
	_build_tutorial_complete_dialog()
	_set_tutorial_step(0)


func _build_tutorial_arrow() -> void:
	_tutorial_arrow = Node3D.new()
	_tutorial_arrow.name = "TutorialArrow"
	_tutorial_arrow.visible = false

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.25)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.25)
	mat.emission_energy_multiplier = 2.0

	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.0
	cone_mesh.bottom_radius = 0.35
	cone_mesh.height = 0.6
	cone_mesh.material = mat

	var cone_inst := MeshInstance3D.new()
	cone_inst.mesh = cone_mesh
	cone_inst.rotation.x = PI
	cone_inst.position.y = 0.3
	_tutorial_arrow.add_child(cone_inst)

	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.12
	shaft_mesh.bottom_radius = 0.12
	shaft_mesh.height = 0.5
	shaft_mesh.material = mat

	var shaft_inst := MeshInstance3D.new()
	shaft_inst.mesh = shaft_mesh
	shaft_inst.position.y = 0.75
	_tutorial_arrow.add_child(shaft_inst)

	add_child(_tutorial_arrow)


func _setup_tutorial_world() -> void:
	if _tutorial_climb_prop != null:
		return
	_tutorial_climb_prop = _make_box(Vector3(4.0, 2.0, 3.0), Color(0.22, 0.35, 0.50))
	_tutorial_climb_prop.position = Vector3(0.0, 0.0, -1.5)
	_tutorial_climb_prop.name = "TutorialClimbPlatform"
	add_child(_tutorial_climb_prop)

	var edge_mesh := ImmediateMesh.new()
	edge_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	edge_mesh.surface_set_color(Color(1.0, 0.85, 0.25))
	edge_mesh.surface_add_vertex(Vector3(-2.0, 2.02, -1.5))
	edge_mesh.surface_add_vertex(Vector3(2.0, 2.02, -1.5))
	edge_mesh.surface_end()

	var edge_mat := StandardMaterial3D.new()
	edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge_mat.vertex_color_use_as_albedo = true

	var edge_inst := MeshInstance3D.new()
	edge_inst.mesh = edge_mesh
	edge_inst.material_override = edge_mat
	_tutorial_climb_prop.add_child(edge_inst)

	_tutorial_arrow.position = Vector3(0.0, 2.8, -3.0)
	_tutorial_arrow.visible = false


func _build_tutorial_banner() -> void:
	_tutorial_banner = PanelContainer.new()
	_tutorial_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_tutorial_banner.offset_left = -350
	_tutorial_banner.offset_right = 350
	_tutorial_banner.offset_top = 40
	_tutorial_banner.offset_bottom = 145
	_tutorial_banner.custom_minimum_size = Vector2(700, 105)
	_tutorial_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_tutorial_banner_style = StyleBoxFlat.new()
	_tutorial_banner_style.bg_color = Color(0.08, 0.10, 0.14, 0.96)
	_tutorial_banner_style.set_corner_radius_all(12)
	_tutorial_banner_style.set_border_width_all(2)
	_tutorial_banner_style.border_color = Color(0.3, 0.85, 1.0)
	_tutorial_banner_style.set_content_margin_all(14)
	_tutorial_banner.add_theme_stylebox_override("panel", _tutorial_banner_style)
	_hud_layer.add_child(_tutorial_banner)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 18)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_tutorial_banner.add_child(hbox)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(vbox)

	_tutorial_title_label = Label.new()
	if _custom_font != null:
		_tutorial_title_label.add_theme_font_override("font", _custom_font)
	_tutorial_title_label.add_theme_font_size_override("font_size", 20)
	_tutorial_title_label.modulate = Color(1.0, 0.88, 0.3)
	vbox.add_child(_tutorial_title_label)

	_tutorial_sub_label = Label.new()
	_tutorial_sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _custom_font != null:
		_tutorial_sub_label.add_theme_font_override("font", _custom_font)
	_tutorial_sub_label.add_theme_font_size_override("font_size", 14)
	_tutorial_sub_label.modulate = Color(0.9, 0.92, 0.96)
	vbox.add_child(_tutorial_sub_label)

	_tutorial_keys_container = HBoxContainer.new()
	_tutorial_keys_container.add_theme_constant_override("separation", 6)
	_tutorial_keys_container.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(_tutorial_keys_container)


func _rebuild_tutorial_keys(keys: Array[String]) -> void:
	for child in _tutorial_keys_container.get_children():
		_tutorial_keys_container.remove_child(child)
		child.queue_free()
	for k in keys:
		if k == "+" or k == "或" or k == "/":
			var lbl := Label.new()
			lbl.text = " %s " % k
			lbl.add_theme_font_size_override("font_size", 16)
			lbl.modulate = Color(1.0, 0.85, 0.3)
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_tutorial_keys_container.add_child(lbl)
		else:
			var path := "res://assets/buttons_pattern/%s.png" % k
			var tex_rect := TextureRect.new()
			if ResourceLoader.exists(path):
				tex_rect.texture = load(path)
			tex_rect.custom_minimum_size = Vector2(38, 38)
			tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			_tutorial_keys_container.add_child(tex_rect)


func _set_tutorial_step(step: int) -> void:
	_tutorial_step = step
	_tutorial_accum_dist = 0.0
	_tutorial_accum_run = 0.0
	_camera_toggled_during_step = false

	match step:
		0:
			_tutorial_banner_style.border_color = Color(0.3, 0.85, 1.0)
			_tutorial_title_label.text = "🎯 基础身法 (1/6): 前后左右位移"
			_tutorial_sub_label.text = "使用键盘 【W / A / S / D】 键控制角色在场景中自由行走走动。"
			_rebuild_tutorial_keys(["W", "A", "S", "D"])
			if _tutorial_arrow != null:
				_tutorial_arrow.visible = false
		1:
			_tutorial_banner_style.border_color = Color(1.0, 0.75, 0.2)
			_tutorial_title_label.text = "🎯 基础身法 (2/6): 疾步冲刺奔跑"
			_tutorial_sub_label.text = "按住 【Shift】 键并按住 【W】 直线向前，角色将进入全力疾跑冲刺状态！"
			_rebuild_tutorial_keys(["SHIFT", "+", "W"])
			if _tutorial_arrow != null:
				_tutorial_arrow.visible = false
		2:
			_tutorial_banner_style.border_color = Color(0.35, 0.9, 0.6)
			_tutorial_title_label.text = "🎯 基础身法 (3/6): 起跳腾空"
			_tutorial_sub_label.text = "按下 【空格键 (Space)】，角色将发力向上起跳腾空！"
			_rebuild_tutorial_keys(["SPACE"])
			if _tutorial_arrow != null:
				_tutorial_arrow.visible = false
		3:
			_tutorial_banner_style.border_color = Color(1.0, 0.85, 0.3)
			_tutorial_title_label.text = "🎯 基础身法 (4/6): 攀登 2 格高台"
			_tutorial_sub_label.text = "贴近前方发光的 2 格高障碍平台边缘，按下 【空格键 (Space)】 触发物理攀登翻越上台！"
			_rebuild_tutorial_keys(["W", "+", "SPACE"])
			if _tutorial_arrow != null:
				_tutorial_arrow.visible = true
		4:
			_tutorial_banner_style.border_color = Color(0.85, 0.4, 1.0)
			_tutorial_title_label.text = "🎯 基础身法 (5/6): 敏捷战术翻滚"
			_tutorial_sub_label.text = "在地面移动时按下 【Ctrl 键】（或 C 键 / 快速双击 Shift），角色将进行敏捷的战术翻滚闪避！"
			_rebuild_tutorial_keys(["CTRL", "或", "C"])
			if _tutorial_arrow != null:
				_tutorial_arrow.visible = false
		5:
			_tutorial_banner_style.border_color = Color(0.2, 0.9, 0.95)
			_tutorial_title_label.text = "🎯 基础身法 (6/6): 视界自由切换"
			_tutorial_sub_label.text = "按下 【F3 键】 体验第一人称沉浸视角与第三人称全景视角的自由切换！"
			_rebuild_tutorial_keys(["F3"])
			if _tutorial_arrow != null:
				_tutorial_arrow.visible = false
		6:
			if _tutorial_banner != null:
				_tutorial_banner.visible = false
			if _tutorial_arrow != null:
				_tutorial_arrow.visible = false
			if _tutorial_complete_dialog != null:
				_tutorial_complete_dialog.visible = true
			AudioManagerScript.play_voice_file("res://assets/voice/Voiceover Pack/Male/mission_completed.ogg", 0.0)


func _advance_tutorial(next_step: int) -> void:
	AudioManagerScript.play_voice_file("res://assets/voice/Voiceover Pack/Male/go.ogg", -4.0)
	_set_tutorial_step(next_step)


func _build_tutorial_complete_dialog() -> void:
	_tutorial_complete_dialog = PanelContainer.new()
	_tutorial_complete_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_tutorial_complete_dialog.offset_left = -280
	_tutorial_complete_dialog.offset_right = 280
	_tutorial_complete_dialog.offset_top = -170
	_tutorial_complete_dialog.offset_bottom = 170
	_tutorial_complete_dialog.custom_minimum_size = Vector2(560, 340)
	_tutorial_complete_dialog.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.11, 0.16, 0.98)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(24)
	style.set_border_width_all(2)
	style.border_color = Color(0.3, 0.9, 0.6)
	_tutorial_complete_dialog.add_theme_stylebox_override("panel", style)
	_hud_layer.add_child(_tutorial_complete_dialog)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	_tutorial_complete_dialog.add_child(vbox)

	var title := Label.new()
	title.text = "🎉 身法大师 · 互动教学圆满完成！"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _custom_font != null:
		title.add_theme_font_override("font", _custom_font)
	title.add_theme_font_size_override("font_size", 24)
	title.modulate = Color(0.3, 0.95, 0.65)
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = "恭喜您已全面掌握物理动力学角色引擎的核心动作：\n• WASD 位移与 Shift 极速冲刺\n• 空格跳跃与 2 格高台攀登翻越\n• Ctrl 敏捷战术翻滚闪避\n• F3 第一/第三人称视界切换\n\n现在您可以尽情在沙盒中自由体验与探索！"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _custom_font != null:
		desc.add_theme_font_override("font", _custom_font)
	desc.add_theme_font_size_override("font_size", 14)
	desc.modulate = Color(0.88, 0.92, 0.96)
	vbox.add_child(desc)

	var continue_btn := Button.new()
	continue_btn.text = "✨ 继续自由试玩 (Free Play)"
	if _custom_font != null:
		continue_btn.add_theme_font_override("font", _custom_font)
	continue_btn.add_theme_font_size_override("font_size", 16)
	continue_btn.custom_minimum_size = Vector2(220, 44)
	continue_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	continue_btn.pressed.connect(func() -> void:
		_tutorial_complete_dialog.visible = false
	)
	vbox.add_child(continue_btn)


func _update_tutorial_state(delta: float) -> void:
	if not _tutorial_active or _player == null:
		return

	if _tutorial_arrow != null and _tutorial_arrow.visible:
		var time := Time.get_ticks_msec() * 0.003
		_tutorial_arrow.position.y = 2.8 + sin(time) * 0.2

	match _tutorial_step:
		0:
			if _player.speed() > 0.2:
				_tutorial_accum_dist += _player.speed() * delta
			if _tutorial_accum_dist >= 2.5:
				_advance_tutorial(1)
		1:
			if _player.state == PlayerControllerScript.State.RUN:
				_tutorial_accum_run += delta
			if _tutorial_accum_run >= 1.2:
				_advance_tutorial(2)
		2:
			if _player.state == PlayerControllerScript.State.JUMPING:
				_advance_tutorial(3)
		3:
			if _player.state == PlayerControllerScript.State.CLIMBING:
				_advance_tutorial(4)
		4:
			if _player.state == PlayerControllerScript.State.ROLLING:
				_advance_tutorial(5)
		5:
			if _camera_toggled_during_step:
				_advance_tutorial(6)


func _process(delta: float) -> void:
	if _tutorial_active:
		_update_tutorial_state(delta)

	if _state_label == null or _player == null:
		return
	var mode_str := "[第一视角]" if (_camera != null and bool(_camera.get("is_first_person"))) else "[第三视角]"
	_state_label.text = "%s %s   %.2f m/s   高度 %.2f m\n站立时鼠标只转视角；一移动，角色转向视角方向" % [
		mode_str, _player.state_name(), _player.speed(), _player.global_position.y]


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_ESCAPE:
			if _tutorial_complete_dialog != null and _tutorial_complete_dialog.visible:
				_tutorial_complete_dialog.visible = false
				return
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_tree().change_scene_to_file(return_scene)
		KEY_TAB:
			_index = (_index + 1) % _characters.size()
			_spawn_character()
		KEY_F3:
			if _tutorial_active and _tutorial_step == 5:
				_camera_toggled_during_step = true

