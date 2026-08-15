extends SceneTree
## Dumps SkeletonProfileHumanoid bone names + reference pose, so bone maps can
## be authored against exact strings instead of guesses.

func _initialize() -> void:
	var p := SkeletonProfileHumanoid.new()
	print("=== SkeletonProfileHumanoid: %d bones, %d groups ===" % [
		p.bone_size, p.group_size])
	for i in p.group_size:
		print("group %d: %s" % [i, p.get_group_name(i)])
	print("--- bones: idx | name | parent | tail | group | reference_pose.origin ---")
	for i in p.bone_size:
		var rp := p.get_reference_pose(i)
		print("%2d | %-24s | %-20s | %-20s | %-10s | (%6.3f,%6.3f,%6.3f)" % [
			i, p.get_bone_name(i), p.get_bone_parent(i), p.get_bone_tail(i),
			p.get_group(i), rp.origin.x, rp.origin.y, rp.origin.z])
	quit(0)
