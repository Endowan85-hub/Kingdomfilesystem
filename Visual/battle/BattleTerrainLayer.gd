# ==================================================
# BattleTerrainLayer
# ==================================================
# Phase 3 — draws biome-tinted terrain tiles behind the
# existing BattleGrid (which sits in CanvasLayer 10).
# This layer sits at layer 9 so terrain appears as a
# textured floor beneath unit highlights and circles.
#
# Reads setup dict for biome only — never mutates state.
# ==================================================
extends CanvasLayer
class_name BattleTerrainLayer

const GRID_COLS: int = 19
const GRID_ROWS: int = 11
const TILE_SIZE: int = 64
const ORIGIN := Vector2(48, 56)

# Biome → base floor color
const BIOME_COLORS: Dictionary = {
	"plains":    Color(0.18, 0.22, 0.12),
	"forest":    Color(0.10, 0.18, 0.10),
	"mountain":  Color(0.22, 0.20, 0.18),
	"swamp":     Color(0.12, 0.16, 0.12),
	"desert":    Color(0.26, 0.22, 0.12),
	"tundra":    Color(0.20, 0.22, 0.26),
	"coastal":   Color(0.12, 0.18, 0.26),
	"volcanic":  Color(0.22, 0.10, 0.08),
	"marsh":     Color(0.12, 0.18, 0.14),
	"steppe":    Color(0.22, 0.20, 0.12),
}

# Biome → accent color for variation patches
const BIOME_ACCENTS: Dictionary = {
	"plains":    Color(0.22, 0.30, 0.14),
	"forest":    Color(0.08, 0.22, 0.10),
	"mountain":  Color(0.28, 0.26, 0.24),
	"swamp":     Color(0.14, 0.22, 0.14),
	"desert":    Color(0.32, 0.28, 0.14),
	"tundra":    Color(0.26, 0.28, 0.34),
	"coastal":   Color(0.16, 0.24, 0.34),
	"volcanic":  Color(0.28, 0.12, 0.08),
	"marsh":     Color(0.14, 0.22, 0.18),
	"steppe":    Color(0.28, 0.26, 0.14),
}

var _biome: String = "plains"
var _draw_node: _TerrainDraw = null


func init_terrain(biome: String) -> void:
	_biome = biome.to_lower()
	if not BIOME_COLORS.has(_biome):
		_biome = "plains"
	if _draw_node != null:
		_draw_node.biome = _biome
		_draw_node.queue_redraw()


func _ready() -> void:
	layer = 9
	_draw_node = _TerrainDraw.new()
	_draw_node.biome = _biome
	add_child(_draw_node)


# Inner class handles _draw so we have a proper CanvasItem
class _TerrainDraw extends Node2D:
	var biome: String = "plains"

	func _draw() -> void:
		var base_col: Color = BattleTerrainLayer.BIOME_COLORS.get(biome, Color(0.14, 0.14, 0.16))
		var accent_col: Color = BattleTerrainLayer.BIOME_ACCENTS.get(biome, Color(0.18, 0.18, 0.20))

		# Draw a subtle grid-aligned background
		# We replace the BattleScene's solid dark background with a biome-tinted one
		# (BattleScene's own background ColorRect is still behind us at layer 10,
		# but this draws the floor art at layer 9 — if background is removed later this is ready)
		for x in range(BattleTerrainLayer.GRID_COLS):
			for y in range(BattleTerrainLayer.GRID_ROWS):
				var pos: Vector2 = BattleTerrainLayer.ORIGIN + Vector2(
					x * BattleTerrainLayer.TILE_SIZE,
					y * BattleTerrainLayer.TILE_SIZE
				)
				var tile_rect := Rect2(pos, Vector2(
					BattleTerrainLayer.TILE_SIZE,
					BattleTerrainLayer.TILE_SIZE
				))

				# Checkerboard-style alternating accent to break up the grid
				var is_accent: bool = (x + y) % 3 == 0
				draw_rect(tile_rect, accent_col if is_accent else base_col, true)

				# Thin border (slightly lighter than the tile)
				draw_rect(tile_rect, base_col.lightened(0.15), false, 0.5)

		# Left territory stripe (cols 0-8) — subtle attacker tint
		var left_rect := Rect2(
			BattleTerrainLayer.ORIGIN,
			Vector2(9 * BattleTerrainLayer.TILE_SIZE, BattleTerrainLayer.GRID_ROWS * BattleTerrainLayer.TILE_SIZE)
		)
		draw_rect(left_rect, Color(0.15, 0.40, 0.80, 0.06), true)

		# Right territory stripe (cols 10-18) — subtle defender tint
		var right_rect := Rect2(
			BattleTerrainLayer.ORIGIN + Vector2(10 * BattleTerrainLayer.TILE_SIZE, 0),
			Vector2(9 * BattleTerrainLayer.TILE_SIZE, BattleTerrainLayer.GRID_ROWS * BattleTerrainLayer.TILE_SIZE)
		)
		draw_rect(right_rect, Color(0.80, 0.20, 0.20, 0.06), true)
