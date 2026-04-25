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

# Pick mode — set by CampaignMap when attack/transfer is active
var _pick_mode: int = 0   # 0=none 1=attack 2=transfer
var _pick_source_id: int = -1
var _pick_valid_targets: Array = []  # when non-empty, only highlight these


func set_pick_mode(mode: int, source_id: int, valid_targets: Array = []) -> void:
	_pick_mode = mode
	_pick_source_id = source_id
	_pick_valid_targets = valid_targets
	queue_redraw()

const NODE_RADIUS: float = 9.0
const PICK_RADIUS: float = 16.0

# Parchment-style background colors
const BG_COLOR       := Color(0.14, 0.11, 0.08)
const NEUTRAL_BORDER := Color(0.30, 0.27, 0.20, 0.70)


func init(gs: GameState, md: MapData, human_id: int, voronoi: Dictionary) -> void:
	game_state = gs
	map_data = md
	human_faction_id = human_id
	if voronoi.is_empty() and md != null:
		_build_voronoi(md)
	else:
		_voronoi_cells = voronoi
	_frame_map()
	queue_redraw()


# --------------------------------------------------
# Voronoi generation (used when debug view is not present)
# --------------------------------------------------
func _build_voronoi(data: MapData) -> void:
	_voronoi_cells.clear()
	if data == null or data.provinces.is_empty():
		return
	var bounds: Rect2 = _map_bounds(data)
	for item_a in data.provinces:
		var a: ProvinceData = item_a as ProvinceData
		var poly: Array = [
			bounds.position,
			bounds.position + Vector2(bounds.size.x, 0.0),
			bounds.position + bounds.size,
			bounds.position + Vector2(0.0, bounds.size.y)
		]
		for item_b in data.provinces:
			var b: ProvinceData = item_b as ProvinceData
			if a == b:
				continue
			poly = _clip_half_plane(poly, a.center, b.center)
			if poly.size() < 3:
				break
		_voronoi_cells[int(a.id)] = poly


func _map_bounds(data: MapData) -> Rect2:
	var minx: float = 1.0e18; var miny: float = 1.0e18
	var maxx: float = -1.0e18; var maxy: float = -1.0e18
	for item in data.provinces:
		var p: ProvinceData = item as ProvinceData
		minx = minf(minx, p.center.x); miny = minf(miny, p.center.y)
		maxx = maxf(maxx, p.center.x); maxy = maxf(maxy, p.center.y)
	if maxx < minx or maxy < miny:
		return Rect2(Vector2.ZERO, Vector2.ONE)
	return Rect2(Vector2(minx, miny), Vector2(maxx - minx, maxy - miny))


func _clip_half_plane(poly: Array, a: Vector2, b: Vector2) -> Array:
	var out: Array = []
	var mid: Vector2 = (a + b) * 0.5
	var normal: Vector2 = (b - a).normalized()
	var prev: Vector2 = poly[poly.size() - 1]
	var prev_in: bool = (prev - mid).dot(normal) <= 0.0
	for curr in poly:
		var curr_v: Vector2 = curr
		var curr_in: bool = (curr_v - mid).dot(normal) <= 0.0
		if curr_in != prev_in:
			var dir: Vector2 = curr_v - prev
			var denom: float = dir.dot(normal)
			if absf(denom) > 0.000001:
				var t: float = ((mid - prev).dot(normal)) / denom
				out.append(prev + dir * t)
		if curr_in:
			out.append(curr_v)
		prev = curr_v
		prev_in = curr_in
	return out


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
	_draw_order_indicators()


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

		# --- Pick mode highlights ---
		if _pick_mode != 0:
			if pid == _pick_source_id:
				# Source province: bright gold ring
				draw_polyline(pts, Color(1.0, 0.90, 0.20, 1.0), 4.0, true)
			elif _pick_mode == 1:
				# Attack mode: only highlight valid adjacent targets
				var is_valid_target: bool = _pick_valid_targets.is_empty() or _pick_valid_targets.has(pid)
				if is_valid_target and not is_human and not is_neutral:
					draw_colored_polygon(pts, Color(1.0, 0.20, 0.15, 0.22))
					draw_polyline(pts, Color(1.0, 0.30, 0.25, 0.85), 2.0, true)
				elif is_valid_target and is_neutral:
					draw_colored_polygon(pts, Color(1.0, 0.55, 0.10, 0.18))
					draw_polyline(pts, Color(1.0, 0.60, 0.20, 0.75), 2.0, true)
			elif _pick_mode == 2 and is_human and pid != _pick_source_id:
				# Transfer mode: highlight own provinces blue
				draw_colored_polygon(pts, Color(0.25, 0.60, 1.0, 0.22))
				draw_polyline(pts, Color(0.35, 0.70, 1.0, 0.85), 2.0, true)

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


# --------------------------------------------------
# Order indicators
# --------------------------------------------------
func _draw_order_indicators() -> void:
	if game_state == null or game_state.order_book == null or map_data == null:
		return

	for atk in game_state.order_book.get_attacks(human_faction_id):
		var from_id: int = int(atk.get("from", -1))
		var to_id:   int = int(atk.get("to",   -1))
		if from_id < 0 or to_id < 0:
			continue
		if from_id >= map_data.provinces.size() or to_id >= map_data.provinces.size():
			continue
		var from_p: ProvinceData = map_data.provinces[from_id] as ProvinceData
		var to_p:   ProvinceData = map_data.provinces[to_id]   as ProvinceData
		if from_p == null or to_p == null:
			continue
		var from_s: Vector2 = _to_screen(from_p.center)
		var to_s:   Vector2 = _to_screen(to_p.center)
		# Connecting line
		draw_line(from_s, to_s, Color(1.0, 0.25, 0.20, 0.55), 2.0)
		_draw_arrowhead(from_s, to_s, Color(1.0, 0.30, 0.20, 0.90))
		# Icon above target node
		_draw_crossed_swords(_to_screen(to_p.center) + Vector2(0.0, -NODE_RADIUS - 16.0),
				10.0, Color(1.0, 0.28, 0.18, 1.0))

	for xfer in game_state.order_book.get_transfers(human_faction_id):
		var from_id: int = int(xfer.get("from", -1))
		var to_id:   int = int(xfer.get("to",   -1))
		if from_id < 0 or to_id < 0:
			continue
		if from_id >= map_data.provinces.size() or to_id >= map_data.provinces.size():
			continue
		var from_p: ProvinceData = map_data.provinces[from_id] as ProvinceData
		var to_p:   ProvinceData = map_data.provinces[to_id]   as ProvinceData
		if from_p == null or to_p == null:
			continue
		var from_s: Vector2 = _to_screen(from_p.center)
		var to_s:   Vector2 = _to_screen(to_p.center)
		# Connecting line
		draw_line(from_s, to_s, Color(0.35, 0.70, 1.0, 0.55), 2.0)
		_draw_arrowhead(from_s, to_s, Color(0.35, 0.70, 1.0, 0.90))
		# Icon above target node
		_draw_transfer_badge(_to_screen(to_p.center) + Vector2(0.0, -NODE_RADIUS - 16.0),
				10.0, Color(0.35, 0.72, 1.0, 1.0))


func _draw_arrowhead(from: Vector2, to: Vector2, color: Color) -> void:
	var dir: Vector2 = (to - from).normalized()
	var tip: Vector2 = to - dir * (NODE_RADIUS + 3.0)
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var sz: float = 7.0
	draw_line(tip, tip - dir * sz + perp * sz * 0.5, color, 2.0)
	draw_line(tip, tip - dir * sz - perp * sz * 0.5, color, 2.0)


func _draw_crossed_swords(center: Vector2, size: float, color: Color) -> void:
	# Dark backing circle
	draw_circle(center, size + 3.5, Color(0.05, 0.03, 0.06, 0.88))
	var h: float = size * 0.82
	var g: float = size * 0.38   # crossguard half-length
	var go: float = size * 0.18  # crossguard offset from center

	# Sword 1: top-left → bottom-right
	draw_line(center + Vector2(-h, -h), center + Vector2(h, h), color, 2.0)
	var gp1: Vector2 = center + Vector2(-go, -go)
	var gd1: Vector2 = Vector2(1.0, -1.0).normalized() * g
	draw_line(gp1 - gd1, gp1 + gd1, color, 2.0)

	# Sword 2: top-right → bottom-left
	draw_line(center + Vector2(h, -h), center + Vector2(-h, h), color, 2.0)
	var gp2: Vector2 = center + Vector2(go, -go)
	var gd2: Vector2 = Vector2(1.0, 1.0).normalized() * g
	draw_line(gp2 - gd2, gp2 + gd2, color, 2.0)


func _draw_transfer_badge(center: Vector2, size: float, color: Color) -> void:
	# Dark backing circle
	draw_circle(center, size + 3.5, Color(0.04, 0.05, 0.10, 0.88))
	var h: float = size * 0.72
	var tip: float = size * 0.32
	# Arrow pointing right (→)
	draw_line(Vector2(center.x - h, center.y), Vector2(center.x + h, center.y), color, 2.0)
	draw_line(Vector2(center.x + h, center.y),
			Vector2(center.x + h - tip, center.y - tip * 0.6), color, 2.0)
	draw_line(Vector2(center.x + h, center.y),
			Vector2(center.x + h - tip, center.y + tip * 0.6), color, 2.0)


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
