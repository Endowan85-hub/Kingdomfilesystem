# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: BattleAI
#
# Role:
# Controls AI decisions in tactical battle.
#
# Allowed Interactions:
# - BattleState
#
# Forbidden Responsibilities:
# - Must not modify GameState
#
# Game Phase:
# Execution Phase (Battle Only)
# ==================================================

class_name BattleAI

static func take_turn(state, unit):
	if not unit.is_alive:
		return

	var enemies = state.defender_units if unit.side == "attacker" else state.attacker_units

	var target = null
	for e in enemies:
		if e.is_alive:
			target = e
			break

	if target:
		BattleResolver.attack(state, unit, target)
