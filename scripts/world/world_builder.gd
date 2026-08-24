class_name WorldBuilder
extends RefCounted
## Shared scene scaffolding: environment (sky/light/post) and ground (plane/grid/ring).
## Replaces the per-scene copies of _build_environment() and _build_ground().
## All methods are static and stateless: they only add children to the root passed in.

const EnvPresetScript = preload("res://scripts/world/env_preset.gd")
const GroundPresetScript = preload("res://scripts/world/ground_preset.gd")

## Ground collision slab. Uniform across every scene that had a hand-rolled _build_ground().
const GROUND_COLLISION_THICKNESS := 0.4
const GROUND_COLLISION_Y := -0.2

## CONTRACT: skills match the ground body by this exact name to exclude it from targeting.
## See skill_slam / skill_grapple / skill_mist / skill_sand / skill_entangle / skill_cleanse.
const GROUND_BODY_NAME := "Ground"


## build_environment(root, preset): adds WorldEnvironment + sun (+ optional fill) under root.
## Pre: root is in a 3D scene. preset==null falls back to EnvPreset defaults.
## Post: returns the WorldEnvironment node. Tonemap is always FILMIC, background always sky.
static func build_environment(root: Node, preset: EnvPreset = null) -> WorldEnvironment:
	if root == null:
		return null
	var p: EnvPreset = preset if preset != null else EnvPresetScript.new()

	var sky := Sky.new()
	sky.sky_material = _make_sky_material(p)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = p.ambient_energy
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if p.reflect_sky:
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ssao_enabled = p.ssao
	env.glow_enabled = p.glow
	if p.glow:
		if p.glow_additive:
			env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		env.glow_intensity = p.glow_intensity
		env.glow_bloom = p.glow_bloom
		env.glow_hdr_threshold = p.glow_hdr_threshold
	env.fog_enabled = p.fog
	if p.fog:
		env.fog_light_color = p.fog_color
		env.fog_density = p.fog_density

	var env_node := WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
	env_node.environment = env
	root.add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.light_color = p.sun_color
	sun.light_energy = p.sun_energy
	sun.rotation_degrees = Vector3(p.sun_pitch_deg, p.sun_yaw_deg, 0.0)
	sun.shadow_enabled = p.sun_shadows
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = p.shadow_blend_splits
	sun.directional_shadow_max_distance = p.shadow_max_distance
	sun.directional_shadow_fade_start = p.shadow_fade_start
	sun.shadow_bias = p.shadow_bias
	sun.shadow_normal_bias = p.shadow_normal_bias
	root.add_child(sun)

	if p.fill_enabled:
		var fill := DirectionalLight3D.new()
		fill.name = "FillLight"
		fill.light_color = p.fill_color
		fill.light_energy = p.fill_energy
		fill.rotation_degrees = Vector3(p.fill_pitch_deg, p.fill_yaw_deg, 0.0)
		fill.shadow_enabled = false
		root.add_child(fill)

	return env_node


## _make_sky_material(p): panorama when panorama_path resolves, else procedural gradient.
static func _make_sky_material(p: EnvPreset) -> Material:
	if p.panorama_path != "" and ResourceLoader.exists(p.panorama_path):
		var pano := PanoramaSkyMaterial.new()
		pano.panorama = load(p.panorama_path) as Texture2D
		return pano
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = p.sky_top_color
	mat.sky_horizon_color = p.sky_horizon_color
	mat.ground_bottom_color = p.ground_bottom_color
	mat.ground_horizon_color = p.ground_horizon_color
	return mat


## build_ground(root, preset, half_extent): StaticBody3D named "Ground" spanning
## [-half_extent, +half_extent] on X and Z, plus optional grid / ring overlays.
## Pre: half_extent > 0. preset==null falls back to GroundPreset defaults.
## Post: returns the body. Grid and ring are siblings of the body, not children.
static func build_ground(root: Node, preset: GroundPreset, half_extent: float) -> StaticBody3D:
	if root == null or half_extent <= 0.0:
		return null
	var p: GroundPreset = preset if preset != null else GroundPresetScript.new()
	var span := half_extent * 2.0

	var body := StaticBody3D.new()
	body.name = GROUND_BODY_NAME

	if p.plane_enabled:
		var plane := PlaneMesh.new()
		plane.size = Vector2(span, span)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = p.plane_color
		mat.roughness = p.plane_roughness
		plane.material = mat
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.name = "GroundPlane"
		mesh_inst.mesh = plane
		body.add_child(mesh_inst)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(span, GROUND_COLLISION_THICKNESS, span)
	shape.shape = box
	shape.position = Vector3(0.0, GROUND_COLLISION_Y, 0.0)
	body.add_child(shape)
	root.add_child(body)

	if p.grid_enabled:
		root.add_child(_make_grid(p, int(half_extent)))
	if p.ring_enabled:
		root.add_child(_make_ring(p))
	return body


## _make_grid(p, half): unshaded vertex-coloured line grid at 1m spacing.
static func _make_grid(p: GroundPreset, half: int) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(-half, half + 1):
		var colour := p.grid_major_color if i % p.grid_major_every == 0 else p.grid_minor_color
		mesh.surface_set_color(colour)
		mesh.surface_add_vertex(Vector3(i, 0.0, -half))
		mesh.surface_add_vertex(Vector3(i, 0.0, half))
		mesh.surface_set_color(colour)
		mesh.surface_add_vertex(Vector3(-half, 0.0, i))
		mesh.surface_add_vertex(Vector3(half, 0.0, i))
	mesh.surface_end()
	var node := MeshInstance3D.new()
	node.name = "Grid"
	node.mesh = mesh
	node.material_override = _overlay_material()
	node.position.y = p.grid_y
	return node


## _make_ring(p): flat line-strip circle marking an arena boundary.
static func _make_ring(p: GroundPreset) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in range(p.ring_segments + 1):
		var ang := TAU * float(i) / float(p.ring_segments)
		mesh.surface_set_color(p.ring_color)
		mesh.surface_add_vertex(Vector3(cos(ang) * p.ring_radius, p.ring_y, sin(ang) * p.ring_radius))
	mesh.surface_end()
	var node := MeshInstance3D.new()
	node.name = "ArenaRing"
	node.mesh = mesh
	node.material_override = _overlay_material()
	return node


## _overlay_material(): unshaded + vertex-colour + alpha, shared by grid and ring.
static func _overlay_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat
