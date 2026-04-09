# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: BattleUnitSprite
#
# Role:
# Reserved visual wrapper for future art-layer unit rendering.
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
class_name BattleUnitSprite

var battle_unit = null

func bind_unit(unit) -> void:
	battle_unit = unit
	queue_redraw()

func _draw() -> void:
	if battle_unit == null or not battle_unit.is_alive:
		return
	draw_circle(Vector2.ZERO, 16.0, Color.WHITE)
