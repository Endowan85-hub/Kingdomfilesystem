# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: ItemLibrary
#
# Role:
# Static library of all item definitions. Province inventories and unit
# equipped_item_id fields store item_id strings only — all item data is
# looked up here. Never duplicates item data in game state.
#
# Allowed Interactions:
# - Read-only by all systems (GameState, resolvers, AI, UI)
#
# Forbidden Responsibilities:
# - Must not mutate GameState
# - Must not queue orders
# - Must not contain gameplay logic
#
# Notes:
# - effect_type: attack_bonus | defense_bonus | hp_bonus | speed_bonus |
#                heal_hp | cure_poison | hybrid
# - effect_value: primary numeric bonus
# - effect_value_2: secondary bonus for hybrid items (else 0)
# - speed_bonus items are stored/equipped/sold but have NO current
#   strategic combat effect — reserved for Tactical Layer
# - consumables provide NO passive stat bonus in V1
# - buy_value 0 = not purchasable in store (equipment must be earned)
# ==================================================
extends RefCounted
class_name ItemLibrary


const ITEMS: Array = [
	# ── ATTACK ──────────────────────────────────────────
	{
		"item_id": "iron_bangle",    "name": "Iron Bangle",
		"category": "equipment",     "subtype": "attack",
		"tier": 1, "rarity": "common",
		"effect_type": "attack_bonus", "effect_value": 1, "effect_value_2": 0,
		"sell_value": 10, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"description": "Attack +1 while equipped."
	},
	{
		"item_id": "steel_bangle",   "name": "Steel Bangle",
		"category": "equipment",     "subtype": "attack",
		"tier": 2, "rarity": "common",
		"effect_type": "attack_bonus", "effect_value": 2, "effect_value_2": 0,
		"sell_value": 20, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"description": "Attack +2 while equipped."
	},
	{
		"item_id": "war_bangle",     "name": "War Bangle",
		"category": "equipment",     "subtype": "attack",
		"tier": 3, "rarity": "uncommon",
		"effect_type": "attack_bonus", "effect_value": 3, "effect_value_2": 0,
		"sell_value": 35, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"description": "Attack +3 while equipped."
	},
	{
		"item_id": "kings_bangle",   "name": "King's Bangle",
		"category": "equipment",     "subtype": "attack",
		"tier": 4, "rarity": "rare",
		"effect_type": "attack_bonus", "effect_value": 4, "effect_value_2": 0,
		"sell_value": 50, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"description": "Attack +4 while equipped."
	},
	# ── DEFENSE ─────────────────────────────────────────
	{
		"item_id": "bronze_guard",   "name": "Bronze Guard",
		"category": "equipment",     "subtype": "defense",
		"tier": 1, "rarity": "common",
		"effect_type": "defense_bonus", "effect_value": 1, "effect_value_2": 0,
		"sell_value": 10, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"description": "Defense +1 while equipped."
	},
	{
		"item_id": "iron_guard",     "name": "Iron Guard",
		"category": "equipment",     "subtype": "defense",
		"tier": 2, "rarity": "common",
		"effect_type": "defense_bonus", "effect_value": 2, "effect_value_2": 0,
		"sell_value": 20, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"description": "Defense +2 while equipped."
	},
	{
		"item_id": "tower_crest",    "name": "Tower Crest",
		"category": "equipment",     "subtype": "defense",
		"tier": 3, "rarity": "uncommon",
		"effect_type": "defense_bonus", "effect_value": 3, "effect_value_2": 0,
		"sell_value": 35, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"description": "Defense +3 while equipped."
	},
	{
		"item_id": "fortress_sigil", "name": "Fortress Sigil",
		"category": "equipment",     "subtype": "defense",
		"tier": 4, "rarity": "rare",
		"effect_type": "defense_bonus", "effect_value": 4, "effect_value_2": 0,
		"sell_value": 50, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"description": "Defense +4 while equipped."
	},
	# ── HP / ENDURANCE ───────────────────────────────────
	{
		"item_id": "vital_charm",    "name": "Vital Charm",
		"category": "equipment",     "subtype": "hp",
		"tier": 1, "rarity": "common",
		"effect_type": "hp_bonus", "effect_value": 5, "effect_value_2": 0,
		"sell_value": 10, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"description": "Max HP +5 while equipped."
	},
	{
		"item_id": "veteran_charm",  "name": "Veteran Charm",
		"category": "equipment",     "subtype": "hp",
		"tier": 2, "rarity": "common",
		"effect_type": "hp_bonus", "effect_value": 10, "effect_value_2": 0,
		"sell_value": 20, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"description": "Max HP +10 while equipped."
	},
	{
		"item_id": "war_totem",      "name": "War Totem",
		"category": "equipment",     "subtype": "hp",
		"tier": 3, "rarity": "uncommon",
		"effect_type": "hp_bonus", "effect_value": 15, "effect_value_2": 0,
		"sell_value": 35, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"description": "Max HP +15 while equipped."
	},
	{
		"item_id": "titan_relic",    "name": "Titan Relic",
		"category": "equipment",     "subtype": "hp",
		"tier": 4, "rarity": "rare",
		"effect_type": "hp_bonus", "effect_value": 20, "effect_value_2": 0,
		"sell_value": 50, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"description": "Max HP +20 while equipped."
	},
	# ── SPEED (future Tactical Layer — no current combat effect) ────
	{
		"item_id": "traveler_boots",      "name": "Traveler Boots",
		"category": "equipment",          "subtype": "speed",
		"tier": 1, "rarity": "common",
		"effect_type": "speed_bonus", "effect_value": 1, "effect_value_2": 0,
		"sell_value": 10, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"description": "Speed +1. (No effect in Strategic Layer.)"
	},
	{
		"item_id": "windstep_boots",      "name": "Windstep Boots",
		"category": "equipment",          "subtype": "speed",
		"tier": 2, "rarity": "common",
		"effect_type": "speed_bonus", "effect_value": 2, "effect_value_2": 0,
		"sell_value": 20, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"description": "Speed +2. (No effect in Strategic Layer.)"
	},
	{
		"item_id": "phantom_boots",       "name": "Phantom Boots",
		"category": "equipment",          "subtype": "speed",
		"tier": 3, "rarity": "uncommon",
		"effect_type": "speed_bonus", "effect_value": 3, "effect_value_2": 0,
		"sell_value": 35, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"description": "Speed +3. (No effect in Strategic Layer.)"
	},
	{
		"item_id": "stormwalker_greaves", "name": "Stormwalker Greaves",
		"category": "equipment",          "subtype": "speed",
		"tier": 4, "rarity": "rare",
		"effect_type": "speed_bonus", "effect_value": 4, "effect_value_2": 0,
		"sell_value": 50, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"description": "Speed +4. (No effect in Strategic Layer.)"
	},
	# ── HYBRID ──────────────────────────────────────────
	{
		"item_id": "soldiers_crest",  "name": "Soldier's Crest",
		"category": "equipment",      "subtype": "hybrid",
		"tier": 2, "rarity": "uncommon",
		"effect_type": "hybrid", "effect_value": 1, "effect_value_2": 1,
		"sell_value": 25, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"description": "Attack +1, Defense +1 while equipped."
	},
	{
		"item_id": "warband_sigil",   "name": "Warband Sigil",
		"category": "equipment",      "subtype": "hybrid",
		"tier": 3, "rarity": "rare",
		"effect_type": "hybrid", "effect_value": 2, "effect_value_2": 1,
		"sell_value": 40, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"description": "Attack +2, Defense +1 while equipped."
	},
	{
		"item_id": "guardian_emblem", "name": "Guardian Emblem",
		"category": "equipment",      "subtype": "hybrid",
		"tier": 3, "rarity": "rare",
		"effect_type": "hybrid", "effect_value": 1, "effect_value_2": 2,
		"sell_value": 40, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"description": "Attack +1, Defense +2 while equipped."
	},
	# ── CONSUMABLES ─────────────────────────────────────
	{
		"item_id": "minor_potion",   "name": "Minor Potion",
		"category": "consumable",    "subtype": "healing",
		"tier": 1, "rarity": "common",
		"effect_type": "heal_hp", "effect_value": 20, "effect_value_2": 0,
		"sell_value": 8, "buy_value": 15,
		"is_consumable": true, "stackable": true,
		"description": "Restores HP when used. (Tactical Layer)"
	},
	{
		"item_id": "major_potion",   "name": "Major Potion",
		"category": "consumable",    "subtype": "healing",
		"tier": 2, "rarity": "common",
		"effect_type": "heal_hp", "effect_value": 50, "effect_value_2": 0,
		"sell_value": 15, "buy_value": 30,
		"is_consumable": true, "stackable": true,
		"description": "Restores more HP when used. (Tactical Layer)"
	},
	{
		"item_id": "antidote",       "name": "Antidote",
		"category": "consumable",    "subtype": "status",
		"tier": 1, "rarity": "common",
		"effect_type": "cure_poison", "effect_value": 1, "effect_value_2": 0,
		"sell_value": 10, "buy_value": 20,
		"is_consumable": true, "stackable": true,
		"description": "Removes poison. (Tactical Layer)"
	},
	# ── SP (SKILL POINTS) ───────────────────────────────
	{
		"item_id": "focus_stone",     "name": "Focus Stone",
		"category": "equipment",      "subtype": "sp",
		"tier": 1, "rarity": "common",
		"effect_type": "sp_bonus", "effect_value": 4, "effect_value_2": 0,
		"sell_value": 10, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"description": "Max SP +4 while equipped."
	},
	{
		"item_id": "spirit_shard",    "name": "Spirit Shard",
		"category": "equipment",      "subtype": "sp",
		"tier": 2, "rarity": "common",
		"effect_type": "sp_bonus", "effect_value": 8, "effect_value_2": 0,
		"sell_value": 20, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"description": "Max SP +8 while equipped."
	},
	{
		"item_id": "arcane_crystal",  "name": "Arcane Crystal",
		"category": "equipment",      "subtype": "sp",
		"tier": 3, "rarity": "uncommon",
		"effect_type": "sp_bonus", "effect_value": 12, "effect_value_2": 0,
		"sell_value": 35, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"description": "Max SP +12 while equipped."
	},
	{
		"item_id": "void_prism",      "name": "Void Prism",
		"category": "equipment",      "subtype": "sp",
		"tier": 4, "rarity": "rare",
		"effect_type": "sp_bonus", "effect_value": 16, "effect_value_2": 0,
		"sell_value": 50, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"description": "Max SP +16 while equipped."
	},
	# ── CP (COMMAND POINTS) — leader only ───────────────
	{
		"item_id": "banner_token",    "name": "Banner Token",
		"category": "equipment",      "subtype": "cp",
		"tier": 1, "rarity": "uncommon",
		"effect_type": "cp_bonus", "effect_value": 5, "effect_value_2": 0,
		"sell_value": 15, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"leader_only": true,
		"description": "Leader only. Command Points +5."
	},
	{
		"item_id": "warlord_seal",    "name": "Warlord Seal",
		"category": "equipment",      "subtype": "cp",
		"tier": 2, "rarity": "uncommon",
		"effect_type": "cp_bonus", "effect_value": 8, "effect_value_2": 0,
		"sell_value": 25, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"leader_only": true,
		"description": "Leader only. Command Points +8."
	},
	{
		"item_id": "marshal_standard", "name": "Marshal Standard",
		"category": "equipment",       "subtype": "cp",
		"tier": 3, "rarity": "rare",
		"effect_type": "cp_bonus", "effect_value": 12, "effect_value_2": 0,
		"sell_value": 40, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"leader_only": true,
		"description": "Leader only. Command Points +12."
	},
	{
		"item_id": "sovereign_banner", "name": "Sovereign Banner",
		"category": "equipment",       "subtype": "cp",
		"tier": 4, "rarity": "rare",
		"effect_type": "cp_bonus", "effect_value": 16, "effect_value_2": 0,
		"sell_value": 55, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"leader_only": true,
		"description": "Leader only. Command Points +16."
	},
	# ── RARE ────────────────────────────────────────────
	{
		"item_id": "champions_mark", "name": "Champion's Mark",
		"category": "equipment",     "subtype": "attack",
		"tier": 2, "rarity": "rare",
		"effect_type": "attack_bonus", "effect_value": 2, "effect_value_2": 0,
		"sell_value": 25, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"description": "Attack +2 while equipped."
	},
	{
		"item_id": "bulwark_relic",  "name": "Bulwark Relic",
		"category": "equipment",     "subtype": "defense",
		"tier": 2, "rarity": "rare",
		"effect_type": "defense_bonus", "effect_value": 2, "effect_value_2": 0,
		"sell_value": 25, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"description": "Defense +2 while equipped."
	},
	{
		"item_id": "giants_totem",   "name": "Giant's Totem",
		"category": "equipment",     "subtype": "hp",
		"tier": 3, "rarity": "rare",
		"effect_type": "hp_bonus", "effect_value": 15, "effect_value_2": 0,
		"sell_value": 40, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"description": "Max HP +15 while equipped."
	},
	{
		"item_id": "war_master_token", "name": "War Master Token",
		"category": "equipment",       "subtype": "hybrid",
		"tier": 3, "rarity": "rare",
		"effect_type": "hybrid", "effect_value": 1, "effect_value_2": 1,
		"sell_value": 40, "buy_value": 0,
		"is_consumable": false, "stackable": false,
		"description": "Attack +1, Defense +1 while equipped."
	},
]

# Mission reward drop weights by tier (within the 15% item result chance)
const MISSION_TIER_WEIGHTS: Dictionary = { 1: 65, 2: 25, 3: 8, 4: 2 }

# Store: consumable item_ids available for purchase
const STORE_CATALOG: Array[String] = ["minor_potion", "major_potion", "antidote"]

# AI buy caps per province
const AI_BUY_CAPS: Dictionary = {
	"minor_potion": 2, "major_potion": 1, "antidote": 1
}


# ── Static API ───────────────────────────────────────────────────────────────

static func get_item(item_id: String) -> Dictionary:
	for tpl in ITEMS:
		if str(tpl["item_id"]) == item_id:
			return tpl
	return {}


static func is_valid_id(item_id: String) -> bool:
	for tpl in ITEMS:
		if str(tpl["item_id"]) == item_id:
			return true
	return false


static func get_sell_value(item_id: String) -> int:
	var tpl: Dictionary = get_item(item_id)
	return int(tpl.get("sell_value", 0))


static func get_buy_value(item_id: String) -> int:
	var tpl: Dictionary = get_item(item_id)
	return int(tpl.get("buy_value", 0))


static func is_consumable(item_id: String) -> bool:
	var tpl: Dictionary = get_item(item_id)
	return bool(tpl.get("is_consumable", false))


static func get_tier(item_id: String) -> int:
	var tpl: Dictionary = get_item(item_id)
	return int(tpl.get("tier", 1))


static func get_effect_type(item_id: String) -> String:
	var tpl: Dictionary = get_item(item_id)
	return str(tpl.get("effect_type", ""))


static func get_effect_value(item_id: String) -> int:
	var tpl: Dictionary = get_item(item_id)
	return int(tpl.get("effect_value", 0))


static func get_effect_value_2(item_id: String) -> int:
	var tpl: Dictionary = get_item(item_id)
	return int(tpl.get("effect_value_2", 0))


# Returns all equipment item_ids of a given tier for mission rewards
static func get_equipment_ids_by_tier(tier: int) -> Array[String]:
	var out: Array[String] = []
	for tpl in ITEMS:
		if int(tpl.get("tier", 1)) == tier and not bool(tpl.get("is_consumable", false)):
			out.append(str(tpl["item_id"]))
	return out


# Roll a random mission item reward using weighted tier table
static func roll_mission_item(rng: RandomNumberGenerator) -> String:
	var roll: int = rng.randi_range(1, 100)
	var tier: int = 1
	if roll <= 2:
		tier = 4
	elif roll <= 10:
		tier = 3
	elif roll <= 35:
		tier = 2
	var candidates: Array[String] = get_equipment_ids_by_tier(tier)
	if candidates.is_empty():
		candidates = get_equipment_ids_by_tier(1)
	if candidates.is_empty():
		return ""
	return candidates[rng.randi_range(0, candidates.size() - 1)]


# Apply item stat bonuses to a unit's effective stats for combat/display.
# Returns a Dictionary with keys: attack, defense, max_hp
# Speed bonus is tracked but not applied to combat.
static func get_unit_item_bonuses(item_id: String) -> Dictionary:
	if item_id == "":
		return { "attack": 0, "defense": 0, "max_hp": 0, "max_sp": 0, "max_cp": 0 }
	var tpl: Dictionary = get_item(item_id)
	if tpl.is_empty() or bool(tpl.get("is_consumable", false)):
		return { "attack": 0, "defense": 0, "max_hp": 0, "max_sp": 0, "max_cp": 0 }
	var effect: String = str(tpl.get("effect_type", ""))
	var v1: int = int(tpl.get("effect_value", 0))
	var v2: int = int(tpl.get("effect_value_2", 0))
	match effect:
		"attack_bonus":  return { "attack": v1, "defense": 0,  "max_hp": 0,  "max_sp": 0,  "max_cp": 0 }
		"defense_bonus": return { "attack": 0,  "defense": v1, "max_hp": 0,  "max_sp": 0,  "max_cp": 0 }
		"hp_bonus":      return { "attack": 0,  "defense": 0,  "max_hp": v1, "max_sp": 0,  "max_cp": 0 }
		"hybrid":        return { "attack": v1, "defense": v2, "max_hp": 0,  "max_sp": 0,  "max_cp": 0 }
		"speed_bonus":   return { "attack": 0,  "defense": 0,  "max_hp": 0,  "max_sp": 0,  "max_cp": 0 }  # inactive
		"sp_bonus":      return { "attack": 0,  "defense": 0,  "max_hp": 0,  "max_sp": v1, "max_cp": 0 }
		"cp_bonus":      return { "attack": 0,  "defense": 0,  "max_hp": 0,  "max_sp": 0,  "max_cp": v1 }
		_:               return { "attack": 0,  "defense": 0,  "max_hp": 0,  "max_sp": 0,  "max_cp": 0 }
