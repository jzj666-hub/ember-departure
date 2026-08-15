class_name BlockRegistry
extends RefCounted
## Block type definition registry and multi-cell geometry instance factory.

## Block type definition metadata and material properties.
class BlockType extends RefCounted:
	var id: String = "cube"
	var name: String = "默认立方体"
	var color: Color = Color(0.45, 0.42, 0.38)
	var roughness: float = 0.8
	var metallic: float = 0.0
	var transparency: bool = false
	var is_solid: bool = true
	var can_climb: bool = true
	var custom_properties: Dictionary = {}
	var _material: StandardMaterial3D = null

	## Returns cached or newly built StandardMaterial3D.
	func get_material() -> StandardMaterial3D:
		if _material == null:
			_material = StandardMaterial3D.new()
			_material.albedo_color = color
			_material.roughness = roughness
			_material.metallic = metallic
			if transparency:
				_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				_material.albedo_color.a = 0.6
		return _material

	## Creates visual MeshInstance3D for size dimension in grid units.
	func create_visual(size: Vector3i) -> MeshInstance3D:
		var node := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = Vector3(size)
		box_mesh.material = get_material()
		node.mesh = box_mesh
		node.position = Vector3(size) * 0.5
		return node

	## Creates BoxShape3D collision for size dimension in grid units.
	func create_collision(size: Vector3i) -> CollisionShape3D:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(size)
		col.shape = shape
		col.position = Vector3(size) * 0.5
		return col


## Instantiated block metadata in world grid.
class BlockInstance extends RefCounted:
	var id: String = ""
	var type_id: String = "cube"
	var grid_pos: Vector3i = Vector3i.ZERO
	var size: Vector3i = Vector3i.ONE
	var color_override: Color = Color.WHITE
	var use_color_override: bool = false
	var custom_data: Dictionary = {}
	var body_node: StaticBody3D = null

	## Returns all occupied Vector3i cells.
	func get_occupied_cells() -> Array[Vector3i]:
		var cells: Array[Vector3i] = []
		for x in range(size.x):
			for y in range(size.y):
				for z in range(size.z):
					cells.append(Vector3i(grid_pos.x + x, grid_pos.y + y, grid_pos.z + z))
		return cells

	## Serializes instance into dictionary for map save.
	func to_dict() -> Dictionary:
		var out := {
			"id": id,
			"type": type_id,
			"pos": [grid_pos.x, grid_pos.y, grid_pos.z],
			"size": [size.x, size.y, size.z],
			"custom_data": custom_data,
		}
		if use_color_override:
			out["color"] = [color_override.r, color_override.g, color_override.b, color_override.a]
		return out

	## Deserializes block instance from dictionary.
	static func from_dict(dict: Dictionary) -> BlockInstance:
		var inst := BlockInstance.new()
		inst.id = str(dict.get("id", ""))
		inst.type_id = str(dict.get("type", "cube"))
		var p: Array = dict.get("pos", [0, 0, 0])
		if p.size() >= 3:
			inst.grid_pos = Vector3i(int(p[0]), int(p[1]), int(p[2]))
		var s: Array = dict.get("size", [1, 1, 1])
		if s.size() >= 3:
			inst.size = Vector3i(maxi(1, int(s[0])), maxi(1, int(s[1])), maxi(1, int(s[2])))
		if dict.has("color"):
			var c: Array = dict.get("color", [1, 1, 1, 1])
			if c.size() >= 4:
				inst.color_override = Color(float(c[0]), float(c[1]), float(c[2]), float(c[3]))
				inst.use_color_override = true
		inst.custom_data = dict.get("custom_data", {})
		return inst


static var _types: Dictionary = {}
static var _initialized: bool = false

## Initializes default block types in registry.
static func init_registry() -> void:
	if _initialized:
		return
	_initialized = true

	var default_cube := BlockType.new()
	default_cube.id = "cube"
	default_cube.name = "默认立方体"
	default_cube.color = Color(0.45, 0.42, 0.38)
	default_cube.roughness = 0.8
	register_type(default_cube)

	var stone := BlockType.new()
	stone.id = "stone"
	stone.name = "坚硬岩石"
	stone.color = Color(0.32, 0.34, 0.36)
	stone.roughness = 0.95
	register_type(stone)

	var metal := BlockType.new()
	metal.id = "metal"
	metal.name = "工业金属"
	metal.color = Color(0.65, 0.70, 0.75)
	metal.roughness = 0.3
	metal.metallic = 0.9
	register_type(metal)

	var wood := BlockType.new()
	wood.id = "wood"
	wood.name = "原木结构"
	wood.color = Color(0.55, 0.38, 0.22)
	wood.roughness = 0.7
	register_type(wood)

	var glass := BlockType.new()
	glass.id = "glass"
	glass.name = "透光玻璃"
	glass.color = Color(0.5, 0.8, 0.9, 0.5)
	glass.roughness = 0.1
	glass.transparency = true
	register_type(glass)

	var glow := BlockType.new()
	glow.id = "glow"
	glow.name = "发光体"
	glow.color = Color(0.9, 0.6, 0.2)
	glow.roughness = 0.4
	register_type(glow)


## Registers custom BlockType.
static func register_type(type: BlockType) -> void:
	_types[type.id] = type


## Returns BlockType by id with fallback to default cube.
static func get_type(type_id: String) -> BlockType:
	init_registry()
	return _types.get(type_id, _types.get("cube"))


## Returns array of all registered BlockTypes.
static func list_types() -> Array[BlockType]:
	init_registry()
	var list: Array[BlockType] = []
	for k in _types.keys():
		list.append(_types[k])
	return list


## Creates complete StaticBody3D node for block instance.
static func create_body(inst: BlockInstance) -> StaticBody3D:
	init_registry()
	var btype := get_type(inst.type_id)
	var body := StaticBody3D.new()
	body.name = "Block_%s" % inst.id

	var visual := btype.create_visual(inst.size)
	if inst.use_color_override:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = inst.color_override
		mat.roughness = btype.roughness
		mat.metallic = btype.metallic
		(visual.mesh as BoxMesh).material = mat
	body.add_child(visual)

	var col := btype.create_collision(inst.size)
	body.add_child(col)

	body.position = Vector3(inst.grid_pos)
	body.set_meta("block_instance", inst)
	return body
