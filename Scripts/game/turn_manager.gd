class_name TurnManager
extends RefCounted

# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: TurnManager
#
# Role:
# Executes the monthly turn pipeline by invoking resolvers in order.
#
# Allowed Interactions:
# - GameState
# - OrderBook
# - Resolvers
# - AIPlanner
#
# Forbidden Responsibilities:
# - Creating orders
# - Modifying UI
#
# Game Phase:
# Execution Phase
#
# Notes:
# - Monthly execution may trigger staged reserve-general releases before AI planning for that month.
# ==================================================

# -----------------------------
# Balance / shared constants
# -----------------------------
const FORT_BASE_COST: int = 400
const MISSION_DEFAULT_DURATION: int = 1
const FORT_DEF_PER_LEVEL: int = 25
const CHOKE_DEF_BONUS: int = 20
const ATTACK_BASE_LOSS_MIN: int = 10
const ATTACK_BASE_LOSS_MAX: int = 80
const DEF_LOSS_MIN: int = 5
const DEF_LOSS_MAX: int = 60
const MIN_CAPTURE_GARRISON: int = 40
const FORT_ATTACK_BONUS_PER_LEVEL: int = 10
const FORT_DEF_MULT: int = 10

# -----------------------------
# Resolver script references
# -----------------------------
const AIPlannerScript = preload("res://Scripts/game/ai_planner.gd")
const UpgradeResolverScript = preload("res://Scripts/game/resolvers/upgrade_resolver.gd")
const TransferResolverScript = preload("res://Scripts/game/resolvers/transfer_resolver.gd")
const CombatResolverScript = preload("res://Scripts/game/resolvers/combat_resolver.gd")
const MissionResolverScript = preload("res://Scripts/game/resolvers/mission_resolver.gd")
const LeaderXPResolverScript = preload("res://Scripts/game/resolvers/leader_xp_resolver.gd")
const EconomyResolverScript = preload("res://Scripts/game/resolvers/economy_resolver.gd")
const ReinforcementResolverScript = preload("res://Scripts/game/resolvers/reinforcement_resolver.gd")
const OwnershipResolverScript = preload("res://Scripts/game/resolvers/ownership_resolver.gd")
const BattleManager = preload("res://Scripts/game/battle/battle_manager.gd")
const CampaignEventResolverScript = preload("res://Scripts/game/resolvers/campaign_event_resolver.gd")

# -----------------------------
# Modules
# -----------------------------
var ai_planner = AIPlannerScript.new()
var upgrade_resolver = UpgradeResolverScript.new()
var transfer_resolver = TransferResolverScript.new()
var combat_resolver = CombatResolverScript.new()
var mission_resolver = MissionResolverScript.new()
var leader_xp_resolver = LeaderXPResolverScript.new()
var economy_resolver = EconomyResolverScript.new()
var reinforcement_resolver = ReinforcementResolverScript.new()
var ownership_resolver = OwnershipResolverScript.new()
var campaign_event_resolver = CampaignEventResolverScript.new()


func execute_month(state: GameState, human_id: int, ai_id: int, run_ai: bool) -> void:
	await execute_month_with_summary(state, human_id, ai_id, run_ai)


func execute_month_with_summary(state: GameState, human_id: int, ai_id: int, run_ai: bool) -> Dictionary:  # async when player battle queued
	if state == null or state.map_data == null:
		return {}

	var owner_before: Dictionary = {}
	for item_before in state.map_data.provinces:
		var province_before: ProvinceData = item_before as ProvinceData
		owner_before[int(province_before.id)] = int(province_before.owner_id)

	DebugLogger.log("event:execute_month", {"month": state.month_index + 1})
	state.month_index += 1
	state.release_generals_for_month(state.month_index)

	if run_ai:
		# Plan for ALL non-human factions, not just one hardcoded AI id
		for item in state.map_data.factions:
			var f: FactionData = item as FactionData
			if f == null:
				continue
			var fid: int = int(f.id)
			if fid == human_id:
				continue
			if bool(f.is_eliminated):
				continue
			if (f.provinces as Array).is_empty():
				continue
			ai_planner.plan_month(state, fid)

	var summary: Dictionary = _snapshot_order_summary(state)
	_update_faction_war_metas(state, summary)
	DebugLogger.log("ai_month_summary_pre", summary)

	DebugLogger.log("stage_start:upgrade")
	upgrade_resolver.resolve(state)
	DebugLogger.log("stage_end:upgrade")

	DebugLogger.log("stage_start:transfer")
	transfer_resolver.resolve(state)
	DebugLogger.log("stage_end:transfer")

	DebugLogger.log("stage_start:combat")
	combat_resolver.resolve(state)
	if BattleManager.has_pending_battles():
		BattleManager.process_queue()
		if int(state.human_faction_id) >= 0:
			await BattleManager._get_emitter().battles_resolved
	DebugLogger.log("stage_end:combat")

	DebugLogger.log("stage_start:missions")
	mission_resolver.resolve(state)
	if BattleManager.has_pending_battles():
		BattleManager.process_queue()
	DebugLogger.log("stage_end:missions")

	DebugLogger.log("stage_start:leader_xp")
	leader_xp_resolver.resolve(state)
	DebugLogger.log("stage_end:leader_xp")

	DebugLogger.log("stage_start:economy")
	economy_resolver.resolve(state)
	DebugLogger.log("stage_end:economy")

	DebugLogger.log("stage_start:reinforcement")
	reinforcement_resolver.resolve(state)
	DebugLogger.log("stage_end:reinforcement")

	DebugLogger.log("stage_start:ownership")
	ownership_resolver.recount_faction_provinces(state)
	DebugLogger.log("stage_end:ownership")

	DebugLogger.log("stage_start:campaign_events")
	campaign_event_resolver.resolve(state)
	DebugLogger.log("stage_end:campaign_events")

	var captures: Array = []
	for item_after in state.map_data.provinces:
		var province_after: ProvinceData = item_after as ProvinceData
		var pid: int = int(province_after.id)
		var prev_owner: int = int(owner_before.get(pid, -1))
		var new_owner: int = int(province_after.owner_id)
		if prev_owner != new_owner:
			captures.append({"province_id": pid, "from": prev_owner, "to": new_owner})
	summary["captures"] = captures
	summary["capture_count"] = captures.size()
	summary["alive_factions"] = _count_alive_factions(state)
	summary["month"] = state.month_index
	DebugLogger.log("ai_month_summary_post", summary)

	var faction_ids: Array[int] = []
	for item in state.map_data.factions:
		var faction: FactionData = item as FactionData
		faction_ids.append(int(faction.id))
	state.order_book.clear_all(faction_ids)
	return summary


func _snapshot_order_summary(state: GameState) -> Dictionary:
	var summary: Dictionary = {
		"upgrade_orders": 0,
		"transfer_orders": 0,
		"attack_orders": 0,
		"attack_orders_vs_neutral": 0,
		"attack_orders_vs_faction": 0,
		"mission_orders": 0,
		"promotion_orders": 0,
		"faction_attack_orders": {},
		"faction_attack_orders_vs_neutral": {},
		"faction_attack_orders_vs_faction": {},
	}
	if state == null or state.map_data == null or state.order_book == null:
		return summary

	for item in state.map_data.factions:
		var faction: FactionData = item as FactionData
		if faction == null:
			continue
		var fid: int = int(faction.id)
		var upgrades: Array = state.order_book.get_upgrades(fid)
		var transfers: Array = state.order_book.get_transfers(fid)
		var attacks: Array = state.order_book.get_attacks(fid)
		var missions: Array = state.order_book.get_missions(fid)
		var neutral_attacks: int = 0
		var faction_attacks: int = 0
		for attack_value in attacks:
			var attack: Dictionary = attack_value as Dictionary
			var target_id: int = int(attack.get("to", -1))
			if target_id < 0 or target_id >= state.map_data.provinces.size():
				continue
			var target: ProvinceData = state.map_data.provinces[target_id] as ProvinceData
			if target == null:
				continue
			if int(target.owner_id) < 0:
				neutral_attacks += 1
			elif int(target.owner_id) != fid:
				faction_attacks += 1
		var promotions: Array = state.order_book.get_promotions(fid)
		summary["upgrade_orders"] = int(summary["upgrade_orders"]) + upgrades.size()
		summary["transfer_orders"] = int(summary["transfer_orders"]) + transfers.size()
		summary["attack_orders"] = int(summary["attack_orders"]) + attacks.size()
		summary["attack_orders_vs_neutral"] = int(summary["attack_orders_vs_neutral"]) + neutral_attacks
		summary["attack_orders_vs_faction"] = int(summary["attack_orders_vs_faction"]) + faction_attacks
		summary["mission_orders"] = int(summary["mission_orders"]) + missions.size()
		summary["promotion_orders"] = int(summary["promotion_orders"]) + promotions.size()
		(summary["faction_attack_orders"] as Dictionary)[str(fid)] = attacks.size()
		(summary["faction_attack_orders_vs_neutral"] as Dictionary)[str(fid)] = neutral_attacks
		(summary["faction_attack_orders_vs_faction"] as Dictionary)[str(fid)] = faction_attacks
	return summary


func _count_alive_factions(state: GameState) -> int:
	if state == null or state.map_data == null:
		return 0
	var alive: int = 0
	for item in state.map_data.factions:
		var faction: FactionData = item as FactionData
		if faction == null:
			continue
		if not bool(faction.is_eliminated):
			alive += 1
	return alive


func _update_faction_war_metas(state: GameState, summary: Dictionary) -> void:
	if state == null or state.map_data == null:
		return
	var attack_orders: Dictionary = summary.get("faction_attack_orders", {}) as Dictionary
	var neutral_orders: Dictionary = summary.get("faction_attack_orders_vs_neutral", {}) as Dictionary
	var faction_orders: Dictionary = summary.get("faction_attack_orders_vs_faction", {}) as Dictionary
	for item in state.map_data.factions:
		var faction: FactionData = item as FactionData
		if faction == null:
			continue
		var fid_key: String = str(int(faction.id))
		var any_attack: bool = int(attack_orders.get(fid_key, 0)) > 0
		var any_faction_war: bool = int(faction_orders.get(fid_key, 0)) > 0
		var any_neutral_war: bool = int(neutral_orders.get(fid_key, 0)) > 0
		var months_since_offense: int = int(faction.get_meta("months_since_offense", 0)) if faction.has_meta("months_since_offense") else 0
		var months_since_faction_war: int = int(faction.get_meta("months_since_faction_war", 0)) if faction.has_meta("months_since_faction_war") else 0
		faction.set_meta("months_since_offense", 0 if any_attack else months_since_offense + 1)
		faction.set_meta("months_since_faction_war", 0 if any_faction_war else months_since_faction_war + 1)
		faction.set_meta("last_attack_target_type", "faction" if any_faction_war else ("neutral" if any_neutral_war else "none"))
