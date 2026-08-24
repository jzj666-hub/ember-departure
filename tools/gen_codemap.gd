extends SceneTree
## Generates CODEMAP.md — repo-wide script index used by AI agents as a lookup standard.
## Source of truth = the scripts themselves (leading `##` docstring + preload graph).
## No sidecar file, so the map cannot drift from the code.
## Post: CODEMAP.md rewritten; exit 0. Scripts lacking a `##` docstring are listed as TODO.
##
##   godot --headless --path . --script res://tools/gen_codemap.gd

const OUT_PATH := "res://CODEMAP.md"

## Directories scanned. scratch/ and .godot/ are excluded as throwaway.
const SCAN_ROOTS: Array[String] = ["res://scripts", "res://tools", "res://addons"]

## Duplicate-function detection is limited to game code; probe helpers (_ok/_run) would drown it.
const DUP_ROOT := "scripts/"
const DUP_MIN := 3

## Fan-in at or above this marks a script as a hub: its public signatures are load-bearing.
const HUB_MIN_FANIN := 5

## Functions whose body is this short are delegators/stubs, not implementations.
## Keeps refactored-to-shared-impl wrappers out of the duplicate report (the map self-heals).
const DELEGATOR_MAX_BODY := 2

## Engine callbacks and probe scaffolding: never counted as duplicate implementations.
const IGNORED_FUNCS: Array[String] = [
	"_ready", "_process", "_physics_process", "_input", "_unhandled_input",
	"_unhandled_key_input", "_shortcut_input", "_init", "_initialize", "_draw",
	"_notification", "_enter_tree", "_exit_tree", "_to_string", "_get_configuration_warnings",
	"_run", "_ok", "_fail", "_finish", "_section",
]

var _files: Array = []          # Array of parsed script dicts
var _by_rel: Dictionary = {}    # rel path -> parsed dict
var _fan_in: Dictionary = {}    # rel path -> Array[rel path] of dependents
var _parent: Dictionary = {}    # rel path -> parent rel path ("" if engine base)


func _initialize() -> void:
	_scan()
	_build_graph()
	var md := _render()
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		printerr("CODEMAP: cannot write %s" % OUT_PATH)
		quit(1)
		return
	f.store_string(md)
	f.close()
	print("CODEMAP: wrote %s (%d scripts indexed)" % [OUT_PATH, _files.size()])
	quit(0)


# --- Scanning ---------------------------------------------------------------

func _scan() -> void:
	for root in SCAN_ROOTS:
		_walk(root)
	_files.sort_custom(func(a, b): return a.rel < b.rel)
	for e in _files:
		_by_rel[e.rel] = e


func _walk(dir_path: String) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			_walk(full)
		elif name.ends_with(".gd"):
			var parsed := _parse(full)
			if not parsed.is_empty():
				_files.append(parsed)
		name = d.get_next()
	d.list_dir_end()


## _parse(path): extracts line count, class_name, docstring, preload edges, func names.
## Post: returns {} on unreadable file.
func _parse(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text().replace("\r\n", "\n")
	f.close()
	var lines := text.split("\n")

	var re_class := RegEx.new()
	re_class.compile("(?m)^class_name\\s+(\\w+)")
	var re_pre := RegEx.new()
	re_pre.compile("preload\\(\"res://([^\"]+\\.gd)\"\\)")
	var re_func := RegEx.new()
	re_func.compile("(?m)^(?:static\\s+)?func\\s+(\\w+)\\s*\\(")
	var re_extends := RegEx.new()
	re_extends.compile("(?m)^extends\\s+(?:\"([^\"]+)\"|([\\w\\.]+))")

	var cls := ""
	var m := re_class.search(text)
	if m != null:
		cls = m.get_string(1)

	var base := ""
	var me := re_extends.search(text)
	if me != null:
		base = me.get_string(1)
		if base == "":
			base = me.get_string(2)

	# Docstring: first `##` line appearing before any declaration.
	var doc := ""
	for i in range(min(20, lines.size())):
		var ln: String = lines[i].strip_edges()
		if ln.begins_with("##"):
			var body := ln.substr(2).strip_edges()
			if body != "":
				doc = body
				break
		elif ln.begins_with("func ") or ln.begins_with("var ") or ln.begins_with("@export"):
			break

	var preloads: Array = []
	for pm in re_pre.search_all(text):
		var t: String = pm.get_string(1)
		if not preloads.has(t):
			preloads.append(t)

	# Line-walk funcs so each body length is known; delegators are excluded from dup detection.
	var funcs: Array = []
	var pub_funcs: Array = []
	var meaty: Array = []
	var i := 0
	while i < lines.size():
		var fm := re_func.search(lines[i])
		if fm == null:
			i += 1
			continue
		var fname: String = fm.get_string(1)
		if not funcs.has(fname):
			funcs.append(fname)
		if not fname.begins_with("_") and not pub_funcs.has(fname):
			pub_funcs.append(fname)
		var j := i + 1
		var body := 0
		while j < lines.size():
			var bl: String = lines[j]
			var t := bl.strip_edges()
			if t == "":
				j += 1
				continue
			if not (bl.begins_with("\t") or bl.begins_with(" ")):
				break
			if not t.begins_with("#"):
				body += 1
			j += 1
		if body > DELEGATOR_MAX_BODY and not meaty.has(fname):
			meaty.append(fname)
		i = j

	return {
		"rel": path.replace("res://", ""),
		"lines": lines.size(),
		"cls": cls,
		"base": base,
		"doc": doc,
		"preloads": preloads,
		"funcs": funcs,
		"meaty": meaty,
		"pub": pub_funcs,
	}


# --- Graph ------------------------------------------------------------------

func _build_graph() -> void:
	for e in _files:
		for target in e.preloads:
			if not _fan_in.has(target):
				_fan_in[target] = []
			if not _fan_in[target].has(e.rel):
				_fan_in[target].append(e.rel)
	_build_parents()


## _build_parents(): resolves each script's `extends` to a sibling rel path.
## Handles both `extends "res://x.gd"` and `extends SomeClassName`.
func _build_parents() -> void:
	var by_class: Dictionary = {}
	for e in _files:
		if e.cls != "":
			by_class[e.cls] = e.rel
	for e in _files:
		var b: String = e.base
		if b.begins_with("res://"):
			_parent[e.rel] = b.replace("res://", "")
		elif by_class.has(b):
			_parent[e.rel] = by_class[b]
		else:
			_parent[e.rel] = ""


## _is_ancestor(a, b): true if a appears in b's extends chain. Depth-capped against cycles.
func _is_ancestor(a: String, b: String) -> bool:
	var cur: String = _parent.get(b, "")
	var guard := 0
	while cur != "" and guard < 16:
		if cur == a:
			return true
		cur = _parent.get(cur, "")
		guard += 1
	return false


## _is_interface_family(defs): true if any definer inherits from another definer.
## Polymorphic overrides (skills/, intent sources) are not duplicated code.
func _is_interface_family(defs: Array) -> bool:
	for a in defs:
		for b in defs:
			if a != b and _is_ancestor(a, b):
				return true
	return false


func _fanin_of(rel: String) -> int:
	if not _fan_in.has(rel):
		return 0
	return _fan_in[rel].size()


# --- Rendering --------------------------------------------------------------

func _render() -> String:
	var out := ""
	out += _render_header()
	out += _render_stats()
	out += _render_duplicates()
	out += _render_hubs()
	out += _render_index()
	out += _render_todo()
	return out


func _render_header() -> String:
	return """# CODEMAP — 灰烬:启程 代码索引

> **自动生成,请勿手工编辑本文件。** 重跑:
> `godot --headless --path . --script res://tools/gen_codemap.gd`
>
> 每行的「职责」列取自脚本自身开头的 `##` 文档注释 —— 想改描述就去改那个脚本的注释,
> 索引不会和代码漂移。

## 给 AI 代理的使用规则

1. **实现任何新功能前,先在本文件检索关键词。** 已存在的能力必须复用,禁止另起炉灶。
2. 「重复实现警告」一节列出了已经发生的重复。往这些函数里再加一份 = 明确错误。
3. 「高扇入服务层」的公开函数签名是契约。改签名前先看扇入清单,评估波及面。
4. 新建脚本必须写开头 `##` 文档注释,否则会出现在文末 TODO 里。

"""


func _render_stats() -> String:
	var total_lines := 0
	var with_doc := 0
	var with_class := 0
	for e in _files:
		total_lines += e.lines
		if e.doc != "":
			with_doc += 1
		if e.cls != "":
			with_class += 1
	var s := "## 统计\n\n"
	s += "| 项 | 值 |\n|---|---|\n"
	s += "| 脚本数 | %d |\n" % _files.size()
	s += "| 总行数 | %d |\n" % total_lines
	s += "| 有 `##` 职责注释 | %d / %d |\n" % [with_doc, _files.size()]
	s += "| 有 `class_name` 全局名 | %d / %d |\n" % [with_class, _files.size()]
	s += "\n"
	return s


## _render_duplicates(): same func name defined in >= DUP_MIN files under DUP_ROOT.
## Split: real copy-paste vs polymorphic override families (detected via extends chain).
func _render_duplicates() -> String:
	var dup: Dictionary = {}      # name -> definers with a real body (what we report)
	var dup_all: Dictionary = {}  # name -> every definer incl. abstract stubs (ancestry test)
	for e in _files:
		if not (e.rel as String).begins_with(DUP_ROOT):
			continue
		for fname in e.funcs:
			if IGNORED_FUNCS.has(fname):
				continue
			if not dup_all.has(fname):
				dup_all[fname] = []
			dup_all[fname].append(e.rel)
		for fname in e.meaty:
			if IGNORED_FUNCS.has(fname):
				continue
			if not dup.has(fname):
				dup[fname] = []
			dup[fname].append(e.rel)

	var real: Array = []
	var iface: Array = []
	for k in dup.keys():
		if dup[k].size() < DUP_MIN:
			continue
		# Ancestry is tested over ALL definers: an abstract base stub is filtered out of `meaty`
		# but is exactly what proves this is polymorphism rather than copy-paste.
		if _is_interface_family(dup_all[k]):
			iface.append(k)
		else:
			real.append(k)
	real.sort_custom(func(a, b): return dup[a].size() > dup[b].size())
	iface.sort_custom(func(a, b): return dup_all[a].size() > dup_all[b].size())

	var s := "## ⚠️ 重复实现警告\n\n"
	s += "同名函数在 `%s` 下被复制了 %d 份以上,**且彼此没有继承关系**。\n" % [DUP_ROOT, DUP_MIN]
	s += "写新场景/新模式时,不要再复制第 N+1 份 —— 先看这里,考虑抽公共实现。\n"
	s += "抽成公共实现后,剩下的 ≤%d 行转发函数不再计数,本表会自动变短。\n\n" % DELEGATOR_MAX_BODY
	if real.is_empty():
		s += "_(无)_\n\n"
	else:
		s += "| 函数 | 份数 | 分布 |\n|---|---|---|\n"
		for k in real:
			var paths: Array = dup[k]
			paths.sort()
			s += "| `%s` | **%d** | %s |\n" % [k, paths.size(), ", ".join(paths)]
		s += "\n"

	s += "<details>\n<summary>接口族(多态覆写,非重复 —— 点开查看)</summary>\n\n"
	if iface.is_empty():
		s += "_(无)_\n"
	else:
		s += "| 函数 | 实现数 | 基类 |\n|---|---|---|\n"
		for k in iface:
			var defs: Array = dup_all[k]
			var base_rel := ""
			for a in defs:
				for b in defs:
					if a != b and _is_ancestor(a, b):
						base_rel = a
						break
				if base_rel != "":
					break
			s += "| `%s` | %d | `%s` |\n" % [k, defs.size(), base_rel]
	s += "\n</details>\n\n"
	return s


func _render_hubs() -> String:
	var hubs: Array = []
	for e in _files:
		if _fanin_of(e.rel) >= HUB_MIN_FANIN:
			hubs.append(e)
	hubs.sort_custom(func(a, b): return _fanin_of(a.rel) > _fanin_of(b.rel))

	var s := "## 🔒 高扇入服务层(扇入 ≥ %d)\n\n" % HUB_MIN_FANIN
	s += "改这些脚本的**公开函数签名**会波及下列依赖方。改内部实现是安全的。\n\n"
	if hubs.is_empty():
		s += "_(无)_\n\n"
		return s
	for e in hubs:
		s += "### `%s` — 扇入 %d\n\n" % [e.rel, _fanin_of(e.rel)]
		if e.doc != "":
			s += "%s\n\n" % e.doc
		if not e.pub.is_empty():
			var shown: Array = e.pub.slice(0, 24)
			s += "公开 API:`%s`" % "`, `".join(shown)
			if e.pub.size() > shown.size():
				s += " …(共 %d 个)" % e.pub.size()
			s += "\n\n"
		var deps: Array = _fan_in[e.rel]
		deps.sort()
		s += "被依赖:%s\n\n" % ", ".join(deps)
	return s


func _render_index() -> String:
	var groups: Dictionary = {}
	for e in _files:
		var d: String = (e.rel as String).get_base_dir()
		if d == "":
			d = "."
		if not groups.has(d):
			groups[d] = []
		groups[d].append(e)

	var dirs: Array = groups.keys()
	dirs.sort()

	var s := "## 全量索引\n\n"
	s += "扇入 = 有多少脚本 preload 它;扇出 = 它 preload 了多少脚本。\n\n"
	for d in dirs:
		s += "### `%s/`\n\n" % d
		s += "| 脚本 | 行 | class_name | 扇入 | 扇出 | 职责 |\n"
		s += "|---|---|---|---|---|---|\n"
		for e in groups[d]:
			var fname: String = (e.rel as String).get_file()
			var cls: String = e.cls if e.cls != "" else "—"
			var doc: String = e.doc if e.doc != "" else "**⚠ 缺注释**"
			doc = doc.replace("|", "\\|")
			s += "| `%s` | %d | %s | %d | %d | %s |\n" % [
				fname, e.lines, cls, _fanin_of(e.rel), e.preloads.size(), doc]
		s += "\n"
	return s


func _render_todo() -> String:
	var missing: Array = []
	for e in _files:
		if e.doc == "":
			missing.append(e.rel)
	var s := "## TODO — 缺少 `##` 职责注释\n\n"
	if missing.is_empty():
		s += "_(全部已标注)_\n"
		return s
	s += "这些脚本对 AI 检索不可见,补一行 `##` 注释即可。\n\n"
	for r in missing:
		s += "- `%s`\n" % r
	return s
