class_name EquipmentManager
extends Node
## PlayerController component managing equipping, unequipping, and applying ItemData behaviors.

var controller: Node # PlayerController
var equipped_items := {} # {"right_hand": HandheldItem, "left_hand": HandheldItem}


func _ready() -> void:
	controller = get_parent()


## Equips weapon by id from JSON configuration file.
func equip_by_id(weapon_id: String, socket_name: String = "") -> HandheldItem:
	var mesh := WeaponConfig.mesh_scene_for(weapon_id)
	if mesh == null:
		push_warning("EquipmentManager: no model for weapon '%s'" % weapon_id)
		return null
	return equip(WeaponConfig.to_item_data(
		weapon_id, WeaponConfig.load_for(weapon_id), mesh), socket_name)


## Instantiates HandheldItem and mounts it on specified socket.
func equip(item_data: ItemData, socket_name: String = "") -> HandheldItem:
	if controller == null:
		return null
	var char_node = controller.get("character") as Character
	if char_node == null:
		return null
	if socket_name.is_empty():
		socket_name = item_data.default_socket

	unequip(socket_name)

	var socket_node = char_node.get_socket_node(socket_name)
	if socket_node == null:
		push_warning("Socket %s not found on character %s" % [socket_name, char_node.name])
		return null

	var item := HandheldItem.new()
	socket_node.add_child(item)
	item.initialize(item_data)

	equipped_items[socket_name] = item

	if socket_name == "right_hand":
		apply_behaviour(item_data)
	return item


func equipped(socket_name: String) -> HandheldItem:
	var item = equipped_items.get(socket_name)
	return item if is_instance_valid(item) else null


func unequip(socket_name: String) -> void:
	if not equipped_items.has(socket_name):
		return
	var item = equipped_items[socket_name]
	if is_instance_valid(item):
		item.queue_free()
	equipped_items.erase(socket_name)

	if socket_name == "right_hand":
		apply_behaviour(null)


## Updates weapon stance clip, blend, locomotion poles, action graph and blade
## trail on PlayerController.
func apply_behaviour(item_data: ItemData) -> void:
	# One guard for all five calls: they arrived together and a parent that has
	# any of them has all of them. Checked at all so this component can be hung on
	# something that is not a PlayerController without filling the log.
	if controller == null or not controller.has_method("set_weapon_graph"):
		return
	if item_data == null:
		controller.call("set_weapon_graph", {})
		controller.call("set_weapon_stance", 0.0)
		# Poles back to the bare-handed clips, or the last weapon's walk survives it.
		controller.call("set_weapon_locomotion", "", "", "")
		controller.call("set_weapon_trail", {}, null)
		return
	controller.call("set_weapon_stance_filter", item_data.stance_filter_bone)
	controller.call("set_weapon_stance_clip", item_data.stance_clip)
	controller.call("set_weapon_locomotion", item_data.stance_clip,
		item_data.stance_walk_clip, item_data.stance_run_clip)
	controller.call("set_weapon_graph", item_data.graph)
	controller.call("set_weapon_stance", item_data.stance_blend)
	# The item, not just the settings: the trail's anchors live on the blade, and
	# the caller re-tuning a config in place has no other way to hand it over.
	# Read back from equipped_items rather than taken as an argument, so live
	# re-tuning reaches the item that is actually mounted.
	controller.call("set_weapon_trail", item_data.trail, equipped("right_hand"))
