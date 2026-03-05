extends Node2D
class_name MapDebugView

# =====================================================
# CONTRACT NOTES (do not change without updating all callers)
# - Planning Phase: UI queues orders into OrderBook ONLY (no state mutation).
# - Execution Phase: TurnManager.execute_month resolves queued orders via resolvers.
# - Hard rules enforced at UI layer:
#   * You can only issue orders from HUMAN-owned provinces.
#   * ATTACK targets must be non-HUMAN (enemy or neutral).
#   * TRANSFER targets must be HUMAN-owned.
# - Do NOT change public ui_* function signatures; MapDebugUI calls them via call().
# =====================================================


signal debug_state_changed

@export var settings: MapSettings

var map_data: MapData
var game_state: GameState
var turn_manager: TurnManager

const HUMAN_ID := 0
const AI_ID := 1

var selected_province_id: int = -1
var hover_province_id: int = -1

enum TargetPickMode { NONE, ATTACK, TRANSFER }
var pick_mode: int = TargetPickMode.NONE
var _pick_source_id: int = -1

# Camera
var _zoom: float = 1.0
var _origin: Vector2 = Vector2.ZERO
var _is_panning: bool = false
var _pan_last: Vector2 = Vector2.ZERO

# Voronoi
var _voronoi_cells: Dictionary = {} # int -> Array[Vector2]

# Labels
var _label_font: Font

const NODE_RADIUS: float = 8.0
const PICK_RADIUS: float = 14.0


func _ready() -> void:
	_label_font = ThemeDB.fallback_font

	if settings == null:
		settings = load("res://data/default_map_settings.tres")

	var generator := MapGenerator.new()
	map_data = generator.generate_map(settings)

	game_state = GameState.new()
	game_state.init_with_map(map_data)

	turn_manager = TurnManager.new()

	DebugLogger.log("MapDebugView ready | map provinces=%d routes=%d" % [map_data.provinces.size(), map_data.routes.size()])

	_rebuild_voronoi()
	_frame_map()

	# Debug UI
	var ui_scene: PackedScene = load("res://Scenes/debug/map_debug_ui.tscn")
	if ui_scene:
		var ui = ui_scene.instantiate()
		add_child(ui)

	queue_redraw()


# =====================================================
# INPUT
# =====================================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton

		# Middle mouse pan
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_is_panning = true
				_pan_last = mb.position
			else:
				_is_panning = false

		# Wheel zoom (do NOT rely on pressed flag)
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mb.position, 1.1)

		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mb.position, 0.9)

		# Left click
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_on_left_click(mb.position)

	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _is_panning:
			var delta: Vector2 = mm.position - _pan_last
			_pan_last = mm.position
			_origin += delta
			queue_redraw()
		else:
			hover_province_id = _pick_province_id(mm.position)
			queue_redraw()


# =====================================================
# CAMERA
# =====================================================

func _to_screen(world: Vector2) -> Vector2:
	return world * _zoom + _origin


func _to_world(screen: Vector2) -> Vector2:
	return (screen - _origin) / _zoom


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var world: Vector2 = _to_world(screen_pos)
	_zoom = clamp(_zoom * factor, 0.35, 2.5)
	_origin = screen_pos - world * _zoom
	queue_redraw()


func _frame_map() -> void:
	var rect: Rect2 = _compute_bounds()
	var vp: Vector2 = get_viewport_rect().size

	var sx: float = vp.x / rect.size.x
	var sy: float = vp.y / rect.size.y

	_zoom = min(sx, sy) * 0.85
	var center: Vector2 = rect.position + rect.size * 0.5
	_origin = vp * 0.5 - center * _zoom


func _compute_bounds() -> Rect2:
	var minx: float = 1.0e18
	var miny: float = 1.0e18
	var maxx: float = -1.0e18
	var maxy: float = -1.0e18

	for item in map_data.provinces:
		var p: ProvinceData = item as ProvinceData
		minx = minf(minx, p.center.x)
		miny = minf(miny, p.center.y)
		maxx = maxf(maxx, p.center.x)
		maxy = maxf(maxy, p.center.y)

	if maxx < minx or maxy < miny:
		return Rect2(Vector2.ZERO, Vector2.ONE)

	return Rect2(Vector2(minx, miny), Vector2(maxx - minx, maxy - miny))


# =====================================================
# SELECTION + ORDER PICKING
# =====================================================

func _on_left_click(screen_pos: Vector2) -> void:
	var pid: int = _pick_province_id(screen_pos)
	if pid == -1:
		return

	# If we are in a targeting mode, interpret this click as a target selection.
	if pick_mode != TargetPickMode.NONE and _pick_source_id != -1:
		if pid == _pick_source_id:
			# Clicking the source again just re-selects it.
			selected_province_id = pid
			queue_redraw()
			debug_state_changed.emit()
			return

		# Queue the appropriate order (planning phase only)
		if game_state == null or game_state.order_book == null:
			return

		# Hard rule: validate target by ownership before queuing
		var src_p: ProvinceData = map_data.provinces[_pick_source_id] as ProvinceData
		var tgt_p: ProvinceData = map_data.provinces[pid] as ProvinceData
		# Source must remain HUMAN-owned
		if int(src_p.owner_id) != HUMAN_ID:
			DebugLogger.log('Order blocked | source not HUMAN | P%d owner=%d' % [_pick_source_id, int(src_p.owner_id)])
			return
		# Attack cannot target HUMAN; Transfer must target HUMAN
		if pick_mode == TargetPickMode.ATTACK and int(tgt_p.owner_id) == HUMAN_ID:
			DebugLogger.log('ATTACK blocked | target is HUMAN | P%d -> P%d' % [_pick_source_id, pid])
			return
		if pick_mode == TargetPickMode.TRANSFER and int(tgt_p.owner_id) != HUMAN_ID:
			DebugLogger.log('TRANSFER blocked | target not HUMAN | P%d -> P%d owner=%d' % [_pick_source_id, pid, int(tgt_p.owner_id)])
			return

		match pick_mode:
			TargetPickMode.ATTACK:
				_queue_attack(_pick_source_id, pid)
			TargetPickMode.TRANSFER:
				_queue_transfer(_pick_source_id, pid)

		# Exit mode after queuing
		pick_mode = TargetPickMode.NONE
		_pick_source_id = -1
		selected_province_id = pid
		DebugLogger.log("Click target P%d | mode resolved" % pid)
		queue_redraw()
		debug_state_changed.emit()
		return

	# Normal selection
	selected_province_id = pid
	DebugLogger.log("Select P%d" % pid)
	queue_redraw()
	debug_state_changed.emit()


func _pick_province_id(screen_pos: Vector2) -> int:
	var world: Vector2 = _to_world(screen_pos)
	var best: int = -1
	var best_d: float = 999999.0

	for item in map_data.provinces:
		var p: ProvinceData = item as ProvinceData
		var d: float = world.distance_to(p.center)
		if d < PICK_RADIUS and d < best_d:
			best = int(p.id)
			best_d = d

	return best


func _queue_attack(from_id: int, to_id: int) -> void:
	var pa: ProvinceData = map_data.provinces[from_id] as ProvinceData
	# Commit half the garrison (debug default); resolvers enforce validity.
	var commit: int = clampi(int(pa.garrison) / 2, 1, int(pa.garrison))
	game_state.order_book.queue_attack(HUMAN_ID, from_id, to_id, commit)
	DebugLogger.log("Queue ATTACK | P%d -> P%d | commit=%d" % [from_id, to_id, commit])


func _queue_transfer(from_id: int, to_id: int) -> void:
	var pa: ProvinceData = map_data.provinces[from_id] as ProvinceData
	var sent: int = clampi(int(pa.garrison) / 2, 1, int(pa.garrison))
	var arrive: int = sent
	game_state.order_book.queue_transfer(HUMAN_ID, from_id, to_id, sent, 0, arrive)
	DebugLogger.log("Queue TRANSFER | P%d -> P%d | sent=%d" % [from_id, to_id, sent])


# =====================================================
# UI HELPERS (MapDebugUI reads these via call())
# =====================================================

func ui_has_selection() -> bool:
	return selected_province_id != -1


func ui_get_selected_text() -> String:
	if selected_province_id == -1:
		return "Selected: (none)"

	var p: ProvinceData = map_data.provinces[selected_province_id] as ProvinceData
	return "Selected: Province %d (ID %d) | Owner:%d | Garr:%d/%d | Fort:%d" % [
		int(p.id),
		int(p.id),
		int(p.owner_id),
		int(p.garrison),
		int(p.max_garrison),
		int(p.fort_level)
	]


func ui_get_mode_text() -> String:
	match pick_mode:
		TargetPickMode.ATTACK:
			return "Attack"
		TargetPickMode.TRANSFER:
			return "Transfer"
	return "None"


func ui_get_orders_text() -> String:
	if game_state == null or game_state.order_book == null:
		return ""

	var ob: OrderBook = game_state.order_book
	var lines: Array[String] = []

	lines.append("Your Upgrades")
	var ups: Array = ob.get_upgrades(HUMAN_ID)
	if ups.is_empty():
		lines.append("(none)")
	else:
		for o in ups:
			lines.append("Upgrade P%d (cost %d)" % [int(o["province_id"]), int(o["cost"])])

	lines.append("")
	lines.append("Your Transfers")
	var trs: Array = ob.get_transfers(HUMAN_ID)
	if trs.is_empty():
		lines.append("(none)")
	else:
		for o in trs:
			lines.append("Transfer %d: P%d -> P%d (arrive %d)" % [
				int(o["sent"]),
				int(o["from"]),
				int(o["to"]),
				int(o["arrive"])
			])

	lines.append("")
	lines.append("Your Attacks")
	var atks: Array = ob.get_attacks(HUMAN_ID)
	if atks.is_empty():
		lines.append("(none)")
	else:
		for o in atks:
			lines.append("Attack %d: P%d -> P%d" % [
				int(o["commit"]),
				int(o["from"]),
				int(o["to"])
			])

	return "\n".join(lines)


func ui_start_attack() -> void:
	if selected_province_id == -1:
		return
	# Hard rule: only HUMAN-owned provinces can issue orders
	var src: ProvinceData = map_data.provinces[selected_province_id] as ProvinceData
	if int(src.owner_id) != HUMAN_ID:
		DebugLogger.log('Mode ATTACK blocked | source not HUMAN | P%d owner=%d' % [selected_province_id, int(src.owner_id)])
		return

	_pick_source_id = selected_province_id
	pick_mode = TargetPickMode.ATTACK
	DebugLogger.log("Mode ATTACK | source=P%d" % _pick_source_id)
	debug_state_changed.emit()


func ui_start_transfer() -> void:
	if selected_province_id == -1:
		return
	# Hard rule: only HUMAN-owned provinces can issue orders
	var src: ProvinceData = map_data.provinces[selected_province_id] as ProvinceData
	if int(src.owner_id) != HUMAN_ID:
		DebugLogger.log('Mode TRANSFER blocked | source not HUMAN | P%d owner=%d' % [selected_province_id, int(src.owner_id)])
		return

	_pick_source_id = selected_province_id
	pick_mode = TargetPickMode.TRANSFER
	DebugLogger.log("Mode TRANSFER | source=P%d" % _pick_source_id)
	debug_state_changed.emit()


func ui_queue_upgrade() -> void:
	if selected_province_id == -1:
		return
	if game_state == null or game_state.order_book == null:
		return

	var p: ProvinceData = map_data.provinces[selected_province_id] as ProvinceData
	if int(p.owner_id) != HUMAN_ID:
		return

	var f: FactionData = _find_faction(HUMAN_ID)
	if f == null:
		return

	var cost: int = TurnManager.FORT_BASE_COST * maxi(1, int(p.fort_level))
	if int(f.gold) < cost:
		DebugLogger.log("Queue UPGRADE blocked | not enough gold | need=%d have=%d" % [cost, int(f.gold)])
		return

	game_state.order_book.queue_upgrade(HUMAN_ID, int(p.id), cost)
	DebugLogger.log("Queue UPGRADE | P%d | cost=%d" % [int(p.id), cost])
	debug_state_changed.emit()


func ui_cancel_mode() -> void:
	pick_mode = TargetPickMode.NONE
	_pick_source_id = -1
	DebugLogger.log("Mode CANCEL")
	debug_state_changed.emit()


func ui_clear_orders() -> void:
	if game_state == null or game_state.order_book == null:
		return
	game_state.order_book.clear_orders_for_faction(HUMAN_ID)
	DebugLogger.log("Clear orders | faction=%d" % HUMAN_ID)
	debug_state_changed.emit()
	queue_redraw()


func ui_execute_month() -> void:
	if turn_manager == null or game_state == null:
		return

	DebugLogger.log("=== EXECUTE MONTH start | month=%d ===" % int(game_state.month_index))
	turn_manager.execute_month(game_state, HUMAN_ID, AI_ID, true)
	DebugLogger.log("=== EXECUTE MONTH end | month=%d ===" % int(game_state.month_index))

	_rebuild_voronoi()
	debug_state_changed.emit()
	queue_redraw()


func _find_faction(fid: int) -> FactionData:
	for item in map_data.factions:
		var f: FactionData = item as FactionData
		if int(f.id) == fid:
			return f
	return null


# =====================================================
# VORONOI
# =====================================================

func _rebuild_voronoi() -> void:
	_voronoi_cells.clear()

	var bounds: Rect2 = _compute_bounds()

	for item_a in map_data.provinces:
		var a: ProvinceData = item_a as ProvinceData

		var poly: Array = [
			bounds.position,
			bounds.position + Vector2(bounds.size.x, 0.0),
			bounds.position + bounds.size,
			bounds.position + Vector2(0.0, bounds.size.y)
		]

		for item_b in map_data.provinces:
			var b: ProvinceData = item_b as ProvinceData
			if a == b:
				continue

			poly = _clip_cell(poly, a.center, b.center)
			if poly.size() < 3:
				break

		_voronoi_cells[int(a.id)] = poly


func _clip_cell(poly: Array, a: Vector2, b: Vector2) -> Array:
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


# =====================================================
# DRAW
# =====================================================

func _draw() -> void:
	if map_data == null:
		return

	_draw_cells()
	_draw_routes()
	_draw_orders()
	_draw_nodes()
	_draw_labels()


func _draw_cells() -> void:
	for item in map_data.provinces:
		var p: ProvinceData = item as ProvinceData
		if !_voronoi_cells.has(int(p.id)):
			continue

		var poly_pts: PackedVector2Array = PackedVector2Array()
		for v in _voronoi_cells[int(p.id)]:
			poly_pts.append(_to_screen(v))

		var c: Color = _owner_color(int(p.owner_id))
		c.a = 0.20
		draw_colored_polygon(poly_pts, c)

		draw_polyline(poly_pts, Color(1, 1, 1, 0.25), 1.0, true)


func _draw_routes() -> void:
	for r in map_data.routes:
		var a: ProvinceData = map_data.provinces[int(r.a)] as ProvinceData
		var b: ProvinceData = map_data.provinces[int(r.b)] as ProvinceData

		draw_line(_to_screen(a.center), _to_screen(b.center), Color(1, 1, 1, 0.4), 1.0)


func _draw_orders() -> void:
	if game_state == null or game_state.order_book == null:
		return

	var ob: OrderBook = game_state.order_book

	# Draw transfers (green)
	for o in ob.get_transfers(HUMAN_ID):
		var a: int = int(o["from"])
		var b: int = int(o["to"])
		var pa: ProvinceData = map_data.provinces[a] as ProvinceData
		var pb: ProvinceData = map_data.provinces[b] as ProvinceData
		draw_line(_to_screen(pa.center), _to_screen(pb.center), Color(0.2, 1.0, 0.2, 0.9), 3.0)

	# Draw attacks (red)
	for o in ob.get_attacks(HUMAN_ID):
		var a2: int = int(o["from"])
		var b2: int = int(o["to"])
		var pa2: ProvinceData = map_data.provinces[a2] as ProvinceData
		var pb2: ProvinceData = map_data.provinces[b2] as ProvinceData
		draw_line(_to_screen(pa2.center), _to_screen(pb2.center), Color(1.0, 0.2, 0.2, 0.9), 3.0)


func _draw_nodes() -> void:
	for item in map_data.provinces:
		var p: ProvinceData = item as ProvinceData
		var pos: Vector2 = _to_screen(p.center)

		draw_circle(pos, NODE_RADIUS, _owner_color(int(p.owner_id)))

		if int(p.id) == selected_province_id:
			draw_arc(pos, 14.0, 0.0, TAU, 48, Color.WHITE, 2.0)

		if int(p.id) == hover_province_id and hover_province_id != selected_province_id:
			draw_arc(pos, 10.5, 0.0, TAU, 36, Color(1.0, 0.6, 0.2), 2.0)


func _draw_labels() -> void:
	for item in map_data.provinces:
		var p: ProvinceData = item as ProvinceData
		var pos: Vector2 = _to_screen(p.center) + Vector2(10, -10)

		var txt: String = "Province %d\nG%d F%d I%d" % [
			int(p.id),
			int(p.garrison),
			int(p.fort_level),
			int(p.income)
		]

		draw_multiline_string(
			_label_font,
			pos,
			txt,
			HORIZONTAL_ALIGNMENT_LEFT,
			220,
			14
		)


# =====================================================
# COLORS
# =====================================================

func _owner_color(owner: int) -> Color:
	if owner == HUMAN_ID:
		return Color(0.9, 0.2, 0.2)
	if owner == AI_ID:
		return Color(0.2, 0.4, 0.95)
	return Color(0.2, 0.8, 0.2)
