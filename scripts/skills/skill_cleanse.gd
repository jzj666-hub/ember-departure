extends "res://scripts/skills/skill_base.gd"
## Skill 11: Holy Cleanse (✨ 圣洁净化).
## Instantly dispels all negative crowd control effects (roots, pulls, blinds, knockdowns, slows).
## Grants complete CC immunity and unstoppability for duration.
## VFX: Radiant sacred golden-white expansion halo, ascending holy light particles, and golden protective barrier.

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const SkillRegistryScript = preload("res://scripts/skills/skill_registry.gd")

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

	# 1. Expanding Radiant Halo
	var halo := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.9
	torus.rings = 24
	torus.ring_segments = 12
	halo.mesh = torus
	halo.position.y = 0.8

	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.albedo_color = Color(1.0, 0.95, 0.65, 0.95)
	halo_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	halo.material_override = halo_mat
	root_vfx.add_child(halo)

	# 2. Protective Holy Light Sphere Shell
	var sphere := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.85
	sm.height = 1.7
	sphere.mesh = sm
	sphere.position.y = 0.85

	var sphere_mat := StandardMaterial3D.new()
	sphere_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere_mat.albedo_color = Color(1.0, 0.88, 0.35, 0.35)
	sphere_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	sphere.material_override = sphere_mat
	root_vfx.add_child(sphere)

	# 3. Holy Sparkles / Runes
	var parts := CPUParticles3D.new()
	parts.amount = 36
	parts.lifetime = 0.7
	parts.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	parts.emission_sphere_radius = 0.8
	parts.direction = Vector3.UP
	parts.spread = 45.0
	parts.gravity = Vector3(0.0, 3.5, 0.0)
	parts.initial_velocity_min = 1.5
	parts.initial_velocity_max = 3.5
	var p_mesh := BoxMesh.new()
	p_mesh.size = Vector3(0.06, 0.06, 0.06)
	parts.mesh = p_mesh
	var p_mat := StandardMaterial3D.new()
	p_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	p_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p_mat.albedo_color = Color(1.0, 0.96, 0.7, 0.9)
	parts.material_override = p_mat
	parts.position.y = 0.85
	root_vfx.add_child(parts)
	parts.emitting = true

	# Animations
	var burst_tw := root_vfx.create_tween().set_parallel(true)
	burst_tw.tween_property(halo, "scale", Vector3(3.2, 1.0, 3.2), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	burst_tw.tween_property(halo_mat, "albedo_color:a", 0.0, 0.40).set_ease(Tween.EASE_IN)

	# Shield follow and pulsing
	var loop_tw := root_vfx.create_tween().set_parallel(true)
	loop_tw.tween_method(func(_t: float):
		if is_instance_valid(caster) and is_instance_valid(root_vfx):
			root_vfx.global_position = caster.global_position
			sphere.rotate_y(0.05)
	, 0.0, 1.0, dur)

	loop_tw.chain().tween_property(sphere_mat, "albedo_color:a", 0.0, 0.25)
	loop_tw.chain().tween_callback(root_vfx.queue_free)

	return root_vfx


func preload_assets() -> void:
	AudioManagerScript.preload_sounds([
		"res://assets/voice/RPGsounds_Kenney/OGG/cloth1.ogg"
	])
