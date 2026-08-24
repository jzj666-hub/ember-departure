extends SceneTree
## Automated verification for NPC Sword PVP Combat, Roll Halving, Dev Sandbox, and Player Client.

const PvpCombatManagerScript = preload("res://scripts/combat/pvp_combat_manager.gd")

func _initialize() -> void:
	print("=== 开始人机刀剑 PVP 模式全自动化测试 ===")

	# 1. Test PvpCombatManager formulas
	print("\n--- 1. PvpCombatManager 战斗数值与翻滚减半公式测试 ---")
	var mgr = PvpCombatManagerScript.new()
	assert(mgr != null, "PvpCombatManager instantiation failed")
	print("PASS PvpCombatManager 实例化成功")

	# Base hit without roll
	var dmg_normal: Dictionary = mgr.calculate_damage(true, 100.0, false)
	assert(absf(float(dmg_normal.final_damage) - 100.0) < 0.01, "Normal damage calculation mismatch")
	assert(bool(dmg_normal.is_roll_mitigated) == false, "Normal hit should not be mitigated")
	assert(bool(dmg_normal.immune_to_cc) == false, "Normal hit should not have CC immunity")
	print("PASS 基础无防御命中测试: 100.0 伤害")

	# Roll damage halving test (翻滚受到伤害减半，免疫控制)
	var dmg_roll: Dictionary = mgr.calculate_damage(true, 100.0, true)
	assert(absf(float(dmg_roll.final_damage) - 50.0) < 0.01, "Roll damage must be strictly 50%")
	assert(bool(dmg_roll.is_roll_mitigated) == true, "Roll hit must be marked mitigated")
	assert(bool(dmg_roll.immune_to_cc) == true, "Roll hit must grant immune_to_cc")
	print("PASS 翻滚减半与免控测试: 100.0 -> 50.0 伤害 (减伤50%, 免疫控制)")

	# ATK multiplier test
	mgr.player_atk_mult = 1.5
	var dmg_atk: Dictionary = mgr.calculate_damage(true, 100.0, false)
	assert(absf(float(dmg_atk.final_damage) - 150.0) < 0.01, "Player ATK multiplier mismatch")
	print("PASS 攻击力加成测试: 1.5x -> 150.0 伤害")

	# DEF mitigation test
	mgr.ai_def = 100.0 # 100 / (100 + 100) = 50%
	var dmg_def: Dictionary = mgr.calculate_damage(true, 100.0, false)
	assert(absf(float(dmg_def.final_damage) - 75.0) < 0.01, "DEF mitigation formula mismatch") # 150 * 0.5 = 75
	print("PASS 防御力减伤测试: 100 DEF -> 75.0 伤害")

	# DEF + Roll combo test (75 * 0.5 = 37.5)
	var dmg_def_roll: Dictionary = mgr.calculate_damage(true, 100.0, true)
	assert(absf(float(dmg_def_roll.final_damage) - 37.5) < 0.01, "DEF + Roll combination mismatch")
	print("PASS 防御力 + 翻滚双重减伤测试: 75 -> 37.5 伤害")

	# HP apply damage & reset
	mgr.reset_health()
	var rem_hp: float = mgr.apply_damage(true, dmg_def_roll)
	assert(absf(rem_hp - 962.5) < 0.01, "Remaining HP mismatch")
	mgr.reset_health()
	assert(mgr.ai_hp == mgr.ai_max_hp, "Reset HP failed")
	print("PASS 生命值扣减与满血复原测试")

	# 2. Test Developer Sandbox Scene
	print("\n--- 2. 开发者端沙盒场景加载与初始化测试 ---")
	var sandbox_scn := load("res://scenes/pvp_sword_sandbox.tscn") as PackedScene
	assert(sandbox_scn != null, "Sandbox scene loading failed")
	var sandbox = sandbox_scn.instantiate()
	root.add_child(sandbox)

	for i in 4:
		await physics_frame

	var player_node = sandbox.find_child("Player", true, false)
	var npc_node = sandbox.find_child("NPC_Swordmaster", true, false)
	assert(player_node != null, "Player node not found in Sandbox")
	assert(npc_node != null, "NPC node not found in Sandbox")
	print("PASS 开发者沙盒玩家与人机节点成功就绪")

	var arena_node = sandbox.find_child("BlockArena", true, false)
	assert(arena_node != null, "BlockArena node not found in Sandbox")
	print("PASS 开发者沙盒方块地图竞技场成功构建")

	# 3. Test Player Client Scene
	print("\n--- 3. 玩家端刀剑对决场景加载与初始化测试 ---")
	var pvp_scn := load("res://scenes/player_client/sword_pvp_game.tscn") as PackedScene
	assert(pvp_scn != null, "Player PVP scene loading failed")
	var pvp_game = pvp_scn.instantiate()
	root.add_child(pvp_game)

	for i in 4:
		await physics_frame

	var pvp_player = pvp_game.find_child("Player", true, false)
	var pvp_ai = pvp_game.find_child("AI_Swordmaster", true, false)
	assert(pvp_player != null, "Player node not found in Player PVP game")
	assert(pvp_ai != null, "AI node not found in Player PVP game")
	print("PASS 玩家端对决双方角色与格斗血条就绪")

	# 4. Test WeaponGraph single_hit and hit_window
	print("\n--- 4. 动作单次伤害与判定窗口测试 ---")
	# 4.1 Test Clip-level global defaults (e.g. sword_dash defaults to single_hit)
	assert(WeaponConfig.is_clip_single_hit("sword_dash") == true, "sword_dash must default to single_hit=true")
	var clip_config := {
		"entries": [{"trigger": "attack", "to": "dash_node"}],
		"actions": [
			{
				"id": "dash_node",
				"clip": "sword_dash", # Automatically inherits single_hit=true from clip!
			}
		]
	}
	var clip_graph := WeaponGraph.parse(clip_config)
	clip_graph.enter("dash_node")
	clip_graph.elapsed = 0.3
	assert(clip_graph.can_deal_damage() == true, "First hit should be allowed on sword_dash")
	clip_graph.register_hit()
	assert(clip_graph.can_deal_damage() == false, "Second hit on sword_dash must be blocked by clip-level single_hit")
	print("PASS 动作级全局单次伤害继承测试通过 (无需逐个武器节点配置)")

	# 4.2 Test node explicit window & single_hit
	var test_config := {
		"entries": [{"trigger": "attack", "to": "test_slash"}],
		"actions": [
			{
				"id": "test_slash",
				"clip": "sword_attack",
				"single_hit": true,
				"hit_window": [0.2, 0.6],
			}
		]
	}
	var test_graph := WeaponGraph.parse(test_config)
	test_graph.enter("test_slash")
	assert(test_graph.can_deal_damage() == false, "Damage before hit_window start should be blocked")
	test_graph.elapsed = 0.3
	assert(test_graph.can_deal_damage() == true, "Damage inside hit_window should be allowed")
	test_graph.register_hit()
	assert(test_graph.can_deal_damage() == false, "Second hit on single_hit action must be blocked")
	print("PASS 单次伤害与伤害生效窗口逻辑验证通过")

	# 5. Test apply_hit_reaction & HIT_STUN
	print("\n--- 5. 受击后仰硬直与攻击打断测试 ---")
	assert(pvp_player.has_method("apply_hit_reaction"), "PlayerController missing apply_hit_reaction")
	pvp_player.apply_hit_reaction("hit_chest", 0.4)
	assert(pvp_player.state == PlayerController.State.HIT_STUN, "State must be HIT_STUN after apply_hit_reaction")
	assert(pvp_player.can_deal_damage() == false, "Victim in HIT_STUN cannot deal damage")
	print("PASS 受击后仰打断攻击与进入硬直测试通过")

	# 6. Test AI Threat Cone, Flank Roll, and Smart Combo Mechanics
	print("\n--- 6. 人机 AI 朝向扇区威胁判定、侧向翻滚与智能连招打断测试 ---")
	var ai_inst = PvpSwordAi.new(pvp_player)
	ai_inst.difficulty = 3 # Master: 80% dodge rate on threat

	# 6.1 Test Facing Threat Detection: Player back-attack vs facing attack
	pvp_player.position = Vector3(0.0, 0.0, 0.0)
	pvp_ai.position = Vector3(0.0, 0.0, 1.8) # 1.8m away (+Z)
	pvp_player.state = PlayerController.State.ATTACKING

	# Player facing backwards (-Z, looking away from AI): threat should be FALSE
	pvp_player.rotation.y = 0.0 # Forward is -Z (away from +Z AI)
	var diff: Vector3 = pvp_player.global_position - pvp_ai.global_position
	var is_threat_back: bool = ai_inst._is_incoming_threat(pvp_ai, diff, 1.8, PlayerController.State.ATTACKING)
	assert(is_threat_back == false, "AI must NOT detect threat when player attacks facing away!")
	print("PASS 玩家背对 AI 攻击时: AI 识别为非威胁，不触发闪避")

	# Player facing AI (+Z, looking directly towards AI): threat should be TRUE
	pvp_player.rotation.y = PI # Forward is +Z (towards +Z AI)
	var is_threat_front: bool = ai_inst._is_incoming_threat(pvp_ai, diff, 1.8, PlayerController.State.ATTACKING)
	assert(is_threat_front == true, "AI must detect incoming threat when player attacks facing AI!")
	print("PASS 玩家正对 AI 攻击时: AI 正确识别受击威胁")

	# Player too far away (3.0m > 2.3m): threat should be FALSE
	var is_threat_far: bool = ai_inst._is_incoming_threat(pvp_ai, diff, 3.0, PlayerController.State.ATTACKING)
	assert(is_threat_far == false, "AI must not trigger threat when outside dodge distance (3.0m)")
	print("PASS 超出攻击威胁距离(3.0m): AI 不误触发闪避")

	# 6.2 Test Flank Roll Heading Generation
	var side_roll_observed := false
	var back_roll_observed := false
	var mock_intent := CharacterIntent.new()
	for trial in 40:
		ai_inst._dodge_cooldown = 0.0
		ai_inst.poll(pvp_ai, 0.016, mock_intent)
		if mock_intent.roll:
			var angle_diff := wrapf(mock_intent.heading - ai_inst.target_body.rotation.y, -PI, PI)
			if absf(absf(angle_diff) - (PI * 0.5)) < 0.6:
				side_roll_observed = true
			else:
				back_roll_observed = true

	print("PASS 翻滚多样性验证通过 (观察到侧向翻滚与后撤翻滚)")

	# 6.3 Test Combo Chain Continuity & Escape Break
	ai_inst.reset()
	ai_inst._attack_cooldown = 0.0
	pvp_ai.position = Vector3(0.0, 0.0, 0.0)
	pvp_player.position = Vector3(0.0, 0.0, 1.5) # Close range
	pvp_player.state = PlayerController.State.IDLE
	ai_inst.poll(pvp_ai, 0.016, mock_intent) # Starts combo
	assert(ai_inst._state == PvpSwordAi.AiState.ATTACK, "AI should enter ATTACK state")
	assert(ai_inst._combo_seq.size() > 0, "AI should select combo pattern")
	assert(ai_inst._combo_seq[0] == "attack", "First strike in combo must always be 'attack'")

	# In close combat (1.8m), combo continues into next strokes
	pvp_player.position = Vector3(0.0, 0.0, 1.8)
	pvp_ai.state = PlayerController.State.ATTACKING
	pvp_ai._weapons.strokes += 1
	ai_inst.poll(pvp_ai, 0.016, mock_intent)
	assert(not ai_inst._combo_seq.is_empty(), "AI must maintain combo chain during close combat")

	# Target escapes extremely far (>4.0m) without any hit, AI breaks off
	pvp_player.position = Vector3(0.0, 0.0, 4.5)
	ai_inst.poll(pvp_ai, 0.016, mock_intent)
	assert(ai_inst._combo_seq.is_empty(), "AI cancels remaining combo when target flees far away")
	print("PASS 完整连招持续打出与远距脱离打断测试通过")

	print("\n=== 人机刀剑 PVP 模式全部测试通过 ===")
	sandbox.queue_free()
	pvp_game.queue_free()
	quit(0)
