extends SceneTree
## Throwaway: what the reaction clips actually do to the body. Hip height over
## the clip tells a stagger from a knockdown, and names the matching get-up.

const CLIPS := ["idle", "hit_head", "hit_chest", "hit_knockback", "death_01",
	"lay_to_idle", "zombie_stand_up", "falling_to_roll", "roll"]


func _initialize() -> void:
	_run()


func _run() -> void:
	var packed: PackedScene = load("res://assets/characters/hero/hero.tscn")
	var ch: Character = packed.instantiate() as Character
	root.add_child(ch)
	await process_frame

	var skel: Skeleton3D = ch.skeleton
	var hips := skel.find_bone("Hips")
	print("hips bone: ", hips, "  (", skel.get_bone_name(hips) if hips >= 0 else "?", ")")
	print("%-18s %7s  %s" % ["clip", "len", "hip world Y at 0% 25% 50% 75% 100%"])
	for clip in CLIPS:
		var full: String = ch.resolve(clip)
		if full.is_empty():
			print("%-18s  MISSING" % clip)
			continue
		var anim: Animation = ch.player.get_animation(full)
		anim.loop_mode = Animation.LOOP_NONE
		var row := ""
		for frac in [0.0, 0.25, 0.5, 0.75, 1.0]:
			skel.reset_bone_poses()
			ch.player.play(full)
			ch.player.seek(anim.length * frac, true)
			ch.player.advance(0.0)
			await process_frame
			var y: float = (skel.global_transform * skel.get_bone_global_pose(hips)).origin.y
			row += "%6.2f" % y
		print("%-18s %6.2fs %s" % [clip, anim.length, row])

	print("\n--- does play() with a blend time cross-fade? ---")
	var idle: String = ch.resolve("idle")
	var knock: String = ch.resolve("hit_knockback")
	ch.player.play(knock)
	ch.player.seek(ch.player.get_animation(knock).length, true)
	ch.player.advance(0.0)
	await process_frame
	var down: float = (skel.global_transform * skel.get_bone_global_pose(hips)).origin.y
	print("  end of knockback, hip Y = %.2f" % down)
	ch.player.play(idle, 0.35)
	for i in 6:
		await process_frame
		var y: float = (skel.global_transform * skel.get_bone_global_pose(hips)).origin.y
		print("    frame %d hip Y = %.2f" % [i, y])
	quit()
