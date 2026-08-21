extends "res://scripts/skills/skill_base.gd"
## Skill 8: Mist Obscurity (昏暗/迷雾障眼).
## Affects enemies within radius. Caster immune.
## Vision radius and duration scale linearly with distance from cast center.
## 3D depth-based shader with max render priority produces pure absolute darkness outside remaining vision sphere.

const AudioManagerScript = preload("res://scripts/audio_manager.gd")

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
	return "🌑 昏暗 (迷雾障眼)"


func get_title() -> String:
	return "🌑 昏暗配置 (DARKNESS / MIST OBSCURITY)"


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
	evision_slider.max_value = 15.0
	evision_slider.step = 0.5
	evision_slider.value = edge_vision
	evision_slider.value_changed.connect(func(v: float):
		edge_vision = v
		evision_lbl.text = "边缘残存视野 (Edge Vision): %.1fm" % v
		on_changed.call("edge_vision", v)
	)
	container.add_child(evision_slider)

	# 中心最长致盲时间
	var ctime_lbl := Label.new()
	ctime_lbl.text = "核心致盲时长 (Center Blind Time): %.1fs" % center_blind_time
	ctime_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(ctime_lbl)

	var ctime_slider := HSlider.new()
	ctime_slider.min_value = 2.0
	ctime_slider.max_value = 15.0
	ctime_slider.step = 0.5
	ctime_slider.value = center_blind_time
	ctime_slider.value_changed.connect(func(v: float):
		center_blind_time = v
		ctime_lbl.text = "核心致盲时长 (Center Blind Time): %.1fs" % v
		on_changed.call("center_blind_time", v)
	)
	container.add_child(ctime_slider)

	# 边缘最短致盲时间
	var etime_lbl := Label.new()
	etime_lbl.text = "边缘致盲时长 (Edge Blind Time): %.1fs" % edge_blind_time
	etime_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(etime_lbl)

	var etime_slider := HSlider.new()
	etime_slider.min_value = 0.5
	etime_slider.max_value = 6.0
	etime_slider.step = 0.5
	etime_slider.value = edge_blind_time
	etime_slider.value_changed.connect(func(v: float):
		edge_blind_time = v
		etime_lbl.text = "边缘致盲时长 (Edge Blind Time): %.1fs" % v
		on_changed.call("edge_blind_time", v)
	)
	container.add_child(etime_slider)

	# 说明面板
	var tip_panel := PanelContainer.new()
	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.08, 0.09, 0.13, 0.90)
	t_style.set_corner_radius_all(6)
	t_style.set_border_width_all(1)
	t_style.border_color = Color(0.4, 0.7, 1.0, 0.55)
	t_style.set_content_margin_all(8)
	tip_panel.add_theme_stylebox_override("panel", t_style)
	container.add_child(tip_panel)

	var tip_vbox := VBoxContainer.new()
	tip_vbox.add_theme_constant_override("separation", 4)
	tip_panel.add_child(tip_vbox)

	var tip1 := Label.new()
	tip1.text = "🌑 施法者自身不受影响；半径内其余人视野被3D深度物理距离压缩"
	tip1.add_theme_font_size_override("font_size", 11)
	tip1.modulate = Color(0.6, 0.9, 1.0)
	tip_vbox.add_child(tip1)

	var tip2 := Label.new()
	tip2.text = "⬛ 越靠近中心：视野越狭窄、致盲时间越长 (严格线性)"
	tip2.add_theme_font_size_override("font_size", 11)
	tip2.modulate = Color(1.0, 0.85, 0.3)
	tip_vbox.add_child(tip2)

	var tip3 := Label.new()
	tip3.text = "👁️ 残存视野外全部陷入绝对纯黑(完全遮蔽地面网格与人物轮廓)；[F2] 切换受害者体验"
	tip3.add_theme_font_size_override("font_size", 11)
	tip3.modulate = Color(0.7, 0.8, 0.9)
	tip_vbox.add_child(tip3)


static func _ensure_blackout(parent: Node) -> void:
	if _blackout != null and is_instance_valid(_blackout):
		return
	_blackout = VisionBlackout.new()
	_blackout.name = "MistVisionBlackout"
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
	vfx.name = "MistCastVFX"
	parent.add_child(vfx)
	vfx.global_position = caster.global_position

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.2
	torus.outer_radius = 0.5
	torus.rings = 32
	torus.ring_segments = 16
	ring.mesh = torus
	ring.position.y = 0.08

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.08, 0.05, 0.15, 0.85)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = mat
	vfx.add_child(ring)

	var ground_disc := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.5
	cylinder.bottom_radius = 0.5
	cylinder.height = 0.02
	ground_disc.mesh = cylinder
	ground_disc.position.y = 0.04

	var disc_mat := StandardMaterial3D.new()
	disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_mat.albedo_color = Color(0.03, 0.02, 0.06, 0.70)
	ground_disc.material_override = disc_mat
	vfx.add_child(ground_disc)

	var tw := vfx.create_tween().set_parallel(true)
	var max_scale := mist_radius * 2.0
	tw.tween_property(ring, "scale", Vector3(max_scale, 1.0, max_scale), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ground_disc, "scale", Vector3(max_scale, 1.0, max_scale), 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.65).set_ease(Tween.EASE_IN)
	tw.tween_property(disc_mat, "albedo_color:a", 0.0, 0.65).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(vfx.queue_free)


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
	var torus := TorusMesh.new()
	torus.inner_radius = 0.65
	torus.outer_radius = 0.85
	torus.rings = 24
	torus.ring_segments = 12
	ring.mesh = torus
	ring.position.y = 0.9

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.12, 0.06, 0.20, 0.75)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = mat
	aura.add_child(ring)

	target.add_child(aura)

	var tw := aura.create_tween().set_loops()
	tw.tween_property(ring, "rotation:y", TAU, 2.5).from(0.0)
	return aura


## 3D world-space depth-based darkness post-processor.
class VisionBlackout extends Node3D:
	var blinds: Dictionary = {}

	var _mesh_inst: MeshInstance3D = null
	var _mat: ShaderMaterial = null


	func _ready() -> void:
		_build_mesh()


	func _build_mesh() -> void:
		_mesh_inst = MeshInstance3D.new()
		_mesh_inst.name = "PostProcessMesh"
		var quad := QuadMesh.new()
		quad.size = Vector2(2.0, 2.0)
		_mesh_inst.mesh = quad
		_mesh_inst.extra_cull_margin = 16384.0
		_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		_mat = ShaderMaterial.new()
		_mat.shader = _make_shader()
		_mat.render_priority = 127
		_mesh_inst.material_override = _mat
		_mesh_inst.visible = false
		add_child(_mesh_inst)


	func _process(delta: float) -> void:
		_tick(delta)
		_render()


	func _tick(delta: float) -> void:
		if blinds.is_empty():
			return
		for id in blinds.keys().duplicate():
			var entry: Dictionary = blinds[id]
			var rem: float = float(entry.get("remaining", 0.0)) - delta
			entry["remaining"] = rem
			if rem <= 0.0:
				_release_aura(entry)
				blinds.erase(id)


	## aura 挂在被致盲者身上，目标先一步被 free 时它也随之释放；
	## 对已释放对象做 `as` 转换会报错，必须先校验 is_instance_valid。
	func _release_aura(entry: Dictionary) -> void:
		var aura_v: Variant = entry.get("aura")
		if aura_v != null and is_instance_valid(aura_v):
			(aura_v as Node3D).queue_free()


	func clear_target(actor: Node) -> void:
		if actor == null:
			return
		var id := actor.get_instance_id()
		if blinds.has(id):
			var entry: Dictionary = blinds[id]
			_release_aura(entry)
			blinds.erase(id)


	func _render() -> void:
		if _mesh_inst == null or _mat == null or not is_inside_tree():
			return
		var vp := get_viewport()
		if vp == null:
			return
		var cam := vp.get_camera_3d()
		if cam == null:
			_mesh_inst.visible = false
			return

		var target_v: Variant = cam.get("target")
		var target := target_v as Node3D if target_v is Node3D else null
		if target == null or not blinds.has(target.get_instance_id()):
			_mesh_inst.visible = false
			return

		var entry: Dictionary = blinds[target.get_instance_id()]
		var vision: float = float(entry.get("vision", 4.0))
		var rem: float = float(entry.get("remaining", 1.0))
		var actor_center := target.global_position + Vector3(0.0, 0.9, 0.0)

		var is_active: float = 1.0 if rem > 0.0 else 0.0
		var soft_edge: float = clampf(vision * 0.15, 0.2, 0.4)

		_mat.set_shader_parameter("u_actor_pos", actor_center)
		_mat.set_shader_parameter("u_vision_radius", vision)
		_mat.set_shader_parameter("u_soft_edge", soft_edge)
		_mat.set_shader_parameter("u_blind_active", is_active)
		_mesh_inst.visible = true


	func _make_shader() -> Shader:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled, blend_mix;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

uniform vec3 u_actor_pos = vec3(0.0);
uniform float u_vision_radius = 2.0;
uniform float u_soft_edge = 0.35;
uniform float u_blind_active = 1.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	if (u_blind_active < 0.01) {
		discard;
	}

	float raw_depth = texture(depth_texture, SCREEN_UV).x;
	vec3 scene_color = texture(screen_texture, SCREEN_UV).rgb;

	// Reconstruct 3D world position from depth buffer
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos.xyz /= view_pos.w;
	vec4 world_pos = INV_VIEW_MATRIX * vec4(view_pos.xyz, 1.0);

	float dist = distance(world_pos.xyz, u_actor_pos);

	ALPHA = 1.0;
	// Beyond vision radius, far plane, sky or invalid values: 100% PURE PITCH BLACK
	if (raw_depth >= 0.99999 || raw_depth <= 0.000001 || isinf(dist) || isnan(dist) || dist >= u_vision_radius) {
		ALBEDO = vec3(0.0);
	} else if (dist <= max(u_vision_radius - u_soft_edge, 0.0)) {
		ALBEDO = scene_color;
	} else {
		// Steep quadratic falloff to absolute pitch black
		float factor = 1.0 - clamp((dist - (u_vision_radius - u_soft_edge)) / max(u_soft_edge, 0.001), 0.0, 1.0);
		factor = factor * factor;
		ALBEDO = scene_color * factor;
	}
}
"""
		return sh


func preload_assets() -> void:
	AudioManagerScript.preload_sounds([
		"res://assets/voice/RPGsounds_Kenney/OGG/clothBelt2.ogg"
	])


func get_warmup_materials() -> Array:
	if _blackout != null and _blackout._mat != null:
		return [_blackout._mat]
	var mat := ShaderMaterial.new()
	mat.shader = VisionBlackout.new()._make_shader()
	return [mat]


func dispel_actor(actor: CharacterBody3D) -> void:
	if actor != null and is_instance_valid(actor) and _blackout != null and is_instance_valid(_blackout):
		_blackout.clear_target(actor)
