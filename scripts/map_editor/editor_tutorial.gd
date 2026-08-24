extends RefCounted
## Interactive 8-step onboarding quest for MapEditor.
## Owns: top banner, completion dialog, floating 3D arrow, tutorial platform spawn.
## Pre: ed assigned before any call. Invariant: active==false => all notify_* hooks are no-ops.

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const SpecialPathRecorderScript = preload("res://scripts/special_path_recorder.gd")

## Mirrors MapEditor.EditorMode ordinals. Duplicated to avoid a preload cycle.
const MODE_BUILD := 0
const MODE_PLAY_TEST := 1
const MODE_RECORD := 2

var ed  # MapEditor host (untyped: breaks preload cycle)

var active := false
var step := 0

var banner: PanelContainer
var banner_style: StyleBoxFlat
var banner_icon: TextureRect
var banner_title: Label
var banner_sub: Label
var complete_dialog: PanelContainer

var arrow: Node3D = null
var arrow_base_pos: Vector3 = Vector3.ZERO
var arrow_time: float = 0.0


func _init(host) -> void:
	ed = host


# --- Construction -----------------------------------------------------------

## build_hud(): creates banner + completion dialog. Pre: ed._hud_canvas exists.
func build_hud() -> void:
	banner = PanelContainer.new()
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.offset_left = -340
	banner.offset_right = 340
	banner.offset_top = 58
	banner.offset_bottom = 150
	banner.custom_minimum_size = Vector2(680, 92)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.visible = false

	banner_style = StyleBoxFlat.new()
	banner_style.bg_color = Color(0.09, 0.12, 0.17, 0.96)
	banner_style.set_corner_radius_all(10)
	banner_style.set_border_width_all(2)
	banner_style.border_color = Color(1.0, 0.85, 0.25)
	banner_style.set_content_margin_all(12)
	banner.add_theme_stylebox_override("panel", banner_style)
	ed._hud_canvas.add_child(banner)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 14)
	banner.add_child(hbox)

	banner_icon = TextureRect.new()
	if ResourceLoader.exists("res://assets/UI_assets/cubes.svg"):
		banner_icon.texture = load("res://assets/UI_assets/cubes.svg")
	banner_icon.custom_minimum_size = Vector2(46, 46)
	banner_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	banner_icon.modulate = Color(1.0, 0.85, 0.25)
	hbox.add_child(banner_icon)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(vbox)

	banner_title = Label.new()
	if ed._custom_font != null:
		banner_title.add_theme_font_override("font", ed._custom_font)
	banner_title.add_theme_font_size_override("font_size", 20)
	banner_title.modulate = Color(1.0, 0.88, 0.3)
	vbox.add_child(banner_title)

	banner_sub = Label.new()
	banner_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if ed._custom_font != null:
		banner_sub.add_theme_font_override("font", ed._custom_font)
	banner_sub.add_theme_font_size_override("font_size", 14)
	banner_sub.modulate = Color(0.9, 0.92, 0.96)
	vbox.add_child(banner_sub)

	_build_complete_dialog()


func _build_complete_dialog() -> void:
	complete_dialog = PanelContainer.new()
	complete_dialog.set_anchors_preset(Control.PRESET_CENTER)
	complete_dialog.offset_left = -290
	complete_dialog.offset_right = 290
	complete_dialog.offset_top = -180
	complete_dialog.offset_bottom = 180
	complete_dialog.custom_minimum_size = Vector2(580, 360)
	complete_dialog.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.16, 0.98)
	style.set_corner_radius_all(12)
	style.set_border_width_all(2)
	style.border_color = Color(0.3, 0.9, 0.6)
	style.set_content_margin_all(22)
	complete_dialog.add_theme_stylebox_override("panel", style)
	ed._hud_canvas.add_child(complete_dialog)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	complete_dialog.add_child(vbox)

	var icon := TextureRect.new()
	if ResourceLoader.exists("res://assets/UI_assets/freedom-dove.svg"):
		icon.texture = load("res://assets/UI_assets/freedom-dove.svg")
	icon.custom_minimum_size = Vector2(56, 56)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Color(0.3, 0.9, 0.6)
	vbox.add_child(icon)

	var title := Label.new()
	title.text = "🎉 恭喜！新手互动教学圆满完成！"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ed._custom_font != null:
		title.add_theme_font_override("font", ed._custom_font)
	title.add_theme_font_size_override("font_size", 24)
	title.modulate = Color(0.3, 0.9, 0.6)
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = "您已成功掌握方块搭建、物理寻路测试、极限跳跃示范录制与轨迹管理！\n\n💡 进阶揭秘：其实人机本身是可以从断点跳过去的，甚至有更强的高阶跳跃处理机制，请敬请期待这些 NPC 战士的惊艳表现吧！\n\n随时按【B 键】可在【属性面板（鼠标指针）】与【沉浸自由视角】之间一键切换；快去打造您的专属对决战场吧！"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if ed._custom_font != null:
		desc.add_theme_font_override("font", ed._custom_font)
	desc.add_theme_font_size_override("font_size", 14)
	desc.modulate = Color(0.88, 0.92, 0.96)
	vbox.add_child(desc)

	var finish_btn := Button.new()
	finish_btn.text = "开始自由探索创作 (Start)"
	if ed._custom_font != null:
		finish_btn.add_theme_font_override("font", ed._custom_font)
	finish_btn.add_theme_font_size_override("font_size", 16)
	finish_btn.custom_minimum_size = Vector2(220, 42)
	finish_btn.pressed.connect(func() -> void:
		complete_dialog.visible = false
		active = false
		banner.visible = false
		ed._update_ui_panels_visibility()
	)
	vbox.add_child(finish_btn)


# --- Lifecycle --------------------------------------------------------------

## start(): enters immersive mode and arms step 0. Post: active==true, step==0.
func start() -> void:
	active = true
	ed._ui_panels_visible = false
	ed._update_ui_panels_visibility()
	ed._set_mode(MODE_BUILD)
	advance(0)


## advance(s): sets step and repaints banner. Pre: build_hud() ran or banner==null (no-op).
func advance(s: int) -> void:
	step = s
	if banner == null:
		return
	banner.visible = true

	match s:
		0:
			if ResourceLoader.exists("res://assets/UI_assets/cubes.svg"):
				banner_icon.texture = load("res://assets/UI_assets/cubes.svg")
				banner_icon.modulate = Color(0.3, 0.85, 1.0)
			banner_title.text = "🎯 新手任务 (1/8): 放置方块"
			banner_sub.text = "准星对准地面任意网格，点击【鼠标左键 (LMB)】放置一个方块。"
			banner_style.border_color = Color(0.3, 0.85, 1.0)
			ed._set_status("【任务 1/8】点击鼠标左键放置方块")

		1:
			if ResourceLoader.exists("res://assets/UI_assets/cross-mark.svg"):
				banner_icon.texture = load("res://assets/UI_assets/cross-mark.svg")
				banner_icon.modulate = Color(1.0, 0.4, 0.4)
			banner_title.text = "🎯 新手任务 (2/8): 拆除方块"
			banner_sub.text = "太棒了！现在准星对准带有金箭头的方块，点击【鼠标右键 (RMB)】将其拆除。"
			banner_style.border_color = Color(1.0, 0.4, 0.4)
			ed._set_status("【任务 2/8】准星对准方块点击鼠标右键拆除")

		2:
			if ResourceLoader.exists("res://assets/UI_assets/run.svg"):
				banner_icon.texture = load("res://assets/UI_assets/run.svg")
				banner_icon.modulate = Color(0.3, 0.9, 0.6)
			banner_title.text = "🎯 新手任务 (3/8): 人机智能寻路"
			banner_sub.text = "人机拥有强大的物理能力寻路！按住【Shift + 鼠标左键】点击地面较远处，指挥 NPC 走过去。"
			banner_style.border_color = Color(0.3, 0.9, 0.6)
			ed._set_status("【任务 3/8】按住 Shift 点击左键测试 NPC 寻路")

		3:
			_spawn_glowing_platforms()
			if ResourceLoader.exists("res://assets/UI_assets/cctv-camera.svg"):
				banner_icon.texture = load("res://assets/UI_assets/cctv-camera.svg")
				banner_icon.modulate = Color(1.0, 0.85, 0.25)
			banner_title.text = "🎯 新手任务 (4/8): 切换自身操控"
			banner_sub.text = "场景中央已生成两座测试跳台！按【TAB 键】切换为自己操控角色，并站到起点方块上方。"
			banner_style.border_color = Color(1.0, 0.85, 0.25)
			ed._set_status("【任务 4/8】按 TAB 键切换为自身操控")

		4:
			if ResourceLoader.exists("res://assets/UI_assets/digital-trace.svg"):
				banner_icon.texture = load("res://assets/UI_assets/digital-trace.svg")
				banner_icon.modulate = Color(0.2, 0.85, 1.0)
			banner_title.text = "🎯 新手任务 (5/8): 录制极限跳跃轨迹"
			banner_sub.text = "人机原本无法判断断台可达。按【R 键】就绪，然后助跑跳到对面跳台！系统将自动捕获你的跳跃轨迹，作为人机新的可行路径！"
			banner_style.border_color = Color(0.2, 0.85, 1.0)
			ed._set_status("【任务 5/8】按 R 键就绪，全力助跑起跳跨越断台，让人机学习新路径")

		5:
			if ResourceLoader.exists("res://assets/UI_assets/claw-slashes.svg"):
				banner_icon.texture = load("res://assets/UI_assets/claw-slashes.svg")
				banner_icon.modulate = Color(1.0, 0.88, 0.3)
			banner_title.text = "🎯 新手任务 (6/8): 见证 AI 学习并复现跳跃"
			banner_sub.text = "录制成功！角色已重置回起点。按【TAB 键】回到自由建造，按住【Shift + 左键】点击对面跳台，见证 NPC 完美复现你的跳跃！"
			banner_style.border_color = Color(1.0, 0.88, 0.3)
			ed._set_status("【任务 6/8】角色已回起点，按 TAB 建造模式并 Shift+左键 命令 NPC 跨越跳跃")

		6:
			if ResourceLoader.exists("res://assets/UI_assets/cross-mark.svg"):
				banner_icon.texture = load("res://assets/UI_assets/cross-mark.svg")
				banner_icon.modulate = Color(1.0, 0.45, 0.3)
			banner_title.text = "🎯 新手任务 (7/8): 精准删除特殊跳跃轨迹"
			banner_sub.text = "学会录制也要学会清理！将准星对准空中刚才录制的绿色轨迹线条，【连续按两下 X 键】将其精准删除。"
			banner_style.border_color = Color(1.0, 0.45, 0.3)
			ed._set_status("【任务 7/8】准星对准绿色轨迹线条，连续按两次 X 键精准删除")

		7:
			banner.visible = false
			complete_dialog.visible = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			ed._cursor_free = true
			AudioManagerScript.play_voice_file("res://assets/voice/Voiceover Pack/Male/mission_completed.ogg", 2.0)
			ed._set_status("恭喜！您已圆满完成地图工坊新手互动教学！")


## dismiss_complete_dialog(): ESC handler. Post: returns true iff dialog was open and got closed.
func dismiss_complete_dialog() -> bool:
	if complete_dialog == null or not complete_dialog.visible:
		return false
	complete_dialog.visible = false
	active = false
	if banner != null:
		banner.visible = false
	ed._update_ui_panels_visibility()
	return true


func _spawn_glowing_platforms() -> void:
	ed._clear_all_blocks()
	ed._nav.clear_special_paths()

	# Platform 1
	var inst1 := BlockRegistry.BlockInstance.new()
	inst1.id = "tut_plat_1"
	inst1.type_id = "cube"
	inst1.grid_pos = Vector3i(0, 1, 0)
	inst1.size = Vector3i(2, 1, 2)
	var body1 := BlockRegistry.create_body(inst1)
	inst1.body_node = body1
	ed.add_child(body1)
	ed._blocks[inst1.id] = inst1
	for c in inst1.get_occupied_cells():
		ed._cell_to_block_id[c] = inst1.id
		ed._nav.set_block(c, true)

	# Platform 2 (Across gap of 2 blocks, separated at z = 4)
	var inst2 := BlockRegistry.BlockInstance.new()
	inst2.id = "tut_plat_2"
	inst2.type_id = "cube"
	inst2.grid_pos = Vector3i(0, 1, 4)
	inst2.size = Vector3i(2, 1, 2)
	var body2 := BlockRegistry.create_body(inst2)
	inst2.body_node = body2
	ed.add_child(body2)
	ed._blocks[inst2.id] = inst2
	for c in inst2.get_occupied_cells():
		ed._cell_to_block_id[c] = inst2.id
		ed._nav.set_block(c, true)

	ed._nav.rebuild()
	ed._nav.set_capability(ed._npc)

	# Position NPC on Platform 1
	ed._npc.global_position = Vector3(1.0, 1.2, 1.0)
	ed._npc.velocity = Vector3.ZERO
	ed._builder_camera.global_position = Vector3(1.0, 3.5, -3.5)
	ed._cam_pitch = -0.35
	ed._cam_yaw = 0.0
	ed._apply_builder_orientation()


# --- Floating arrow ---------------------------------------------------------

## build_arrow(): idempotent. Post: arrow attached to ed, hidden.
func build_arrow() -> void:
	if arrow != null:
		return
	arrow = Node3D.new()
	arrow.name = "TutorialFloatingArrow"
	arrow.visible = false

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.2)
	mat.emission_energy_multiplier = 2.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

	# Arrow Head (Downward Cone)
	var head_mesh := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.35
	cone.bottom_radius = 0.0
	cone.height = 0.55
	cone.material = mat
	head_mesh.mesh = cone
	head_mesh.position.y = 0.28
	arrow.add_child(head_mesh)

	# Arrow Shaft (Cylinder)
	var shaft_mesh := MeshInstance3D.new()
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.12
	shaft.bottom_radius = 0.12
	shaft.height = 0.45
	shaft.material = mat
	shaft_mesh.mesh = shaft
	shaft_mesh.position.y = 0.75
	arrow.add_child(shaft_mesh)

	ed.add_child(arrow)


func show_arrow_at(world_pos: Vector3) -> void:
	if arrow == null:
		build_arrow()
	arrow_base_pos = world_pos
	arrow_time = 0.0
	arrow.position = world_pos + Vector3(0, 0.45, 0)
	arrow.visible = true


func hide_arrow() -> void:
	if arrow != null:
		arrow.visible = false


## process_arrow(delta): bob + spin. Call from MapEditor._process.
func process_arrow(delta: float) -> void:
	if arrow == null or not arrow.visible:
		return
	arrow_time += delta
	arrow.position = arrow_base_pos + Vector3(0.0, 0.45 + sin(arrow_time * 5.0) * 0.15, 0.0)
	arrow.rotation.y += delta * 2.5


# --- Editor notification hooks (all no-op when inactive) ---------------------

## block_place_locked(): step 1 forbids new blocks. Post: returns true => caller must abort placement.
func block_place_locked() -> bool:
	if active and step == 1:
		ed._set_status("【任务 2/6】请先拆除上方浮动箭头指示的方块，暂不可放置新方块哦")
		return true
	return false


func on_block_placed(grid_pos: Vector3i, block_size: Vector3i) -> void:
	if not active or step != 0:
		return
	var center_pos := Vector3(
		float(grid_pos.x) + float(block_size.x) * 0.5,
		float(grid_pos.y) + float(block_size.y),
		float(grid_pos.z) + float(block_size.z) * 0.5
	)
	show_arrow_at(center_pos)
	advance(1)


func on_block_removed() -> void:
	if not active or step != 1:
		return
	hide_arrow()
	advance(2)


func on_mode_play_test() -> void:
	if active and step == 3:
		advance(4)


func on_mode_record() -> void:
	if not active or step != 4:
		return
	if banner != null:
		banner_icon.modulate = Color(1.0, 0.35, 0.35)
		banner_title.text = "🎯 新手任务 (5/8): 🔴 正在录制！助跑起跳！"
		banner_sub.text = "已响应【R 键】！动作捕获就绪：请全力助跑起跳跨越断台，录制空中飞跃轨迹！"
		banner_style.border_color = Color(1.0, 0.35, 0.35)
	ed._set_status("🔴【R 键已响应】录制就绪！请立即向对面跳台助跑起跳！")


## on_path_recorded(): step 4 -> 5, resets character to Platform 1.
func on_path_recorded() -> void:
	if not active or step != 4:
		return
	ed._npc.global_position = Vector3(1.0, 1.2, 1.0)
	ed._npc.velocity = Vector3.ZERO
	ed._follow_camera.snap()
	advance(5)


func on_path_record_failed() -> void:
	if active and step == 4:
		advance(4)


func on_recorder_state(state: int) -> void:
	if not active or step != 4 or banner == null:
		return
	match state:
		SpecialPathRecorderScript.State.ARMED_WAITING_FOR_REST:
			banner_sub.text = "已响应【R 键】！就绪状态：请原地起跑并助跑跳向对面跳台！"
		SpecialPathRecorderScript.State.GROUND_RECORDING:
			banner_sub.text = "🏃 检测到助跑加速！请全力向前起跳！"
		SpecialPathRecorderScript.State.AIRBORNE_RECORDING:
			banner_sub.text = "🚀 腾空检测中！正在逐帧捕获空中抛物线轨迹..."
		SpecialPathRecorderScript.State.COMPLETED:
			banner_sub.text = "🎯 成功着陆！正在提取跳跃轨迹并生成路径..."


## on_path_planned(): banner copy while player observes NPC pathing (steps 2 and 5).
func on_path_planned() -> void:
	if not active or banner == null:
		return
	if step == 2:
		banner_title.text = "🎯 新手任务 (3/8): 正在寻路..."
		banner_sub.text = "👀 人机已启动智能寻路规划，请静静观察其移动路线与落点！"
	elif step == 5:
		banner_title.text = "🎯 新手任务 (6/8): 见证飞跃..."
		banner_sub.text = "👀 观察 NPC 正在起跑并复刻你的跳跃航迹飞跃断台！"


func on_special_path_deleted() -> void:
	if active and step == 6:
		advance(7)


## on_npc_arrived(target): steps 2 and 5 hold 2s then advance. Coroutine.
func on_npc_arrived(_target: Vector3) -> void:
	if not active:
		return
	if step == 2:
		if banner != null:
			banner_icon.modulate = Color(0.3, 0.9, 0.6)
			banner_title.text = "🎯 新手任务 (3/8): 寻路抵达！"
			banner_sub.text = "✅ 人机已按物理规划成功抵达目标点！停留 2 秒即将进入下一阶段..."
		await ed.get_tree().create_timer(2.0).timeout
		if active and step == 2:
			advance(3)
	elif step == 5:
		if banner != null:
			banner_icon.modulate = Color(0.3, 0.9, 0.6)
			banner_title.text = "🎯 新手任务 (6/8): 飞跃完成！"
			banner_sub.text = "✅ 人机已完美复刻跳跃并成功着陆！停留 2 秒进入下一阶段..."
		await ed.get_tree().create_timer(2.0).timeout
		if active and step == 5:
			advance(6)
