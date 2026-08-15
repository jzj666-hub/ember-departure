extends Node3D
## Third-person test playground scene. Spawns test geometry (stair, pads, pillars) and character body.
## Controls: WASD to move, Shift to run, Ctrl to crouch, Space to jump/climb, Double Shift to roll, Tab to swap character, Esc to exit.

const CharacterPipelineScript = preload("res://tools/character_pipeline.gd")
const PlayerControllerScript = preload("res://scripts/player_controller.gd")
const PlayerIntentSourceScript = preload("res://scripts/player_intent_source.gd")
const FollowCameraScript = preload("res://scripts/follow_camera.gd")

const MENU_SCENE := "res://scenes/main_menu.tscn"

## Half-width of the floor, in metres.
const GROUND_HALF := 40.0
const SPAWN := Vector3(0.0, 0.2, -6.0)

## Height difference in meters between stair treads.
const CLIMB_STEP := 1.4

var _characters: Array = []
var _index := 0
var _player: CharacterBody3D
var _camera: Camera3D
var _visual: Node3D

var _state_label: Label
var _hint_label: Label


func _ready() -> void:
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
	_camera.connect("mode_changed", func(_fp: bool) -> void: _refresh_hint())
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

	# add_child() has run the character's _ready(), so its height and its
	# AnimationPlayer are both resolved by now.
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


# --- hud ------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(300, 0)
	panel.modulate = Color(1, 1, 1, 0.9)
	layer.add_child(panel)

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


func _process(_delta: float) -> void:
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
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_tree().change_scene_to_file(MENU_SCENE)
		KEY_TAB:
			_index = (_index + 1) % _characters.size()
			_spawn_character()
