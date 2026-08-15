class_name Character
extends Node3D
## Root Node3D for character, wrapping instanced model scene.
## Handles runtime AnimationLibrary attachment and bone sockets.

const AnimPipelineScript = preload("res://tools/anim_pipeline.gd")

## Clips every character shares, addressed as "anims/<clip>".
const SHARED_LIB := "anims"
## Clips only this character has, addressed as "own/<clip>".
const OWN_LIB := "own"

@export var character_id := ""

## Standing body height in meters. Set by pipeline.
@export var body_height := 0.0

@export var shared_animations: AnimationLibrary
@export var own_animations: AnimationLibrary

## Cached nodes, resolved by search instead of path.
var player: AnimationPlayer
var skeleton: Skeleton3D

const SOCKETS := {
	"right_hand": "RightHand",
	"left_hand": "LeftHand",
	"head": "Head",
}

var _attachment_nodes := {}


func _ready() -> void:
	player = AnimPipelineScript.first_of_class(self, "AnimationPlayer") as AnimationPlayer
	skeleton = AnimPipelineScript.first_of_class(self, "Skeleton3D") as Skeleton3D
	if player == null or skeleton == null:
		push_error("%s: imported model has no AnimationPlayer or Skeleton3D" % name)
		return
	attach_libraries()
	_setup_sockets()


func _setup_sockets() -> void:
	if skeleton == null:
		return
	for socket_name in SOCKETS:
		var bone_name: String = SOCKETS[socket_name]
		var node_name: String = "Socket_" + socket_name
		var attachment: BoneAttachment3D = skeleton.find_child(node_name, false, false) as BoneAttachment3D
		if attachment == null:
			attachment = BoneAttachment3D.new()
			attachment.name = node_name
			attachment.bone_name = bone_name
			skeleton.add_child(attachment)
		_attachment_nodes[socket_name] = attachment


func get_socket_node(socket_name: String) -> BoneAttachment3D:
	return _attachment_nodes.get(socket_name, null)


## Return head bone world position if available.
func get_head_position() -> Vector3:
	var socket := get_socket_node("head")
	if socket != null:
		return socket.global_position
	if skeleton != null:
		var idx := skeleton.find_bone("Head")
		if idx >= 0:
			return skeleton.global_transform * skeleton.get_bone_global_pose(idx).origin
	return global_position + Vector3.UP * (body_height * 0.88 if body_height > 0.1 else 1.5)


## Return world position at front of head/eyes derived from head and eye bone transforms.
func get_head_front_position() -> Vector3:
	if skeleton != null:
		var leye_idx := skeleton.find_bone("LeftEye")
		var reye_idx := skeleton.find_bone("RightEye")
		var head_idx := skeleton.find_bone("Head")
		if head_idx >= 0:
			var head_pose := skeleton.get_bone_global_pose(head_idx)
			var head_forward := head_pose.basis.z.normalized()
			if leye_idx >= 0 and reye_idx >= 0:
				var leye_pose := skeleton.get_bone_global_pose(leye_idx)
				var reye_pose := skeleton.get_bone_global_pose(reye_idx)
				var eye_mid := (leye_pose.origin + reye_pose.origin) * 0.5
				return skeleton.global_transform * (eye_mid + head_forward * 0.08)
			else:
				var head_up := head_pose.basis.y.normalized()
				return skeleton.global_transform * (head_pose.origin + head_up * 0.08 + head_forward * 0.12)
	var socket := get_socket_node("head")
	if socket != null:
		return socket.global_transform.origin + socket.global_transform.basis.z * 0.12
	return global_position + Vector3.UP * (body_height * 0.88 if body_height > 0.1 else 1.55)


## Attach/re-attach animation libraries.
func attach_libraries() -> void:
	if player == null:
		return
	_swap(SHARED_LIB, shared_animations)
	_swap(OWN_LIB, own_animations)


func _swap(lib_name: String, lib: AnimationLibrary) -> void:
	if player.has_animation_library(lib_name):
		player.remove_animation_library(lib_name)
	if lib != null:
		player.add_animation_library(lib_name, lib)


## Sorted list of qualified clip names.
func clip_names() -> PackedStringArray:
	var out := PackedStringArray()
	if player == null:
		return out
	for lib_name in player.get_animation_library_list():
		var lib := player.get_animation_library(lib_name)
		for clip in lib.get_animation_list():
			out.append(String(clip) if String(lib_name).is_empty()
				else "%s/%s" % [lib_name, clip])
	out.sort()
	return out


## Plays clip. Resets bones first to prevent stale rotations from immutable track
## removal - skipped when blending, since the cross-fade reads the outgoing clip
## and a reset mid-fade pops whatever bones the incoming one does not track.
## Returns false if clip not found.
func play(clip: String, blend: float = 0.0) -> bool:
	var full := resolve(clip)
	if full == "":
		return false
	if skeleton != null and blend <= 0.0:
		skeleton.reset_bone_poses()
	player.play(full, blend)
	return true


## Resolves bare or qualified clip name to qualified AnimationPlayer candidate.
func resolve(clip: String) -> String:
	if player == null:
		return ""
	for candidate in [clip, "%s/%s" % [SHARED_LIB, clip], "%s/%s" % [OWN_LIB, clip]]:
		if player.has_animation(candidate):
			return candidate
	return ""


func has_clip(clip: String) -> bool:
	return resolve(clip) != ""
