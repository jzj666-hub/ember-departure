class_name HudKit
extends RefCounted
## Pure UI construction helpers shared across HUDs. No scene state, all static.

## nine_patch(path, ...): StyleBoxTexture stretched on both axes.
## Pre: texture_path may be missing — the box is then untextured rather than an error.
## ml/mt/mr/mb = texture margins (where the 9-patch cuts). cl/ct/cr/cb = content padding.
static func nine_patch(texture_path: String, ml: float, mt: float, mr: float, mb: float,
		cl: float = 16.0, ct: float = 14.0, cr: float = 16.0, cb: float = 14.0) -> StyleBoxTexture:
	var sbox := StyleBoxTexture.new()
	if ResourceLoader.exists(texture_path):
		sbox.texture = load(texture_path)
	sbox.texture_margin_left = ml
	sbox.texture_margin_top = mt
	sbox.texture_margin_right = mr
	sbox.texture_margin_bottom = mb
	sbox.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sbox.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sbox.content_margin_left = cl
	sbox.content_margin_top = ct
	sbox.content_margin_right = cr
	sbox.content_margin_bottom = cb
	return sbox
