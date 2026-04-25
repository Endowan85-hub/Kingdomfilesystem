# ==================================================
# ProvincePanel
# ==================================================
# Right-side panel opened when the player clicks a province.
# Embeds the existing LeaderPanel (army/items/store/sigils tabs)
# and RecruitPanel from Scripts/ui — gives full debug-parity
# functionality without duplicating code.
#
# Also acts as the RecruitPanel's view proxy (implements
# ui_get_gold_text / ui_recruit_unit so RecruitPanel works
# without needing MapDebugView).
#
# Reads GameState; queues orders via OrderBook only.
# ==================================================
extends CanvasLayer
class_name ProvincePanel

signal closed
signal leader_selection_changed

var game_state: GameState = null
var human_faction_id: int = 0
var _province_id: int = -1

var _panel: PanelContainer
var _header_vbox: VBoxContainer
var _leader_panel: LeaderPanel = null
var _recruit_panel: RecruitPanel = null
var _selected_leader_ids: Array[int] = []


func _ready() -> void:
	layer = 15
	_build_shell()
	hide()


func _build_shell() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_left   = 1.0
	_panel.anchor_right  = 1.0
	_panel.anchor_top    = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left   = -520
	_panel.offset_right  = 0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.10, 0.97)
	style.border_color = Color(0.35, 0.30, 0.18)
	style.set_border_width_all(1)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 0)
	root_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(root_vbox)

	# Close row
	var close_row := HBoxContainer.new()
	close_row.add_theme_constant_override("separation", 8)
	root_vbox.add_child(close_row)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.add_theme_font_size_override("font_size", 14)
	close_btn.custom_minimum_size = Vector2(36, 36)
	close_btn.pressed.connect(_on_close)
	close_row.add_child(close_btn)

	var row_spacer := Control.new()
	row_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_row.add_child(row_spacer)

	# Province info header (rebuilt per open())
	_header_vbox = VBoxContainer.new()
	_header_vbox.add_theme_constant_override("separation", 4)
	root_vbox.add_child(_header_vbox)

	# LeaderPanel — full army/items/store/sigils tabs
	_leader_panel = LeaderPanel.new()
	_leader_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_leader_panel.toggle_callback = func(lid: int) -> void: _toggle_leader(lid)
	_leader_panel.selected_ids_callback = func() -> Array: return _selected_leader_ids.duplicate()
	_leader_panel.order_text_callback = func(lid: int) -> String: return _get_order_text(lid)
	_leader_panel.dismiss_callback = func(lid: int) -> void: _dismiss_leader(lid)
	_leader_panel.heal_unit_callback = func(uid: int, pid: int) -> bool: return _heal_unit(uid, pid)
	_leader_panel.heal_cost_callback = func(uid: int) -> int: return _heal_cost(uid)
	root_vbox.add_child(_leader_panel)

	# RecruitPanel — shown only for own provinces; self acts as view proxy
	_recruit_panel = RecruitPanel.new()
	_recruit_panel.set_view(self)
	_recruit_panel.custom_minimum_size = Vector2(0, 130)
	_recruit_panel.visible = false
	root_vbox.add_child(_recruit_panel)


# --------------------------------------------------
# Public API
# --------------------------------------------------
func open(province_id: int) -> void:
	_province_id = province_id
	_selected_leader_ids.clear()
	_rebuild_header()

	if _leader_panel != null:
		_leader_panel.set_game_state(game_state)
		_leader_panel.human_faction_id = human_faction_id
		_leader_panel.refresh(province_id)

	var is_own: bool = _is_own_province(province_id)
	if _recruit_panel != null:
		_recruit_panel.visible = is_own
		if is_own:
			var p: ProvinceData = game_state.map_data.provinces[province_id] as ProvinceData
			var biome: String = str(p.biome) if p != null else ""
			_recruit_panel.refresh(biome, _get_max_leader_level(province_id))

	show()


func get_selected_leader_ids() -> Array[int]:
	return _selected_leader_ids.duplicate()


# --------------------------------------------------
# RecruitPanel view proxy methods
# --------------------------------------------------
func ui_get_gold_text() -> String:
	if game_state == null:
		return "Gold: --"
	for item in game_state.map_data.factions:
		var f: FactionData = item as FactionData
		if f != null and int(f.id) == human_faction_id:
			return "Gold: %d" % int(f.gold)
	return "Gold: --"


func ui_recruit_unit(unit_type: String) -> void:
	if _province_id < 0 or game_state == null:
		return
	var p: ProvinceData = game_state.map_data.provinces[_province_id] as ProvinceData
	if p == null or int(p.owner_id) != human_faction_id:
		return
	var ok: bool = game_state.recruit_unit(human_faction_id, _province_id, unit_type)
	if ok and _leader_panel != null:
		_leader_panel.refresh(_province_id)
	if _recruit_panel != null:
		_recruit_panel.refresh_gold()


# --------------------------------------------------
# LeaderPanel callbacks
# --------------------------------------------------
func _toggle_leader(leader_id: int) -> void:
	if _selected_leader_ids.has(leader_id):
		_selected_leader_ids.erase(leader_id)
	else:
		if _selected_leader_ids.size() < 3:
			_selected_leader_ids.append(leader_id)
	if _leader_panel != null:
		_leader_panel.refresh_highlights()
	leader_selection_changed.emit()


func _get_order_text(leader_id: int) -> String:
	if game_state == null or game_state.order_book == null:
		return ""
	var ob = game_state.order_book
	for atk in ob.get_attacks(human_faction_id):
		var lids: Array = atk.get("leader_ids") if atk.get("leader_ids") != null else []
		if leader_id in lids:
			return "ATK→P%d" % int(atk.get("to") if atk.get("to") != null else -1)
	for xfer in ob.get_transfers(human_faction_id):
		var lids: Array = xfer.get("leader_ids") if xfer.get("leader_ids") != null else []
		if leader_id in lids:
			return "→P%d" % int(xfer.get("to") if xfer.get("to") != null else -1)
	for mis in ob.get_missions(human_faction_id):
		if int(mis.get("leader_id") if mis.get("leader_id") != null else -1) == leader_id:
			return "Mission"
	return ""


func _dismiss_leader(leader_id: int) -> void:
	if game_state == null:
		return
	var ok: bool = game_state.dismiss_general(leader_id)
	if ok:
		_selected_leader_ids.erase(leader_id)
		if _leader_panel != null:
			_leader_panel.refresh(_province_id)


func _heal_unit(unit_id: int, province_id: int) -> bool:
	if game_state == null:
		return false
	var cost: int = game_state.get_unit_active_heal_cost(unit_id)
	if cost < 0:
		return false
	var ok: bool = game_state.active_heal_unit(human_faction_id, unit_id, province_id)
	if ok and _leader_panel != null:
		_leader_panel.refresh(_province_id)
	return ok


func _heal_cost(unit_id: int) -> int:
	if game_state == null:
		return -1
	return game_state.get_unit_active_heal_cost(unit_id)


# --------------------------------------------------
# Header rebuild
# --------------------------------------------------
func _rebuild_header() -> void:
	for child in _header_vbox.get_children():
		child.queue_free()

	if game_state == null or _province_id < 0:
		return
	var p: ProvinceData = game_state.map_data.provinces[_province_id] as ProvinceData
	if p == null:
		return

	var name_lbl := Label.new()
	name_lbl.text = str(p.display_name)
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	_header_vbox.add_child(name_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = "%s  ·  %s" % [str(p.biome).capitalize(), _owner_name(int(p.owner_id))]
	sub_lbl.add_theme_font_size_override("font_size", 11)
	sub_lbl.add_theme_color_override("font_color", Color(0.60, 0.68, 0.60))
	_header_vbox.add_child(sub_lbl)

	var stats_lbl := Label.new()
	stats_lbl.text = "Fort %d  ·  Income %d  ·  Defense %d" % [
		int(p.fort_level), int(p.income), int(p.defense_value)
	]
	stats_lbl.add_theme_font_size_override("font_size", 11)
	stats_lbl.add_theme_color_override("font_color", Color(0.65, 0.72, 0.80))
	_header_vbox.add_child(stats_lbl)

	var div := ColorRect.new()
	div.color = Color(0.22, 0.20, 0.16)
	div.custom_minimum_size = Vector2(0, 1)
	_header_vbox.add_child(div)


# --------------------------------------------------
# Helpers
# --------------------------------------------------
func _is_own_province(province_id: int) -> bool:
	if game_state == null or province_id < 0:
		return false
	var p: ProvinceData = game_state.map_data.provinces[province_id] as ProvinceData
	return p != null and int(p.owner_id) == human_faction_id


func _get_max_leader_level(province_id: int) -> int:
	if game_state == null:
		return 1
	var leaders: Array = game_state.get_province_leaders(province_id, false)
	var max_lvl: int = 1
	for item in leaders:
		var l: LeaderData = item as LeaderData
		if l != null:
			var lvl: int = int(l.get("level") if l.get("level") != null else 1)
			max_lvl = max(max_lvl, lvl)
	return max_lvl


func _owner_name(owner_id: int) -> String:
	if owner_id < 0:
		return "Neutral"
	if game_state == null:
		return "Unknown"
	for item in game_state.map_data.factions:
		var f: FactionData = item as FactionData
		if f != null and int(f.id) == owner_id:
			return f.display_name
	return "Unknown"


func _on_close() -> void:
	hide()
	closed.emit()
