extends Node3D
## Continuous-map navigation test: NPC pathfinds over a baked NavigationMesh with
## no voxel grid anywhere. The ramp is the point - a slope has no integer height,
## so NavGrid cannot represent it at all, and the NPC still walks up it without a
## single line of NPCIntentSource changing.
##
## Controls: WASD/QE fly, mouse look, LMB set target, TAB free cursor, ESC menu.

const CharacterPipelineScript = preload("res://tools/character_pipeline.gd")
const PlayerControllerScript = preload("res://scripts/player_controller.gd")
const NPCIntentSourceScript = preload("res://scripts/npc_intent_source.gd")
const NavMeshProviderScript = preload("res://scripts/nav_mesh_provider.gd")
const FollowCameraScript = preload("res://scripts/follow_camera.gd")
const WorldBuilderScript = preload("res://scripts/world/world_builder.gd")
const ENV_PRESET = preload("res://config/env/plain_blue.tres")

const MENU_SCENE := "res://scenes/main_menu.tscn"
const GROUND_HALF := 20.0
const SPAWN_POS := Vector3(-8.0, 0.2, -8.0)

const LOOK_SENS := 0.0026
const PITCH_LIMIT := 1.5
const FLY_DAMP := 12.0
const FLY_SPRINT := 3.0
const FLY_MIN := 2.0
const FLY_MAX := 40.0
const AIM_REACH := 120.0

## Bake resolution. Height is the one that matters for behaviour - see
## _build_navigation().
const CELL_SIZE := 0.15
const CELL_HEIGHT := 0.05

var _nav := NavMeshProviderScript.new()
var _region: NavigationRegion3D
var _geometry_root: Node3D

var _npc: CharacterBody3D
var _visual: Node3D
var _follow_camera: Camera3D
var _fly_camera: Camera3D
var _npc_intent_source: NPCIntentSource

var _path_mesh: ImmediateMesh
var _beacon: Node3D

var _status_label: Label
var _hint_label: Label
var _nav_status := "尚未指定目的地"

var _cursor_free := false
var _cam_yaw := 0.0
var _cam_pitch := -0.45
var _cam_velocity := Vector3.ZERO
var _fly_speed := 9.0


func _ready() -> void:
	_build_environment()
	_build_world()
	_build_navigation()
	_build_visual_helpers()
	_build_cameras()
	_build_npc()
	_build_hud()
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# The server publishes a baked map one physics frame later; querying before
	# that answers empty. Bind after the sync, not after the bake.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_nav.bind_region(_region)
	_npc_intent_source.bind_nav_grid(_nav)
	_nav_status = "导航网格就绪 · 准星对准地面按 LMB 指定目的地" if _nav.is_ready() \
		else "导航网格烘焙失败"


# --- world ------------------------------------------------------------------

func _build_environment() -> void:
	WorldBuilderScript.build_environment(self, ENV_PRESET)


## Every piece here is off-grid on purpose: rotated, sloped or round. None of it
## has a voxel footprint, which is what makes this map unrepresentable in NavGrid.
func _build_world() -> void:
	_geometry_root = Node3D.new()
	_geometry_root.name = "Geometry"
	add_child(_geometry_root)

	_add_box(Vector3(0.0, -0.2, 0.0), Vector3(GROUND_HALF * 2.0, 0.4, GROUND_HALF * 2.0),
		Vector3.ZERO, Color(0.18, 0.20, 0.23), "Ground")

	# Ramp up to the platform: ~17 degrees, rises 2 m over 6.5 m of run, and its
	# top end overlaps the platform edge so the two rasterize as one surface.
	_add_box(Vector3(5.0, 0.95, 0.25), Vector3(4.0, 0.4, 6.8),
		Vector3(deg_to_rad(-17.1), 0.0, 0.0), Color(0.42, 0.36, 0.28), "Ramp")
	_add_box(Vector3(5.0, 1.0, 6.0), Vector3(10.0, 2.0, 6.0),
		Vector3.ZERO, Color(0.30, 0.33, 0.36), "Platform")

	# Rotated walls - the angles are the point.
	_add_box(Vector3(-6.0, 1.2, 1.0), Vector3(0.8, 2.4, 9.0),
		Vector3(0.0, deg_to_rad(28.0), 0.0), Color(0.35, 0.30, 0.30), "WallA")
	_add_box(Vector3(-2.0, 1.2, -9.0), Vector3(0.8, 2.4, 7.0),
		Vector3(0.0, deg_to_rad(-52.0), 0.0), Color(0.35, 0.30, 0.30), "WallB")

	_add_cylinder(Vector3(-10.0, 1.5, 8.0), 1.6, 3.0, Color(0.33, 0.36, 0.31), "Pillar")
	_add_cylinder(Vector3(9.0, 1.5, -10.0), 2.2, 3.0, Color(0.33, 0.36, 0.31), "Pillar2")


func _add_box(pos: Vector3, size: Vector3, euler: Vector3, colour: Color, name_hint: String) -> void:
	var body := StaticBody3D.new()
	body.name = name_hint
	body.transform = Transform3D(Basis.from_euler(euler), pos)

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.9
	box.material = mat
	mesh.mesh = box
	body.add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	_geometry_root.add_child(body)


func _add_cylinder(pos: Vector3, radius: float, height: float, colour: Color, name_hint: String) -> void:
	var body := StaticBody3D.new()
	body.name = name_hint
	body.position = pos

	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.85
	cyl.material = mat
	mesh.mesh = cyl
	body.add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	col.shape = shape
	body.add_child(col)
	_geometry_root.add_child(body)


## Bakes the region from the static colliders under _geometry_root.
## Agent metrics mirror the character capsule so the mesh is inset where the body
## actually cannot fit - the voxel graph got the same guarantee from head_cells().
##
## Cell height drives how far the baked surface floats above the real one, and
## that offset lands straight on top of every leg's dy. The executor reads a dy
## past its step tolerance (~0.4 m) as a ledge, so a coarse bake makes the body
## try to jump flat ground. 0.05 keeps the mesh within noise of the collider.
func _build_navigation() -> void:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = 0.4
	nav_mesh.agent_height = 1.8
	nav_mesh.agent_max_climb = 0.4
	nav_mesh.agent_max_slope = 45.0
	nav_mesh.cell_size = CELL_SIZE
	nav_mesh.cell_height = CELL_HEIGHT
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN

	# The map rasterizes on its own cells; leaving them at the project defaults
	# while the bake uses finer ones is what the "mismatch" warning is about.
	var map := get_world_3d().get_navigation_map()
	NavigationServer3D.map_set_cell_size(map, CELL_SIZE)
	NavigationServer3D.map_set_cell_height(map, CELL_HEIGHT)

	_region = NavigationRegion3D.new()
	_region.name = "NavRegion"
	_region.navigation_mesh = nav_mesh
	add_child(_region)

	# Source geometry is read from the region's children, so the world has to hang
	# under it for the bake to see anything.
	_geometry_root.reparent(_region)
	_region.bake_navigation_mesh(false)


## Probe hook: replaces the world with a flat run into a single step of `height`
## metres, rebakes, and puts the body at the near end facing it.
##
## Sub-metre steps cannot exist on a voxel map - every cell is 1 m - so this is a
## case only a continuous map produces, and the one the executor has no rule for.
## Post: the step's top face is at y == height; body starts at z == -5.
func setup_step_course(height: float) -> void:
	for child in _geometry_root.get_children():
		_geometry_root.remove_child(child)
		child.queue_free()

	_add_box(Vector3(0.0, -0.2, 0.0), Vector3(24.0, 0.4, 24.0), Vector3.ZERO,
		Color(0.18, 0.20, 0.23), "Ground")
	_add_box(Vector3(0.0, height * 0.5, 5.0), Vector3(12.0, maxf(height, 0.01), 8.0),
		Vector3.ZERO, Color(0.42, 0.36, 0.28), "Step")

	_region.bake_navigation_mesh(false)
	await get_tree().physics_frame
	await get_tree().physics_frame

	_npc.global_position = Vector3(0.0, 0.3, -5.0)
	_npc.velocity = Vector3.ZERO
	_npc_intent_source.clear_target()


# --- helpers ----------------------------------------------------------------

func _build_visual_helpers() -> void:
	_path_mesh = ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _path_mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mi.material_override = mat
	add_child(mi)

	_beacon = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.28
	sphere.height = 0.56
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(1.0, 0.35, 0.25)
	bmat.emission_enabled = true
	bmat.emission = Color(1.0, 0.35, 0.25)
	sphere.material = bmat
	(_beacon as MeshInstance3D).mesh = sphere
	_beacon.visible = false
	add_child(_beacon)


func _draw_path(points: PackedVector3Array) -> void:
	_path_mesh.clear_surfaces()
	if points.size() < 2:
		return
	_path_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(1, points.size()):
		var colour := Color(0.2, 0.95, 0.55, 0.9)
		_path_mesh.surface_set_color(colour)
		_path_mesh.surface_add_vertex(points[i - 1] + Vector3(0.0, 0.12, 0.0))
		_path_mesh.surface_set_color(colour)
		_path_mesh.surface_add_vertex(points[i] + Vector3(0.0, 0.12, 0.0))
	_path_mesh.surface_end()


func _build_cameras() -> void:
	_follow_camera = FollowCameraScript.new()
	_follow_camera.fov = 55.0
	_follow_camera.near = 0.05
	add_child(_follow_camera)

	_fly_camera = Camera3D.new()
	_fly_camera.fov = 65.0
	_fly_camera.near = 0.05
	_fly_camera.far = 400.0
	add_child(_fly_camera)
	_fly_camera.global_position = Vector3(-14.0, 12.0, -18.0)
	_cam_yaw = deg_to_rad(35.0)
	_apply_fly_orientation()
	_fly_camera.current = true


func _apply_fly_orientation() -> void:
	_fly_camera.global_transform = Transform3D(
		Basis.from_euler(Vector3(_cam_pitch, _cam_yaw, 0.0)),
		_fly_camera.global_position)


func _build_npc() -> void:
	_npc = PlayerControllerScript.new()
	_npc.name = "NPC"
	_npc.position = SPAWN_POS

	_npc_intent_source = NPCIntentSourceScript.new()
	_npc.intent_source = _npc_intent_source
	_npc_intent_source.repath_requested.connect(_on_repath_requested)
	_npc_intent_source.path_finished.connect(_on_path_finished)
	_npc_intent_source.path_blocked.connect(_on_path_blocked)
	add_child(_npc)

	var characters: Array = CharacterPipelineScript.list_characters().filter(
		func(c: Dictionary) -> bool: return ResourceLoader.exists(c.scene))
	if characters.is_empty():
		push_error("no character scenes available")
		return
	var scene := load(characters[0].scene) as PackedScene
	if scene == null:
		return
	_visual = scene.instantiate() as Node3D
	_npc.add_child(_visual)

	var height: float = _visual.get("body_height")
	if height <= 0.1:
		height = 1.75

	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = minf(0.3, height * 0.2)
	capsule.height = height
	collider.shape = capsule
	collider.position.y = height * 0.5
	_npc.add_child(collider)

	_npc.setup(_visual, _follow_camera)
	_follow_camera.target = _npc
	_follow_camera.frame_for(height)
	_follow_camera.snap()

	# Same contract as the voxel path: the rules come off the body, not the map.
	_nav.set_capability(_npc)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(20, 20)
	layer.add_child(panel)

	var box := VBoxContainer.new()
	panel.add_child(box)

	_status_label = Label.new()
	box.add_child(_status_label)

	_hint_label = Label.new()
	_hint_label.text = "WASD/QE 飞行 · 鼠标看向 · LMB 指定目的地 · TAB 释放光标 · ESC 返回菜单"
	box.add_child(_hint_label)

	var cross := Label.new()
	cross.text = "+"
	cross.set_anchors_preset(Control.PRESET_CENTER)
	layer.add_child(cross)


# --- input & loop -----------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				get_tree().change_scene_to_file(MENU_SCENE)
				return
			KEY_TAB:
				_cursor_free = not _cursor_free
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _cursor_free \
					else Input.MOUSE_MODE_CAPTURED
				return

	if event is InputEventMouseMotion and not _cursor_free:
		_cam_yaw -= event.relative.x * LOOK_SENS
		_cam_pitch = clampf(_cam_pitch - event.relative.y * LOOK_SENS, -PITCH_LIMIT, PITCH_LIMIT)
		_apply_fly_orientation()

	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and not _cursor_free:
		_pick_target()


func _process(delta: float) -> void:
	_drive_fly_camera(delta)
	if _status_label != null:
		_status_label.text = _nav_status


func _drive_fly_camera(delta: float) -> void:
	if _cursor_free:
		return
	var dir := Vector3.ZERO
	var basis := _fly_camera.global_transform.basis
	if Input.is_key_pressed(KEY_W): dir -= basis.z
	if Input.is_key_pressed(KEY_S): dir += basis.z
	if Input.is_key_pressed(KEY_A): dir -= basis.x
	if Input.is_key_pressed(KEY_D): dir += basis.x
	if Input.is_key_pressed(KEY_E): dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q): dir -= Vector3.UP

	var speed := _fly_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= FLY_SPRINT
	var wanted := dir.normalized() * speed
	_cam_velocity = _cam_velocity.lerp(wanted, clampf(FLY_DAMP * delta, 0.0, 1.0))
	_fly_camera.global_position += _cam_velocity * delta
	_apply_fly_orientation()


## Raycasts the crosshair into the world and routes the NPC to what it hits.
func _pick_target() -> void:
	var from := _fly_camera.global_position
	var to := from - _fly_camera.global_transform.basis.z * AIM_REACH
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_npc.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_nav_status = "准星没有指向任何几何体"
		return
	_route_to(hit.position)


func _route_to(target: Vector3) -> void:
	var result := _nav.find_path(_npc.global_position, target)
	var points: PackedVector3Array = result.points
	if points.is_empty():
		_npc_intent_source.clear_target()
		_draw_path(PackedVector3Array())
		_beacon.visible = false
		_nav_status = "无法从当前位置起步（不在导航网格上？）"
		return

	_npc_intent_source.set_plan_result(result)
	_draw_path(points)
	_beacon.global_position = target
	_beacon.visible = true
	_report(result)


func _report(result: Dictionary) -> void:
	var points: PackedVector3Array = result.points
	var rise := 0.0
	for i in range(1, points.size()):
		rise += maxf(points[i].y - points[i - 1].y, 0.0)
	if bool(result.complete):
		_nav_status = "路径 %d 段 · 累计爬升 %.1f m · 全程 WALK（连续地图无跳跃段）" % [
			points.size(), rise]
	else:
		var last: Vector3 = points[points.size() - 1]
		_nav_status = "目标不可达，已移动至最近点 (%.1f, %.1f, %.1f) · 路径 %d 段" % [
			last.x, last.y, last.z, points.size()]


func _on_repath_requested(from_pos: Vector3, target: Vector3) -> void:
	var result := _nav.find_path(from_pos, target)
	if result.points.is_empty():
		_npc_intent_source.clear_target()
		_nav_status = "受阻且无可用路径，已停止"
		return
	_npc_intent_source.set_plan_result(result)
	_draw_path(result.points)
	_report(result)


func _on_path_finished(_target: Vector3) -> void:
	_beacon.visible = false
	_draw_path(PackedVector3Array())
	_nav_status = "已抵达目的地"


func _on_path_blocked(_target: Vector3, reachable: Vector3) -> void:
	_beacon.visible = false
	_draw_path(PackedVector3Array())
	_nav_status = "目标不可达，已停在最近点 (%.1f, %.1f, %.1f)" % [
		reachable.x, reachable.y, reachable.z]
