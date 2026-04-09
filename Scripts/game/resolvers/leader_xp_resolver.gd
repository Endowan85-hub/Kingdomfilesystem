# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: LeaderXPResolver
#
# Role:
# Applies queued leader XP rewards, resolves level-ups, and updates leader
# stats as part of the strategic execution pipeline.
#
# Allowed Interactions:
# - GameState
# - LeaderData
# - DebugLogger (logging only)
#
# Forbidden Responsibilities:
# - Must not interact with UI
# - Must not create orders
# - Must not orchestrate the turn
#
# Game Phase:
# Execution Phase
#
# Notes:
# - XP events must be queued by other execution systems before this resolver.
# - This resolver may only mutate leader simulation data on GameState.
# ==================================================

class_name LeaderXPResolver
extends RefCounted

const LEVEL_UP_STAT_ORDER: Array[String] = ["leadership", "attack", "defense"]
const LEVEL_UP_XP_STEP: int = 15


func resolve(state: GameState) -> void:
	if state == null:
		return

	var events: Array = state.pending_leader_xp_events
	var log: DebugLogger = state.logger
	var applied: int = 0
	var leveled_up: int = 0
	var details: Array = []

	for item in events:
		if not item is Dictionary:
			continue

		var evt: Dictionary = item
		var leader_id: int = int(evt.get("leader_id", -1))
		var amount: int = max(0, int(evt.get("amount", 0)))
		if leader_id < 0 or amount <= 0:
			continue

		var leader: LeaderData = state.get_leader(leader_id)
		if leader == null:
			continue

		var before_level: int = int(leader.level)
		var before_xp: int = int(leader.xp)
		leader.xp += amount
		applied += 1

		var gained_levels: int = 0
		while int(leader.xp) >= int(leader.xp_to_next_level):
			leader.xp -= int(leader.xp_to_next_level)
			leader.level += 1
			leader.xp_to_next_level += LEVEL_UP_XP_STEP
			_apply_level_bonus(leader)
			gained_levels += 1

		if gained_levels > 0:
			leveled_up += 1

		details.append({
			"leader": leader.display_name,
			"leader_id": leader_id,
			"source": str(evt.get("source", "unknown")),
			"xp_gain": amount,
			"xp_before": before_xp,
			"xp_after": int(leader.xp),
			"level_before": before_level,
			"level_after": int(leader.level),
			"gained_levels": gained_levels
		})

	events.clear()

	if log != null:
		log.event("leader_xp_result", {
			"applied": applied,
			"leveled_up": leveled_up,
			"details": details
		})


func _apply_level_bonus(leader: LeaderData) -> void:
	var stat_name: String = LEVEL_UP_STAT_ORDER[(int(leader.level) - 2) % LEVEL_UP_STAT_ORDER.size()]
	match stat_name:
		"attack":
			leader.attack += 1
		"defense":
			leader.defense += 1
		_:
			leader.leadership += 1
