# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: UpgradeResolver
#
# Role:
# Applies queued fort upgrade orders during the execution phase.
#
# Allowed Interactions:
# - GameState
# - MapData / ProvinceData / FactionData
# - OrderBook (read-only)
# - DebugLogger (logging only)
#
# Forbidden Responsibilities:
# - Must not interact with UI
# - Must not create orders
# - Must not run turn sequencing
#
# Game Phase:
# Execution Phase
#
# Notes:
# - A specific province may only be upgraded once per turn.
# - Duplicate upgrade orders for the same province in the same month are skipped.
# ==================================================

class_name UpgradeResolver
extends RefCounted


func resolve(state: GameState) -> void:
	var map_data: MapData = state.map_data
	var ob: OrderBook = state.order_book
	var log: DebugLogger = state.logger

	var attempted := 0
	var applied := 0
	var skipped_owner := 0
	var skipped_gold := 0
	var skipped_duplicate := 0
	var total_cost := 0
	var upgrades: Array = []

	# province_id -> true for provinces already upgraded this turn
	var upgraded_this_turn: Dictionary = {}

	for item in map_data.factions:
		var f: FactionData = item as FactionData
		var fid: int = int(f.id)
		var orders: Array = ob.get_upgrades(fid)

		for o in orders:
			attempted += 1

			var pid: int = int(o["province_id"])
			var cost: int = int(o["cost"])

			if upgraded_this_turn.has(pid):
				skipped_duplicate += 1
				continue

			var p: ProvinceData = map_data.provinces[pid] as ProvinceData

			if int(p.owner_id) != fid:
				skipped_owner += 1
				continue

			if int(f.gold) < cost:
				skipped_gold += 1
				continue

			f.gold = int(f.gold) - cost
			total_cost += cost

			p.fort_level = int(p.fort_level) + 1
			p.defense_value = int(p.defense_value) + TurnManager.FORT_DEF_PER_LEVEL

			upgraded_this_turn[pid] = true
			applied += 1

			upgrades.append({
				"faction": fid,
				"province_id": pid,
				"new_fort": int(p.fort_level)
			})

	if log != null:
		log.event("upgrade_result", {
			"attempted": attempted,
			"applied": applied,
			"skipped_owner": skipped_owner,
			"skipped_gold": skipped_gold,
			"skipped_duplicate": skipped_duplicate,
			"total_cost": total_cost,
			"upgrades": upgrades
		})

	# --------------------------------------------------
	# Promotions
	# --------------------------------------------------
	for item2 in map_data.factions:
		var f2: FactionData = item2 as FactionData
		var fid2: int = int(f2.id)
		var promo_orders: Array = ob.get_promotions(fid2)
		for o2 in promo_orders:
			state.promote_unit(fid2, int(o2["unit_id"]))
