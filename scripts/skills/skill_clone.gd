extends "res://scripts/skills/skill_base.gd"
## 分身·深渊黑煞浓雾幻象 (Dense Shadow Phantom Clone).
## 召唤时在角色头顶与身躯周围爆发一团真正浓厚、深邃不透光的3层立体黑雾，将角色完全吞没笼罩，
## 随后黑雾向外剧烈翻滚、膨胀弥散化开，双生幻影破雾而出；零物理开销，实时同步骨骼动作与姿态。

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const AnimPipelineScript = preload("res://tools/anim_pipeline.gd")
const SonicRingShader = preload("res://shaders/sonic_boom_ring.gdshader")
const ShadowShroudMistShader = preload("res://shaders/shadow_shroud_mist.gdshader")

## Clone lifetime (s).
var clone_duration: float = 8.0

## Active clone tracking: caster_id -> { "clone": VisualMirrorClone, "timer": Tween }
static var _active_clones: Dictionary = {}
static var _scene_cache: Dictionary = {}

## Pure visual follower node performing lateral axis-symmetric mirror translation and real-time bone pose sync.
class VisualMirrorClone extends Node3D:
	var caster: CharacterBody3D = null
	var caster_skel: Skeleton3D = null
	var clone_skel: Skeleton3D = null
	var origin_pos: Vector3 = Vector3.ZERO
	var origin_yaw: float = 0.0
	var forward_vec: Vector3 = Vector3.FORWARD
	var right_vec: Vector3 = Vector3.RIGHT
	var is_active: bool = true

	func setup(p_caster: CharacterBody3D, p_visual: Node3D) -> void:
		caster = p_caster
		origin_pos = caster.global_position
		origin_yaw = caster.rotation.y
		
		forward_vec = Vector3(-sin(origin_yaw), 0.0, -cos(origin_yaw)).normalized()
		right_vec = Vector3(cos(origin_yaw), 0.0, -sin(origin_yaw)).normalized()
		
		global_position = origin_pos
		rotation.y = origin_yaw
		
		add_child(p_visual)
		
		caster_skel = AnimPipelineScript.first_of_class(caster, "Skeleton3D") as Skeleton3D
		clone_skel = AnimPipelineScript.first_of_class(p_visual, "Skeleton3D") as Skeleton3D
		
		var anim_player := AnimPipelineScript.first_of_class(p_visual, "AnimationPlayer") as AnimationPlayer
		if anim_player != null:
			anim_player.stop()
		var anim_tree := AnimPipelineScript.first_of_class(p_visual, "AnimationTree") as AnimationTree
		if anim_tree != null:
			anim_tree.active = false

	func _process(_delta: float) -> void:
		if not is_active or caster == null or not is_instance_valid(caster):
			queue_free()
			return
		
		var cur_pos := caster.global_position
		var diff := cur_pos - origin_pos
		var fwd_dist := diff.dot(forward_vec)
		var right_dist := diff.dot(right_vec)
		var y_dist := diff.y
		
		global_position = origin_pos + (forward_vec * fwd_dist) - (right_vec * right_dist) + (Vector3.UP * y_dist)
		
		var cur_yaw := caster.rotation.y
		var delta_yaw := cur_yaw - origin_yaw
		rotation.y = origin_yaw - delta_yaw
		
		if caster_skel != null and clone_skel != null and is_instance_valid(caster_skel):
			var b_count := mini(caster_skel.get_bone_count(), clone_skel.get_bone_count())
			for b in range(b_count):
				clone_skel.set_bone_pose_rotation(b, caster_skel.get_bone_pose_rotation(b))
				clone_skel.set_bone_pose_position(b, caster_skel.get_bone_pose_position(b))
				clone_skel.set_bone_pose_scale(b, caster_skel.get_bone_pose_scale(b))

func get_id() -> String:
	return "clone"

func get_name() -> String:
	return "👥 分身 (暗影黑雾幻象)"

func get_title() -> String:
	return "👥 分身配置 (SHADOW PHANTOM CLONE)"

func get_params() -> Dictionary:
	return {
		"clone_duration": clone_duration
	}

func set_param(key: String, value: Variant) -> void:
	match key:
		"clone_duration": clone_duration = float(value)

func cast(caster: CharacterBody3D, _intent_dir: Vector3, vfx_parent: Node, _is_spectator: bool = false) -> Dictionary:
	if caster == null or not is_instance_valid(caster):
		return {}
	var c_id := caster.get_instance_id()
	if _active_clones.has(c_id):
		_despawn_clone(c_id, vfx_parent)

	var clone := _spawn_visual_clone(caster, vfx_parent)
	if clone == null:
		return {}
	_active_clones[c_id] = { "clone": clone }
	_start_clone_timer(c_id, clone_duration, vfx_parent)

	AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/cloth1.ogg", 1.0)

	return {
		"success": true,
		"skill_id": get_id(),
		"from_pos": caster.global_position,
		"clone_duration": clone_duration
	}

func replay(caster: CharacterBody3D, record: Dictionary, vfx_parent: Node) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	var c_id := caster.get_instance_id()
	if _active_clones.has(c_id):
		_despawn_clone(c_id, vfx_parent)

	var clone := _spawn_visual_clone(caster, vfx_parent)
	if clone == null:
		return
	var dur: float = float(record.get("clone_duration", clone_duration))
	_active_clones[c_id] = { "clone": clone }
	_start_clone_timer(c_id, dur, vfx_parent)

func get_replay_hold_time(record: Dictionary) -> float:
	return maxf(float(record.get("clone_duration", clone_duration)) + 0.5, 2.0)

func dispel_actor(actor: CharacterBody3D) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	_despawn_clone(actor.get_instance_id(), null)

func build_config_panel(container: VBoxContainer, on_changed: Callable) -> void:
	var dur_lbl := Label.new()
	dur_lbl.text = "分身持续 (Duration): %.1fs" % clone_duration
	dur_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(dur_lbl)

	var dur_slider := HSlider.new()
	dur_slider.min_value = 2.0
	dur_slider.max_value = 20.0
	dur_slider.step = 0.5
	dur_slider.value = clone_duration
	dur_slider.value_changed.connect(func(v: float):
		clone_duration = v
		dur_lbl.text = "分身持续 (Duration): %.1fs" % v
		on_changed.call("clone_duration", v)
	)
	container.add_child(dur_slider)

	var tip_panel := PanelContainer.new()
	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.08, 0.04, 0.12, 0.90)
	t_style.set_corner_radius_all(6)
	t_style.set_border_width_all(1)
	t_style.border_color = Color(0.4, 0.25, 0.55, 0.6)
	t_style.set_content_margin_all(8)
	tip_panel.add_theme_stylebox_override("panel", t_style)
	container.add_child(tip_panel)

	var tip_vbox := VBoxContainer.new()
	tip_vbox.add_theme_constant_override("separation", 4)
	tip_panel.add_child(tip_vbox)

	var tip1 := Label.new()
	tip1.text = "🌑 召唤时3层浓密深渊黑雾瞬间完全笼罩角色，随后向外翻滚散开"
	tip1.add_theme_font_size_override("font_size", 11)
	tip1.modulate = Color(0.8, 0.65, 0.95)
	tip_vbox.add_child(tip1)

	var tip2 := Label.new()
	tip2.text = "🪞 纯正深邃不透明黑雾质感，告别薄雾与透明泡泡"
	tip2.add_theme_font_size_override("font_size", 11)
	tip2.modulate = Color(0.65, 0.75, 0.9)
	tip_vbox.add_child(tip2)

	var tip3 := Label.new()
	tip3.text = "↔️ 零物理开销，实时同步动作，A/D位移镜像对称"
	tip3.add_theme_font_size_override("font_size", 11)
	tip3.modulate = Color(0.9, 0.8, 0.3)
	tip_vbox.add_child(tip3)

## reset_state(): drops live-clone bookkeeping. _scene_cache is an asset cache, kept.
func reset_state() -> void:
	_active_clones.clear()


func preload_assets() -> void:
	AudioManagerScript.preload_sounds([
		"res://assets/voice/RPGsounds_Kenney/OGG/cloth1.ogg"
	])
	for i in [1, 2, 3, 4, 5, 8, 9, 10, 11, 12]:
		var h_id := "hero_%d" % i
		var p := "res://assets/characters/%s/%s.tscn" % [h_id, h_id]
		if ResourceLoader.exists(p) and not _scene_cache.has(h_id):
			_scene_cache[h_id] = load(p) as PackedScene

func _spawn_visual_clone(caster: CharacterBody3D, vfx_parent: Node) -> VisualMirrorClone:
	if caster == null or not is_instance_valid(caster):
		return null
	if vfx_parent == null or not is_instance_valid(vfx_parent):
		return null

	var hero_id: String = str(caster.get_meta("hero_id", "hero_1"))
	var p_scene: PackedScene = _scene_cache.get(hero_id, null)
	if p_scene == null:
		var scene_path := "res://assets/characters/%s/%s.tscn" % [hero_id, hero_id]
		if ResourceLoader.exists(scene_path):
			p_scene = load(scene_path) as PackedScene
			_scene_cache[hero_id] = p_scene
		elif _scene_cache.has("hero_1"):
			p_scene = _scene_cache["hero_1"]
		elif ResourceLoader.exists("res://assets/characters/hero_1/hero_1.tscn"):
			p_scene = load("res://assets/characters/hero_1/hero_1.tscn") as PackedScene
			_scene_cache["hero_1"] = p_scene

	if p_scene == null:
		return null
	var visual := p_scene.instantiate() as Node3D
	if visual == null:
		return null

	var clone := VisualMirrorClone.new()
	clone.name = "VisualMirrorClone"
	vfx_parent.add_child(clone)
	clone.setup(caster, visual)

	_spawn_clone_split_vfx(caster.global_position, vfx_parent)
	return clone

## 召唤时在角色头顶与身躯周围爆发一团真正浓厚、深邃不透光的3层立体黑雾，随后向外翻滚散开
static func _spawn_clone_split_vfx(center: Vector3, parent: Node) -> void:
	if parent == null or not is_instance_valid(parent):
		return

	var root := Node3D.new()
	root.name = "DenseShadowShroudMist"
	root.position = center
	parent.add_child(root)

	# 1. 地面暗影激波环
	var qm := QuadMesh.new()
	qm.size = Vector2(3.5, 3.5)
	var ring := MeshInstance3D.new()
	ring.mesh = qm
	ring.rotation.x = -PI * 0.5
	ring.position.y = 0.04

	var ring_mat := ShaderMaterial.new()
	ring_mat.shader = SonicRingShader
	ring_mat.set_shader_parameter("ring_color", Color(0.04, 0.02, 0.06, 0.98))
	ring_mat.set_shader_parameter("fade", 1.0)
	ring_mat.set_shader_parameter("thickness", 0.22)
	VfxTextures.bind(ring_mat, "ring_tex", VfxTextures.SHOCKWAVE_RING, "tex_mix", 1.0)
	ring.material_override = ring_mat
	root.add_child(ring)

	# 2. 构造 3 层同心嵌套的浓厚实心黑雾群（彻底遮蔽角色，不留透明缝隙）
	var layers_info: Array[Dictionary] = [
		{ "radius": 2.10, "height": 3.0, "y_off": 1.15, "density": 6.5, "speed": 3.0, "opacity": 1.4 }, # 外层翻滚烟团
		{ "radius": 1.55, "height": 2.4, "y_off": 1.10, "density": 8.0, "speed": 3.5, "opacity": 1.6 }, # 中层浓黑烟幔
		{ "radius": 1.05, "height": 1.8, "y_off": 1.05, "density": 10.0, "speed": 4.0, "opacity": 1.8 }  # 核心实心墨煞
	]

	var mist_mats: Array[ShaderMaterial] = []
	var mist_nodes: Array[MeshInstance3D] = []

	for info in layers_info:
		var node := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = info["radius"]
		sm.height = info["height"]
		sm.radial_segments = 24
		sm.rings = 12
		node.mesh = sm
		node.position.y = info["y_off"]

		var m_mat := ShaderMaterial.new()
		m_mat.shader = ShadowShroudMistShader
		m_mat.set_shader_parameter("color_deep_ink", Color(0.02, 0.01, 0.03, 0.98))
		m_mat.set_shader_parameter("color_charcoal_smoke", Color(0.06, 0.04, 0.08, 0.95))
		m_mat.set_shader_parameter("color_shadow_fringe", Color(0.14, 0.10, 0.16, 0.85))
		m_mat.set_shader_parameter("speed", info["speed"])
		m_mat.set_shader_parameter("smoke_density", info["density"])
		m_mat.set_shader_parameter("expansion_progress", 0.0)
		m_mat.set_shader_parameter("core_opacity", info["opacity"])
		m_mat.set_shader_parameter("fade", 1.0)
		node.material_override = m_mat

		mist_mats.append(m_mat)
		mist_nodes.append(node)
		root.add_child(node)

	# 动画：3层实心黑雾瞬间爆发笼罩角色（0.06s），随后向外剧烈翻滚散开（0.65s）
	ring.scale = Vector3(0.2, 0.2, 0.2)
	for n in mist_nodes:
		n.scale = Vector3(0.25, 0.25, 0.25)

	var tw := root.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3.ONE, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float):
		if is_instance_valid(ring_mat):
			ring_mat.set_shader_parameter("fade", v)
	, 1.0, 0.0, 0.38).set_ease(Tween.EASE_IN)

	for i in range(mist_nodes.size()):
		var n := mist_nodes[i]
		var mat := mist_mats[i]
		var target_scale := Vector3(1.5, 1.35, 1.5) if i == 0 else Vector3(1.3, 1.25, 1.3)
		tw.tween_property(n, "scale", target_scale, 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_method(func(p: float):
			if is_instance_valid(mat):
				mat.set_shader_parameter("expansion_progress", p)
		, 0.0, 1.0, 0.65).set_ease(Tween.EASE_IN_OUT)

	tw.chain().tween_callback(root.queue_free)

## 分身到期消散时的浓墨暗影消融
static func _spawn_clone_dissolve_vfx(pos: Vector3, parent: Node) -> void:
	if parent == null or not is_instance_valid(parent):
		return

	var mist_cloud := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.6
	sm.height = 2.4
	sm.radial_segments = 24
	sm.rings = 12
	mist_cloud.mesh = sm
	mist_cloud.position = pos + Vector3.UP * 1.0

	var mist_mat := ShaderMaterial.new()
	mist_mat.shader = ShadowShroudMistShader
	mist_mat.set_shader_parameter("color_deep_ink", Color(0.02, 0.01, 0.03, 0.98))
	mist_mat.set_shader_parameter("color_charcoal_smoke", Color(0.08, 0.05, 0.10, 0.95))
	mist_mat.set_shader_parameter("color_shadow_fringe", Color(0.16, 0.11, 0.18, 0.85))
	mist_mat.set_shader_parameter("speed", 2.6)
	mist_mat.set_shader_parameter("smoke_density", 7.0)
	mist_mat.set_shader_parameter("expansion_progress", 0.15)
	mist_mat.set_shader_parameter("core_opacity", 1.5)
	mist_mat.set_shader_parameter("fade", 1.0)
	mist_cloud.material_override = mist_mat
	parent.add_child(mist_cloud)

	var tw := mist_cloud.create_tween().set_parallel(true)
	tw.tween_property(mist_cloud, "scale", Vector3(1.4, 1.3, 1.4), 0.48).from(Vector3(0.5, 0.5, 0.5)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(p: float):
		if is_instance_valid(mist_mat):
			mist_mat.set_shader_parameter("expansion_progress", p)
	, 0.15, 1.0, 0.48).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mist_cloud.queue_free)

func get_warmup_materials() -> Array:
	var m_ring := ShaderMaterial.new()
	m_ring.shader = SonicRingShader
	VfxTextures.bind(m_ring, "ring_tex", VfxTextures.SHOCKWAVE_RING, "tex_mix", 1.0)

	var m_mist := ShaderMaterial.new()
	m_mist.shader = ShadowShroudMistShader

	return [m_ring, m_mist]

func _start_clone_timer(caster_id: int, dur: float, vfx_parent: Node) -> void:
	if not _active_clones.has(caster_id):
		return
	var entry: Dictionary = _active_clones[caster_id]
	var clone: VisualMirrorClone = entry.get("clone")
	if clone == null or not is_instance_valid(clone):
		return

	var tw: Tween = clone.create_tween()
	tw.tween_interval(maxf(dur, 0.2))
	tw.tween_callback(func():
		_despawn_clone(caster_id, vfx_parent)
	)

static func _despawn_clone(caster_id: int, vfx_parent: Node = null) -> void:
	if not _active_clones.has(caster_id):
		return
	var entry: Dictionary = _active_clones[caster_id]
	_active_clones.erase(caster_id)
	var clone: VisualMirrorClone = entry.get("clone")
	if clone != null and is_instance_valid(clone):
		clone.is_active = false
		if vfx_parent != null and is_instance_valid(vfx_parent):
			_spawn_clone_dissolve_vfx(clone.global_position, vfx_parent)
		clone.queue_free()

## Removes every active clone.
static func clear_all() -> void:
	for c_id in _active_clones.keys():
		_despawn_clone(c_id, null)
