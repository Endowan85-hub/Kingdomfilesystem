# ==================================================
# PlayerMap
# ==================================================
# Player-facing campaign map rendered as a Node2D.
# Draws styled province fills, borders, route lines,
# and province nodes on top of a parchment background.
#
# Reads from GameState / MapData — never modifies them.
# Emits signals for province hover and click.
#
# Phase 2 visual layer — no simulation logic here.
# ==================================================
extends Node2D
class_name PlayerMap

signal province_hovered(province_id: int)
signal province_clicked(province_id: int)

# Set by CampaignMap after initialization
var game_state: GameState = null
var map_data: MapData = null
var human_faction_id: int = 0

# Camera / pan / zoom (mirrors debug view logic)
var _zoom: float = 1.0
var _origin: Vector2 = Vector2.ZERO
var _is_panning: bool = false
var _pan_last: Vector2 = Vector2.ZERO

# Voronoi cells mirrored from debug view
var _voronoi_cells: Dictionary = {}  # int -> Array[Vector2]

var _hover_id: int = -1
var _selected_id: int = -1

const NODE_RADIUS: float = 9.0
const PICK_RADIUS: float = 16.0

# Parchment-style background colors
const BG_COLOR       := Color(0.14, 0.11, 0.08)
const NEUTRAL_BORDER := Color(0.30, 0.27, 0.20, 0.70)


func init(gs: GameState, md: MapData, human_id: int, voronoi: Dictionary) -> void:
	game_state = gs
	map_data = md
	human_faction_id = human_id
	_voronoi_cells = voronoi
	_frame_map()
	queue_redraw()


func refresh() -> void:
	queue_redraw()


# --------------------------------------------------
# Input
# --------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if game_state == null or map_data == null:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var pid: int = _pick_province(mb.position)
			if pid >= 0:
				_selected_id = pid
				province_clicked.emit(pid)
				queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE or (mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed):
			_is_panning = mb.pressed
			_pan_last = mb.position
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mb.position, 1.12)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mb.position, 1.0 / 1.12)

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _is_panning:
			_origin += mm.relative / _zoom
			queue_redraw()
		var new_hover: int = _pick_province(mm.position)
		if new_hover != _hover_id:
			_hover_id = new_hover
			province_hovered.emit(_hover_id)
			queue_redraw()


# --------------------------------------------------
# Drawing
# --------------------------------------------------
func _draw() -> void:
	if map_data == null:
		return
	_draw_background()
	_draw_routes()
	_draw_cells()
	_draw_nodes()


func _draw_background() -> void:
	var vp := get_viewport_rect()
	draw_rect(vp, BG_COLOR)


func _draw_cells() -> void:
	for item in map_data.provinces:
		var p: ProvinceData = item as ProvinceData
		var pid: int = int(p.id)
		if not _voronoi_cells.has(pid):
			continue

		var raw_pts: Array = _voronoi_cells[pid]
		var pts: PackedVector2Array = PackedVector2Array()
		for v in raw_pts:
			pts.append(_to_screen(v))

		var owner_id: int = int(p.owner_id)
		var is_human: bool = owner_id == human_faction_id
		var is_neutral: bool = owner_id < 0
		var is_hover: bool = pid == _hover_id
		var is_selected: bool = pid == _selected_id

		# --- Fill ---
		var biome_c: Color = _biome_color(p.biome)
		var fill_c: Color
		if is_neutral:
			fill_c = biome_c.darkened(0.15)
			fill_c.a = 0.55
		else:
			var faction_c: Color = _faction_color(owner_id)
			fill_c = biome_c.lerp(faction_c, 0.35)
			fill_c.a = 0.75
			if is_human:
				fill_c.a = 0.85

		if is_hover:
			fill_c = fill_c.lightened(0.18)
		if is_selected:
			fill_c = fill_c.lightened(0.25)

		draw_colored_polygon(pts, fill_c)

		# --- Border ---
		var border_c: Color
		var border_w: float
		if is_selected:
			border_c = Color(1.0, 0.90, 0.40, 1.0)
			border_w = 3.5
		elif is_hover:
			border_c = Color(1.0, 1.0, 1.0, 0.85)
			border_w = 2.5
		elif is_human:
			border_c = _faction_color(owner_id)
			border_c.a = 1.0
			border_w = 2.5
		elif not is_neutral:
			border_c = _faction_color(owner_id)
			border_c.a = 0.80
			border_w = 1.8
		else:
			border_c = NEUTRAL_BORDER
			border_w = 1.0

		draw_polyline(pts, border_c, border_w, true)

		# --- Fort level indicator (small dots) ---
		if not is_neutral:
			_draw_fort_indicator(p, pts)


func _draw_fort_indicator(p: ProvinceData, pts: PackedVector2Array) -> void:
	var center: Vector2 = _to_screen(p.center)
	var fort: int = clamp(int(p.fort_level), 0, 5)
	var dot_r: float = 3.0
	var spacing: float = 8.0
	var total_w: float = fort * spacing - spacing * 0.5
	var start_x: float = center.x - total_w * 0.5
	for i in range(fort):
		var dot_pos := Vector2(start_x + i * spacing, center.y + NODE_RADIUS + 6.0)
		draw_circle(dot_pos, dot_r, Color(0.90, 0.80, 0.40, 0.85))


func _draw_routes() -> void:
	if map_data == null:
		return
	for r in map_data.routes:
		var a: ProvinceData = map_data.provinces[int(r.a)] as ProvinceData
		var b: ProvinceData = map_data.provinces[int(r.b)] as ProvinceData
		draw_line(_to_screen(a.center), _to_screen(b.center), Color(0.55, 0.48, 0.32, 0.50), 1.5)


func _draw_nodes() -> void:
	for item in map_data.provinces:
		var p: ProvinceData = item as ProvinceData
		var pid: int = int(p.id)
		var pos: Vector2 = _to_screen(p.center)
		var owner_id: int = int(p.owner_id)
		var is_neutral: bool = owner_id < 0

		var node_c: Color
		if is_neutral:
			node_c = Color(0.45, 0.42, 0.38)
		else:
			node_c = _faction_color(owner_id)

		# Outer ring
		draw_circle(pos, NODE_RADIUS + 1.5, Color(0.10, 0.08, 0.06, 0.85))
		# Inner fill
		draw_circle(pos, NODE_RADIUS, node_c)

		# Leader presence dot (white pip if leaders are here)
		if game_state != null and not is_neutral:
			var leaders: Array = game_state.get_province_leaders(pid, false)
			if not leaders.is_empty():
				draw_circle(pos, 3.5, Color(1, 1, 1, 0.90))


# --------------------------------------------------
# Coordinate helpers
# --------------------------------------------------
func _to_screen(world: Vector2) -> Vector2:
	return (world + _origin) * _zoom


func _to_world(screen: Vector2) -> Vector2:
	return screen / _zoom - _origin


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var world_before: Vector2 = _to_world(screen_pos)
	_zoom = clamp(_zoom * factor, 0.15, 8.0)
	_origin = screen_pos / _zoom - world_before
	queue_redraw()


func _frame_map() -> void:
	if map_data == null or map_data.provinces.is_empty():
		return
	var min_pt := Vector2(INF, INF)
	var max_pt := Vector2(-INF, -INF)
	for item in map_data.provinces:
		var p: ProvinceData = item as ProvinceData
		min_pt = min_pt.min(p.center)
		max_pt = max_pt.max(p.center)
	var bounds := Rect2(min_pt, max_pt - min_pt)
	var vp := get_viewport_rect().size
	var pad := 80.0
	_zoom = min((vp.x - pad * 2.0) / bounds.size.x, (vp.y - pad * 2.0) / bounds.size.y)
	_origin = -bounds.position + Vector2(pad, pad) / _zoom


# --------------------------------------------------
# Province picking
# --------------------------------------------------
func _pick_province(screen_pos: Vector2) -> int:
	if map_data == null:
		return -1
	var world_pos: Vector2 = _to_world(screen_pos)
	var best_id: int = -1
	var best_dist: float = PICK_RADIUS / _zoom
	for item in map_data.provinces:
		var p: ProvinceData = item as ProvinceData
		var d: float = world_pos.distance_to(p.center)
		if d < best_dist:
			best_dist = d
			best_id = int(p.id)
	return best_id


# --------------------------------------------------
# Color helpers
# --------------------------------------------------
func _faction_color(owner_id: int) -> Color:
	if game_state != null and game_state.map_data != null:
		for item in game_state.map_data.factions:
			var f: FactionData = item as FactionData
			if f != null and int(f.id) == owner_id:
				return f.color
	return Color(0.55, 0.55, 0.55)


func _biome_color(biome: String) -> Color:
	match biome:
		"plains":   return Color(0.48, 0.62, 0.32)
		"forest":   return Color(0.16, 0.42, 0.20)
		"mountain": return Color(0.52, 0.48, 0.44)
		"desert":   return Color(0.76, 0.64, 0.32)
		"tundra":   return Color(0.62, 0.74, 0.80)
		"swamp":    return Color(0.28, 0.42, 0.28)
		"coast":    return Color(0.24, 0.52, 0.72)
		_:          return Color(0.45, 0.45, 0.45)
