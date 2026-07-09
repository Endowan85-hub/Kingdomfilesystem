# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: RecruitPanel
#
# Role:
# Standalone floating panel for unit recruitment.
# Completely independent from MapDebugUI.
# Spawned by MapDebugView and positioned separately.
#
# Allowed Interactions:
# - MapDebugView via set_view() + ui_* calls only
# - UnitLibrary (read-only)
#
# Forbidden Responsibilities:
# - Must not modify GameState directly
# - Must not touch MapDebugUI
#
# Game Phase:
# Planning Phase
# ==================================================
extends Control
class_name RecruitPanel

const UnitLibrary = preload("res://Scripts/data/unit_library.gd")

const MIN_WIDTH: int = 260
const MIN_HEIGHT: int = 90
const HANDLE_SIZE: int = 16
const TITLE_HEIGHT: int = 26

var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _resizing: bool = false
var _resize_start_mouse: Vector2 = Vector2.ZERO
var _resize_start_size: Vector2 = Vector2.ZERO

var _gold_label: Label
var _biome_label: Label
var _type_option: OptionButton
var _recruit_btn: Button
var _resize_handle: Control
var _view: Node = null
var _current_biome: String = ""
var _current_types: Array[String] = []
var _current_leader_level: int = 1  # gates which unit tiers are available


func _ready() -> void:
	_build_ui()
	set_process_input(true)


func _build_ui() -> void:
	_gold_label    = $VBox/GoldLabel
	_biome_label   = $VBox/BiomeLabel
	_type_option   = $VBox/RecruitRow/TypeOption
	_recruit_btn   = $VBox/RecruitRow/RecruitButton
	_resize_handle = $ResizeHandle

	_recruit_btn.pressed.connect(_on_recruit_pressed)
	_resize_handle.draw.connect(_draw_handle)
	_reposition_handle()


func _draw_handle() -> void:
	for i in range(3):
		var offset: float = float(i) * 4.0 + 4.0
		_resize_handle.draw_line(
			Vector2(HANDLE_SIZE - 2, offset),
			Vector2(offset, HANDLE_SIZE - 2),
			Color(0.6, 0.6, 0.7, 0.8), 1.0
		)


func _reposition_handle() -> void:
	if _resize_handle != null:
		_resize_handle.position = size - Vector2(HANDLE_SIZE, HANDLE_SIZE)


func set_view(view: Node) -> void:
	_view = view


func refresh(biome: String = "", leader_level: int = -1) -> void:
	if _view != null and _view.has_method("ui_get_gold_text"):
		_gold_label.text = str(_view.call("ui_get_gold_text"))

	var needs_rebuild: bool = false
	if biome != "" and biome != _current_biome:
		_current_biome = biome
		needs_rebuild = true
	if leader_level >= 1 and leader_level != _current_leader_level:
		_current_leader_level = leader_level
		needs_rebuild = true
	if needs_rebuild:
		_rebuild_unit_list()

	if _biome_label != null:
		_biome_label.text = "Biome: %s" % (_current_biome.capitalize() if _current_biome != "" else "--")


func refresh_gold() -> void:
	refresh()


func _rebuild_unit_list() -> void:
	if _type_option == null:
		return
	_type_option.clear()
	# Use tier-gated function — leader level determines available tiers
	# Tier 1: always  |  Tier 2: Lv5+  |  Tier 3: Lv10+
	_current_types = UnitLibrary.get_types_for_biome_at_leader_level(_current_biome, _current_leader_level)
	for utype in _current_types:
		var cost: int = UnitLibrary.get_gold_cost(utype)
		var tpl: Dictionary = UnitLibrary.get_template(utype)
		var tier: int = int(tpl.get("tier", 1))
		var tier_label: String = "" if tier == 1 else (" [Veteran]" if tier == 2 else " [Elite]")
		_type_option.add_item("%s%s (%dg)" % [utype, tier_label, cost])


func _on_recruit_pressed() -> void:
	if _view == null or _type_option == null:
		return
	var idx: int = _type_option.selected
	if idx < 0 or idx >= _current_types.size():
		return
	_view.call("ui_recruit_unit", _current_types[idx])
	refresh()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# Ignore clicks outside this panel
				if not Rect2(global_position, size).has_point(mb.global_position):
					return
				var lp: Vector2 = mb.global_position - global_position
				# Resize handle zone
				var hrect := Rect2(size - Vector2(HANDLE_SIZE, HANDLE_SIZE), Vector2(HANDLE_SIZE, HANDLE_SIZE))
				if hrect.has_point(lp):
					_resizing = true
					_resize_start_mouse = mb.global_position
					_resize_start_size = size
					get_viewport().set_input_as_handled()
					return
				# Title bar drag zone
				var trect := Rect2(Vector2.ZERO, Vector2(size.x, TITLE_HEIGHT))
				if trect.has_point(lp):
					_dragging = true
					_drag_offset = global_position - mb.global_position
					get_viewport().set_input_as_handled()
					return
			else:
				_dragging = false
				_resizing = false
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			global_position = mm.global_position + _drag_offset
			_clamp_to_screen()
			get_viewport().set_input_as_handled()
		elif _resizing:
			var delta: Vector2 = mm.global_position - _resize_start_mouse
			var ns := _resize_start_size + delta
			ns.x = maxf(ns.x, MIN_WIDTH)
			ns.y = maxf(ns.y, MIN_HEIGHT)
			size = ns
			_reposition_handle()
			get_viewport().set_input_as_handled()


func _clamp_to_screen() -> void:
	var vp: Vector2 = get_viewport_rect().size
	global_position.x = clampf(global_position.x, 0.0, vp.x - size.x)
	global_position.y = clampf(global_position.y, 0.0, vp.y - size.y)
