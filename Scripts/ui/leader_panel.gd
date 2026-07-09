# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: LeaderPanel
#
# Role:
# Floating panel showing leaders + armies for the selected province.
# Leader header rows are clickable to toggle selection (max 3).
# Highlights selected leaders with a gold border.
# Shows queued order status on the left of each leader row.
# Supports drag-and-drop unit assignment.
#
# Allowed Interactions:
# - GameState (read/write units)
# - toggle_callback: Callable(leader_id: int) — called when a leader is clicked
# - selected_ids_callback: Callable() -> Array[int] — returns currently selected ids
# - order_book_ref: set externally for order status display
#
# Forbidden Responsibilities:
# - Must not queue orders
# - Must not execute simulation logic
#
# Game Phase:
# Planning Phase
# ==================================================
extends Control
class_name LeaderPanel

const UnitLibrary = preload("res://Scripts/data/unit_library.gd")
const ItemLibrary = preload("res://Scripts/data/item_library.gd")
const SigilLibrary = preload("res://Scripts/data/sigil_library.gd")
const AugmentLibrary = preload("res://Scripts/data/augment_library.gd")

const MIN_WIDTH: int = 280
const MIN_HEIGHT: int = 120
const HANDLE_SIZE: int = 16
const SLOT_COUNT: int = 6

const COL_LEADER_BG        := Color(0.20, 0.20, 0.28, 1.0)
const COL_LEADER_SELECTED  := Color(0.30, 0.22, 0.08, 1.0)
const COL_BORDER_SELECTED  := Color(0.95, 0.75, 0.25, 1.0)
const COL_LEADER_NAME      := Color(1.0, 0.90, 0.50)
const COL_ORDER_IDLE       := Color(0.50, 0.50, 0.55)
const COL_ORDER_ATTACK     := Color(1.0, 0.35, 0.35)
const COL_ORDER_XFER       := Color(0.35, 0.90, 0.45)
const COL_ORDER_MISSION    := Color(0.55, 0.75, 1.0)

var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _resizing: bool = false
var _resize_start_mouse: Vector2 = Vector2.ZERO
var _resize_start_size: Vector2 = Vector2.ZERO

var _panel: PanelContainer
var _title_bar: Panel
var _title_label: Label
var _scroll: ScrollContainer
var _leader_rows: VBoxContainer
var _resize_handle: Control

var _game_state = null
var _current_province_id: int = -1
var _active_tab: String = "army"  # "army" | "items" | "store" | "sigils"
var _tab_bar: HBoxContainer = null

# Callbacks set by map_debug_view
var toggle_callback: Callable = Callable()         # fn(leader_id: int)
var selected_ids_callback: Callable = Callable()   # fn() -> Array
var order_text_callback: Callable = Callable()     # fn(leader_id: int) -> String
var dismiss_callback: Callable = Callable()        # fn(leader_id: int) — called when player dismisses a general

var human_faction_id: int = 0
var heal_toggle_callback: Callable = Callable()   # fn(is_enabled: bool)
var heal_unit_callback: Callable = Callable()     # fn(unit_id: int, province_id: int) -> bool
var heal_cost_callback: Callable = Callable()     # fn(unit_id: int) -> int
var _heal_mode_enabled: bool = false
var _heal_button: Button = null

# Maps leader_id -> name_bar PanelContainer for highlight refresh
var _leader_bars: Dictionary = {}


func _ready() -> void:
	_build_ui()
	set_process_input(true)


func _build_ui() -> void:
	custom_minimum_size = Vector2(MIN_WIDTH, MIN_HEIGHT)

	_panel         = $Panel
	_title_bar     = $Panel/VBox/TitleBar
	_title_label   = $Panel/VBox/TitleBar/TitleLabel
	_heal_button   = $Panel/VBox/TitleBar/HealButton
	_tab_bar       = $Panel/VBox/TabBar
	_scroll        = $Panel/VBox/Scroll
	_leader_rows   = $Panel/VBox/Scroll/LeaderRows
	_resize_handle = $ResizeHandle

	_heal_button.pressed.connect(func() -> void:
		set_heal_mode(_heal_button.button_pressed)
	)

	var tab_names := ["army", "items", "store", "sigils"]
	var tab_nodes := ["ArmyTab", "ItemsTab", "StoreTab", "SigilsTab"]
	for i in tab_names.size():
		var captured_tab: String = tab_names[i]
		var btn: Button = _tab_bar.get_node(tab_nodes[i])
		btn.pressed.connect(func() -> void:
			_switch_tab(captured_tab)
		)

	_resize_handle.draw.connect(_draw_handle)
	_resize_handle.queue_redraw()
	_reposition_handle()


func _draw_handle() -> void:
	var lines: Array[Vector2] = [
		Vector2(HANDLE_SIZE - 4, 4), Vector2(4, HANDLE_SIZE - 4),
		Vector2(HANDLE_SIZE - 4, 8), Vector2(8, HANDLE_SIZE - 4),
		Vector2(HANDLE_SIZE - 4, 12), Vector2(12, HANDLE_SIZE - 4),
	]
	for i in range(0, lines.size(), 2):
		_resize_handle.draw_line(lines[i], lines[i + 1], Color(0.6, 0.6, 0.7, 0.8), 1.0)


func _reposition_handle() -> void:
	_resize_handle.position = size - Vector2(HANDLE_SIZE, HANDLE_SIZE)


func _input(event: InputEvent) -> void:
	var panel_rect := Rect2(global_position, size)

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if not panel_rect.has_point(mb.global_position):
					return
				var local_pos: Vector2 = mb.global_position - global_position
				var handle_rect := Rect2(size - Vector2(HANDLE_SIZE, HANDLE_SIZE), Vector2(HANDLE_SIZE, HANDLE_SIZE))
				if handle_rect.has_point(local_pos):
					_resizing = true
					_resize_start_mouse = mb.global_position
					_resize_start_size = size
					get_viewport().set_input_as_handled()
					return
				var title_rect := Rect2(Vector2.ZERO, Vector2(size.x, 28))
				if title_rect.has_point(local_pos):
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
			var new_size := _resize_start_size + delta
			new_size.x = maxf(new_size.x, MIN_WIDTH)
			new_size.y = maxf(new_size.y, MIN_HEIGHT)
			size = new_size
			_panel.size = size
			_reposition_handle()
			get_viewport().set_input_as_handled()


func _clamp_to_screen() -> void:
	var vp_size: Vector2 = get_viewport_rect().size
	global_position.x = clampf(global_position.x, 0.0, vp_size.x - size.x)
	global_position.y = clampf(global_position.y, 0.0, vp_size.y - size.y)


func set_heal_mode(enabled: bool) -> void:
	_heal_mode_enabled = enabled
	if _heal_button != null:
		_heal_button.button_pressed = enabled
		_heal_button.text = "Heal: ON" if enabled else "Heal: OFF"
		var normal_style := StyleBoxFlat.new()
		normal_style.bg_color = Color(0.24, 0.24, 0.30, 1.0) if not enabled else Color(0.20, 0.40, 0.22, 1.0)
		normal_style.border_width_left = 1
		normal_style.border_width_right = 1
		normal_style.border_width_top = 1
		normal_style.border_width_bottom = 1
		normal_style.border_color = Color(0.45, 0.45, 0.55, 1.0) if not enabled else Color(0.75, 1.0, 0.75, 1.0)
		_heal_button.add_theme_stylebox_override("normal", normal_style)
		_heal_button.add_theme_stylebox_override("pressed", normal_style)
		_heal_button.add_theme_stylebox_override("hover", normal_style)
	if heal_toggle_callback.is_valid():
		heal_toggle_callback.call(enabled)


func is_heal_mode_enabled() -> bool:
	return _heal_mode_enabled


func _try_heal_unit_click(unit_id: int) -> bool:
	if not _heal_mode_enabled or unit_id < 0:
		return false
	if heal_unit_callback.is_valid():
		var success: bool = bool(heal_unit_callback.call(unit_id, _current_province_id))
		if success:
			refresh(_current_province_id)
		return success
	return false


# --------------------------------------------------
# Public API
# --------------------------------------------------

func set_game_state(gs) -> void:
	_game_state = gs


func refresh(province_id: int) -> void:
	_current_province_id = province_id
	_leader_bars.clear()
	for child in _leader_rows.get_children():
		child.queue_free()

	if _game_state == null or province_id < 0:
		_title_label.text = "Army Panel"
		return

	var map_data = _game_state.map_data
	if map_data == null or province_id >= map_data.provinces.size():
		return

	_title_label.text = "Province %d — Army" % province_id

	var leaders: Array = _game_state.get_province_leaders(province_id, false)
	if leaders.is_empty():
		var lbl := Label.new()
		lbl.text = "  No leaders stationed here."
		lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_leader_rows.add_child(lbl)

	for leader in leaders:
		_leader_rows.add_child(_build_leader_row(leader))

	match _active_tab:
		"army":
			_leader_rows.add_child(_build_inventory_section(province_id))
			refresh_highlights()
		"items":
			_leader_rows.add_child(_build_items_section(province_id))
		"store":
			_leader_rows.add_child(_build_store_section(province_id))
		"sigils":
			_leader_rows.add_child(_build_sigils_section(province_id))
		_:
			_leader_rows.add_child(_build_inventory_section(province_id))
			refresh_highlights()


func refresh_highlights() -> void:
	var selected_ids: Array = []
	if selected_ids_callback.is_valid():
		selected_ids = selected_ids_callback.call()

	for lid in _leader_bars.keys():
		var bar: PanelContainer = _leader_bars[lid]
		if not is_instance_valid(bar):
			continue

		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(3)
		if selected_ids.has(int(lid)):
			style.bg_color = COL_LEADER_SELECTED
			style.border_width_left = 2
			style.border_width_right = 2
			style.border_width_top = 2
			style.border_width_bottom = 2
			style.border_color = COL_BORDER_SELECTED
		else:
			style.bg_color = COL_LEADER_BG
		bar.add_theme_stylebox_override("panel", style)

		# Update order label (first child of the HBox inside the bar)
		var hbox := bar.get_child(0) as HBoxContainer
		if hbox == null:
			continue
		var order_lbl := hbox.get_child(0) as Label
		if order_lbl == null:
			continue
		# Find the leader to check wounded state
		var order_text: String = "Idle"
		var order_color: Color = COL_ORDER_IDLE
		var refresh_leader = _game_state.get_leader(int(lid)) if _game_state != null and _game_state.has_method("get_leader") else null
		if refresh_leader != null and str(refresh_leader.status) == "wounded":
			var rt: int = int(refresh_leader.wounded_turns_remaining) if "wounded_turns_remaining" in refresh_leader else 0
			order_text = "Wounded"
			order_color = Color(0.80, 0.35, 0.35)
			# Also update name label with current turn count
			var name_lbl2 := hbox.get_child(1) as Label
			if name_lbl2 != null:
				name_lbl2.text = "%s [Wounded — %d turn%s]  Lv:%d" % [
					refresh_leader.display_name, rt, "s" if rt != 1 else "", int(refresh_leader.level)
				]
				name_lbl2.add_theme_color_override("font_color", Color(0.55, 0.55, 0.60))
		elif order_text_callback.is_valid():
			order_text = order_text_callback.call(int(lid))
			order_color = _order_color(order_text)
		order_lbl.text = "  " + order_text
		order_lbl.add_theme_color_override("font_color", order_color)


func _order_color(txt: String) -> Color:
	if txt.begins_with("Attack"):
		return COL_ORDER_ATTACK
	if txt.begins_with("→"):
		return COL_ORDER_XFER
	if txt != "Idle":
		return COL_ORDER_MISSION
	return COL_ORDER_IDLE


# --------------------------------------------------
# Leader row
# --------------------------------------------------

func _build_leader_row(leader) -> Control:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 4)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Clickable header bar
	var name_bar := PanelContainer.new()
	name_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	name_bar.custom_minimum_size = Vector2(0, 30)

	var is_wounded: bool = str(leader.status) == "wounded"
	var wound_turns: int = (int(leader.wounded_turns_remaining) if "wounded_turns_remaining" in leader else 0) if is_wounded else 0

	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.14, 0.14, 0.18, 1.0) if is_wounded else COL_LEADER_BG
	bar_style.set_corner_radius_all(3)
	name_bar.add_theme_stylebox_override("panel", bar_style)

	_leader_bars[int(leader.id)] = name_bar

	var bar_hbox := HBoxContainer.new()
	bar_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name_bar.add_child(bar_hbox)

	# Order status — left column (fixed width)
	var order_lbl := Label.new()
	order_lbl.custom_minimum_size = Vector2(90, 0)
	order_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	order_lbl.add_theme_font_size_override("font_size", 10)
	if is_wounded:
		order_lbl.text = "  Wounded"
		order_lbl.add_theme_color_override("font_color", Color(0.80, 0.35, 0.35))
	else:
		order_lbl.text = "  Idle"
		order_lbl.add_theme_color_override("font_color", COL_ORDER_IDLE)
	bar_hbox.add_child(order_lbl)

	# Name + stats
	var name_lbl := Label.new()
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cp_used: int = _game_state.get_leader_used_cp(leader) if _game_state != null and _game_state.has_method("get_leader_used_cp") else 0
	if is_wounded:
		name_lbl.text = "%s [Wounded — %d turn%s]  Lv:%d" % [
			leader.display_name, wound_turns, "s" if wound_turns != 1 else "", int(leader.level)
		]
		name_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.60))
	else:
		var status_str: String = "[%s]" % str(leader.status).capitalize()
		name_lbl.text = "%s %s  Lv:%d  HP:%d/%d  CP:%d/%d  %d/mo" % [
			leader.display_name, status_str, int(leader.level),
			int(leader.hp) if "hp" in leader else 0, int(leader.max_hp) if "max_hp" in leader else 0,
			cp_used, (int(leader.get_effective_max_cp()) if leader.has_method("get_effective_max_cp") else int(leader.max_cp)), int(leader.upkeep_cost)
		]
		name_lbl.add_theme_color_override("font_color", COL_LEADER_NAME)
	name_lbl.add_theme_font_size_override("font_size", 12)
	bar_hbox.add_child(name_lbl)

	# Dismiss button — only for human faction procedural generals with empty army
	var can_dismiss: bool = (
		not bool(leader.is_story_leader)
		and int(leader.faction_id) == human_faction_id
	)
	if can_dismiss:
		var army_empty: bool = true
		for uid in leader.army_unit_ids:
			if int(uid) >= 0:
				army_empty = false
				break
		if army_empty:
			var dismiss_btn := Button.new()
			dismiss_btn.text = "Dismiss"
			dismiss_btn.add_theme_font_size_override("font_size", 10)
			dismiss_btn.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
			dismiss_btn.mouse_filter = Control.MOUSE_FILTER_STOP
			var captured_lid: int = int(leader.id)
			dismiss_btn.pressed.connect(func() -> void:
				if dismiss_callback.is_valid():
					dismiss_callback.call(captured_lid)
			)
			bar_hbox.add_child(dismiss_btn)

	# Stat button — always visible
	var stat_btn := Button.new()
	stat_btn.text = "Stat"
	stat_btn.add_theme_font_size_override("font_size", 10)
	stat_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	var captured_leader_id: int = int(leader.id)
	stat_btn.pressed.connect(func() -> void:
		_open_leader_stat_sheet(captured_leader_id)
	)
	bar_hbox.add_child(stat_btn)

	# Click → toggle selection (blocked when wounded)
	var lid: int = int(leader.id)
	name_bar.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				if is_wounded:
					return  # Wounded leaders cannot be selected
				if toggle_callback.is_valid():
					toggle_callback.call(lid)
				name_bar.get_viewport().set_input_as_handled()
	)

	container.add_child(name_bar)

	# Unit slots
	var slot_row := HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 4)
	slot_row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for i in SLOT_COUNT:
		var unit_id: int = leader.army_unit_ids[i] if i < leader.army_unit_ids.size() else -1
		slot_row.add_child(_build_army_slot(unit_id, int(leader.id)))

	container.add_child(slot_row)
	container.add_child(HSeparator.new())
	return container


# --------------------------------------------------
# Army slots (unchanged logic)
# --------------------------------------------------

func _build_army_slot(unit_id: int, leader_id: int) -> Control:
	var slot := _DragSlot.new()
	slot.custom_minimum_size = Vector2(72, 64)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(3)
	var inner := VBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if unit_id >= 0 and _game_state != null:
		var unit = _game_state.get_unit(unit_id)
		if unit != null:
			style.bg_color = Color(0.18, 0.24, 0.18, 1.0)
			style.border_color = Color(0.4, 0.65, 0.4, 1.0)
			style.border_width_left = 1; style.border_width_right = 1
			style.border_width_top = 1; style.border_width_bottom = 1
			if "unit_name" in unit and str(unit.unit_name) != "":
				inner.add_child(_make_slot_label(str(unit.unit_name), 9, Color(1.0, 0.95, 0.7)))
			inner.add_child(_make_slot_label(unit.unit_type if unit.unit_type != "" else "Unit", 10, Color(0.85, 1.0, 0.85)))
			inner.add_child(_make_slot_label("CP:%d" % unit.cp_cost, 9, Color(0.7, 0.9, 0.7)))
			inner.add_child(_make_slot_label("Lv:%d" % unit.level, 9, Color(0.6, 0.8, 0.6)))
			inner.add_child(_make_slot_label("HP:%d/%d" % [int(unit.hp), int(unit.max_hp)], 9, Color(0.90, 0.70, 0.70)))
			inner.add_child(_make_slot_label("%d/mo" % unit.upkeep_cost, 9, Color(1.0, 0.75, 0.4)))
			if heal_cost_callback.is_valid() and int(unit.hp) < int(unit.max_hp):
				inner.add_child(_make_slot_label("Heal %dg" % int(heal_cost_callback.call(unit_id)), 9, Color(1.0, 0.85, 0.4)))

			# Promote button — level, leader tier gate, and gold checked
			var promotes_to: String = UnitLibrary.get_promotion(str(unit.unit_type))
			if promotes_to != "":
				var promo_cost: int = UnitLibrary.get_gold_cost(promotes_to)
				var current_tier: int = int(unit.tier)
				var required_unit_level: int = 5 if current_tier == 1 else 10
				var unit_level_met: bool = int(unit.level) >= required_unit_level
				var leader_level_met: bool = true  # Leader level does not gate promotion
				# Gold check
				var faction = null
				if _game_state != null:
					for f in _game_state.map_data.factions:
						var fd: FactionData = f as FactionData
						if fd != null and int(fd.id) == human_faction_id:
							faction = fd
							break
				var can_afford: bool = faction != null and int(faction.gold) >= promo_cost
				# CP check: promoted unit costs more CP — ensure leader has headroom
				var promo_tpl: Dictionary = UnitLibrary.get_template(promotes_to)
				var new_cp_cost: int = int(promo_tpl.get("cp_cost", int(unit.cp_cost)))
				var cp_delta: int = new_cp_cost - int(unit.cp_cost)
				var leader_data = _game_state.get_leader(leader_id) if _game_state != null else null
				var cp_used: int = _game_state.get_leader_used_cp(leader_data) if leader_data != null and _game_state.has_method("get_leader_used_cp") else 0
				var effective_max_cp: int = int(leader_data.get_effective_max_cp()) if leader_data != null and leader_data.has_method("get_effective_max_cp") else (int(leader_data.max_cp) if leader_data != null else 30)
				var cp_ok: bool = (cp_used + cp_delta) <= effective_max_cp
				var can_promote: bool = unit_level_met and leader_level_met and can_afford and cp_ok
				var promo_btn := Button.new()
				if can_promote:
					promo_btn.text = "▲ %dg" % promo_cost
					promo_btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
				elif not unit_level_met:
					promo_btn.text = "▲ Lv%d" % required_unit_level
					promo_btn.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
					promo_btn.disabled = true
				elif not cp_ok:
					promo_btn.text = "▲ CP full"
					promo_btn.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
					promo_btn.disabled = true
				else:
					promo_btn.text = "▲ Need%dg" % promo_cost
					promo_btn.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
					promo_btn.disabled = true
				promo_btn.add_theme_font_size_override("font_size", 9)
				promo_btn.mouse_filter = Control.MOUSE_FILTER_STOP
				if can_promote:
					var captured_uid: int = unit_id
					promo_btn.pressed.connect(func() -> void:
						_on_promote_pressed(captured_uid)
					)
				inner.add_child(promo_btn)

			# Stat button — opens unit stat sheet with item panel
			var stat_btn := Button.new()
			stat_btn.text = "Stat"
			stat_btn.add_theme_font_size_override("font_size", 9)
			stat_btn.mouse_filter = Control.MOUSE_FILTER_STOP
			var captured_stat_uid: int = unit_id
			stat_btn.pressed.connect(func() -> void:
				_open_stat_sheet(captured_stat_uid)
			)
			inner.add_child(stat_btn)

			slot.drag_payload = {
				"unit_id": unit_id, "from": "leader_slot",
				"leader_id": leader_id, "province_id": _current_province_id
			}
		else:
			_style_empty(style, inner)
	else:
		_style_empty(style, inner)

	slot.drop_type = "army_slot"
	slot.drop_leader_id = leader_id
	slot.panel_ref = self
	slot.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and _try_heal_unit_click(unit_id):
				slot.get_viewport().set_input_as_handled()
	)
	slot.add_theme_stylebox_override("panel", style)
	slot.add_child(inner)
	return slot


# --------------------------------------------------
# Inventory section
# --------------------------------------------------

func _on_promote_pressed(unit_id: int) -> void:
	if _game_state == null:
		return
	var unit = _game_state.get_unit(unit_id)
	if unit == null:
		return
	# Promote immediately — do not queue, apply now
	var success: bool = _game_state.promote_unit(human_faction_id, unit_id)
	if success:
		DebugLogger.log("UI promote applied | unit_id=%d" % unit_id)
	else:
		DebugLogger.log("UI promote failed | unit_id=%d" % unit_id)
	refresh(_current_province_id)


func _build_inventory_section(province_id: int) -> Control:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 4)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var header := _DragSlot.new()
	header.custom_minimum_size = Vector2(0, 28)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.drop_type = "inventory"
	header.drop_province_id = province_id
	header.panel_ref = self

	var header_style := StyleBoxFlat.new()
	header_style.bg_color = Color(0.16, 0.16, 0.22, 1.0)
	header_style.set_corner_radius_all(3)
	header.add_theme_stylebox_override("panel", header_style)

	var header_lbl := Label.new()
	header_lbl.text = "  Province Inventory  (drag here to unassign)"
	header_lbl.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	header_lbl.add_theme_font_size_override("font_size", 11)
	header_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(header_lbl)
	container.add_child(header)

	if _game_state == null or not _game_state.has_method("get_province_inventory_units"):
		return container

	var inv_units: Array = _game_state.get_province_inventory_units(province_id)
	if inv_units.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "  (empty — recruit units or drag from leaders)"
		empty_lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
		empty_lbl.add_theme_font_size_override("font_size", 11)
		container.add_child(empty_lbl)
		return container

	const COLS: int = 4
	var row: HBoxContainer = null
	for i in inv_units.size():
		if i % COLS == 0:
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			container.add_child(row)
		row.add_child(_build_inventory_slot(inv_units[i], province_id))

	if inv_units.size() % COLS != 0:
		var remaining: int = COLS - (inv_units.size() % COLS)
		for _p in remaining:
			var spacer := Control.new()
			spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(spacer)

	return container


func _build_inventory_slot(unit, province_id: int) -> Control:
	var slot := _DragSlot.new()
	slot.custom_minimum_size = Vector2(72, 64)
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(3)
	style.bg_color = Color(0.16, 0.20, 0.26, 1.0)
	style.border_color = Color(0.35, 0.50, 0.70, 1.0)
	style.border_width_left = 1; style.border_width_right = 1
	style.border_width_top = 1; style.border_width_bottom = 1
	slot.add_theme_stylebox_override("panel", style)

	var inner := VBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if "unit_name" in unit and str(unit.unit_name) != "":
		inner.add_child(_make_slot_label(str(unit.unit_name), 9, Color(1.0, 0.95, 0.7)))
	inner.add_child(_make_slot_label(unit.unit_type if unit.unit_type != "" else "Unit", 10, Color(0.75, 0.90, 1.0)))
	inner.add_child(_make_slot_label("CP:%d" % unit.cp_cost, 9, Color(0.55, 0.75, 0.95)))
	inner.add_child(_make_slot_label("Lv:%d" % unit.level, 9, Color(0.45, 0.65, 0.85)))
	inner.add_child(_make_slot_label("HP:%d/%d" % [int(unit.hp), int(unit.max_hp)], 9, Color(0.85, 0.70, 0.70)))
	inner.add_child(_make_slot_label("%d/mo" % unit.upkeep_cost, 9, Color(1.0, 0.75, 0.4)))
	slot.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and _try_heal_unit_click(int(unit.unit_id)):
				slot.get_viewport().set_input_as_handled()
	)
	slot.add_child(inner)

	slot.drag_payload = {
		"unit_id": unit.unit_id, "from": "inventory",
		"leader_id": -1, "province_id": province_id
	}
	slot.drop_type = "inventory"
	slot.drop_province_id = province_id
	slot.panel_ref = self
	return slot


# --------------------------------------------------
# Helpers
# --------------------------------------------------

func _make_slot_label(txt: String, font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = txt
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _style_empty(style: StyleBoxFlat, inner: VBoxContainer) -> void:
	style.bg_color = Color(0.14, 0.14, 0.18, 1.0)
	style.border_color = Color(0.3, 0.3, 0.38, 0.6)
	style.border_width_left = 1; style.border_width_right = 1
	style.border_width_top = 1; style.border_width_bottom = 1
	var lbl := Label.new()
	lbl.text = "[ Empty ]"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(lbl)


func _on_drop_complete() -> void:
	refresh(_current_province_id)


# --------------------------------------------------
# _DragSlot inner class
# --------------------------------------------------

class _DragSlot extends PanelContainer:
	var drag_payload: Dictionary = {}
	var drop_type: String = ""
	var drop_leader_id: int = -1
	var drop_province_id: int = -1
	var panel_ref: Control = null

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if drag_payload.is_empty():
			return null
		var preview := Label.new()
		var unit_id: int = drag_payload.get("unit_id", -1)
		if panel_ref != null and panel_ref._game_state != null:
			var u = panel_ref._game_state.get_unit(unit_id)
			preview.text = u.unit_type if u != null else "Unit"
		else:
			preview.text = "Unit"
		preview.add_theme_color_override("font_color", Color(1, 1, 0.5))
		preview.add_theme_font_size_override("font_size", 12)
		set_drag_preview(preview)
		return drag_payload

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		if not data is Dictionary or drop_type == "":
			return false
		var unit_id: int = data.get("unit_id", -1)
		if unit_id < 0 or panel_ref == null or panel_ref._game_state == null:
			return false
		var gs = panel_ref._game_state
		if drop_type == "army_slot":
			return gs.can_attach_unit(drop_leader_id, unit_id)
		if drop_type == "inventory":
			return data.get("from", "") == "leader_slot"
		return false

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if panel_ref == null or panel_ref._game_state == null:
			return
		var gs = panel_ref._game_state
		var unit_id: int = data.get("unit_id", -1)
		var from: String = data.get("from", "")
		var from_leader: int = data.get("leader_id", -1)
		var from_province: int = data.get("province_id", -1)
		if drop_type == "army_slot":
			if from == "leader_slot" and from_leader >= 0:
				gs.detach_unit(from_leader, unit_id)
			gs.move_unit_to_leader(unit_id, drop_leader_id)
		elif drop_type == "inventory":
			var prov: int = drop_province_id if drop_province_id >= 0 else from_province
			if from == "leader_slot" and from_leader >= 0:
				gs.move_unit_to_inventory(unit_id, prov)
		panel_ref._on_drop_complete()

# ==================================================
# UNIT STAT SHEET
# --------------------------------------------------
# Opens a floating window showing unit stats, XP progress,
# and item slot with equip/remove/replace controls.
# This is the only place items are visible and manageable on units.
# ==================================================

func _open_stat_sheet(unit_id: int) -> void:
	if _game_state == null:
		return
	var unit: UnitData = _game_state.get_unit(unit_id) as UnitData
	if unit == null:
		return
	# Remove any existing stat sheet
	var existing = get_parent().find_child("StatSheet", true, false)
	if existing != null:
		existing.queue_free()
	var sheet := _build_stat_sheet_window(unit)
	sheet.name = "StatSheet"
	get_parent().add_child(sheet)
	sheet.position = Vector2(300, 100)


func _build_stat_sheet_window(unit: UnitData) -> Control:
	var win := PanelContainer.new()
	win.custom_minimum_size = Vector2(280, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.20, 0.97)
	style.border_color = Color(0.5, 0.6, 0.9, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	win.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	win.add_child(vbox)

	# ── Close button ──────────────────────────────────────
	var top_bar := HBoxContainer.new()
	var title := Label.new()
	title.text = "Unit Stats"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.add_theme_font_size_override("font_size", 10)
	close_btn.pressed.connect(func() -> void: win.queue_free())
	top_bar.add_child(title)
	top_bar.add_child(close_btn)
	vbox.add_child(top_bar)
	vbox.add_child(_sheet_divider())

	# ── Header ────────────────────────────────────────────
	# Personal name above unit type in stat sheet
	if "unit_name" in unit and str(unit.unit_name) != "":
		var personal_name_lbl := Label.new()
		personal_name_lbl.text = str(unit.unit_name)
		personal_name_lbl.add_theme_font_size_override("font_size", 14)
		personal_name_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
		vbox.add_child(personal_name_lbl)
	var unit_name := Label.new()
	unit_name.text = str(unit.unit_type) if str(unit.unit_type) != "" else "Unit"
	unit_name.add_theme_font_size_override("font_size", 12)
	unit_name.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	vbox.add_child(unit_name)

	var tier_lv := Label.new()
	var tier_names := ["", "Recruit", "Veteran", "Elite"]
	var tier_str: String = tier_names[clampi(int(unit.tier), 0, 3)]
	tier_lv.text = "Tier %d (%s)  |  Level %d" % [int(unit.tier), tier_str, int(unit.level)]
	tier_lv.add_theme_font_size_override("font_size", 10)
	tier_lv.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	vbox.add_child(tier_lv)
	vbox.add_child(_sheet_divider())

	# ── Core Stats ────────────────────────────────────────
	var bonuses: Dictionary = ItemLibrary.get_unit_item_bonuses(str(unit.equipped_item_id))
	var atk_bonus: int = int(bonuses.get("attack", 0))
	var def_bonus: int = int(bonuses.get("defense", 0))
	var hp_bonus: int = int(bonuses.get("max_hp", 0))

	var stats_label := Label.new()
	var atk_str: String = "%d" % int(unit.attack) if atk_bonus == 0 else "%d base + %d item = %d" % [int(unit.attack) - atk_bonus, atk_bonus, int(unit.attack)]
	var def_str: String = "%d" % int(unit.defense) if def_bonus == 0 else "%d base + %d item = %d" % [int(unit.defense) - def_bonus, def_bonus, int(unit.defense)]
	var hp_base: int = int(unit.max_hp) - hp_bonus
	var hp_str: String = "%d/%d" % [int(unit.hp), int(unit.max_hp)] if hp_bonus == 0 else "%d/%d (%d base + %d item)" % [int(unit.hp), int(unit.max_hp), hp_base, hp_bonus]
	var unit_spd: int = int(unit.speed) if "speed" in unit else 4
	var unit_acc: int = int(unit.accuracy) if "accuracy" in unit else 75
	var unit_eva: int = int(unit.evasion) if "evasion" in unit else 8
	stats_label.text = "HP: %s\nAttack: %s\nDefense: %s\nSP: %d/%d\nDamage: %s\nSpeed: %d\nAccuracy: %d\nEvasion: %d\nCP Cost: %d\nUpkeep: %dg/mo" % [
		hp_str, atk_str, def_str,
		int(unit.skill_power) if "skill_power" in unit else 10, _calc_max_sp(int(unit.level)),
		str(unit.damage_type),
		unit_spd, unit_acc, unit_eva,
		int(unit.cp_cost), int(unit.upkeep_cost)
	]
	stats_label.add_theme_font_size_override("font_size", 10)
	stats_label.add_theme_color_override("font_color", Color(0.85, 0.90, 0.85))
	vbox.add_child(stats_label)
	vbox.add_child(_sheet_divider())

	# ── XP / Growth ───────────────────────────────────────
	var xp_label := Label.new()
	var promo_path: String = UnitLibrary.get_promotion(str(unit.unit_type))
	var promo_text: String = "Max tier" if promo_path == "" else "Promotes to: %s" % promo_path
	var req_lv: int = 5 if int(unit.tier) == 1 else 10
	xp_label.text = "XP: %d / %d\n%s\nPromotion at Lv%d" % [int(unit.xp), int(unit.xp_to_next_level), promo_text, req_lv]
	xp_label.add_theme_font_size_override("font_size", 10)
	xp_label.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	vbox.add_child(xp_label)
	vbox.add_child(_sheet_divider())

	# ── Item Panel ────────────────────────────────────────
	var item_header := Label.new()
	item_header.text = "EQUIPPED ITEM"
	item_header.add_theme_font_size_override("font_size", 10)
	item_header.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vbox.add_child(item_header)

	var equipped_id: String = str(unit.equipped_item_id)
	if equipped_id != "":
		var tpl: Dictionary = ItemLibrary.get_item(equipped_id)
		var item_label := Label.new()
		item_label.text = "%s\nTier %d  |  %s" % [
			str(tpl.get("name", equipped_id)),
			int(tpl.get("tier", 1)),
			str(tpl.get("description", ""))
		]
		item_label.add_theme_font_size_override("font_size", 10)
		item_label.add_theme_color_override("font_color", Color(0.9, 0.95, 0.7))
		vbox.add_child(item_label)

		var btn_row := HBoxContainer.new()
		var remove_btn := Button.new()
		remove_btn.text = "Remove"
		remove_btn.add_theme_font_size_override("font_size", 10)
		var captured_uid: int = int(unit.unit_id)
		remove_btn.pressed.connect(func() -> void:
			_game_state.unequip_item_from_unit(captured_uid)
			win.queue_free()
			refresh(_current_province_id)
		)
		var replace_btn := Button.new()
		replace_btn.text = "Replace"
		replace_btn.add_theme_font_size_override("font_size", 10)
		replace_btn.pressed.connect(func() -> void:
			win.queue_free()
			_open_item_picker(captured_uid, true)
		)
		btn_row.add_child(remove_btn)
		btn_row.add_child(replace_btn)
		vbox.add_child(btn_row)
	else:
		var no_item := Label.new()
		no_item.text = "No Item Equipped"
		no_item.add_theme_font_size_override("font_size", 10)
		no_item.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		vbox.add_child(no_item)
		var equip_btn := Button.new()
		equip_btn.text = "Equip Item"
		equip_btn.add_theme_font_size_override("font_size", 10)
		var captured_uid2: int = int(unit.unit_id)
		equip_btn.pressed.connect(func() -> void:
			win.queue_free()
			_open_item_picker(captured_uid2, false)
		)
		vbox.add_child(equip_btn)

	vbox.add_child(_sheet_divider())

	# ── Sigil Slot ────────────────────────────────────────
	var sigil_header := Label.new()
	sigil_header.text = "EQUIPPED SIGIL"
	sigil_header.add_theme_font_size_override("font_size", 10)
	sigil_header.add_theme_color_override("font_color", Color(0.7, 0.55, 1.0))
	vbox.add_child(sigil_header)

	var unit_sigil_id: String = str(unit.equipped_sigil_id) if "equipped_sigil_id" in unit else ""
	if unit_sigil_id != "":
		var stpl: Dictionary = SigilLibrary.get_sigil(unit_sigil_id)
		var sigil_lbl := Label.new()
		sigil_lbl.text = "%s\nTier %d  |  SP:%d  |  %s" % [
			str(stpl.get("name", unit_sigil_id)),
			int(stpl.get("tier", 1)),
			int(stpl.get("sp_cost", 0)),
			str(stpl.get("description", ""))
		]
		sigil_lbl.add_theme_font_size_override("font_size", 10)
		sigil_lbl.add_theme_color_override("font_color", Color(0.80, 0.70, 1.0))
		sigil_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(sigil_lbl)

		var sig_btn_row := HBoxContainer.new()
		var remove_sig_btn := Button.new()
		remove_sig_btn.text = "Remove"
		remove_sig_btn.add_theme_font_size_override("font_size", 10)
		remove_sig_btn.pressed.connect(func() -> void:
			var ret_sid: String = str(unit.equipped_sigil_id)
			unit.equipped_sigil_id = ""
			if ret_sid != "" and _game_state != null and _current_province_id >= 0:
				var _ret_prov = _game_state.map_data.provinces[_current_province_id]
				if _ret_prov != null and _ret_prov.has_method("add_sigil"):
					_ret_prov.add_sigil(ret_sid)
			win.queue_free()
			refresh(_current_province_id)
		)
		var replace_sig_btn := Button.new()
		replace_sig_btn.text = "Replace"
		replace_sig_btn.add_theme_font_size_override("font_size", 10)
		var c_uid_sig: int = int(unit.unit_id)
		replace_sig_btn.pressed.connect(func() -> void:
			win.queue_free()
			_open_sigil_picker_for_unit(c_uid_sig)
		)
		sig_btn_row.add_child(remove_sig_btn)
		sig_btn_row.add_child(replace_sig_btn)
		vbox.add_child(sig_btn_row)
	else:
		var no_sigil := Label.new()
		no_sigil.text = "No Sigil Equipped"
		no_sigil.add_theme_font_size_override("font_size", 10)
		no_sigil.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		vbox.add_child(no_sigil)

		var equip_sig_btn := Button.new()
		equip_sig_btn.text = "Equip Sigil"
		equip_sig_btn.add_theme_font_size_override("font_size", 10)
		var c_uid_sig2: int = int(unit.unit_id)
		equip_sig_btn.pressed.connect(func() -> void:
			win.queue_free()
			_open_sigil_picker_for_unit(c_uid_sig2)
		)
		vbox.add_child(equip_sig_btn)


	# ── Augment Slot (Tier 3+ / Level 10+ only) ───────────
	if int(unit.tier) >= 3 or int(unit.level) >= 10:
		vbox.add_child(_sheet_divider())
		var aug_header := Label.new()
		aug_header.text = "AUGMENT SLOT  (Tier 3+)"
		aug_header.add_theme_font_size_override("font_size", 10)
		aug_header.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
		vbox.add_child(aug_header)

		var unit_aug_id: String = str(unit.equipped_augment_id) if "equipped_augment_id" in unit else ""
		var unit_sigil_id2: String = str(unit.equipped_sigil_id) if "equipped_sigil_id" in unit else ""
		if unit_aug_id != "":
			var atpl: Dictionary = AugmentLibrary.get_augment(unit_aug_id)
			var aug_lbl := Label.new()
			aug_lbl.text = "%s\n%s" % [str(atpl.get("name", unit_aug_id)), str(atpl.get("description", ""))]
			aug_lbl.add_theme_font_size_override("font_size", 10)
			aug_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
			aug_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			vbox.add_child(aug_lbl)
			var aug_btn_row := HBoxContainer.new()
			var rem_aug_btn := Button.new()
			rem_aug_btn.text = "Remove"
			rem_aug_btn.add_theme_font_size_override("font_size", 10)
			rem_aug_btn.pressed.connect(func() -> void:
				unit.equipped_augment_id = ""
				win.queue_free()
				refresh(_current_province_id)
			)
			var rep_aug_btn := Button.new()
			rep_aug_btn.text = "Replace"
			rep_aug_btn.add_theme_font_size_override("font_size", 10)
			var c_uid_aug: int = int(unit.unit_id)
			rep_aug_btn.pressed.connect(func() -> void:
				win.queue_free()
				_open_augment_picker_for_unit(c_uid_aug)
			)
			aug_btn_row.add_child(rem_aug_btn)
			aug_btn_row.add_child(rep_aug_btn)
			vbox.add_child(aug_btn_row)
		else:
			var no_aug := Label.new()
			if unit_sigil_id2 == "":
				no_aug.text = "Equip a Sigil first."
			else:
				no_aug.text = "No Augment Equipped"
			no_aug.add_theme_font_size_override("font_size", 10)
			no_aug.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
			vbox.add_child(no_aug)
			if unit_sigil_id2 != "":
				var equip_aug_btn := Button.new()
				equip_aug_btn.text = "Equip Augment"
				equip_aug_btn.add_theme_font_size_override("font_size", 10)
				var c_uid_aug2: int = int(unit.unit_id)
				equip_aug_btn.pressed.connect(func() -> void:
					win.queue_free()
					_open_augment_picker_for_unit(c_uid_aug2)
				)
				vbox.add_child(equip_aug_btn)

	return win


func _open_item_picker(unit_id: int, is_replace: bool) -> void:
	if _game_state == null or _current_province_id < 0:
		return
	var province_data = _game_state.map_data.provinces[_current_province_id]
	if province_data == null:
		return
	# Remove existing picker
	var existing = get_parent().find_child("ItemPicker", true, false)
	if existing != null:
		existing.queue_free()

	var picker := PanelContainer.new()
	picker.name = "ItemPicker"
	picker.custom_minimum_size = Vector2(240, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.18, 0.97)
	style.border_color = Color(0.4, 0.6, 0.9, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	picker.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	picker.add_child(vbox)

	var hdr := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "Select Item to Equip"
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var x_btn := Button.new()
	x_btn.text = "X"
	x_btn.pressed.connect(func() -> void: picker.queue_free())
	hdr.add_child(lbl)
	hdr.add_child(x_btn)
	vbox.add_child(hdr)

	var has_any: bool = false
	for item_entry in province_data.item_inventory:
		var entry := item_entry as Dictionary
		var item_id: String = str(entry.get("item_id", ""))
		if item_id == "" or not ItemLibrary.is_valid_id(item_id):
			continue
		has_any = true
		var tpl: Dictionary = ItemLibrary.get_item(item_id)
		var row := HBoxContainer.new()
		var item_lbl := Label.new()
		item_lbl.text = "%s  (T%d)  Sell:%dg" % [
			str(tpl.get("name", item_id)),
			int(tpl.get("tier", 1)),
			int(tpl.get("sell_value", 0))
		]
		item_lbl.add_theme_font_size_override("font_size", 10)
		item_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var equip_btn := Button.new()
		equip_btn.text = "Equip"
		equip_btn.add_theme_font_size_override("font_size", 10)
		var c_uid: int = unit_id
		var c_iid: String = item_id
		var c_pid: int = _current_province_id
		equip_btn.pressed.connect(func() -> void:
			_game_state.equip_item_to_unit(c_uid, c_iid, c_pid)
			picker.queue_free()
			refresh(_current_province_id)
		)
		row.add_child(item_lbl)
		row.add_child(equip_btn)
		vbox.add_child(row)

	if not has_any:
		var empty_lbl := Label.new()
		empty_lbl.text = "No items in province inventory."
		empty_lbl.add_theme_font_size_override("font_size", 10)
		empty_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		vbox.add_child(empty_lbl)

	get_parent().add_child(picker)
	picker.position = Vector2(340, 120)


func _sheet_divider() -> Control:
	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color(0.3, 0.35, 0.5, 0.6))
	return sep


func _calc_max_sp(unit_level: int) -> int:
	return 10 + (unit_level - 1) * 2

# ==================================================
# TAB SYSTEM — Army / Items / Store
# ==================================================

func _switch_tab(tab_name: String) -> void:
	_active_tab = tab_name
	# Update button pressed states
	if _tab_bar != null:
		for btn in _tab_bar.get_children():
			var b := btn as Button
			if b != null:
				b.button_pressed = (b.text.to_lower() == tab_name)
	refresh(_current_province_id)


func _build_items_section(province_id: int) -> Control:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 4)

	if _game_state == null or province_id < 0:
		return container
	var province = _game_state.map_data.provinces[province_id]
	if province == null:
		return container

	var hdr := Label.new()
	hdr.text = "Province Item Inventory"
	hdr.add_theme_font_size_override("font_size", 11)
	hdr.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	container.add_child(hdr)

	var inventory: Array = province.item_inventory
	if inventory.is_empty():
		var empty := Label.new()
		empty.text = "  No items stored here."
		empty.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		empty.add_theme_font_size_override("font_size", 10)
		container.add_child(empty)
		return container

	for entry in inventory:
		var e := entry as Dictionary
		var item_id: String = str(e.get("item_id", ""))
		var qty: int = int(e.get("quantity", 0))
		if item_id == "" or qty <= 0:
			continue
		var tpl: Dictionary = ItemLibrary.get_item(item_id)
		if tpl.is_empty():
			continue

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var name_lbl := Label.new()
		var qty_str: String = "" if qty == 1 else " x%d" % qty
		name_lbl.text = "%s%s  (T%d)" % [str(tpl.get("name", item_id)), qty_str, int(tpl.get("tier", 1))]
		name_lbl.add_theme_font_size_override("font_size", 10)
		name_lbl.add_theme_color_override("font_color", Color(0.85, 0.90, 0.75))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		# Info button
		var info_btn := Button.new()
		info_btn.text = "Info"
		info_btn.add_theme_font_size_override("font_size", 9)
		var c_iid_info: String = item_id
		info_btn.pressed.connect(func() -> void:
			_open_item_info_window(c_iid_info)
		)
		row.add_child(info_btn)

		# Equip button
		var eq_btn := Button.new()
		eq_btn.text = "Equip"
		eq_btn.add_theme_font_size_override("font_size", 9)
		var c_iid: String = item_id
		var c_pid: int = province_id
		eq_btn.pressed.connect(func() -> void:
			_open_unit_picker_for_item(c_iid, c_pid)
		)
		row.add_child(eq_btn)

		# Sell button
		var sell_btn := Button.new()
		var sell_val: int = ItemLibrary.get_sell_value(item_id)
		sell_btn.text = "Sell %dg" % sell_val
		sell_btn.add_theme_font_size_override("font_size", 9)
		var c_iid2: String = item_id
		var c_pid2: int = province_id
		var c_owner: int = int(province.owner_id)
		sell_btn.pressed.connect(func() -> void:
			# Tier 3+ confirmation via popup
			var tier: int = ItemLibrary.get_tier(c_iid2)
			if tier >= 3:
				_confirm_sell(c_iid2, c_pid2, c_owner)
			else:
				_game_state.sell_item_from_province(c_pid2, c_iid2, c_owner)
				refresh(_current_province_id)
		)
		row.add_child(sell_btn)
		container.add_child(row)

	return container


func _build_sigils_section(province_id: int) -> Control:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 4)

	if _game_state == null or province_id < 0:
		return container
	var province = _game_state.map_data.provinces[province_id]
	if province == null:
		return container

	var hdr := Label.new()
	hdr.text = "Province Sigil Inventory"
	hdr.add_theme_font_size_override("font_size", 11)
	hdr.add_theme_color_override("font_color", Color(0.7, 0.55, 1.0))
	container.add_child(hdr)

	var sigil_inv: Array = province.sigil_inventory if province.has_method("add_sigil") else []
	if sigil_inv.is_empty():
		var empty := Label.new()
		empty.text = "  No sigils stored here."
		empty.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		empty.add_theme_font_size_override("font_size", 10)
		container.add_child(empty)
		return container

	var counts: Dictionary = {}
	for sid in sigil_inv:
		var key: String = str(sid)
		counts[key] = int(counts.get(key, 0)) + 1

	for sigil_id in counts.keys():
		var qty: int = int(counts[sigil_id])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var name_lbl := Label.new()
		var qty_str: String = "" if qty == 1 else " x%d" % qty
		name_lbl.text = "%s%s" % [sigil_id, qty_str]
		name_lbl.add_theme_font_size_override("font_size", 10)
		name_lbl.add_theme_color_override("font_color", Color(0.80, 0.70, 1.0))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		var discard_btn := Button.new()
		discard_btn.text = "Discard"
		discard_btn.add_theme_font_size_override("font_size", 9)
		var c_sid: String = sigil_id
		var c_pid: int = province_id
		discard_btn.pressed.connect(func() -> void:
			var p = _game_state.map_data.provinces[c_pid]
			if p != null and p.has_method("remove_sigil"):
				p.remove_sigil(c_sid)
			refresh(_current_province_id)
		)
		row.add_child(discard_btn)
		container.add_child(row)

	return container



func _build_store_section(province_id: int) -> Control:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 6)

	if _game_state == null or province_id < 0:
		return container
	var province = _game_state.map_data.provinces[province_id]
	if province == null:
		return container
	var faction_id: int = int(province.owner_id)
	var faction = null
	for f in _game_state.map_data.factions:
		if int((f as Object).get("id")) == faction_id:
			faction = f
			break
	var gold: int = faction.gold if faction != null else 0

	# ── BUY ─────────────────────────────────────────────
	var buy_hdr := Label.new()
	buy_hdr.text = "BUY  (Gold: %dg)" % gold
	buy_hdr.add_theme_font_size_override("font_size", 11)
	buy_hdr.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	container.add_child(buy_hdr)

	var catalog: Array = ItemLibrary.STORE_CATALOG
	for item_id in catalog:
		var tpl: Dictionary = ItemLibrary.get_item(item_id)
		if tpl.is_empty():
			continue
		var cost: int = int(tpl.get("buy_value", 0))
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "%s — %dg" % [str(tpl.get("name", item_id)), cost]
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", Color(0.85, 0.90, 0.75))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var buy_btn := Button.new()
		buy_btn.text = "Buy"
		buy_btn.add_theme_font_size_override("font_size", 9)
		buy_btn.disabled = gold < cost
		var c_iid: String = item_id
		var c_pid: int = province_id
		var c_fid: int = faction_id
		buy_btn.pressed.connect(func() -> void:
			_game_state.buy_item_for_province(c_pid, c_iid, c_fid)
			refresh(_current_province_id)
		)
		row.add_child(lbl)
		row.add_child(buy_btn)
		container.add_child(row)

	# ── SELL ─────────────────────────────────────────────
	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color(0.3, 0.35, 0.5, 0.6))
	container.add_child(sep)

	var sell_hdr := Label.new()
	sell_hdr.text = "SELL"
	sell_hdr.add_theme_font_size_override("font_size", 11)
	sell_hdr.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	container.add_child(sell_hdr)

	var inventory: Array = province.item_inventory
	if inventory.is_empty():
		var empty := Label.new()
		empty.text = "  Nothing to sell."
		empty.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		empty.add_theme_font_size_override("font_size", 10)
		container.add_child(empty)
	else:
		for entry in inventory:
			var e := entry as Dictionary
			var item_id: String = str(e.get("item_id", ""))
			var qty: int = int(e.get("quantity", 0))
			if item_id == "" or qty <= 0:
				continue
			var tpl: Dictionary = ItemLibrary.get_item(item_id)
			if tpl.is_empty():
				continue
			var sell_val: int = ItemLibrary.get_sell_value(item_id)
			var row := HBoxContainer.new()
			var qty_str: String = "" if qty == 1 else " x%d" % qty
			var lbl := Label.new()
			lbl.text = "%s%s → %dg" % [str(tpl.get("name", item_id)), qty_str, sell_val]
			lbl.add_theme_font_size_override("font_size", 10)
			lbl.add_theme_color_override("font_color", Color(0.85, 0.90, 0.75))
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var sell_btn := Button.new()
			sell_btn.text = "Sell"
			sell_btn.add_theme_font_size_override("font_size", 9)
			var c_iid: String = item_id
			var c_pid: int = province_id
			var c_fid: int = faction_id
			sell_btn.pressed.connect(func() -> void:
				var tier: int = ItemLibrary.get_tier(c_iid)
				if tier >= 3:
					_confirm_sell(c_iid, c_pid, c_fid)
				else:
					_game_state.sell_item_from_province(c_pid, c_iid, c_fid)
					refresh(_current_province_id)
			)
			row.add_child(lbl)
			row.add_child(sell_btn)
			container.add_child(row)

	return container


func _open_unit_picker_for_item(item_id: String, province_id: int) -> void:
	# Guard: if item is exhausted in province, do not reopen
	if _game_state != null and province_id >= 0:
		var _prov = _game_state.map_data.provinces[province_id]
		if _prov != null and not _prov.has_item(item_id):
			return
	# Show a small popup listing units in the province to equip the item to
	var existing = get_parent().find_child("UnitPicker", true, false)
	if existing != null:
		existing.queue_free()

	var picker := PanelContainer.new()
	picker.name = "UnitPicker"
	picker.custom_minimum_size = Vector2(220, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.18, 0.97)
	style.border_color = Color(0.4, 0.6, 0.9, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	picker.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	picker.add_child(vbox)

	var hdr_row := HBoxContainer.new()
	var tpl: Dictionary = ItemLibrary.get_item(item_id)
	var hdr := Label.new()
	hdr.text = "Equip: %s" % str(tpl.get("name", item_id))
	hdr.add_theme_font_size_override("font_size", 10)
	hdr.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
	hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var x_btn := Button.new()
	x_btn.text = "X"
	x_btn.pressed.connect(func() -> void: picker.queue_free())
	hdr_row.add_child(hdr)
	hdr_row.add_child(x_btn)
	vbox.add_child(hdr_row)

	var province = _game_state.map_data.provinces[province_id]
	var has_units: bool = false
	for lid_val in province.leader_ids:
		var leader = _game_state.get_leader(int(lid_val))
		if leader == null or bool(leader.on_mission):
			continue
		for uid_val in leader.army_unit_ids:
			var unit = _game_state.get_unit(int(uid_val))
			if unit == null or not unit.is_alive():
				continue
			has_units = true
			var row := HBoxContainer.new()
			var lbl := Label.new()
			var cur_item: String = str(unit.equipped_item_id)
			var cur_str: String = "" if cur_item == "" else "  [has item]"
			lbl.text = "%s Lv%d%s" % [str(unit.unit_type), int(unit.level), cur_str]
			lbl.add_theme_font_size_override("font_size", 10)
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var eq_btn := Button.new()
			eq_btn.text = "Equip"
			eq_btn.add_theme_font_size_override("font_size", 9)
			var c_uid: int = int(unit.unit_id)
			var c_iid: String = item_id
			var c_pid: int = province_id
			eq_btn.pressed.connect(func() -> void:
				_game_state.equip_item_to_unit(c_uid, c_iid, c_pid)
				picker.queue_free()
				refresh(_current_province_id)
				# Reopen picker so player can equip remaining units
				_open_unit_picker_for_item(c_iid, c_pid)
			)
			row.add_child(lbl)
			row.add_child(eq_btn)
			vbox.add_child(row)

	if not has_units:
		var empty := Label.new()
		empty.text = "No available units."
		empty.add_theme_font_size_override("font_size", 10)
		empty.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		vbox.add_child(empty)

	get_parent().add_child(picker)
	picker.position = Vector2(350, 140)


func _open_item_info_window(item_id: String) -> void:
	var tpl: Dictionary = ItemLibrary.get_item(item_id)
	if tpl.is_empty():
		return
	var win := Window.new()
	win.title = str(tpl.get("name", item_id))
	win.size = Vector2i(300, 260)
	win.unresizable = true
	add_child(win)
	win.popup_centered()
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 6)
	win.add_child(vbox)
	# Name + tier
	var name_lbl := Label.new()
	name_lbl.text = "%s  (Tier %d)" % [str(tpl.get("name", item_id)), int(tpl.get("tier", 1))]
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vbox.add_child(name_lbl)
	# Description
	var desc_lbl := Label.new()
	desc_lbl.text = str(tpl.get("description", "No description available."))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.add_theme_color_override("font_color", Color(0.80, 0.85, 0.80))
	vbox.add_child(desc_lbl)
	# Stats
	var bonuses: Dictionary = ItemLibrary.get_unit_item_bonuses(item_id)
	var stat_lines: Array = []
	if int(bonuses.get("attack", 0)) != 0: stat_lines.append("Attack: +%d" % int(bonuses["attack"]))
	if int(bonuses.get("defense", 0)) != 0: stat_lines.append("Defense: +%d" % int(bonuses["defense"]))
	if int(bonuses.get("max_hp", 0)) != 0: stat_lines.append("HP: +%d" % int(bonuses["max_hp"]))
	if bool(tpl.get("is_consumable", false)): stat_lines.append("Consumable (used in battle)")
	if not stat_lines.is_empty():
		var stat_lbl := Label.new()
		stat_lbl.text = "\n".join(stat_lines)
		stat_lbl.add_theme_font_size_override("font_size", 10)
		stat_lbl.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
		vbox.add_child(stat_lbl)
	# Sell value
	var sell_val: int = ItemLibrary.get_sell_value(item_id)
	var sell_lbl := Label.new()
	sell_lbl.text = "Sell value: %dg" % sell_val
	sell_lbl.add_theme_font_size_override("font_size", 10)
	sell_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(sell_lbl)
	# Close button
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func() -> void: win.queue_free())
	vbox.add_child(close_btn)


func _confirm_sell(item_id: String, province_id: int, faction_id: int) -> void:
	# Small confirmation popup for Tier 3+ items
	var existing = get_parent().find_child("SellConfirm", true, false)
	if existing != null:
		existing.queue_free()
	var popup := PanelContainer.new()
	popup.name = "SellConfirm"
	popup.custom_minimum_size = Vector2(200, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.10, 0.10, 0.97)
	style.border_color = Color(0.9, 0.4, 0.4, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	popup.add_theme_stylebox_override("panel", style)
	var vbox := VBoxContainer.new()
	popup.add_child(vbox)
	var tpl: Dictionary = ItemLibrary.get_item(item_id)
	var lbl := Label.new()
	lbl.text = "Sell %s for %dg?" % [str(tpl.get("name", item_id)), ItemLibrary.get_sell_value(item_id)]
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.75))
	vbox.add_child(lbl)
	var btn_row := HBoxContainer.new()
	var yes_btn := Button.new()
	yes_btn.text = "Yes, Sell"
	yes_btn.add_theme_font_size_override("font_size", 10)
	var c_iid: String = item_id
	var c_pid: int = province_id
	var c_fid: int = faction_id
	yes_btn.pressed.connect(func() -> void:
		_game_state.sell_item_from_province(c_pid, c_iid, c_fid)
		popup.queue_free()
		refresh(_current_province_id)
	)
	var no_btn := Button.new()
	no_btn.text = "Cancel"
	no_btn.add_theme_font_size_override("font_size", 10)
	no_btn.pressed.connect(func() -> void: popup.queue_free())
	btn_row.add_child(yes_btn)
	btn_row.add_child(no_btn)
	vbox.add_child(btn_row)
	get_parent().add_child(popup)
	popup.position = Vector2(320, 160)


# ==================================================
# Leader Stat Sheet
# ==================================================

func _open_leader_stat_sheet(leader_id: int) -> void:
	if _game_state == null:
		return
	var leader = _game_state.get_leader(leader_id)
	if leader == null:
		return
	var existing = get_parent().find_child("LeaderStatSheet", true, false)
	if existing != null:
		existing.queue_free()
	var sheet := _build_leader_stat_sheet_window(leader)
	sheet.name = "LeaderStatSheet"
	get_parent().add_child(sheet)
	sheet.position = Vector2(320, 80)


func _build_leader_stat_sheet_window(leader) -> Control:
	var win := PanelContainer.new()
	win.custom_minimum_size = Vector2(280, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.20, 0.97)
	style.border_color = Color(0.9, 0.75, 0.35, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	win.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	win.add_child(vbox)

	# ── Close button ──────────────────────────────────────
	var top_bar := HBoxContainer.new()
	var title := Label.new()
	title.text = "Leader Stats"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.add_theme_font_size_override("font_size", 10)
	close_btn.pressed.connect(func() -> void: win.queue_free())
	top_bar.add_child(title)
	top_bar.add_child(close_btn)
	vbox.add_child(top_bar)
	vbox.add_child(_sheet_divider())

	# ── Header ────────────────────────────────────────────
	var name_lbl := Label.new()
	name_lbl.text = str(leader.display_name)
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	vbox.add_child(name_lbl)

	var type_lbl := Label.new()
	var leader_type: String = "Story Leader" if bool(leader.is_story_leader) else "General"
	var status_str: String = str(leader.status).capitalize()
	type_lbl.text = "%s  |  %s  |  Level %d" % [leader_type, status_str, int(leader.level)]
	type_lbl.add_theme_font_size_override("font_size", 10)
	type_lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	vbox.add_child(type_lbl)
	vbox.add_child(_sheet_divider())

	# ── Core Stats ────────────────────────────────────────
	var ldr_dtype: String = str(leader.damage_type).capitalize() if "damage_type" in leader else "Slash"
	var ldr_spd: int = int(leader.speed) if "speed" in leader else 4
	var ldr_acc: int = int(leader.accuracy) if "accuracy" in leader else 72
	var ldr_eva: int = int(leader.evasion) if "evasion" in leader else 10
	var stats_lbl := Label.new()
	# Compute effective combat stats (same formula as battle_unit.gd)
	var lvl: int = int(leader.level)
	var item_id: String = str(leader.equipped_item_id) if "equipped_item_id" in leader else ""
	var item_bonuses: Dictionary = {}
	if item_id != "":
		item_bonuses = ItemLibrary.get_unit_item_bonuses(item_id)
	var item_atk: int = int(item_bonuses.get("attack", 0))
	var item_def: int = int(item_bonuses.get("defense", 0))
	var item_hp: int = int(item_bonuses.get("max_hp", 0))
	var eff_atk: int = maxi(18, int(leader.attack) + lvl) + item_atk
	var eff_def: int = maxi(12, int(leader.defense) + int(lvl * 0.5)) + item_def
	var eff_hp: int = maxi(65, 65 + lvl * 3 + int(leader.defense)) + item_hp
	stats_lbl.text = "HP:         %d/%d\nLeadership: %d\nAttack:     %d\nDefense:    %d\nWeapon:     %s\nSpeed:      %d\nAccuracy:   %d\nEvasion:    %d\nSP:         %d/%d\nUpkeep:     %dg/mo\nCP Budget:  %d" % [
		eff_hp, eff_hp,
		int(leader.leadership), eff_atk,
		eff_def,
		ldr_dtype, ldr_spd, ldr_acc, ldr_eva,
		int(leader.skill_power) if "skill_power" in leader else 10, _calc_max_sp(int(leader.level)),
		int(leader.upkeep_cost), (int(leader.get_effective_max_cp()) if leader.has_method("get_effective_max_cp") else int(leader.max_cp))
	]
	stats_lbl.add_theme_font_size_override("font_size", 10)
	stats_lbl.add_theme_color_override("font_color", Color(0.85, 0.90, 0.85))
	vbox.add_child(stats_lbl)
	vbox.add_child(_sheet_divider())

	# ── XP ────────────────────────────────────────────────
	var xp_lbl := Label.new()
	xp_lbl.text = "XP: %d / %d" % [int(leader.xp), int(leader.xp_to_next_level)]
	xp_lbl.add_theme_font_size_override("font_size", 10)
	xp_lbl.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	vbox.add_child(xp_lbl)
	vbox.add_child(_sheet_divider())

	# ── Item Slot ─────────────────────────────────────────
	var item_header := Label.new()
	item_header.text = "EQUIPPED ITEM"
	item_header.add_theme_font_size_override("font_size", 10)
	item_header.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vbox.add_child(item_header)

	var equipped_id: String = str(leader.equipped_item_id)
	if equipped_id != "":
		
		var tpl: Dictionary = ItemLibrary.get_item(equipped_id)
		var item_lbl := Label.new()
		item_lbl.text = "%s\nTier %d  |  %s" % [
			str(tpl.get("name", equipped_id)),
			int(tpl.get("tier", 1)),
			str(tpl.get("description", ""))
		]
		item_lbl.add_theme_font_size_override("font_size", 10)
		item_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 0.7))
		vbox.add_child(item_lbl)

		var btn_row := HBoxContainer.new()
		var remove_btn := Button.new()
		remove_btn.text = "Remove"
		remove_btn.add_theme_font_size_override("font_size", 10)
		var c_lid: int = int(leader.id)
		remove_btn.pressed.connect(func() -> void:
			var _item_to_return: String = str(leader.equipped_item_id)
			leader.equipped_item_id = ""
			# Return item to province inventory
			if _item_to_return != "" and _game_state != null:
				var _ret_prov = _game_state.map_data.provinces[_current_province_id] if _current_province_id >= 0 else null
				if _ret_prov != null:
					_ret_prov.add_item(_item_to_return, 1)
			win.queue_free()
			refresh(_current_province_id)
		)
		var replace_btn := Button.new()
		replace_btn.text = "Replace"
		replace_btn.add_theme_font_size_override("font_size", 10)
		replace_btn.pressed.connect(func() -> void:
			win.queue_free()
			_open_leader_item_picker(c_lid)
		)
		btn_row.add_child(remove_btn)
		btn_row.add_child(replace_btn)
		vbox.add_child(btn_row)
	else:
		var no_item := Label.new()
		no_item.text = "No Item Equipped"
		no_item.add_theme_font_size_override("font_size", 10)
		no_item.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		vbox.add_child(no_item)

		var equip_btn := Button.new()
		equip_btn.text = "Equip Item"
		equip_btn.add_theme_font_size_override("font_size", 10)
		var c_lid2: int = int(leader.id)
		equip_btn.pressed.connect(func() -> void:
			win.queue_free()
			_open_leader_item_picker(c_lid2)
		)
		vbox.add_child(equip_btn)

	vbox.add_child(_sheet_divider())

	# ── Signature Ability ─────────────────────────────────
	var sig_ability_id: String = str(leader.signature_ability_id) if "signature_ability_id" in leader else ""
	if sig_ability_id != "":
		vbox.add_child(_sheet_divider())
		var sig_hdr := Label.new()
		sig_hdr.text = "SIGNATURE ABILITY  ✦"
		sig_hdr.add_theme_font_size_override("font_size", 10)
		sig_hdr.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		vbox.add_child(sig_hdr)
		var sig_data: Dictionary = SigilLibrary.get_signature_ability(sig_ability_id)
		if not sig_data.is_empty():
			var sig_btn := Button.new()
			sig_btn.text = "%s  ✦  SP:%d  [%s]" % [
				str(sig_data.get("name", sig_ability_id)),
				int(sig_data.get("sp_cost", 0)),
				str(sig_data.get("action_type", "standard")).capitalize()
			]
			sig_btn.add_theme_font_size_override("font_size", 10)
			sig_btn.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
			sig_btn.autowrap_mode = TextServer.AUTOWRAP_WORD
			sig_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var c_sig_data: Dictionary = sig_data.duplicate()
			sig_btn.pressed.connect(func() -> void:
				_open_signature_ability_popup(c_sig_data)
			)
			vbox.add_child(sig_btn)
			var locked_lbl := Label.new()
			locked_lbl.text = "[ Innate — cannot be removed ]"
			locked_lbl.add_theme_font_size_override("font_size", 9)
			locked_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			vbox.add_child(locked_lbl)

	# ── Sigil Slot ────────────────────────────────────────
	var ldr_sigil_header := Label.new()
	ldr_sigil_header.text = "EQUIPPED SIGIL"
	ldr_sigil_header.add_theme_font_size_override("font_size", 10)
	ldr_sigil_header.add_theme_color_override("font_color", Color(0.7, 0.55, 1.0))
	vbox.add_child(ldr_sigil_header)

	var ldr_sigil_id: String = str(leader.equipped_sigil_id) if "equipped_sigil_id" in leader else ""
	if ldr_sigil_id != "":
		var stpl: Dictionary = SigilLibrary.get_sigil(ldr_sigil_id)
		var sigil_lbl := Label.new()
		sigil_lbl.text = "%s\nTier %d  |  SP:%d  |  %s" % [
			str(stpl.get("name", ldr_sigil_id)),
			int(stpl.get("tier", 1)),
			int(stpl.get("sp_cost", 0)),
			str(stpl.get("description", ""))
		]
		sigil_lbl.add_theme_font_size_override("font_size", 10)
		sigil_lbl.add_theme_color_override("font_color", Color(0.80, 0.70, 1.0))
		sigil_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(sigil_lbl)

		var sig_btn_row := HBoxContainer.new()
		var remove_sig_btn := Button.new()
		remove_sig_btn.text = "Remove"
		remove_sig_btn.add_theme_font_size_override("font_size", 10)
		var c_lid_rm: int = int(leader.id)
		remove_sig_btn.pressed.connect(func() -> void:
			var ldr_rm = _game_state.get_leader(c_lid_rm)
			if ldr_rm != null:
				var ret_sid: String = str(ldr_rm.equipped_sigil_id)
				ldr_rm.equipped_sigil_id = ""
				if ret_sid != "" and _current_province_id >= 0:
					var _ret_prov = _game_state.map_data.provinces[_current_province_id]
					if _ret_prov != null and _ret_prov.has_method("add_sigil"):
						_ret_prov.add_sigil(ret_sid)
			win.queue_free()
			refresh(_current_province_id)
		)
		var replace_sig_btn := Button.new()
		replace_sig_btn.text = "Replace"
		replace_sig_btn.add_theme_font_size_override("font_size", 10)
		var c_lid_rep: int = int(leader.id)
		replace_sig_btn.pressed.connect(func() -> void:
			win.queue_free()
			_open_leader_sigil_picker(c_lid_rep)
		)
		sig_btn_row.add_child(remove_sig_btn)
		sig_btn_row.add_child(replace_sig_btn)
		vbox.add_child(sig_btn_row)
	else:
		var no_sigil := Label.new()
		no_sigil.text = "No Sigil Equipped"
		no_sigil.add_theme_font_size_override("font_size", 10)
		no_sigil.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		vbox.add_child(no_sigil)

		var equip_sig_btn := Button.new()
		equip_sig_btn.text = "Equip Sigil"
		equip_sig_btn.add_theme_font_size_override("font_size", 10)
		var c_lid3: int = int(leader.id)
		equip_sig_btn.pressed.connect(func() -> void:
			win.queue_free()
			_open_leader_sigil_picker(c_lid3)
		)
		vbox.add_child(equip_sig_btn)


	# ── Augment Slot (Level 10+ leaders) ──────────────────
	if int(leader.level) >= 10:
		vbox.add_child(_sheet_divider())
		var ldr_aug_header := Label.new()
		ldr_aug_header.text = "AUGMENT SLOT  (Lv10+)"
		ldr_aug_header.add_theme_font_size_override("font_size", 10)
		ldr_aug_header.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
		vbox.add_child(ldr_aug_header)

		var ldr_aug_id: String = str(leader.equipped_augment_id) if "equipped_augment_id" in leader else ""
		var ldr_sigil_id2: String = str(leader.equipped_sigil_id) if "equipped_sigil_id" in leader else ""
		if ldr_aug_id != "":
			var atpl: Dictionary = AugmentLibrary.get_augment(ldr_aug_id)
			var aug_lbl := Label.new()
			aug_lbl.text = "%s\n%s" % [str(atpl.get("name", ldr_aug_id)), str(atpl.get("description", ""))]
			aug_lbl.add_theme_font_size_override("font_size", 10)
			aug_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
			aug_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			vbox.add_child(aug_lbl)
			var aug_btn_row := HBoxContainer.new()
			var rem_aug_btn := Button.new()
			rem_aug_btn.text = "Remove"
			rem_aug_btn.add_theme_font_size_override("font_size", 10)
			var c_lid_rem_aug: int = int(leader.id)
			rem_aug_btn.pressed.connect(func() -> void:
				var ldr_rm = _game_state.get_leader(c_lid_rem_aug)
				if ldr_rm != null: ldr_rm.equipped_augment_id = ""
				win.queue_free()
				refresh(_current_province_id)
			)
			var rep_aug_btn := Button.new()
			rep_aug_btn.text = "Replace"
			rep_aug_btn.add_theme_font_size_override("font_size", 10)
			var c_lid_rep_aug: int = int(leader.id)
			rep_aug_btn.pressed.connect(func() -> void:
				win.queue_free()
				_open_leader_augment_picker(c_lid_rep_aug)
			)
			aug_btn_row.add_child(rem_aug_btn)
			aug_btn_row.add_child(rep_aug_btn)
			vbox.add_child(aug_btn_row)
		else:
			var no_aug := Label.new()
			if ldr_sigil_id2 == "":
				no_aug.text = "Equip a Sigil first."
			else:
				no_aug.text = "No Augment Equipped"
			no_aug.add_theme_font_size_override("font_size", 10)
			no_aug.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
			vbox.add_child(no_aug)
			if ldr_sigil_id2 != "":
				var equip_aug_btn := Button.new()
				equip_aug_btn.text = "Equip Augment"
				equip_aug_btn.add_theme_font_size_override("font_size", 10)
				var c_lid_aug2: int = int(leader.id)
				equip_aug_btn.pressed.connect(func() -> void:
					win.queue_free()
					_open_leader_augment_picker(c_lid_aug2)
				)
				vbox.add_child(equip_aug_btn)

	return win


func _open_leader_item_picker(leader_id: int) -> void:
	if _game_state == null or _current_province_id < 0:
		return
	var province = _game_state.map_data.provinces[_current_province_id]
	if province == null:
		return
	var inventory: Array = province.item_inventory if "item_inventory" in province else []

	var popup := PanelContainer.new()
	popup.custom_minimum_size = Vector2(240, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.18, 0.98)
	style.border_color = Color(1.0, 0.85, 0.4, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	popup.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	popup.add_child(vbox)

	var hdr := Label.new()
	hdr.text = "Choose Item for Leader"
	hdr.add_theme_font_size_override("font_size", 11)
	hdr.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vbox.add_child(hdr)
	vbox.add_child(_sheet_divider())

	var found_any := false
	for entry in inventory:
		var item_id: String = str(entry.get("item_id", ""))
		var qty: int = int(entry.get("quantity", 0))
		if item_id == "" or qty <= 0:
			continue
		found_any = true
		var tpl: Dictionary = ItemLibrary.get_item(item_id)
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "%s (x%d)" % [str(tpl.get("name", item_id)), qty]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 10)
		row.add_child(lbl)
		var pick_btn := Button.new()
		pick_btn.text = "Equip"
		pick_btn.add_theme_font_size_override("font_size", 10)
		var c_iid: String = item_id
		var c_lid: int = leader_id
		pick_btn.pressed.connect(func() -> void:
			var ldr = _game_state.get_leader(c_lid)
			if ldr != null:
				ldr.equipped_item_id = c_iid
				# Remove one from province inventory
				var _prov = _game_state.map_data.provinces[_current_province_id]; if _prov != null: _prov.remove_item(c_iid, 1)
			popup.queue_free()
			refresh(_current_province_id)
		)
		row.add_child(pick_btn)
		vbox.add_child(row)

	if not found_any:
		var empty := Label.new()
		empty.text = "No items in province inventory."
		empty.add_theme_font_size_override("font_size", 10)
		empty.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		vbox.add_child(empty)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.add_theme_font_size_override("font_size", 10)
	cancel_btn.pressed.connect(func() -> void: popup.queue_free())
	vbox.add_child(cancel_btn)

	get_parent().add_child(popup)
	popup.position = Vector2(320, 120)


func _open_sigil_picker_for_unit(unit_id: int) -> void:
	if _game_state == null or _current_province_id < 0:
		return
	var province = _game_state.map_data.provinces[_current_province_id]
	if province == null:
		return
	var sigil_inv: Array = province.sigil_inventory if province.has_method("add_sigil") else []

	var popup := PanelContainer.new()
	popup.name = "SigilPicker"
	popup.custom_minimum_size = Vector2(260, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.18, 0.98)
	style.border_color = Color(0.7, 0.55, 1.0, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	popup.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	popup.add_child(vbox)

	var hdr_row := HBoxContainer.new()
	var hdr := Label.new()
	hdr.text = "Equip Sigil to Unit"
	hdr.add_theme_font_size_override("font_size", 11)
	hdr.add_theme_color_override("font_color", Color(0.7, 0.55, 1.0))
	hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var x_btn := Button.new()
	x_btn.text = "X"
	x_btn.pressed.connect(func() -> void: popup.queue_free())
	hdr_row.add_child(hdr)
	hdr_row.add_child(x_btn)
	vbox.add_child(hdr_row)
	vbox.add_child(_sheet_divider())

	var found_any := false
	# Deduplicate
	var seen: Dictionary = {}
	var unit_for_tags = _game_state.get_unit(unit_id)
	var unit_tier: int = int(unit_for_tags.tier) if unit_for_tags != null else 1
	var allowed_tags: Array = _get_unit_allowed_tags(unit_for_tags) if unit_for_tags != null else ["melee"]
	for sid in sigil_inv:
		var sigil_id: String = str(sid)
		if sigil_id == "" or seen.has(sigil_id):
			continue
		seen[sigil_id] = true
		var stpl: Dictionary = SigilLibrary.get_sigil(sigil_id)
		if stpl.is_empty():
			continue
		var sigil_tier: int = int(stpl.get("tier", 1))
		var sigil_tags: Array = stpl.get("tags", [])
		var tier_ok: bool = sigil_tier <= unit_tier
		var tag_ok: bool = false
		for t in sigil_tags:
			if allowed_tags.has(t):
				tag_ok = true
				break
		var row := HBoxContainer.new()
		var lbl := Label.new()
		var reason: String = ""
		if not tier_ok:
			reason = " [Requires T%d unit]" % sigil_tier
		elif not tag_ok:
			reason = " [Wrong type]"
		lbl.text = "%s (T%d SP:%d)%s" % [str(stpl.get("name", sigil_id)), sigil_tier, int(stpl.get("sp_cost", 0)), reason]
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not tier_ok or not tag_ok:
			lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
		row.add_child(lbl)
		var pick_btn := Button.new()
		pick_btn.text = "Equip"
		pick_btn.add_theme_font_size_override("font_size", 10)
		pick_btn.disabled = not tier_ok or not tag_ok
		found_any = true
		var c_sid: String = sigil_id
		var c_uid: int = unit_id
		pick_btn.pressed.connect(func() -> void:
			var u = _game_state.get_unit(c_uid)
			if u != null:
				if str(u.equipped_sigil_id) != "" and _current_province_id >= 0:
					var _prov2 = _game_state.map_data.provinces[_current_province_id]
					if _prov2 != null and _prov2.has_method("add_sigil"):
						_prov2.add_sigil(str(u.equipped_sigil_id))
				u.equipped_sigil_id = c_sid
				var _prov = _game_state.map_data.provinces[_current_province_id]
				if _prov != null and _prov.has_method("remove_sigil"):
					_prov.remove_sigil(c_sid)
			popup.queue_free()
			refresh(_current_province_id)
		)
		row.add_child(pick_btn)
		vbox.add_child(row)

	if not found_any:
		var empty := Label.new()
		empty.text = "No sigils in province inventory."
		empty.add_theme_font_size_override("font_size", 10)
		empty.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		vbox.add_child(empty)

	get_parent().add_child(popup)
	popup.position = Vector2(360, 120)


func _open_leader_sigil_picker(leader_id: int) -> void:
	if _game_state == null or _current_province_id < 0:
		return
	var province = _game_state.map_data.provinces[_current_province_id]
	if province == null:
		return
	var sigil_inv: Array = province.sigil_inventory if province.has_method("add_sigil") else []

	var popup := PanelContainer.new()
	popup.name = "LeaderSigilPicker"
	popup.custom_minimum_size = Vector2(260, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.18, 0.98)
	style.border_color = Color(0.7, 0.55, 1.0, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	popup.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	popup.add_child(vbox)

	var hdr_row := HBoxContainer.new()
	var hdr := Label.new()
	hdr.text = "Equip Sigil to Leader"
	hdr.add_theme_font_size_override("font_size", 11)
	hdr.add_theme_color_override("font_color", Color(0.7, 0.55, 1.0))
	hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var x_btn := Button.new()
	x_btn.text = "X"
	x_btn.pressed.connect(func() -> void: popup.queue_free())
	hdr_row.add_child(hdr)
	hdr_row.add_child(x_btn)
	vbox.add_child(hdr_row)
	vbox.add_child(_sheet_divider())

	var found_any := false
	var seen: Dictionary = {}
	var ldr_for_tags = _game_state.get_leader(leader_id)
	var ldr_level: int = int(ldr_for_tags.level) if ldr_for_tags != null else 1
	# Leader tier bracket: 1-4=T1, 5-9=T2, 10-14=T3, 15+=T4
	var ldr_tier: int = 1
	if ldr_level >= 15: ldr_tier = 4
	elif ldr_level >= 10: ldr_tier = 3
	elif ldr_level >= 5: ldr_tier = 2
	var ldr_allowed_tags: Array = _get_leader_allowed_tags()
	for sid in sigil_inv:
		var sigil_id: String = str(sid)
		if sigil_id == "" or seen.has(sigil_id):
			continue
		seen[sigil_id] = true
		var stpl: Dictionary = SigilLibrary.get_sigil(sigil_id)
		if stpl.is_empty():
			continue
		var sigil_tier: int = int(stpl.get("tier", 1))
		var sigil_tags: Array = stpl.get("tags", [])
		var tier_ok: bool = sigil_tier <= ldr_tier
		var tag_ok: bool = false
		for t in sigil_tags:
			if ldr_allowed_tags.has(t):
				tag_ok = true
				break
		var row := HBoxContainer.new()
		var lbl := Label.new()
		var reason: String = ""
		if not tier_ok:
			reason = " [Requires Lv%d+]" % ([5, 10, 15][sigil_tier - 2] if sigil_tier >= 2 else 1)
		elif not tag_ok:
			reason = " [Wrong type]"
		lbl.text = "%s (T%d SP:%d)%s" % [str(stpl.get("name", sigil_id)), sigil_tier, int(stpl.get("sp_cost", 0)), reason]
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not tier_ok or not tag_ok:
			lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
		row.add_child(lbl)
		var pick_btn := Button.new()
		pick_btn.text = "Equip"
		pick_btn.add_theme_font_size_override("font_size", 10)
		pick_btn.disabled = not tier_ok or not tag_ok
		found_any = true
		var c_sid: String = sigil_id
		var c_lid: int = leader_id
		pick_btn.pressed.connect(func() -> void:
			var ldr = _game_state.get_leader(c_lid)
			if ldr != null:
				if str(ldr.equipped_sigil_id) != "" and _current_province_id >= 0:
					var _prov2 = _game_state.map_data.provinces[_current_province_id]
					if _prov2 != null and _prov2.has_method("add_sigil"):
						_prov2.add_sigil(str(ldr.equipped_sigil_id))
				ldr.equipped_sigil_id = c_sid
				var _prov = _game_state.map_data.provinces[_current_province_id]
				if _prov != null and _prov.has_method("remove_sigil"):
					_prov.remove_sigil(c_sid)
			popup.queue_free()
			refresh(_current_province_id)
		)
		row.add_child(pick_btn)
		vbox.add_child(row)

	if not found_any:
		var empty := Label.new()
		empty.text = "No sigils in province inventory."
		empty.add_theme_font_size_override("font_size", 10)
		empty.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		vbox.add_child(empty)

	get_parent().add_child(popup)
	popup.position = Vector2(360, 120)


func _open_augment_picker_for_unit(unit_id: int) -> void:
	if _game_state == null or _current_province_id < 0:
		return
	var unit = _game_state.get_unit(unit_id)
	if unit == null:
		return
	var sigil_id: String = str(unit.equipped_sigil_id)
	if sigil_id == "":
		return
	var sigil_data: Dictionary = SigilLibrary.get_sigil(sigil_id)
	var sigil_tags: Array = sigil_data.get("tags", [])

	var popup := PanelContainer.new()
	popup.name = "AugmentPicker"
	popup.custom_minimum_size = Vector2(260, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.16, 0.98)
	style.border_color = Color(1.0, 0.75, 0.3, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	popup.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	popup.add_child(vbox)

	var hdr_row := HBoxContainer.new()
	var hdr := Label.new()
	hdr.text = "Equip Augment to Unit"
	hdr.add_theme_font_size_override("font_size", 11)
	hdr.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var x_btn := Button.new()
	x_btn.text = "X"
	x_btn.pressed.connect(func() -> void: popup.queue_free())
	hdr_row.add_child(hdr)
	hdr_row.add_child(x_btn)
	vbox.add_child(hdr_row)
	vbox.add_child(_sheet_divider())

	var found_any := false
	for aug_data in AugmentLibrary.AUGMENTS:
		var aug_id: String = str(aug_data.get("id", ""))
		if not AugmentLibrary.can_equip(aug_id, sigil_tags):
			continue
		found_any = true
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "%s — %s" % [str(aug_data.get("name", aug_id)), str(aug_data.get("description", ""))]
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		row.add_child(lbl)
		var pick_btn := Button.new()
		pick_btn.text = "Equip"
		pick_btn.add_theme_font_size_override("font_size", 10)
		var c_aug_id: String = aug_id
		var c_uid: int = unit_id
		pick_btn.pressed.connect(func() -> void:
			var u = _game_state.get_unit(c_uid)
			if u != null:
				u.equipped_augment_id = c_aug_id
			popup.queue_free()
			refresh(_current_province_id)
		)
		row.add_child(pick_btn)
		vbox.add_child(row)

	if not found_any:
		var empty := Label.new()
		empty.text = "No compatible augments for this sigil."
		empty.add_theme_font_size_override("font_size", 10)
		empty.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		vbox.add_child(empty)

	get_parent().add_child(popup)
	popup.position = Vector2(360, 160)


func _open_leader_augment_picker(leader_id: int) -> void:
	if _game_state == null or _current_province_id < 0:
		return
	var leader = _game_state.get_leader(leader_id)
	if leader == null:
		return
	var sigil_id: String = str(leader.equipped_sigil_id)
	if sigil_id == "":
		return
	var sigil_data: Dictionary = SigilLibrary.get_sigil(sigil_id)
	var sigil_tags: Array = sigil_data.get("tags", [])

	var popup := PanelContainer.new()
	popup.name = "LeaderAugmentPicker"
	popup.custom_minimum_size = Vector2(260, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.16, 0.98)
	style.border_color = Color(1.0, 0.75, 0.3, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	popup.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	popup.add_child(vbox)

	var hdr_row := HBoxContainer.new()
	var hdr := Label.new()
	hdr.text = "Equip Augment to Leader"
	hdr.add_theme_font_size_override("font_size", 11)
	hdr.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var x_btn := Button.new()
	x_btn.text = "X"
	x_btn.pressed.connect(func() -> void: popup.queue_free())
	hdr_row.add_child(hdr)
	hdr_row.add_child(x_btn)
	vbox.add_child(hdr_row)
	vbox.add_child(_sheet_divider())

	var found_any := false
	for aug_data in AugmentLibrary.AUGMENTS:
		var aug_id: String = str(aug_data.get("id", ""))
		if not AugmentLibrary.can_equip(aug_id, sigil_tags):
			continue
		found_any = true
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = "%s — %s" % [str(aug_data.get("name", aug_id)), str(aug_data.get("description", ""))]
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		row.add_child(lbl)
		var pick_btn := Button.new()
		pick_btn.text = "Equip"
		pick_btn.add_theme_font_size_override("font_size", 10)
		var c_aug_id: String = aug_id
		var c_lid: int = leader_id
		pick_btn.pressed.connect(func() -> void:
			var ldr = _game_state.get_leader(c_lid)
			if ldr != null:
				ldr.equipped_augment_id = c_aug_id
			popup.queue_free()
			refresh(_current_province_id)
		)
		row.add_child(pick_btn)
		vbox.add_child(row)

	if not found_any:
		var empty := Label.new()
		empty.text = "No compatible augments for this sigil."
		empty.add_theme_font_size_override("font_size", 10)
		empty.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		vbox.add_child(empty)

	get_parent().add_child(popup)
	popup.position = Vector2(360, 160)


func _open_signature_ability_popup(sig_data: Dictionary) -> void:
	var existing = get_parent().find_child("SigAbilityPopup", true, false)
	if existing != null:
		existing.queue_free()

	var popup := PanelContainer.new()
	popup.name = "SigAbilityPopup"
	popup.custom_minimum_size = Vector2(280, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.10, 0.16, 0.98)
	style.border_color = Color(1.0, 0.85, 0.3, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	popup.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	popup.add_child(vbox)

	# Header row
	var hdr_row := HBoxContainer.new()
	var title := Label.new()
	title.text = "SIGNATURE ABILITY  ✦"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var x_btn := Button.new()
	x_btn.text = "X"
	x_btn.add_theme_font_size_override("font_size", 10)
	x_btn.pressed.connect(func() -> void: popup.queue_free())
	hdr_row.add_child(title)
	hdr_row.add_child(x_btn)
	vbox.add_child(hdr_row)
	vbox.add_child(_sheet_divider())

	# Name
	var name_lbl := Label.new()
	name_lbl.text = str(sig_data.get("name", "Unknown"))
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	vbox.add_child(name_lbl)

	# Stats row
	var tags: Array = sig_data.get("tags", [])
	var stats_lbl := Label.new()
	stats_lbl.text = "SP Cost:  %d\nAction:   %s\nTags:     %s\nTarget:   %s\nRange:    %s" % [
		int(sig_data.get("sp_cost", 0)),
		str(sig_data.get("action_type", "standard")).capitalize(),
		", ".join(tags) if not tags.is_empty() else "—",
		str(sig_data.get("target_type", "enemy")).capitalize(),
		str(sig_data.get("range", 1)) if int(sig_data.get("range", 1)) >= 0 else "Unit range"
	]
	stats_lbl.add_theme_font_size_override("font_size", 10)
	stats_lbl.add_theme_color_override("font_color", Color(0.85, 0.90, 0.85))
	vbox.add_child(stats_lbl)
	vbox.add_child(_sheet_divider())

	# Description
	var desc_lbl := Label.new()
	desc_lbl.text = str(sig_data.get("description", ""))
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.add_theme_color_override("font_color", Color(0.80, 0.85, 1.0))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc_lbl)

	vbox.add_child(_sheet_divider())
	var locked_lbl := Label.new()
	locked_lbl.text = "Innate ability — cannot be removed or replaced."
	locked_lbl.add_theme_font_size_override("font_size", 9)
	locked_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	vbox.add_child(locked_lbl)

	get_parent().add_child(popup)
	popup.position = Vector2(320, 80)


func _get_unit_allowed_tags(unit) -> Array:
	# Infer allowed sigil tags from unit type name
	var utype: String = str(unit.unit_type).to_lower()
	var tags: Array = []
	# Ranged units
	if "archer" in utype or "crossbow" in utype or "ranger" in utype or "hunter" in utype \
	or "sniper" in utype or "arbalest" in utype or "harpoon" in utype or "reed" in utype \
	or "shot" in utype or "volley" in utype or "blizzard" in utype:
		tags.append("ranged")
	# Melee units (most infantry)
	if "guard" in utype or "warrior" in utype or "infantry" in utype or "swordsman" in utype \
	or "spearman" in utype or "pikeman" in utype or "fighter" in utype or "raider" in utype \
	or "knight" in utype or "cavalry" in utype or "rider" in utype or "champion" in utype \
	or "sentinel" in utype or "phalanx" in utype or "hammer" in utype or "titan" in utype \
	or "marine" in utype or "boarding" in utype or "ambusher" in utype or "stalker" in utype \
	or "captain" in utype or "commander" in utype or "warlord" in utype or "chief" in utype:
		tags.append("melee")
	# Support/heal — commanders and support roles
	if "commander" in utype or "captain" in utype or "warlord" in utype or "chief" in utype \
	or "marshal" in utype or "master" in utype:
		tags.append("support")
	# Fallback — give melee if nothing matched
	if tags.is_empty():
		tags.append("melee")
	return tags


func _get_leader_allowed_tags() -> Array:
	# Leaders always get melee, support, and heal per spec
	return ["melee", "support", "heal"]
