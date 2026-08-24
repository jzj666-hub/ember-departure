extends SceneTree
## Diagnoses why the VFX textures do not show up.
## Answers, in order: does the file resolve, does the shader still compile with the new uniforms,
## does bind() actually run, and what does the live material carry after a real cast.

const SHADERS := {
	"sigil_ring": "res://shaders/sigil_ring.gdshader",
	"sonic_boom_ring": "res://shaders/sonic_boom_ring.gdshader",
	"wind_cutter": "res://shaders/wind_cutter.gdshader",
}

var _VfxTextures = null
var _SkillRegistry = null


func _initialize() -> void:
	Engine.max_fps = 60
	_VfxTextures = load("res://scripts/vfx/vfx_textures.gd")
	_SkillRegistry = load("res://scripts/skills/skill_registry.gd")

	print("\n=========== 1. TEXTURE RESOLUTION ===========")
	_check_textures()

	print("\n=========== 2. SHADER UNIFORMS (compile check) ===========")
	_check_shaders()

	print("\n=========== 3. LIVE MATERIALS AFTER CAST ===========")
	await _check_live_casts()

	print("\n--- probe done ---")
	quit(0)


func _check_textures() -> void:
	var paths := {
		"MAGIC_CIRCLE": _VfxTextures.MAGIC_CIRCLE,
		"SHOCKWAVE_RING": _VfxTextures.SHOCKWAVE_RING,
		"WIND_SLASH": _VfxTextures.WIND_SLASH,
		"GROUND_CRACK": _VfxTextures.GROUND_CRACK,
		"SMOKE": _VfxTextures.SMOKE,
		"RAMP_TOXIC": _VfxTextures.RAMP_TOXIC,
		"RAMP_ICE": _VfxTextures.RAMP_ICE,
	}
	for key in paths:
		var p: String = paths[key]
		var exists := ResourceLoader.exists(p)
		var tex = _VfxTextures.get_tex(p)
		var desc := "null"
		if tex != null:
			desc = "%s %dx%d" % [tex.get_class(), tex.get_width(), tex.get_height()]
		print("  %-16s exists=%-5s get_tex=%s" % [key, str(exists), desc])
		if not exists:
			print("      ^^ PATH NOT FOUND: %s" % p)


func _check_shaders() -> void:
	for name in SHADERS:
		var path: String = SHADERS[name]
		var sh = load(path) as Shader
		if sh == null:
			print("  %-16s LOAD FAILED" % name)
			continue
		var uniforms: Array = sh.get_shader_uniform_list(false)
		var names: Array[String] = []
		for u in uniforms:
			names.append(str(u.get("name", "?")))
		print("  %-16s uniforms(%d): %s" % [name, names.size(), ", ".join(names)])
		if not names.has("tex_mix"):
			print("      ^^ tex_mix MISSING -> shader did not compile with the new uniforms")


func _check_live_casts() -> void:
	var root_node := Node3D.new()
	root_node.name = "ProbeRoot"
	root.add_child(root_node)

	_SkillRegistry.init_registry()

	var caster := CharacterBody3D.new()
	caster.name = "ProbeCaster"
	root_node.add_child(caster)
	await physics_frame

	for s_id in ["teleport", "entangle", "slam", "mist"]:
		var holder := Node3D.new()
		holder.name = "Holder_" + s_id
		root_node.add_child(holder)

		var skill = _SkillRegistry.get_skill(s_id)
		if skill == null:
			print("  [%s] skill not registered" % s_id)
			continue
		skill.call("cast", caster, Vector3.BACK, holder, false)
		for f in 3:
			await physics_frame

		print("  --- %s ---" % s_id)
		var found := 0
		found = _walk(holder, found)
		if found == 0:
			print("      (no MeshInstance3D with material_override found)")


func _walk(node: Node, found: int) -> int:
	var mi := node as MeshInstance3D
	if mi != null and mi.material_override != null:
		found += 1
		var mat := mi.material_override
		var sm := mat as ShaderMaterial
		if sm != null:
			var sh_name := "?"
			if sm.shader != null:
				sh_name = sm.shader.resource_path.get_file()
			var tm = sm.get_shader_parameter("tex_mix")
			var t0 = sm.get_shader_parameter("sigil_tex")
			var t1 = sm.get_shader_parameter("ring_tex")
			var t2 = sm.get_shader_parameter("wind_tex")
			var rm = sm.get_shader_parameter("ramp_mix")
			var rt = sm.get_shader_parameter("color_ramp")
			print("      ShaderMaterial<%s> tex_mix=%s ramp_mix=%s | sigil=%s ring=%s wind=%s ramp=%s"
				% [sh_name, str(tm), str(rm),
					str(t0 != null), str(t1 != null), str(t2 != null), str(rt != null)])
		else:
			var std := mat as StandardMaterial3D
			if std != null:
				print("      StandardMaterial3D albedo_texture=%s color=%s"
					% [str(std.albedo_texture != null), str(std.albedo_color)])
	for c in node.get_children():
		found = _walk(c, found)
	return found
