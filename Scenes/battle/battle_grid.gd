# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: BattleGrid
#
# Role:
# Renders the tactical grid and forwards grid clicks to BattleScene.
#
# Allowed Interactions:
# - BattleScene
#
# Forbidden Responsibilities:
# - Must not modify GameState
#
# Game Phase:
# Execution Phase (Battle Only)
# ==================================================

extends Node2D
class_name BattleGrid

const GRID_COLS: int = 19
const GRID_ROWS: int = 11
const TILE_SIZE: int = 64
const ORIGIN := Vector2(48, 56)

var _scene_ref = null
var _attacker_units: Array = []
var _defender_units: Array = []
var _selected_unit = null
var _player_side: String = "attacker"
var _move_range_cells: Array = []
var _attack_range_cells: Array = []
var _skill_range_cells: Array = []
var _skill_ally_range_cells: Array = []
var _active_unit = null
var _flash_time: float = 0.0
var _show_divider: bool = false
var _deploy_zone_cells: Array = []

func set_scene(scene_ref) -> void:
	_scene_ref = scene_ref

func set_player_side(side: String) -> void:
	_player_side = side
	queue_redraw()

func set_units(attacker_units: Array, defender_units: Array) -> void:
	_attacker_units = attacker_units
	_defender_units = defender_units
	queue_redraw()

func set_selected_unit(unit) -> void:
	_selected_unit = unit
	queue_redraw()

func set_move_range_cells(cells: Array) -> void:
	_move_range_cells = cells
	queue_redraw()

func set_attack_range_cells(cells: Array) -> void:
	_attack_range_cells = cells
	queue_redraw()

func set_skill_range_cells(cells: Array, ally: bool = false) -> void:
	if ally:
		_skill_ally_range_cells = cells
		_skill_range_cells = []
	else:
		_skill_range_cells = cells
		_skill_ally_range_cells = []
	queue_redraw()

func clear_move_range() -> void:
	_move_range_cells = []
	_attack_range_cells = []
	_skill_range_cells = []
	_skill_ally_range_cells = []
	queue_redraw()

func set_active_unit(unit) -> void:
	_active_unit = unit
	queue_redraw()

func set_divider_visible(show: bool) -> void:
	_show_divider = show
	queue_redraw()

func set_deploy_zone(cells: Array) -> void:
	_deploy_zone_cells = cells
	queue_redraw()

func _process(delta: float) -> void:
	_flash_time += delta
	if _active_unit != null:
		queue_redraw()

func _draw() -> void:
	for x in range(GRID_COLS):
		for y in range(GRID_ROWS):
			var pos := ORIGIN + Vector2(x * TILE_SIZE, y * TILE_SIZE)
			draw_rect(Rect2(pos, Vector2(TILE_SIZE, TILE_SIZE)), Color(0.12, 0.12, 0.14, 1.0), true)
			draw_rect(Rect2(pos, Vector2(TILE_SIZE, TILE_SIZE)), Color(0.4, 0.4, 0.45, 1.0), false)
			var cell := Vector2i(x, y)
			if _deploy_zone_cells.has(cell):
				draw_rect(Rect2(pos + Vector2(2,2), Vector2(TILE_SIZE-4, TILE_SIZE-4)), Color(0.2, 0.8, 0.3, 0.18), true)
				draw_rect(Rect2(pos + Vector2(2,2), Vector2(TILE_SIZE-4, TILE_SIZE-4)), Color(0.3, 1.0, 0.4, 0.4), false, 1.0)
			if _move_range_cells.has(cell):
				draw_rect(Rect2(pos + Vector2(2,2), Vector2(TILE_SIZE-4, TILE_SIZE-4)), Color(0.2, 0.6, 1.0, 0.35), true)
			if _attack_range_cells.has(cell):
				draw_rect(Rect2(pos + Vector2(2,2), Vector2(TILE_SIZE-4, TILE_SIZE-4)), Color(1.0, 0.25, 0.25, 0.28), true)
				draw_rect(Rect2(pos + Vector2(2,2), Vector2(TILE_SIZE-4, TILE_SIZE-4)), Color(1.0, 0.3, 0.3, 0.5), false, 1.5)
			if _skill_range_cells.has(cell):
				draw_rect(Rect2(pos + Vector2(2,2), Vector2(TILE_SIZE-4, TILE_SIZE-4)), Color(0.8, 0.3, 1.0, 0.32), true)
				draw_rect(Rect2(pos + Vector2(2,2), Vector2(TILE_SIZE-4, TILE_SIZE-4)), Color(0.8, 0.4, 1.0, 0.6), false, 1.5)
			if _skill_ally_range_cells.has(cell):
				draw_rect(Rect2(pos + Vector2(2,2), Vector2(TILE_SIZE-4, TILE_SIZE-4)), Color(0.2, 0.9, 0.4, 0.32), true)
				draw_rect(Rect2(pos + Vector2(2,2), Vector2(TILE_SIZE-4, TILE_SIZE-4)), Color(0.3, 1.0, 0.5, 0.6), false, 1.5)

	# Divider line between col 6 and 7 during deployment
	if _show_divider:
		var div_x: float = ORIGIN.x + 9.5 * TILE_SIZE
		var top_y: float = ORIGIN.y
		var bot_y: float = ORIGIN.y + GRID_ROWS * TILE_SIZE
		draw_line(Vector2(div_x, top_y), Vector2(div_x, bot_y), Color(1.0, 0.9, 0.2, 0.3), 10.0)
		draw_line(Vector2(div_x, top_y), Vector2(div_x, bot_y), Color(1.0, 0.85, 0.1, 0.95), 2.5)

	for unit in _attacker_units:
		var col := Color(0.2, 0.75, 1.0, 1.0) if _player_side == "attacker" else Color(1.0, 0.35, 0.35, 1.0)
		_draw_unit(unit, col)
	for unit in _defender_units:
		var col := Color(0.2, 0.75, 1.0, 1.0) if _player_side == "defender" else Color(1.0, 0.35, 0.35, 1.0)
		_draw_unit(unit, col)

func _draw_unit(unit, color: Color) -> void:
	if unit == null or not unit.is_alive:
		return
	var center := _cell_center(unit.grid_pos)
	draw_circle(center, 18.0, color)
	if unit == _selected_unit:
		draw_circle(center, 24.0, Color(1, 1, 0.3, 1.0), false, 3.0)
	if unit == _active_unit:
		var pulse: float = 0.5 + 0.5 * sin(_flash_time * 6.0)
		draw_circle(center, 28.0 + pulse * 4.0, Color(1.0, 1.0, 1.0, 0.6 * pulse), false, 2.5)
	if ThemeDB.fallback_font != null:
		draw_string(ThemeDB.fallback_font, center + Vector2(-16, 5), str(unit.battle_hp), HORIZONTAL_ALIGNMENT_LEFT, -1, 12)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _screen_to_cell(event.position)
		if cell.x >= 0 and cell.y >= 0 and cell.x < GRID_COLS and cell.y < GRID_ROWS:
			if _scene_ref != null:
				_scene_ref.on_grid_clicked(cell)

func _screen_to_cell(screen_pos: Vector2) -> Vector2i:
	var local := screen_pos - ORIGIN
	return Vector2i(floori(local.x / TILE_SIZE), floori(local.y / TILE_SIZE))

func _cell_center(cell: Vector2i) -> Vector2:
	return ORIGIN + Vector2(cell.x * TILE_SIZE + TILE_SIZE * 0.5, cell.y * TILE_SIZE + TILE_SIZE * 0.5)


# --------------------------------------------------
# Line of Sight (Bresenham's algorithm)
# Only relevant for ranged units (attack_range > 1)
# Returns true if there is a clear path from 'from' to 'to'
# Blocked by any alive, non-captured unit on intermediate tiles
# --------------------------------------------------
func has_line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	var cells := _bresenham_cells(from, to)
	# Build occupied set from all alive non-captured units
	var occupied: Dictionary = {}
	for u in _attacker_units:
		if u != null and bool(u.is_alive) and not ("is_captured" in u and bool(u.is_captured)):
			occupied[u.grid_pos] = true
	for u in _defender_units:
		if u != null and bool(u.is_alive) and not ("is_captured" in u and bool(u.is_captured)):
			occupied[u.grid_pos] = true
	# Check intermediate tiles only (not source or destination)
	for i in range(1, cells.size() - 1):
		if occupied.has(cells[i]):
			return false
	return true


func _bresenham_cells(from: Vector2i, to: Vector2i) -> Array:
	var cells: Array = []
	var x0: int = from.x
	var y0: int = from.y
	var x1: int = to.x
	var y1: int = to.y
	var dx: int = abs(x1 - x0)
	var dy: int = abs(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx - dy
	while true:
		cells.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy
	return cells
