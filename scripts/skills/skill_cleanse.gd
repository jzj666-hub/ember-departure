extends "res://scripts/skills/skill_base.gd"
## Skill 11: Holy Cleanse (✨ 圣洁净化).
## Instantly dispels all negative crowd control effects (roots, pulls, blinds, knockdowns, slows).
## Grants complete CC immunity and unstoppability for duration.
## VFX: Radiant sacred golden-white expansion halo, ascending holy light particles, and golden protective barrier.

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const SkillRegistryScript = preload("res://scripts/skills/skill_registry.gd")
const SigilRingShader = preload("res://shaders/sigil_ring.gdshader")
const SonicRingShader = preload("res://shaders/sonic_boom_ring.gdshader")
const HolyVeilShader = preload("res://shaders/holy_veil.gdshader")

var immune_duration: float = 3.5
var cleanse_radius: float = 6.0

static var _active_shields: Dictionary = {}


func get_id() -> String:
	return "cleanse"


func get_name() -> String:
	return "✨ 圣洁净化 (瞬间解除全负面控制)"


func get_title() -> String:
	return "✨ 圣洁净化配置 (PURIFY & CC IMMUNITY)"


func get_params() -> Dictionary:
	return {
		"immune_duration": immune_duration,
		"cleanse_radius": cleanse_radius
	}


func set_param(key: String, value: Variant) -> void:
	match key:
		"immune_duration": immune_duration = float(value)
		"cleanse_radius": cleanse_radius = float(value)


func cast(caster: CharacterBody3D, _intent_dir: Vector3, vfx_parent: Node, _is_spectator: bool = false) -> Dictionary:
	if caster == null or not is_instance_valid(caster):
		return {}

	_execute_cleanse(caster, immune_duration, cleanse_radius, vfx_parent)

	AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/cloth1.ogg", 1.4)

	return {
		"success": true,
		"skill_id": get_id(),
		"from_pos": caster.global_position if caster.is_inside_tree() else Vector3.ZERO,
		"immune_duration": immune_duration,
		"cleanse_radius": cleanse_radius
	}


func replay(caster: CharacterBody3D, record: Dictionary, vfx_parent: Node) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	var dur: float = float(record.get("immune_duration", immune_duration))
	var rad: float = float(record.get("cleanse_radius", cleanse_radius))
	_execute_cleanse(caster, dur, rad, vfx_parent)


func get_replay_hold_time(record: Dictionary) -> float:
	return float(record.get("immune_duration", immune_duration)) + 0.5


func build_config_panel(container: VBoxContainer, on_changed: Callable) -> void:
	# 免控霸体时长
	var dur_lbl := Label.new()
	dur_lbl.text = "免控霸体时长 (Immunity Duration): %.1fs" % immune_duration
	dur_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(dur_lbl)

	var dur_slider := HSlider.new()
	dur_slider.min_value = 1.0
	dur_slider.max_value = 10.0
	dur_slider.step = 0.5
	dur_slider.value = immune_duration
	dur_slider.value_changed.connect(func(v: float):
		immune_duration = v
		dur_lbl.text = "免控霸体时长 (Immunity Duration): %.1fs" % v
		on_changed.call("immune_duration", v)
	)
	container.add_child(dur_slider)

	# 驱散范围
	var rad_lbl := Label.new()
	rad_lbl.text = "范围驱散半径 (Cleanse Radius): %.1fm" % cleanse_radius
	rad_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(rad_lbl)

	var rad_slider := HSlider.new()
	rad_slider.min_value = 2.0
	rad_slider.max_value = 16.0
	rad_slider.step = 0.5
	rad_slider.value = cleanse_radius
	rad_slider.value_changed.connect(func(v: float):
		cleanse_radius = v
		rad_lbl.text = "范围驱散半径 (Cleanse Radius): %.1fm" % v
		on_changed.call("cleanse_radius", v)
	)
	container.add_child(rad_slider)

	# 说明面板
	var tip_panel := PanelContainer.new()
	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.14, 0.12, 0.04, 0.90)
	t_style.set_corner_radius_all(6)
	t_style.set_border_width_all(1)
	t_style.border_color = Color(1.0, 0.88, 0.3, 0.75)
	t_style.set_content_margin_all(8)
	tip_panel.add_theme_stylebox_override("panel", t_style)
	container.add_child(tip_panel)

	var tip_vbox := VBoxContainer.new()
	tip_vbox.add_theme_constant_override("separation", 4)
	tip_panel.add_child(tip_vbox)

	var tip1 := Label.new()
	tip1.text = "🌟 瞬间解除自身及范围内一切控制（缠绕、击倒、拉拽、致盲、减速）"
	tip1.add_theme_font_size_override("font_size", 11)
	tip1.modulate = Color(1.0, 0.95, 0.5)
	tip_vbox.add_child(tip1)

	var tip2 := Label.new()
	tip2.text = "🛡️ 持续期间获得绝对霸体与圣光免控护体，无视后续任何负面控制"
	tip2.add_theme_font_size_override("font_size", 11)
	tip2.modulate = Color(1.0, 0.75, 0.2)
	tip_vbox.add_child(tip2)


static func _execute_cleanse(caster: CharacterBody3D, dur: float, radius: float, parent: Node) -> void:
	if caster == null or not is_instance_valid(caster):
		return

	# 1. Dispel caster immediately
	SkillRegistryScript.dispel_all_debuffs(caster)
	caster.set_meta("is_cc_immune", true)

	# 2. Dispel nearby entities within radius
	var tree := caster.get_tree()
	if tree != null:
		var bodies := tree.root.find_children("", "CharacterBody3D", true, false)
		for b in bodies:
			if b == null or not is_instance_valid(b):
				continue
			var cb := b as CharacterBody3D
			if cb != null and cb != caster and cb.name != "Ground":
				if cb.global_position.distance_to(caster.global_position) <= radius:
					SkillRegistryScript.dispel_all_debuffs(cb)

	# 3. Spawn Sacred Light Burst & Holy Barrier VFX
	var shield_vfx := _spawn_holy_cleanse_vfx(caster, dur, parent)

	var c_id := caster.get_instance_id()
	if _active_shields.has(c_id):
		var prev_tw: Tween = _active_shields[c_id].get("tween")
		if prev_tw != null and prev_tw.is_valid():
			prev_tw.kill()
		var prev_vfx: Node = _active_shields[c_id].get("vfx")
		if prev_vfx != null and is_instance_valid(prev_vfx):
			prev_vfx.queue_free()

	var tw := caster.create_tween()
	_active_shields[c_id] = {
		"tween": tw,
		"vfx": shield_vfx
	}

	tw.tween_interval(dur)
	tw.tween_callback(func():
		_remove_cleanse_immunity(caster)
	)


static func _remove_cleanse_immunity(caster: CharacterBody3D) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	var c_id := caster.get_instance_id()
	_active_shields.erase(c_id)
	if is_instance_valid(caster):
		caster.set_meta("is_cc_immune", false)


static func _spawn_holy_cleanse_vfx(caster: CharacterBody3D, dur: float, parent: Node) -> Node3D:
	if parent == null or not is_instance_valid(parent):
		parent = caster

	var root_vfx := Node3D.new()
	root_vfx.name = "HolyCleanseVFX"
	parent.add_child(root_vfx)
	root_vfx.global_position = caster.global_position

	# 1. 地面圣洁法阵 (Ground Sacred Magic Circle Sigil)
	var sigil_quad := QuadMesh.new()
	sigil_quad.size = Vector2(3.6, 3.6)
	var sigil_inst := MeshInstance3D.new()
	sigil_inst.name = "CleanseGroundSigil"
	sigil_inst.mesh = sigil_quad
	sigil_inst.rotation.x = -PI * 0.5
	sigil_inst.position.y = 0.03

	var sigil_mat := ShaderMaterial.new()
	sigil_mat.shader = SigilRingShader
	sigil_mat.set_shader_parameter("sigil_color", Color(1.0, 0.92, 0.55, 0.95))
	sigil_mat.set_shader_parameter("spin_speed", 1.8)
	sigil_mat.set_shader_parameter("fade", 1.0)
	VfxTextures.bind(sigil_mat, "sigil_tex", VfxTextures.MAGIC_CIRCLE, "tex_mix", 1.0)
	sigil_inst.material_override = sigil_mat
	root_vfx.add_child(sigil_inst)

	# 2. 净化爆发神圣光环 (Instant Radiant Burst Shockwave Halo)
	var halo_quad := QuadMesh.new()
	halo_quad.size = Vector2(2.5, 2.5)
	var halo := MeshInstance3D.new()
	halo.name = "CleanseBurstHalo"
	halo.mesh = halo_quad
	halo.rotation.x = -PI * 0.5
	halo.position.y = 0.85

	var halo_mat := ShaderMaterial.new()
	halo_mat.shader = SonicRingShader
	halo_mat.set_shader_parameter("ring_color", Color(1.0, 0.96, 0.7, 0.95))
	halo_mat.set_shader_parameter("fade", 1.0)
	halo_mat.set_shader_parameter("thickness", 0.16)
	VfxTextures.bind(halo_mat, "ring_tex", VfxTextures.SHOCKWAVE_RING, "tex_mix", 1.0)
	halo.material_override = halo_mat
	root_vfx.add_child(halo)

	# 3. 圣洁微光护体气幕 (Subtle Holy Translucent Veil - 高通透清爽视界)
	var sphere := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.95
	sm.height = 1.9
	sm.radial_segments = 32
	sm.rings = 16
	sphere.mesh = sm
	sphere.position.y = 0.95

	var sphere_mat := ShaderMaterial.new()
	sphere_mat.shader = HolyVeilShader
	sphere_mat.set_shader_parameter("veil_color", Color(0.9, 0.95, 1.0, 0.05))
	sphere_mat.set_shader_parameter("rim_color", Color(1.0, 0.94, 0.75, 0.40))
	sphere_mat.set_shader_parameter("rim_power", 4.0)
	sphere_mat.set_shader_parameter("pulse_speed", 1.8)
	sphere_mat.set_shader_parameter("fade", 1.0)
	sphere.material_override = sphere_mat
	root_vfx.add_child(sphere)

	# 初始爆发动效
	sigil_inst.scale = Vector3(0.1, 0.1, 0.1)
	halo.scale = Vector3(0.2, 0.2, 0.2)
	sphere.scale = Vector3(0.2, 0.2, 0.2)

	var burst_tw := root_vfx.create_tween().set_parallel(true)
	burst_tw.tween_property(sigil_inst, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	burst_tw.tween_property(sphere, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	burst_tw.tween_property(halo, "scale", Vector3(3.6, 3.6, 3.6), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	burst_tw.tween_method(func(v: float):
		if is_instance_valid(halo_mat):
			halo_mat.set_shader_parameter("fade", v)
	, 1.0, 0.0, 0.35).set_ease(Tween.EASE_IN)

	# 持续跟随与消散动效
	var loop_tw := root_vfx.create_tween().set_parallel(true)
	loop_tw.tween_method(func(_t: float):
		if is_instance_valid(caster) and is_instance_valid(root_vfx):
			root_vfx.global_position = caster.global_position
			sphere.rotate_y(0.02)
	, 0.0, 1.0, dur)

	loop_tw.chain().tween_method(func(v: float):
		if is_instance_valid(sphere_mat):
			sphere_mat.set_shader_parameter("fade", v)
		if is_instance_valid(sigil_mat):
			sigil_mat.set_shader_parameter("fade", v)
	, 1.0, 0.0, 0.25)
	loop_tw.chain().tween_callback(root_vfx.queue_free)

	return root_vfx


func preload_assets() -> void:
	AudioManagerScript.preload_sounds([
		"res://assets/voice/RPGsounds_Kenney/OGG/cloth1.ogg"
	])


func get_warmup_materials() -> Array:
	var m_sigil := ShaderMaterial.new()
	m_sigil.shader = SigilRingShader
	VfxTextures.bind(m_sigil, "sigil_tex", VfxTextures.MAGIC_CIRCLE, "tex_mix", 1.0)

	var m_halo := ShaderMaterial.new()
	m_halo.shader = SonicRingShader
	VfxTextures.bind(m_halo, "ring_tex", VfxTextures.SHOCKWAVE_RING, "tex_mix", 1.0)

	var m_veil := ShaderMaterial.new()
	m_veil.shader = HolyVeilShader

	return [m_sigil, m_halo, m_veil]
