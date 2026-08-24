class_name ManorChair
extends Node3D
## Interactive chair/bench node enabling player and NPC sitting interaction with forward seat offset.

signal player_sat(player: CharacterBody3D)
signal player_stood(player: CharacterBody3D)

const FONT_CHINESE := "res://assets/Fonts/Long_Cang/LongCang-Regular.ttf"

@export var prompt_text := "坐下"
@export var seat_offset := Vector3(0.0, 0.0, 0.28)
@export var seat_yaw_offset := 0.0
@export var interaction_radius := 1.8

var _area: Area3D
var _prompt_label: Label3D
var _player_in_range: CharacterBody3D = null
var _occupant: CharacterBody3D = null
var _font_chinese: Font = null


func _ready() -> void:
	if ResourceLoader.exists(FONT_CHINESE):
		_font_chinese = load(FONT_CHINESE) as Font
	_build_trigger()
	_build_prompt()


func _process(_delta: float) -> void:
	if _occupant != null:
		if _occupant.has_method("is_sitting") and not _occupant.call("is_sitting"):
			_occupant = null
			_update_prompt()


func _build_trigger() -> void:
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 1

	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = interaction_radius
	cyl.height = 2.2
	col.shape = cyl
	col.position.y = 1.0
	_area.add_child(col)
	add_child(_area)

	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)


func _build_prompt() -> void:
	_prompt_label = Label3D.new()
	_prompt_label.text = "[E] " + prompt_text
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.position = seat_offset + Vector3(0.0, 1.3, 0.0)
	_prompt_label.font_size = 22
	_prompt_label.outline_size = 6
	_prompt_label.modulate = Color(0.9, 0.95, 1.0)
	_prompt_label.visible = false
	if _font_chinese != null:
		_prompt_label.font = _font_chinese
	add_child(_prompt_label)


func _update_prompt() -> void:
	if _prompt_label == null:
		return
	if _occupant != null:
		_prompt_label.text = "[E] / [WASD] 站起"
		_prompt_label.modulate = Color(1.0, 0.85, 0.4)
	else:
		_prompt_label.text = "[E] " + prompt_text
		_prompt_label.modulate = Color(0.9, 0.95, 1.0)


func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D and body.name == "Player":
		_player_in_range = body as CharacterBody3D
		_update_prompt()
		if _prompt_label != null:
			_prompt_label.visible = true


func _on_body_exited(body: Node3D) -> void:
	if body == _player_in_range:
		_player_in_range = null
		if _occupant == null and _prompt_label != null:
			_prompt_label.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E and _player_in_range != null:
			if _occupant == null:
				sit_player(_player_in_range)
				get_viewport().set_input_as_handled()
			elif _occupant == _player_in_range:
				stand_player()
				get_viewport().set_input_as_handled()


func sit_player(player: CharacterBody3D) -> void:
	if player == null or _occupant != null:
		return
	_occupant = player
	var seat_pos := global_position + global_transform.basis * seat_offset
	var seat_yaw := global_rotation.y + seat_yaw_offset

	if player.has_method("sit_down"):
		player.call("sit_down", seat_pos, seat_yaw)
	_update_prompt()
	player_sat.emit(player)


func stand_player() -> void:
	if _occupant == null:
		return
	var p := _occupant
	_occupant = null
	if p.has_method("stand_up"):
		p.call("stand_up")
	_update_prompt()
	player_stood.emit(p)
