# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: OwnershipResolver
#
# Role:
# Rebuilds each faction's province list based on current province owners,
# then checks for and processes faction eliminations.
#
# Elimination rules:
# - A faction is eliminated when it owns 0 provinces.
# - On elimination: all leaders set to "wounded", stripped from province
#   and faction assignment, faction.is_eliminated = true.
# - Leaders are NOT deleted (game rule: leaders never die permanently).
# - Eliminated factions are skipped in all future AI planning passes.
#
# Allowed Interactions:
# - GameState
# - MapData / ProvinceData / FactionData / LeaderData
# - DebugLogger (logging only)
#
# Forbidden Responsibilities:
# - Must not interact with UI
# - Must not create orders
# - Must not run turn sequencing
#
# Game Phase:
# Execution Phase (runs after all other resolvers each month)
# ==================================================

class_name OwnershipResolver
extends RefCounted


func resolve(state: GameState) -> void:
	recount_faction_provinces(state)


func recount_faction_provinces(state: GameState) -> void:
	var map_data: MapData = state.map_data
	var log = state.logger

	var counts: Dictionary = {}

	# Clear province lists and init counts
	for item in map_data.factions:
		var f: FactionData = item as FactionData
		f.provinces = []
		counts[int(f.id)] = 0

	# Rebuild lists
	for item2 in map_data.provinces:
		var p: ProvinceData = item2 as ProvinceData
		var oid: int = int(p.owner_id)
		if oid < 0:
			continue

		var f2: FactionData = _find_faction(map_data, oid)
		if f2 != null:
			f2.provinces.append(int(p.id))
			counts[int(f2.id)] = int(counts.get(int(f2.id), 0)) + 1

	if log != null:
		log.event("ownership_result", {
			"province_counts": counts
		})

	# Check for new eliminations after province counts are settled
	_check_eliminations(state)
	_relocate_stranded_leaders(state)


func _check_eliminations(state: GameState) -> void:
	var map_data: MapData = state.map_data
	var log = state.logger

	for item in map_data.factions:
		var faction: FactionData = item as FactionData
		if faction == null:
			continue
		if bool(faction.is_eliminated):
			continue
		if not (faction.provinces as Array).is_empty():
			continue

		# Faction has 0 provinces — eliminate it
		faction.is_eliminated = true

		var wounded_ids: Array = []

		# Wound and evict all leaders belonging to this faction
		for item2 in state.leaders:
			var leader: LeaderData = item2 as LeaderData
			if leader == null:
				continue
			if int(leader.faction_id) != int(faction.id):
				continue

			# Set wounded with full timer
			leader.status = "wounded"
			leader.wounded_turns_remaining = 4
			leader.on_mission = false

			# Remove from their province's leader list and clear ruler slot
			var pid: int = int(leader.current_province_id)
			if pid >= 0 and pid < map_data.provinces.size():
				var prov: ProvinceData = map_data.provinces[pid] as ProvinceData
				if prov != null:
					prov.leader_ids.erase(int(leader.id))
					if int(prov.ruler_leader_id) == int(leader.id):
						prov.ruler_leader_id = prov.leader_ids[0] if not prov.leader_ids.is_empty() else -1

			# Park leader in limbo (province -1, faction -1)
			leader.current_province_id = -1
			leader.province_id = -1
			leader.faction_id = -1

			wounded_ids.append(int(leader.id))

		# Clear faction's leader registry
		faction.leader_ids.clear()

		if log != null:
			log.event("faction_eliminated", {
				"faction_id": int(faction.id),
				"faction_name": str(faction.display_name),
				"wounded_leaders": wounded_ids
			})

		DebugLogger.log("faction_eliminated: %s (id=%d) | %d leaders wounded" % [
			str(faction.display_name), int(faction.id), wounded_ids.size()
		])


func _find_faction(map_data: MapData, id: int) -> FactionData:
	for item in map_data.factions:
		var f: FactionData = item as FactionData
		if int(f.id) == id:
			return f
	return null


func _relocate_stranded_leaders(state: GameState) -> void:
	var map_data: MapData = state.map_data
	if map_data == null:
		return

	for item in state.leaders:
		var leader: LeaderData = item as LeaderData
		if leader == null:
			continue
		if int(leader.faction_id) < 0:
			continue

		var pid: int = int(leader.current_province_id)
		if pid < 0 or pid >= map_data.provinces.size():
			continue

		var current_province: ProvinceData = map_data.provinces[pid] as ProvinceData
		if current_province == null:
			continue
		if int(current_province.owner_id) == int(leader.faction_id):
			continue

		var fallback_pid: int = _find_nearest_friendly_province(map_data, pid, int(leader.faction_id))
		if fallback_pid >= 0:
			current_province.leader_ids.erase(int(leader.id))
			if int(current_province.ruler_leader_id) == int(leader.id):
				current_province.ruler_leader_id = current_province.leader_ids[0] if not current_province.leader_ids.is_empty() else -1

			var fallback_province: ProvinceData = map_data.provinces[fallback_pid] as ProvinceData
			if fallback_province != null and not fallback_province.leader_ids.has(int(leader.id)):
				fallback_province.leader_ids.append(int(leader.id))
				if int(fallback_province.ruler_leader_id) < 0:
					fallback_province.ruler_leader_id = int(leader.id)

			leader.current_province_id = fallback_pid
			leader.province_id = fallback_pid
		else:
			leader.status = "wounded"
			leader.on_mission = false
			current_province.leader_ids.erase(int(leader.id))
			if int(current_province.ruler_leader_id) == int(leader.id):
				current_province.ruler_leader_id = current_province.leader_ids[0] if not current_province.leader_ids.is_empty() else -1
			leader.current_province_id = -1
			leader.province_id = -1
			leader.faction_id = -1


func _find_nearest_friendly_province(map_data: MapData, start_pid: int, faction_id: int) -> int:
	var visited: Dictionary = {}
	var queue: Array = [start_pid]
	visited[start_pid] = true

	while not queue.is_empty():
		var pid: int = int(queue.pop_front())
		for next_pid_value in map_data.adjacency.get(pid, []):
			var next_pid: int = int(next_pid_value)
			if visited.has(next_pid):
				continue
			visited[next_pid] = true
			var province: ProvinceData = map_data.provinces[next_pid] as ProvinceData
			if province != null and int(province.owner_id) == faction_id:
				return next_pid
			queue.append(next_pid)

	return -1
