class_name SettingsDialog
extends PanelContainer
## Visual, performance, atmosphere, and gameplay configuration UI dialog.
## Modally binds to GameSettings for real-time adjustments and disk persistence.

signal closed

const GameSettingsScript = preload("res://scripts/game_settings.gd")
const FONT_PATH := "res://assets/Fonts/Long_Cang/LongCang-Regular.ttf"

var _custom_font: Font = null
var _settings_mgr: GameSettings = null

# UI Controls
var _fps_opt: OptionButton = null
var _vsync_chk: CheckButton = null
var _scale_slider: HSlider = null
var _scale_label: Label = null

var _sky_dynamic_chk: CheckButton = null
var _cloud_speed_slider: HSlider = null
var _cloud_speed_label: Label = null
var _glow_chk: CheckButton = null
var _ssao_chk: CheckButton = null
var _fog_chk: CheckButton = null

var _filter_opt: OptionButton = null
var _custom_tex_chk: CheckButton = null
var _vfx_quality_opt: OptionButton = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(720, 620)
	if ResourceLoader.exists(FONT_PATH):
		_custom_font = load(FONT_PATH) as Font
	_settings_mgr = GameSettingsScript.get_instance()
	_build_panel()
	_refresh_ui_from_settings()


func _ready() -> void:
	_refresh_ui_from_settings()


func _build_panel() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.13, 0.96)
	style.set_corner_radius_all(14)
	style.set_border_width_all(2)
	style.border_color = Color(0.85, 0.58, 0.20, 0.95)
	style.set_content_margin_all(20)
	add_theme_stylebox_override("panel", style)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 14)
	add_child(main_vbox)

	# Title Bar
	var title_box := HBoxContainer.new()
	var title_lbl := Label.new()
	title_lbl.text = "⚙️ 画质与系统设置 (Game & Graphics Settings)"
	if _custom_font != null:
		title_lbl.add_theme_font_override("font", _custom_font)
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.modulate = Color(1.0, 0.85, 0.35)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.text = " ✕ "
	close_btn.pressed.connect(_on_close_pressed)
	title_box.add_child(close_btn)
	main_vbox.add_child(title_box)

	# Scrollable content area
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll)

	var content_vbox := VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.add_theme_constant_override("separation", 16)
	scroll.add_child(content_vbox)

	# --- Section 1: 性能与流畅度 (Performance) ---
	content_vbox.add_child(_create_section_header("🚀 性能与流畅度 (Performance)"))
	var perf_box := _create_card_container(content_vbox)

	# FPS Limit
	_fps_opt = OptionButton.new()
	_fps_opt.add_item("30 FPS", 0)
	_fps_opt.add_item("60 FPS (推荐)", 1)
	_fps_opt.add_item("120 FPS", 2)
	_fps_opt.add_item("144 FPS", 3)
	_fps_opt.add_item("不限制 (Unlimited)", 4)
	if _custom_font != null:
		_fps_opt.add_theme_font_override("font", _custom_font)
	_fps_opt.item_selected.connect(_on_fps_selected)
	perf_box.add_child(_create_row("帧率上限 (FPS Limit):", _fps_opt, "限制最高渲染帧率以降低发热与功耗"))

	# VSync
	_vsync_chk = CheckButton.new()
	_vsync_chk.toggled.connect(func(v: bool): _settings_mgr.set_setting("vsync", v))
	perf_box.add_child(_create_row("垂直同步 (VSync):", _vsync_chk, "消除画面撕裂，稳定帧输出间隔"))

	# 3D Resolution Scale
	var scale_row := HBoxContainer.new()
	_scale_slider = HSlider.new()
	_scale_slider.min_value = 0.5
	_scale_slider.max_value = 1.5
	_scale_slider.step = 0.05
	_scale_slider.value = 1.0
	_scale_slider.custom_minimum_size = Vector2(160, 24)
	_scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scale_label = Label.new()
	_scale_label.text = "100%"
	_scale_label.custom_minimum_size = Vector2(50, 0)
	if _custom_font != null:
		_scale_label.add_theme_font_override("font", _custom_font)
	_scale_slider.value_changed.connect(_on_scale_changed)
	scale_row.add_child(_scale_slider)
	scale_row.add_child(_scale_label)
	perf_box.add_child(_create_row("3D 渲染缩放 (Render Scale):", scale_row, "低配设备调低至 70%~80% 可大幅提高游戏流畅度"))

	# --- Section 2: 天空与环境 (Atmosphere & Sky) ---
	content_vbox.add_child(_create_section_header("🌄 天空与大气环境 (Atmosphere & Sky)"))
	var sky_box := _create_card_container(content_vbox)

	# Dynamic sky
	_sky_dynamic_chk = CheckButton.new()
	_sky_dynamic_chk.toggled.connect(func(v: bool): _settings_mgr.set_setting("dynamic_sky", v))
	sky_box.add_child(_create_row("动态天空与云流 (Dynamic Sky):", _sky_dynamic_chk, "开启着色器驱动的无太阳动态云层流动"))

	# Cloud speed
	var speed_row := HBoxContainer.new()
	_cloud_speed_slider = HSlider.new()
	_cloud_speed_slider.min_value = 0.0
	_cloud_speed_slider.max_value = 3.0
	_cloud_speed_slider.step = 0.1
	_cloud_speed_slider.value = 1.0
	_cloud_speed_slider.custom_minimum_size = Vector2(160, 24)
	_cloud_speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cloud_speed_label = Label.new()
	_cloud_speed_label.text = "1.0x"
	_cloud_speed_label.custom_minimum_size = Vector2(50, 0)
	if _custom_font != null:
		_cloud_speed_label.add_theme_font_override("font", _custom_font)
	_cloud_speed_slider.value_changed.connect(_on_cloud_speed_changed)
	speed_row.add_child(_cloud_speed_slider)
	speed_row.add_child(_cloud_speed_label)
	sky_box.add_child(_create_row("云层漂移速度 (Cloud Speed):", speed_row, "调节天空云层随风飘动的速度"))

	# Glow
	_glow_chk = CheckButton.new()
	_glow_chk.toggled.connect(func(v: bool): _settings_mgr.set_setting("glow_enabled", v))
	sky_box.add_child(_create_row("辉光特效 (Bloom & Glow):", _glow_chk, "技能与发光方块的光晕泛光效果"))

	# SSAO
	_ssao_chk = CheckButton.new()
	_ssao_chk.toggled.connect(func(v: bool): _settings_mgr.set_setting("ssao_enabled", v))
	sky_box.add_child(_create_row("环境光遮蔽 (SSAO):", _ssao_chk, "增强方块边角和物体接触阴影立体感 (消耗 GPU)"))

	# Fog
	_fog_chk = CheckButton.new()
	_fog_chk.toggled.connect(func(v: bool): _settings_mgr.set_setting("fog_enabled", v))
	sky_box.add_child(_create_row("场景雾气 (Atmospheric Fog):", _fog_chk, "远处环境虚化与景深氛围雾效"))

	# --- Section 3: 材质与特效 (Blocks & VFX) ---
	content_vbox.add_child(_create_section_header("🧱 材质纹理与技能特效 (Materials & VFX)"))
	var mat_box := _create_card_container(content_vbox)

	# Texture filter
	_filter_opt = OptionButton.new()
	_filter_opt.add_item("近邻过滤 (Nearest / 像素风)", 0)
	_filter_opt.add_item("三线性平滑 (Linear / 柔和)", 1)
	_filter_opt.add_item("各向异性极清 (Anisotropic)", 2)
	if _custom_font != null:
		_filter_opt.add_theme_font_override("font", _custom_font)
	_filter_opt.item_selected.connect(_on_filter_selected)
	mat_box.add_child(_create_row("方块纹理过滤 (Texture Filter):", _filter_opt, "方块材质贴图的采样清晰度与过滤方式"))

	# Custom textures
	_custom_tex_chk = CheckButton.new()
	_custom_tex_chk.toggled.connect(func(v: bool): _settings_mgr.set_setting("custom_textures_enabled", v))
	mat_box.add_child(_create_row("启用自定义纹理导入 (Custom Textures):", _custom_tex_chk, "允许从本地导入外部图片生成方块材质"))

	# VFX quality
	_vfx_quality_opt = OptionButton.new()
	_vfx_quality_opt.add_item("流畅 (Low - 30% 粒子)", 0)
	_vfx_quality_opt.add_item("标准 (Medium - 70% 粒子)", 1)
	_vfx_quality_opt.add_item("华丽 (High - 100% 全粒子)", 2)
	if _custom_font != null:
		_vfx_quality_opt.add_theme_font_override("font", _custom_font)
	_vfx_quality_opt.item_selected.connect(_on_vfx_quality_selected)
	mat_box.add_child(_create_row("技能特效品质 (VFX Quality):", _vfx_quality_opt, "调整技能粒子发射密度与着色器复杂度"))

	# Bottom Action Bar
	var bottom_bar := HBoxContainer.new()
	bottom_bar.add_theme_constant_override("separation", 16)
	bottom_bar.alignment = BoxContainer.ALIGNMENT_END

	var reset_btn := Button.new()
	reset_btn.text = " 🔄 恢复默认设置 "
	if _custom_font != null:
		reset_btn.add_theme_font_override("font", _custom_font)
	reset_btn.pressed.connect(_on_reset_pressed)
	bottom_bar.add_child(reset_btn)

	var apply_btn := Button.new()
	apply_btn.text = " 💾 保存并应用 "
	if _custom_font != null:
		apply_btn.add_theme_font_override("font", _custom_font)
	apply_btn.pressed.connect(_on_apply_pressed)
	bottom_bar.add_child(apply_btn)

	var close_bottom_btn := Button.new()
	close_bottom_btn.text = " ✕ 关闭 "
	if _custom_font != null:
		close_bottom_btn.add_theme_font_override("font", _custom_font)
	close_bottom_btn.pressed.connect(_on_close_pressed)
	bottom_bar.add_child(close_bottom_btn)

	main_vbox.add_child(bottom_bar)


func _create_section_header(title: String) -> Label:
	var lbl := Label.new()
	lbl.text = title
	if _custom_font != null:
		lbl.add_theme_font_override("font", _custom_font)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.modulate = Color(0.9, 0.75, 0.45)
	return lbl


func _create_card_container(parent_vbox: VBoxContainer) -> VBoxContainer:
	var bg_panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.15, 0.20, 0.75)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	bg_panel.add_theme_stylebox_override("panel", style)
	bg_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent_vbox.add_child(bg_panel)

	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 10)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg_panel.add_child(container)
	return container


func _create_row(label_text: String, control: Control, tooltip: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(250, 0)
	if _custom_font != null:
		lbl.add_theme_font_override("font", _custom_font)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.modulate = Color(0.9, 0.92, 0.96)
	if tooltip != "":
		lbl.tooltip_text = tooltip
		control.tooltip_text = tooltip
	row.add_child(lbl)
	
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _refresh_ui_from_settings() -> void:
	if _settings_mgr == null:
		return

	# FPS Limit
	var fps: int = int(_settings_mgr.get_setting("fps_limit", 60))
	match fps:
		30: _fps_opt.selected = 0
		60: _fps_opt.selected = 1
		120: _fps_opt.selected = 2
		144: _fps_opt.selected = 3
		0: _fps_opt.selected = 4
		_: _fps_opt.selected = 1

	# VSync
	_vsync_chk.button_pressed = bool(_settings_mgr.get_setting("vsync", true))

	# Render Scale
	var scale_val: float = float(_settings_mgr.get_setting("render_scale", 1.0))
	_scale_slider.value = scale_val
	_scale_label.text = "%d%%" % int(scale_val * 100.0)

	# Dynamic Sky
	_sky_dynamic_chk.button_pressed = bool(_settings_mgr.get_setting("dynamic_sky", true))

	# Cloud speed
	var speed_val: float = float(_settings_mgr.get_setting("cloud_speed", 1.0))
	_cloud_speed_slider.value = speed_val
	_cloud_speed_label.text = "%.1fx" % speed_val

	# Post processing
	_glow_chk.button_pressed = bool(_settings_mgr.get_setting("glow_enabled", true))
	_ssao_chk.button_pressed = bool(_settings_mgr.get_setting("ssao_enabled", false))
	_fog_chk.button_pressed = bool(_settings_mgr.get_setting("fog_enabled", false))

	# Texture filtering
	var filter_str: String = str(_settings_mgr.get_setting("texture_filtering", "linear"))
	match filter_str:
		"nearest": _filter_opt.selected = 0
		"linear": _filter_opt.selected = 1
		"anisotropic": _filter_opt.selected = 2
		_: _filter_opt.selected = 1

	# Custom textures
	_custom_tex_chk.button_pressed = bool(_settings_mgr.get_setting("custom_textures_enabled", true))

	# VFX Quality
	var vfx_str: String = str(_settings_mgr.get_setting("vfx_quality", "high"))
	match vfx_str:
		"low": _vfx_quality_opt.selected = 0
		"medium": _vfx_quality_opt.selected = 1
		"high": _vfx_quality_opt.selected = 2
		_: _vfx_quality_opt.selected = 2


func _on_fps_selected(index: int) -> void:
	var map: Array[int] = [30, 60, 120, 144, 0]
	if index >= 0 and index < map.size():
		_settings_mgr.set_setting("fps_limit", map[index])


func _on_scale_changed(val: float) -> void:
	_scale_label.text = "%d%%" % int(val * 100.0)
	_settings_mgr.set_setting("render_scale", val)


func _on_cloud_speed_changed(val: float) -> void:
	_cloud_speed_label.text = "%.1fx" % val
	_settings_mgr.set_setting("cloud_speed", val)


func _on_filter_selected(index: int) -> void:
	var map: Array[String] = ["nearest", "linear", "anisotropic"]
	if index >= 0 and index < map.size():
		_settings_mgr.set_setting("texture_filtering", map[index])


func _on_vfx_quality_selected(index: int) -> void:
	var map: Array[String] = ["low", "medium", "high"]
	if index >= 0 and index < map.size():
		_settings_mgr.set_setting("vfx_quality", map[index])


func _on_reset_pressed() -> void:
	_settings_mgr.reset_to_defaults()
	_refresh_ui_from_settings()


func _on_apply_pressed() -> void:
	_settings_mgr.save_to_disk()
	_settings_mgr.apply_settings()


func _on_close_pressed() -> void:
	closed.emit()
	queue_free()
