extends "res://scripts/skills/skill_base.gd"
## Skill 12: Thunder Smite (天雷神裁).
## Calls down a catastrophic celestial lightning bolt over an area around the caster.
## Overhead celestial ring with rotating lightning orbs strikes thick lightning bolts straight down onto the ground purple-gold sigil.
## Stuns and confuses hit enemies: inverts movement directions (W<->S, A<->D) and distorts their visual perspective.

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const AnimPipelineScript = preload("res://tools/anim_pipeline.gd")
const LightningStrikeShader = preload("res://shaders/lightning_strike.gdshader")
const SpatialWarp3DShader = preload("res://shaders/spatial_warp_3d.gdshader")
const SonicRingShader = preload("res://shaders/sonic_boom_ring.gdshader")
const ThunderMagicSigilShader = preload("res://shaders/thunder_magic_sigil.gdshader")
const CelestialRingShader = preload("res://shaders/celestial_ring.gdshader")
const CelestialOrbShader = preload("res://shaders/celestial_thunder_orb.gdshader")
const FineLightningWebShader = preload("res://shaders/fine_lightning_web.gdshader")

var thunder_radius: float = 7.5
var confuse_duration: float = 4.5
var damage: float = 140.0
var thunder_delay: float = 0.22

## Overhead top ring height directly above the character
const SKY_HEIGHT: float = 7.6
const ORB_COUNT: int = 5
## Extended strike continuous duration
const STRIKE_DURATION: float = 1.80

static var _active_confusions: Dictionary = {}


func get_id() -> String:
	return "thunder"


func get_name() -> String:
	return "⚡ 天雷神裁 (操作颠倒·空间扭曲)"


func get_title() -> String:
	return "⚡ 天雷神裁配置 (THUNDER SMITE & SPATIAL CONFUSION)"


func get_params() -> Dictionary:
	return {
		"thunder_radius": thunder_radius,
		"confuse_duration": confuse_duration,
		"damage": damage,
		"thunder_delay": thunder_delay
	}


func set_param(key: String, value: Variant) -> void:
	match key:
		"thunder_radius": thunder_radius = float(value)
		"confuse_duration": confuse_duration = float(value)
		"damage": damage = float(value)
		"thunder_delay": thunder_delay = float(value)


func cast(caster: CharacterBody3D, _intent_dir: Vector3, vfx_parent: Node, _is_spectator: bool = false) -> Dictionary:
	if caster == null or not is_instance_valid(caster) or not caster.is_inside_tree():
		return {}
	return _execute_thunder(caster, vfx_parent)


func replay(caster: CharacterBody3D, record: Dictionary, vfx_parent: Node) -> void:
	if caster == null or not is_instance_valid(caster) or not caster.is_inside_tree():
		return
	_execute_thunder(caster, vfx_parent)


func get_replay_hold_time(_record: Dictionary) -> float:
	return thunder_delay + STRIKE_DURATION + 1.0


func build_config_panel(container: VBoxContainer, on_changed: Callable) -> void:
	# 波及半径
	var r_lbl := Label.new()
	r_lbl.text = "天雷波及半径 (Radius): %.1fm" % thunder_radius
	r_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(r_lbl)

	var r_slider := HSlider.new()
	r_slider.min_value = 3.0
	r_slider.max_value = 16.0
	r_slider.step = 0.5
	r_slider.value = thunder_radius
	r_slider.value_changed.connect(func(v: float):
		thunder_radius = v
		r_lbl.text = "天雷波及半径 (Radius): %.1fm" % v
		on_changed.call("thunder_radius", v)
	)
	container.add_child(r_slider)

	# 混乱颠倒与扭曲时长
	var dur_lbl := Label.new()
	dur_lbl.text = "颠倒与空间扭曲持续 (Duration): %.1fs" % confuse_duration
	dur_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(dur_lbl)

	var dur_slider := HSlider.new()
	dur_slider.min_value = 1.5
	dur_slider.max_value = 10.0
	dur_slider.step = 0.5
	dur_slider.value = confuse_duration
	dur_slider.value_changed.connect(func(v: float):
		confuse_duration = v
		dur_lbl.text = "颠倒与空间扭曲持续 (Duration): %.1fs" % v
		on_changed.call("confuse_duration", v)
	)
	container.add_child(dur_slider)

	# 基础伤害
	var dmg_lbl := Label.new()
	dmg_lbl.text = "神雷伤害 (Damage): %d" % int(damage)
	dmg_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(dmg_lbl)

	var dmg_slider := HSlider.new()
	dmg_slider.min_value = 0.0
	dmg_slider.max_value = 500.0
	dmg_slider.step = 10.0
	dmg_slider.value = damage
	dmg_slider.value_changed.connect(func(v: float):
		damage = v
		dmg_lbl.text = "神雷伤害 (Damage): %d" % int(v)
		on_changed.call("damage", v)
	)
	container.add_child(dmg_slider)

	# 特性说明面板
	var tip_panel := PanelContainer.new()
	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.06, 0.08, 0.16, 0.90)
	t_style.set_corner_radius_all(6)
	t_style.set_border_width_all(1)
	t_style.border_color = Color(0.65, 0.45, 0.95, 0.6)
	t_style.set_content_margin_all(8)
	tip_panel.add_theme_stylebox_override("panel", t_style)
	container.add_child(tip_panel)

	var tip_vbox := VBoxContainer.new()
	tip_vbox.add_theme_constant_override("separation", 4)
	tip_panel.add_child(tip_vbox)

	var tip1 := Label.new()
	tip1.text = "⚡ 精美紫金天轨法球，迸发粗壮神雷直击下方紫金雷电法阵"
	tip1.add_theme_font_size_override("font_size", 11)
	tip1.modulate = Color(0.85, 0.75, 1.0)
	tip_vbox.add_child(tip1)

	var tip2 := Label.new()
	tip2.text = "💫 击中敌方造成操作颠倒：按W变S、按A变D"
	tip2.add_theme_font_size_override("font_size", 11)
	tip2.modulate = Color(1.0, 0.85, 0.3)
	tip_vbox.add_child(tip2)

	var tip3 := Label.new()
	tip3.text = "🌀 紫金白三色透光雷网，角色动作清晰显现"
	tip3.add_theme_font_size_override("font_size", 11)
	tip3.modulate = Color(0.7, 0.8, 1.0)
	tip_vbox.add_child(tip3)


## reset_state(): drops confusion bookkeeping. Scene entry only.
func reset_state() -> void:
	_active_confusions.clear()


func preload_assets() -> void:
	AudioManagerScript.preload_sounds([
		"res://assets/voice/RPGsounds_Kenney/OGG/chop.ogg",
		"res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg"
	])


func _execute_thunder(caster: CharacterBody3D, vfx_parent: Node) -> Dictionary:
	var center := caster.global_position

	# 1. Caster casting pose
	var raw_ch: Variant = caster.get("character")
	if raw_ch != null and is_instance_valid(raw_ch) and raw_ch.has_method("play"):
		raw_ch.call("play", "jump_start", 0.08)

	AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg", 0.9)

	# 2. Single unified ground electric sigil: persists smoothly across the entire cast duration
	_spawn_single_ground_sigil(center, thunder_radius, vfx_parent)

	# 3. Thunder strike after brief charge delay
	var tw := caster.create_tween()
	tw.tween_interval(thunder_delay)
	tw.tween_callback(func():
		if is_instance_valid(caster) and is_instance_valid(vfx_parent):
			_on_thunder_impact(caster, center, vfx_parent)
	)

	return {
		"success": true,
		"skill_id": get_id(),
		"center": center,
		"thunder_radius": thunder_radius,
		"confuse_duration": confuse_duration,
		"damage": damage
	}


## Spawns the single, continuous ground purple-gold sigil using PlaneMesh (perfect 1:1 circle).
func _spawn_single_ground_sigil(center: Vector3, radius: float, parent: Node) -> void:
	var sigil := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(radius * 2.0, radius * 2.0)
	sigil.mesh = pm
	sigil.position = center + Vector3.UP * 0.03

	var mat := ShaderMaterial.new()
	mat.shader = ThunderMagicSigilShader
	mat.set_shader_parameter("sigil_purple", Color(0.58, 0.18, 0.88, 0.95))
	mat.set_shader_parameter("sigil_gold", Color(1.0, 0.84, 0.38, 1.0))
	mat.set_shader_parameter("brightness", 1.10)
	mat.set_shader_parameter("spin_speed", 0.30)
	mat.set_shader_parameter("fade", 1.0)
	mat.set_shader_parameter("rune_threshold", 0.05)
	VfxTextures.bind(mat, "sigil_tex", VfxTextures.THUNDER_SIGIL, "", 1.0)
	sigil.material_override = mat
	parent.add_child(sigil)

	var tw := sigil.create_tween()
	# Smooth expand into view during pre-cast
	tw.tween_property(sigil, "scale", Vector3(1.0, 1.0, 1.0), thunder_delay).from(Vector3(0.1, 1.0, 0.1)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Sustain through the full extended strike duration
	tw.tween_interval(STRIKE_DURATION)
	# Smooth fade out at the end
	tw.tween_property(mat, "shader_parameter/fade", 0.0, 0.45).set_ease(Tween.EASE_IN)
	tw.tween_callback(sigil.queue_free)


func _on_thunder_impact(caster: CharacterBody3D, center: Vector3, parent: Node) -> void:
	AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/chop.ogg", 1.5)

	# 1. Main central translucent thunderbolt pillar
	_spawn_thunder_pillar(center, parent)

	# 2. Refined, reduced density 3D fine lightning web in the center (clear character visibility)
	_spawn_dense_fine_lightning(center, thunder_radius, parent)

	# 3. Overhead top ring with exquisite rotating rune lightning orbs and thick vertical strikes
	_spawn_overhead_ring_and_orbs(center, thunder_radius, parent)

	# 4. Ground electric blast shockwave
	_spawn_thunder_shockwave(center, thunder_radius, parent)

	# 5. Dynamic flash light
	_spawn_flash_light(center, parent)

	# 6. Target scan & confusion debuff application
	_apply_thunder_to_entities(caster, center, thunder_radius)


## Spawns the central vertical lightning pillar with translucent purple-gold-white triad colors.
func _spawn_thunder_pillar(center: Vector3, parent: Node) -> void:
	var pillar := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.9
	cyl.bottom_radius = 1.2
	cyl.height = SKY_HEIGHT * 1.5
	pillar.mesh = cyl
	pillar.position = center + Vector3.UP * (SKY_HEIGHT * 0.5)

	var mat := ShaderMaterial.new()
	mat.shader = LightningStrikeShader
	mat.set_shader_parameter("lightning_violet", Color(0.58, 0.18, 0.92, 0.75))
	mat.set_shader_parameter("lightning_gold", Color(0.95, 0.78, 0.32, 0.80))
	mat.set_shader_parameter("lightning_core", Color(1.25, 1.20, 1.35, 0.85))
	mat.set_shader_parameter("brightness", 1.15)
	mat.set_shader_parameter("transparency", 0.45)
	mat.set_shader_parameter("fade", 1.0)
	VfxTextures.bind(mat, "lightning_tex", VfxTextures.LIGHTNING, "tex_mix", 1.0)
	pillar.material_override = mat
	parent.add_child(pillar)

	var tw := pillar.create_tween().set_parallel(true)
	tw.tween_property(pillar, "scale", Vector3(1.2, 1.0, 1.2), 0.15).from(Vector3(0.4, 1.0, 0.4))
	tw.tween_property(mat, "shader_parameter/fade", 0.0, 0.45).set_ease(Tween.EASE_IN).set_delay(STRIKE_DURATION)
	tw.chain().tween_callback(pillar.queue_free)


## Spawns reduced density, lightweight 3D fine lightning web allowing clear character visibility.
func _spawn_dense_fine_lightning(center: Vector3, radius: float, parent: Node) -> void:
	var web_root := Node3D.new()
	web_root.position = center + Vector3.UP * (SKY_HEIGHT * 0.5)
	parent.add_child(web_root)

	# Lightweight outer 3D cylinder that keeps the central character area clear & visible
	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius * 0.38
	cyl.bottom_radius = radius * 0.45
	cyl.height = SKY_HEIGHT * 1.1
	cyl.radial_segments = 32
	mesh_inst.mesh = cyl

	var mat := ShaderMaterial.new()
	mat.shader = FineLightningWebShader
	mat.set_shader_parameter("arc_violet", Color(0.62, 0.20, 0.95, 0.70))
	mat.set_shader_parameter("arc_gold", Color(0.95, 0.78, 0.30, 0.75))
	mat.set_shader_parameter("arc_core", Color(1.20, 1.18, 1.30, 0.80))
	mat.set_shader_parameter("brightness", 1.10)
	mat.set_shader_parameter("transparency", 0.38)
	mat.set_shader_parameter("fade", 1.0)
	mat.set_shader_parameter("frequency", 22.0)
	mat.set_shader_parameter("jitter_speed", 38.0)
	VfxTextures.bind(mat, "lightning_tex", VfxTextures.LIGHTNING, "", 1.0)
	mesh_inst.material_override = mat
	web_root.add_child(mesh_inst)

	# Parallel tween to sustain through STRIKE_DURATION and synchronously destroy together
	var tw := web_root.create_tween().set_parallel(true)
	tw.tween_property(web_root, "scale", Vector3(1.12, 1.0, 1.12), 0.15).from(Vector3(0.5, 1.0, 0.5))
	tw.tween_property(mat, "shader_parameter/fade", 0.0, 0.45).set_ease(Tween.EASE_IN).set_delay(STRIKE_DURATION)
	tw.chain().tween_callback(web_root.queue_free)


## Spawns the overhead celestial ring and exquisite rotating rune lightning orbs that strike thick bolts down.
func _spawn_overhead_ring_and_orbs(center: Vector3, radius: float, parent: Node) -> void:
	var ring_radius := radius * 0.85
	var overhead_root := Node3D.new()
	overhead_root.position = center + Vector3.UP * SKY_HEIGHT
	parent.add_child(overhead_root)

	# 1. Top Celestial Halo Ring Mesh (PlaneMesh for perfect circle)
	var top_ring := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(ring_radius * 2.0, ring_radius * 2.0)
	top_ring.mesh = pm

	var ring_mat := ShaderMaterial.new()
	ring_mat.shader = CelestialRingShader
	ring_mat.set_shader_parameter("ring_violet", Color(0.62, 0.20, 0.95, 0.80))
	ring_mat.set_shader_parameter("ring_gold", Color(0.95, 0.78, 0.30, 0.85))
	ring_mat.set_shader_parameter("ring_core", Color(1.30, 1.25, 1.40, 0.85))
	ring_mat.set_shader_parameter("brightness", 1.15)
	ring_mat.set_shader_parameter("spin_speed", 1.5)
	ring_mat.set_shader_parameter("thickness", 0.07)
	ring_mat.set_shader_parameter("fade", 1.0)
	VfxTextures.bind(ring_mat, "ring_tex", VfxTextures.SHOCKWAVE_RING, "tex_mix", 0.35)
	top_ring.material_override = ring_mat
	overhead_root.add_child(top_ring)

	# 2. Rotating Orbit Container for Lightning Orbs and Thick Downward Lightning Beams
	var orbit_pivot := Node3D.new()
	overhead_root.add_child(orbit_pivot)

	var child_materials: Array[ShaderMaterial] = [ring_mat]

	for i in range(ORB_COUNT):
		var angle := float(i) * (TAU / float(ORB_COUNT))
		var orb_offset := Vector3(cos(angle) * ring_radius, 0.0, sin(angle) * ring_radius)

		var orb_anchor := Node3D.new()
		orb_anchor.position = orb_offset
		orbit_pivot.add_child(orb_anchor)

		# 2a. Exquisite Lightning Orb Sphere Mesh with Clear Golden & Purple Runes
		var orb_mesh := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.52
		sm.height = 1.04
		orb_mesh.mesh = sm

		var orb_mat := ShaderMaterial.new()
		orb_mat.shader = CelestialOrbShader
		orb_mat.set_shader_parameter("orb_base", Color(0.18, 0.05, 0.32, 0.95))
		orb_mat.set_shader_parameter("rune_gold", Color(1.0, 0.85, 0.26, 1.0))
		orb_mat.set_shader_parameter("rune_violet", Color(0.85, 0.38, 1.0, 1.0))
		orb_mat.set_shader_parameter("rim_glow", Color(0.65, 0.25, 0.95, 0.70))
		orb_mat.set_shader_parameter("brightness", 1.05)
		orb_mat.set_shader_parameter("spin_speed", 1.4)
		orb_mat.set_shader_parameter("fade", 1.0)
		VfxTextures.bind(orb_mat, "rune_tex", VfxTextures.THUNDER_SIGIL, "", 1.0)
		VfxTextures.bind(orb_mat, "lightning_tex", VfxTextures.LIGHTNING, "", 1.0)
		orb_mesh.material_override = orb_mat
		orb_anchor.add_child(orb_mesh)
		child_materials.append(orb_mat)

		# 2b. Exquisite mini equatorial rune halo around each orb
		var orb_halo := MeshInstance3D.new()
		var h_pm := PlaneMesh.new()
		h_pm.size = Vector2(1.35, 1.35)
		orb_halo.mesh = h_pm
		var halo_mat := ShaderMaterial.new()
		halo_mat.shader = CelestialRingShader
		halo_mat.set_shader_parameter("ring_violet", Color(0.62, 0.20, 0.95, 0.75))
		halo_mat.set_shader_parameter("ring_gold", Color(0.98, 0.82, 0.32, 0.85))
		halo_mat.set_shader_parameter("brightness", 1.05)
		halo_mat.set_shader_parameter("spin_speed", 2.5)
		halo_mat.set_shader_parameter("thickness", 0.10)
		halo_mat.set_shader_parameter("fade", 1.0)
		VfxTextures.bind(halo_mat, "ring_tex", VfxTextures.SHOCKWAVE_RING, "tex_mix", 0.4)
		orb_halo.material_override = halo_mat
		orb_anchor.add_child(orb_halo)
		child_materials.append(halo_mat)

		# 2c. Thick vertical lightning beam striking straight down from beneath the orb
		var bolt := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.24
		cyl.bottom_radius = 0.35
		cyl.height = SKY_HEIGHT
		bolt.mesh = cyl
		bolt.position = Vector3(0.0, -SKY_HEIGHT * 0.5 - 0.25, 0.0)

		var bolt_mat := ShaderMaterial.new()
		bolt_mat.shader = LightningStrikeShader
		bolt_mat.set_shader_parameter("lightning_violet", Color(0.62, 0.18, 0.95, 0.78))
		bolt_mat.set_shader_parameter("lightning_gold", Color(0.95, 0.78, 0.32, 0.82))
		bolt_mat.set_shader_parameter("lightning_core", Color(1.25, 1.20, 1.35, 0.88))
		bolt_mat.set_shader_parameter("brightness", 1.10)
		bolt_mat.set_shader_parameter("transparency", 0.58)
		bolt_mat.set_shader_parameter("fade", 1.0)
		VfxTextures.bind(bolt_mat, "lightning_tex", VfxTextures.LIGHTNING, "tex_mix", 1.0)
		bolt.material_override = bolt_mat
		orb_anchor.add_child(bolt)
		child_materials.append(bolt_mat)

		# 2d. Ground landing impact ring rotating in 100% exact sync directly below the orb & bolt
		var ground_ring := MeshInstance3D.new()
		var g_pm := PlaneMesh.new()
		g_pm.size = Vector2(1.6, 1.6)
		ground_ring.mesh = g_pm
		ground_ring.position = Vector3(0.0, -SKY_HEIGHT + 0.04, 0.0)

		var g_ring_mat := ShaderMaterial.new()
		g_ring_mat.shader = SonicRingShader
		g_ring_mat.set_shader_parameter("ring_color", Color(0.70, 0.32, 1.15, 0.85))
		g_ring_mat.set_shader_parameter("fade", 1.0)
		g_ring_mat.set_shader_parameter("thickness", 0.28)
		VfxTextures.bind(g_ring_mat, "ring_tex", VfxTextures.SHOCKWAVE_RING, "tex_mix", 1.0)
		ground_ring.material_override = g_ring_mat
		orb_anchor.add_child(ground_ring)
		child_materials.append(g_ring_mat)

	# Synchronous parallel animation and fade dissipation for ALL orb & ring elements across STRIKE_DURATION
	var tw := overhead_root.create_tween().set_parallel(true)
	tw.tween_property(orbit_pivot, "rotation:y", 3.6, STRIKE_DURATION + 0.45).from(0.0).set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(top_ring, "scale", Vector3(1.05, 1.0, 1.05), STRIKE_DURATION).from(Vector3(0.9, 1.0, 0.9))

	for mat in child_materials:
		tw.tween_property(mat, "shader_parameter/fade", 0.0, 0.45).set_ease(Tween.EASE_IN).set_delay(STRIKE_DURATION)

	tw.chain().tween_callback(overhead_root.queue_free)


func _spawn_thunder_shockwave(center: Vector3, radius: float, parent: Node) -> void:
	var ring := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(radius * 2.2, radius * 2.2)
	ring.mesh = pm
	ring.position = center + Vector3.UP * 0.05

	var ring_mat := ShaderMaterial.new()
	ring_mat.shader = SonicRingShader
	ring_mat.set_shader_parameter("ring_color", Color(0.65, 0.28, 1.15, 0.85))
	ring_mat.set_shader_parameter("fade", 1.0)
	ring_mat.set_shader_parameter("thickness", 0.22)
	VfxTextures.bind(ring_mat, "ring_tex", VfxTextures.SHOCKWAVE_RING, "tex_mix", 1.0)
	VfxTextures.bind_ramp(ring_mat, VfxTextures.RAMP_ARC, 0.9)
	ring.material_override = ring_mat
	parent.add_child(ring)

	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(1.2, 1.0, 1.2), 0.45).from(Vector3(0.1, 1.0, 0.1)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring_mat, "shader_parameter/fade", 0.0, 0.45).set_ease(Tween.EASE_IN).set_delay(0.20)
	tw.chain().tween_callback(ring.queue_free)


func _spawn_flash_light(center: Vector3, parent: Node) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(0.75, 0.65, 1.0)
	light.light_energy = 3.2
	light.omni_range = thunder_radius * 2.0
	light.position = center + Vector3.UP * 2.5
	parent.add_child(light)

	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 1.2, 0.20)
	tw.chain().tween_interval(STRIKE_DURATION)
	tw.chain().tween_property(light, "light_energy", 0.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(light.queue_free)


func _apply_thunder_to_entities(caster: CharacterBody3D, center: Vector3, radius: float) -> void:
	var tree := caster.get_tree()
	if tree == null:
		return

	var candidates: Array[Node] = tree.get_nodes_in_group("characters")
	if candidates.is_empty():
		var scene_root := tree.current_scene
		if scene_root != null:
			for ch in scene_root.find_children("*", "CharacterBody3D", true, false):
				candidates.append(ch)
			for ch in scene_root.find_children("*", "DummyTarget", true, false):
				candidates.append(ch)

	for b in candidates:
		if b == caster or caster.is_ancestor_of(b) or b.is_ancestor_of(caster):
			continue

		var b_pos: Vector3 = b.global_position if (b is Node3D) else Vector3.ZERO
		var dist := (b_pos - center).length()
		if dist > radius:
			continue

		# 1. Apply damage if supported
		if b.has_method("take_damage"):
			b.call("take_damage", damage, caster)
		elif b.has_method("take_hit"):
			b.call("take_hit", b_pos, damage, Vector3.UP)

		# 2. Trigger flinch / hit reaction
		if b.has_method("apply_hit_reaction"):
			b.call("apply_hit_reaction", "hit_chest", 0.08)
		elif b.has_method("play"):
			b.call("play", "hit_chest", 0.08)

		# 3. Apply confusion & inverted controls to the victim
		_apply_confusion_debuff(b, confuse_duration)


func _apply_confusion_debuff(target: Node, dur: float) -> void:
	if target == null or not is_instance_valid(target):
		return

	var t_id := target.get_instance_id()
	if _active_confusions.has(t_id):
		dispel_actor(target as CharacterBody3D if (target is CharacterBody3D) else null)

	# Mark metadata for PlayerIntentSource inverted controls
	target.set_meta("confusion_debuff", true)

	# In 3D space: attach overhead electric stun sparks and 3D localized spatial distortion bubble
	var stun_sparks := _create_stun_sparks(target as Node3D)
	if stun_sparks != null:
		target.add_child(stun_sparks)

	var warp_bubble := _create_3d_warp_bubble(target as Node3D)
	if warp_bubble != null:
		target.add_child(warp_bubble)

	var tw := target.create_tween()
	_active_confusions[t_id] = {
		"target": target,
		"stun_sparks": stun_sparks,
		"warp_bubble": warp_bubble,
		"tween": tw
	}

	# Hold confusion duration then smoothly fade out 3D effects
	tw.tween_interval(maxf(dur - 0.5, 0.1))
	if warp_bubble != null and is_instance_valid(warp_bubble):
		var b_mat: Material = warp_bubble.material_override
		if b_mat is ShaderMaterial:
			tw.tween_property(b_mat, "shader_parameter/fade", 0.0, 0.5).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		_clear_single_confusion(t_id)
	)


func _create_3d_warp_bubble(target: Node3D) -> Node3D:
	if target == null:
		return null
	var bubble := MeshInstance3D.new()
	bubble.name = "StunDistortionBubble"
	var sphere := SphereMesh.new()
	sphere.radius = 1.05
	sphere.height = 2.1
	bubble.mesh = sphere
	bubble.position.y = 1.05

	var mat := ShaderMaterial.new()
	mat.shader = SpatialWarp3DShader
	mat.set_shader_parameter("warp_color", Color(0.55, 0.25, 0.95, 0.75))
	mat.set_shader_parameter("core_color", Color(1.6, 1.5, 2.2, 1.0))
	mat.set_shader_parameter("fade", 1.0)
	mat.set_shader_parameter("wave_speed", 8.0)
	mat.set_shader_parameter("wave_freq", 12.0)
	VfxTextures.bind(mat, "noise_tex", VfxTextures.SHOCKWAVE_RING, "noise_mix", 0.85)
	bubble.material_override = mat
	return bubble


func _create_stun_sparks(target: Node3D) -> Node3D:
	if target == null:
		return null
	var sparks_root := Node3D.new()
	sparks_root.name = "StunElectricSparks"
	var y_offset := 1.9
	if target.has_method("get_head_position"):
		y_offset = (target.call("get_head_position") as Vector3).y - target.global_position.y + 0.35
	sparks_root.position.y = y_offset

	var particles := CPUParticles3D.new()
	particles.amount = 16
	particles.lifetime = 0.6
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.4
	particles.gravity = Vector3(0.0, 0.5, 0.0)
	particles.initial_velocity_min = 0.5
	particles.initial_velocity_max = 1.2
	particles.scale_amount_min = 0.04
	particles.scale_amount_max = 0.08
	particles.color = Color(0.75, 0.55, 1.0, 0.95)

	var p_mesh := QuadMesh.new()
	p_mesh.size = Vector2(0.06, 0.06)
	var p_mat := StandardMaterial3D.new()
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p_mat.albedo_color = Color(0.75, 0.55, 1.0, 0.95)
	p_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	particles.mesh = p_mesh
	particles.material_override = p_mat

	sparks_root.add_child(particles)
	return sparks_root


func dispel_actor(actor: CharacterBody3D) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	_clear_single_confusion(actor.get_instance_id())


static func _clear_single_confusion(t_id: int) -> void:
	if not _active_confusions.has(t_id):
		return
	var data: Dictionary = _active_confusions[t_id]
	_active_confusions.erase(t_id)

	var target: Node = data.get("target")
	if target != null and is_instance_valid(target):
		if target.has_meta("confusion_debuff"):
			target.remove_meta("confusion_debuff")

	var warp_bubble: Node = data.get("warp_bubble")
	if warp_bubble != null and is_instance_valid(warp_bubble):
		warp_bubble.queue_free()

	var stun_sparks: Node = data.get("stun_sparks")
	if stun_sparks != null and is_instance_valid(stun_sparks):
		stun_sparks.queue_free()

	var tw: Tween = data.get("tween")
	if tw != null and tw.is_valid():
		tw.kill()


func get_warmup_materials() -> Array:
	var m_pillar := ShaderMaterial.new()
	m_pillar.shader = LightningStrikeShader
	var m_warp := ShaderMaterial.new()
	m_warp.shader = SpatialWarp3DShader
	var m_ring := ShaderMaterial.new()
	m_ring.shader = SonicRingShader
	var m_sigil := ShaderMaterial.new()
	m_sigil.shader = ThunderMagicSigilShader
	var m_celestial_ring := ShaderMaterial.new()
	m_celestial_ring.shader = CelestialRingShader
	var m_orb := ShaderMaterial.new()
	m_orb.shader = CelestialOrbShader
	var m_fine_web := ShaderMaterial.new()
	m_fine_web.shader = FineLightningWebShader
	return [m_pillar, m_warp, m_ring, m_sigil, m_celestial_ring, m_orb, m_fine_web]
