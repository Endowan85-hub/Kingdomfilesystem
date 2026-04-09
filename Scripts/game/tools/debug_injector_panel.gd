# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: DebugInjectorPanel
#
# Role:
# Dev-only panel for injecting items and sigils
# directly into a selected province's inventory.
#
# Allowed Interactions:
# - ProvinceData (item_inventory, sigil_inventory)
# - ItemLibrary, SigilLibrary (read-only for listing)
#
# Forbidden Responsibilities:
# - Must not modify GameState economy or unit data
# - Must not queue orders into OrderBook
#
# Game Phase:
# Planning Phase (debug tool only)
# ==================================================

class_name DebugInjectorPanel
extends Control

const ItemLibrary = preload("res://Scripts/data/item_library.gd")
const SigilLibrary = preload("res://Scripts/data/sigil_library.gd")

var _view: Node = null  # reference to MapDebugView for live map_data access
var _selected_province_id: int = -1

var _tab_bar: TabBar
var _item_list: VBoxContainer
var _sigil_list: VBoxContainer
var _scroll_items: ScrollContainer
var _scroll_sigils: ScrollContainer
var _status_label: Label
var _province_label: Label

const PANEL_W: float = 300.0
const PANEL_H: float = 420.0


func _ready() -> void:
	_build_ui()
	hide()


func set_view(v: Node) -> void:
	_view = v


func refresh(province_id: int) -> void:
	_selected_province_id = province_id
	if province_id < 0 or _view == null or _view.map_data == null:
		_province_label.text = "No province selected"
		_clear_lists()
		return
	if province_id >= _view.map_data.provinces.size():
		_province_label.text = "Province ID out of range"
		_clear_lists()
		return
	var p: ProvinceData = _view.map_data.provinces[province_id] as ProvinceData
	if p == null:
		_province_label.text = "Invalid province"
		_clear_lists()
		return
	_province_label.text = "Province: %s (P%d)" % [str(p.display_name), province_id]
	_populate_items()
	_populate_sigils()


func _build_ui() -> void:
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	size = Vector2(PANEL_W, PANEL_H)

	# Background
	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.10, 0.14, 0.93)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	# Header
	var header_hbox := HBoxContainer.new()
	vbox.add_child(header_hbox)

	var title := Label.new()
	title.text = "  DEBUG INJECTOR"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(28, 24)
	close_btn.pressed.connect(func() -> void: hide())
	header_hbox.add_child(close_btn)

	# Province label
	_province_label = Label.new()
	_province_label.text = "No province selected"
	_province_label.add_theme_font_size_override("font_size", 11)
	_province_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	_province_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_province_label)

	# Separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Tabs
	_tab_bar = TabBar.new()
	_tab_bar.add_tab("Items")
	_tab_bar.add_tab("Sigils")
	_tab_bar.tab_changed.connect(_on_tab_changed)
	vbox.add_child(_tab_bar)

	# Item scroll
	_scroll_items = ScrollContainer.new()
	_scroll_items.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_items.custom_minimum_size = Vector2(0, 280)
	vbox.add_child(_scroll_items)

	_item_list = VBoxContainer.new()
	_item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_list.add_theme_constant_override("separation", 2)
	_scroll_items.add_child(_item_list)

	# Sigil scroll (hidden by default)
	_scroll_sigils = ScrollContainer.new()
	_scroll_sigils.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_sigils.custom_minimum_size = Vector2(0, 280)
	_scroll_sigils.hide()
	vbox.add_child(_scroll_sigils)

	_sigil_list = VBoxContainer.new()
	_sigil_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sigil_list.add_theme_constant_override("separation", 2)
	_scroll_sigils.add_child(_sigil_list)

	# Status
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 10)
	_status_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(_status_label)


func _on_tab_changed(tab: int) -> void:
	_scroll_items.visible = (tab == 0)
	_scroll_sigils.visible = (tab == 1)


func _clear_lists() -> void:
	for c in _item_list.get_children():
		c.queue_free()
	for c in _sigil_list.get_children():
		c.queue_free()


func _populate_items() -> void:
	for c in _item_list.get_children():
		c.queue_free()

	var items: Array = ItemLibrary.ITEMS if "ITEMS" in ItemLibrary else []
	if items.is_empty():
		var lbl := Label.new()
		lbl.text = "(no items found in ItemLibrary)"
		lbl.add_theme_font_size_override("font_size", 11)
		_item_list.add_child(lbl)
		return

	for item_data in items:
		var item_id: String = str(item_data.get("id", ""))
		var item_name: String = str(item_data.get("name", item_id))
		_item_list.add_child(_make_inject_row(item_name, item_id, false))


func _populate_sigils() -> void:
	for c in _sigil_list.get_children():
		c.queue_free()

	var sigils: Array = SigilLibrary.SIGILS if "SIGILS" in SigilLibrary else []
	if sigils.is_empty():
		var lbl := Label.new()
		lbl.text = "(no sigils found in SigilLibrary)"
		lbl.add_theme_font_size_override("font_size", 11)
		_sigil_list.add_child(lbl)
		return

	for sigil_data in sigils:
		var sigil_id: String = str(sigil_data.get("id", ""))
		var sigil_name: String = str(sigil_data.get("name", sigil_id))
		var tags: Array = sigil_data.get("tags", [])
		var display: String = "%s [%s]" % [sigil_name, ", ".join(tags)]
		_sigil_list.add_child(_make_inject_row(display, sigil_id, true))


func _make_inject_row(display_name: String, entry_id: String, is_sigil: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var lbl := Label.new()
	lbl.text = display_name
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	lbl.clip_text = true
	row.add_child(lbl)

	var btn := Button.new()
	btn.text = "+1"
	btn.custom_minimum_size = Vector2(34, 22)
	btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(func() -> void: _inject(entry_id, is_sigil))
	row.add_child(btn)

	return row


func _inject(entry_id: String, is_sigil: bool) -> void:
	if _selected_province_id < 0 or _view == null or _view.map_data == null or _selected_province_id >= _view.map_data.provinces.size():
		_status_label.text = "Select a province first."
		return
	var p: ProvinceData = _view.map_data.provinces[_selected_province_id] as ProvinceData
	if p == null:
		_status_label.text = "Invalid province."
		return

	if is_sigil:
		if not p.has_method("add_sigil"):
			_status_label.text = "Province has no add_sigil method."
			return
		p.add_sigil(entry_id)
		_status_label.text = "Added sigil: %s" % entry_id
	else:
		if not p.has_method("add_item"):
			_status_label.text = "Province has no add_item method."
			return
		p.add_item(entry_id, 1)
		_status_label.text = "Added item: %s" % entry_id
