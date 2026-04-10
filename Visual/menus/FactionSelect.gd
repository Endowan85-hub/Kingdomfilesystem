# ==================================================
# FactionSelect
# ==================================================
# Player chooses which of the 15 great houses to lead.
# Generates MapData, sets human_faction_id, then
# hands off to CampaignMap via SceneManager.
# ==================================================
extends Control
class_name FactionSelect

const StoryLeaderLibrary = preload("res://Scripts/data/story_leader_library.gd")
const MapGeneratorScript = preload("res://Scripts/map/map_generator.gd")
const MapSettingsScript  = preload("res://Scripts/map/map_settings.gd")
const GameStateScript    = preload("res://Scripts/game/game_state.gd")

var _selected_faction_id: int = -1
var _selected_entry: Dictionary = {}
var _province_count: int = 20
var _map_data: MapData = null

# UI refs
var _detail_panel: Control
var _start_btn: Button
var _card_grid: GridContainer


func _ready() -> void:
	_generate_map()
	_build_ui()


func _generate_map() -> void:
	var settings := MapSettingsScript.new()
	settings.province_count = _province_count
	var generator := MapGeneratorScript.new()
	_map_data = generator.generate_map(settings)


func _build_ui() -> void:
	# --- Dark background ---
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.03, 0.07, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# --- Main layout: left panel + right detail ---
	var root_hbox := HBoxContainer.new()
	root_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_hbox.add_theme_constant_override("separation", 0)
	add_child(root_hbox)

	# Left side: title + map preview + faction grid
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 12)
	left.custom_minimum_size = Vector2(820, 0)
	root_hbox.add_child(left)

	# Title
	var title_lbl := Label.new()
	title_lbl.text = "Choose Your Faction"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 28)
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	title_lbl.custom_minimum_size = Vector2(0, 50)
	left.add_child(title_lbl)

	# Map preview placeholder
	var map_preview := ColorRect.new()
	map_preview.color = Color(0.08, 0.10, 0.14)
	map_preview.custom_minimum_size = Vector2(0, 180)
	map_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(map_preview)

	var map_hint := Label.new()
	map_hint.text = "[ Campaign Map Preview — Phase 2 ]"
	map_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	map_hint.add_theme_color_override("font_color", Color(0.25, 0.28, 0.32))
	map_hint.add_theme_font_size_override("font_size", 12)
	map_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_preview.add_child(map_hint)

	# Province count selector
	var province_row := HBoxContainer.new()
	province_row.alignment = BoxContainer.ALIGNMENT_CENTER
	province_row.add_theme_constant_override("separation", 12)
	left.add_child(province_row)

	var prov_lbl := Label.new()
	prov_lbl.text = "Province Count:"
	prov_lbl.add_theme_color_override("font_color", Color(0.70, 0.68, 0.60))
	prov_lbl.add_theme_font_size_override("font_size", 13)
	province_row.add_child(prov_lbl)

	for count in [20, 40]:
		var pbtn := Button.new()
		pbtn.text = str(count)
		pbtn.custom_minimum_size = Vector2(60, 32)
		pbtn.toggle_mode = true
		pbtn.button_pressed = (count == _province_count)
		var c: int = count
		pbtn.toggled.connect(func(pressed: bool) -> void:
			if pressed:
				_province_count = c
				_generate_map()
		)
		province_row.add_child(pbtn)

	# Faction grid scroll
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)

	_card_grid = GridContainer.new()
	_card_grid.columns = 5
	_card_grid.add_theme_constant_override("h_separation", 8)
	_card_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_card_grid)

	_build_faction_cards()

	# Right detail panel
	_detail_panel = _build_detail_panel()
	root_hbox.add_child(_detail_panel)


func _build_faction_cards() -> void:
	for child in _card_grid.get_children():
		child.queue_free()

	# Build faction lookup
	var key_to_faction: Dictionary = {}
	if _map_data != null:
		for item in _map_data.factions:
			var f := item as FactionData
			if f != null and f.faction_key != "":
				key_to_faction[f.faction_key] = f

	for entry in StoryLeaderLibrary.STORY_ROSTER:
		var fkey: String = entry.get("faction_key", "")
		var faction := key_to_faction.get(fkey, null) as FactionData
		if faction == null:
			continue
		_card_grid.add_child(_make_card(entry, faction))


func _make_card(entry: Dictionary, faction: FactionData) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(148, 130)

	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(0.09, 0.10, 0.14)
	style_normal.border_color = Color(0.28, 0.28, 0.38)
	style_normal.set_border_width_all(1)
	style_normal.set_corner_radius_all(3)

	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = Color(0.13, 0.14, 0.20)
	style_hover.border_color = faction.color
	style_hover.set_border_width_all(2)
	style_hover.set_corner_radius_all(3)

	card.add_theme_stylebox_override("panel", style_normal)
	card.mouse_entered.connect(func() -> void: card.add_theme_stylebox_override("panel", style_hover))
	card.mouse_exited.connect(func() -> void: card.add_theme_stylebox_override("panel", style_normal))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	card.add_child(vbox)

	# Color bar
	var bar := ColorRect.new()
	bar.color = faction.color
	bar.custom_minimum_size = Vector2(0, 4)
	vbox.add_child(bar)

	# Portrait placeholder
	var portrait := ColorRect.new()
	portrait.color = faction.color.darkened(0.6)
	portrait.custom_minimum_size = Vector2(0, 40)
	var portrait_hint := Label.new()
	portrait_hint.text = "[ Portrait ]"
	portrait_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait_hint.add_theme_color_override("font_color", Color(0.35, 0.35, 0.35))
	portrait_hint.add_theme_font_size_override("font_size", 9)
	portrait_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.add_child(portrait_hint)
	vbox.add_child(portrait)

	# House name
	var house_lbl := Label.new()
	house_lbl.text = faction.display_name
	house_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	house_lbl.add_theme_font_size_override("font_size", 9)
	house_lbl.add_theme_color_override("font_color", Color(0.70, 0.80, 0.95))
	house_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(house_lbl)

	# Leader name
	var leader_lbl := Label.new()
	leader_lbl.text = entry.get("display_name", "?")
	leader_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	leader_lbl.add_theme_font_size_override("font_size", 11)
	leader_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	vbox.add_child(leader_lbl)

	# Select button
	var btn := Button.new()
	btn.text = "Select"
	btn.add_theme_font_size_override("font_size", 10)
	var fid: int = faction.id
	btn.pressed.connect(func() -> void: _on_faction_selected(fid, entry, faction))
	vbox.add_child(btn)

	return card


func _build_detail_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.10)
	style.border_color = Color(0.25, 0.25, 0.35)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	# Placeholder text shown before selection
	var hint := Label.new()
	hint.text = "Select a faction\nto see details"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.35, 0.33, 0.30))
	hint.add_theme_font_size_override("font_size", 14)
	hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hint.name = "HintLabel"
	vbox.add_child(hint)

	# Start button (bottom)
	_start_btn = Button.new()
	_start_btn.text = "Begin Campaign"
	_start_btn.custom_minimum_size = Vector2(0, 50)
	_start_btn.add_theme_font_size_override("font_size", 16)
	_start_btn.disabled = true
	_start_btn.pressed.connect(_on_start_campaign)
	vbox.add_child(_start_btn)

	# Back button
	var back_btn := Button.new()
	back_btn.text = "← Back to Main Menu"
	back_btn.add_theme_font_size_override("font_size", 12)
	back_btn.pressed.connect(func() -> void: SceneManager.go_to_main_menu())
	vbox.add_child(back_btn)

	return panel


func _on_faction_selected(faction_id: int, entry: Dictionary, faction: FactionData) -> void:
	_selected_faction_id = faction_id
	_selected_entry = entry

	# Rebuild detail panel contents
	var vbox := _detail_panel.get_child(0) as VBoxContainer
	var hint := vbox.get_node("HintLabel") as Label
	if hint:
		hint.queue_free()

	# Clear previous detail nodes (keep start/back buttons)
	for child in vbox.get_children():
		if child != _start_btn and child.name != "BackBtn":
			child.queue_free()

	# Rebuild detail content
	var detail_vbox := VBoxContainer.new()
	detail_vbox.add_theme_constant_override("separation", 10)
	detail_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(detail_vbox)
	vbox.move_child(detail_vbox, 0)

	# Faction color bar
	var bar := ColorRect.new()
	bar.color = faction.color
	bar.custom_minimum_size = Vector2(0, 5)
	detail_vbox.add_child(bar)

	# Portrait placeholder
	var portrait_box := ColorRect.new()
	portrait_box.color = faction.color.darkened(0.65)
	portrait_box.custom_minimum_size = Vector2(0, 120)
	var p_lbl := Label.new()
	p_lbl.text = "[ Leader Portrait ]"
	p_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p_lbl.add_theme_color_override("font_color", Color(0.30, 0.30, 0.30))
	p_lbl.add_theme_font_size_override("font_size", 11)
	p_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait_box.add_child(p_lbl)
	detail_vbox.add_child(portrait_box)

	# Faction + leader names
	_detail_label(detail_vbox, faction.display_name, 11, Color(0.65, 0.78, 1.0))
	_detail_label(detail_vbox, entry.get("display_name", ""), 18, Color(0.95, 0.85, 0.45))
	_detail_label(detail_vbox, entry.get("archetype", ""), 12, Color(0.60, 0.70, 0.60))
	_detail_label(detail_vbox, "Playstyle: " + str(entry.get("ai_playstyle", "")).capitalize(), 11, Color(0.55, 0.80, 0.55))

	# Stats
	var stats := "Ldr %d  ·  Atk %d  ·  Def %d  ·  Mag %d" % [
		entry.get("leadership", 5), entry.get("attack", 5),
		entry.get("defense", 5), entry.get("magic", 5)
	]
	_detail_label(detail_vbox, stats, 11, Color(0.68, 0.68, 0.78))

	# Traits
	var traits: Array = entry.get("traits", [])
	if not traits.is_empty():
		_detail_label(detail_vbox, "Traits: " + ", ".join(traits), 10, Color(0.55, 0.65, 0.75))

	# Lore placeholder
	_detail_label(detail_vbox, "[ Lore flavor text — Phase 5 ]", 10, Color(0.30, 0.28, 0.25))

	_start_btn.disabled = false
	_start_btn.text = "Begin as %s" % entry.get("display_name", "?")


func _detail_label(parent: Control, text: String, size: int, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(lbl)


func _on_start_campaign() -> void:
	if _selected_faction_id < 0 or _map_data == null:
		return

	# Initialize game state
	var game_state := GameState.new()
	game_state.human_faction_id = _selected_faction_id
	game_state.init_with_map(_map_data)

	SceneManager.go_to_campaign(game_state, _map_data, _selected_faction_id)
