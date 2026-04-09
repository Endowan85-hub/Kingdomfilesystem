# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: MissionPanel
#
# Role:
# Floating planning-phase panel showing active missions in the selected
# province. Player selects a mission then assigns a leader to it.
# Displays results from the last resolved turn.
#
# Allowed Interactions:
# - GameState (read-only)
# - OrderBook (queue_mission only)
# - MissionLibrary (read-only display data)
# - MissionData (read-only display)
#
# Forbidden Responsibilities:
# - Must not execute simulation logic
# - Must not modify LeaderData directly
# - Must not interact with resolvers
#
# Game Phase:
# Planning Phase
# ==================================================
extends Control
class_name MissionPanel

const MissionLibraryScript = preload("res://Scripts/data/mission_library.gd")

const MIN_WIDTH: int = 300
const MIN_HEIGHT: int = 140

const COL_TITLE      := Color(0.95, 0.85, 0.45)
const COL_LEADER     := Color(1.0, 0.90, 0.50)
const COL_QUEUED     := Color(0.55, 0.90, 0.55)
const COL_INJURED    := Color(1.0, 0.40, 0.40)
const COL_ON_MISSION := Color(0.55, 0.75, 1.0)
const COL_IDLE       := Color(0.60, 0.60, 0.65)
const COL_RESULT_HDR := Color(0.75, 0.85, 1.0)
const COL_RESULT_TXT := Color(0.80, 0.80, 0.85)
const COL_MISSION    := Color(0.75, 0.95, 0.80)
const COL_HUNT       := Color(1.0, 0.70, 0.45)
const COL_ELITE      := Color(0.85, 0.60, 1.0)
const COL_TREASURE   := Color(1.0, 0.88, 0.40)

var _panel: PanelContainer
var _title_label: Label
var _scroll: ScrollContainer
var _content: VBoxContainer

var _game_state = null
var _current_province_id: int = -1
var _human_faction_id: int = 0

# Which mission instance_id is selected for assignment
var _selected_mission_id: String = ""

# Mission results accumulated by MapDebugView after Execute Month
var pending_results: Array = []


func _ready() -> void:
	_build_ui()
	set_process_input(true)


func _build_ui() -> void:
	custom_minimum_size = Vector2(MIN_WIDTH, MIN_HEIGHT)
	size = Vector2(340, 520)

	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.10, 0.12, 0.16, 0.93)
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.35, 0.40, 0.55, 1.0)
	_panel.add_theme_stylebox_override("panel", panel_style)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(vbox)

	# Title bar
	var title_bar := Panel.new()
	title_bar.custom_minimum_size = Vector2(0, 28)
	title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	var title_style := StyleBoxFlat.new()
	title_style.bg_color = Color(0.15, 0.17, 0.24, 1.0)
	title_bar.add_theme_stylebox_override("panel", title_style)
	vbox.add_child(title_bar)

	_title_label = Label.new()
	_title_label.text = "Missions"
	_title_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.add_theme_color_override("font_color", COL_TITLE)
	title_bar.add_child(_title_label)

	title_bar.gui_input.connect(func(ev: InputEvent) -> void:
		_handle_title_drag(ev)
	)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(_scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_theme_constant_override("separation", 6)
	_scroll.add_child(_content)


var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO


func _handle_title_drag(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			if mb.pressed:
				_drag_offset = global_position - mb.global_position
			get_viewport().set_input_as_handled()
	elif ev is InputEventMouseMotion and _dragging:
		global_position = (ev as InputEventMouseMotion).global_position + _drag_offset
		_clamp_to_screen()
		get_viewport().set_input_as_handled()


func _clamp_to_screen() -> void:
	var vp: Vector2 = get_viewport_rect().size
	global_position.x = clampf(global_position.x, 0.0, vp.x - size.x)
	global_position.y = clampf(global_position.y, 0.0, vp.y - size.y)


# --------------------------------------------------
# Public API
# --------------------------------------------------

func set_game_state(gs) -> void:
	_game_state = gs


func set_human_faction(fid: int) -> void:
	_human_faction_id = fid


func refresh(province_id: int) -> void:
	_current_province_id = province_id
	_selected_mission_id = ""
	_rebuild()


func push_results(results: Array) -> void:
	for r in results:
		pending_results.append(r)
	_rebuild()


func clear_results() -> void:
	pending_results.clear()
	_rebuild()


# --------------------------------------------------
# Build content
# --------------------------------------------------

func _rebuild() -> void:
	for c in _content.get_children():
		c.queue_free()

	if _game_state == null:
		return

	var province_id: int = _current_province_id
	if province_id < 0:
		_title_label.text = "Missions"
		_content.add_child(_make_label("  Select a province.", 11, COL_IDLE))
		return

	_title_label.text = "Missions — P%d" % province_id

	var map_data = _game_state.map_data
	if map_data == null or province_id >= map_data.provinces.size():
		return

	var province: ProvinceData = map_data.provinces[province_id] as ProvinceData
	if province == null or int(province.owner_id) != _human_faction_id:
		_content.add_child(_make_label("  Not your province.", 11, COL_IDLE))
		_append_results_section()
		return

	# ── Active missions in this province ─────────────
	_content.add_child(_make_label("  AVAILABLE MISSIONS", 11, COL_TITLE))

	var province_missions: Array = _get_province_missions(province_id)

	if province_missions.is_empty():
		_content.add_child(_make_label("  No missions available.", 11, COL_IDLE))
	else:
		for mission in province_missions:
			_content.add_child(_build_mission_card(mission))

	# ── Leaders section ───────────────────────────────
	_content.add_child(HSeparator.new())
	_content.add_child(_make_label("  ASSIGN LEADER", 11, COL_TITLE))

	if _selected_mission_id == "":
		_content.add_child(_make_label("  Select a mission above first.", 11, COL_IDLE))
	else:
		var leaders: Array = _game_state.get_province_leaders(province_id, true)
		var idle_leaders: Array = []
		for ldr in leaders:
			if not bool(ldr.on_mission) and str(ldr.status) not in ["wounded", "injured", "on_mission"]:
				idle_leaders.append(ldr)

		if idle_leaders.is_empty():
			_content.add_child(_make_label("  No idle leaders available.", 11, COL_IDLE))
		else:
			for ldr in idle_leaders:
				_content.add_child(_build_leader_assign_row(ldr))

	# ── On-mission leaders ───────────────────────────
	var on_mission_leaders: Array = []
	var all_leaders: Array = _game_state.get_province_leaders(province_id, true)
	for ldr in all_leaders:
		if bool(ldr.on_mission) or str(ldr.status) in ["wounded", "injured", "on_mission"]:
			on_mission_leaders.append(ldr)

	if not on_mission_leaders.is_empty():
		_content.add_child(HSeparator.new())
		_content.add_child(_make_label("  LEADER STATUS", 11, COL_TITLE))
		for ldr in on_mission_leaders:
			_content.add_child(_build_leader_status_row(ldr))

	_append_results_section()


func _get_province_missions(province_id: int) -> Array:
	if _game_state == null or not "active_missions" in _game_state:
		return []
	var out: Array = []
	for instance_id in _game_state.active_missions.keys():
		var mission = _game_state.active_missions[instance_id]
		if mission == null:
			continue
		if int(mission.province_id) == province_id and str(mission.phase) == "available":
			out.append(mission)
	return out


func _build_mission_card(mission) -> Control:
	var is_selected: bool = str(mission.instance_id) == _selected_mission_id
	var queued_for: int = _get_queued_leader_for_mission(str(mission.instance_id))

	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.18, 0.22, 0.30, 1.0) if is_selected else Color(0.14, 0.16, 0.22, 1.0)
	card_style.border_color = _type_color(str(mission.mission_type)) if is_selected else Color(0.3, 0.3, 0.4, 1.0)
	card_style.set_border_width_all(1 if not is_selected else 2)
	card_style.set_corner_radius_all(3)
	card.add_theme_stylebox_override("panel", card_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)

	# Mission name + type tag
	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_lbl := _make_label("  %s" % str(mission.display_name), 11, _type_color(str(mission.mission_type)))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_lbl)
	var type_lbl := _make_label("%s  " % mission.get_type_display(), 9, COL_IDLE)
	name_row.add_child(type_lbl)
	vbox.add_child(name_row)

	# Risk + duration
	var info_row := HBoxContainer.new()
	info_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_row.add_child(_make_label("  Risk: %s" % mission.get_risk_display(), 9, COL_IDLE))
	info_row.add_child(_make_label("  |  Expires in: %d turn(s)" % int(mission.duration_remaining), 9, COL_IDLE))
	vbox.add_child(info_row)

	# Queued indicator
	if queued_for >= 0:
		var q_ldr = _find_leader(queued_for)
		var q_name: String = "Leader" if q_ldr == null else str(q_ldr.display_name)
		vbox.add_child(_make_label("  ✓ Assigned: %s" % q_name, 9, COL_QUEUED))

	# Select button
	var btn := Button.new()
	btn.text = "▶ Select" if not is_selected else "✓ Selected"
	btn.add_theme_font_size_override("font_size", 10)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	if is_selected:
		btn.add_theme_color_override("font_color", COL_QUEUED)
	var captured_id: String = str(mission.instance_id)
	btn.pressed.connect(func() -> void:
		_selected_mission_id = captured_id
		_rebuild()
	)
	vbox.add_child(btn)

	return card


func _build_leader_assign_row(leader) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)

	var already_queued: bool = _get_queued_leader_for_mission(_selected_mission_id) == int(leader.id)

	var name_lbl := _make_label("  %s" % str(leader.display_name if str(leader.display_name) != "" else leader.name), 11, COL_LEADER)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)

	var btn := Button.new()
	btn.text = "✕ Cancel" if already_queued else "Assign"
	btn.add_theme_font_size_override("font_size", 10)
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	if already_queued:
		btn.add_theme_color_override("font_color", COL_INJURED)
	var captured_lid: int = int(leader.id)
	btn.pressed.connect(func() -> void:
		if already_queued:
			_cancel_mission_assignment(_selected_mission_id)
		else:
			_queue_mission_assignment(_selected_mission_id, captured_lid)
	)
	row.add_child(btn)
	return row


func _build_leader_status_row(leader) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var status: String = str(leader.status)
	var status_txt: String = ""
	var status_color: Color = COL_IDLE

	if status == "wounded":
		status_txt = "Wounded (%d turns)" % int(leader.wounded_turns_remaining)
		status_color = COL_INJURED
	elif status == "injured":
		status_txt = "Injured (%d turns)" % int(leader.mission_turns_remaining)
		status_color = COL_INJURED
	elif bool(leader.on_mission) or status == "on_mission":
		var turns: int = int(leader.mission_turns_remaining)
		status_txt = "On Mission — %s" % ("Travelling" if turns > 0 else "Battle Ready")
		status_color = COL_ON_MISSION

	var name_lbl := _make_label("  %s" % str(leader.display_name if str(leader.display_name) != "" else leader.name), 10, COL_LEADER)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)
	row.add_child(_make_label(status_txt + "  ", 9, status_color))
	return row


func _append_results_section() -> void:
	if pending_results.is_empty():
		return

	_content.add_child(HSeparator.new())
	_content.add_child(_make_label("  LAST TURN RESULTS", 11, COL_RESULT_HDR))

	for result in pending_results:
		var r_container := VBoxContainer.new()
		r_container.add_theme_constant_override("separation", 2)
		r_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var leader_name: String = str(result.get("leader", result.get("display_name", "?")))
		var win: bool = bool(result.get("win", false))
		var outcome_txt: String = "[WIN]" if win else "[LOSS]"
		var outcome_color: Color = COL_QUEUED if win else COL_INJURED

		var header_hbox := HBoxContainer.new()
		header_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hdr_lbl := _make_label("  %s — %s" % [leader_name, str(result.get("display_name", ""))], 10, COL_LEADER)
		hdr_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header_hbox.add_child(hdr_lbl)
		header_hbox.add_child(_make_label(outcome_txt + "  ", 10, outcome_color))
		r_container.add_child(header_hbox)

		var detail: String = _format_result_detail(result)
		if detail != "":
			var det_lbl := _make_label("  → " + detail, 9, COL_RESULT_TXT)
			det_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			r_container.add_child(det_lbl)

		r_container.add_child(HSeparator.new())
		_content.add_child(r_container)


func _format_result_detail(result: Dictionary) -> String:
	var parts: Array = []
	if result.has("xp_gain"):
		parts.append("+%d XP" % int(result.get("xp_gain", 0)))
	if result.has("gold_gain"):
		parts.append("+%d gold" % int(result.get("gold_gain", 0)))
	if result.has("item_name"):
		parts.append("Item: %s" % str(result.get("item_name", "")))
	if bool(result.get("gem_found", false)):
		parts.append("Skill Gem found!")
	if result.has("rising_general_name"):
		parts.append("Recruited: %s" % str(result.get("rising_general_name", "")))
	if bool(result.get("wounded", false)):
		parts.append("Leader wounded — %d turns" % int(result.get("wound_turns", 4)))
	return "  |  ".join(parts)


# --------------------------------------------------
# Mission order helpers
# --------------------------------------------------

func _get_queued_leader_for_mission(mission_instance_id: String) -> int:
	if _game_state == null or _game_state.order_book == null:
		return -1
	var orders: Array = _game_state.order_book.get_missions(_human_faction_id)
	for o in orders:
		if str(o.get("mission_instance_id", "")) == mission_instance_id:
			return int(o.get("leader_id", -1))
	return -1


func _queue_mission_assignment(mission_instance_id: String, leader_id: int) -> void:
	if _game_state == null or _game_state.order_book == null:
		return
	# Cancel any existing assignment for this leader
	_cancel_any_mission_for_leader(leader_id)
	_game_state.order_book.queue_mission(
		_human_faction_id,
		_current_province_id,
		leader_id,
		mission_instance_id,
		1
	)
	_rebuild()


func _cancel_mission_assignment(mission_instance_id: String) -> void:
	if _game_state == null or _game_state.order_book == null:
		return
	var ob: OrderBook = _game_state.order_book
	if not ob.missions_by_faction.has(_human_faction_id):
		return
	var arr: Array = ob.missions_by_faction[_human_faction_id]
	for i in range(arr.size() - 1, -1, -1):
		if str(arr[i].get("mission_instance_id", "")) == mission_instance_id:
			arr.remove_at(i)
	ob.missions_by_faction[_human_faction_id] = arr
	_rebuild()


func _cancel_any_mission_for_leader(leader_id: int) -> void:
	if _game_state == null or _game_state.order_book == null:
		return
	var ob: OrderBook = _game_state.order_book
	if not ob.missions_by_faction.has(_human_faction_id):
		return
	var arr: Array = ob.missions_by_faction[_human_faction_id]
	for i in range(arr.size() - 1, -1, -1):
		if int(arr[i].get("leader_id", -1)) == leader_id:
			arr.remove_at(i)
	ob.missions_by_faction[_human_faction_id] = arr


func _find_leader(leader_id: int):
	if _game_state == null:
		return null
	for ldr in _game_state.leaders:
		if int(ldr.id) == leader_id:
			return ldr
	return null


func _type_color(mission_type: String) -> Color:
	if mission_type.begins_with("hunt"):
		return COL_HUNT
	match mission_type:
		"elite":    return COL_ELITE
		"treasure": return COL_TREASURE
	return COL_MISSION


# --------------------------------------------------
# Helpers
# --------------------------------------------------

func _make_label(txt: String, font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = txt
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl
