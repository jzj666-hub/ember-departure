extends Node
## Player profile persistence and avatar manager.
## Supports built-in avatar library scanning, custom local file import, and anti-aliased circular rendering.

const SAVE_PATH := "user://player_profile.json"
const CUSTOM_AVATAR_PATH := "user://custom_avatar.png"
const AVATAR_DIR := "res://assets/avatars/"
const SHADER_PATH := "res://shaders/circle_avatar.gdshader"
const FONT_CHINESE := "res://assets/Fonts/Long_Cang/LongCang-Regular.ttf"
const FONT_GLITCH := "res://assets/Fonts/Long_Cang,Rubik_Glitch/Rubik_Glitch/RubikGlitch-Regular.ttf"

var player_name: String = "灰烬行者"
var avatar_type: String = "builtin" # "builtin" | "custom"
var avatar_key: String = "avatar_01_01.png"

var gold: int = 1000
var ember_vouchers: int = 0

signal currency_changed(new_gold: int, new_vouchers: int)

var available_builtin_avatars: Array[String] = []
var _shader_mat: Shader = null
var font_chinese: Font = null
var font_glitch: Font = null

var _custom_tex_cache: ImageTexture = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_shader_and_fonts()
	_scan_builtin_avatars()
	_load_profile()


func _load_shader_and_fonts() -> void:
	if ResourceLoader.exists(SHADER_PATH):
		_shader_mat = load(SHADER_PATH) as Shader
	if ResourceLoader.exists(FONT_CHINESE):
		font_chinese = load(FONT_CHINESE) as Font
	if ResourceLoader.exists(FONT_GLITCH):
		font_glitch = load(FONT_GLITCH) as Font


func _scan_builtin_avatars() -> void:
	available_builtin_avatars.clear()
	var dir := DirAccess.open(AVATAR_DIR)
	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				var clean_name := file_name.replace(".import", "").replace(".remap", "")
				if clean_name.ends_with(".png") and not available_builtin_avatars.has(clean_name):
					available_builtin_avatars.append(clean_name)
			file_name = dir.get_next()
		dir.list_dir_end()

	# Fallback for exported PCK package where res:// directory listing is omitted
	if available_builtin_avatars.is_empty():
		for group in range(1, 9):
			for idx in range(1, 9):
				var key := "avatar_%02d_%02d.png" % [group, idx]
				available_builtin_avatars.append(key)

	available_builtin_avatars.sort()


func save_profile(new_name: String = "", new_av_type: String = "", new_av_key: String = "") -> void:
	if not new_name.is_empty():
		player_name = new_name.strip_edges()
	if not new_av_type.is_empty():
		avatar_type = new_av_type
	if not new_av_key.is_empty():
		avatar_key = new_av_key

	var data := {
		"name": player_name,
		"avatar_type": avatar_type,
		"avatar_key": avatar_key,
		"gold": gold,
		"ember_vouchers": ember_vouchers
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "  "))
		f.close()


func add_gold(amount: int) -> void:
	gold = maxi(0, gold + amount)
	save_profile()
	currency_changed.emit(gold, ember_vouchers)


func add_ember_vouchers(amount: int) -> void:
	ember_vouchers = maxi(0, ember_vouchers + amount)
	save_profile()
	currency_changed.emit(gold, ember_vouchers)


func exchange_gold_to_vouchers(gold_amount: int, rate: int = 100) -> bool:
	if gold_amount <= 0 or gold < gold_amount or rate <= 0:
		return false
	var vouchers_to_add := int(gold_amount / rate)
	if vouchers_to_add <= 0:
		return false
	var gold_deducted := vouchers_to_add * rate
	gold -= gold_deducted
	ember_vouchers += vouchers_to_add
	save_profile()
	currency_changed.emit(gold, ember_vouchers)
	return true


func _load_profile() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		var default_names := ["疾风行者", "破晓断魂", "影刃行者", "幽火追光", "逆风游侠"]
		player_name = default_names[randi() % default_names.size()]
		if not available_builtin_avatars.is_empty():
			avatar_type = "builtin"
			avatar_key = available_builtin_avatars[randi() % available_builtin_avatars.size()]
		return

	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f != null:
		var json_str := f.get_as_text()
		f.close()
		var parsed = JSON.parse_string(json_str)
		if parsed is Dictionary:
			player_name = str(parsed.get("name", player_name))
			avatar_type = str(parsed.get("avatar_type", "builtin"))
			avatar_key = str(parsed.get("avatar_key", "avatar_01_01.png"))
			gold = int(parsed.get("gold", 1000))
			ember_vouchers = int(parsed.get("ember_vouchers", 0))


func import_custom_avatar_from_path(src_path: String) -> bool:
	if not FileAccess.file_exists(src_path):
		return false

	var img := Image.new()
	var err := img.load(src_path)
	if err != OK:
		return false

	# Resize to 256x256 square
	if img.get_width() != img.get_height():
		var min_edge := mini(img.get_width(), img.get_height())
		var x_off := int(float(img.get_width() - min_edge) * 0.5)
		var y_off := int(float(img.get_height() - min_edge) * 0.5)
		img = img.get_region(Rect2i(x_off, y_off, min_edge, min_edge))
	img.resize(256, 256, Image.INTERPOLATE_LANCZOS)

	var save_err := img.save_png(CUSTOM_AVATAR_PATH)
	if save_err != OK:
		return false

	_custom_tex_cache = ImageTexture.create_from_image(img)
	avatar_type = "custom"
	avatar_key = "custom"
	save_profile(player_name, avatar_type, avatar_key)
	return true


func get_avatar_texture(av_type: String = "", av_key: String = "") -> Texture2D:
	var t_type := avatar_type if av_type.is_empty() else av_type
	var t_key := avatar_key if av_key.is_empty() else av_key

	if t_type == "custom":
		if _custom_tex_cache != null:
			return _custom_tex_cache
		if FileAccess.file_exists(CUSTOM_AVATAR_PATH):
			var img := Image.load_from_file(CUSTOM_AVATAR_PATH)
			if img != null and not img.is_empty():
				_custom_tex_cache = ImageTexture.create_from_image(img)
				return _custom_tex_cache

	# Built-in avatar
	var path := AVATAR_DIR + t_key
	if ResourceLoader.exists(path):
		return load(path) as Texture2D

	if not available_builtin_avatars.is_empty():
		var fallback_path := AVATAR_DIR + available_builtin_avatars[0]
		if ResourceLoader.exists(fallback_path):
			return load(fallback_path) as Texture2D

	if ResourceLoader.exists("res://assets/UI_assets/running-shoe.svg"):
		return load("res://assets/UI_assets/running-shoe.svg") as Texture2D
	return null


func create_avatar_circle(size_px: float, av_type: String = "", av_key: String = "", border_glow: Color = Color(0.25, 0.85, 1.0, 1.0)) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(size_px, size_px)
	root.size = Vector2(size_px, size_px)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tex_rect := TextureRect.new()
	tex_rect.custom_minimum_size = Vector2(size_px, size_px)
	tex_rect.size = Vector2(size_px, size_px)
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tex := get_avatar_texture(av_type, av_key)
	if tex != null:
		tex_rect.texture = tex

	if _shader_mat != null:
		var mat := ShaderMaterial.new()
		mat.shader = _shader_mat
		mat.set_shader_parameter("border_color", border_glow)
		mat.set_shader_parameter("border_width", 0.05)
		tex_rect.material = mat

	root.add_child(tex_rect)
	return root
