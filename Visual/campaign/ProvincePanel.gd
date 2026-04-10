# ==================================================
# ProvincePanel
# ==================================================
# Side panel opened when player clicks one of their provinces.
# Shows province info, leaders, army units, and actions.
# Read-only view for enemy/neutral provinces.
#
# Reads from GameState — queues orders via OrderBook only.
# ==================================================
extends CanvasLayer
class_name ProvincePanel

signal closed
signal end_turn_requested

var game_state: GameState = null
var human_faction_id: int = 0
var _province_id: int = -1

var _panel: PanelContainer
var _content_vbox: VBoxContainer


func _ready() -> void:
	layer = 15
	_build_shell()
	hide()


func _build_shell() -> void:
	# Right-side slide-in panel
	_panel = PanelContainer.new()
	_panel.anchor_left   = 1.0
	_panel.anchor_right  = 1.0
	_panel.anchor_top    = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left   = -380
	_panel.offset_right  = 0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.10, 0.96)
	style.border_color = Color(0.35, 0.30, 0.18)
	style.set_border_width_all(1)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 0)
	_panel.add_child(root_vbox)

	# Close button header
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root_vbox.add_child(header)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.add_theme_font_size_override("font_size", 14)
	close_btn.custom_minimum_size = Vector2(36, 36)
	close_btn.pressed.connect(_on_close)
	header.add_child(close_btn)

	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_spacer)

	# Scrollable content
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(scroll)

	_content_vbox = VBoxContainer.new()
	_content_vbox.add_theme_constant_override("separation", 10)
	_content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content_vbox)


func open(province_id: int) -> void:
	_province_id = province_id
	_rebuild_content()
	show()


func _rebuild_content() -> void:
	for child in _content_vbox.get_children():
		child.queue_free()

	if game_state == null or _province_id < 0:
		return

	var p: ProvinceData = game_state.map_data.provinces[_province_id] as ProvinceData
	if p == null:
		return

	var is_own: bool = int(p.owner_id) == human_faction_id
	var is_neutral: bool = int(p.owner_id) < 0

	# --- Province Header ---
	_section_title(p.display_name, Color(0.95, 0.85, 0.45))

	var biome_owner := "%s  ·  %s" % [str(p.biome).capitalize(), _owner_name(int(p.owner_id))]
	_info_label(biome_owner, Color(0.60, 0.68, 0.60))

	# Stats row
	var stats := "Fort %d  ·  Income %d  ·  Defense %d" % [
		int(p.fort_level), int(p.income), int(p.defense_value)
	]
	_info_label(stats, Color(0.65, 0.72, 0.80))

	_divider()

	if is_own:
		_build_own_province(p)
	elif is_neutral:
		_info_label("Neutral territory — no garrison.", Color(0.50, 0.48, 0.42))
	else:
		_build_enemy_province(p)


func _build_own_province(p: ProvinceData) -> void:
	# Leaders
	var leaders: Array = game_state.get_province_leaders(int(p.id), true)
	if leaders.is_empty():
		_info_label("No leaders stationed here.", Color(0.45, 0.43, 0.40))
	else:
		_section_label("LEADERS")
		for item in leaders:
			var leader: LeaderData = item as LeaderData
			if leader == null:
				continue
			_build_leader_card(leader)

	_divider()

	# Items
	_section_label("ITEMS")
	if (p.item_inventory as Array).is_empty():
		_info_label("No items.", Color(0.40, 0.38, 0.35))
	else:
		_info_label("%d item(s) in inventory." % (p.item_inventory as Array).size(), Color(0.70, 0.68, 0.55))

	_divider()

	# Sigils
	_section_label("SIGILS")
	if (p.sigil_inventory as Array).is_empty():
		_info_label("No sigils.", Color(0.40, 0.38, 0.35))
	else:
		_info_label("%d sigil(s) in inventory." % (p.sigil_inventory as Array).size(), Color(0.70, 0.55, 0.75))

	_divider()
	_info_label("Full province management panel — Phase 3", Color(0.30, 0.28, 0.25))


func _build_enemy_province(p: ProvinceData) -> void:
	_section_label("INTELLIGENCE")
	_info_label("Owner: %s" % _owner_name(int(p.owner_id)), Color(0.75, 0.55, 0.45))
	_info_label("Fort Level: %d" % int(p.fort_level), Color(0.65, 0.72, 0.80))

	# Leader count — fog of war, no stats
	var leaders: Array = game_state.get_province_leaders(int(p.id), false)
	if leaders.is_empty():
		_info_label("No leaders detected.", Color(0.50, 0.48, 0.42))
	else:
		_info_label("Leaders present: %d" % leaders.size(), Color(0.75, 0.55, 0.45))
		_info_label("(Unit details hidden — fog of war)", Color(0.35, 0.33, 0.30))


func _build_leader_card(leader: LeaderData) -> void:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.08, 0.14)
	style.border_color = Color(0.28, 0.26, 0.38)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	card.add_theme_stylebox_override("panel", style)
	_content_vbox.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	# Leader name + status
	var status_color: Color
	match str(leader.status):
		"wounded": status_color = Color(0.85, 0.30, 0.25)
		"on_mission": status_color = Color(0.45, 0.65, 0.85)
		_: status_color = Color(0.45, 0.80, 0.45)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	vbox.add_child(name_row)

	var name_lbl := Label.new()
	name_lbl.text = str(leader.display_name)
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(0.92, 0.82, 0.42))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_lbl)

	var status_lbl := Label.new()
	status_lbl.text = str(leader.status).capitalize()
	status_lbl.add_theme_font_size_override("font_size", 10)
	status_lbl.add_theme_color_override("font_color", status_color)
	name_row.add_child(status_lbl)

	# HP / CP bar row
	var hp_max: int = max(1, int(leader.get("hp_max", 100)))
	var hp_cur: int = int(leader.get("hp", hp_max))
	_bar_row(vbox, "HP", hp_cur, hp_max, Color(0.75, 0.25, 0.20), Color(0.20, 0.65, 0.30))

	# Stats
	var stats_lbl := Label.new()
	stats_lbl.text = "Ldr:%d  Atk:%d  Def:%d  Mag:%d  Lvl:%d" % [
		int(leader.get("leadership", 5)),
		int(leader.get("attack", 5)),
		int(leader.get("defense", 5)),
		int(leader.get("magic", 5)),
		int(leader.get("level", 1))
	]
	stats_lbl.add_theme_font_size_override("font_size", 10)
	stats_lbl.add_theme_color_override("font_color", Color(0.60, 0.60, 0.70))
	vbox.add_child(stats_lbl)

	# Units under this leader
	var unit_ids: Array = leader.get("unit_ids", []) as Array
	if not unit_ids.is_empty():
		var unit_count_lbl := Label.new()
		unit_count_lbl.text = "Units: %d" % unit_ids.size()
		unit_count_lbl.add_theme_font_size_override("font_size", 10)
		unit_count_lbl.add_theme_color_override("font_color", Color(0.50, 0.55, 0.65))
		vbox.add_child(unit_count_lbl)


func _bar_row(parent: Control, label: String, current: int, maximum: int, empty_c: Color, fill_c: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = "%s %d/%d" % [label, current, maximum]
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.60, 0.60, 0.65))
	lbl.custom_minimum_size = Vector2(80, 0)
	row.add_child(lbl)

	var bar_bg := ColorRect.new()
	bar_bg.custom_minimum_size = Vector2(120, 10)
	bar_bg.color = empty_c.darkened(0.5)
	bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar_bg)

	var bar_fill := ColorRect.new()
	var pct: float = float(current) / float(maximum)
	bar_fill.color = fill_c
	bar_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	bar_fill.anchor_right = clamp(pct, 0.0, 1.0)
	bar_bg.add_child(bar_fill)


# --------------------------------------------------
# Helpers
# --------------------------------------------------
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


func _section_title(text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", color)
	_content_vbox.add_child(lbl)


func _section_label(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.45, 0.42, 0.35))
	_content_vbox.add_child(lbl)


func _info_label(text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_vbox.add_child(lbl)


func _divider() -> void:
	var line := ColorRect.new()
	line.color = Color(0.22, 0.20, 0.16)
	line.custom_minimum_size = Vector2(0, 1)
	_content_vbox.add_child(line)


func _on_close() -> void:
	hide()
	closed.emit()
