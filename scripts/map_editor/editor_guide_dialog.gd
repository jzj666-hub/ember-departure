extends RefCounted
## Static 4-page "special operations" guide book modal for MapEditor.
## Owns: dialog panel, page navigation, per-page content cards.
## Pre: ed assigned before any call; build() before open(). Invariant: page in [0,3].

var ed  # MapEditor host (untyped: breaks preload cycle)

var dialog: PanelContainer
var page := 0
var title_lbl: Label
var page_lbl: Label
var content_box: VBoxContainer
var prev_btn: Button
var next_btn: Button


func _init(host) -> void:
	ed = host


func is_open() -> bool:
	return dialog != null and dialog.visible


## open(p): shows dialog on page p and frees the cursor.
func open(p: int = 0) -> void:
	_render_page(p)
	dialog.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ed._cursor_free = true


## close(): hides dialog and restores panel/cursor mode.
func close() -> void:
	dialog.visible = false
	ed._update_ui_panels_visibility()


## build(): creates dialog chrome and renders page 0. Pre: ed._hud_canvas exists.
func build() -> void:
	dialog = PanelContainer.new()
	dialog.set_anchors_preset(Control.PRESET_CENTER)
	dialog.offset_left = -340
	dialog.offset_right = 340
	dialog.offset_top = -240
	dialog.offset_bottom = 240
	dialog.custom_minimum_size = Vector2(680, 480)
	dialog.visible = false

	var diag_style := StyleBoxFlat.new()
	diag_style.bg_color = Color(0.09, 0.11, 0.15, 0.98)
	diag_style.set_corner_radius_all(12)
	diag_style.set_border_width_all(2)
	diag_style.border_color = Color(0.2, 0.8, 1.0)
	diag_style.set_content_margin_all(20)
	dialog.add_theme_stylebox_override("panel", diag_style)
	ed._hud_canvas.add_child(dialog)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	dialog.add_child(vbox)

	# Header: Title + Page counter + Close button
	var head_hbox := HBoxContainer.new()
	head_hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(head_hbox)

	var icon_tex := TextureRect.new()
	if ResourceLoader.exists("res://assets/UI_assets/cubes.svg"):
		icon_tex.texture = load("res://assets/UI_assets/cubes.svg")
	icon_tex.custom_minimum_size = Vector2(32, 32)
	icon_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_tex.modulate = Color(0.2, 0.85, 1.0)
	head_hbox.add_child(icon_tex)

	title_lbl = Label.new()
	title_lbl.text = "地图工坊 · 特殊操作与录制指南"
	if ed._custom_font != null:
		title_lbl.add_theme_font_override("font", ed._custom_font)
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.modulate = Color(0.2, 0.9, 1.0)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_hbox.add_child(title_lbl)

	page_lbl = Label.new()
	page_lbl.text = "第 1 / 4 页"
	if ed._custom_font != null:
		page_lbl.add_theme_font_override("font", ed._custom_font)
	page_lbl.add_theme_font_size_override("font_size", 16)
	page_lbl.modulate = Color(1.0, 0.85, 0.3)
	head_hbox.add_child(page_lbl)

	var skip_btn := Button.new()
	skip_btn.text = " 关闭 (ESC) "
	if ed._custom_font != null:
		skip_btn.add_theme_font_override("font", ed._custom_font)
	skip_btn.pressed.connect(close)
	head_hbox.add_child(skip_btn)

	# Content Area
	content_box = VBoxContainer.new()
	content_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_box.add_theme_constant_override("separation", 12)
	vbox.add_child(content_box)

	# Bottom Navigation
	var nav_hbox := HBoxContainer.new()
	nav_hbox.add_theme_constant_override("separation", 24)
	nav_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(nav_hbox)

	prev_btn = Button.new()
	prev_btn.text = "← 上一页 (Previous)"
	if ed._custom_font != null:
		prev_btn.add_theme_font_override("font", ed._custom_font)
	prev_btn.add_theme_font_size_override("font_size", 16)
	prev_btn.custom_minimum_size = Vector2(160, 40)
	prev_btn.pressed.connect(func() -> void: _render_page(page - 1))
	nav_hbox.add_child(prev_btn)

	next_btn = Button.new()
	next_btn.text = "下一页 (Next) →"
	if ed._custom_font != null:
		next_btn.add_theme_font_override("font", ed._custom_font)
	next_btn.add_theme_font_size_override("font_size", 16)
	next_btn.custom_minimum_size = Vector2(180, 40)
	next_btn.pressed.connect(func() -> void:
		if page >= 3:
			close()
		else:
			_render_page(page + 1)
	)
	nav_hbox.add_child(next_btn)

	_render_page(0)


func _render_page(p: int) -> void:
	page = clamp(p, 0, 3)
	if page_lbl != null:
		page_lbl.text = "第 %d / 4 页" % (page + 1)
	if prev_btn != null:
		prev_btn.disabled = (page == 0)
	if next_btn != null:
		if page == 3:
			next_btn.text = "开始探索创作 (Start) ✓"
		else:
			next_btn.text = "下一页 (Next) →"

	if content_box == null:
		return

	for child in content_box.get_children():
		child.queue_free()

	match page:
		0:
			_build_page_0()
		1:
			_build_page_1()
		2:
			_build_page_2()
		3:
			_build_page_3()


func _page_heading(txt: String) -> void:
	var sub := Label.new()
	sub.text = txt
	if ed._custom_font != null:
		sub.add_theme_font_override("font", ed._custom_font)
	sub.add_theme_font_size_override("font_size", 18)
	sub.modulate = Color(1.0, 0.85, 0.3)
	content_box.add_child(sub)


func _build_page_0() -> void:
	_page_heading("【一、视角模式与面板一键切换】")
	_add_step(content_box, "B", "按 B 键切换面板与沉浸视角",
		"按 B 键在【属性面板模式（鼠标指针工作，可点击调整尺寸材质与保存）】与【沉浸模式（鼠标隐藏，自由旋转视角飞行与瞄准）】之间随时切换。")
	_add_step(content_box, "TAB", "按 TAB 键切换建造与角色试跑",
		"在【第一人称自由飞行建造】与【第三人称角色试玩】之间一键切换。试跑可实地检验跳跃距离与落点。")
	_add_step(content_box, "W", "自由飞行巡航控制",
		"飞行模式下使用 WASD 水平巡航，Space 空格向上升空，Ctrl / C 向下降落，鼠标滚轮可调节飞行速度。")


func _build_page_1() -> void:
	_page_heading("【二、多尺寸方块与材质快速搭建】")
	_add_step(content_box, "LMB", "鼠标左键 (LMB) 放置方块",
		"准星对准地面或已有方块表面，点击左键放置当前选中的方块。在左侧面板可自由选择 Cube、Slab、Stairs 等类型与 2x1x1、4x1x2 等丰富尺寸。")
	_add_step(content_box, "RMB", "鼠标右键 (RMB) 快速拆除",
		"准星对准任意方块，点击右键即可瞬间拆除整块积木。")
	_add_step(content_box, "SHIFT", "Shift + 左键 实时指定 NPC 寻路测试",
		"准星对准地图任意地面，按住 Shift 点击左键，可指定 NPC 按照其真实物理能力规划路径前往该点。")


func _build_page_2() -> void:
	_page_heading("【三、特殊跳跃 / 极限身法航迹录制】")
	_add_step(content_box, "R", "按 R 键就绪录制特殊跳跃",
		"按 TAB 切换为角色试跑后，在悬崖起跳边缘停下脚步保持静止。按 R 键进入录制准备状态。")
	_add_step(content_box, "SPACE", "助跑起跳与自动航迹截取",
		"顶部横幅提示【🟢 准备就绪，可以起跳】后，向目标高台全力助跑起跳。落地瞬间系统会自动从你起跳前的最后一帧零速度点开始，完整截取空中跳跃航迹！")
	_add_step(content_box, "AI", "NPC (AI) 智能学习复现",
		"录制成功的航迹会化为绿色轨迹线。AI 追缉或寻路时，到达该起跳点会自动无缝复现你的跳跃动作！")


func _build_page_3() -> void:
	_page_heading("【四、轨迹精准删除与地图导出对决】")
	_add_step(content_box, "X", "连按两下 X 快速删除选中轨迹",
		"在建造模式下，将准星对准空中的绿色特殊跳跃轨迹线（轨迹会高亮），连续按两下 X 键即可精准删除该段轨迹记录。")
	_add_step(content_box, "SAVE", "保存地图 (Save Map)",
		"按 B 键呼出顶部工具栏，点击【保存 (Save)】输入地图名称，即可将包含全部方块与特殊跳跃的地图永久保存。")
	_add_step(content_box, "PLAY", "导入追缉模式实战对决",
		"返回主大厅选择【开始追缉逃生 (Pursuit)】，在地图列表中选择你刚才保存的地图，即可在自己打造的专属战场中展开 1v1 极限逃生对决！")


func _add_step(parent: VBoxContainer, key_or_tag: String, title: String, desc: String) -> void:
	var card := PanelContainer.new()
	var c_style := StyleBoxFlat.new()
	c_style.bg_color = Color(0.13, 0.15, 0.20, 0.85)
	c_style.set_corner_radius_all(8)
	c_style.set_border_width_all(1)
	c_style.border_color = Color(0.25, 0.30, 0.40)
	c_style.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", c_style)
	parent.add_child(card)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	card.add_child(hbox)

	var icon_widget := _create_icon(key_or_tag)
	hbox.add_child(icon_widget)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	hbox.add_child(vbox)

	var t_lbl := Label.new()
	t_lbl.text = title
	if ed._custom_font != null:
		t_lbl.add_theme_font_override("font", ed._custom_font)
	t_lbl.add_theme_font_size_override("font_size", 16)
	t_lbl.modulate = Color(0.35, 0.9, 1.0)
	vbox.add_child(t_lbl)

	var d_lbl := Label.new()
	d_lbl.text = desc
	d_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if ed._custom_font != null:
		d_lbl.add_theme_font_override("font", ed._custom_font)
	d_lbl.add_theme_font_size_override("font_size", 13)
	d_lbl.modulate = Color(0.85, 0.88, 0.92, 0.9)
	vbox.add_child(d_lbl)


## _create_icon(tag): png keycap if present under assets/buttons_pattern, else drawn badge.
func _create_icon(key_tag: String) -> Control:
	var png_path := "res://assets/buttons_pattern/%s.png" % key_tag
	if ResourceLoader.exists(png_path):
		var tex := TextureRect.new()
		tex.texture = load(png_path)
		tex.custom_minimum_size = Vector2(36, 36)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return tex

	var badge := PanelContainer.new()
	var b_style := StyleBoxFlat.new()
	b_style.bg_color = Color(0.20, 0.24, 0.32, 0.95)
	b_style.set_corner_radius_all(6)
	b_style.set_border_width_all(1)
	b_style.border_color = Color(0.4, 0.6, 0.8)
	b_style.set_content_margin_all(6)
	badge.add_theme_stylebox_override("panel", b_style)
	badge.custom_minimum_size = Vector2(40, 36)

	var lbl := Label.new()
	lbl.text = key_tag
	if ed._custom_font != null:
		lbl.add_theme_font_override("font", ed._custom_font)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.modulate = Color(1.0, 0.88, 0.35)
	badge.add_child(lbl)
	return badge
