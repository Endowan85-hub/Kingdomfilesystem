# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: UnitData
#
# Role:
# Stores simulation state for a single unit entity in the strategic layer.
# Units are real game objects with stats, not numeric garrison values.
# Units exist independently of leaders and can reside in a leader army,
# a province inventory, or be unassigned.
#
# Allowed Interactions:
# - GameState (registry lookup)
# - LeaderData (army_unit_ids references this unit's id)
# - ProvinceData (unit_inventory references this unit's id)
# - Resolvers (read/mutate stats during execution phase)
# - UnitLibrary (used to spawn units from templates)
# - ProgressionTuningProfile (stat growth knobs)
#
# Forbidden Responsibilities:
# - Must not execute gameplay logic
# - Must not queue orders
# - Must not interact with UI directly
# - Must not reference LeaderData or ProvinceData directly (id references only)
#
# Game Phase:
# Both
#
# Notes:
# - cp_cost is defined by unit type and does not change at runtime.
# - Units level independently from their leader.
# - owner_leader_id = -1 means the unit is in province inventory (unassigned).
# - province_id tracks physical location regardless of army assignment.
# - Stat growth per level is driven by ProgressionTuningProfile.
# ==================================================
extends Resource
class_name UnitData

const ProgressionTuningProfile = preload("res://Scripts/game/tools/progression_tuning_profile.gd")

@export var unit_id: int = -1
@export var unit_type: String = ""
@export var unit_name: String = ""  # personal name assigned at recruitment

@export var level: int = 1
@export var xp: int = 0
@export var xp_to_next_level: int = 20

@export var attack: int = 3
@export var defense: int = 3
@export var skill_power: int = 10  # legacy field — use max_sp
@export var max_sp: int = 10       # SP per spec: 10 + (level-1)*2
@export var hp: int = 10
@export var max_hp: int = 10

@export var skills: Array[String] = []
@export var traits: Array[String] = []

@export var damage_type: String = "slash"  # slash | pierce | blunt
@export var tier: int = 1                  # 1=recruit 2=veteran 3=elite
@export var cp_cost: int = 5
@export var upkeep_cost: int = 10  # gold drained per month while attached to a leader

@export var speed: int = 4        # movement / initiative — affects hit chance calculation
@export var accuracy: int = 75    # base hit chance before evasion
@export var evasion: int = 8      # reduces attacker hit chance

@export var owner_leader_id: int = -1
@export var province_id: int = -1

# Item system — one slot per unit.
# Stores the item_id string from ItemLibrary. Empty string = no item.
# Units retain their equipped item when moved to storage or reserve.
@export var equipped_item_id: String = ""

# Sigil system — one sigil slot per unit.
# Stores the sigil_id string from SigilLibrary. Empty = no sigil equipped.
@export var equipped_sigil_id: String = ""

# Augment slot — Tier 3+ only (level 10+). Modifies the equipped sigil.
@export var equipped_augment_id: String = ""

# Sigil tag filter — set at spawn by UnitLibrary based on damage_type and role.
# Determines which sigil categories this unit may equip.
@export var allowed_tags: Array[String] = []

# Accumulated fractional stat growth (not exported — runtime only)
var _attack_accum: float = 0.0
var _defense_accum: float = 0.0
var _hp_accum: float = 0.0


func is_alive() -> bool:
	return hp > 0


func is_in_army() -> bool:
	return owner_leader_id >= 0


func heal_full() -> void:
	hp = max_hp


func take_damage(amount: int) -> void:
	hp = maxi(0, hp - amount)


func add_xp(amount: int) -> int:
	xp += amount
	var levels_gained: int = 0
	var profile := ProgressionTuningProfile.get_instance()

	while xp >= xp_to_next_level:
		xp -= xp_to_next_level
		level += 1
		xp_to_next_level = _calc_xp_to_next(level, profile)
		_apply_stat_growth(profile)
		levels_gained += 1

	return levels_gained


func _calc_xp_to_next(current_level: int, profile: ProgressionTuningProfile) -> int:
	return profile.unit_xp_base + (current_level - 1) * profile.unit_xp_growth


func _apply_stat_growth(profile: ProgressionTuningProfile) -> void:
	_attack_accum += profile.unit_attack_per_level
	_defense_accum += profile.unit_defense_per_level
	_hp_accum += profile.unit_hp_per_level

	var atk_gain: int = int(_attack_accum)
	var def_gain: int = int(_defense_accum)
	var hp_gain: int = int(_hp_accum)

	_attack_accum -= atk_gain
	_defense_accum -= def_gain
	_hp_accum -= hp_gain

	attack += atk_gain
	defense += def_gain
	max_hp += hp_gain
	hp = mini(hp + hp_gain, max_hp)


static func calc_max_sp(unit_level: int) -> int:
	return 10 + (unit_level - 1) * 2
