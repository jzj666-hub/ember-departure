class_name ItemData
extends Resource
## Configuration resource for a handheld item.

@export var item_id: String = ""
@export var display_name: String = ""
@export var mesh_scene: PackedScene ## The 3D model/scene of the item (FBX/GLB).

## Grip offset and rotation transform relative to hand bone.
@export var grip_transform := Transform3D.IDENTITY
## Model uniform scale.
@export var item_scale := 1.0
## Grip orientation flip flag.
@export var flip_grip := false
## Flag to bypass automatic pivot anchoring.
@export var auto_anchor := true
@export var default_socket := "right_hand"

## Upper body stance animation clip for holding item. Also drives the gait blend
## space's idle pole, so it reaches the legs while standing still.
@export var stance_clip := ""
## Stance blend amount at rest (0.0 to 1.0). Faded out by gait.
@export var stance_blend := 1.0
## Stance animation bone filter subtree root.
@export var stance_filter_bone := "Spine"
## Armed locomotion clips. Empty = keep the bare-handed pole.
@export var stance_walk_clip := ""
@export var stance_run_clip := ""

## Raw weapon behavior graph dictionary.
@export var graph := {}

## Blade afterimage settings. Empty = the weapon draws none.
@export var trail := {}
