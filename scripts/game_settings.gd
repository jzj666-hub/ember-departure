class_name GameSettings
extends Node
## Global graphics, performance, and gameplay configuration manager.
## Handles persistence to user://game_settings.json, engine rendering parameter dispatch, and settings change events.

signal setting_changed(key: String, value: Variant)
signal settings_applied

const SAVE_PATH := "user://game_settings.json"

const DEFAULT_SETTINGS := {
	# Performance
	"fps_limit": 60,
	"vsync": true,
	"render_scale": 1.0,
	
	# Atmosphere & Sky
	"dynamic_sky": true,
	"cloud_speed": 1.0,
	"glow_enabled": true,
	"ssao_enabled": false,
	"fog_enabled": false,
	
	# Block & Texture Quality
	"texture_filtering": "linear", # "nearest", "linear", "anisotropic"
	"custom_textures_enabled": true,
	
	# Skills & VFX
	"vfx_quality": "high", # "low", "medium", "high"
	"vfx_particle_ratio": 1.0, # 0.3 for low, 0.7 for medium, 1.0 for high
}

const FPS_OPTIONS: Array[int] = [30, 60, 120, 144, 0] # 0 = Unlimited
const TEXTURE_FILTER_OPTIONS: Array[String] = ["nearest", "linear", "anisotropic"]
const VFX_QUALITY_OPTIONS: Array[String] = ["low", "medium", "high"]

var _settings: Dictionary = {}
static var _instance: GameSettings = null


func _init() -> void:
	if _instance == null:
		_instance = self
	_reset_memory_settings()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_from_disk()
	apply_settings()


static func get_instance() -> GameSettings:
	if _instance == null:
		var script: GDScript = load("res://scripts/game_settings.gd")
		_instance = script.new()
		_instance.load_from_disk()
	return _instance


func _reset_memory_settings() -> void:
	_settings.clear()
	for k in DEFAULT_SETTINGS:
		_settings[k] = DEFAULT_SETTINGS[k]


func get_all_settings() -> Dictionary:
	return _settings.duplicate()


func get_setting(key: String, default_val: Variant = null) -> Variant:
	if _settings.has(key):
		return _settings[key]
	if DEFAULT_SETTINGS.has(key):
		return DEFAULT_SETTINGS[key]
	return default_val


func set_setting(key: String, val: Variant, auto_save: bool = true) -> void:
	_settings[key] = val
	
	# Keep particle ratio in sync if vfx_quality changes
	if key == "vfx_quality":
		match str(val):
			"low":
				_settings["vfx_particle_ratio"] = 0.3
			"medium":
				_settings["vfx_particle_ratio"] = 0.7
			"high":
				_settings["vfx_particle_ratio"] = 1.0
	
	setting_changed.emit(key, val)
	if auto_save:
		save_to_disk()
		apply_settings()


func reset_to_defaults() -> void:
	_reset_memory_settings()
	save_to_disk()
	apply_settings()
	for k in _settings:
		setting_changed.emit(k, _settings[k])


func save_to_disk() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_settings, "  "))
		f.close()


func load_from_disk() -> void:
	_reset_memory_settings()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		for k in parsed:
			_settings[str(k)] = parsed[k]


## Dispatches settings to engine and viewport.
func apply_settings(viewport: Viewport = null) -> void:
	# FPS limit
	var fps: int = int(get_setting("fps_limit", 60))
	Engine.max_fps = fps
	
	# VSync
	var vsync: bool = bool(get_setting("vsync", true))
	var vsync_mode := DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(vsync_mode)
	
	# 3D Render Resolution Scaling
	var scale_val: float = float(get_setting("render_scale", 1.0))
	var vp: Viewport = viewport
	if vp == null and Engine.get_main_loop() is SceneTree:
		var tree := Engine.get_main_loop() as SceneTree
		if tree.root != null:
			vp = tree.root.get_viewport()
	
	if vp != null and vp is Window:
		vp.scaling_3d_scale = clampf(scale_val, 0.25, 2.0)
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	
	settings_applied.emit()
