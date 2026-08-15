class_name TrailPalette
extends RefCounted
## Derives a whole trail colour set from one hue family. Stateless, all static.
## Convention: age 0 = just spawned, 1 = about to vanish; side 0 = core rail,
## -1/+1 = the two outer rails.
##
## `energy` above 1 puts the result out of the 0..1 range on purpose - that is
## what Environment glow picks up. Callers that write into an 8-bit sink (vertex
## colours, particle ramps) must pass energy 1.0 here and apply the real gain in
## the material, or it clamps away. See WeaponTrail._refresh_material().

## Colour families: id -> [hue deg, spread deg].
const PRESETS := {
	"ember": [24.0, 38.0],
	"frost": [196.0, 42.0],
	"void": [276.0, 52.0],
	"blood": [352.0, 30.0],
	"gold": [46.0, 26.0],
	"toxic": [92.0, 46.0],
}

## Core rail saturation: near-white when fresh, taking on the family as it ages.
const CORE_SAT_MIN := 0.10
const CORE_SAT_GAIN := 0.25
## Outer rails: saturated and dimmer, so a cross-section reads bright-ridge /
## coloured-flanks rather than flat.
const EDGE_SAT := 0.90
const EDGE_VALUE := 0.75
## Fraction of `energy` an outer rail gets. Only the ridge is meant to clip into
## bloom.
const EDGE_ENERGY := 0.55
## Core rail alpha relative to an outer rail.
const CORE_ALPHA_GAIN := 1.3
## Saturation of the non-HDR family colour handed to light nodes and swatches.
const LIGHT_SAT := 0.55
## Fraction of its width a sample has lost by the time it vanishes.
const TAIL_WIDTH := 0.45
## Stops in the ramp gradient() builds.
const STOPS := 6


## Core rail colour. Post: rgb exceeds 1 when energy > 1 (HDR, needs glow).
static func core(hue: float, spread: float, energy: float, age: float, exponent: float = 2.0) -> Color:
	return _rail(hue, spread, energy, age, 0.0, exponent)


## Outer rail colour. Pre: side is -1 or +1.
static func edge(hue: float, spread: float, energy: float, age: float,
		side: float, exponent: float = 2.0) -> Color:
	return _rail(hue, spread, energy, age, signf(side), exponent)


## One rail. Post: hue stays within [hue-spread, hue+spread]; alpha is
## fade(age, exponent), lifted by CORE_ALPHA_GAIN on the core rail, clamped to 1.
static func _rail(hue: float, spread: float, energy: float, age: float,
		side: float, exponent: float = 2.0) -> Color:
	var t := clampf(age, 0.0, 1.0)
	var is_core := is_zero_approx(side)
	# Quadratic in age: the head holds the family's own hue and only the tail
	# splits, so the two flanks separate as the sample cools.
	var shifted := wrapf(hue + side * maxf(spread, 0.0) * t * t, 0.0, 360.0)
	var sat := (CORE_SAT_MIN + CORE_SAT_GAIN * t) if is_core else EDGE_SAT
	var value := 1.0 if is_core else EDGE_VALUE
	var gain := maxf(energy, 0.0) * (1.0 if is_core else EDGE_ENERGY)
	var rgb := Color.from_hsv(shifted / 360.0, sat, value)
	var alpha := fade(t, exponent) * (CORE_ALPHA_GAIN if is_core else 1.0)
	return Color(rgb.r * gain, rgb.g * gain, rgb.b * gain, minf(alpha, 1.0))


## Alpha over a sample's life. Post: fade(0)==1, fade(1)==0, monotone down.
static func fade(age: float, exponent: float = 2.0) -> float:
	var left := 1.0 - clampf(age, 0.0, 1.0)
	return pow(left, maxf(exponent, 0.1))


## Width multiplier over a sample's life.
## Post: shrink(0)==1, shrink(1)==1-TAIL_WIDTH, monotone down.
static func shrink(age: float) -> float:
	var t := clampf(age, 0.0, 1.0)
	return 1.0 - TAIL_WIDTH * t * t


## Head-to-tail ramp for particle color_ramp and the panel preview.
## Pass energy 1.0 for a ramp meant to be looked at rather than bloomed.
## Post: STOPS points, offsets ascending 0..1.
static func gradient(hue: float, spread: float, energy: float) -> Gradient:
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for i in STOPS:
		var age := float(i) / float(STOPS - 1)
		# Ridge and one flank averaged: what the strip looks like from far enough
		# away that the rails stop being separable.
		offsets.append(age)
		colors.append(core(hue, spread, energy, age).lerp(
			edge(hue, spread, energy, age, 1.0), 0.5))
	var ramp := Gradient.new()
	ramp.offsets = offsets
	ramp.colors = colors
	return ramp


## Family colour with no HDR gain. For light nodes and UI swatches.
static func plain(hue: float) -> Color:
	return Color.from_hsv(wrapf(hue, 0.0, 360.0) / 360.0, LIGHT_SAT, 1.0)


## A preset's [hue, spread], or [] if the id is not one.
static func preset(family: String) -> Array:
	var found = PRESETS.get(family)
	return [float(found[0]), float(found[1])] if found != null else []
