extends SceneTree
## Generates scenes/anim_debug.tscn: lighting, ground and an orbit camera rig,
## wired to scripts/anim_debug.gd.
##
## Characters are NOT baked in - anim_debug.gd loads every one it finds at
## runtime, so adding a character never means regenerating this scene.
##
## Does NOT touch the project's main scene. That is scenes/main_menu.tscn, which
## opens this one and the playground; pointing F5 straight back here on every
## regeneration would silently undo the menu.
##
##   godot --headless --path <project> --script res://tools/build_debug_scene.gd

const SCRIPT := "res://scripts/anim_debug.gd"
const OUT_PATH := "res://scenes/anim_debug.tscn"

func _initialize() -> void:
	var root := Node3D.new()
	root.name = "AnimDebug"

	var characters := Node3D.new()
	characters.name = "Characters"

	_add(root, _make_environment())
	_add(root, _make_light("KeyLight", -50.0, -40.0, 2.6, true))
	_add(root, _make_light("FillLight", -20.0, 140.0, 0.6, false))
	_add(root, _make_ground())
	_add(root, _make_camera_rig(), true)
	_add(root, characters)

	root.set_script(load(SCRIPT))
	root.set("characters_root", characters)

	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		printerr("pack failed: %d" % err)
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(OUT_PATH.get_base_dir())
	err = ResourceSaver.save(packed, OUT_PATH)
	if err != OK:
		printerr("save failed: %d" % err)
		quit(1)
		return
	print("wrote %s" % OUT_PATH)

	root.free()
	quit(0)


## Children must be owned by the root or pack() drops them.
func _add(root: Node, child: Node, own_descendants := false) -> void:
	root.add_child(child)
	child.owner = root
	if own_descendants:
		for n in _walk(child):
			n.owner = root


func _make_environment() -> WorldEnvironment:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.36, 0.50)
	sky_mat.sky_horizon_color = Color(0.55, 0.58, 0.62)
	sky_mat.ground_bottom_color = Color(0.14, 0.14, 0.16)
	sky_mat.ground_horizon_color = Color(0.55, 0.58, 0.62)

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true

	var node := WorldEnvironment.new()
	node.name = "WorldEnvironment"
	node.environment = env
	return node


func _make_light(name: String, pitch_deg: float, yaw_deg: float,
		energy: float, shadows: bool) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = name
	light.light_energy = energy
	light.shadow_enabled = shadows
	light.transform.basis = Basis.from_euler(
		Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0.0))
	light.position = Vector3(0.0, 4.0, 0.0)
	return light


func _make_ground() -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(24.0, 24.0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.17, 0.18, 0.20)
	mat.roughness = 0.95
	mat.metallic = 0.0
	plane.material = mat

	var node := MeshInstance3D.new()
	node.name = "Ground"
	node.mesh = plane
	return node


## Yaw on the rig, pitch on the child, distance on the camera: the script drives
## these three independently.
func _make_camera_rig() -> Node3D:
	var rig := Node3D.new()
	rig.name = "CameraRig"
	rig.position = Vector3(0.0, 1.0, 0.0)
	rig.rotation = Vector3(0.0, 0.55, 0.0)

	var pitch := Node3D.new()
	pitch.name = "Pitch"
	pitch.rotation = Vector3(-0.18, 0.0, 0.0)
	rig.add_child(pitch)

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.position = Vector3(0.0, 0.0, 3.6)
	cam.fov = 50.0
	cam.near = 0.05
	pitch.add_child(cam)
	return rig


func _walk(node: Node, out: Array = []) -> Array:
	for c in node.get_children():
		out.append(c)
		_walk(c, out)
	return out
