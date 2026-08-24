class_name SkillDrawPanel
extends CanvasLayer
## Slot-machine reveal for the drawn skill. Purely cosmetic: the result is decided by SkillLoadout.roll().
## Lifecycle: play(candidates, result) -> spin decelerates -> lock -> hold -> hide + finished.

signal finished

const SPIN_TIME := 1.6
const HOLD_TIME := 1.7
const FONT_PATH := "res://assets/Fonts/Long_Cang/LongCang-Regular.ttf"

var _panel: PanelContainer
var _title_lbl: Label
var _roll_lbl: Label
var _hint_lbl: Label

var _names: Array[String] = []
var _result_text := ""
var _elapsed := 0.0
var _tick := 0.0
var _cursor := 0
var _spinning := false
var _locked := false


func _ready() -> void:
	layer = 20
	_build()
	visible = false


func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.45)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -260
	_panel.offset_right = 260
	_panel.offset_top = -110
	_panel.offset_bottom = 110
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.13, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(1.0, 0.82, 0.35, 0.85)
	style.set_corner_radius_all(12)
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	_panel.add_child(vbox)

	var font: Font = load(FONT_PATH) as Font if ResourceLoader.exists(FONT_PATH) else null

	_title_lbl = Label.new()
	_title_lbl.text = "🎲 技能抽取"
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.add_theme_font_size_override("font_size", 22)
	_title_lbl.modulate = Color(1.0, 0.85, 0.4)
	if font != null:
		_title_lbl.add_theme_font_override("font", font)
	vbox.add_child(_title_lbl)

	_roll_lbl = Label.new()
	_roll_lbl.text = ""
	_roll_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_roll_lbl.add_theme_font_size_override("font_size", 28)
	_roll_lbl.modulate = Color(0.85, 0.9, 1.0)
	vbox.add_child(_roll_lbl)

	_hint_lbl = Label.new()
	_hint_lbl.text = "正在从你的阵营技能池中抽取..."
	_hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_lbl.add_theme_font_size_override("font_size", 14)
	_hint_lbl.modulate = Color(0.65, 0.72, 0.85)
	vbox.add_child(_hint_lbl)


## play(): spins through display_names then locks on result_name. Pre: result_name is the already-rolled skill.
func play(display_names: Array[String], result_name: String) -> void:
	_names = display_names.duplicate()
	if _names.is_empty():
		_names = [result_name]
	_result_text = result_name
	_elapsed = 0.0
	_tick = 0.0
	_cursor = 0
	_spinning = true
	_locked = false
	visible = true
	_title_lbl.text = "🎲 技能抽取"
	_hint_lbl.text = "正在从你的阵营技能池中抽取..."
	_roll_lbl.modulate = Color(0.85, 0.9, 1.0)


func _process(delta: float) -> void:
	if not _spinning:
		return
	_elapsed += delta

	if not _locked:
		# Interval widens from 40ms to ~320ms across SPIN_TIME: the reel visibly slows down.
		var t := clampf(_elapsed / SPIN_TIME, 0.0, 1.0)
		var interval: float = lerpf(0.04, 0.32, t * t)
		_tick += delta
		if _tick >= interval:
			_tick = 0.0
			_cursor = (_cursor + 1) % _names.size()
			_roll_lbl.text = _names[_cursor]
		if _elapsed >= SPIN_TIME:
			_lock_result()
		return

	if _elapsed >= SPIN_TIME + HOLD_TIME:
		_spinning = false
		visible = false
		finished.emit()


func _lock_result() -> void:
	_locked = true
	_roll_lbl.text = _result_text
	_roll_lbl.modulate = Color(1.0, 0.85, 0.35)
	_title_lbl.text = "✨ 抽取完成"
	_hint_lbl.text = "本局技能已锁定 · 战斗中按 [1] 释放"
	var tw := create_tween()
	tw.tween_property(_roll_lbl, "scale", Vector2(1.18, 1.18), 0.12)
	tw.tween_property(_roll_lbl, "scale", Vector2.ONE, 0.16)
