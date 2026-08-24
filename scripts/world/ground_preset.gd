class_name GroundPreset
extends Resource
## Ground plane + line grid + decorative ring appearance for one scene.
## Consumed by WorldBuilder.build_ground(). Authored as .tres under config/ground/.
## Extent is NOT stored here: it comes from the scene's own GROUND_HALF (nav bounds depend on it).
## Defaults == the "editor slate" look (map_editor / npc_test).

@export_group("Solid plane")
## false -> collision only, no visible surface (chase scenes draw only the grid).
@export var plane_enabled := true
@export var plane_color := Color(0.18, 0.20, 0.23)
@export_range(0.0, 1.0, 0.01) var plane_roughness := 0.9

@export_group("Line grid")
@export var grid_enabled := true
## Every Nth line uses grid_major_color instead of grid_minor_color.
@export_range(1, 20, 1) var grid_major_every := 5
@export var grid_major_color := Color(0.45, 0.50, 0.60, 0.6)
@export var grid_minor_color := Color(0.28, 0.30, 0.35, 0.3)
## Lift above the plane; 0 would z-fight.
@export var grid_y := 0.003

@export_group("Decorative ring")
@export var ring_enabled := false
@export var ring_radius := 12.0
@export_range(8, 256, 1) var ring_segments := 64
@export var ring_color := Color(0.9, 0.55, 0.2, 0.6)
@export var ring_y := 0.005
