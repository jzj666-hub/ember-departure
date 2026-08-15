@tool
extends SceneTree

const NavGridScript = preload("res://scripts/nav_grid.gd")

func _init() -> void:
	print("\n--- standing node closest block probe ---")
	var nav := NavGridScript.new()
	nav.set_bounds(10, 5)
	
	# Block A at (0, 0, 0) with surface at y = 1.0 (level 1)
	# Block B at (1, 0, 0) and (1, 1, 0) with surface at y = 2.0 (level 2)
	nav.set_block(Vector3i(0, 0, 0), true)
	nav.set_block(Vector3i(1, 0, 0), true)
	nav.set_block(Vector3i(1, 1, 0), true)

	# Test 1: Character standing on top of Block B at x = 0.9, y = 2.0
	# pos.x is 0.9 (which is in x=0 column if using floor(pos.x)), but feet are at y=2.0 on top of Block B at x=1!
	var node := nav.standing_node(Vector3(0.9, 2.0, 0.5))
	
	assert(node == Vector3i(1, 2, 0), "Character at y=2.0 on top block should map to Vector3i(1, 2, 0)!")
	print("  PASS  Character at (0.9, 2.0, 0.5) correctly identified on top block (1, 2, 0)!")

	# Test 2: Character standing on Block A at x = 0.4, y = 1.0
	var node2 := nav.standing_node(Vector3(0.4, 1.0, 0.5))
	assert(node2 == Vector3i(0, 1, 0), "Character on Block A should map to Vector3i(0, 1, 0)!")
	print("  PASS  Character at (0.4, 1.0, 0.5) correctly identified on lower block (0, 1, 0)!")

	print("all standing node probe tests passed!\n")
	quit(0)
