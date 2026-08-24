class_name VfxTextures
extends RefCounted
## Central lookup for the VFX texture library under assets/VFX_assets/.
##
## Runtime-loaded and cached rather than preloaded on purpose: the .import sidecars only exist
## after the editor has scanned the folder, and a texture that is not there yet must degrade the
## skill to its procedural look instead of failing the whole script at parse time.
##
## Invariant: get_tex() returns null exactly when the texture is unavailable; every caller must
## keep working in that case.

const DIR := "res://assets/VFX_assets/"

const MAGIC_CIRCLE := DIR + "magic_circle.png"
const SHOCKWAVE_RING := DIR + "shockwave_ring_texture.png"
const WIND_SLASH := DIR + "wind_slash_texture.png"
const GROUND_CRACK := DIR + "ground_crack_texture.png"
const LIGHTNING := DIR + "lightning_texture.png"
const SMOKE := DIR + "smoke_texture.png"
const FLASH_GLOW := DIR + "flash_glow.png"
## Voronoi cell noise. The file name says shield; the content is cells.
const CELLS := DIR + "shield_texture.png"
## A smoke puff, despite the file name it shipped under.
const SMOKE_PUFF := DIR + "VFX Color Ramp Texture (1).png"

const RAMP_FIRE := DIR + "ramps/ramp_fire.png"
const RAMP_TOXIC := DIR + "ramps/ramp_toxic.png"
const RAMP_ICE := DIR + "ramps/ramp_ice.png"
const RAMP_VOID := DIR + "ramps/ramp_void.png"
const RAMP_ARC := DIR + "ramps/ramp_arc.png"

static var _cache: Dictionary = {}


## Returns the texture, or null when it has not been imported yet. Result is cached either way.
static func get_tex(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_cache[path] = tex
	return tex


## bind(): sets `uniform_name` to the texture and only then raises `mix_uniform`.
## Post: on a missing texture the material is left untouched and the procedural fallback stands.
static func bind(mat: ShaderMaterial, uniform_name: String, path: String,
		mix_uniform: String = "", mix_value: float = 1.0) -> bool:
	if mat == null:
		return false
	var tex := get_tex(path)
	if tex == null:
		return false
	mat.set_shader_parameter(uniform_name, tex)
	if not mix_uniform.is_empty():
		mat.set_shader_parameter(mix_uniform, mix_value)
	return true


## bind_ramp(): convenience for the colour-ramp slot shared by the skill shaders.
static func bind_ramp(mat: ShaderMaterial, path: String, amount: float = 1.0) -> bool:
	return bind(mat, "color_ramp", path, "ramp_mix", amount)
