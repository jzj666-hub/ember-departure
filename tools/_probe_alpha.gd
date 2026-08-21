extends SceneTree

func _initialize() -> void:
	var img = Image.load_from_file("res://assets/scene_objects/glTF/Grass.png")
	if img != null:
		print("Grass.png format: ", img.get_format(), " size: ", img.get_size(), " has alpha: ", img.detect_alpha())
	var fl_img = Image.load_from_file("res://assets/scene_objects/glTF/Flowers.png")
	if fl_img != null:
		print("Flowers.png format: ", fl_img.get_format(), " size: ", fl_img.get_size(), " has alpha: ", fl_img.detect_alpha())
	quit(0)
