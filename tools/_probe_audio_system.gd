extends SceneTree

const SCENE := "res://scenes/manor_estate.tscn"

var _failed := 0

func _initialize() -> void:
	_run()

func _run() -> void:
	print("--- 开始 3D 音频空间化、脚步声衰减与监听器测试 ---")
	var scn = load(SCENE) as PackedScene
	_ok("场景加载", scn != null)
	if scn == null:
		quit(1)
		return

	var inst = scn.instantiate() as Node3D
	root.add_child(inst)

	for i in 15:
		await physics_frame

	# 1. Check Player AudioListener3D
	var player = inst.find_child("Player", true, false)
	_ok("玩家对象存在", player != null)
	if player != null:
		var listener: AudioListener3D = player.find_child("PlayerAudioListener", true, false) as AudioListener3D
		_ok("玩家头部绑定 AudioListener3D", listener != null)
		if listener != null:
			_ok("AudioListener3D 处于当前激活状态 (is_current)", listener.is_current())

		# 2. Check 3D Footstep Player on Player
		var foot_player: AudioStreamPlayer3D = player.find_child("FootstepAudio3D", true, false) as AudioStreamPlayer3D
		_ok("玩家具有 3D 脚步声发声器", foot_player != null)
		if foot_player != null:
			_ok("脚步声衰减距离合理 (max_distance <= 15m)", foot_player.max_distance <= 15.0)

	# 3. Check NPCs 3D Footstep Players
	var wandering_npcs: Array = inst.get("_wandering_npcs")
	if wandering_npcs != null and not wandering_npcs.is_empty():
		var npc = wandering_npcs[0] as Node
		var npc_foot: AudioStreamPlayer3D = npc.find_child("FootstepAudio3D", true, false) as AudioStreamPlayer3D
		_ok("NPC 独立具有 3D 空间脚步声发声器", npc_foot != null)

	# 4. Check Merchant 3D Voice Player
	var merchant = inst.find_child("EmberMerchant", true, false)
	_ok("商贩存在", merchant != null)
	if merchant != null:
		var voice_player: AudioStreamPlayer3D = merchant.find_child("MerchantVoice", true, false) as AudioStreamPlayer3D
		_ok("商贩具有 3D 语音发声器", voice_player != null)
		if voice_player != null:
			_ok("商贩语音音量已增强 (volume_db >= 6dB)", voice_player.volume_db >= 6.0)
			_ok("商贩语音清晰传播半径增大 (unit_size >= 5.0)", voice_player.unit_size >= 5.0)

	print("\n", "=== 音频空间化系统全部验证通过 ===" if _failed == 0 else "=== %d 项未通过 ===" % _failed)
	inst.queue_free()
	quit(0 if _failed == 0 else 1)

func _ok(label: String, passed: bool) -> void:
	if not passed:
		_failed += 1
	print("%s %s" % ["PASS" if passed else "FAIL", label])
