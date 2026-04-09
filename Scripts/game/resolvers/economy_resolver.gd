# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: EconomyResolver
#
# Role:
# Computes faction income from owned provinces, deducts unit upkeep,
# and applies the net result to faction gold.
#
# Allowed Interactions:
# - GameState
# - MapData / ProvinceData / FactionData
# - DebugLogger (logging only)
#
# Forbidden Responsibilities:
# - Must not interact with UI
# - Must not create orders
# - Must not run turn sequencing
#
# Game Phase:
# Execution Phase
# ==================================================

class_name EconomyResolver
extends RefCounted


func resolve(state: GameState) -> void:
	var map_data: MapData = state.map_data
	var log = state.logger

	var income_by_faction:  Dictionary = {}
	var upkeep_by_faction:  Dictionary = {}
	var gold_before:        Dictionary = {}

	# Reset income counters and capture gold before
	for item in map_data.factions:
		var f: FactionData = item as FactionData
		income_by_faction[int(f.id)] = 0
		upkeep_by_faction[int(f.id)] = 0
		gold_before[int(f.id)]       = int(f.gold)
		f.income = 0

	# Sum province income per faction
	for p_item in map_data.provinces:
		var p: ProvinceData = p_item as ProvinceData
		var owner_id: int = int(p.owner_id)
		var f2: FactionData = _find_faction(map_data, owner_id)
		if f2 == null:
			continue
		f2.income += int(p.income)

	# Sum unit upkeep per faction
	# Only units currently attached to a leader (in an army) cost upkeep.
	# Units sitting in a province inventory are not yet paid soldiers.
	for f_item in map_data.factions:
		var f3: FactionData = f_item as FactionData
		var total_upkeep: int = 0
		for lid_val in f3.leader_ids:
			var leader: LeaderData = state.get_leader(int(lid_val))
			if leader == null:
				continue
			# Leader salary
			total_upkeep += int(leader.upkeep_cost)
			# Unit upkeep
			for uid_val in leader.army_unit_ids:
				var unit: UnitData = state.get_unit(int(uid_val)) as UnitData
				if unit != null:
					total_upkeep += int(unit.upkeep_cost)
		upkeep_by_faction[int(f3.id)] = total_upkeep

	# Apply net (income - upkeep) to gold
	# Upkeep is capped to available income + gold so factions can never go
	# permanently negative from a single bad turn. Small factions starting with
	# 1-2 provinces and full armies would otherwise collapse immediately.
	for item2 in map_data.factions:
		var f4: FactionData = item2 as FactionData
		var fid: int = int(f4.id)
		f4.income_last_turn = int(f4.income)
		var income: int = int(f4.income_last_turn)
		var upkeep: int = int(upkeep_by_faction.get(fid, 0))
		# Cap upkeep to what the faction can actually afford:
		# income first, then dip into gold, but never below 0
		var available: int = income + int(f4.gold)
		var paid_upkeep: int = mini(upkeep, available)
		var net: int = income - paid_upkeep
		f4.gold = maxi(0, int(f4.gold) + net)
		income_by_faction[fid] = income
		upkeep_by_faction[fid] = paid_upkeep

	var gold_after: Dictionary = {}
	for item3 in map_data.factions:
		var f5: FactionData = item3 as FactionData
		gold_after[int(f5.id)] = int(f5.gold)

	if log != null:
		log.event("economy_result", {
			"income":   income_by_faction,
			"upkeep":   upkeep_by_faction,
			"gold_before": gold_before,
			"gold_after":  gold_after
		})


func _find_faction(map_data: MapData, id: int) -> FactionData:
	for item in map_data.factions:
		var f: FactionData = item as FactionData
		if int(f.id) == id:
			return f
	return null
