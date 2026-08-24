class_name EnvPreset
extends Resource
## Sky + post-processing + directional light settings for one scene's look.
## Consumed by WorldBuilder.build_environment(). Authored as .tres under config/env/.
## Defaults == the project's "editor blue" look and Godot engine defaults, so a .tres
## only needs to list what it actually changes.

## Non-empty and existing -> PanoramaSkyMaterial from this texture; otherwise procedural sky.
@export_file("*.jpg", "*.png", "*.hdr", "*.exr") var panorama_path: String = ""

@export_group("Procedural sky")
@export var sky_top_color := Color(0.24, 0.32, 0.47)
@export var sky_horizon_color := Color(0.58, 0.60, 0.63)
@export var ground_bottom_color := Color(0.12, 0.12, 0.14)
@export var ground_horizon_color := Color(0.58, 0.60, 0.63)

@export_group("Ambient")
@export_range(0.0, 4.0, 0.01) var ambient_energy := 0.45
## Sky also drives specular reflections. Chase scenes enable this.
@export var reflect_sky := false

@export_group("Post processing")
@export var ssao := false
@export var glow := false
## Additive glow blend instead of Godot's softlight default.
@export var glow_additive := false
@export_range(0.0, 8.0, 0.01) var glow_intensity := 0.8
@export_range(0.0, 1.0, 0.01) var glow_bloom := 0.0
@export_range(0.0, 4.0, 0.01) var glow_hdr_threshold := 1.0
@export var fog := false
@export var fog_color := Color(0.55, 0.59, 0.66)
@export_range(0.0, 0.1, 0.0001) var fog_density := 0.006

@export_group("Sun (key light)")
@export var sun_color := Color(1.0, 1.0, 1.0)
@export_range(0.0, 8.0, 0.01) var sun_energy := 1.2
@export_range(-90.0, 90.0, 0.5) var sun_pitch_deg := -45.0
## Sign matters: editor/test scenes use -35, chase scenes use +35. Not interchangeable.
@export_range(-180.0, 180.0, 0.5) var sun_yaw_deg := -35.0
@export var sun_shadows := true

@export_group("Sun shadow tuning")
@export var shadow_blend_splits := false
@export var shadow_max_distance := 100.0
@export_range(0.0, 1.0, 0.01) var shadow_fade_start := 0.8
@export var shadow_bias := 0.1
@export var shadow_normal_bias := 2.0

@export_group("Fill light")
@export var fill_enabled := false
@export var fill_color := Color(1.0, 1.0, 1.0)
@export_range(0.0, 4.0, 0.01) var fill_energy := 0.4
@export_range(-90.0, 90.0, 0.5) var fill_pitch_deg := -20.0
@export_range(-180.0, 180.0, 0.5) var fill_yaw_deg := 145.0
