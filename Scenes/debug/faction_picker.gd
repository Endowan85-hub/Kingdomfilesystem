# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: FactionPicker
#
# Role:
# Startup overlay that lets the player choose which faction/story leader
# to play as. Emits faction_selected(faction_id) then removes itself.
#
# Allowed Interactions:
# - MapDebugView (via signal only)
# - StoryLeaderLibrary (read-only)
# - FactionData / MapData (read-only)
#
# Forbidden Responsibilities:
# - Must not modify GameState
# - Must not queue orders
#
# Game Phase:
# Pre-game (before Planning Phase begins)
# ==================================================
extends CanvasLayer
class_name FactionPicker

signal faction_selected(faction_id: int)

const StoryLeaderLibrary = preload("res://Scripts/data/story_leader_library.gd")

var _map_data: MapData = null


func init(map_data: MapData) -> void:
	_map_data = map_data
	_build_ui()


func _build_ui() -> void:
	# Full-screen dark overlay
	var overlay := ColorRect.new()
	overlay.color = Color(0.04, 0.04, 0.08, 0.96)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	# Centered container
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(outer)

	# Title
	var title := Label.new()
	title.text = "Choose Your Faction"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.90, 0.55))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(title)

	var sub := Label.new()
	sub.text = "Select a leader to begin your campaign"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color(0.65, 0.65, 0.75))
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(sub)

	# Scroll + grid
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1100, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(grid)

	# Build roster lookup
	var key_to_faction: Dictionary = {}
	if _map_data != null:
		for item in _map_data.factions:
			var f: FactionData = item as FactionData
			if f != null and str(f.faction_key) != "":
				key_to_faction[str(f.faction_key)] = f

	for entry in StoryLeaderLibrary.STORY_ROSTER:
		var fkey: String = str(entry.get("faction_key", ""))
		var faction: FactionData = key_to_faction.get(fkey, null) as FactionData
		if faction == null:
			continue
		grid.add_child(_make_card(entry, faction))


func _make_card(entry: Dictionary, faction: FactionData) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(200, 180)
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(0.10, 0.11, 0.16, 1.0)
	style_normal.border_color = Color(0.30, 0.30, 0.42, 1.0)
	style_normal.set_border_width_all(1)
	style_normal.set_corner_radius_all(4)
	card.add_theme_stylebox_override("panel", style_normal)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)

	# Faction color bar
	var color_bar := ColorRect.new()
	color_bar.color = faction.color
	color_bar.custom_minimum_size = Vector2(0, 5)
	color_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(color_bar)

	# House name
	var house_lbl := Label.new()
	house_lbl.text = str(faction.display_name)
	house_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	house_lbl.add_theme_font_size_override("font_size", 11)
	house_lbl.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	house_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(house_lbl)

	# Leader name
	var leader_lbl := Label.new()
	leader_lbl.text = str(entry.get("display_name", "?"))
	leader_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	leader_lbl.add_theme_font_size_override("font_size", 14)
	leader_lbl.add_theme_color_override("font_color", Color(1.0, 0.90, 0.55))
	leader_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(leader_lbl)

	# Playstyle
	var style_lbl := Label.new()
	style_lbl.text = str(entry.get("ai_playstyle", "")).capitalize()
	style_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	style_lbl.add_theme_font_size_override("font_size", 10)
	style_lbl.add_theme_color_override("font_color", Color(0.55, 0.80, 0.55))
	style_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(style_lbl)

	# Stats row
	var stats_lbl := Label.new()
	stats_lbl.text = "Ldr:%d  Atk:%d  Def:%d  Mag:%d" % [
		int(entry.get("leadership", 5)),
		int(entry.get("attack", 5)),
		int(entry.get("defense", 5)),
		int(entry.get("magic", 5))
	]
	stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_lbl.add_theme_font_size_override("font_size", 10)
	stats_lbl.add_theme_color_override("font_color", Color(0.70, 0.70, 0.80))
	stats_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(stats_lbl)

	# Traits
	var traits_arr: Array = entry.get("traits", [])
	var traits_lbl := Label.new()
	traits_lbl.text = ", ".join(traits_arr) if not traits_arr.is_empty() else ""
	traits_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	traits_lbl.add_theme_font_size_override("font_size", 9)
	traits_lbl.add_theme_color_override("font_color", Color(0.55, 0.65, 0.75))
	traits_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	traits_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(traits_lbl)

	# Select button
	var btn := Button.new()
	btn.text = "Play as %s" % str(entry.get("display_name", "?"))
	btn.add_theme_font_size_override("font_size", 11)
	var fid: int = int(faction.id)
	btn.pressed.connect(func() -> void: _on_faction_chosen(fid))
	vbox.add_child(btn)

	return card


func _on_faction_chosen(faction_id: int) -> void:
	faction_selected.emit(faction_id)
	queue_free()
