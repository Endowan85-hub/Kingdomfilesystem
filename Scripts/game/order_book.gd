extends Resource
class_name OrderBook
## CONTRACT NOTES (do not remove; append only):
## - OrderBook stores Planning Phase orders only (queued actions).
## - Resolvers read orders during Execute Month; UI should not execute simulation.
## - Do not change data keys without updating all resolvers/UI together.
## - Mission orders now target leader ids; outcomes still belong to MissionResolver.

var upgrades_by_faction: Dictionary = {}
var transfers_by_faction: Dictionary = {}
var attacks_by_faction: Dictionary = {}
var missions_by_faction: Dictionary = {}
var promotions_by_faction: Dictionary = {}
var heals_by_faction: Dictionary = {}


func clear_orders_for_faction(faction_id: int) -> void:
	upgrades_by_faction[faction_id] = []
	transfers_by_faction[faction_id] = []
	attacks_by_faction[faction_id] = []
	missions_by_faction[faction_id] = []
	promotions_by_faction[faction_id] = []
	heals_by_faction[faction_id] = []


func clear_all(faction_ids: Array[int]) -> void:
	for fid in faction_ids:
		clear_orders_for_faction(int(fid))


func queue_upgrade(faction_id: int, province_id: int, cost: int) -> void:
	if not upgrades_by_faction.has(faction_id):
		upgrades_by_faction[faction_id] = []
	var arr: Array = upgrades_by_faction[faction_id]
	arr.append({"province_id": province_id, "cost": cost})
	DebugLogger.log("order:upgrade", {"faction": faction_id, "province_id": province_id, "cost": cost})


func queue_transfer(faction_id: int, from_id: int, to_id: int, leader_ids: Array) -> void:
	if not transfers_by_faction.has(faction_id):
		transfers_by_faction[faction_id] = []
	var arr: Array = transfers_by_faction[faction_id]

	# Remove any leader already committed to another transfer or attack
	var already_committed: Array = []
	for existing in arr:
		for lid in existing.get("leader_ids", []):
			already_committed.append(int(lid))
	for existing in attacks_by_faction.get(faction_id, []):
		for lid in existing.get("leader_ids", []):
			already_committed.append(int(lid))

	var clean_leader_ids: Array = []
	for lid in leader_ids:
		if not already_committed.has(int(lid)):
			clean_leader_ids.append(int(lid))

	arr.append({"from": from_id, "to": to_id, "leader_ids": clean_leader_ids})
	DebugLogger.log("order:transfer", {"faction": faction_id, "from": from_id, "to": to_id, "leader_ids": clean_leader_ids})


func queue_attack(faction_id: int, from_id: int, to_id: int, commit: int, leader_ids: Array = []) -> void:
	if not attacks_by_faction.has(faction_id):
		attacks_by_faction[faction_id] = []
	var arr: Array = attacks_by_faction[faction_id]

	# Remove any leader already committed to another attack order
	var already_committed: Array = []
	for existing in arr:
		for lid in existing.get("leader_ids", []):
			already_committed.append(int(lid))

	var clean_leader_ids: Array = []
	for lid in leader_ids:
		if not already_committed.has(int(lid)):
			clean_leader_ids.append(int(lid))
		else:
			DebugLogger.log("order:attack_leader_conflict", {"faction": faction_id, "leader_id": int(lid), "skipped_to": to_id})

	arr.append({"from": from_id, "to": to_id, "commit": commit, "leader_ids": clean_leader_ids})
	DebugLogger.log("order:attack", {"faction": faction_id, "from": from_id, "to": to_id, "leader_ids": clean_leader_ids})


func queue_mission(faction_id: int, province_id: int, leader_id: int, mission_instance_id: String, duration_turns: int = 1) -> void:
	if not missions_by_faction.has(faction_id):
		missions_by_faction[faction_id] = []

	var arr: Array = missions_by_faction[faction_id]

	var payload := {
		"faction":             faction_id,
		"province_id":         province_id,
		"leader_id":           int(leader_id),
		"mission_instance_id": mission_instance_id,
		"duration_turns":      maxi(1, duration_turns)
	}

	# Replace existing order for this leader if one exists
	for i in range(arr.size()):
		var existing: Dictionary = arr[i]
		if int(existing.get("leader_id", -1)) == int(leader_id):
			arr[i] = payload
			missions_by_faction[faction_id] = arr
			DebugLogger.log("order:mission_replace", payload)
			return

	arr.append(payload)
	missions_by_faction[faction_id] = arr
	DebugLogger.log("order:mission", payload)


func queue_heal(faction_id: int, province_id: int, unit_id: int, cost: int) -> void:
	if not heals_by_faction.has(faction_id):
		heals_by_faction[faction_id] = []
	var arr: Array = heals_by_faction[faction_id]
	for existing in arr:
		if int(existing.get("unit_id", -1)) == unit_id:
			DebugLogger.log("order:heal_duplicate", {"faction": faction_id, "province_id": province_id, "unit_id": unit_id})
			return
	arr.append({"province_id": province_id, "unit_id": unit_id, "cost": cost})
	DebugLogger.log("order:heal", {"faction": faction_id, "province_id": province_id, "unit_id": unit_id, "cost": cost})


func get_upgrades(faction_id: int) -> Array:
	if not upgrades_by_faction.has(faction_id):
		return []
	return upgrades_by_faction[faction_id]


func get_transfers(faction_id: int) -> Array:
	if not transfers_by_faction.has(faction_id):
		return []
	return transfers_by_faction[faction_id]


func get_attacks(faction_id: int) -> Array:
	if not attacks_by_faction.has(faction_id):
		return []
	return attacks_by_faction[faction_id]


func get_missions(faction_id: int) -> Array:
	if not missions_by_faction.has(faction_id):
		return []
	return missions_by_faction[faction_id]


func queue_promotion(faction_id: int, unit_id: int, cost: int) -> void:
	if not promotions_by_faction.has(faction_id):
		promotions_by_faction[faction_id] = []
	heals_by_faction[faction_id] = []
	var arr: Array = promotions_by_faction[faction_id]
	# Prevent duplicate promotion orders for the same unit
	for existing in arr:
		if int(existing.get("unit_id", -1)) == unit_id:
			DebugLogger.log("order:promotion_duplicate", {"faction": faction_id, "unit_id": unit_id})
			return
	arr.append({"unit_id": unit_id, "cost": cost})
	DebugLogger.log("order:promotion", {"faction": faction_id, "unit_id": unit_id, "cost": cost})


func get_promotions(faction_id: int) -> Array:
	if not promotions_by_faction.has(faction_id):
		return []
	return promotions_by_faction[faction_id]


func get_heals(faction_id: int) -> Array:
	if not heals_by_faction.has(faction_id):
		return []
	return heals_by_faction[faction_id]
