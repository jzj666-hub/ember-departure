class_name ManorTeleporter
extends Node3D

signal teleport_requested(target_position: Vector3, target_yaw: float)

@export var prompt_text: String = "进入室内"
@export var target_position: Vector3 = Vector3.ZERO
@export var target_yaw: float = 0.0
@export var trigger_radius: float = 1.6
@export var portal_color: Color = Color(0.25, 0.85, 1.0)

var _area: Area3D
var _ring_mesh: MeshInstance3D
var _light: OmniLight3D
var _prompt_label: Label3D
var _player_in_range: CharacterBody3D = null
var _time: float = 0.0


func _ready() -> void:
	_build_visuals()
	_build_trigger()


func _build_visuals() -> void:
	_ring_mesh = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = trigger_radius * 0.75
	torus.outer_radius = trigger_radius * 0.95
	_ring_mesh.mesh = torus
	_ring_mesh.position.y = 0.06

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = portal_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.8
	mat.emission_enabled = true
	mat.emission = portal_color
	mat.emission_energy_multiplier = 2.0
	_ring_mesh.material_override = mat
	add_child(_ring_mesh)

	_light = OmniLight3D.new()
	_light.light_color = portal_color
	_light.light_energy = 1.2
	_light.omni_range = trigger_radius * 2.5
	_light.position.y = 0.8
	add_child(_light)

	_prompt_label = Label3D.new()
	_prompt_label.text = "[E] " + prompt_text
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.position.y = 1.8
	_prompt_label.font_size = 28
	_prompt_label.outline_size = 8
	_prompt_label.outline_modulate = Color(0, 0, 0, 0.9)
	_prompt_label.modulate = Color(1.0, 1.0, 1.0, 0.9)
	_prompt_label.visible = false
	add_child(_prompt_label)


func _build_trigger() -> void:
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 1

	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = trigger_radius
	cyl.height = 2.4
	col.shape = cyl
	col.position.y = 1.2
	_area.add_child(col)
	add_child(_area)

	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	_time += delta
	if _ring_mesh != null:
		_ring_mesh.rotation.y += delta * 0.8
		var pulse := 0.7 + 0.3 * sin(_time * 3.0)
		var mat := _ring_mesh.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color.a = pulse
	if _light != null:
		_light.light_energy = 1.0 + 0.4 * sin(_time * 4.0)


func _unhandled_input(event: InputEvent) -> void:
	if _player_in_range != null and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			_trigger_teleport()
			get_viewport().set_input_as_handled()


func _trigger_teleport() -> void:
	if _player_in_range == null:
		return
	teleport_requested.emit(target_position, target_yaw)


func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		_player_in_range = body as CharacterBody3D
		if _prompt_label != null:
			_prompt_label.visible = true


func _on_body_exited(body: Node3D) -> void:
	if body == _player_in_range:
		_player_in_range = null
		if _prompt_label != null:
			_prompt_label.visible = false
