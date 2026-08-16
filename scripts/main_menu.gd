extends Control
## Project main menu UI controller for scene navigation.

const ENTRIES := [
	{
		"title": "动作调试 / Animation Debug",
		"blurb": "所有角色并排，同步播同一个动作。检查重定向、身高、骨骼绑定。",
		"scene": "res://scenes/anim_debug.tscn",
	},
	{
		"title": "第三人称试玩 / Third-person Playground",
		"blurb": "操控一个角色走路、侧移、跑步、蹲行。鼠标转向，相机锁在背后。",
		"scene": "res://scenes/playground.tscn",
	},
	{
		"title": "角色手持武器测试 / Handheld Weapon Test",
		"blurb": "测试手持刀具挂载与微调。点击列表装备，滑动条调整握持Transform，LMB进行挥砍。",
		"scene": "res://scenes/weapon_test.tscn",
	},
	{
		"title": "人机操控与寻路测试 / NPC Control & Pathfinding Test",
		"blurb": "第一人称自由飞行搭建：鼠标转视角，准星高亮目标格，左键放置右键拆除，中键指定人机目的地。按 E 寄身操控。寻路按角色真实的跳跃/攀爬能力规划。",
		"scene": "res://scenes/npc_test.tscn",
	},
	{
		"title": "地图编辑器 / Map Editor",
		"blurb": "支持多尺寸方块搭建与材质切换、地图新建/存档/加载，支持玩家录制空中直线特殊跳跃轨迹并与NPC寻路无缝集成。",
		"scene": "res://scenes/map_editor.tscn",
	},
	{
		"title": "追缉 / 1v1 Pursuit Mode",
		"blurb": "1v1 追缉逃生挑战：选择自定义或保存的地图，开局 15 秒逃生时间。追缉者全速追踪，同平台高频刷新，攀爬跳跃落地触发，离追缉者一格以内判定追缉成功！",
		"scene": "res://scenes/chase_mode.tscn",
	},
]


func _ready() -> void:
	# The playground captures the pointer. Coming back here without releasing it
	# would leave a menu that cannot be clicked.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_ui()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.09, 0.10, 0.12)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(460, 0)
	centre.add_child(box)

	var title := Label.new()
	title.text = "灰烬:启程"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "测试场景 / Test scenes"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.modulate = Color(1, 1, 1, 0.6)
	box.add_child(subtitle)

	box.add_child(_spacer(16))

	for entry in ENTRIES:
		box.add_child(_make_entry(entry))

	box.add_child(_spacer(10))

	var quit_button := Button.new()
	quit_button.text = "退出 / Quit"
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit_button)

	var hint := Label.new()
	hint.text = "场景里按 Esc 回到这里"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(1, 1, 1, 0.45)
	box.add_child(hint)


func _make_entry(entry: Dictionary) -> Control:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 2)

	var button := Button.new()
	button.text = entry.title
	button.custom_minimum_size = Vector2(0, 44)
	# A missing scene should say so rather than freezing on a dead button.
	if not ResourceLoader.exists(entry.scene):
		button.disabled = true
		button.text += "   (缺少 %s)" % String(entry.scene).get_file()
	else:
		button.pressed.connect(func() -> void: _open(entry.scene))
	panel.add_child(button)

	var blurb := Label.new()
	blurb.text = entry.blurb
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_font_size_override("font_size", 12)
	blurb.modulate = Color(1, 1, 1, 0.55)
	panel.add_child(blurb)
	return panel


func _open(scene_path: String) -> void:
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("could not open %s (%d)" % [scene_path, err])


func _spacer(height: int) -> Control:
	var node := Control.new()
	node.custom_minimum_size = Vector2(0, height)
	return node
