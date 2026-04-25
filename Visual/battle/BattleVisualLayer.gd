# ==================================================
# BattleVisualLayer
# ==================================================
# Phase 3 — visual enhancement overlay for the battle scene.
# Sits at CanvasLayer 20 (above the simulation's layer 10).
#
# Provides:
#   - Unit HP bar overlays (drawn over unit circles)
#   - Styled top bar (round / faction names)
#   - Styled bottom bar (active unit info)
#   - Battle result overlay (styled scorecard replacement)
#
# Reads BattleScene state — never mutates it.
# ==================================================
extends CanvasLayer
class_name BattleVisualLayer

const GRID_COLS : int = 19
const GRID_ROWS : int = 19
const TILE_W    : int = 128   # must match BattleGrid.TILE_W
const TILE_H    : int = 64    # must match BattleGrid.TILE_H

var _origin : Vector2 = Vector2.ZERO  # computed in _ready, same formula as BattleGrid

var _battle_scene = null
var _setup: Dictionary = {}

# Sub-layers
var _terrain_layer: BattleTerrainLayer = null
var _hpbar_draw: _HPBarDraw = null

# HUD nodes
var _top_bar: PanelContainer = null
var _round_label: Label = null
var _atk_label: Label = null
var _def_label: Label = null

var _bottom_bar: PanelContainer = null
var _unit_info_label: Label = null

# Result overlay
var _result_overlay: Control = null
var _result_visible: bool = false


func init_layer(battle_scene, setup: Dictionary) -> void:
	_battle_scene = battle_scene
	_setup = setup

	# Enrich setup with display names from GameState
	var state = setup.get("state")
	if state != null:
		var province_id: int = int(setup.get("target_province_id", -1))
		var atk_id: int = int(setup.get("attacker_faction_id", -1))
		var def_id: int = int(setup.get("defender_faction_id", -1))
		var map_data = state.get("map_data") if state.get("map_data") != null else null
		if map_data != null:
			for prov_item in map_data.provinces:
				var prov = prov_item as ProvinceData
				if prov != null and int(prov.id) == province_id:
					_setup["province_name"] = str(prov.display_name)
					break
			for fac_item in map_data.factions:
				var fac = fac_item as FactionData
				if fac == null:
					continue
				if int(fac.id) == atk_id:
					_setup["attacker_faction_name"] = str(fac.display_name)
				elif int(fac.id) == def_id:
					_setup["defender_faction_name"] = str(fac.display_name)

	# Wire battle_ended signal (fires before scorecard, so our overlay shows at the right time)
	if battle_scene != null and battle_scene.has_signal("battle_ended"):
		battle_scene.battle_ended.connect(_on_battle_finished)

	# Spawn terrain layer as sibling
	_terrain_layer = BattleTerrainLayer.new()
	var biome: String = str(setup.get("biome", "plains"))
	_terrain_layer.init_terrain(biome)
	if battle_scene != null:
		battle_scene.add_child(_terrain_layer)

	# Refresh HUD labels once scene is known
	_refresh_top_bar()


func _ready() -> void:
	layer = 20
	_compute_origin()
	_build_hpbar_draw()
	_build_top_bar()
	_build_result_overlay()

func _compute_origin() -> void:
	# Must match BattleGrid._compute_origin() exactly
	_origin = Vector2(
		float(GRID_ROWS) * TILE_W * 0.5,
		36.0
	)


# --------------------------------------------------
# HP Bar draw node
# --------------------------------------------------
func _build_hpbar_draw() -> void:
	_hpbar_draw = _HPBarDraw.new()
	_hpbar_draw.visual_layer_ref = self
	add_child(_hpbar_draw)


# --------------------------------------------------
# Top bar
# --------------------------------------------------
func _build_top_bar() -> void:
	_top_bar = PanelContainer.new()
	_top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top_bar.offset_bottom = 44.0
	_top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.10, 0.90)
	style.border_color = Color(0.35, 0.30, 0.18, 0.80)
	style.set_border_width_all(1)
	_top_bar.add_theme_stylebox_override("panel", style)
	add_child(_top_bar)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	_top_bar.add_child(hbox)

	_atk_label = Label.new()
	_atk_label.text = "Attacker"
	_atk_label.add_theme_font_size_override("font_size", 13)
	_atk_label.add_theme_color_override("font_color", Color(0.40, 0.70, 1.00))
	_atk_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_atk_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hbox.add_child(_atk_label)

	_round_label = Label.new()
	_round_label.text = "Battle"
	_round_label.add_theme_font_size_override("font_size", 14)
	_round_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	_round_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hbox.add_child(_round_label)

	_def_label = Label.new()
	_def_label.text = "Defender"
	_def_label.add_theme_font_size_override("font_size", 13)
	_def_label.add_theme_color_override("font_color", Color(1.00, 0.45, 0.35))
	_def_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_def_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(_def_label)


func _refresh_top_bar() -> void:
	if _setup.is_empty() or _round_label == null:
		return
	var province_name: String = str(_setup.get("province_name", "Unknown Province"))
	var biome: String = str(_setup.get("biome", "")).capitalize()
	var fort: int = int(_setup.get("fort_level", 0))
	var fort_str: String = "  ·  Fort %d" % fort if fort > 0 else ""
	_round_label.text = "%s  (%s%s)" % [province_name, biome, fort_str]

	var atk_name: String = str(_setup.get("attacker_faction_name", "Attacker"))
	var def_name: String = str(_setup.get("defender_faction_name", "Defender"))
	_atk_label.text = "⚔ %s" % atk_name
	_def_label.text = "%s ⚔" % def_name


# --------------------------------------------------
# Bottom bar — shows active unit info
# --------------------------------------------------
# --------------------------------------------------
# Result overlay
# --------------------------------------------------
func _build_result_overlay() -> void:
	_result_overlay = Control.new()
	_result_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_overlay.visible = false
	add_child(_result_overlay)

	# Dim background — ignore mouse so battle_scene buttons remain clickable
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_overlay.add_child(dim)

	# Result panel (centered)
	var panel := PanelContainer.new()
	panel.name = "ResultPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left  = -300.0
	panel.offset_top   = -220.0
	panel.offset_right =  300.0
	panel.offset_bottom = 220.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.12, 0.97)
	style.border_color = Color(0.55, 0.48, 0.22)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", style)
	_result_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.name = "ResultVBox"
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)


func _on_battle_finished(result: Dictionary) -> void:
	_populate_result(result)
	_result_overlay.visible = true
	_result_visible = true


func _populate_result(result: Dictionary) -> void:
	var vbox: VBoxContainer = _result_overlay.get_node_or_null("ResultPanel/ResultVBox")
	if vbox == null:
		return

	for child in vbox.get_children():
		child.queue_free()

	var attacker_won: bool = bool(result.get("attacker_won", false))
	var player_side: String = ""
	if _battle_scene != null:
		player_side = str(_battle_scene.get("_player_side") if _battle_scene.get("_player_side") != null else "")
	var player_won: bool = (attacker_won and player_side == "attacker") or \
						   (not attacker_won and player_side == "defender")

	# Title
	var title_lbl := Label.new()
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if player_won:
		title_lbl.text = "Victory"
		title_lbl.add_theme_color_override("font_color", Color(0.90, 0.80, 0.30))
	else:
		title_lbl.text = "Defeat"
		title_lbl.add_theme_color_override("font_color", Color(0.85, 0.30, 0.25))
	vbox.add_child(title_lbl)

	# Divider
	var div := ColorRect.new()
	div.color = Color(0.35, 0.30, 0.18)
	div.custom_minimum_size = Vector2(0, 1)
	vbox.add_child(div)

	# Stats
	var atk_lost: int = (result.get("dead_attacker_unit_ids", []) as Array).size() + \
						(result.get("captured_attacker_unit_ids", []) as Array).size()
	var def_lost: int = (result.get("dead_defender_unit_ids", []) as Array).size() + \
						(result.get("captured_defender_unit_ids", []) as Array).size()
	var rounds: int = int(result.get("rounds_taken", 0))
	var province_name: String = str(_setup.get("province_name", "Unknown"))

	_result_row(vbox, "Province", province_name, Color(0.75, 0.72, 0.55))
	_result_row(vbox, "Rounds", str(rounds), Color(0.65, 0.72, 0.80))
	_result_row(vbox, "Attacker losses", str(atk_lost), Color(0.40, 0.65, 1.00))
	_result_row(vbox, "Defender losses", str(def_lost), Color(1.00, 0.45, 0.35))

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)

	# Note — the actual close / return button is handled by the existing Scorecard
	var note_lbl := Label.new()
	note_lbl.text = "(Use 'Return to Campaign' below)"
	note_lbl.add_theme_font_size_override("font_size", 10)
	note_lbl.add_theme_color_override("font_color", Color(0.40, 0.38, 0.32))
	note_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(note_lbl)


func _result_row(parent: Control, key: String, value: String, value_color: Color) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	parent.add_child(hbox)

	var key_lbl := Label.new()
	key_lbl.text = key
	key_lbl.add_theme_font_size_override("font_size", 12)
	key_lbl.add_theme_color_override("font_color", Color(0.50, 0.48, 0.42))
	key_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(key_lbl)

	var val_lbl := Label.new()
	val_lbl.text = value
	val_lbl.add_theme_font_size_override("font_size", 12)
	val_lbl.add_theme_color_override("font_color", value_color)
	hbox.add_child(val_lbl)


# --------------------------------------------------
# Process — update HUD each frame
# --------------------------------------------------
func _process(_delta: float) -> void:
	if _battle_scene == null or _result_visible:
		return

	# Update round counter from battle state
	var _bs = _battle_scene.get("state")
	if _bs != null and _round_label != null:
		var _round: int = int(_bs.get("round") if _bs.get("round") != null else 0)
		var _province: String = str(_setup.get("province_name", "Battle"))
		var _biome: String = str(_setup.get("biome", "")).capitalize()
		var _fort: int = int(_setup.get("fort_level", 0))
		var _fort_str: String = "  ·  Fort %d" % _fort if _fort > 0 else ""
		_round_label.text = "%s  (%s%s)  —  Round %d" % [_province, _biome, _fort_str, _round]

	# Redraw HP bars
	if _hpbar_draw != null:
		_hpbar_draw.queue_redraw()




# --------------------------------------------------
# HP Bar drawing node (inner class)
# --------------------------------------------------
class _HPBarDraw extends Node2D:
	var visual_layer_ref: BattleVisualLayer = null

	func _draw() -> void:
		if visual_layer_ref == null or visual_layer_ref._battle_scene == null:
			return
		var bs = visual_layer_ref._battle_scene
		var state = bs.get("state")
		if state == null:
			return

		var all_units: Array = []
		var atk_units = state.get("attacker_units")
		var def_units = state.get("defender_units")
		if atk_units is Array:
			all_units.append_array(atk_units)
		if def_units is Array:
			all_units.append_array(def_units)

		for unit in all_units:
			if unit == null or not bool(unit.get("is_alive") if unit.get("is_alive") != null else false):
				continue
			var grid_pos = unit.get("grid_pos")
			if grid_pos == null:
				continue
			_draw_hp_bar(unit, grid_pos)


	func _draw_hp_bar(unit, _grid_pos: Vector2i) -> void:
		# Use BattleGrid's unit_screen_pos so position tracks zoom + camera + walking
		var bs = visual_layer_ref._battle_scene
		var bg = bs.get("battle_grid") if bs != null else null
		var center: Vector2
		if bg != null and bg.has_method("unit_screen_pos"):
			center = bg.unit_screen_pos(unit)
		else:
			var origin := visual_layer_ref._origin
			center = origin + Vector2(
				float(_grid_pos.x - _grid_pos.y) * BattleVisualLayer.TILE_W * 0.5,
				float(_grid_pos.x + _grid_pos.y) * BattleVisualLayer.TILE_H * 0.5 + BattleVisualLayer.TILE_H * 0.5
			)

		var hp_cur: int = int(unit.get("battle_hp") if unit.get("battle_hp") != null else 0)
		var hp_max: int = int(unit.get("final_max_hp") if unit.get("final_max_hp") != null else 1)
		hp_max = max(1, hp_max)

		var bar_w: float = 44.0
		var bar_h: float = 5.0
		var bar_x: float = center.x - bar_w * 0.5
		var bar_y: float = center.y - 30.0  # above the unit circle

		# Background
		draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.15, 0.05, 0.05, 0.85), true)

		# Fill
		var pct: float = clamp(float(hp_cur) / float(hp_max), 0.0, 1.0)
		var fill_color: Color = Color(0.20, 0.75, 0.25) if pct > 0.5 else \
								Color(0.85, 0.65, 0.10) if pct > 0.25 else \
								Color(0.90, 0.20, 0.15)
		if pct > 0.0:
			draw_rect(Rect2(bar_x, bar_y, bar_w * pct, bar_h), fill_color, true)

		# Border
		draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(0.0, 0.0, 0.0, 0.6), false, 0.5)
