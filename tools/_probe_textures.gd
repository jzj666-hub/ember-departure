extends SceneTree

func _initialize() -> void:
	var g_tex = load("res://assets/scene_objects/glTF/Grass.png") as Texture2D
	var p_tex = load("res://assets/scene_objects/glTF/PathRocks_Diffuse.png") as Texture2D
	var r_tex = load("res://assets/scene_objects/glTF/Rocks_Diffuse.png") as Texture2D
	print("Grass.png size: ", g_tex.get_size() if g_tex else "null")
	print("PathRocks_Diffuse.png size: ", p_tex.get_size() if p_tex else "null")
	print("Rocks_Diffuse.png size: ", r_tex.get_size() if r_tex else "null")
	quit(0)
