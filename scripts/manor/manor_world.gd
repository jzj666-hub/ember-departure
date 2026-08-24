extends Node3D

const CharacterPipelineScript = preload("res://tools/character_pipeline.gd")
const PlayerControllerScript = preload("res://scripts/player_controller.gd")
const PlayerIntentSourceScript = preload("res://scripts/player_intent_source.gd")
const FollowCameraScript = preload("res://scripts/follow_camera.gd")
const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const ManorTeleporterScript = preload("res://scripts/manor/manor_teleporter.gd")
const ManorMerchantScript = preload("res://scripts/manor/manor_merchant.gd")
const ManorNpcWanderScript = preload("res://scripts/manor/manor_npc_wander.gd")
const ManorChairScript = preload("res://scripts/manor/manor_chair.gd")
const WorldBuilderScript = preload("res://scripts/world/world_builder.gd")
const ENV_PRESET = preload("res://config/env/manor.tres")

const MENU_SCENE := "res://scenes/main_menu.tscn"
const FONT_CHINESE := "res://assets/Fonts/Long_Cang/LongCang-Regular.ttf"
const SHADER_TERRAIN := "res://shaders/manor_terrain.gdshader"
const SHADER_GRASS := "res://shaders/grass_wind.gdshader"

const TEX_GRASS := "res://assets/scene_objects/glTF/Grass.png"
const TEX_FLOWERS := "res://assets/scene_objects/glTF/Flowers.png"
const TEX_PATH := "res://assets/scene_objects/glTF/PathRocks_Diffuse.png"
const TEX_ROCK := "res://assets/scene_objects/glTF/Rocks_Diffuse.png"

# Outdoor & Indoor Coordinates
const OUTDOOR_SPAWN := Vector3(0.0, 0.3, 10.0)
const OUTDOOR_PORTAL_POS := Vector3(0.0, 0.1, -11.2)
const INDOOR_ORIGIN := Vector3(300.0, 50.0, 300.0)
const INDOOR_SPAWN := Vector3(300.0, 50.2, 304.5)
const INDOOR_PORTAL_POS := Vector3(300.0, 50.1, 305.8)

# Terrain Parameters
const TERRAIN_SIZE := 140.0
const TERRAIN_RES := 70 # 70x70 quads -> 2m per quad

var _player: CharacterBody3D
var _camera: Camera3D
var _visual: Node3D
var _geometry_root: Node3D
var _indoor_root: Node3D
var _nav_region: NavigationRegion3D
var _wandering_npcs: Array[PlayerController] = []

# Teleporters
var _outdoor_teleporter: Node3D
var _indoor_teleporter: Node3D

# HUD elements
var _hud_layer: CanvasLayer
var _gold_label: Label
var _voucher_label: Label
var _fade_rect: ColorRect
var _is_teleporting: bool = false
var _font_chinese: Font = null


func _ready() -> void:
	if ResourceLoader.exists(FONT_CHINESE):
		_font_chinese = load(FONT_CHINESE) as Font

	AudioManagerScript.init_pool(self)

	_build_environment()
	_build_navigation_and_world()
	_build_indoor_manor()
	_build_teleporters()
	_build_player()
	_build_hud()

	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var prof = _get_profile()
	if prof != null:
		if not prof.currency_changed.is_connected(_on_currency_changed):
			prof.currency_changed.connect(_on_currency_changed)
	_update_currency_display()


func _get_profile() -> Node:
	if has_node("/root/ProfileManager"):
		return get_node("/root/ProfileManager")
	return null


func _physics_process(_delta: float) -> void:
	if _player != null:
		# Fail-safe recovery if player somehow falls out of bounds
		if _player.global_position.x > 200.0 and _player.global_position.y < 35.0:
			_player.global_position = INDOOR_SPAWN
			_player.velocity = Vector3.ZERO
		elif _player.global_position.y < -30.0:
			_player.global_position = OUTDOOR_SPAWN
			_player.velocity = Vector3.ZERO


# --- Environment & Lighting --------------------------------------------------

func _build_environment() -> void:
	WorldBuilderScript.build_environment(self, ENV_PRESET)


# --- Continuous World & Buildings -------------------------------------------

func _build_navigation_and_world() -> void:
	_nav_region = NavigationRegion3D.new()
	_nav_region.name = "NavRegion"
	add_child(_nav_region)

	_geometry_root = Node3D.new()
	_geometry_root.name = "OutdoorGeometry"
	_nav_region.add_child(_geometry_root)

	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.012
	noise.fractal_octaves = 3

	_build_continuous_terrain(noise)
	_build_estate_buildings(noise)
	_build_vegetation_and_props(noise)
	_build_automatic_grass_coverage(noise)
	_build_wandering_npcs(noise)


func _get_terrain_height(x: float, z: float, noise: FastNoiseLite) -> float:
	var dist_center := Vector2(x, z).length()
	var base_height: float = noise.get_noise_2d(x, z) * 6.5
	var flat_factor: float = clampf((dist_center - 22.0) / 20.0, 0.0, 1.0)
	return base_height * flat_factor


## Generates continuous natural terrain with rolling hills, rich multi-texture shader, and collision.
func _build_continuous_terrain(noise: FastNoiseLite) -> void:
	var half := TERRAIN_SIZE * 0.5
	var step := TERRAIN_SIZE / float(TERRAIN_RES)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var heights: Array = []
	for z_idx in range(TERRAIN_RES + 1):
		var row: Array = []
		var z := -half + float(z_idx) * step
		for x_idx in range(TERRAIN_RES + 1):
			var x := -half + float(x_idx) * step
			var h := _get_terrain_height(x, z, noise)
			row.append(h)
		heights.append(row)

	for z_idx in range(TERRAIN_RES):
		var z0 := -half + float(z_idx) * step
		var z1 := z0 + step
		for x_idx in range(TERRAIN_RES):
			var x0 := -half + float(x_idx) * step
			var x1 := x0 + step

			var h00: float = heights[z_idx][x_idx]
			var h10: float = heights[z_idx][x_idx + 1]
			var h01: float = heights[z_idx + 1][x_idx]
			var h11: float = heights[z_idx + 1][x_idx + 1]

			var p00 := Vector3(x0, h00, z0)
			var p10 := Vector3(x1, h10, z0)
			var p01 := Vector3(x0, h01, z1)
			var p11 := Vector3(x1, h11, z1)

			# Tri 1
			st.set_uv(Vector2(x0 / 10.0, z0 / 10.0))
			st.add_vertex(p00)

			st.set_uv(Vector2(x1 / 10.0, z0 / 10.0))
			st.add_vertex(p10)

			st.set_uv(Vector2(x0 / 10.0, z1 / 10.0))
			st.add_vertex(p01)

			# Tri 2
			st.set_uv(Vector2(x1 / 10.0, z0 / 10.0))
			st.add_vertex(p10)

			st.set_uv(Vector2(x1 / 10.0, z1 / 10.0))
			st.add_vertex(p11)

			st.set_uv(Vector2(x0 / 10.0, z1 / 10.0))
			st.add_vertex(p01)

	st.generate_normals()
	st.generate_tangents()
	var terrain_mesh := st.commit()

	var terrain_body := StaticBody3D.new()
	terrain_body.name = "ContinuousTerrain"

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = terrain_mesh

	# Rich Procedural Natural Terrain Shader with Real Textures
	if ResourceLoader.exists(SHADER_TERRAIN):
		var sh := load(SHADER_TERRAIN) as Shader
		var s_mat := ShaderMaterial.new()
		s_mat.shader = sh
		if ResourceLoader.exists(TEX_GRASS):
			s_mat.set_shader_parameter("grass_tex", load(TEX_GRASS))
		if ResourceLoader.exists(TEX_PATH):
			s_mat.set_shader_parameter("path_tex", load(TEX_PATH))
		if ResourceLoader.exists(TEX_ROCK):
			s_mat.set_shader_parameter("rock_tex", load(TEX_ROCK))
		mesh_inst.material_override = s_mat
	else:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.32, 0.46, 0.24)
		mat.roughness = 0.9
		mesh_inst.material_override = mat

	terrain_body.add_child(mesh_inst)

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(terrain_mesh.get_faces())
	var col := CollisionShape3D.new()
	col.shape = shape
	terrain_body.add_child(col)
	_geometry_root.add_child(terrain_body)


## Automatic GPU MultiMesh grass and wildflower coverage with dynamic wind waving.
func _build_automatic_grass_coverage(noise: FastNoiseLite) -> void:
	# 1. Main Lawn Grass MultiMesh (~3,000 sparse tufts with dynamic wind wave)
	var grass_scn = load("res://assets/scene_objects/glTF/Grass_Common_Short.gltf") as PackedScene
	if grass_scn != null:
		var g_inst = grass_scn.instantiate()
		var mesh_node: MeshInstance3D = null
		for c in g_inst.get_children():
			if c is MeshInstance3D:
				mesh_node = c
				break
		if mesh_node != null and mesh_node.mesh != null:
			var grass_mesh: Mesh = mesh_node.mesh
			var transforms: Array[Transform3D] = []
			var rng := RandomNumberGenerator.new()
			rng.seed = 1337

			var attempts := 3800
			for i in range(attempts):
				var rx := rng.randf_range(-64.0, 64.0)
				var rz := rng.randf_range(-64.0, 64.0)

				# Avoid stone path and building footprints
				if abs(rx) < 2.4 and rz > -16.0 and rz < 12.0:
					continue
				if rx > -12.0 and rx < 12.0 and rz > -28.0 and rz < -10.0:
					continue
				if rx > 16.0 and rx < 30.0 and rz > -18.0 and rz < -6.0:
					continue
				if rx < -18.0 and rx > -32.0 and rz > -26.0 and rz < -10.0:
					continue

				var ry := _get_terrain_height(rx, rz, noise)
				var r_rot := rng.randf_range(0.0, TAU)
				var r_scale_xz := rng.randf_range(0.35, 0.55)
				var r_scale_y := rng.randf_range(0.28, 0.42)

				var t := Transform3D(Basis.from_euler(Vector3(0.0, r_rot, 0.0)).scaled(Vector3(r_scale_xz, r_scale_y, r_scale_xz)), Vector3(rx, ry, rz))
				transforms.append(t)

			var mm_grass := MultiMesh.new()
			mm_grass.transform_format = MultiMesh.TRANSFORM_3D
			mm_grass.mesh = grass_mesh
			mm_grass.instance_count = transforms.size()

			for idx in range(transforms.size()):
				mm_grass.set_instance_transform(idx, transforms[idx])

			var mmi_grass := MultiMeshInstance3D.new()
			mmi_grass.name = "GrassMultiMesh"
			mmi_grass.multimesh = mm_grass

			# Apply dynamic wind swaying shader
			if ResourceLoader.exists(SHADER_GRASS):
				var g_sh := load(SHADER_GRASS) as Shader
				var g_mat := ShaderMaterial.new()
				g_mat.shader = g_sh
				if ResourceLoader.exists(TEX_GRASS):
					g_mat.set_shader_parameter("grass_texture", load(TEX_GRASS))
				g_mat.set_shader_parameter("wind_speed", 2.2)
				g_mat.set_shader_parameter("wind_strength", 0.32)
				mmi_grass.material_override = g_mat

			_geometry_root.add_child(mmi_grass)
		g_inst.free()

	# 2. Wildflower Clusters MultiMesh (~600 sparse accents with dynamic wind sway)
	var flower_scn = load("res://assets/scene_objects/glTF/Flower_3_Group.gltf") as PackedScene
	if flower_scn != null:
		var f_inst = flower_scn.instantiate()
		var f_mesh_node: MeshInstance3D = null
		for c in f_inst.get_children():
			if c is MeshInstance3D:
				f_mesh_node = c
				break
		if f_mesh_node != null and f_mesh_node.mesh != null:
			var flower_mesh: Mesh = f_mesh_node.mesh
			var flower_transforms: Array[Transform3D] = []
			var f_rng := RandomNumberGenerator.new()
			f_rng.seed = 2048

			var f_attempts := 750
			for i in range(f_attempts):
				var fx := f_rng.randf_range(-60.0, 60.0)
				var fz := f_rng.randf_range(-60.0, 60.0)

				if abs(fx) < 2.4 and fz > -16.0 and fz < 12.0:
					continue
				if fx > -12.0 and fx < 12.0 and fz > -28.0 and fz < -10.0:
					continue

				var fy := _get_terrain_height(fx, fz, noise)
				var f_rot := f_rng.randf_range(0.0, TAU)
				var f_scale := f_rng.randf_range(0.35, 0.55)

				var t := Transform3D(Basis.from_euler(Vector3(0.0, f_rot, 0.0)).scaled(Vector3(f_scale, f_scale, f_scale)), Vector3(fx, fy, fz))
				flower_transforms.append(t)

			var mm_flower := MultiMesh.new()
			mm_flower.transform_format = MultiMesh.TRANSFORM_3D
			mm_flower.mesh = flower_mesh
			mm_flower.instance_count = flower_transforms.size()

			for idx in range(flower_transforms.size()):
				mm_flower.set_instance_transform(idx, flower_transforms[idx])

			var mmi_flower := MultiMeshInstance3D.new()
			mmi_flower.name = "FlowerMultiMesh"
			mmi_flower.multimesh = mm_flower

			# Apply dynamic wind swaying shader
			if ResourceLoader.exists(SHADER_GRASS):
				var f_sh := load(SHADER_GRASS) as Shader
				var f_mat := ShaderMaterial.new()
				f_mat.shader = f_sh
				if ResourceLoader.exists(TEX_FLOWERS):
					f_mat.set_shader_parameter("grass_texture", load(TEX_FLOWERS))
				f_mat.set_shader_parameter("wind_speed", 2.0)
				f_mat.set_shader_parameter("wind_strength", 0.26)
				mmi_flower.material_override = f_mat

			_geometry_root.add_child(mmi_flower)
		f_inst.free()

	# 3. Clover Tufts MultiMesh (~600 sparse accents with dynamic wind sway)
	var clover_scn = load("res://assets/scene_objects/glTF/Clover_1.gltf") as PackedScene
	if clover_scn != null:
		var c_inst = clover_scn.instantiate()
		var c_mesh_node: MeshInstance3D = null
		for c in c_inst.get_children():
			if c is MeshInstance3D:
				c_mesh_node = c
				break
		if c_mesh_node != null and c_mesh_node.mesh != null:
			var clover_mesh: Mesh = c_mesh_node.mesh
			var clover_transforms: Array[Transform3D] = []
			var c_rng := RandomNumberGenerator.new()
			c_rng.seed = 4096

			var c_attempts := 700
			for i in range(c_attempts):
				var cx := c_rng.randf_range(-55.0, 55.0)
				var cz := c_rng.randf_range(-55.0, 55.0)

				if abs(cx) < 2.4 and cz > -16.0 and cz < 12.0:
					continue
				if cx > -12.0 and cx < 12.0 and cz > -28.0 and cz < -10.0:
					continue

				var cy := _get_terrain_height(cx, cz, noise)
				var c_rot := c_rng.randf_range(0.0, TAU)
				var c_scale := c_rng.randf_range(0.35, 0.55)

				var t := Transform3D(Basis.from_euler(Vector3(0.0, c_rot, 0.0)).scaled(Vector3(c_scale, c_scale, c_scale)), Vector3(cx, cy, cz))
				clover_transforms.append(t)

			var mm_clover := MultiMesh.new()
			mm_clover.transform_format = MultiMesh.TRANSFORM_3D
			mm_clover.mesh = clover_mesh
			mm_clover.instance_count = clover_transforms.size()

			for idx in range(clover_transforms.size()):
				mm_clover.set_instance_transform(idx, clover_transforms[idx])

			var mmi_clover := MultiMeshInstance3D.new()
			mmi_clover.name = "CloverMultiMesh"
			mmi_clover.multimesh = mm_clover

			# Apply dynamic wind swaying shader
			if ResourceLoader.exists(SHADER_GRASS):
				var c_sh := load(SHADER_GRASS) as Shader
				var c_mat := ShaderMaterial.new()
				c_mat.shader = c_sh
				if ResourceLoader.exists(TEX_GRASS):
					c_mat.set_shader_parameter("grass_texture", load(TEX_GRASS))
				c_mat.set_shader_parameter("wind_speed", 2.2)
				c_mat.set_shader_parameter("wind_strength", 0.28)
				mmi_clover.material_override = c_mat

			_geometry_root.add_child(mmi_clover)
		c_inst.free()


## Places estate architectural buildings with proper height and scale.
func _build_estate_buildings(noise: FastNoiseLite) -> void:
	# Main Manor Mansion (House_1) - scaled up to grand 3-story estate mansion (scale 3.6x)
	var h1_y: float = _get_terrain_height(0.0, -18.0, noise)
	_spawn_model("res://assets/scene_objects/FBX/House_1.fbx",
		Vector3(0.0, h1_y, -18.0), Vector3(0.0, 0.0, 0.0), Vector3(3.6, 3.6, 3.6), "MainManorHouse", true)

	# Bell Tower on northwest hill (scale 3.0x)
	var bt_y: float = _get_terrain_height(-24.0, -18.0, noise)
	_spawn_model("res://assets/scene_objects/FBX/Bell_Tower.fbx",
		Vector3(-24.0, bt_y, -18.0), Vector3(0.0, deg_to_rad(30.0), 0.0), Vector3(3.0, 3.0, 3.0), "BellTower", true)

	# Blacksmith on northeast terrace (scale 2.8x)
	var bs_y: float = _get_terrain_height(22.0, -12.0, noise)
	_spawn_model("res://assets/scene_objects/FBX/Blacksmith.fbx",
		Vector3(22.0, bs_y, -12.0), Vector3(0.0, deg_to_rad(-45.0), 0.0), Vector3(2.8, 2.8, 2.8), "Blacksmith", true)

	# Stable on east perimeter (scale 2.8x)
	var st_y: float = _get_terrain_height(26.0, 10.0, noise)
	_spawn_model("res://assets/scene_objects/FBX/Stable.fbx",
		Vector3(26.0, st_y, 10.0), Vector3(0.0, deg_to_rad(-90.0), 0.0), Vector3(2.8, 2.8, 2.8), "Stable", true)

	# Mill on southwest valley (scale 3.0x)
	var ml_y: float = _get_terrain_height(-26.0, 14.0, noise)
	_spawn_model("res://assets/scene_objects/FBX/Mill.fbx",
		Vector3(-26.0, ml_y, 14.0), Vector3(0.0, deg_to_rad(60.0), 0.0), Vector3(3.0, 3.0, 3.0), "Mill", true)

	# Sawmill on west (scale 2.8x)
	var sm_y: float = _get_terrain_height(-28.0, -2.0, noise)
	_spawn_model("res://assets/scene_objects/FBX/Sawmill.fbx",
		Vector3(-28.0, sm_y, -2.0), Vector3(0.0, deg_to_rad(15.0), 0.0), Vector3(2.8, 2.8, 2.8), "Sawmill", true)

	# Guest cottages
	var h2_y: float = _get_terrain_height(12.0, 24.0, noise)
	_spawn_model("res://assets/scene_objects/FBX/House_2.fbx",
		Vector3(12.0, h2_y, 24.0), Vector3(0.0, deg_to_rad(180.0), 0.0), Vector3(2.8, 2.8, 2.8), "GuestHouse1", true)
	var h3_y: float = _get_terrain_height(-14.0, 24.0, noise)
	_spawn_model("res://assets/scene_objects/FBX/House_3.fbx",
		Vector3(-14.0, h3_y, 24.0), Vector3(0.0, deg_to_rad(160.0), 0.0), Vector3(2.8, 2.8, 2.8), "GuestHouse2", true)
	var h4_y: float = _get_terrain_height(0.0, 32.0, noise)
	_spawn_model("res://assets/scene_objects/FBX/House_4.fbx",
		Vector3(0.0, h4_y, 32.0), Vector3(0.0, deg_to_rad(180.0), 0.0), Vector3(2.8, 2.8, 2.8), "GateHouse", true)


## Scatters trees, bushes, rocks, cobblestone paths and courtyard props firmly grounded on terrain.
func _build_vegetation_and_props(noise: FastNoiseLite) -> void:
	# Cobblestone path from spawn to manor entrance
	for i in range(8):
		var pz := 10.0 - float(i) * 2.6
		var py: float = _get_terrain_height(0.0, pz, noise) + 0.02
		_spawn_model("res://assets/scene_objects/glTF/RockPath_Round_Wide.gltf",
			Vector3(0.0, py, pz), Vector3(0.0, float(i) * 0.4, 0.0), Vector3(1.2, 1.0, 1.2), "Path_%d" % i, false)

	# Trees around the manor perimeter and hills - grounded dynamically with -0.15m sink
	var tree_models := [
		"res://assets/scene_objects/glTF/CommonTree_1.gltf",
		"res://assets/scene_objects/glTF/CommonTree_2.gltf",
		"res://assets/scene_objects/glTF/CommonTree_3.gltf",
		"res://assets/scene_objects/glTF/Pine_1.gltf",
		"res://assets/scene_objects/glTF/Pine_2.gltf",
		"res://assets/scene_objects/glTF/TwistedTree_1.gltf",
		"res://assets/scene_objects/glTF/TwistedTree_2.gltf",
	]

	var tree_coords := [
		Vector2(-10.0, -10.0), Vector2(10.0, -10.0),
		Vector2(-18.0, -6.0), Vector2(18.0, -4.0),
		Vector2(-34.0, -24.0), Vector2(32.0, -22.0),
		Vector2(-38.0, 10.0), Vector2(36.0, 16.0),
		Vector2(-20.0, 30.0), Vector2(20.0, 30.0),
		Vector2(-8.0, 18.0), Vector2(8.0, 18.0),
		Vector2(-30.0, -32.0), Vector2(30.0, -32.0),
		Vector2(0.0, -36.0), Vector2(14.0, -34.0),
		Vector2(-14.0, -34.0), Vector2(-45.0, 0.0),
		Vector2(45.0, 0.0), Vector2(0.0, 44.0)
	]

	for idx in range(tree_coords.size()):
		var tx: float = tree_coords[idx].x
		var tz: float = tree_coords[idx].y
		var ty: float = _get_terrain_height(tx, tz, noise) - 0.15 # Anchor roots firmly into ground
		var model_path: String = tree_models[idx % tree_models.size()]
		var t_scale := 1.2 + float(idx % 4) * 0.2
		var t_rot := float(idx) * 1.3
		_spawn_model(model_path, Vector3(tx, ty, tz), Vector3(0.0, t_rot, 0.0), Vector3(t_scale, t_scale, t_scale), "Tree_%d" % idx, true)

	# Bushes, Rocks & Flowers in courtyard
	var bush_coords := [
		Vector2(-5.0, -12.0), Vector2(5.0, -12.0),
		Vector2(-6.0, 4.0), Vector2(6.0, 4.0),
		Vector2(-12.0, 2.0), Vector2(12.0, 2.0)
	]
	for idx in range(bush_coords.size()):
		var bx: float = bush_coords[idx].x
		var bz: float = bush_coords[idx].y
		var by: float = _get_terrain_height(bx, bz, noise) - 0.05
		_spawn_model("res://assets/scene_objects/glTF/Bush_Common_Flowers.gltf",
			Vector3(bx, by, bz), Vector3.ZERO, Vector3(1.2, 1.2, 1.2), "Bush_%d" % idx, false)

	# Courtyard street lanterns & benches
	var b1_y: float = _get_terrain_height(-4.5, -2.0, noise)
	_spawn_model("res://assets/scene_objects/glTF/Bench.gltf",
		Vector3(-4.5, b1_y, -2.0), Vector3(0.0, deg_to_rad(90.0), 0.0), Vector3(1.0, 1.0, 1.0), "Bench_1", true)
	var chair_b1 := ManorChairScript.new()
	chair_b1.position = Vector3(-4.5, b1_y, -2.0)
	chair_b1.rotation.y = deg_to_rad(90.0)
	_geometry_root.add_child(chair_b1)

	var b2_y: float = _get_terrain_height(4.5, -2.0, noise)
	_spawn_model("res://assets/scene_objects/glTF/Bench.gltf",
		Vector3(4.5, b2_y, -2.0), Vector3(0.0, deg_to_rad(-90.0), 0.0), Vector3(1.0, 1.0, 1.0), "Bench_2", true)
	var chair_b2 := ManorChairScript.new()
	chair_b2.position = Vector3(4.5, b2_y, -2.0)
	chair_b2.rotation.y = deg_to_rad(-90.0)
	_geometry_root.add_child(chair_b2)

	var t1_y: float = _get_terrain_height(-2.2, -11.0, noise)
	_spawn_model("res://assets/scene_objects/glTF/Torch_Metal.gltf",
		Vector3(-2.2, t1_y, -11.0), Vector3.ZERO, Vector3(1.2, 1.2, 1.2), "Torch_Left", false)
	var t2_y: float = _get_terrain_height(2.2, -11.0, noise)
	_spawn_model("res://assets/scene_objects/glTF/Torch_Metal.gltf",
		Vector3(2.2, t2_y, -11.0), Vector3.ZERO, Vector3(1.2, 1.2, 1.2), "Torch_Right", false)


## Spawns NPC characters in the courtyard and surrounding estate grounds with autonomous wandering.
func _build_wandering_npcs(noise: FastNoiseLite) -> void:
	var npc_chars := CharacterPipelineScript.list_characters().filter(
		func(c: Dictionary) -> bool: return c.id.to_lower().contains("npc") and ResourceLoader.exists(c.scene))

	if npc_chars.is_empty():
		return

	var spawn_anchors := [
		Vector3(-6.0, 0.0, 7.0),   # Southwest garden path
		Vector3(6.0, 0.0, 7.5),    # Southeast courtyard
		Vector3(-4.5, 0.0, 0.5),   # West plaza near benches
		Vector3(5.5, 0.0, -1.0),   # East terrace
		Vector3(-1.5, 0.0, 16.0),  # South avenue entrance
		Vector3(10.0, 0.0, 14.0),  # Southeast lawn
		Vector3(-10.0, 0.0, 12.0), # Southwest lawn
	]

	for i in range(npc_chars.size()):
		var char_info: Dictionary = npc_chars[i]
		var scn := load(char_info.scene) as PackedScene
		if scn == null:
			continue

		var anchor: Vector3 = spawn_anchors[i % spawn_anchors.size()]
		var terrain_y := _get_terrain_height(anchor.x, anchor.z, noise) + 0.25
		anchor.y = terrain_y

		var npc := PlayerControllerScript.new()
		npc.name = "NPC_%s" % char_info.id
		npc.position = anchor

		var wander_source := ManorNpcWanderScript.new(anchor, 6.0)
		npc.intent_source = wander_source

		_geometry_root.add_child(npc)

		var visual := scn.instantiate() as Node3D
		npc.add_child(visual)

		var height: float = visual.get("body_height") if visual != null else 1.75
		if height <= 0.1:
			height = 1.75

		var collider := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = minf(0.3, height * 0.2)
		capsule.height = height
		collider.shape = capsule
		collider.position.y = height * 0.5
		npc.add_child(collider)

		npc.setup(visual, null)

		_wandering_npcs.append(npc)


# --- Indoor Environment -----------------------------------------------------

func _build_indoor_manor() -> void:
	_indoor_root = Node3D.new()
	_indoor_root.name = "IndoorManor"
	_indoor_root.position = INDOOR_ORIGIN
	add_child(_indoor_root)

	var room_w := 18.0
	var room_d := 14.0
	var room_h := 4.8

	# Floor
	_add_indoor_box(Vector3(0.0, -0.1, 0.0), Vector3(room_w, 0.2, room_d), Color(0.18, 0.12, 0.08), "IndoorFloor")
	# Ceiling
	_add_indoor_box(Vector3(0.0, room_h + 0.1, 0.0), Vector3(room_w, 0.2, room_d), Color(0.14, 0.10, 0.07), "IndoorCeiling")
	# North Wall (Back)
	_add_indoor_box(Vector3(0.0, room_h * 0.5, -room_d * 0.5), Vector3(room_w, room_h, 0.4), Color(0.24, 0.22, 0.20), "WallNorth")
	# South Wall (Solid with decorative entrance door frame - fully blocks void exit)
	_add_indoor_box(Vector3(0.0, room_h * 0.5, room_d * 0.5), Vector3(room_w, room_h, 0.4), Color(0.24, 0.22, 0.20), "WallSouth")
	# Decorative Indoor Door Frame & Panels
	_add_indoor_box(Vector3(0.0, 1.8, room_d * 0.5 - 0.05), Vector3(3.2, 3.6, 0.15), Color(0.16, 0.11, 0.07), "DoorPanelWood")
	_add_indoor_box(Vector3(-1.7, 1.8, room_d * 0.5 - 0.08), Vector3(0.3, 3.8, 0.2), Color(0.28, 0.18, 0.10), "DoorFrameL")
	_add_indoor_box(Vector3(1.7, 1.8, room_d * 0.5 - 0.08), Vector3(0.3, 3.8, 0.2), Color(0.28, 0.18, 0.10), "DoorFrameR")
	_add_indoor_box(Vector3(0.0, 3.7, room_d * 0.5 - 0.08), Vector3(3.7, 0.3, 0.2), Color(0.28, 0.18, 0.10), "DoorFrameTop")
	# West Wall
	_add_indoor_box(Vector3(-room_w * 0.5, room_h * 0.5, 0.0), Vector3(0.4, room_h, room_d), Color(0.24, 0.22, 0.20), "WallWest")
	# East Wall
	_add_indoor_box(Vector3(room_w * 0.5, room_h * 0.5, 0.0), Vector3(0.4, room_h, room_d), Color(0.24, 0.22, 0.20), "WallEast")

	# Indoor Warm Lighting
	var light_center := OmniLight3D.new()
	light_center.light_color = Color(1.0, 0.88, 0.65)
	light_energy_set(light_center, 1.4, 16.0, Vector3(0.0, 3.6, 0.0))
	_indoor_root.add_child(light_center)

	var light_fireplace := OmniLight3D.new()
	light_fireplace.light_color = Color(1.0, 0.55, 0.2)
	light_energy_set(light_fireplace, 1.6, 8.0, Vector3(-6.0, 1.2, -5.5))
	_indoor_root.add_child(light_fireplace)

	var light_vendor := OmniLight3D.new()
	light_vendor.light_color = Color(1.0, 0.92, 0.7)
	light_energy_set(light_vendor, 1.5, 9.0, Vector3(5.5, 2.2, -4.5))
	_indoor_root.add_child(light_vendor)

	# --- Furnishing ---
	# Fireplace Lounge (Northwest)
	_spawn_indoor_prop("res://assets/scene_objects/glTF/Fireplace.gltf",
		Vector3(-6.0, 0.0, -6.5), Vector3.ZERO, Vector3(1.3, 1.3, 1.3), "Fireplace", true)
	_spawn_indoor_prop("res://assets/scene_objects/glTF/Table_Large.gltf",
		Vector3(-4.0, 0.0, -2.5), Vector3.ZERO, Vector3(1.1, 1.1, 1.1), "LoungeTable", true)
	_spawn_indoor_prop("res://assets/scene_objects/glTF/Chair_1.gltf",
		Vector3(-5.5, 0.0, -2.5), Vector3(0.0, deg_to_rad(90.0), 0.0), Vector3(1.0, 1.0, 1.0), "Chair_1", true)
	var in_chair1 := ManorChairScript.new()
	in_chair1.position = Vector3(-5.5, 0.0, -2.5)
	in_chair1.rotation.y = deg_to_rad(90.0)
	_indoor_root.add_child(in_chair1)

	_spawn_indoor_prop("res://assets/scene_objects/glTF/Chair_1.gltf",
		Vector3(-2.5, 0.0, -2.5), Vector3(0.0, deg_to_rad(-90.0), 0.0), Vector3(1.0, 1.0, 1.0), "Chair_2", true)
	var in_chair2 := ManorChairScript.new()
	in_chair2.position = Vector3(-2.5, 0.0, -2.5)
	in_chair2.rotation.y = deg_to_rad(-90.0)
	_indoor_root.add_child(in_chair2)
	_spawn_indoor_prop("res://assets/scene_objects/glTF/Mug.gltf",
		Vector3(-3.8, 0.82, -2.3), Vector3.ZERO, Vector3(1.0, 1.0, 1.0), "Mug", false)

	# Study / Work Station (West)
	_spawn_indoor_prop("res://assets/scene_objects/glTF/Workbench.gltf",
		Vector3(-7.5, 0.0, 2.0), Vector3(0.0, deg_to_rad(90.0), 0.0), Vector3(1.2, 1.2, 1.2), "Desk", true)
	_spawn_indoor_prop("res://assets/scene_objects/glTF/Bookcase_2.gltf",
		Vector3(-7.8, 0.0, -0.5), Vector3(0.0, deg_to_rad(90.0), 0.0), Vector3(1.2, 1.2, 1.2), "Bookcase1", true)
	_spawn_indoor_prop("res://assets/scene_objects/glTF/Book_Stack_1.gltf",
		Vector3(-7.5, 0.85, 2.2), Vector3.ZERO, Vector3(1.0, 1.0, 1.0), "BookStack", false)
	_spawn_indoor_prop("res://assets/scene_objects/glTF/Scroll_1.gltf",
		Vector3(-7.5, 0.85, 1.6), Vector3.ZERO, Vector3(1.0, 1.0, 1.0), "Scroll", false)

	# Bedroom Corner (Southwest)
	_spawn_indoor_prop("res://assets/scene_objects/glTF/Bed_Twin1.gltf",
		Vector3(-6.5, 0.0, 5.0), Vector3(0.0, deg_to_rad(180.0), 0.0), Vector3(1.2, 1.2, 1.2), "Bed", true)
	_spawn_indoor_prop("res://assets/scene_objects/glTF/Nightstand_Shelf.gltf",
		Vector3(-8.0, 0.0, 5.0), Vector3(0.0, deg_to_rad(90.0), 0.0), Vector3(1.1, 1.1, 1.1), "Nightstand", true)
	_spawn_indoor_prop("res://assets/scene_objects/glTF/Chest_Wood.gltf",
		Vector3(-4.0, 0.0, 5.8), Vector3.ZERO, Vector3(1.1, 1.1, 1.1), "Chest", true)

	# Armory & Trophies (North Center)
	_spawn_indoor_prop("res://assets/scene_objects/glTF/WeaponStand.gltf",
		Vector3(0.0, 0.0, -6.2), Vector3.ZERO, Vector3(1.2, 1.2, 1.2), "WeaponStand", true)
	_spawn_indoor_prop("res://assets/scene_objects/glTF/Shield_Wooden.gltf",
		Vector3(1.2, 1.6, -6.7), Vector3.ZERO, Vector3(1.2, 1.2, 1.2), "ShieldWall", false)
	_spawn_indoor_prop("res://assets/scene_objects/glTF/Banner_1.gltf",
		Vector3(-1.4, 1.5, -6.7), Vector3.ZERO, Vector3(1.2, 1.2, 1.2), "BannerWall", false)

	# Merchant Trading Post (Northeast)
	_spawn_indoor_prop("res://assets/scene_objects/glTF/Stall_Empty.gltf",
		Vector3(5.5, 0.0, -4.5), Vector3(0.0, deg_to_rad(180.0), 0.0), Vector3(1.2, 1.2, 1.2), "VendorStall", true)
	_spawn_indoor_prop("res://assets/scene_objects/glTF/Coin_Pile.gltf",
		Vector3(5.0, 0.95, -4.2), Vector3.ZERO, Vector3(1.2, 1.2, 1.2), "CoinPile", false)
	_spawn_indoor_prop("res://assets/scene_objects/glTF/Potion_1.gltf",
		Vector3(5.8, 0.95, -4.2), Vector3.ZERO, Vector3(1.2, 1.2, 1.2), "Potion", false)
	_spawn_indoor_prop("res://assets/scene_objects/glTF/Shelf_Small_Bottles.gltf",
		Vector3(7.5, 1.4, -4.5), Vector3(0.0, deg_to_rad(-90.0), 0.0), Vector3(1.1, 1.1, 1.1), "PotionShelf", true)
	_spawn_indoor_prop("res://assets/scene_objects/glTF/Barrel_Apples.gltf",
		Vector3(7.5, 0.0, -2.5), Vector3.ZERO, Vector3(1.1, 1.1, 1.1), "AppleBarrel", true)
	_spawn_indoor_prop("res://assets/scene_objects/glTF/Crate_Wooden.gltf",
		Vector3(7.5, 0.0, -6.0), Vector3.ZERO, Vector3(1.1, 1.1, 1.1), "VendorCrate", true)

	# Merchant NPC behind stall
	var merchant := ManorMerchantScript.new()
	merchant.name = "EmberMerchant"
	merchant.position = Vector3(5.5, 0.0, -5.2)
	_indoor_root.add_child(merchant)

	# Chandelier in center ceiling
	_spawn_indoor_prop("res://assets/scene_objects/glTF/Chandelier.gltf",
		Vector3(0.0, 3.4, 0.0), Vector3.ZERO, Vector3(1.3, 1.3, 1.3), "Chandelier", false)


func light_energy_set(light: OmniLight3D, energy: float, range_m: float, pos: Vector3) -> void:
	light.light_energy = energy
	light.omni_range = range_m
	light.position = pos


func _add_indoor_box(pos: Vector3, size: Vector3, colour: Color, name_hint: String) -> void:
	var body := StaticBody3D.new()
	body.name = name_hint
	body.position = pos

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.85
	mesh.mesh = box
	mesh.material_override = mat
	body.add_child(mesh)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	_indoor_root.add_child(body)


# --- Teleporter Connections --------------------------------------------------

func _build_teleporters() -> void:
	# Outdoor Entrance Teleporter (near Manor front door)
	_outdoor_teleporter = ManorTeleporterScript.new()
	_outdoor_teleporter.name = "OutdoorTeleporter"
	_outdoor_teleporter.position = OUTDOOR_PORTAL_POS
	_outdoor_teleporter.prompt_text = "进入庄园主宅"
	_outdoor_teleporter.target_position = INDOOR_SPAWN
	_outdoor_teleporter.target_yaw = deg_to_rad(180.0)
	_outdoor_teleporter.portal_color = Color(0.2, 0.85, 1.0)
	_outdoor_teleporter.teleport_requested.connect(_on_teleport_requested)
	add_child(_outdoor_teleporter)

	# Indoor Exit Teleporter (near indoor door)
	_indoor_teleporter = ManorTeleporterScript.new()
	_indoor_teleporter.name = "IndoorTeleporter"
	_indoor_teleporter.position = INDOOR_PORTAL_POS
	_indoor_teleporter.prompt_text = "返回庄园庭院"
	_indoor_teleporter.target_position = OUTDOOR_PORTAL_POS + Vector3(0.0, 0.2, 2.5)
	_indoor_teleporter.target_yaw = deg_to_rad(0.0)
	_indoor_teleporter.portal_color = Color(1.0, 0.75, 0.2)
	_indoor_teleporter.teleport_requested.connect(_on_teleport_requested)
	add_child(_indoor_teleporter)


func _on_teleport_requested(target_pos: Vector3, _target_yaw: float) -> void:
	if _is_teleporting or _player == null:
		return
	_is_teleporting = true

	# Fade out
	var tween := create_tween()
	if _fade_rect != null:
		tween.tween_property(_fade_rect, "modulate:a", 1.0, 0.25)
	await tween.finished

	# Teleport player position & reset velocity
	_player.global_position = target_pos
	_player.velocity = Vector3.ZERO
	if _camera != null and _camera.has_method("snap"):
		_camera.call("snap")

	# Fade in
	var tween_in := create_tween()
	if _fade_rect != null:
		tween_in.tween_property(_fade_rect, "modulate:a", 0.0, 0.3)
	await tween_in.finished
	_is_teleporting = false


# --- Player Setup ------------------------------------------------------------

func _build_player() -> void:
	_camera = FollowCameraScript.new()
	_camera.fov = 55.0
	_camera.near = 0.05
	_camera.far = 400.0
	add_child(_camera)

	_player = PlayerControllerScript.new()
	_player.name = "Player"
	_player.position = OUTDOOR_SPAWN
	_player.intent_source = PlayerIntentSourceScript.new()
	add_child(_player)

	var characters: Array = CharacterPipelineScript.list_characters().filter(
		func(c: Dictionary) -> bool: return ResourceLoader.exists(c.scene))
	if not characters.is_empty():
		var scene := load(characters[0].scene) as PackedScene
		if scene != null:
			_visual = scene.instantiate() as Node3D
			_player.add_child(_visual)

	var height: float = _visual.get("body_height") if _visual != null else 1.75
	if height <= 0.1:
		height = 1.75

	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = minf(0.3, height * 0.2)
	capsule.height = height
	collider.shape = capsule
	collider.position.y = height * 0.5
	_player.add_child(collider)

	if _visual != null:
		_player.setup(_visual, _camera)

	var listener := AudioListener3D.new()
	listener.name = "PlayerAudioListener"
	listener.position = Vector3(0.0, height * 0.9, 0.0)
	_player.add_child(listener)
	listener.make_current()

	_camera.target = _player
	_camera.frame_for(height)
	_camera.snap()


# --- HUD & UI ----------------------------------------------------------------

func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 5
	add_child(_hud_layer)

	# Fullscreen Fade Overlay
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.04, 0.05, 0.07, 1.0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.modulate.a = 0.0
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(_fade_rect)

	# Top Right Currency Bar
	var cur_panel := PanelContainer.new()
	cur_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	cur_panel.offset_left = -320
	cur_panel.offset_top = 16
	cur_panel.offset_right = -16
	cur_panel.offset_bottom = 64

	var c_style := StyleBoxFlat.new()
	c_style.bg_color = Color(0.08, 0.09, 0.12, 0.85)
	c_style.border_width_left = 2
	c_style.border_width_top = 2
	c_style.border_width_right = 2
	c_style.border_width_bottom = 2
	c_style.border_color = Color(0.3, 0.85, 1.0, 0.6)
	c_style.corner_radius_top_left = 8
	c_style.corner_radius_top_right = 8
	c_style.corner_radius_bottom_left = 8
	c_style.corner_radius_bottom_right = 8
	c_style.content_margin_left = 14
	c_style.content_margin_right = 14
	c_style.content_margin_top = 8
	c_style.content_margin_bottom = 8
	cur_panel.add_theme_stylebox_override("panel", c_style)
	_hud_layer.add_child(cur_panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 18)
	cur_panel.add_child(hbox)

	_gold_label = Label.new()
	_gold_label.text = "🪙 金币: 1000"
	_gold_label.add_theme_font_size_override("font_size", 16)
	_gold_label.modulate = Color(1.0, 0.9, 0.4)
	hbox.add_child(_gold_label)

	_voucher_label = Label.new()
	_voucher_label.text = "📜 灰烬凭证: 0"
	_voucher_label.add_theme_font_size_override("font_size", 16)
	_voucher_label.modulate = Color(0.3, 0.9, 1.0)
	hbox.add_child(_voucher_label)

	# Bottom Hint Bar
	var hint_panel := PanelContainer.new()
	hint_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint_panel.offset_left = 20
	hint_panel.offset_right = -20
	hint_panel.offset_bottom = -16
	hint_panel.offset_top = -54

	var h_style := StyleBoxFlat.new()
	h_style.bg_color = Color(0.06, 0.07, 0.09, 0.75)
	h_style.corner_radius_top_left = 6
	h_style.corner_radius_top_right = 6
	h_style.corner_radius_bottom_left = 6
	h_style.corner_radius_bottom_right = 6
	h_style.content_margin_left = 16
	h_style.content_margin_right = 16
	hint_panel.add_theme_stylebox_override("panel", h_style)
	_hud_layer.add_child(hint_panel)

	var hint_lbl := Label.new()
	hint_lbl.text = "WASD 移动 · Shift 奔跑 · 空格 跳跃 · C 蹲伏/翻滚 · E 交互/就座/传送 · TAB 释放光标 · ESC 返回菜单"
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_lbl.add_theme_font_size_override("font_size", 14)
	hint_lbl.modulate = Color(0.85, 0.88, 0.94)
	hint_panel.add_child(hint_lbl)


func _on_currency_changed(new_gold: int, new_vouchers: int) -> void:
	if _gold_label != null:
		_gold_label.text = "🪙 金币: %d" % new_gold
	if _voucher_label != null:
		_voucher_label.text = "📜 灰烬凭证: %d" % new_vouchers


func _update_currency_display() -> void:
	var prof := _get_profile()
	if prof != null:
		_on_currency_changed(prof.gold, prof.ember_vouchers)


# --- Input Handling ----------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file(MENU_SCENE)
			return
		elif event.keycode == KEY_TAB:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()


# --- Asset Spawning Helpers --------------------------------------------------

func _spawn_model(path: String, pos: Vector3, rot: Vector3, scale_vec: Vector3, name_hint: String, add_col: bool) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var scn = load(path) as PackedScene
	if scn == null:
		return null
	var inst := scn.instantiate() as Node3D
	inst.name = name_hint
	inst.position = pos
	inst.rotation = rot
	inst.scale = scale_vec
	_geometry_root.add_child(inst)

	if add_col:
		_setup_node_collision(inst)
	return inst


func _spawn_indoor_prop(path: String, pos: Vector3, rot: Vector3, scale_vec: Vector3, name_hint: String, add_col: bool) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var scn = load(path) as PackedScene
	if scn == null:
		return null
	var inst := scn.instantiate() as Node3D
	inst.name = name_hint
	inst.position = pos
	inst.rotation = rot
	inst.scale = scale_vec
	_indoor_root.add_child(inst)

	if add_col:
		_setup_node_collision(inst)
	return inst


func _setup_node_collision(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		(node as MeshInstance3D).create_trimesh_collision()
	for child in node.get_children():
		_setup_node_collision(child)
