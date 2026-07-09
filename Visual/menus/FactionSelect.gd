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
var _province_count: int = 40
var _map_data: MapData = null

# UI refs
var _detail_panel: Control
var _start_btn: Button
var _card_grid: GridContainer

const BAD_SEEDS_PATH := "user://bad_river_seeds.json"
var _bad_seeds: Dictionary = {}


func _ready() -> void:
	_load_bad_seeds()
	_generate_map()
	_build_ui()


func _load_bad_seeds() -> void:
	if not FileAccess.file_exists(BAD_SEEDS_PATH):
		return
	var f := FileAccess.open(BAD_SEEDS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_bad_seeds = parsed


func _save_bad_seeds() -> void:
	var f := FileAccess.open(BAD_SEEDS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_bad_seeds))


func _generate_map() -> void:
	var settings := MapSettingsScript.new()
	settings.province_count = _province_count
	var generator := MapGeneratorScript.new()
	const MAX_ATTEMPTS := 10
	for attempt in MAX_ATTEMPTS:
		settings.seed = 0  # let generator randomize each time
		_map_data = generator.generate_map(settings)
		var sid := str(_map_data.map_seed)
		if _bad_seeds.has(sid):
			DebugLogger.log("river_seed_skipped", {"seed": sid, "attempt": attempt})
			continue
		if _river_is_feasible(_map_data):
			DebugLogger.log("river_seed_accepted", {"seed": sid, "attempt": attempt})
			break
		DebugLogger.log("river_seed_bad", {"seed": sid, "attempt": attempt})
		_bad_seeds[sid] = true
		_save_bad_seeds()


# Quick A* feasibility check — same logic as PlayerMap._build_branch but
# lightweight (no continent polygon, bounds-only wall check) so we can run
# it before the scene transition.
func _river_is_feasible(md: MapData) -> bool:
	if md == null or md.provinces.is_empty():
		return false
	const GRID := 45.0
	const COST_DOWN := 1.0
	const COST_LATERAL := 3.0
	const COST_UP := 12.0

	# Compute bounds
	var minx := 1.0e18; var miny := 1.0e18
	var maxx := -1.0e18; var maxy := -1.0e18
	for item in md.provinces:
		var p := item as ProvinceData
		minx = minf(minx, p.center.x); miny = minf(miny, p.center.y)
		maxx = maxf(maxx, p.center.x); maxy = maxf(maxy, p.center.y)
	var bounds := Rect2(Vector2(minx, miny), Vector2(maxx - minx, maxy - miny))

	# Precompute blocked cells
	var blocked: Dictionary = {}
	var x := bounds.position.x - GRID
	while x <= bounds.position.x + bounds.size.x + GRID:
		var y := bounds.position.y - GRID
		while y <= bounds.position.y + bounds.size.y + GRID:
			var best_biome := ""
			var best_d := 1.0e18
			for item in md.provinces:
				var p := item as ProvinceData
				var d := Vector2(x, y).distance_squared_to(p.center)
				if d < best_d:
					best_d = d
					best_biome = p.biome
			if best_biome in ["desert", "mountain"]:
				blocked["%d_%d" % [int(round(x / GRID)), int(round(y / GRID))]] = true
			y += GRID
		x += GRID

	var cx := bounds.position.x + bounds.size.x * 0.5
	var start := Vector2(round(cx / GRID) * GRID,
			round((bounds.position.y + bounds.size.y * 0.15) / GRID) * GRID)
	var end_y: float = lerpf(start.y, bounds.position.y + bounds.size.y, 0.85)

	var gk := func(pos: Vector2) -> String:
		return "%d_%d" % [int(round(pos.x / GRID)), int(round(pos.y / GRID))]

	var open_set: Array = []
	var g_score: Dictionary = {}
	var closed: Dictionary = {}
	var sk: String = gk.call(start)
	g_score[sk] = 0.0
	open_set.append([maxf(0.0, end_y - start.y) / GRID, start])

	while not open_set.is_empty():
		var bi := 0
		for idx in range(1, open_set.size()):
			if (open_set[idx] as Array)[0] < (open_set[bi] as Array)[0]:
				bi = idx
		var entry: Array = open_set[bi]
		open_set.remove_at(bi)
		var cur: Vector2 = entry[1]
		var ck: String = gk.call(cur)
		if closed.has(ck):
			continue
		closed[ck] = true
		if cur.y >= end_y:
			# Also verify the path is long enough to support 3 tributaries
			var path_len: int = closed.size()
			return path_len >= 12

		for nb in [[Vector2.DOWN, COST_DOWN], [Vector2.LEFT, COST_LATERAL],
				[Vector2.RIGHT, COST_LATERAL], [Vector2.UP, COST_UP]]:
			var np: Vector2 = cur + (nb[0] as Vector2) * GRID
			var nk: String = gk.call(np)
			if closed.has(nk) or blocked.has(nk):
				continue
			if np.x < bounds.position.x - GRID or np.x > bounds.position.x + bounds.size.x + GRID:
				continue
			var ng: float = g_score[ck] + (nb[1] as float)
			if not g_score.has(nk) or ng < g_score[nk]:
				g_score[nk] = ng
				open_set.append([ng + maxf(0.0, end_y - np.y) / GRID, np])
	return false


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
	var left_margin := MarginContainer.new()
	left_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_margin.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	left_margin.add_theme_constant_override("margin_left",   20)
	left_margin.add_theme_constant_override("margin_right",  20)
	left_margin.add_theme_constant_override("margin_top",    16)
	left_margin.add_theme_constant_override("margin_bottom", 16)
	root_hbox.add_child(left_margin)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 12)
	left_margin.add_child(left)

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

	# Faction grid scroll
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)

	_card_grid = GridContainer.new()
	_card_grid.columns = 5
	_card_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_grid.add_theme_constant_override("h_separation", 10)
	_card_grid.add_theme_constant_override("v_separation", 10)
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
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 160)

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

	# Portrait — use sprite if available, else colored placeholder
	vbox.add_child(_make_portrait(faction, 60))

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

	# Portrait — use sprite if available, else colored placeholder
	detail_vbox.add_child(_make_portrait(faction, 120))

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
	_start_btn.disabled = true
	_show_loading_screen()
	await get_tree().process_frame
	await get_tree().process_frame

	_set_loading_progress(0.2, "Initializing game state...")
	await get_tree().process_frame
	var game_state := GameState.new()
	game_state.human_faction_id = _selected_faction_id
	game_state.init_with_map(_map_data)

	_set_loading_progress(0.5, "Building terrain tiles...")
	await get_tree().process_frame
	var terrain := MapTerrainGenerator.new()
	terrain.generate_base_tiles(_map_data)

	_set_loading_progress(0.65, "Generating noise overlays...")
	await get_tree().process_frame
	terrain.generate_noise_tiles(_map_data)

	_set_loading_progress(0.75, "Painting biomes...")
	await get_tree().process_frame
	terrain.generate_biome_tiles(_map_data)

	_set_loading_progress(0.85, "Scattering trees...")
	await get_tree().process_frame
	terrain.generate_trees(_map_data)

	SceneManager.pending_terrain = terrain
	_set_loading_progress(1.0, "Loading campaign map...")
	await get_tree().process_frame

	SceneManager.go_to_campaign(game_state, _map_data, _selected_faction_id)


var _loading_bar: ProgressBar = null
var _loading_label: Label = null

func _show_loading_screen() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.80)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 100
	add_child(overlay)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 16)
	overlay.add_child(vbox)

	var title := Label.new()
	title.text = "Loading Campaign..."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	vbox.add_child(title)

	_loading_bar = ProgressBar.new()
	_loading_bar.min_value = 0.0
	_loading_bar.max_value = 1.0
	_loading_bar.value = 0.0
	_loading_bar.custom_minimum_size = Vector2(400, 24)
	_loading_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(_loading_bar)

	_loading_label = Label.new()
	_loading_label.text = "Please wait..."
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.add_theme_font_size_override("font_size", 13)
	_loading_label.add_theme_color_override("font_color", Color(0.70, 0.70, 0.70))
	vbox.add_child(_loading_label)


func _set_loading_progress(value: float, status: String) -> void:
	if _loading_bar:
		_loading_bar.value = value
	if _loading_label:
		_loading_label.text = status


func _make_portrait(faction: FactionData, height: int) -> Control:
	var fkey: String = str(faction.get("faction_key") if faction.get("faction_key") != null else "")
	# Prefer portrait file, fall back to battle sprite
	var candidates: Array = [
		"res://Art/leaders/%s/portraits/%s_portrait.png" % [fkey, fkey],
		"res://Art/leaders/%s/sprites/%s.png" % [fkey, fkey],
	]
	if fkey != "":
		for tex_path: String in candidates:
			if ResourceLoader.exists(tex_path):
				var tex: Texture2D = load(tex_path) as Texture2D
				var tr := TextureRect.new()
				tr.texture = tex
				tr.custom_minimum_size = Vector2(0, height)
				tr.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
				tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				return tr
	# Fallback placeholder
	var box := ColorRect.new()
	box.color = faction.color.darkened(0.65)
	box.custom_minimum_size = Vector2(0, height)
	var lbl := Label.new()
	lbl.text = "[ Portrait ]"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color(0.35, 0.35, 0.35))
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_child(lbl)
	return box
