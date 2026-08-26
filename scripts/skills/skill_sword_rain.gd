extends "res://scripts/skills/skill_base.gd"
## Skill 14: Sword Rain / 万剑归宗 (太乙剑阵·御剑飞霄·天降剑雨).
## Summons an ancient rotating celestial sword array high in the sky using authentic FBX weapon meshes.
## Cascades rapid volleys of energy-infused flying blades plunging into the target area in front of the caster.
## Deals continuous AoE damage, interrupts enemy attacks, applies hit-flinch stagger, and embeds shaking swords into the terrain.

const AudioManagerScript = preload("res://scripts/audio_manager.gd")
const SigilRingShader = preload("res://shaders/sigil_ring.gdshader")
const SonicRingShader = preload("res://shaders/sonic_boom_ring.gdshader")
const ThunderMagicSigilShader = preload("res://shaders/thunder_magic_sigil.gdshader")
const RibbonTrailShader = preload("res://shaders/golden_ribbon_trail.gdshader")
const SwordAuraShader = preload("res://shaders/sword_blade_aura.gdshader")
const GroundFractureShader = preload("res://shaders/ground_fracture_glow.gdshader")
const ShockwaveDomeShader = preload("res://shaders/shockwave_dome.gdshader")
const HeavenlyPillarShader = preload("res://shaders/heavenly_pillar.gdshader")
const FineLightningWebShader = preload("res://shaders/fine_lightning_web.gdshader")

const CRACK_TEX_PATH := "res://assets/VFX_assets/ground_crack_texture.png"
const FLASH_GLOW_PATH := "res://assets/VFX_assets/flash_glow.png"
const LIGHTNING_TEX_PATH := "res://assets/VFX_assets/lightning_texture.png"
const SMOKE_TEX_PATH := "res://assets/VFX_assets/smoke_texture.png"

var sword_count: int = 32
var barrage_duration: float = 1.80
var strike_radius: float = 4.8
var strike_distance: float = 6.0
var cast_range: float = 18.0
var sword_scale: float = 1.45
var damage_per_sword: float = 16.0
var theme_index: int = 0
var model_index: int = 0

## Color Hierarchy (60-30-10 Rule):
## 60% Dominant Base/Atmosphere (sigil & outer wave, dark/rich)
## 30% Secondary Flow/Trail (streamlined ribbon & blade stream, vivid)
## 10% Accent Specular/Core (sharp blade hotspot & impact burst, warm/cool contrast)
const THEME_PRESETS: Array[Dictionary] = [
	{
		"name": "🌟 纯阳金辉 (沉敛古金 60% ➔ 炽烈阳炎 30% ➔ 极昼圣白 10%)",
		"sigil": Color(0.78, 0.45, 0.10, 0.90),
		"blade_glow": Color(1.0, 0.65, 0.15, 0.85),
		"core": Color(1.35, 1.30, 1.15, 1.0),
		"trail": Color(1.0, 0.35, 0.05, 0.95),
		"impact_core": Color(1.40, 1.35, 1.15, 1.0),
		"impact_mid": Color(0.95, 0.45, 0.08, 0.90),
		"impact_outer": Color(0.60, 0.12, 0.04, 0.80),
		"crack_amber": Color(1.0, 0.55, 0.12, 1.0),
		"crack_crimson": Color(0.55, 0.12, 0.03, 1.0),
		"scorch": Color(0.20, 0.10, 0.04, 0.95)
	},
	{
		"name": "💠 青莲天青 (幽夜苍蓝 60% ➔ 碧翡青莲 30% ➔ 暖金微芒 10%)",
		"sigil": Color(0.08, 0.28, 0.55, 0.90),
		"blade_glow": Color(0.12, 0.88, 0.72, 0.85),
		"core": Color(1.30, 1.22, 1.05, 1.0), # Warm gold core against cold cyan body
		"trail": Color(0.06, 0.75, 0.92, 0.95),
		"impact_core": Color(1.35, 1.28, 1.10, 1.0),
		"impact_mid": Color(0.10, 0.85, 0.70, 0.90),
		"impact_outer": Color(0.04, 0.25, 0.65, 0.80),
		"crack_amber": Color(0.15, 0.90, 0.75, 1.0),
		"crack_crimson": Color(0.04, 0.30, 0.55, 1.0),
		"scorch": Color(0.04, 0.10, 0.16, 0.95)
	},
	{
		"name": "🩸 诛仙血煞 (暗渊墨血 60% ➔ 猩红流火 30% ➔ 炽金焚心 10%)",
		"sigil": Color(0.35, 0.03, 0.06, 0.90),
		"blade_glow": Color(0.92, 0.12, 0.16, 0.85),
		"core": Color(1.35, 1.18, 0.85, 1.0), # Blazing gold hotspot against blood red
		"trail": Color(0.85, 0.05, 0.12, 0.95),
		"impact_core": Color(1.40, 1.25, 0.90, 1.0),
		"impact_mid": Color(0.90, 0.12, 0.10, 0.90),
		"impact_outer": Color(0.40, 0.02, 0.05, 0.80),
		"crack_amber": Color(0.95, 0.22, 0.08, 1.0),
		"crack_crimson": Color(0.42, 0.02, 0.04, 1.0),
		"scorch": Color(0.16, 0.03, 0.04, 0.95)
	},
	{
		"name": "🟣 幽冥紫极 (暗夜深紫 60% ➔ 霓虹丁香 30% ➔ 极光天青 10%)",
		"sigil": Color(0.24, 0.05, 0.38, 0.90),
		"blade_glow": Color(0.82, 0.18, 0.92, 0.85),
		"core": Color(0.95, 1.25, 1.35, 1.0), # Aurora cyan/white core against purple
		"trail": Color(0.70, 0.08, 0.90, 0.95),
		"impact_core": Color(1.05, 1.30, 1.40, 1.0),
		"impact_mid": Color(0.78, 0.15, 0.85, 0.90),
		"impact_outer": Color(0.30, 0.03, 0.50, 0.80),
		"crack_amber": Color(0.80, 0.20, 0.90, 1.0),
		"crack_crimson": Color(0.32, 0.04, 0.48, 1.0),
		"scorch": Color(0.12, 0.03, 0.15, 0.95)
	},
	{
		"name": "❄️ 霜华玄冰 (极地钴蓝 60% ➔ 冰晶天蓝 30% ➔ 纯阳微金 10%)",
		"sigil": Color(0.08, 0.22, 0.48, 0.90),
		"blade_glow": Color(0.30, 0.75, 0.95, 0.85),
		"core": Color(1.30, 1.25, 1.15, 1.0),
		"trail": Color(0.18, 0.60, 0.95, 0.95),
		"impact_core": Color(1.35, 1.30, 1.20, 1.0),
		"impact_mid": Color(0.28, 0.70, 0.95, 0.90),
		"impact_outer": Color(0.06, 0.25, 0.60, 0.80),
		"crack_amber": Color(0.35, 0.75, 0.95, 1.0),
		"crack_crimson": Color(0.06, 0.22, 0.50, 1.0),
		"scorch": Color(0.05, 0.08, 0.16, 0.95)
	},
	{
		"name": "🖤 玄墨水墨 (焦墨玄黑 60% ➔ 宣纸钢灰 30% ➔ 朱砂炽白 10%)",
		"sigil": Color(0.12, 0.12, 0.15, 0.95),
		"blade_glow": Color(0.60, 0.65, 0.72, 0.85),
		"core": Color(1.35, 1.25, 1.15, 1.0),
		"trail": Color(0.40, 0.42, 0.46, 0.95),
		"impact_core": Color(1.35, 1.25, 1.15, 1.0),
		"impact_mid": Color(0.55, 0.58, 0.62, 0.90),
		"impact_outer": Color(0.12, 0.12, 0.15, 0.80),
		"crack_amber": Color(0.65, 0.70, 0.75, 1.0),
		"crack_crimson": Color(0.12, 0.12, 0.15, 1.0),
		"scorch": Color(0.08, 0.08, 0.09, 0.95)
	}
]

const MODEL_PRESETS: Array[Dictionary] = [
	{ "name": "✨ 万剑齐鸣·混搭全剑 (Random All Models)", "path": "" },
	{ "name": "🗡️ 直锋长剑 (Straight Longsword)", "path": "res://assets/combat_tools/Straight Longsword.fbx" },
	{ "name": "🔮 诛仙魔剑 (Magic Sword)", "path": "res://assets/combat_tools/Magic Sword.fbx" },
	{ "name": "⚜️ 使徒巨剑 (Apostle GreatSword)", "path": "res://assets/combat_tools/Apostle GreatSword.fbx" },
	{ "name": "🐉 苍龙鳞剑 (Dragon Scales Sword)", "path": "res://assets/combat_tools/Dragon Scales Sword.fbx" },
	{ "name": "✝️ 圣光十字剑 (Cross Great Sword)", "path": "res://assets/combat_tools/Cross Great Sword.fbx" },
	{ "name": "⚔️ 混元百炼剑 (Common Sword)", "path": "res://assets/combat_tools/Common Sword.fbx" },
	{ "name": "🛡️ 骑士阔剑 (Longsword)", "path": "res://assets/combat_tools/Longsword.fbx" },
	{ "name": "🖤 玄铁重剑 (Black Steel Sword)", "path": "res://assets/combat_tools/Black Steel Sword.fbx" }
]

const SWORD_FBX_PATHS: Array[String] = [
	"res://assets/combat_tools/Straight Longsword.fbx",
	"res://assets/combat_tools/Magic Sword.fbx",
	"res://assets/combat_tools/Apostle GreatSword.fbx",
	"res://assets/combat_tools/Dragon Scales Sword.fbx",
	"res://assets/combat_tools/Cross Great Sword.fbx",
	"res://assets/combat_tools/Common Sword.fbx",
	"res://assets/combat_tools/Longsword.fbx",
	"res://assets/combat_tools/Black Steel Sword.fbx"
]

## Cached PackedScenes & geometric calibration info
static var _cached_sword_data: Array[Dictionary] = []
static var _ground_sigil_mat: ShaderMaterial = null
static var _sky_sigil_mat: ShaderMaterial = null
static var _shockwave_mat: ShaderMaterial = null
static var _trail_mat: ShaderMaterial = null
static var _blade_aura_mat: ShaderMaterial = null
static var _ground_crack_mat: ShaderMaterial = null
static var _shockwave_dome_mat: ShaderMaterial = null
static var _heavenly_pillar_mat: ShaderMaterial = null
static var _lightning_web_mat: ShaderMaterial = null

static var _quad_mesh: QuadMesh = null
static var _plane_mesh: PlaneMesh = null
static var _sphere_mesh: SphereMesh = null
static var _cylinder_mesh: CylinderMesh = null

static var _cached_crack_tex: Texture2D = null
static var _cached_flash_tex: Texture2D = null
static var _cached_lightning_tex: Texture2D = null


func get_id() -> String:
	return "sword_rain"


func get_name() -> String:
	return "⚔️ 万剑归宗 (太乙剑阵·御剑飞霄·天降剑雨)"


func get_title() -> String:
	return "⚔️ 万剑归宗配置 (HEAVENLY SWORD RAIN)"


func get_params() -> Dictionary:
	return {
		"sword_count": sword_count,
		"barrage_duration": barrage_duration,
		"strike_radius": strike_radius,
		"strike_distance": strike_distance,
		"sword_scale": sword_scale,
		"damage_per_sword": damage_per_sword,
		"theme_index": theme_index,
		"model_index": model_index
	}


func set_param(key: String, value: Variant) -> void:
	match key:
		"sword_count": sword_count = int(value)
		"barrage_duration": barrage_duration = float(value)
		"strike_radius": strike_radius = float(value)
		"strike_distance": strike_distance = float(value)
		"sword_scale": sword_scale = float(value)
		"damage_per_sword": damage_per_sword = float(value)
		"theme_index": theme_index = clampi(int(value), 0, THEME_PRESETS.size() - 1)
		"model_index": model_index = clampi(int(value), 0, MODEL_PRESETS.size() - 1)


func cast(caster: CharacterBody3D, intent_dir: Vector3, vfx_parent: Node, _is_spectator: bool = false) -> Dictionary:
	if caster == null or not is_instance_valid(caster):
		return {}
	var target_pos := _calculate_target_position(caster, intent_dir)
	return _execute_sword_rain(caster, target_pos, vfx_parent)


## Aim-support: allows SkillAim ground targeting
func cast_at(caster: CharacterBody3D, target_pos: Vector3, vfx_parent: Node, _is_spectator: bool = false) -> Dictionary:
	if caster == null or not is_instance_valid(caster):
		return {}
	return _execute_sword_rain(caster, target_pos, vfx_parent)


func replay(caster: CharacterBody3D, record: Dictionary, vfx_parent: Node) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	var target_pos: Vector3 = record.get("target_pos", caster.global_position + (caster.global_transform.basis.z if caster.is_inside_tree() else Vector3.FORWARD) * strike_distance)
	_execute_sword_rain(caster, target_pos, vfx_parent)


func get_replay_hold_time(_record: Dictionary) -> float:
	return barrage_duration + 1.4


func preload_assets() -> void:
	_ensure_cached_resources()
	AudioManagerScript.preload_sound("res://assets/voice/RPGsounds_Kenney/OGG/drawKnife1.ogg")
	AudioManagerScript.preload_sound("res://assets/voice/RPGsounds_Kenney/OGG/drawKnife2.ogg")
	AudioManagerScript.preload_sound("res://assets/voice/RPGsounds_Kenney/OGG/drawKnife3.ogg")
	AudioManagerScript.preload_sound("res://assets/voice/RPGsounds_Kenney/OGG/knifeSlice.ogg")
	AudioManagerScript.preload_sound("res://assets/voice/RPGsounds_Kenney/OGG/knifeSlice2.ogg")
	AudioManagerScript.preload_sound("res://assets/voice/RPGsounds_Kenney/OGG/chop.ogg")
	AudioManagerScript.preload_sound("res://assets/voice/RPGsounds_Kenney/OGG/metalClick.ogg")
	AudioManagerScript.preload_sound("res://assets/voice/RPGsounds_Kenney/OGG/metalLatch.ogg")
	AudioManagerScript.preload_sound("res://assets/voice/RPGsounds_Kenney/OGG/metalPot1.ogg")
	AudioManagerScript.preload_sound("res://assets/voice/RPGsounds_Kenney/OGG/metalPot2.ogg")
	AudioManagerScript.preload_sound("res://assets/voice/RPGsounds_Kenney/OGG/metalPot3.ogg")


func get_warmup_materials() -> Array:
	_ensure_cached_resources()
	var mats: Array = []
	if _ground_sigil_mat != null:
		mats.append(_ground_sigil_mat)
	if _sky_sigil_mat != null:
		mats.append(_sky_sigil_mat)
	if _shockwave_mat != null:
		mats.append(_shockwave_mat)
	if _trail_mat != null:
		mats.append(_trail_mat)
	if _blade_aura_mat != null:
		mats.append(_blade_aura_mat)
	if _ground_crack_mat != null:
		mats.append(_ground_crack_mat)
	if _shockwave_dome_mat != null:
		mats.append(_shockwave_dome_mat)
	if _heavenly_pillar_mat != null:
		mats.append(_heavenly_pillar_mat)
	if _lightning_web_mat != null:
		mats.append(_lightning_web_mat)
	return mats


func dispel_actor(_actor: CharacterBody3D) -> void:
	pass


func reset_state() -> void:
	pass


func build_config_panel(container: VBoxContainer, on_changed: Callable) -> void:
	# 配色主题
	var theme_lbl := Label.new()
	theme_lbl.text = "🎨 剑灵法阵灵韵配色 (Sword Theme Preset):"
	theme_lbl.add_theme_font_size_override("font_size", 12)
	theme_lbl.modulate = Color(1.0, 0.85, 0.5)
	container.add_child(theme_lbl)

	var theme_opt := OptionButton.new()
	for i in range(THEME_PRESETS.size()):
		theme_opt.add_item(THEME_PRESETS[i]["name"], i)
	theme_opt.selected = theme_index
	theme_opt.item_selected.connect(func(idx: int):
		theme_index = idx
		on_changed.call("theme_index", idx)
	)
	container.add_child(theme_opt)

	# 飞剑模型切换
	var model_lbl := Label.new()
	model_lbl.text = "🗡️ 降临神兵模型 (Weapon Model Choice):"
	model_lbl.add_theme_font_size_override("font_size", 12)
	model_lbl.modulate = Color(0.65, 0.90, 1.0)
	container.add_child(model_lbl)

	var model_opt := OptionButton.new()
	for i in range(MODEL_PRESETS.size()):
		model_opt.add_item(MODEL_PRESETS[i]["name"], i)
	model_opt.selected = model_index
	model_opt.item_selected.connect(func(idx: int):
		model_index = idx
		on_changed.call("model_index", idx)
	)
	container.add_child(model_opt)

	# 飞剑总数量
	var count_lbl := Label.new()
	count_lbl.text = "凌霄飞剑总数 (Total Blades): %d 柄" % sword_count
	count_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(count_lbl)

	var count_slider := HSlider.new()
	count_slider.min_value = 12
	count_slider.max_value = 72
	count_slider.step = 2
	count_slider.value = sword_count
	count_slider.value_changed.connect(func(v: float):
		sword_count = int(v)
		count_lbl.text = "凌霄飞剑总数 (Total Blades): %d 柄" % sword_count
		on_changed.call("sword_count", sword_count)
	)
	container.add_child(count_slider)

	# 剑雨倾泻时长
	var dur_lbl := Label.new()
	dur_lbl.text = "剑雨倾泻时长 (Barrage Duration): %.2fs" % barrage_duration
	dur_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(dur_lbl)

	var dur_slider := HSlider.new()
	dur_slider.min_value = 0.6
	dur_slider.max_value = 3.5
	dur_slider.step = 0.1
	dur_slider.value = barrage_duration
	dur_slider.value_changed.connect(func(v: float):
		barrage_duration = v
		dur_lbl.text = "剑雨倾泻时长 (Barrage Duration): %.2fs" % v
		on_changed.call("barrage_duration", v)
	)
	container.add_child(dur_slider)

	# 剑阵波及半径
	var rad_lbl := Label.new()
	rad_lbl.text = "剑阵落点半径 (Array Radius): %.1fm" % strike_radius
	rad_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(rad_lbl)

	var rad_slider := HSlider.new()
	rad_slider.min_value = 2.0
	rad_slider.max_value = 10.0
	rad_slider.step = 0.5
	rad_slider.value = strike_radius
	rad_slider.value_changed.connect(func(v: float):
		strike_radius = v
		rad_lbl.text = "剑阵落点半径 (Array Radius): %.1fm" % v
		on_changed.call("strike_radius", v)
	)
	container.add_child(rad_slider)

	# 剑阵落点距离
	var dist_lbl := Label.new()
	dist_lbl.text = "施法落点距离 (Cast Distance): %.1fm" % strike_distance
	dist_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(dist_lbl)

	var dist_slider := HSlider.new()
	dist_slider.min_value = 2.0
	dist_slider.max_value = 15.0
	dist_slider.step = 0.5
	dist_slider.value = strike_distance
	dist_slider.value_changed.connect(func(v: float):
		strike_distance = v
		dist_lbl.text = "施法落点距离 (Cast Distance): %.1fm" % v
		on_changed.call("strike_distance", v)
	)
	container.add_child(dist_slider)

	# 飞剑体型缩放
	var scale_lbl := Label.new()
	scale_lbl.text = "飞剑体型缩放 (Blade Scale): %.2fx" % sword_scale
	scale_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(scale_lbl)

	var scale_slider := HSlider.new()
	scale_slider.min_value = 0.7
	scale_slider.max_value = 2.8
	scale_slider.step = 0.05
	scale_slider.value = sword_scale
	scale_slider.value_changed.connect(func(v: float):
		sword_scale = v
		scale_lbl.text = "飞剑体型缩放 (Blade Scale): %.2fx" % v
		on_changed.call("sword_scale", v)
	)
	container.add_child(scale_slider)

	# 单剑伤害
	var dmg_lbl := Label.new()
	dmg_lbl.text = "单柄剑刃伤害 (Damage per Blade): %d" % int(damage_per_sword)
	dmg_lbl.add_theme_font_size_override("font_size", 12)
	container.add_child(dmg_lbl)

	var dmg_slider := HSlider.new()
	dmg_slider.min_value = 2.0
	dmg_slider.max_value = 60.0
	dmg_slider.step = 1.0
	dmg_slider.value = damage_per_sword
	dmg_slider.value_changed.connect(func(v: float):
		damage_per_sword = v
		dmg_lbl.text = "单柄剑刃伤害 (Damage per Blade): %d" % int(v)
		on_changed.call("damage_per_sword", v)
	)
	container.add_child(dmg_slider)

	# 提示面板
	var tip_panel := PanelContainer.new()
	var t_style := StyleBoxFlat.new()
	t_style.bg_color = Color(0.08, 0.10, 0.14, 0.90)
	t_style.set_corner_radius_all(6)
	t_style.set_border_width_all(1)
	t_style.border_color = Color(0.45, 0.75, 1.0, 0.65)
	t_style.set_content_margin_all(8)
	tip_panel.add_theme_stylebox_override("panel", t_style)
	container.add_child(tip_panel)

	var tip_vbox := VBoxContainer.new()
	tip_vbox.add_theme_constant_override("separation", 4)
	tip_panel.add_child(tip_vbox)

	var tip1 := Label.new()
	tip1.text = "⚔️ 原版 FBX 神兵渲染：完美对齐剑尖轴向与材质纹理，支持全神兵混搭与单剑挑选"
	tip1.add_theme_font_size_override("font_size", 11)
	tip1.modulate = Color(1.0, 0.90, 0.75)
	tip_vbox.add_child(tip1)

	var tip2 := Label.new()
	tip2.text = "🌌 凌霄剑阵急坠：高空飞剑大阵旋转汇聚，流星音爆俯冲，地面插剑震颤与灵爆消散"
	tip2.add_theme_font_size_override("font_size", 11)
	tip2.modulate = Color(0.85, 1.0, 0.90)
	tip_vbox.add_child(tip2)

	var tip3 := Label.new()
	tip3.text = "🎯 锁定受击硬直：高频持续多段伤害与打断压制，支持 SkillAim 自由选点"
	tip3.add_theme_font_size_override("font_size", 11)
	tip3.modulate = Color(0.70, 0.90, 1.0)
	tip_vbox.add_child(tip3)


func _calculate_target_position(caster: CharacterBody3D, intent_dir: Vector3) -> Vector3:
	var start_pos := caster.global_position if caster.is_inside_tree() else caster.position
	var fwd := intent_dir
	fwd.y = 0.0
	if fwd.length_squared() > 0.01:
		fwd = fwd.normalized()
	else:
		var basis_z := caster.global_transform.basis.z if caster.is_inside_tree() else caster.transform.basis.z
		basis_z.y = 0.0
		fwd = basis_z.normalized() if basis_z.length_squared() > 0.01 else Vector3.FORWARD

	# Check for locked nearby enemy or dummy target in front
	var tree := caster.get_tree() if caster.is_inside_tree() else null
	if tree != null:
		var scene_root := tree.current_scene
		if scene_root != null:
			var closest_target: Node3D = null
			var closest_dist := 999.0
			var candidates: Array = []
			for ch in scene_root.find_children("*", "CharacterBody3D", true, false):
				candidates.append(ch)
			for ch in scene_root.find_children("*", "DummyTarget", true, false):
				candidates.append(ch)

			for b in candidates:
				if b == null or not is_instance_valid(b) or b == caster or b.name == "Ground":
					continue
				if not (b is Node3D):
					continue
				var n3d := b as Node3D
				var to_b := n3d.global_position - start_pos
				var dist := to_b.length()
				if dist <= strike_distance + strike_radius + 2.0:
					var dot := fwd.dot(to_b.normalized())
					if dot > 0.35 and dist < closest_dist:
						closest_dist = dist
						closest_target = n3d

			if closest_target != null:
				var tpos := closest_target.global_position
				tpos.y = start_pos.y
				return tpos

	return start_pos + fwd * strike_distance


func _execute_sword_rain(caster: CharacterBody3D, target_pos: Vector3, parent: Node) -> Dictionary:
	_ensure_cached_resources()

	# Play cast animation on character
	var raw_ch: Variant = caster.get("character")
	if raw_ch != null and is_instance_valid(raw_ch) and raw_ch.has_method("play"):
		raw_ch.call("play", "attack_heavy", 0.08)

	var theme: Dictionary = THEME_PRESETS[theme_index]
	var root := Node3D.new()
	root.name = "SwordRainVFX_%d" % Time.get_ticks_msec()
	parent.add_child(root)
	root.global_position = target_pos

	var start_pos := caster.global_position if caster.is_inside_tree() else caster.position

	# Sound: Sword drawing / array activation
	AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/drawKnife3.ogg", 1.0)
	AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/metalClick.ogg", 1.15)

	# 1. Caster Ground Sigil (under caster feet)
	var caster_sigil := _create_ground_sigil(root, start_pos, 2.4, theme["sigil"], 1.8)

	# 2. Target Ground Array Sigil (under target area)
	var target_sigil := _create_ground_sigil(root, target_pos, strike_radius * 2.3, theme["sigil"], barrage_duration + 1.4)

	# 3. Overhead Celestial Formation Gate in sky
	var sky_height := 14.0
	var diff := target_pos - start_pos
	diff.y = 0.0
	var fwd_dir := diff.normalized() if diff.length_squared() > 0.01 else Vector3.FORWARD
	var sky_pos := target_pos + Vector3(0.0, sky_height, 0.0) - fwd_dir * 3.2
	var launch_dir := (target_pos - sky_pos).normalized()

	# Oriented strictly perpendicular to launch_dir so portal disc directly faces target
	var sky_ring := _create_sky_formation_ring(root, sky_pos, launch_dir, strike_radius * 2.6, theme)

	# 4. Energy Convergence Windup (前摇能量汇聚 0.32s)
	var windup_time := 0.32
	var active_blades := sword_count
	var time_step := barrage_duration / float(active_blades)

	var embedded_positions: Array[Vector3] = []

	# Wrap sky_ring in Array so lambda captures the container (never freed), not the Node3D
	var sky_ref: Array = [sky_ring]

	for i in range(active_blades):
		var is_finisher := (i == active_blades - 1)
		var delay := windup_time + float(i) * time_step + randf_range(0.0, time_step * 0.30)
		var t_tween := root.create_tween()
		t_tween.tween_interval(delay)
		t_tween.tween_callback(func():
			if root == null or not is_instance_valid(root):
				return
			var _sr_raw = sky_ref[0]
			if _sr_raw != null and is_instance_valid(_sr_raw):
				_apply_sky_recoil(_sr_raw, launch_dir)
			var hit_loc := _spawn_single_falling_sword(root, caster, sky_pos, target_pos, launch_dir, theme, is_finisher)
			if hit_loc != Vector3.ZERO:
				embedded_positions.append(hit_loc)
		)

	# Final Array Resonance Detonation
	var res_tw := root.create_tween()
	res_tw.tween_interval(windup_time + barrage_duration + 0.35)
	res_tw.tween_callback(func():
		if root == null or not is_instance_valid(root):
			return
		_trigger_array_resonance(root, target_pos, theme, embedded_positions)
	)

	# Root cleanup tween
	var clean_tw := root.create_tween()
	clean_tw.tween_interval(windup_time + barrage_duration + 3.2)
	clean_tw.tween_callback(func():
		if root != null and is_instance_valid(root):
			root.queue_free()
	)

	return {
		"target_pos": target_pos,
		"theme_index": theme_index,
		"model_index": model_index,
		"sword_count": sword_count
	}


func _create_ground_sigil(parent: Node3D, pos: Vector3, size: float, col: Color, lifetime: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _plane_mesh
	mi.scale = Vector3(size, 1.0, size)
	parent.add_child(mi)
	mi.global_position = pos + Vector3(0.0, 0.03, 0.0)

	var mat := ShaderMaterial.new()
	mat.shader = ThunderMagicSigilShader
	mat.set_shader_parameter("sigil_color", col)
	mat.set_shader_parameter("spin_speed", 1.8)
	mat.set_shader_parameter("fade", 0.0)
	mi.material_override = mat

	var tw := mi.create_tween()
	tw.tween_property(mat, "shader_parameter/fade", 1.0, 0.25)
	tw.tween_interval(lifetime - 0.5)
	tw.tween_property(mat, "shader_parameter/fade", 0.0, 0.4)
	tw.tween_callback(mi.queue_free)
	return mi


func _create_sky_formation_ring(parent: Node3D, pos: Vector3, launch_dir: Vector3, size: float, theme: Dictionary) -> Node3D:
	var sky_node := Node3D.new()
	parent.add_child(sky_node)
	sky_node.global_position = pos

	# Strictly orient sky_node facing along launch_dir
	sky_node.look_at(pos + launch_dir, Vector3.UP)

	var mi := MeshInstance3D.new()
	mi.mesh = _plane_mesh
	mi.scale = Vector3(size, 1.0, size)
	# PlaneMesh normal is +Y; rotate +90 on X so normal aligns with -Z (launch_dir)
	mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	sky_node.add_child(mi)

	var mat := ShaderMaterial.new()
	mat.shader = SigilRingShader
	mat.set_shader_parameter("sigil_color", theme["sigil"])
	mat.set_shader_parameter("spin_speed", 1.2)
	mat.set_shader_parameter("fade", 0.0)
	mi.material_override = mat

	# Windup Sequence: Scale up from center with accelerating rotation
	sky_node.scale = Vector3(0.05, 0.05, 0.05)
	sky_node.set_meta("base_pos", sky_node.position)
	var tw := sky_node.create_tween()
	tw.set_parallel(true)
	tw.tween_property(sky_node, "scale", Vector3.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "shader_parameter/spin_speed", 4.2, 0.32).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "shader_parameter/fade", 1.0, 0.22)

	# Hold during full barrage + windup margin, then fade out gracefully
	tw.chain().tween_interval(barrage_duration + 0.4)
	tw.chain().tween_property(mat, "shader_parameter/fade", 0.0, 0.65)
	tw.chain().tween_callback(sky_node.queue_free)
	return sky_node


func _apply_sky_recoil(sky_node: Node3D, launch_dir: Vector3) -> void:
	if sky_node == null or not is_instance_valid(sky_node):
		return
	var base_pos: Vector3 = sky_node.get_meta("base_pos", sky_node.position)
	var recoil_tw := sky_node.create_tween()
	recoil_tw.tween_property(sky_node, "position", base_pos - launch_dir * 0.18, 0.04).set_ease(Tween.EASE_OUT)
	recoil_tw.tween_property(sky_node, "position", base_pos, 0.08).set_ease(Tween.EASE_IN_OUT)


func _spawn_single_falling_sword(root: Node3D, caster: CharacterBody3D, sky_center: Vector3, target_center: Vector3, default_launch_dir: Vector3, theme: Dictionary, is_finisher: bool) -> Vector3:
	if root == null or not is_instance_valid(root) or _cached_sword_data.is_empty():
		return Vector3.ZERO

	# Calculate randomized drop origin in sky and landing point on ground
	var angle := randf_range(0.0, TAU)
	var r := 0.0 if is_finisher else sqrt(randf()) * strike_radius
	var offset := Vector3(cos(angle) * r, 0.0, sin(angle) * r)

	var land_pos := target_center + offset
	# Emerges strictly from the sky formation gate
	var spawn_pos := sky_center + offset * 0.35 + Vector3(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4), randf_range(-0.4, 0.4))

	# Sword model selection
	var entry: Dictionary = _cached_sword_data[0]
	if model_index > 0 and model_index < MODEL_PRESETS.size():
		var idx := model_index - 1
		if idx < _cached_sword_data.size():
			entry = _cached_sword_data[idx]
	else:
		var r_idx := randi() % _cached_sword_data.size()
		entry = _cached_sword_data[r_idx]

	var sword_node := Node3D.new()
	root.add_child(sword_node)
	sword_node.global_position = spawn_pos

	# Wrapper for centering the authentic FBX model
	var wrapper := Node3D.new()
	sword_node.add_child(wrapper)

	var scn: PackedScene = entry["scene"]
	var fbx_inst: Node3D = scn.instantiate() as Node3D
	wrapper.add_child(fbx_inst)

	# Offset the instantiated model so its true geometric center is at (0, 0, 0)
	var center_off: Vector3 = entry["center_offset"]
	fbx_inst.position = -center_off

	# Scale wrapper to standard sword scale (Finisher is 2.3x giant divine blade)
	var scale_mult: float = entry["scale_factor"] * sword_scale * (2.30 if is_finisher else randf_range(1.0, 1.18))
	wrapper.scale = Vector3(scale_mult, scale_mult, scale_mult)

	# Rotate wrapper by +90 on X so sword tip (+Y in FBX) points forward along -Z (flight direction)
	wrapper.rotation_degrees = Vector3(90.0, 0.0, 0.0)

	# --- 1. Streamlined Blade-Edge Aura (单条顺向刃口灵芒，不刺眼，保留金属剪影) ---
	var aura_root := Node3D.new()
	sword_node.add_child(aura_root)

	var aura_mat := ShaderMaterial.new()
	aura_mat.shader = SwordAuraShader
	aura_mat.set_shader_parameter("aura_color", theme["blade_glow"])
	aura_mat.set_shader_parameter("core_color", theme["core"])
	aura_mat.set_shader_parameter("intensity", 1.45 if is_finisher else 1.25)
	aura_mat.set_shader_parameter("fade", 1.0)

	var aura_len := 2.4 * (scale_mult / 0.8)
	var aura_w := 0.16 * (scale_mult / 0.8)

	# Aligned strictly along blade's vertical plane (no horizontal cross-quad)
	var aura1 := MeshInstance3D.new()
	aura1.mesh = _quad_mesh
	aura1.scale = Vector3(aura_w, aura_len, 1.0)
	aura1.material_override = aura_mat
	aura1.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	aura_root.add_child(aura1)

	# --- 2. Hypersonic Trailing Ribbon behind Blade (顺着剑柄向后延伸的流光尾迹) ---
	var trail := MeshInstance3D.new()
	trail.mesh = _quad_mesh
	var trail_s := sword_scale * (2.0 if is_finisher else 1.10)
	trail.scale = Vector3(0.28 * trail_s, 3.2 * trail_s, 1.0)
	trail.position = Vector3(0.0, 0.0, 1.4 * trail_s)
	trail.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	sword_node.add_child(trail)

	var t_mat := ShaderMaterial.new()
	t_mat.shader = RibbonTrailShader
	t_mat.set_shader_parameter("ribbon_color", theme["trail"])
	t_mat.set_shader_parameter("glow_intensity", 2.6 if is_finisher else 1.85)
	t_mat.set_shader_parameter("fade", 1.0)
	trail.material_override = t_mat

	# Orient sword node pointing towards landing point
	var dir := (land_pos - spawn_pos).normalized()
	sword_node.look_at(spawn_pos + dir, Vector3.UP)

	# Sound: blade cutting through air
	if randf() < 0.50 or is_finisher:
		AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/knifeSlice2.ogg", randf_range(1.15, 1.38))

	# Flight Tween
	var dist := spawn_pos.distance_to(land_pos)
	var flight_speed := 54.0 if is_finisher else randf_range(42.0, 52.0)
	var flight_time := dist / flight_speed

	var tw := sword_node.create_tween()
	tw.tween_property(sword_node, "global_position", land_pos, flight_time).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func():
		if sword_node == null or not is_instance_valid(sword_node):
			return
		_on_sword_impact(root, caster, sword_node, wrapper, aura_root, trail, land_pos, dir, theme, is_finisher)
	)

	return land_pos


func _on_sword_impact(root: Node3D, caster: CharacterBody3D, sword_node: Node3D, wrapper: Node3D, aura_root: Node3D, trail: MeshInstance3D, hit_pos: Vector3, plunge_dir: Vector3, theme: Dictionary, is_finisher: bool) -> void:
	if root == null or not is_instance_valid(root) or sword_node == null or not is_instance_valid(sword_node):
		return

	# Remove flight trail
	if trail != null and is_instance_valid(trail):
		trail.queue_free()

	# Audio: Layered Heavy impact / metal plunge into earth
	if is_finisher:
		AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/metalPot3.ogg", 0.90)
		AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/chop.ogg", 0.85)
		AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/metalLatch.ogg", 1.05)
	else:
		var hit_sfx := [
			"res://assets/voice/RPGsounds_Kenney/OGG/chop.ogg",
			"res://assets/voice/RPGsounds_Kenney/OGG/metalPot1.ogg",
			"res://assets/voice/RPGsounds_Kenney/OGG/metalPot2.ogg",
			"res://assets/voice/RPGsounds_Kenney/OGG/metalClick.ogg",
			"res://assets/voice/RPGsounds_Kenney/OGG/metalLatch.ogg"
		]
		var chosen_sfx: String = hit_sfx[randi() % hit_sfx.size()]
		AudioManagerScript.play_voice_file(chosen_sfx, randf_range(0.95, 1.25))

	# --- 1. Ground Scorch Crust (地面焦痕深色底斑) ---
	_spawn_ground_scorch(root, hit_pos, theme, is_finisher)

	# --- 2. Ground Fissure / Crater Fracture (深层地裂灵脉) ---
	_spawn_ground_fissure(root, hit_pos, theme, is_finisher)

	# --- 3. 3D Volumetric Shockwave Dome (立体冲击波穹顶) ---
	_spawn_shockwave_dome(root, hit_pos, theme, is_finisher)

	# --- 4. Fast-Start, Slow-Ease Expanding Sonic Ring (快起慢落扩散环) ---
	_spawn_ground_flash_and_ring(root, hit_pos, theme, is_finisher)

	# --- 5. Shattered Rocks & Smoke Dust (碎石飞溅与烟尘扩散) ---
	_spawn_shattered_rocks_and_smoke(root, hit_pos, theme, is_finisher)

	# --- 6. Vertical Spirit Blade Pillar on Finisher (天罡通天灵光柱) ---
	# (Heavenly pillar removed per user request)

	# Damage & Stagger resolution
	_resolve_sword_damage(caster, hit_pos, plunge_dir, is_finisher)

	# Blade embedding into ground with slight quiver
	sword_node.global_position = hit_pos + Vector3(0.0, -0.35, 0.0)

	# Quiver / Shake tween
	var quiver_tw := sword_node.create_tween()
	var base_rot := sword_node.rotation
	quiver_tw.tween_property(sword_node, "rotation", base_rot + Vector3(0.06, 0.04, -0.05), 0.04)
	quiver_tw.tween_property(sword_node, "rotation", base_rot + Vector3(-0.05, -0.03, 0.04), 0.05)
	quiver_tw.tween_property(sword_node, "rotation", base_rot, 0.06)
	quiver_tw.tween_interval(0.45)
	# Dissolve / Fade out by shrinking and sinking slightly
	quiver_tw.tween_property(wrapper, "scale", Vector3.ZERO, 0.40).set_ease(Tween.EASE_IN)
	quiver_tw.tween_property(aura_root, "scale", Vector3.ZERO, 0.40).set_ease(Tween.EASE_IN)
	quiver_tw.tween_callback(sword_node.queue_free)


func _spawn_ground_scorch(root: Node3D, pos: Vector3, theme: Dictionary, is_finisher: bool) -> void:
	var scorch := MeshInstance3D.new()
	scorch.mesh = _plane_mesh
	var sz := 4.6 if is_finisher else randf_range(2.0, 2.8)
	scorch.scale = Vector3(sz, 1.0, sz)
	root.add_child(scorch)
	scorch.global_position = pos + Vector3(0.0, 0.02, 0.0)

	var s_mat := StandardMaterial3D.new()
	s_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	s_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	s_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	s_mat.albedo_color = theme["scorch"]
	if _cached_flash_tex != null:
		s_mat.albedo_texture = _cached_flash_tex
	scorch.material_override = s_mat

	var tw := scorch.create_tween()
	tw.tween_interval(0.85 if is_finisher else 0.55)
	tw.tween_property(s_mat, "albedo_color:a", 0.0, 0.50).set_ease(Tween.EASE_IN)
	tw.tween_callback(scorch.queue_free)


func _spawn_ground_fissure(root: Node3D, pos: Vector3, theme: Dictionary, is_finisher: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _plane_mesh
	var sz := 5.0 if is_finisher else randf_range(2.4, 3.2)
	mi.scale = Vector3(sz, 1.0, sz)
	root.add_child(mi)
	mi.global_position = pos + Vector3(0.0, 0.035, 0.0)

	var mat := ShaderMaterial.new()
	mat.shader = GroundFractureShader
	mat.set_shader_parameter("glow_core", theme["impact_core"])
	mat.set_shader_parameter("glow_amber", theme["crack_amber"])
	mat.set_shader_parameter("glow_crimson", theme["crack_crimson"])
	mat.set_shader_parameter("crust_color", Color(0.0, 0.0, 0.0, 0.0))
	mat.set_shader_parameter("crack_progress", 0.1)
	mat.set_shader_parameter("heat_intensity", 1.4 if is_finisher else 1.0)
	mat.set_shader_parameter("fade", 1.0)
	if _cached_crack_tex != null:
		mat.set_shader_parameter("crack_tex", _cached_crack_tex)
	mi.material_override = mat

	var tw := mi.create_tween()
	tw.tween_property(mat, "shader_parameter/crack_progress", 1.0, 0.16).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.65 if is_finisher else 0.40)
	tw.tween_property(mat, "shader_parameter/fade", 0.0, 0.45)
	tw.tween_callback(mi.queue_free)


func _spawn_shockwave_dome(root: Node3D, pos: Vector3, theme: Dictionary, is_finisher: bool) -> void:
	var dome := MeshInstance3D.new()
	dome.mesh = _sphere_mesh
	var target_r := 7.0 if is_finisher else randf_range(3.0, 4.0)
	dome.scale = Vector3(0.2, 0.2, 0.2)
	root.add_child(dome)
	dome.global_position = pos + Vector3(0.0, 0.08, 0.0)

	var mat := ShaderMaterial.new()
	mat.shader = ShockwaveDomeShader
	mat.set_shader_parameter("core_gold", theme["impact_core"])
	mat.set_shader_parameter("mid_orange", theme["impact_mid"])
	mat.set_shader_parameter("wave_crimson", theme["impact_outer"])
	mat.set_shader_parameter("fade", 1.0)
	dome.material_override = mat

	var tw := dome.create_tween()
	tw.set_parallel(true)
	tw.tween_property(dome, "scale", Vector3(target_r, target_r * 0.70, target_r), 0.30).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(mat, "shader_parameter/fade", 0.0, 0.30).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(dome.queue_free)


func _spawn_ground_flash_and_ring(root: Node3D, pos: Vector3, theme: Dictionary, is_finisher: bool) -> void:
	# 1. Fast-Start, Slow-Ease Expanding Sonic Ring (快起慢落扩散环)
	var ring := MeshInstance3D.new()
	ring.mesh = _plane_mesh
	var r_sz := 5.6 if is_finisher else randf_range(2.6, 3.6)
	ring.scale = Vector3(0.1, 1.0, 0.1)
	root.add_child(ring)
	ring.global_position = pos + Vector3(0.0, 0.045, 0.0)

	var mat := ShaderMaterial.new()
	mat.shader = SonicRingShader
	mat.set_shader_parameter("ring_color", theme["impact_mid"])
	mat.set_shader_parameter("intensity", 3.2 if is_finisher else 2.2)
	mat.set_shader_parameter("fade", 1.0)
	ring.material_override = mat

	var tw := ring.create_tween()
	tw.set_parallel(true)
	# Fast initial expansion, slowing down at the end (TRANS_EXPO + EASE_OUT)
	tw.tween_property(ring, "scale", Vector3(r_sz, 1.0, r_sz), 0.42).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(mat, "shader_parameter/fade", 0.0, 0.42).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(ring.queue_free)

	# 2. Radial Flash Flare (瞬间爆发聚焦点)
	var flash := MeshInstance3D.new()
	flash.mesh = _plane_mesh
	var f_sz := 3.2 if is_finisher else randf_range(1.5, 2.2)
	flash.scale = Vector3(f_sz, 1.0, f_sz)
	root.add_child(flash)
	flash.global_position = pos + Vector3(0.0, 0.05, 0.0)

	var f_mat := StandardMaterial3D.new()
	f_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	f_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	f_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	f_mat.albedo_color = theme["impact_core"]
	if _cached_flash_tex != null:
		f_mat.albedo_texture = _cached_flash_tex
	flash.material_override = f_mat

	var ftw := flash.create_tween()
	ftw.tween_property(f_mat, "albedo_color:a", 0.0, 0.18).set_ease(Tween.EASE_IN)
	ftw.tween_callback(flash.queue_free)


func _spawn_shattered_rocks_and_smoke(root: Node3D, pos: Vector3, theme: Dictionary, is_finisher: bool) -> void:
	# 1. 3D Shattered Rock Debris Eruption
	var rock_count := 8 if is_finisher else 4
	for k in range(rock_count):
		var rock := MeshInstance3D.new()
		rock.mesh = _rock_mesh
		rock.material_override = _rock_mat
		var r_scale := randf_range(0.8, 1.5) if is_finisher else randf_range(0.5, 1.1)
		rock.scale = Vector3(r_scale, r_scale, r_scale)
		root.add_child(rock)
		rock.global_position = pos + Vector3(randf_range(-0.2, 0.2), 0.15, randf_range(-0.2, 0.2))

		var burst_dir := Vector3(randf_range(-1.0, 1.0), randf_range(1.2, 2.5), randf_range(-1.0, 1.0)).normalized()
		var burst_dist := randf_range(1.8, 3.6) if is_finisher else randf_range(1.0, 2.2)
		var dest_pos := rock.global_position + burst_dir * burst_dist
		dest_pos.y = pos.y + 0.05

		var rtw := rock.create_tween()
		rtw.set_parallel(true)
		rtw.tween_property(rock, "global_position", dest_pos, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		rtw.tween_property(rock, "rotation", Vector3(randf_range(-6.0, 6.0), randf_range(-6.0, 6.0), randf_range(-6.0, 6.0)), 0.38)
		rtw.chain().tween_interval(0.25)
		rtw.chain().tween_property(rock, "scale", Vector3.ZERO, 0.25).set_ease(Tween.EASE_IN)
		rtw.chain().tween_callback(rock.queue_free)

	# 2. Smoke Dust Puff
	var smoke := MeshInstance3D.new()
	smoke.mesh = _plane_mesh
	var smk_sz := 3.8 if is_finisher else randf_range(1.8, 2.6)
	smoke.scale = Vector3(0.2, 1.0, 0.2)
	root.add_child(smoke)
	smoke.global_position = pos + Vector3(0.0, 0.08, 0.0)

	var smk_mat := StandardMaterial3D.new()
	smk_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smk_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smk_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	smk_mat.albedo_color = Color(theme["scorch"].r, theme["scorch"].g, theme["scorch"].b, 0.65)
	if _cached_smoke_tex != null:
		smk_mat.albedo_texture = _cached_smoke_tex
	smoke.material_override = smk_mat

	var smk_tw := smoke.create_tween()
	smk_tw.set_parallel(true)
	smk_tw.tween_property(smoke, "scale", Vector3(smk_sz, 1.0, smk_sz), 0.48).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	smk_tw.tween_property(smk_mat, "albedo_color:a", 0.0, 0.48).set_ease(Tween.EASE_IN)
	smk_tw.chain().tween_callback(smoke.queue_free)


func _spawn_heavenly_pillar(root: Node3D, pos: Vector3, theme: Dictionary) -> void:
	var pillar := MeshInstance3D.new()
	pillar.mesh = _cylinder_mesh
	pillar.scale = Vector3(2.8, 16.0, 2.8)
	root.add_child(pillar)
	pillar.global_position = pos + Vector3(0.0, 8.0, 0.0)

	var p_mat := ShaderMaterial.new()
	p_mat.shader = HeavenlyPillarShader
	p_mat.set_shader_parameter("beam_core", theme["impact_core"])
	p_mat.set_shader_parameter("beam_gold", theme["blade_glow"])
	p_mat.set_shader_parameter("beam_aurora", theme["sigil"])
	p_mat.set_shader_parameter("speed", 10.0)
	p_mat.set_shader_parameter("fade", 1.0)
	pillar.material_override = p_mat

	var ptw := pillar.create_tween()
	ptw.tween_interval(0.40)
	ptw.tween_property(p_mat, "shader_parameter/fade", 0.0, 0.50).set_ease(Tween.EASE_IN)
	ptw.tween_callback(pillar.queue_free)


func _trigger_array_resonance(root: Node3D, center_pos: Vector3, theme: Dictionary, embedded_positions: Array[Vector3]) -> void:
	if root == null or not is_instance_valid(root) or embedded_positions.size() < 2:
		return

	# Massive Resonance Wave across entire array
	AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/chop.ogg", 1.1)
	AudioManagerScript.play_voice_file("res://assets/voice/RPGsounds_Kenney/OGG/metalPot2.ogg", 1.25)

	# Grand resonance ground wave
	var wave := MeshInstance3D.new()
	wave.mesh = _plane_mesh
	wave.scale = Vector3(0.5, 1.0, 0.5)
	root.add_child(wave)
	wave.global_position = center_pos + Vector3(0.0, 0.06, 0.0)

	var w_mat := ShaderMaterial.new()
	w_mat.shader = SonicRingShader
	w_mat.set_shader_parameter("ring_color", theme["impact_mid"])
	w_mat.set_shader_parameter("intensity", 4.0)
	w_mat.set_shader_parameter("fade", 1.0)
	wave.material_override = w_mat

	var tw := wave.create_tween()
	tw.set_parallel(true)
	tw.tween_property(wave, "scale", Vector3(strike_radius * 2.8, 1.0, strike_radius * 2.8), 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(w_mat, "shader_parameter/fade", 0.0, 0.45).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(wave.queue_free)


func _resolve_sword_damage(caster: CharacterBody3D, hit_pos: Vector3, swing_dir: Vector3, is_finisher: bool) -> void:
	var tree := caster.get_tree() if (caster != null and is_instance_valid(caster) and caster.is_inside_tree()) else null
	if tree == null:
		return
	var scene_root := tree.current_scene
	if scene_root == null:
		return

	var aoe_r := 3.5 if is_finisher else 1.8
	var dmg := damage_per_sword * (2.8 if is_finisher else 1.0)

	var candidates: Array = []
	for ch in scene_root.find_children("*", "CharacterBody3D", true, false):
		candidates.append(ch)
	for ch in scene_root.find_children("*", "DummyTarget", true, false):
		candidates.append(ch)

	for b in candidates:
		if b == null or not is_instance_valid(b) or b == caster or b.name == "Ground":
			continue
		if not (b is Node3D):
			continue
		var n3d := b as Node3D
		var d := (n3d.global_position - hit_pos).length()
		if d > aoe_r:
			continue

		# 1. DummyTarget hit resolution
		if b.has_method("take_hit"):
			b.call("take_hit", hit_pos, dmg, swing_dir)

		# 2. PlayerController / NPC hit reaction
		if b.has_method("apply_hit_reaction"):
			b.call("apply_hit_reaction", "hit_chest", 0.45 if is_finisher else 0.22)


static var _rock_mesh: PrismMesh = null
static var _rock_mat: StandardMaterial3D = null
static var _cached_smoke_tex: Texture2D = null


static func _ensure_cached_resources() -> void:
	if not _cached_sword_data.is_empty():
		return

	if _quad_mesh == null:
		_quad_mesh = QuadMesh.new()
		_quad_mesh.size = Vector2(1.0, 1.0)

	if _plane_mesh == null:
		_plane_mesh = PlaneMesh.new()
		_plane_mesh.size = Vector2(1.0, 1.0)

	if _sphere_mesh == null:
		_sphere_mesh = SphereMesh.new()
		_sphere_mesh.radial_segments = 32
		_sphere_mesh.rings = 16

	if _cylinder_mesh == null:
		_cylinder_mesh = CylinderMesh.new()
		_cylinder_mesh.top_radius = 1.0
		_cylinder_mesh.bottom_radius = 1.0
		_cylinder_mesh.height = 1.0

	if _rock_mesh == null:
		_rock_mesh = PrismMesh.new()
		_rock_mesh.size = Vector3(0.18, 0.18, 0.18)

	if _rock_mat == null:
		_rock_mat = StandardMaterial3D.new()
		_rock_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		_rock_mat.albedo_color = Color(0.22, 0.20, 0.18)
		_rock_mat.roughness = 0.9

	# Textures
	if _cached_crack_tex == null and ResourceLoader.exists(CRACK_TEX_PATH):
		_cached_crack_tex = load(CRACK_TEX_PATH) as Texture2D

	if _cached_flash_tex == null and ResourceLoader.exists(FLASH_GLOW_PATH):
		_cached_flash_tex = load(FLASH_GLOW_PATH) as Texture2D

	if _cached_lightning_tex == null and ResourceLoader.exists(LIGHTNING_TEX_PATH):
		_cached_lightning_tex = load(LIGHTNING_TEX_PATH) as Texture2D

	if _cached_smoke_tex == null and ResourceLoader.exists(SMOKE_TEX_PATH):
		_cached_smoke_tex = load(SMOKE_TEX_PATH) as Texture2D

	# Preload PackedScenes and calculate calibration offsets
	for path in SWORD_FBX_PATHS:
		var scn: PackedScene = load(path)
		if scn != null:
			var inst: Node3D = scn.instantiate() as Node3D
			var mi: MeshInstance3D = _find_first_mesh_instance(inst)
			if mi != null and mi.mesh != null:
				var aabb := mi.mesh.get_aabb()
				var local_center := aabb.position + aabb.size * 0.5
				var transformed_center := mi.transform * local_center
				var transformed_size := (mi.transform.basis * aabb.size).abs()
				var sword_len := transformed_size.y
				var target_len := 1.85 # standard meters
				var scale_fac := target_len / sword_len if sword_len > 0.001 else 1.0
				_cached_sword_data.append({
					"scene": scn,
					"center_offset": transformed_center,
					"length": sword_len,
					"scale_factor": scale_fac
				})
			inst.free()

	if _ground_sigil_mat == null:
		_ground_sigil_mat = ShaderMaterial.new()
		_ground_sigil_mat.shader = ThunderMagicSigilShader

	if _sky_sigil_mat == null:
		_sky_sigil_mat = ShaderMaterial.new()
		_sky_sigil_mat.shader = SigilRingShader

	if _shockwave_mat == null:
		_shockwave_mat = ShaderMaterial.new()
		_shockwave_mat.shader = SonicRingShader

	if _trail_mat == null:
		_trail_mat = ShaderMaterial.new()
		_trail_mat.shader = RibbonTrailShader

	if _blade_aura_mat == null:
		_blade_aura_mat = ShaderMaterial.new()
		_blade_aura_mat.shader = SwordAuraShader

	if _ground_crack_mat == null:
		_ground_crack_mat = ShaderMaterial.new()
		_ground_crack_mat.shader = GroundFractureShader

	if _shockwave_dome_mat == null:
		_shockwave_dome_mat = ShaderMaterial.new()
		_shockwave_dome_mat.shader = ShockwaveDomeShader

	if _heavenly_pillar_mat == null:
		_heavenly_pillar_mat = ShaderMaterial.new()
		_heavenly_pillar_mat.shader = HeavenlyPillarShader

	if _lightning_web_mat == null:
		_lightning_web_mat = ShaderMaterial.new()
		_lightning_web_mat.shader = FineLightningWebShader


static func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for c in node.get_children():
		var found := _find_first_mesh_instance(c)
		if found != null:
			return found
	return null
