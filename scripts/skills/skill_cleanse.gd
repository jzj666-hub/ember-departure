extends "res://scripts/skills/skill_base.gd"
## 创世天启·广域圣洁神圣净域 (Grand Celestial Holy Cleanse Sanctuary).
## 贯通天地的大型圣辉神柱天降，覆盖全场的双层旋转巨型神域金轮法阵，
## 广域圣光横扫冲击波，宏伟琉璃极光天幕力场，以及漫天升腾浮游的神圣光羽星尘。

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const SkillRegistryScript = preload("res://scripts/skills/skill_registry.gd")
const SigilRingShader = preload("res://shaders/sigil_ring.gdshader")
const SonicRingShader = preload("res://shaders/sonic_boom_ring.gdshader")
const HolyVeilShader = preload("res://shaders/holy_veil.gdshader")
const HeavenlyPillarShader = preload("res://shaders/heavenly_pillar.gdshader")

var immune_duration: float = 3.5
var cleanse_radius: float = 6.0

static var _active_shields: Dictionary = {}

func get_id() -> String:
	return "cleanse"

func get_name() -> String:
	return "✨ 圣洁净化 (天启广域神圣净域)"

func get_title() -> String:
	return "✨ 圣洁净化配置 (CELESTIAL HOLY SANCTUARY)"

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

	AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/cloth1.ogg", 1.6)

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

	var rad_lbl := Label.new()
	rad_lbl.text = "天启净域波及半径 (Cleanse Radius): %.1fm" % cleanse_radius
	rad_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(rad_lbl)

	var rad_slider := HSlider.new()
	rad_slider.min_value = 3.0
	rad_slider.max_value = 18.0
	rad_slider.step = 0.5
	rad_slider.value = cleanse_radius
	rad_slider.value_changed.connect(func(v: float):
		cleanse_radius = v
		rad_lbl.text = "天启净域波及半径 (Cleanse Radius): %.1fm" % v
		on_changed.call("cleanse_radius", v)
	)
	container.add_child(rad_slider)

	var tip_panel := PanelContainer.new()
	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.16, 0.14, 0.04, 0.92)
	t_style.set_corner_radius_all(6)
	t_style.set_border_width_all(1)
	t_style.border_color = Color(1.0, 0.88, 0.35, 0.8)
	t_style.set_content_margin_all(8)
	tip_panel.add_theme_stylebox_override("panel", t_style)
	container.add_child(tip_panel)

	var tip_vbox := VBoxContainer.new()
	tip_vbox.add_theme_constant_override("separation", 4)
	tip_panel.add_child(tip_vbox)

	var tip1 := Label.new()
	tip1.text = "⚡ 天启神柱从天而降，横扫巨型冲击光环解除全场所有控制"
	tip1.add_theme_font_size_override("font_size", 11)
	tip1.modulate = Color(1.0, 0.95, 0.5)
	tip_vbox.add_child(tip1)

	var tip2 := Label.new()
	tip2.text = "🏛️ 铺满地面的双层神域金轮法阵与宏伟琉璃极光天幕持续护体"
	tip2.add_theme_font_size_override("font_size", 11)
	tip2.modulate = Color(0.9, 1.0, 0.6)
	tip_vbox.add_child(tip2)

	var tip3 := Label.new()
	tip3.text = "✨ 漫天升腾神圣光羽与金色星尘，气势磅礴"
	tip3.add_theme_font_size_override("font_size", 11)
	tip3.modulate = Color(0.7, 0.95, 1.0)
	tip_vbox.add_child(tip3)

static func _execute_cleanse(caster: CharacterBody3D, dur: float, radius: float, parent: Node) -> void:
	if caster == null or not is_instance_valid(caster):
		return

	# 1. Dispel caster immediately
	SkillRegistryScript.dispel_all_debuffs(caster)
	caster.set_meta("is_cc_immune", true)

	# 2. Dispel nearby entities within grand radius
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

	# 3. Spawn Grand Celestial Sanctuary VFX Suite
	var shield_vfx := _spawn_grand_celestial_sanctuary(caster, dur, radius, parent)

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

## 构建大场面天启神圣净域全套视觉
static func _spawn_grand_celestial_sanctuary(caster: CharacterBody3D, dur: float, radius: float, parent: Node) -> Node3D:
	if parent == null or not is_instance_valid(parent):
		parent = caster

	var root_vfx := Node3D.new()
	root_vfx.name = "GrandCelestialSanctuary"
	parent.add_child(root_vfx)
	root_vfx.global_position = caster.global_position

	var center := caster.global_position

	# --- 1. 天降贯通天地的天启圣辉神柱 (Heavenly Descending Light Pillar - 3/5 适中比例) ---
	var pillar := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.4
	cyl.bottom_radius = 2.1
	cyl.height = 22.0
	pillar.mesh = cyl
	pillar.position = Vector3.UP * 11.0

	var p_mat := ShaderMaterial.new()
	p_mat.shader = HeavenlyPillarShader
	p_mat.set_shader_parameter("beam_core", Color(2.0, 2.0, 1.8, 1.0))
	p_mat.set_shader_parameter("beam_gold", Color(1.0, 0.88, 0.45, 0.95))
	p_mat.set_shader_parameter("beam_aurora", Color(0.35, 0.92, 0.95, 0.75))
	p_mat.set_shader_parameter("speed", 7.0)
	p_mat.set_shader_parameter("fade", 1.0)
	pillar.material_override = p_mat
	root_vfx.add_child(pillar)

	var p_tw := pillar.create_tween().set_parallel(true)
	p_tw.tween_property(pillar, "scale", Vector3(1.2, 1.0, 1.2), 0.20).from(Vector3(0.2, 1.0, 0.2))\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	p_tw.chain().tween_property(p_mat, "shader_parameter/fade", 0.0, 0.38).set_ease(Tween.EASE_IN)
	p_tw.chain().tween_callback(pillar.queue_free)

	# --- 2. 广域横扫圣光冲击波双巨环 (3/5 比例) ---
	_spawn_grand_shockwaves(radius, root_vfx)

	# --- 3. 战场全向强闪光耀斑 ---
	var flash_light := OmniLight3D.new()
	flash_light.light_color = Color(1.0, 0.95, 0.8)
	flash_light.light_energy = 4.2
	flash_light.omni_range = maxf(radius * 2.0, 14.0)
	flash_light.position = Vector3.UP * 2.0
	root_vfx.add_child(flash_light)

	var fl_tw := flash_light.create_tween()
	fl_tw.tween_property(flash_light, "light_energy", 0.0, 0.40).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fl_tw.tween_callback(flash_light.queue_free)

	# --- 4. 铺满地面的双层旋转神域金轮法阵 (3/5 比例: 直径约 7.5~8.5m) ---
	# 外层大圈
	var outer_sigil := MeshInstance3D.new()
	var outer_quad := QuadMesh.new()
	var grand_diam := maxf(radius * 1.35, 7.8)
	outer_quad.size = Vector2(grand_diam, grand_diam)
	outer_sigil.mesh = outer_quad
	outer_sigil.rotation.x = -PI * 0.5
	outer_sigil.position.y = 0.03

	var outer_mat := ShaderMaterial.new()
	outer_mat.shader = SigilRingShader
	outer_mat.set_shader_parameter("sigil_color", Color(1.0, 0.88, 0.45, 0.95))
	outer_mat.set_shader_parameter("spin_speed", -1.2)
	outer_mat.set_shader_parameter("fade", 1.0)
	VfxTextures.bind(outer_mat, "sigil_tex", VfxTextures.MAGIC_CIRCLE, "tex_mix", 1.0)
	outer_sigil.material_override = outer_mat
	root_vfx.add_child(outer_sigil)

	# 内层密纹精细法阵
	var inner_sigil := MeshInstance3D.new()
	var inner_quad := QuadMesh.new()
	inner_quad.size = Vector2(grand_diam * 0.55, grand_diam * 0.55)
	inner_sigil.mesh = inner_quad
	inner_sigil.rotation.x = -PI * 0.5
	inner_sigil.position.y = 0.04

	var inner_mat := ShaderMaterial.new()
	inner_mat.shader = SigilRingShader
	inner_mat.set_shader_parameter("sigil_color", Color(0.95, 0.98, 1.0, 0.95))
	inner_mat.set_shader_parameter("spin_speed", 2.2)
	inner_mat.set_shader_parameter("fade", 1.0)
	VfxTextures.bind(inner_mat, "sigil_tex", VfxTextures.MAGIC_CIRCLE, "tex_mix", 1.0)
	inner_sigil.material_override = inner_mat
	root_vfx.add_child(inner_sigil)

	# --- 5. 宏伟琉璃极光天幕力场 (3/5 比例: 半径 1.45m，高 2.8m，完美包裹角色) ---
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.45
	sm.height = 2.8
	sm.radial_segments = 32
	sm.rings = 16
	dome.mesh = sm
	dome.position.y = 1.0

	var dome_mat := ShaderMaterial.new()
	dome_mat.shader = HolyVeilShader
	dome_mat.set_shader_parameter("veil_core", Color(0.92, 0.96, 1.0, 0.08))
	dome_mat.set_shader_parameter("rim_rosegold", Color(1.0, 0.85, 0.65, 0.65))
	dome_mat.set_shader_parameter("rim_aurora", Color(0.35, 0.95, 0.88, 0.75))
	dome_mat.set_shader_parameter("rim_power", 2.8)
	dome_mat.set_shader_parameter("pulse_speed", 2.2)
	dome_mat.set_shader_parameter("fade", 1.0)
	dome.material_override = dome_mat
	root_vfx.add_child(dome)

	# --- 6. 漫天升腾浮游的神圣光羽与星尘 ---
	var feathers := _spawn_floating_sacred_feathers(radius, dur, root_vfx)

	# --- 展开与跟随动画 ---
	outer_sigil.scale = Vector3(0.1, 0.1, 0.1)
	inner_sigil.scale = Vector3(0.1, 0.1, 0.1)
	dome.scale = Vector3(0.2, 0.2, 0.2)

	var burst_tw := root_vfx.create_tween().set_parallel(true)
	burst_tw.tween_property(outer_sigil, "scale", Vector3.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	burst_tw.tween_property(inner_sigil, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	burst_tw.tween_property(dome, "scale", Vector3.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 持续跟随与消散动效
	var loop_tw := root_vfx.create_tween().set_parallel(true)
	loop_tw.tween_method(func(_t: float):
		if is_instance_valid(caster) and is_instance_valid(root_vfx):
			root_vfx.global_position = caster.global_position
			dome.rotate_y(0.015)
	, 0.0, 1.0, dur)

	loop_tw.chain().tween_method(func(v: float):
		if is_instance_valid(dome_mat):
			dome_mat.set_shader_parameter("fade", v)
		if is_instance_valid(outer_mat):
			outer_mat.set_shader_parameter("fade", v)
		if is_instance_valid(inner_mat):
			inner_mat.set_shader_parameter("fade", v)
	, 1.0, 0.0, 0.35)
	loop_tw.chain().tween_callback(root_vfx.queue_free)

	return root_vfx

## 广域双重圣光冲击波巨环 (3/5 比例)
static func _spawn_grand_shockwaves(radius: float, parent: Node) -> void:
	var grand_r := maxf(radius * 1.45, 8.5)

	# 巨环 1
	var ring1 := MeshInstance3D.new()
	var qm1 := QuadMesh.new()
	qm1.size = Vector2(grand_r, grand_r)
	ring1.mesh = qm1
	ring1.rotation.x = -PI * 0.5
	ring1.position.y = 0.6

	var r1_mat := ShaderMaterial.new()
	r1_mat.shader = SonicRingShader
	r1_mat.set_shader_parameter("ring_color", Color(1.0, 0.95, 0.7, 0.95))
	r1_mat.set_shader_parameter("thickness", 0.18)
	r1_mat.set_shader_parameter("fade", 1.0)
	VfxTextures.bind(r1_mat, "ring_tex", VfxTextures.SHOCKWAVE_RING, "tex_mix", 1.0)
	VfxTextures.bind_ramp(r1_mat, VfxTextures.RAMP_ARC, 0.8)
	ring1.material_override = r1_mat
	parent.add_child(ring1)

	var tw1 := ring1.create_tween().set_parallel(true)
	tw1.tween_property(ring1, "scale", Vector3(1.2, 1.2, 1.2), 0.38).from(Vector3(0.1, 0.1, 0.1))\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw1.tween_method(func(v: float):
		if is_instance_valid(r1_mat):
			r1_mat.set_shader_parameter("fade", v)
	, 1.0, 0.0, 0.38).set_ease(Tween.EASE_IN)
	tw1.chain().tween_callback(ring1.queue_free)

	# 次级回响光环 2
	var ring2 := MeshInstance3D.new()
	var qm2 := QuadMesh.new()
	qm2.size = Vector2(grand_r * 0.8, grand_r * 0.8)
	ring2.mesh = qm2
	ring2.rotation.x = -PI * 0.5
	ring2.position.y = 1.0

	var r2_mat := ShaderMaterial.new()
	r2_mat.shader = SonicRingShader
	r2_mat.set_shader_parameter("ring_color", Color(0.4, 0.92, 1.0, 0.85))
	r2_mat.set_shader_parameter("thickness", 0.14)
	r2_mat.set_shader_parameter("fade", 1.0)
	VfxTextures.bind(r2_mat, "ring_tex", VfxTextures.SHOCKWAVE_RING, "tex_mix", 1.0)
	ring2.material_override = r2_mat
	parent.add_child(ring2)

	var tw2 := ring2.create_tween()
	tw2.tween_interval(0.06)
	tw2.set_parallel(true)
	tw2.tween_property(ring2, "scale", Vector3(1.15, 1.15, 1.15), 0.35).from(Vector3(0.15, 0.15, 0.15))\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw2.tween_method(func(v: float):
		if is_instance_valid(r2_mat):
			r2_mat.set_shader_parameter("fade", v)
	, 1.0, 0.0, 0.35).set_ease(Tween.EASE_IN)
	tw2.chain().tween_callback(ring2.queue_free)

## 漫天升腾浮游的神圣光羽与星尘粒子 (3/5 比例)
static func _spawn_floating_sacred_feathers(radius: float, dur: float, parent: Node) -> CPUParticles3D:
	var parts := CPUParticles3D.new()
	parts.name = "SacredFeatherDust"
	parts.amount = 32
	parts.lifetime = 1.8
	parts.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	parts.emission_ring_radius = maxf(radius * 0.55, 2.8)
	parts.emission_ring_inner_radius = 0.2
	parts.emission_ring_height = 0.2
	parts.emission_ring_axis = Vector3(0, 1, 0)
	parts.direction = Vector3.UP
	parts.spread = 22.0
	parts.gravity = Vector3(0, 0.3, 0)
	parts.initial_velocity_min = 0.8
	parts.initial_velocity_max = 1.8
	parts.scale_amount_min = 0.7
	parts.scale_amount_max = 1.5

	var p_mesh := QuadMesh.new()
	p_mesh.size = Vector2(0.18, 0.26)
	var p_mat := StandardMaterial3D.new()
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	p_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	p_mat.albedo_color = Color(1.0, 0.95, 0.7, 0.9)
	p_mat.albedo_texture = VfxTextures.get_tex(VfxTextures.FLASH_GLOW)
	parts.mesh = p_mesh
	parts.material_override = p_mat

	parent.add_child(parts)
	parts.position.y = 0.05
	parts.emitting = true

	var tw := parts.create_tween()
	tw.tween_interval(maxf(dur - 0.25, 0.1))
	tw.tween_property(p_mat, "albedo_color:a", 0.0, 0.35)
	tw.tween_callback(func():
		parts.emitting = false
	)

	return parts

## reset_state(): drops shield bookkeeping. Scene entry only.
func reset_state() -> void:
	_active_shields.clear()


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

	var m_pillar := ShaderMaterial.new()
	m_pillar.shader = HeavenlyPillarShader

	return [m_sigil, m_halo, m_veil, m_pillar]
