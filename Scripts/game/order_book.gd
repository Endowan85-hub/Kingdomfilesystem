extends Resource
class_name OrderBook

# Orders stored by faction id. Each value is an Array[Dictionary].
# This keeps the planning phase independent from UI and simulation.

var upgrades_by_faction: Dictionary = {}  # int -> Array[Dictionary]
var transfers_by_faction: Dictionary = {} # int -> Array[Dictionary]
var attacks_by_faction: Dictionary = {}   # int -> Array[Dictionary]


func clear_orders_for_faction(faction_id: int) -> void:
	upgrades_by_faction[faction_id] = []
	transfers_by_faction[faction_id] = []
	attacks_by_faction[faction_id] = []


func clear_all(faction_ids: Array[int]) -> void:
	for fid in faction_ids:
		clear_orders_for_faction(int(fid))


func queue_upgrade(faction_id: int, province_id: int, cost: int) -> void:
	if not upgrades_by_faction.has(faction_id):
		upgrades_by_faction[faction_id] = []
	var arr: Array = upgrades_by_faction[faction_id]
	arr.append({"province_id": province_id, "cost": cost})


func queue_transfer(faction_id: int, from_id: int, to_id: int, sent: int, cost: int, arrive: int) -> void:
	if not transfers_by_faction.has(faction_id):
		transfers_by_faction[faction_id] = []
	var arr: Array = transfers_by_faction[faction_id]
	arr.append({"from": from_id, "to": to_id, "sent": sent, "cost": cost, "arrive": arrive})


func queue_attack(faction_id: int, from_id: int, to_id: int, commit: int) -> void:
	if not attacks_by_faction.has(faction_id):
		attacks_by_faction[faction_id] = []
	var arr: Array = attacks_by_faction[faction_id]
	arr.append({"from": from_id, "to": to_id, "commit": commit})


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
