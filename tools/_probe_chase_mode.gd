extends SceneTree
## Headless probe for 1v1 Chase Mode rules and subsystems.

const NavGridScript = preload("res://scripts/nav_grid.gd")
const NPCIntentSourceScript = preload("res://scripts/npc_intent_source.gd")
const ChaseModeScript = preload("res://scripts/chase_mode.gd")

var _failures := 0


func _initialize() -> void:
	print("\n=== 1v1 Chase Mode Probe Test Suite ===")

	_test_same_flat_platform()
	_test_npc_intent_action_state()
	_test_repath_timing_rules()
	_test_chase_mode_scene()

	print("")
	if _failures == 0:
		print("ALL CHASE MODE TESTS PASSED (0 failures)")
	else:
		print("%d CHASE MODE TEST(S) FAILED" % _failures)

	quit(_failures)


func _ok(label: String, condition: bool, extra := "") -> void:
	if condition:
		print("  PASS  %s %s" % [label, extra])
	else:
		print("  FAIL  %s %s" % [label, extra])
		_failures += 1


func _test_same_flat_platform() -> void:
	print("\n--- Test 1: NavGrid.is_same_flat_platform ---")
	var nav := NavGridScript.new()
	nav.set_bounds(20, 10)

	# Build 3x3 platform at y=2 (block at y=1)
	for x in range(3):
		for z in range(3):
			nav.set_block(Vector3i(x, 1, z), true) # block top is y=2

	# Another isolated platform at x=8, z=8, y=2
	nav.set_block(Vector3i(8, 1, 8), true)

	# High platform at x=15, z=15, y=4
	for y in range(4):
		nav.set_block(Vector3i(15, y, 15), true) # block top is y=4

	var c_00 := Vector3i(0, 2, 0)
	var c_22 := Vector3i(2, 2, 2)
	var c_iso := Vector3i(8, 2, 8)
	var c_high := Vector3i(15, 4, 15)

	_ok("Same cell is on same platform", nav.is_same_flat_platform(c_00, c_00))
	_ok("Adjacent walkable cells on same platform return true", nav.is_same_flat_platform(c_00, c_22))
	_ok("Disconnected platform across gap returns false", not nav.is_same_flat_platform(c_00, c_iso))
	_ok("Different height platform returns false", not nav.is_same_flat_platform(c_00, c_high))


func _test_npc_intent_action_state() -> void:
	print("\n--- Test 2: NPCIntentSource Action State & Direct Chase ---")
	var intent := NPCIntentSourceScript.new()

	_ok("Fresh intent is not jumping or climbing", not intent.is_performing_jump_or_climb())

	intent._is_climbing = true
	_ok("is_climbing=true reports performing action", intent.is_performing_jump_or_climb())
	intent._is_climbing = false

	intent._jump_phase = NPCIntentSourceScript.JumpPhase.AIRBORNE
	_ok("JumpPhase.AIRBORNE reports performing action", intent.is_performing_jump_or_climb())
	intent._jump_phase = NPCIntentSourceScript.JumpPhase.NONE

	intent._replay_phase = NPCIntentSourceScript.ReplayPhase.REPLAYING
	_ok("ReplayPhase.REPLAYING reports performing action", intent.is_performing_jump_or_climb())
	intent._replay_phase = NPCIntentSourceScript.ReplayPhase.NONE

	_ok("Restored intent returns false", not intent.is_performing_jump_or_climb())

	# Test direct_chase mode
	intent.direct_chase(Vector3(10.0, 0.0, 0.0))
	_ok("direct_chase enables _direct_chase_mode", intent._direct_chase_mode)
	_ok("direct_chase sets _has_target", intent._has_target)
	var ci := CharacterIntent.new()
	intent._drive_navigation(null, Vector3(0.0, 0.0, 0.0), 0.016, ci)
	_ok("direct_chase outputs full forward sprint", ci.move == Vector2(0.0, 1.0) and ci.run)


func _test_repath_timing_rules() -> void:
	print("\n--- Test 3: Chase Mode Repath Logic & Rule Invariants ---")
	var scene := load("res://scenes/chase_mode.tscn") as PackedScene
	_ok("ChaseMode scene loaded", scene != null)

	var cm: Node = scene.instantiate()
	root.add_child(cm)
	await process_frame

	# Check initial state
	_ok("Initial state is SELECT_MAP", cm.get("_state") == ChaseModeScript.State.SELECT_MAP)

	# Simulate starting escape countdown
	cm.call("_start_escape_countdown")
	_ok("State transitions to ESCAPE_COUNTDOWN", cm.get("_state") == ChaseModeScript.State.ESCAPE_COUNTDOWN)
	_ok("Escape countdown set to 15.0s", is_equal_approx(float(cm.get("_escape_timer")), 15.0))

	# Test Rule 4 Deferral invariant:
	# When NPC is performing jump/climb, _request_npc_repath flags _deferred_repath_pending
	var npc_intent: NPCIntentSource = cm.get("_npc_intent")
	npc_intent._jump_phase = NPCIntentSourceScript.JumpPhase.AIRBORNE
	cm.call("_request_npc_repath", false)
	_ok("Rule 4: Mid-air repath request is deferred", bool(cm.get("_deferred_repath_pending")))

	# When NPC lands, deferred repath is cleared
	npc_intent._jump_phase = NPCIntentSourceScript.JumpPhase.NONE
	cm.set("_deferred_repath_pending", false)
	_ok("Deferred flag clears on landing execution", not bool(cm.get("_deferred_repath_pending")))

	# Test Rule 3 Landing trigger:
	cm.set("_player_was_jumping_or_climbing", true)
	# Simulate landing
	cm.call("_request_npc_repath", true)
	_ok("Rule 3: Player landing resets repath timer to 0.0", is_zero_approx(float(cm.get("_repath_timer"))))

	# Test Catch detection & Game Over trigger
	var player: CharacterBody3D = cm.get("_player")
	var npc: CharacterBody3D = cm.get("_npc")
	player.global_position = Vector3(0.0, 0.0, 0.0)
	npc.global_position = Vector3(0.8, 0.0, 0.0) # distance 0.8m <= 1.05m
	cm.set("_state", ChaseModeScript.State.CHASE_ACTIVE)
	cm._physics_process(0.016)
	_ok("Catch within 1 cell triggers GAME_OVER", cm.get("_state") == ChaseModeScript.State.GAME_OVER)

	cm.queue_free()


func _test_chase_mode_scene() -> void:
	print("\n--- Test 4: ChaseMode Scene Stability ---")
	var scene := load("res://scenes/chase_mode.tscn") as PackedScene
	var instance: Node = scene.instantiate()
	root.add_child(instance)
	await process_frame
	await process_frame
	_ok("ChaseMode scene executes _ready() cleanly", instance.is_inside_tree())
	instance.queue_free()
	await process_frame
