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
		var uid = unit.unit_ref.id if unit.unit_ref != null else ("leader" if unit.leader_ref != null else "?")
		var tid = target.unit_ref.id if target.unit_ref != null else ("leader" if target.leader_ref != null else "?")
		DebugLogger.log("battle_ai_action", {"unit": uid, "side": unit.side, "target": tid})
		BattleResolver.attack(state, unit, target)
	else:
		DebugLogger.log("battle_ai_no_target", {"side": unit.side})
