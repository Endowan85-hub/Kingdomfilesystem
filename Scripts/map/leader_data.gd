# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: LeaderData
#
# Role:
# Stores simulation state for a strategic-layer leader, including faction
# ownership, province assignment, story/procedural identity, mission state,
# base stats, traits, and army command limits.
#
# Allowed Interactions:
# - GameState
# - MapData / ProvinceData / FactionData
# - TurnManager / resolvers
# - UI visualization systems (read-only during Planning Phase)
# - ProgressionTuningProfile (stat growth knobs)
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
# - Mission state now belongs to leaders instead of provinces.
# - Story and procedural leaders share the same data shape.
# - Base stats use a 1-10 scale. Final effective values may exceed 10 later
#   through levels, relics, buffs, or other systems.
# - Army composition is reference-based. Units are stored elsewhere and linked
#   to leaders by id.
# - Stat growth per level is driven by ProgressionTuningProfile.
# - Stat rotation: leadership → attack → defense (repeating cycle).
# ==================================================
extends Resource
class_name LeaderData

const ProgressionTuningProfile = preload("res://Scripts/game/tools/progression_tuning_profile.gd")

@export var id: int = -1
@export var name: String = "Leader"
@export var display_name: String = "Leader"

@export var faction_id: int = -1
@export var province_id: int = -1
@export var current_province_id: int = -1
@export var home_province_id: int = -1

@export var is_story_leader: bool = false
@export var story_id: String = ""

@export var on_mission: bool = false
@export var status: String = "idle" # idle / on_mission / injured / wounded
@export var wounded_turns_remaining: int = 0
@export var wounded_from_province_id: int = -1
@export var mission_id: String = ""              # id of the active MissionData object
@export var mission_type: String = ""
@export var mission_turns_remaining: int = 0
@export var mission_origin_province_id: int = -1

@export var leadership: int = 5
@export var attack: int = 5
@export var defense: int = 5
@export var skill_power: int = 10  # legacy field — use max_sp
@export var max_sp: int = 10       # SP per spec: 10 + (level-1)*2
@export var hp: int = 65
@export var max_hp: int = 65
@export var damage_type: String = "slash"  # slash / pierce / blunt — leader's personal weapon type
@export var speed: int = 5        # movement / initiative
@export var accuracy: int = 72    # base hit chance before evasion
@export var evasion: int = 10     # reduces attacker hit chance
@export var traits: Array[String] = []

@export var level: int = 1
@export var xp: int = 0
@export var xp_to_next_level: int = 100
@export var upkeep_cost: int = 30  # gold drained per month while assigned to a faction

# ==================================================
# Leader Architecture Cleanup
# --------------------------------------------------
# CP = total army command budget.
# max_unit_slots = hard army cap.
# army_unit_ids = referenced units assigned to this leader.
# equipped_item_id = single item slot.
# ==================================================
@export var max_cp: int = 30
@export var max_unit_slots: int = 6
@export var army_unit_ids: Array[int] = []
@export var equipped_item_id: String = ""  # empty string = no item (matches UnitData)

# Sigil system — one sigil slot per leader.
@export var equipped_sigil_id: String = ""

# Augment slot — Tier 3+ only (level 10+). Modifies the equipped sigil.
@export var equipped_augment_id: String = ""

# Signature ability — set at creation for story leaders. Matches story_id.
@export var signature_ability_id: String = ""

# Tactical layer metadata (set from StoryLeaderLibrary; used by future battle system)
@export var unit_archetype: String = ""

# Accumulated fractional stat growth (runtime only)
var _leadership_accum: float = 0.0
var _attack_accum: float = 0.0
var _defense_accum: float = 0.0
var _hp_accum: float = 0.0


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
	return profile.leader_xp_base + (current_level - 1) * profile.leader_xp_growth


func _apply_stat_growth(profile: ProgressionTuningProfile) -> void:
	_leadership_accum += profile.leader_leadership_per_level
	_attack_accum += profile.leader_attack_per_level
	_defense_accum += profile.leader_defense_per_level
	_hp_accum += profile.unit_hp_per_level  # leaders use same HP knob as units

	var lead_gain: int = int(_leadership_accum)
	var atk_gain: int = int(_attack_accum)
	var def_gain: int = int(_defense_accum)
	var hp_gain: int = int(_hp_accum)

	_leadership_accum -= lead_gain
	_attack_accum -= atk_gain
	_defense_accum -= def_gain
	_hp_accum -= hp_gain

	leadership += lead_gain
	attack += atk_gain
	defense += def_gain
	max_hp += hp_gain
	hp = mini(hp + hp_gain, max_hp)


func get_used_command_points() -> int:
	return 0


func get_effective_max_cp() -> int:
	# Base max_cp + bonus from equipped CP item
	var bonus: int = 0
	if equipped_item_id != "":
		var ItemLibrary = load("res://Scripts/data/item_library.gd")
		if ItemLibrary != null:
			var bonuses: Dictionary = ItemLibrary.get_unit_item_bonuses(equipped_item_id)
			bonus = int(bonuses.get("max_cp", 0))
	return max_cp + bonus


func has_free_unit_slot() -> bool:
	return army_unit_ids.size() < max_unit_slots


func has_unit(unit_id: int) -> bool:
	return army_unit_ids.has(unit_id)


func can_add_army_unit(unit_id: int) -> bool:
	if unit_id < 0:
		return false
	if has_unit(unit_id):
		return false
	return has_free_unit_slot()


func add_army_unit(unit_id: int) -> bool:
	if not can_add_army_unit(unit_id):
		return false
	army_unit_ids.append(unit_id)
	return true


func remove_army_unit(unit_id: int) -> bool:
	var idx: int = army_unit_ids.find(unit_id)
	if idx == -1:
		return false
	army_unit_ids.remove_at(idx)
	return true


func clear_army_units() -> void:
	army_unit_ids.clear()
