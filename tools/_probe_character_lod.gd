extends SceneTree
## Checks the character render/compute tier system: the distance banding and its
## hysteresis, what each tier writes onto the meshes and the mixer, that a culled
## body's pose really stops moving, and that turning the system off puts
## everything back.
##
## Exits 0 on success. CharacterLOD is gated off headless by default, so this
## probe switches it on itself and turns the on-screen clamp off - the dummy
## renderer never reports a body as visible.

var _failed := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	_check_banding()
	await _check_live()
	print("\n", "所有检查通过" if _failed == 0 else "%d 项失败" % _failed)
	quit(0 if _failed == 0 else 1)


func _ok(label: String, passed: bool, detail := "") -> void:
	if not passed:
		_failed += 1
	print("%s %s%s" % ["PASS" if passed else "FAIL", label,
		"" if detail.is_empty() else "  (%s)" % detail])


# --- distance banding, no scene ---------------------------------------------

func _check_banding() -> void:
	print("--- 距离分档")
	var lod := CharacterLOD.new()
	lod.near_end = 10.0
	lod.mid_end = 20.0
	lod.cull_end = 40.0

	lod.tier = CharacterLOD.Tier.NEAR
	_ok("脚下是近档", lod.tier_for(1.0) == CharacterLOD.Tier.NEAR)
	_ok("近档粘过边界 2 m", lod.tier_for(11.0) == CharacterLOD.Tier.NEAR)
	_ok("过了粘滞才升中档", lod.tier_for(13.0) == CharacterLOD.Tier.MID)
	_ok("一口气跨到隐档", lod.tier_for(100.0) == CharacterLOD.Tier.CULLED)

	lod.tier = CharacterLOD.Tier.MID
	_ok("中档不因贴边就回近", lod.tier_for(9.0) == CharacterLOD.Tier.MID)
	_ok("够近才回近档", lod.tier_for(7.0) == CharacterLOD.Tier.NEAR)
	_ok("中档粘过 mid_end", lod.tier_for(21.0) == CharacterLOD.Tier.MID)

	lod.tier = CharacterLOD.Tier.CULLED
	_ok("隐档粘住不回远档", lod.tier_for(39.0) == CharacterLOD.Tier.CULLED)
	_ok("回到 38 m 内才是远档", lod.tier_for(37.0) == CharacterLOD.Tier.FAR)
	lod.free()


# --- a real character in a real scene ---------------------------------------

func _check_live() -> void:
	print("--- 实际挂载")
	_ok("headless 下默认关闭（其余 probe 要满速动画）", not CharacterLOD.enabled)
	# Before the scene, so attach() paints on the way in.
	CharacterLOD.set_enabled(true)
	var scene: Node = load("res://scenes/playground.tscn").instantiate()
	root.add_child(scene)
	for i in 30:
		await physics_frame

	var lod: CharacterLOD = null
	for node in CharacterLOD.instances:
		if is_instance_valid(node):
			lod = node
			break
	_ok("PlayerController.setup() 自动挂上了控制器", lod != null)
	if lod == null:
		return
	# The dummy renderer never reports a body on screen; the clamp would pin
	# every tier to 远 and hide the distance path this probe is here to check.
	lod.offscreen_throttle = false

	_ok("认到 AnimationTree 而不是 AnimationPlayer", lod._mixer is AnimationTree)
	_ok("收集到网格", lod._geo.size() > 0, "%d 个" % lod._geo.size())
	if lod._geo.is_empty():
		return
	var geo: GeometryInstance3D = lod._geo[0]
	_ok("交给引擎的剔除距离写上了",
		is_equal_approx(geo.visibility_range_end, lod.cull_end),
		"%.1f m" % geo.visibility_range_end)
	_ok("剔除前有淡出",
		geo.visibility_range_fade_mode == GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF)

	var skeleton: Skeleton3D = scene._visual.get("skeleton") as Skeleton3D
	_ok("找得到骨架", skeleton != null)
	if skeleton == null:
		return

	# Walk it, so "the pose is moving" is unmistakable rather than idle breathing.
	var body: CharacterBody3D = scene._player
	body.intent_source = null
	body.drive(Vector2(0.0, 1.0), 0.0, true)

	print("--- 各档写了什么")
	lod.forced = CharacterLOD.Tier.FAR
	await physics_frame
	await physics_frame
	_ok("远档关掉全部阴影", _shadows_off(lod))
	_ok("远档把混合器切成手动推进",
		lod._mixer.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL)
	_ok("远档压低 lod_bias", geo.lod_bias < lod._bias0[0], "%.2f" % geo.lod_bias)

	lod.forced = CharacterLOD.Tier.NEAR
	await physics_frame
	await physics_frame
	_ok("近档还原阴影", geo.cast_shadow == lod._shadow0[0])
	_ok("近档交回引擎驱动", lod._mixer.callback_mode_process == lod._mode0)
	_ok("近档还原 lod_bias", is_equal_approx(geo.lod_bias, lod._bias0[0]))

	print("--- 姿势推进")
	var moved_near: float = await _pose_travel(skeleton, 12)
	lod.forced = CharacterLOD.Tier.CULLED
	await physics_frame
	await physics_frame
	var moved_culled: float = await _pose_travel(skeleton, 12)
	_ok("近档姿势在动", moved_near > 1e-4, "%.5f" % moved_near)
	_ok("隐档姿势冻结", moved_culled < 1e-6, "%.7f" % moved_culled)

	lod.forced = CharacterLOD.Tier.MID
	lod.mid_hz = 10.0
	await physics_frame
	await physics_frame
	var ticks := 0
	var last := _pose_hash(skeleton)
	for i in 60:
		await physics_frame
		var now := _pose_hash(skeleton)
		if absf(now - last) > 1e-6:
			ticks += 1
		last = now
	# 60 physics frames is one second, so mid_hz=10 should land near ten advances.
	_ok("中档按 mid_hz 推进", ticks >= 6 and ticks <= 16, "1 秒内推进 %d 次" % ticks)

	print("--- 相机距离实测")
	lod.forced = -1
	lod.offscreen_throttle = false
	body.drive(Vector2.ZERO, 0.0)
	# Unparent the camera from the player so the distance is this probe's to set.
	scene._camera.target = null
	await physics_frame
	var eye: Vector3 = scene._camera.global_position
	var walked := PackedInt32Array()
	for step in [5.0, 25.0, 60.0, 400.0]:
		body.global_position = eye + Vector3(0.0, 0.0, step)
		body.velocity = Vector3.ZERO
		for i in 4:
			await physics_frame
		walked.append(lod.tier)
	_ok("距离一路升档 近→中→远→隐",
		walked == PackedInt32Array([CharacterLOD.Tier.NEAR, CharacterLOD.Tier.MID,
			CharacterLOD.Tier.FAR, CharacterLOD.Tier.CULLED]),
		str(walked))

	print("--- 离屏降档")
	lod.forced = -1
	# Back within near_end, so any downgrade left is the on-screen clamp's doing.
	body.global_position = eye + Vector3(0.0, 0.0, 4.0)
	body.velocity = Vector3.ZERO
	body.drive(Vector2(0.0, 1.0), 0.0, true)
	lod.offscreen_throttle = false
	for i in 8:
		await physics_frame
	_ok("回到近处先回近档", lod.tier == CharacterLOD.Tier.NEAR,
		CharacterLOD.tier_name(lod.tier))
	lod.offscreen_throttle = true
	await physics_frame
	await physics_frame
	_ok("离屏把算力档降到 offscreen_tier", lod.anim_tier >= lod.offscreen_tier,
		"当前 %s，相机距离 %.1f m" % [CharacterLOD.tier_name(lod.anim_tier), lod.distance()])
	_ok("离屏不碰渲染档", lod.tier == CharacterLOD.Tier.NEAR,
		CharacterLOD.tier_name(lod.tier))
	_ok("离屏保留阴影（影子仍可能落进画面）", geo.cast_shadow == lod._shadow0[0])
	var moved_off: float = await _pose_travel(skeleton, 20)
	_ok("离屏是降速不是冻结", moved_off > 1e-4, "%.5f" % moved_off)

	print("--- 关掉之后")
	lod.forced = -1
	CharacterLOD.set_enabled(false)
	await physics_frame
	_ok("阴影还原", geo.cast_shadow == lod._shadow0[0])
	_ok("lod_bias 还原", is_equal_approx(geo.lod_bias, lod._bias0[0]))
	_ok("剔除距离撤掉", geo.visibility_range_end == 0.0)
	_ok("混合器交回原本的回调模式", lod._mixer.callback_mode_process == lod._mode0)

	var shaped := 0
	for g in lod._geo:
		var mi := g as MeshInstance3D
		if mi != null and mi.mesh != null and mi.mesh.get_blend_shape_count() > 0:
			shaped += 1
	print("注: %d/%d 个网格带 blend shape —— 导入器不给这些网格生成 LOD，" % [shaped, lod._geo.size()]
		+ "对它们 lod_bias 不起作用，省的是阴影和姿势那两头")

	scene.queue_free()
	for i in 4:
		await process_frame
	_ok("场景释放后不留残留实例", CharacterLOD.instances.is_empty(),
		"%d 个" % CharacterLOD.instances.size())


func _shadows_off(lod: CharacterLOD) -> bool:
	for g in lod._geo:
		if is_instance_valid(g) and g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			return false
	return true


## Sum over every bone pose rotation. Changes iff the mixer wrote a new pose.
func _pose_hash(skeleton: Skeleton3D) -> float:
	var acc := 0.0
	for i in skeleton.get_bone_count():
		var q := skeleton.get_bone_pose_rotation(i)
		acc += q.x + q.y * 2.0 + q.z * 3.0 + q.w * 5.0
	return acc


## Furthest the pose gets from where it started over `frames` physics frames.
func _pose_travel(skeleton: Skeleton3D, frames: int) -> float:
	var start := _pose_hash(skeleton)
	var worst := 0.0
	for i in frames:
		await physics_frame
		worst = maxf(worst, absf(_pose_hash(skeleton) - start))
	return worst
