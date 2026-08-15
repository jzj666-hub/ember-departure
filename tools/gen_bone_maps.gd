extends SceneTree
## Generates BoneMap resources that map each known source rig onto
## SkeletonProfileHumanoid.
##
##   CC_Base_*   -> humanoid profile   (ActorCore / AccuRig characters)
##   mixamorig_* -> humanoid profile   (Mixamo clips)
##   DEF-*       -> humanoid profile   (Blender Rigify deform bones)
##   pelvis/*_l  -> humanoid profile   (Unreal mannequin, e.g. UAL2_Standard.fbx)
##
## Once two skeletons are renamed to profile bone names, clips move freely
## between them. Add a rig by writing one more dictionary here and re-running.
##
##   godot --headless --path <project> --script res://tools/gen_bone_maps.gd

const OUT_DIR := "res://assets/retarget"

## profile bone name -> CC_Base bone name
const CC_MAP := {
	"Root": "root",
	"Hips": "CC_Base_Hip",
	"Spine": "CC_Base_Waist",
	"Chest": "CC_Base_Spine01",
	"UpperChest": "CC_Base_Spine02",
	"Neck": "CC_Base_NeckTwist01",
	"Head": "CC_Base_Head",
	"LeftEye": "CC_Base_L_Eye",
	"RightEye": "CC_Base_R_Eye",
	"Jaw": "CC_Base_JawRoot",

	"LeftShoulder": "CC_Base_L_Clavicle",
	"LeftUpperArm": "CC_Base_L_Upperarm",
	"LeftLowerArm": "CC_Base_L_Forearm",
	"LeftHand": "CC_Base_L_Hand",
	"LeftThumbMetacarpal": "CC_Base_L_Thumb1",
	"LeftThumbProximal": "CC_Base_L_Thumb2",
	"LeftThumbDistal": "CC_Base_L_Thumb3",
	"LeftIndexProximal": "CC_Base_L_Index1",
	"LeftIndexIntermediate": "CC_Base_L_Index2",
	"LeftIndexDistal": "CC_Base_L_Index3",
	"LeftMiddleProximal": "CC_Base_L_Mid1",
	"LeftMiddleIntermediate": "CC_Base_L_Mid2",
	"LeftMiddleDistal": "CC_Base_L_Mid3",
	"LeftRingProximal": "CC_Base_L_Ring1",
	"LeftRingIntermediate": "CC_Base_L_Ring2",
	"LeftRingDistal": "CC_Base_L_Ring3",
	"LeftLittleProximal": "CC_Base_L_Pinky1",
	"LeftLittleIntermediate": "CC_Base_L_Pinky2",
	"LeftLittleDistal": "CC_Base_L_Pinky3",

	"RightShoulder": "CC_Base_R_Clavicle",
	"RightUpperArm": "CC_Base_R_Upperarm",
	"RightLowerArm": "CC_Base_R_Forearm",
	"RightHand": "CC_Base_R_Hand",
	"RightThumbMetacarpal": "CC_Base_R_Thumb1",
	"RightThumbProximal": "CC_Base_R_Thumb2",
	"RightThumbDistal": "CC_Base_R_Thumb3",
	"RightIndexProximal": "CC_Base_R_Index1",
	"RightIndexIntermediate": "CC_Base_R_Index2",
	"RightIndexDistal": "CC_Base_R_Index3",
	"RightMiddleProximal": "CC_Base_R_Mid1",
	"RightMiddleIntermediate": "CC_Base_R_Mid2",
	"RightMiddleDistal": "CC_Base_R_Mid3",
	"RightRingProximal": "CC_Base_R_Ring1",
	"RightRingIntermediate": "CC_Base_R_Ring2",
	"RightRingDistal": "CC_Base_R_Ring3",
	"RightLittleProximal": "CC_Base_R_Pinky1",
	"RightLittleIntermediate": "CC_Base_R_Pinky2",
	"RightLittleDistal": "CC_Base_R_Pinky3",

	"LeftUpperLeg": "CC_Base_L_Thigh",
	"LeftLowerLeg": "CC_Base_L_Calf",
	"LeftFoot": "CC_Base_L_Foot",
	"LeftToes": "CC_Base_L_ToeBase",
	"RightUpperLeg": "CC_Base_R_Thigh",
	"RightLowerLeg": "CC_Base_R_Calf",
	"RightFoot": "CC_Base_R_Foot",
	"RightToes": "CC_Base_R_ToeBase",
}

## profile bone name -> mixamorig bone name.
## Mixamo has no dedicated root bone, so "Root" stays unmapped.
const MIXAMO_MAP := {
	"Hips": "mixamorig_Hips",
	"Spine": "mixamorig_Spine",
	"Chest": "mixamorig_Spine1",
	"UpperChest": "mixamorig_Spine2",
	"Neck": "mixamorig_Neck",
	"Head": "mixamorig_Head",
	"LeftEye": "mixamorig_LeftEye",
	"RightEye": "mixamorig_RightEye",
	"Jaw": "mixamorig_Jaw",

	"LeftShoulder": "mixamorig_LeftShoulder",
	"LeftUpperArm": "mixamorig_LeftArm",
	"LeftLowerArm": "mixamorig_LeftForeArm",
	"LeftHand": "mixamorig_LeftHand",
	"LeftThumbMetacarpal": "mixamorig_LeftHandThumb1",
	"LeftThumbProximal": "mixamorig_LeftHandThumb2",
	"LeftThumbDistal": "mixamorig_LeftHandThumb3",
	"LeftIndexProximal": "mixamorig_LeftHandIndex1",
	"LeftIndexIntermediate": "mixamorig_LeftHandIndex2",
	"LeftIndexDistal": "mixamorig_LeftHandIndex3",
	"LeftMiddleProximal": "mixamorig_LeftHandMiddle1",
	"LeftMiddleIntermediate": "mixamorig_LeftHandMiddle2",
	"LeftMiddleDistal": "mixamorig_LeftHandMiddle3",
	"LeftRingProximal": "mixamorig_LeftHandRing1",
	"LeftRingIntermediate": "mixamorig_LeftHandRing2",
	"LeftRingDistal": "mixamorig_LeftHandRing3",
	"LeftLittleProximal": "mixamorig_LeftHandPinky1",
	"LeftLittleIntermediate": "mixamorig_LeftHandPinky2",
	"LeftLittleDistal": "mixamorig_LeftHandPinky3",

	"RightShoulder": "mixamorig_RightShoulder",
	"RightUpperArm": "mixamorig_RightArm",
	"RightLowerArm": "mixamorig_RightForeArm",
	"RightHand": "mixamorig_RightHand",
	"RightThumbMetacarpal": "mixamorig_RightHandThumb1",
	"RightThumbProximal": "mixamorig_RightHandThumb2",
	"RightThumbDistal": "mixamorig_RightHandThumb3",
	"RightIndexProximal": "mixamorig_RightHandIndex1",
	"RightIndexIntermediate": "mixamorig_RightHandIndex2",
	"RightIndexDistal": "mixamorig_RightHandIndex3",
	"RightMiddleProximal": "mixamorig_RightHandMiddle1",
	"RightMiddleIntermediate": "mixamorig_RightHandMiddle2",
	"RightMiddleDistal": "mixamorig_RightHandMiddle3",
	"RightRingProximal": "mixamorig_RightHandRing1",
	"RightRingIntermediate": "mixamorig_RightHandRing2",
	"RightRingDistal": "mixamorig_RightHandRing3",
	"RightLittleProximal": "mixamorig_RightHandPinky1",
	"RightLittleIntermediate": "mixamorig_RightHandPinky2",
	"RightLittleDistal": "mixamorig_RightHandPinky3",

	"LeftUpperLeg": "mixamorig_LeftUpLeg",
	"LeftLowerLeg": "mixamorig_LeftLeg",
	"LeftFoot": "mixamorig_LeftFoot",
	"LeftToes": "mixamorig_LeftToeBase",
	"RightUpperLeg": "mixamorig_RightUpLeg",
	"RightLowerLeg": "mixamorig_RightLeg",
	"RightFoot": "mixamorig_RightFoot",
	"RightToes": "mixamorig_RightToeBase",
}


## profile bone name -> Blender Rigify deform bone.
## Rigify splits the spine into numbered segments and has no eye/jaw deform
## bones, so those stay unmapped.
const RIGIFY_MAP := {
	"Root": "root",
	"Hips": "DEF-hips",
	"Spine": "DEF-spine.001",
	"Chest": "DEF-spine.002",
	"UpperChest": "DEF-spine.003",
	"Neck": "DEF-neck",
	"Head": "DEF-head",

	"LeftShoulder": "DEF-shoulder.L",
	"LeftUpperArm": "DEF-upper_arm.L",
	"LeftLowerArm": "DEF-forearm.L",
	"LeftHand": "DEF-hand.L",
	"LeftThumbMetacarpal": "DEF-thumb.01.L",
	"LeftThumbProximal": "DEF-thumb.02.L",
	"LeftThumbDistal": "DEF-thumb.03.L",
	"LeftIndexProximal": "DEF-f_index.01.L",
	"LeftIndexIntermediate": "DEF-f_index.02.L",
	"LeftIndexDistal": "DEF-f_index.03.L",
	"LeftMiddleProximal": "DEF-f_middle.01.L",
	"LeftMiddleIntermediate": "DEF-f_middle.02.L",
	"LeftMiddleDistal": "DEF-f_middle.03.L",
	"LeftRingProximal": "DEF-f_ring.01.L",
	"LeftRingIntermediate": "DEF-f_ring.02.L",
	"LeftRingDistal": "DEF-f_ring.03.L",
	"LeftLittleProximal": "DEF-f_pinky.01.L",
	"LeftLittleIntermediate": "DEF-f_pinky.02.L",
	"LeftLittleDistal": "DEF-f_pinky.03.L",

	"RightShoulder": "DEF-shoulder.R",
	"RightUpperArm": "DEF-upper_arm.R",
	"RightLowerArm": "DEF-forearm.R",
	"RightHand": "DEF-hand.R",
	"RightThumbMetacarpal": "DEF-thumb.01.R",
	"RightThumbProximal": "DEF-thumb.02.R",
	"RightThumbDistal": "DEF-thumb.03.R",
	"RightIndexProximal": "DEF-f_index.01.R",
	"RightIndexIntermediate": "DEF-f_index.02.R",
	"RightIndexDistal": "DEF-f_index.03.R",
	"RightMiddleProximal": "DEF-f_middle.01.R",
	"RightMiddleIntermediate": "DEF-f_middle.02.R",
	"RightMiddleDistal": "DEF-f_middle.03.R",
	"RightRingProximal": "DEF-f_ring.01.R",
	"RightRingIntermediate": "DEF-f_ring.02.R",
	"RightRingDistal": "DEF-f_ring.03.R",
	"RightLittleProximal": "DEF-f_pinky.01.R",
	"RightLittleIntermediate": "DEF-f_pinky.02.R",
	"RightLittleDistal": "DEF-f_pinky.03.R",

	"LeftUpperLeg": "DEF-thigh.L",
	"LeftLowerLeg": "DEF-shin.L",
	"LeftFoot": "DEF-foot.L",
	"LeftToes": "DEF-toe.L",
	"RightUpperLeg": "DEF-thigh.R",
	"RightLowerLeg": "DEF-shin.R",
	"RightFoot": "DEF-foot.R",
	"RightToes": "DEF-toe.R",
}


## profile bone name -> Unreal mannequin bone name (UAL2_Standard.fbx).
## Bones carry no shared namespace, so detection matches on names alone -
## "pelvis" is the hip bone that gates scoring in AnimPipeline.detect_bone_map().
## No eye/jaw bones. Blender's FBX exporter adds *_04_leaf_* finger and ball tips
## that the profile has no slot for; those stay unmapped.
## "Head" is capitalised in this file, unlike every other bone.
const UE_MANNEQUIN_MAP := {
	"Root": "root",
	"Hips": "pelvis",
	"Spine": "spine_01",
	"Chest": "spine_02",
	"UpperChest": "spine_03",
	"Neck": "neck_01",
	"Head": "Head",

	"LeftShoulder": "clavicle_l",
	"LeftUpperArm": "upperarm_l",
	"LeftLowerArm": "lowerarm_l",
	"LeftHand": "hand_l",
	"LeftThumbMetacarpal": "thumb_01_l",
	"LeftThumbProximal": "thumb_02_l",
	"LeftThumbDistal": "thumb_03_l",
	"LeftIndexProximal": "index_01_l",
	"LeftIndexIntermediate": "index_02_l",
	"LeftIndexDistal": "index_03_l",
	"LeftMiddleProximal": "middle_01_l",
	"LeftMiddleIntermediate": "middle_02_l",
	"LeftMiddleDistal": "middle_03_l",
	"LeftRingProximal": "ring_01_l",
	"LeftRingIntermediate": "ring_02_l",
	"LeftRingDistal": "ring_03_l",
	"LeftLittleProximal": "pinky_01_l",
	"LeftLittleIntermediate": "pinky_02_l",
	"LeftLittleDistal": "pinky_03_l",

	"RightShoulder": "clavicle_r",
	"RightUpperArm": "upperarm_r",
	"RightLowerArm": "lowerarm_r",
	"RightHand": "hand_r",
	"RightThumbMetacarpal": "thumb_01_r",
	"RightThumbProximal": "thumb_02_r",
	"RightThumbDistal": "thumb_03_r",
	"RightIndexProximal": "index_01_r",
	"RightIndexIntermediate": "index_02_r",
	"RightIndexDistal": "index_03_r",
	"RightMiddleProximal": "middle_01_r",
	"RightMiddleIntermediate": "middle_02_r",
	"RightMiddleDistal": "middle_03_r",
	"RightRingProximal": "ring_01_r",
	"RightRingIntermediate": "ring_02_r",
	"RightRingDistal": "ring_03_r",
	"RightLittleProximal": "pinky_01_r",
	"RightLittleIntermediate": "pinky_02_r",
	"RightLittleDistal": "pinky_03_r",

	"LeftUpperLeg": "thigh_l",
	"LeftLowerLeg": "calf_l",
	"LeftFoot": "foot_l",
	"LeftToes": "ball_l",
	"RightUpperLeg": "thigh_r",
	"RightLowerLeg": "calf_r",
	"RightFoot": "foot_r",
	"RightToes": "ball_r",
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var ok := true
	ok = _build("cc_base_to_humanoid.tres", CC_MAP) and ok
	ok = _build("mixamo_to_humanoid.tres", MIXAMO_MAP) and ok
	ok = _build("rigify_def_to_humanoid.tres", RIGIFY_MAP) and ok
	ok = _build("ue_mannequin_to_humanoid.tres", UE_MANNEQUIN_MAP) and ok
	quit(0 if ok else 1)


func _build(file_name: String, mapping: Dictionary) -> bool:
	var profile := SkeletonProfileHumanoid.new()
	var bm := BoneMap.new()
	bm.profile = profile

	# Every profile bone must be visited: unmapped ones are explicitly cleared
	# so no stale default survives into the saved resource.
	var mapped := 0
	for i in profile.bone_size:
		var pname := profile.get_bone_name(i)
		var target: String = mapping.get(pname, "")
		bm.set_skeleton_bone_name(pname, target)
		if target != "":
			mapped += 1

	# Catch typos in the dictionary keys: anything not in the profile is a bug.
	for key in mapping:
		if profile.find_bone(key) == -1:
			printerr("  !! '%s' is not a SkeletonProfileHumanoid bone" % key)
			return false

	var path := OUT_DIR.path_join(file_name)
	var err := ResourceSaver.save(bm, path)
	if err != OK:
		printerr("  !! save failed (%d): %s" % [err, path])
		return false
	print("wrote %s  (%d/%d profile bones mapped)" % [path, mapped, profile.bone_size])
	return true
