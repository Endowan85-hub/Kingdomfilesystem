# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: ProvinceData
#
# Role:
# Stores simulation data for a single strategic province, including ownership,
# economy, military values, and stationed leader references.
#
# Allowed Interactions:
# - GameState
# - MapData
# - TurnManager / resolvers
# - UI visualization systems (read-only during Planning Phase)
#
# Forbidden Responsibilities:
# - Must not execute gameplay logic
# - Must not queue orders
# - Must not interact with UI directly
#
# Game Phase:
# Both
#
# Notes:
# - Province leader state is now stored as leader ids only.
# - Mission resolution belongs to MissionResolver and leader records.
# - Military strength is derived from unit_inventory and leader army units (no garrison field).
# ==================================================
extends Resource
class_name ProvinceData

@export var id: int = -1
@export var display_name: String = "Province"
@export var center: Vector2 = Vector2.ZERO
@export var biome: String = "plains"  # plains / forest / mountain / desert / tundra / swamp / coast

# Ownership
@export var owner_id: int = -1 # -1 = neutral

# Economy / strategy
@export var population: int = 0
@export var base_income: int = 0
@export var income: int = 0

@export var fort_level: int = 1
@export var defense_value: int = 0
@export var strategic_value: float = 0.0

@export var is_chokepoint: bool = false
@export var is_bridge_hub: bool = false
@export var is_mountain_pass_hub: bool = false

# Leaders stationed in this province.
@export var leader_ids: Array[int] = []
@export var ruler_leader_id: int = -1

# ==================================================
# Province Inventory System (Phase 5)
# --------------------------------------------------
# unit_inventory stores ids of units not assigned to a leader army.
# These units defend the province if attacked without a leader present.
# Units are added here on recruitment and removed when assigned to a leader.
# ==================================================
@export var unit_inventory: Array[int] = []

# ==================================================
# Province Item Inventory
# --------------------------------------------------
# Stores item_id strings from ItemLibrary for unequipped items.
# Consumables use quantity > 1; equipment always quantity = 1.
# Format: Array of { "item_id": String, "quantity": int }
# Items belong to the province owner — captured province transfers all items.
# ==================================================
@export var item_inventory: Array = []

# ==================================================
# Province Sigil Inventory
# --------------------------------------------------
# Stores sigil_id strings from SigilLibrary for unequipped sigils.
# Format: Array of String sigil_ids
# ==================================================
@export var sigil_inventory: Array = []

# ==================================================
# Mission Slots
# --------------------------------------------------
# active_missions: Array of mission_id Strings currently active in this province.
# Max 2 slots. Each entry is a mission_id that maps to MissionLibrary.
# mission_slot_cooldowns: one cooldown counter per slot (0 = ready to reroll).
# When a mission completes or expires, its slot cooldown is set to 2–4 turns
# and counts down each execute before a new mission can spawn in that slot.
# ==================================================
@export var active_missions: Array = []        # Array of mission_id Strings (max 2)
@export var mission_slot_cooldowns: Array = [] # Array of int cooldown counters per slot


func add_item(item_id: String, quantity: int = 1) -> void:
	for entry in item_inventory:
		if str((entry as Dictionary).get("item_id", "")) == item_id:
			(entry as Dictionary)["quantity"] = int((entry as Dictionary).get("quantity", 0)) + quantity
			return
	item_inventory.append({ "item_id": item_id, "quantity": quantity })


func remove_item(item_id: String, quantity: int = 1) -> bool:
	for i in range(item_inventory.size()):
		var entry := item_inventory[i] as Dictionary
		if str(entry.get("item_id", "")) == item_id:
			var current: int = int(entry.get("quantity", 0))
			if current <= quantity:
				item_inventory.remove_at(i)
			else:
				entry["quantity"] = current - quantity
			return true
	return false


func has_item(item_id: String) -> bool:
	for entry in item_inventory:
		if str((entry as Dictionary).get("item_id", "")) == item_id:
			return int((entry as Dictionary).get("quantity", 0)) > 0
	return false


func get_item_quantity(item_id: String) -> int:
	for entry in item_inventory:
		if str((entry as Dictionary).get("item_id", "")) == item_id:
			return int((entry as Dictionary).get("quantity", 0))
	return 0


func add_unit_to_inventory(unit_id: int) -> void:
	if unit_id >= 0 and not unit_inventory.has(unit_id):
		unit_inventory.append(unit_id)


func remove_unit_from_inventory(unit_id: int) -> bool:
	var idx: int = unit_inventory.find(unit_id)
	if idx == -1:
		return false
	unit_inventory.remove_at(idx)
	return true


func has_unit_in_inventory(unit_id: int) -> bool:
	return unit_inventory.has(unit_id)


func add_sigil(sigil_id: String) -> void:
	sigil_inventory.append(sigil_id)


func remove_sigil(sigil_id: String) -> bool:
	var idx: int = sigil_inventory.find(sigil_id)
	if idx == -1:
		return false
	sigil_inventory.remove_at(idx)
	return true


func has_sigil(sigil_id: String) -> bool:
	return sigil_inventory.has(sigil_id)
