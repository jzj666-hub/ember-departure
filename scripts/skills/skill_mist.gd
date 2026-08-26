extends "res://scripts/skills/skill_base.gd"
## 昏暗·无明夜 (Mist Obscurity / Abyssal Darkness Domain).
## 释放瞬间向全场席卷扩张的深渊翻滚黑雾巨型穹顶（纯数学3D程序化着色，0%黑底贴图瑕疵）；
## 影响波及半径内所有敌方，敌人双眼陷入绝对纯黑障眼（视野随距递减，仅保留核心微弱视野）。

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const AbyssalDarkMistDomeShader = preload("res://shaders/abyssal_dark_mist_dome.gdshader")
const SonicRingShader = preload("res://shaders/sonic_boom_ring.gdshader")

var mist_radius: float = 10.0
var center_blind_time: float = 7.0
var edge_blind_time: float = 2.0
var center_vision: float = 1.5
var edge_vision: float = 7.0

static var _active_blinds: Dictionary = {}
static var _blackout: VisionBlackout = null

func get_id() -> String:
	return "mist"

func get_name() -> String:
	return "🌑 昏暗 (无明夜·深渊黑雾领域)"

func get_title() -> String:
	return "🌑 昏暗配置 (ABYSSAL MIST OBSCURITY)"

func get_params() -> Dictionary:
	return {
		"mist_radius": mist_radius,
		"center_blind_time": center_blind_time,
		"edge_blind_time": edge_blind_time,
		"center_vision": center_vision,
		"edge_vision": edge_vision
	}

func set_param(key: String, value: Variant) -> void:
	match key:
		"mist_radius": mist_radius = float(value)
		"center_blind_time": center_blind_time = float(value)
		"edge_blind_time": edge_blind_time = float(value)
		"center_vision": center_vision = float(value)
		"edge_vision": edge_vision = float(value)

func cast(caster: CharacterBody3D, _intent_dir: Vector3, vfx_parent: Node, _is_spectator: bool = false) -> Dictionary:
	if caster == null or not is_instance_valid(caster):
		return {}
	return _spawn_mist(caster, vfx_parent)

func replay(caster: CharacterBody3D, record: Dictionary, vfx_parent: Node) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	_spawn_mist(caster, vfx_parent)

func get_replay_hold_time(record: Dictionary) -> float:
	return maxf(float(record.get("center_blind_time", center_blind_time)) + 1.5, 3.0)

func build_config_panel(container: VBoxContainer, on_changed: Callable) -> void:
	# 迷雾影响半径
	var radius_lbl := Label.new()
	radius_lbl.text = "昏暗波及半径 (Radius): %.1fm" % mist_radius
	radius_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(radius_lbl)

	var radius_slider := HSlider.new()
	radius_slider.min_value = 3.0
	radius_slider.max_value = 20.0
	radius_slider.step = 0.5
	radius_slider.value = mist_radius
	radius_slider.value_changed.connect(func(v: float):
		mist_radius = v
		radius_lbl.text = "昏暗波及半径 (Radius): %.1fm" % v
		on_changed.call("mist_radius", v)
	)
	container.add_child(radius_slider)

	# 中心残存视野
	var cvision_lbl := Label.new()
	cvision_lbl.text = "核心残存视野 (Center Vision): %.1fm" % center_vision
	cvision_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(cvision_lbl)

	var cvision_slider := HSlider.new()
	cvision_slider.min_value = 0.5
	cvision_slider.max_value = 4.0
	cvision_slider.step = 0.1
	cvision_slider.value = center_vision
	cvision_slider.value_changed.connect(func(v: float):
		center_vision = v
		cvision_lbl.text = "核心残存视野 (Center Vision): %.1fm" % v
		on_changed.call("center_vision", v)
	)
	container.add_child(cvision_slider)

	# 边缘残存视野
	var evision_lbl := Label.new()
	evision_lbl.text = "边缘残存视野 (Edge Vision): %.1fm" % edge_vision
	evision_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(evision_lbl)

	var evision_slider := HSlider.new()
	evision_slider.min_value = 3.0
	evision_slider.max_value = 16.0
	evision_slider.step = 0.5
	evision_slider.value = edge_vision
	evision_slider.value_changed.connect(func(v: float):
		edge_vision = v
		evision_lbl.text = "边缘残存视野 (Edge Vision): %.1fm" % v
		on_changed.call("edge_vision", v)
	)
	container.add_child(evision_slider)

	# 中心失明时长
	var ctime_lbl := Label.new()
	ctime_lbl.text = "核心失明时长 (Center Duration): %.1fs" % center_blind_time
	ctime_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(ctime_lbl)

	var ctime_slider := HSlider.new()
	ctime_slider.min_value = 2.0
	ctime_slider.max_value = 15.0
	ctime_slider.step = 0.5
	ctime_slider.value = center_blind_time
	ctime_slider.value_changed.connect(func(v: float):
		center_blind_time = v
		ctime_lbl.text = "核心失明时长 (Center Duration): %.1fs" % v
		on_changed.call("center_blind_time", v)
	)
	container.add_child(ctime_slider)

	# 边缘失明时长
	var etime_lbl := Label.new()
	etime_lbl.text = "边缘失明时长 (Edge Duration): %.1fs" % edge_blind_time
	etime_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(etime_lbl)

	var etime_slider := HSlider.new()
	etime_slider.min_value = 0.5
	etime_slider.max_value = 6.0
	etime_slider.step = 0.5
	etime_slider.value = edge_blind_time
	etime_slider.value_changed.connect(func(v: float):
		edge_blind_time = v
		etime_lbl.text = "边缘失明时长 (Edge Duration): %.1fs" % v
		on_changed.call("edge_blind_time", v)
	)
	container.add_child(etime_slider)

	# 说明面板
	var tip_panel := PanelContainer.new()
	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.06, 0.03, 0.09, 0.90)
	t_style.set_corner_radius_all(6)
	t_style.set_border_width_all(1)
	t_style.border_color = Color(0.4, 0.2, 0.6, 0.6)
	t_style.set_content_margin_all(8)
	tip_panel.add_theme_stylebox_override("panel", t_style)
	container.add_child(tip_panel)

	var tip_vbox := VBoxContainer.new()
	tip_vbox.add_theme_constant_override("separation", 4)
	tip_panel.add_child(tip_vbox)

	var tip1 := Label.new()
	tip1.text = "🌑 施法时深渊翻滚黑雾巨型天幕席卷全场，无任何黑底贴图瑕疵"
	tip1.add_theme_font_size_override("font_size", 11)
	tip1.modulate = Color(0.7, 0.6, 0.9)
	tip_vbox.add_child(tip1)

	var tip2 := Label.new()
	tip2.text = "💥 施法者完全免疫；受影响敌方陷入纯黑障眼（距离越近失明越久）"
	tip2.add_theme_font_size_override("font_size", 11)
	tip2.modulate = Color(1.0, 0.85, 0.3)
	tip_vbox.add_child(tip2)

	var tip3 := Label.new()
	tip3.text = "👁️ 残存视野外全部陷入绝对纯黑；[F2] 切换受害者体验"
	tip3.add_theme_font_size_override("font_size", 11)
	tip3.modulate = Color(0.7, 0.8, 0.9)
	tip_vbox.add_child(tip3)

static func _ensure_blackout(parent: Node) -> void:
	if _blackout != null and is_instance_valid(_blackout):
		return
	_blackout = VisionBlackout.new()
	_blackout.name = "MistVisionBlackout"
	## Handing over the SAME Dictionary, not a copy: the node ticks entries down and erases
	## them, and _active_blinds sees that immediately. reset_state() must clear() it, never
	## reassign, or the node keeps writing to an orphaned dictionary.
	_blackout.blinds = _active_blinds
	parent.add_child(_blackout)

func _spawn_mist(caster: CharacterBody3D, parent: Node) -> Dictionary:
	if caster == null or not is_instance_valid(caster):
		return {}
	if parent == null or not is_instance_valid(parent):
		return {}

	_ensure_blackout(parent)
	_spawn_cast_vfx(caster, parent)
	_apply_blinds(caster, parent)

	AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg", 1.0)

	return {
		"success": true,
		"skill_id": get_id(),
		"from_pos": caster.global_position,
		"target_pos": caster.global_position,
		"mist_radius": mist_radius,
		"center_blind_time": center_blind_time,
		"edge_blind_time": edge_blind_time,
		"center_vision": center_vision,
		"edge_vision": edge_vision
	}

func _spawn_cast_vfx(caster: CharacterBody3D, parent: Node) -> void:
	var vfx := Node3D.new()
	vfx.name = "AbyssalMistDomeVFX"
	parent.add_child(vfx)
	vfx.global_position = caster.global_position

	# 1. 冲击暗影扩散环 (Shockwave Ring)
	var ring := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(mist_radius * 2.2, mist_radius * 2.2)
	ring.mesh = qm
	ring.rotation.x = -PI * 0.5
	ring.position.y = 0.08

	var r_mat := ShaderMaterial.new()
	r_mat.shader = SonicRingShader
	r_mat.set_shader_parameter("ring_color", Color(0.12, 0.02, 0.22, 0.95))
	r_mat.set_shader_parameter("thickness", 0.20)
	r_mat.set_shader_parameter("fade", 1.0)
	VfxTextures.bind(r_mat, "ring_tex", VfxTextures.SHOCKWAVE_RING, "tex_mix", 1.0)
	ring.material_override = r_mat
	vfx.add_child(ring)

	# 2. 宏伟深渊翻滚黑雾巨型天幕穹顶 (Grand Volumetric Mist Dome - 100% 数学程序化，0% 贴图黑底)
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = mist_radius
	sm.height = mist_radius * 1.5
	sm.radial_segments = 36
	sm.rings = 18
	dome.mesh = sm
	dome.position.y = 0.0

	var dome_mat := ShaderMaterial.new()
	dome_mat.shader = AbyssalDarkMistDomeShader
	dome_mat.set_shader_parameter("color_dark_ink", Color(0.02, 0.01, 0.04, 0.95))
	dome_mat.set_shader_parameter("color_smoke_body", Color(0.08, 0.04, 0.14, 0.85))
	dome_mat.set_shader_parameter("color_ethereal_cyan", Color(0.05, 0.85, 1.1, 0.40))
	dome_mat.set_shader_parameter("speed", 1.8)
	dome_mat.set_shader_parameter("smoke_density", 5.5)
	dome_mat.set_shader_parameter("fade", 1.0)
	dome.material_override = dome_mat
	vfx.add_child(dome)

	# 动画展开与维持
	ring.scale = Vector3(0.1, 0.1, 0.1)
	dome.scale = Vector3(0.15, 0.15, 0.15)

	var tw := vfx.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float):
		if is_instance_valid(r_mat):
			r_mat.set_shader_parameter("fade", v)
	, 1.0, 0.0, 0.55).set_ease(Tween.EASE_IN)

	tw.tween_property(dome, "scale", Vector3.ONE, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# 持续与消散
	var loop_tw := vfx.create_tween()
	loop_tw.tween_interval(center_blind_time)
	loop_tw.tween_method(func(v: float):
		if is_instance_valid(dome_mat):
			dome_mat.set_shader_parameter("fade", v)
	, 1.0, 0.0, 0.65)
	loop_tw.chain().tween_callback(vfx.queue_free)

func _apply_blinds(caster: CharacterBody3D, parent: Node) -> void:
	var tree := caster.get_tree()
	if tree == null:
		return

	var center := caster.global_position
	center.y = 0.0
	var radius := maxf(mist_radius, 0.5)

	var bodies := tree.root.find_children("", "CharacterBody3D", true, false)
	for b in bodies:
		if not (b is CharacterBody3D):
			continue
		var cb := b as CharacterBody3D
		if cb == caster or cb.name == "Ground":
			continue

		var to := cb.global_position - center
		to.y = 0.0
		var dist := to.length()
		if dist > radius:
			continue

		var t := clampf(dist / radius, 0.0, 1.0)
		var vision := lerpf(maxf(center_vision, 0.2), maxf(edge_vision, center_vision), t)
		var duration := lerpf(maxf(center_blind_time, 0.5), maxf(edge_blind_time, 0.2), t)

		var aura := _create_target_aura(cb)

		_active_blinds[cb.get_instance_id()] = {
			"body": cb,
			"vision": vision,
			"remaining": duration,
			"max_duration": duration,
			"aura": aura
		}

func _create_target_aura(target: CharacterBody3D) -> Node3D:
	var existing := target.get_node_or_null("MistTargetAura")
	if existing != null and is_instance_valid(existing):
		return existing as Node3D

	var aura := Node3D.new()
	aura.name = "MistTargetAura"

	var ring := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.2, 1.2)
	ring.mesh = qm
	ring.rotation.x = -PI * 0.5
	ring.position.y = 0.05

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.4, 0.15, 0.65, 0.85)
	mat.albedo_texture = VfxTextures.get_tex(VfxTextures.FLASH_GLOW)
	ring.material_override = mat
	aura.add_child(ring)

	target.add_child(aura)
	return aura

class VisionBlackout extends MeshInstance3D:
	## Fullscreen screen-space vision cone. One instance per scene, owned by the outer
	## static _blackout. Ticks `blinds` down in _process and frees each entry's aura.
	const SHADER = preload("res://shaders/vision_blackout.gdshader")

	## ALIAS, NOT A COPY: assigned SkillMist._active_blinds, and Dictionary is a reference
	## type — erase() here also erases there. Never reassign either side; mutate in place.
	var blinds: Dictionary = {}
	var _mat: ShaderMaterial

	func _ready() -> void:
		name = "VisionBlackoutEffect"
		var qm := QuadMesh.new()
		qm.size = Vector2(2.0, 2.0)
		mesh = qm
		cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		extra_cull_margin = 16384.0

		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
		_mat.render_priority = 127
		material_override = _mat

	func _process(delta: float) -> void:
		var to_remove: Array = []
		for id in blinds.keys():
			var entry: Dictionary = blinds[id]
			entry["remaining"] -= delta
			if entry["remaining"] <= 0.0:
				to_remove.append(id)
				var aura: Node3D = entry.get("aura", null)
				if aura != null and is_instance_valid(aura):
					aura.queue_free()

		for id in to_remove:
			blinds.erase(id)

		var vp := get_viewport()
		if vp == null:
			return
		var cam := vp.get_camera_3d()
		if cam == null:
			_mat.set_shader_parameter("u_blind_active", 0.0)
			return

		var controlled_node := _find_controlled_actor(cam)
		var controlled_id := controlled_node.get_instance_id() if controlled_node != null else 0

		if blinds.has(controlled_id):
			var entry: Dictionary = blinds[controlled_id]
			var actor: CharacterBody3D = entry["body"]
			if actor != null and is_instance_valid(actor):
				_mat.set_shader_parameter("u_blind_active", 1.0)
				_mat.set_shader_parameter("u_actor_pos", actor.global_position + Vector3.UP * 0.9)
				_mat.set_shader_parameter("u_vision_radius", entry["vision"])
				_mat.set_shader_parameter("u_soft_edge", 0.4)
				return

		_mat.set_shader_parameter("u_blind_active", 0.0)

	func _find_controlled_actor(cam: Camera3D) -> CharacterBody3D:
		var target: Node = cam.get("target")
		if target is CharacterBody3D:
			return target as CharacterBody3D
		var p := cam.get_parent()
		while p != null:
			if p is CharacterBody3D:
				return p as CharacterBody3D
			p = p.get_parent()
		return null

	func clear_target(actor: CharacterBody3D) -> void:
		if actor == null:
			return
		var id := actor.get_instance_id()
		if blinds.has(id):
			var entry: Dictionary = blinds[id]
			var aura: Node3D = entry.get("aura", null)
			if aura != null and is_instance_valid(aura):
				aura.queue_free()
			blinds.erase(id)


## reset_state(): drops blind bookkeeping and the dangling blackout node ref.
## clear() not reassignment: VisionBlackout.blinds aliases this same Dictionary.
func reset_state() -> void:
	_active_blinds.clear()
	_blackout = null


func preload_assets() -> void:
	AudioManagerScript.preload_sounds([
		"res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg"
	])

func get_warmup_materials() -> Array:
	var m_dome := ShaderMaterial.new()
	m_dome.shader = AbyssalDarkMistDomeShader

	var m_ring := ShaderMaterial.new()
	m_ring.shader = SonicRingShader

	var m_blackout := ShaderMaterial.new()
	m_blackout.shader = VisionBlackout.SHADER

	return [m_dome, m_ring, m_blackout]

func dispel_actor(actor: CharacterBody3D) -> void:
	if actor != null and is_instance_valid(actor) and _blackout != null and is_instance_valid(_blackout):
		_blackout.clear_target(actor)
