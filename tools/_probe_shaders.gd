extends SceneTree

func _initialize() -> void:
	var shader = load("res://shaders/manor_terrain.gdshader") as Shader
	print("Terrain shader loaded: ", shader != null)
	var grass_shader = load("res://shaders/grass_wind.gdshader") as Shader
	print("Grass wind shader loaded: ", grass_shader != null)
	var grass_tex = load("res://assets/scene_objects/glTF/Grass.png") as Texture2D
	print("Grass texture loaded: ", grass_tex != null)
	var flower_tex = load("res://assets/scene_objects/glTF/Flowers.png") as Texture2D
	print("Flower texture loaded: ", flower_tex != null)
	quit(0)
