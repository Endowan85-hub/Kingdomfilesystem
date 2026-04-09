# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: AIPlanner
#
# Role:
# Generates AI planning-phase orders without mutating GameState directly.
# Implements a 19-pass monthly pipeline:
#   Pass 1  Faction Snapshot
#   Pass 2  Province Evaluation
#   Pass 3  Army Evaluation
#   Pass 4  Doctrine + Monthly Intent
#   Pass 5  Province Posture Assignment
#   Pass 6  Leader Role Assignment
#   Pass 7  Defense Reservation
#   Pass 8  Army Template Assignment
#   Pass 9  Army Deficit Analysis
#   Pass 10 Mission / Item-Hunt Screening
#   Pass 11 Recruit Candidates
#   Pass 12 Transfer Candidates
#   Pass 13 Fortify Candidates
#   Pass 14 Attack Candidates
#   Pass 15 Score All Actions
#   Pass 16 Priority Resolution Ladder
#   Pass 17 Best Non-Conflicting Selection (3 waves)
#   Pass 18 Validation Pass
#   Pass 19 Commit to OrderBook
#
# Allowed Interactions:
# - GameState (read-only)
# - MapData / ProvinceData / FactionData / RouteData
# - OrderBook (queue orders only)
# - DebugLogger (logging only)
#
# Forbidden Responsibilities:
# - Must not execute turns
# - Must not resolve combat
# - Must not mutate simulation state directly
# ==================================================

class_name AIPlanner
extends RefCounted

const UnitLibraryScript = preload("res://Scripts/data/unit_library.gd")
const ItemLibraryScript = preload("res://Scripts/data/item_library.gd")
const SigilLibraryScript = preload("res://Scripts/data/sigil_library.gd")
const AITuningProfileScript = preload("res://Scripts/game/tools/ai_tuning_profile.gd")

# --------------------------------------------------
# Global constants
# --------------------------------------------------
const MIN_GOLD_RESERVE:    int   = 150
const MIN_SOURCE_CP:       int   = 5
const MIN_ACCEPTABLE_PWIN: float = 0.35
const ITEM_HUNT_THRESHOLD: float = 0.55
const BIOME_ROLE_WEIGHT:   float = 25.0
const DEFAULT_ATTRITION_RISK_WEIGHT: float = 30.0
const DEFAULT_POST_BATTLE_HOLD_MARGIN: float = -7.0
const DEFAULT_ATTACK_HEALTH_FLOOR: float = 0.68
const DEFAULT_DAMAGED_TARGET_BONUS: float = 32.0
const DEFAULT_WOUNDED_TARGET_BONUS: float = 18.0
const DEFAULT_SOURCE_WOUNDED_CAUTION: float = 12.0
const UNIT_LEVEL_STEP: float = 0.06
const LEADER_ATTACK_STEP: float = 0.025
const LEADER_DEFENSE_STEP: float = 0.025
const LEADER_LEADERSHIP_STEP: float = 0.015
const ATTACKER_DEFENSE_WEIGHT: float = 0.35
const DEFENDER_OFFENSE_WEIGHT: float = 0.20
const TERRAIN_DEFENSE_MULT: Dictionary = {
	"plains": 1.00,
	"desert": 1.01,
	"coast": 1.02,
	"tundra": 1.03,
	"forest": 1.04,
	"swamp": 1.05,
	"mountain": 1.08,
}

# --------------------------------------------------
# Posture constants
# --------------------------------------------------
const POSTURE_SHIELD    := "shield"
const POSTURE_SPEARHEAD := "spearhead"
const POSTURE_STAGING   := "staging"
const POSTURE_HUB       := "hub"
const POSTURE_MISSION   := "mission_base"
const AI_MISSION_TYPES: Array[String] = ["talent_search", "rumor_investigation", "training_journey"]
const AI_ITEM_MISSION_TYPES: Array[String] = ["ruin_exploration", "caravan_escort"]
const AI_MISSION_IDLE_MONTHS: int = 6
const AI_MISSION_YEARLY_CAP: int = 6
const AI_MISSION_RECENT_COOLDOWN: int = 1

const POSTURE_RECOVERY  := "recovery"
const POSTURE_INTERIOR  := "interior"
const POSTURE_RESERVE   := "reserve"

# Defense floor multipliers applied to province defense CP
const FLOOR: Dictionary = {
	POSTURE_INTERIOR:  0.20,
	POSTURE_MISSION:   0.35,
	POSTURE_HUB:       0.25,
	POSTURE_STAGING:   0.40,
	POSTURE_SPEARHEAD: 0.45,
	POSTURE_RESERVE:   0.55,
	POSTURE_RECOVERY:  0.40,
	POSTURE_SHIELD:    0.75,
}

# --------------------------------------------------
# Legacy playstyle profiles (fallback if doctrine fields absent)
# --------------------------------------------------
const PLAYSTYLE_PROFILES: Dictionary = {
	"aggressive":   { "min_pwin": 0.20, "max_attacks": 3 },
	"defensive":    { "min_pwin": 0.45, "max_attacks": 1 },
	"diplomatic":   { "min_pwin": 0.35, "max_attacks": 1 },
	"economic":     { "min_pwin": 0.30, "max_attacks": 2 },
	"expansionist": { "min_pwin": 0.22, "max_attacks": 3 },
	"opportunist":  { "min_pwin": 0.35, "max_attacks": 2 },
	"balanced":     { "min_pwin": 0.28, "max_attacks": 2 },
	"calculated":   { "min_pwin": 0.38, "max_attacks": 2 },
	"fortify":      { "min_pwin": 0.45, "max_attacks": 1 },
	"conquest":     { "min_pwin": 0.15, "max_attacks": 4 },
}

# --------------------------------------------------
# Unit role weight table
# Roles: fl=frontline, sh=shock, rn=ranged, cv=cavalry_mobility,
#        sk=skirmish, ac=anti_cavalry, aa=anti_armor, ds=defense_specialist
# --------------------------------------------------


func _get_tuning_profile(state: GameState):
	if state == null:
		return null
	if state.has_method("get_ai_tuning_profile"):
		return state.get_ai_tuning_profile()
	return null


func _tuning_float(state: GameState, field_name: String, default_value: float) -> float:
	var profile = _get_tuning_profile(state)
	if profile == null:
		return default_value
	var values: Dictionary = profile.to_dictionary()
	return float(values.get(field_name, default_value))


func _tuning_int(state: GameState, field_name: String, default_value: int) -> int:
	var profile = _get_tuning_profile(state)
	if profile == null:
		return default_value
	var values: Dictionary = profile.to_dictionary()
	return int(values.get(field_name, default_value))



func _get_faction_net_income_estimate(state: GameState, faction: FactionData) -> int:
	if state == null or faction == null:
		return 0
	var upkeep: int = 0
	for lid_val in faction.leader_ids:
		var leader: LeaderData = state.get_leader(int(lid_val))
		if leader == null:
			continue
		upkeep += int(leader.upkeep_cost)
		for uid_val in leader.army_unit_ids:
			var u = state.get_unit(int(uid_val))
			if u != null:
				upkeep += int((u as UnitData).upkeep_cost)
	var income: int = int(faction.income_last_turn)
	if income <= 0:
		income = int(faction.income)
	return income - upkeep


func _get_ai_treasury_reserve(state: GameState, faction: FactionData, snap: Dictionary) -> int:
	var reserve_mult: float = _tuning_float(state, "treasury_reserve_mult", 1.0)
	var base_reserve: int = int(round(float(MIN_GOLD_RESERVE) * reserve_mult))
	var upkeep: int = int(snap.get("upkeep", 0))
	var dynamic_reserve: int = int(round(float(upkeep) * 2.0 * reserve_mult))
	if str(snap.get("risk_state", "stable")) == "crisis":
		dynamic_reserve = int(round(float(upkeep) * 3.0 * reserve_mult))
	return maxi(base_reserve, dynamic_reserve)


func _has_ai_war_surplus(state: GameState, faction: FactionData, snap: Dictionary) -> bool:
	if faction == null:
		return false
	var reserve: int = _get_ai_treasury_reserve(state, faction, snap)
	var mult: float = _tuning_float(state, "surplus_war_chest_mult", 1.6)
	return int(faction.gold) >= int(round(float(reserve) * mult))


func _is_ai_anti_stalemate_window(state: GameState, snap: Dictionary) -> bool:
	if state == null:
		return false
	if str(snap.get("risk_state", "stable")) == "crisis":
		return false
	var month_gate: int = _tuning_int(state, "anti_stalemate_month", 6)
	return int(state.month_index) >= month_gate


func _can_ai_spend(state: GameState, faction: FactionData, snap: Dictionary, cost: int, spend_kind: String) -> bool:
	if faction == null:
		return false
	var reserve: int = _get_ai_treasury_reserve(state, faction, snap)
	var net_income: int = _get_faction_net_income_estimate(state, faction)
	var projected_gold: int = int(faction.gold) - cost
	var projected_next: int = projected_gold + net_income
	if projected_gold < reserve:
		return false
	match spend_kind:
		"recruit":
			var recruit_guard: float = _tuning_float(state, "recruit_econ_guard", 1.0)
			return projected_next >= int(round(float(reserve) * (0.55 * recruit_guard)))
		"fortify":
			var fortify_guard: float = _tuning_float(state, "fortify_econ_guard", 1.0)
			return projected_next >= int(round(float(reserve) * (0.35 * fortify_guard)))
		"attack":
			var attack_guard: float = _tuning_float(state, "attack_econ_guard", 1.0)
			return projected_next >= int(round(float(reserve) * (0.75 * attack_guard)))
	return true


func _can_ai_spend_with_committed(state: GameState, faction: FactionData, snap: Dictionary, cost: int, spend_kind: String, already_committed: int) -> bool:
	if faction == null:
		return false
	var reserve: int = _get_ai_treasury_reserve(state, faction, snap)
	var net_income: int = _get_faction_net_income_estimate(state, faction)
	var projected_gold: int = int(faction.gold) - already_committed - cost
	var projected_next: int = projected_gold + net_income
	if projected_gold < reserve:
		return false
	match spend_kind:
		"recruit":
			var recruit_guard: float = _tuning_float(state, "recruit_econ_guard", 1.0)
			return projected_next >= int(round(float(reserve) * (0.55 * recruit_guard)))
		"fortify":
			var fortify_guard: float = _tuning_float(state, "fortify_econ_guard", 1.0)
			return projected_next >= int(round(float(reserve) * (0.35 * fortify_guard)))
		"attack":
			var attack_guard: float = _tuning_float(state, "attack_econ_guard", 1.0)
			return projected_next >= int(round(float(reserve) * (0.75 * attack_guard)))
	return true


func _get_leader_army_health_ratio(state: GameState, leader: LeaderData) -> float:
	if state == null or leader == null:
		return 0.0
	var total_hp: int = 0
	var total_max_hp: int = 0
	for uid_val in leader.army_unit_ids:
		var unit := state.get_unit(int(uid_val)) as UnitData
		if unit == null:
			continue
		total_hp += int(unit.hp)
		total_max_hp += int(unit.max_hp)
	if total_max_hp <= 0:
		return 1.0
	return clampf(float(total_hp) / float(total_max_hp), 0.0, 1.0)


func _get_unit_template_health_weight(unit: UnitData) -> float:
	if unit == null or int(unit.max_hp) <= 0:
		return 0.0
	var health_ratio: float = clampf(float(unit.hp) / float(unit.max_hp), 0.0, 1.0)
	if health_ratio < 0.40:
		return health_ratio * 0.35
	if health_ratio < 0.60:
		return health_ratio * 0.65
	return health_ratio


func _get_province_attack_health_ratio(state: GameState, province_id: int) -> float:
	if state == null or state.map_data == null:
		return 0.0
	var province: ProvinceData = state.map_data.provinces[province_id] as ProvinceData
	var total_ratio: float = 0.0
	var counted: int = 0
	for lid_val in province.leader_ids:
		var leader: LeaderData = state.get_leader(int(lid_val))
		if leader == null or bool(leader.on_mission):
			continue
		if str(leader.status) == "wounded" or str(leader.status) == "injured":
			continue
		total_ratio += _get_leader_army_health_ratio(state, leader)
		counted += 1
	if counted <= 0:
		return 1.0
	return clampf(total_ratio / float(counted), 0.0, 1.0)


func _get_province_total_health_ratio(state: GameState, province_id: int) -> float:
	if state == null or state.map_data == null:
		return 1.0
	var province: ProvinceData = state.map_data.provinces[province_id] as ProvinceData
	var total_hp: int = 0
	var total_max_hp: int = 0
	for lid_val in province.leader_ids:
		var leader: LeaderData = state.get_leader(int(lid_val))
		if leader == null or bool(leader.on_mission):
			continue
		if str(leader.status) == "wounded" or str(leader.status) == "injured":
			continue
		for uid_val in leader.army_unit_ids:
			var unit := state.get_unit(int(uid_val)) as UnitData
			if unit == null or int(unit.max_hp) <= 0:
				continue
			if int(unit.hp) <= 0:
				continue
			total_hp += int(unit.hp)
			total_max_hp += int(unit.max_hp)
	for uid_val in province.unit_inventory:
		var inv_unit := state.get_unit(int(uid_val)) as UnitData
		if inv_unit == null or int(inv_unit.max_hp) <= 0:
			continue
		if int(inv_unit.hp) <= 0:
			continue
		total_hp += int(inv_unit.hp)
		total_max_hp += int(inv_unit.max_hp)
	if total_max_hp <= 0:
		return 1.0
	return clampf(float(total_hp) / float(total_max_hp), 0.0, 1.0)


func _get_province_wounded_commander_count(state: GameState, province_id: int) -> int:
	if state == null or state.map_data == null:
		return 0
	var province: ProvinceData = state.map_data.provinces[province_id] as ProvinceData
	var total: int = 0
	for lid_val in province.leader_ids:
		var leader: LeaderData = state.get_leader(int(lid_val))
		if leader == null:
			continue
		var status: String = str(leader.status)
		if status == "wounded" or status == "injured":
			total += 1
	return total

const UNIT_ROLE_WEIGHTS: Dictionary = {
	# PLAINS
	"Militia Spearman":       { "fl":0.70,"sh":0.20,"rn":0.00,"cv":0.00,"sk":0.00,"ac":1.00,"aa":0.20,"ds":0.75 },
	"Veteran Spearman":       { "fl":0.75,"sh":0.25,"rn":0.00,"cv":0.00,"sk":0.00,"ac":1.00,"aa":0.25,"ds":0.80 },
	"Elite Phalanx Guard":    { "fl":0.80,"sh":0.30,"rn":0.00,"cv":0.00,"sk":0.00,"ac":1.00,"aa":0.30,"ds":0.85 },
	"Militia Swordsman":      { "fl":0.90,"sh":0.45,"rn":0.00,"cv":0.00,"sk":0.10,"ac":0.25,"aa":0.30,"ds":0.45 },
	"Veteran Infantry":       { "fl":0.95,"sh":0.50,"rn":0.00,"cv":0.00,"sk":0.10,"ac":0.30,"aa":0.35,"ds":0.50 },
	"Royal Guard":            { "fl":1.00,"sh":0.55,"rn":0.00,"cv":0.00,"sk":0.10,"ac":0.35,"aa":0.40,"ds":0.55 },
	"Militia Crossbowman":    { "fl":0.10,"sh":0.00,"rn":0.95,"cv":0.00,"sk":0.15,"ac":0.20,"aa":0.85,"ds":0.10 },
	"Veteran Crossbowman":    { "fl":0.10,"sh":0.00,"rn":1.00,"cv":0.00,"sk":0.15,"ac":0.20,"aa":0.90,"ds":0.10 },
	"Master Arbalest":        { "fl":0.10,"sh":0.00,"rn":1.00,"cv":0.00,"sk":0.15,"ac":0.25,"aa":1.00,"ds":0.10 },
	"Light Rider":            { "fl":0.25,"sh":0.60,"rn":0.00,"cv":1.00,"sk":0.25,"ac":0.10,"aa":0.35,"ds":0.05 },
	"Cavalry":                { "fl":0.30,"sh":0.70,"rn":0.00,"cv":1.00,"sk":0.20,"ac":0.10,"aa":0.40,"ds":0.05 },
	"Elite Knight":           { "fl":0.35,"sh":0.80,"rn":0.00,"cv":1.00,"sk":0.15,"ac":0.10,"aa":0.45,"ds":0.10 },
	# FOREST
	"Hunter":                 { "fl":0.10,"sh":0.00,"rn":1.00,"cv":0.00,"sk":0.35,"ac":0.10,"aa":0.20,"ds":0.05 },
	"Ranger":                 { "fl":0.10,"sh":0.00,"rn":1.00,"cv":0.00,"sk":0.40,"ac":0.10,"aa":0.25,"ds":0.05 },
	"Master Ranger":          { "fl":0.10,"sh":0.00,"rn":1.00,"cv":0.00,"sk":0.45,"ac":0.10,"aa":0.30,"ds":0.05 },
	"Forest Skirmisher":      { "fl":0.20,"sh":0.15,"rn":0.25,"cv":0.25,"sk":1.00,"ac":0.10,"aa":0.10,"ds":0.05 },
	"Pathfinder":             { "fl":0.20,"sh":0.20,"rn":0.25,"cv":0.30,"sk":1.00,"ac":0.10,"aa":0.10,"ds":0.05 },
	"Shadow Ranger":          { "fl":0.20,"sh":0.25,"rn":0.30,"cv":0.35,"sk":1.00,"ac":0.10,"aa":0.15,"ds":0.05 },
	"Forest Rider":           { "fl":0.15,"sh":0.30,"rn":0.00,"cv":0.90,"sk":0.55,"ac":0.10,"aa":0.10,"ds":0.00 },
	"Scout Captain":          { "fl":0.20,"sh":0.35,"rn":0.00,"cv":0.95,"sk":0.55,"ac":0.10,"aa":0.10,"ds":0.00 },
	"Wild Hunt Commander":    { "fl":0.25,"sh":0.40,"rn":0.00,"cv":1.00,"sk":0.60,"ac":0.10,"aa":0.15,"ds":0.00 },
	# MOUNTAIN
	"Mountain Guard":         { "fl":0.95,"sh":0.20,"rn":0.00,"cv":0.00,"sk":0.00,"ac":0.40,"aa":0.25,"ds":1.00 },
	"Veteran Shield Guard":   { "fl":0.95,"sh":0.20,"rn":0.00,"cv":0.00,"sk":0.00,"ac":0.40,"aa":0.25,"ds":1.00 },
	"Iron Phalanx":           { "fl":1.00,"sh":0.25,"rn":0.00,"cv":0.00,"sk":0.00,"ac":0.45,"aa":0.30,"ds":1.00 },
	"Stonebreaker":           { "fl":0.65,"sh":0.80,"rn":0.00,"cv":0.00,"sk":0.00,"ac":0.20,"aa":1.00,"ds":0.35 },
	"War Hammer Guard":       { "fl":0.70,"sh":0.85,"rn":0.00,"cv":0.00,"sk":0.00,"ac":0.20,"aa":1.00,"ds":0.40 },
	"Titan Guard":            { "fl":0.75,"sh":0.90,"rn":0.00,"cv":0.00,"sk":0.00,"ac":0.25,"aa":1.00,"ds":0.45 },
	"Mountain Pikeman":       { "fl":0.75,"sh":0.15,"rn":0.00,"cv":0.00,"sk":0.00,"ac":1.00,"aa":0.25,"ds":0.80 },
	"Veteran Pikeman":        { "fl":0.78,"sh":0.18,"rn":0.00,"cv":0.00,"sk":0.00,"ac":1.00,"aa":0.28,"ds":0.82 },
	"Fortress Sentinel":      { "fl":0.80,"sh":0.20,"rn":0.00,"cv":0.00,"sk":0.00,"ac":1.00,"aa":0.30,"ds":0.85 },
	# DESERT
	"Sand Raider":            { "fl":0.20,"sh":0.85,"rn":0.00,"cv":1.00,"sk":0.35,"ac":0.10,"aa":0.25,"ds":0.05 },
	"Veteran Raider":         { "fl":0.25,"sh":0.88,"rn":0.00,"cv":1.00,"sk":0.38,"ac":0.10,"aa":0.28,"ds":0.05 },
	"Desert Warlord":         { "fl":0.30,"sh":0.90,"rn":0.00,"cv":1.00,"sk":0.40,"ac":0.10,"aa":0.30,"ds":0.10 },
	"Caravan Guard":          { "fl":0.70,"sh":0.35,"rn":0.00,"cv":0.15,"sk":0.10,"ac":0.35,"aa":0.25,"ds":0.55 },
	"Veteran Guard":          { "fl":0.75,"sh":0.38,"rn":0.00,"cv":0.18,"sk":0.10,"ac":0.38,"aa":0.28,"ds":0.58 },
	"Desert Captain":         { "fl":0.80,"sh":0.40,"rn":0.00,"cv":0.20,"sk":0.10,"ac":0.40,"aa":0.30,"ds":0.60 },
	"Dune Archer":            { "fl":0.10,"sh":0.00,"rn":0.85,"cv":0.00,"sk":0.45,"ac":0.10,"aa":0.15,"ds":0.05 },
	"Veteran Archer":         { "fl":0.10,"sh":0.00,"rn":0.90,"cv":0.00,"sk":0.48,"ac":0.10,"aa":0.18,"ds":0.05 },
	"Sandstorm Sniper":       { "fl":0.10,"sh":0.00,"rn":1.00,"cv":0.00,"sk":0.50,"ac":0.10,"aa":0.20,"ds":0.05 },
	# TUNDRA
	"Ice Warrior":            { "fl":0.90,"sh":0.50,"rn":0.00,"cv":0.00,"sk":0.00,"ac":0.25,"aa":0.35,"ds":0.55 },
	"Veteran Frost Warrior":  { "fl":0.93,"sh":0.55,"rn":0.00,"cv":0.00,"sk":0.00,"ac":0.28,"aa":0.38,"ds":0.58 },
	"Frost Champion":         { "fl":0.95,"sh":0.60,"rn":0.00,"cv":0.00,"sk":0.00,"ac":0.30,"aa":0.40,"ds":0.60 },
	"Ice Archer":             { "fl":0.10,"sh":0.00,"rn":0.90,"cv":0.00,"sk":0.20,"ac":0.10,"aa":0.20,"ds":0.10 },
	"Veteran Ice Archer":     { "fl":0.10,"sh":0.00,"rn":0.93,"cv":0.00,"sk":0.22,"ac":0.10,"aa":0.22,"ds":0.10 },
	"Blizzard Ranger":        { "fl":0.10,"sh":0.00,"rn":1.00,"cv":0.00,"sk":0.25,"ac":0.10,"aa":0.25,"ds":0.10 },
	"Northern Raider":        { "fl":0.55,"sh":0.85,"rn":0.00,"cv":0.15,"sk":0.20,"ac":0.15,"aa":0.40,"ds":0.20 },
	"Veteran Raider (Tundra)":{ "fl":0.58,"sh":0.88,"rn":0.00,"cv":0.18,"sk":0.22,"ac":0.18,"aa":0.42,"ds":0.22 },
	"War Chief":              { "fl":0.60,"sh":0.90,"rn":0.00,"cv":0.20,"sk":0.25,"ac":0.20,"aa":0.45,"ds":0.25 },
	# SWAMP
	"Bog Fighter":            { "fl":0.85,"sh":0.35,"rn":0.00,"cv":0.00,"sk":0.10,"ac":0.30,"aa":0.30,"ds":0.65 },
	"Veteran Bog Fighter":    { "fl":0.88,"sh":0.38,"rn":0.00,"cv":0.00,"sk":0.12,"ac":0.33,"aa":0.33,"ds":0.68 },
	"Mire Champion":          { "fl":0.90,"sh":0.40,"rn":0.00,"cv":0.00,"sk":0.15,"ac":0.35,"aa":0.35,"ds":0.70 },
	"Reed Archer":            { "fl":0.10,"sh":0.00,"rn":0.90,"cv":0.00,"sk":0.30,"ac":0.10,"aa":0.20,"ds":0.05 },
	"Veteran Reed Archer":    { "fl":0.10,"sh":0.00,"rn":0.93,"cv":0.00,"sk":0.33,"ac":0.10,"aa":0.22,"ds":0.05 },
	"Marsh Sniper":           { "fl":0.10,"sh":0.00,"rn":1.00,"cv":0.00,"sk":0.35,"ac":0.10,"aa":0.25,"ds":0.05 },
	"Swamp Ambusher":         { "fl":0.20,"sh":0.20,"rn":0.15,"cv":0.20,"sk":1.00,"ac":0.10,"aa":0.10,"ds":0.05 },
	"Veteran Ambusher":       { "fl":0.22,"sh":0.22,"rn":0.18,"cv":0.22,"sk":1.00,"ac":0.10,"aa":0.12,"ds":0.05 },
	"Mire Stalker":           { "fl":0.25,"sh":0.25,"rn":0.20,"cv":0.25,"sk":1.00,"ac":0.10,"aa":0.15,"ds":0.05 },
	# COAST
	"Marine":                 { "fl":0.80,"sh":0.40,"rn":0.00,"cv":0.00,"sk":0.10,"ac":0.35,"aa":0.25,"ds":0.45 },
	"Veteran Marine":         { "fl":0.83,"sh":0.43,"rn":0.00,"cv":0.00,"sk":0.12,"ac":0.38,"aa":0.28,"ds":0.48 },
	"Harbor Guard":           { "fl":0.85,"sh":0.45,"rn":0.00,"cv":0.00,"sk":0.13,"ac":0.40,"aa":0.30,"ds":0.50 },
	"Harpoon Fighter":        { "fl":0.40,"sh":0.25,"rn":0.20,"cv":0.00,"sk":0.10,"ac":0.75,"aa":0.55,"ds":0.30 },
	"Veteran Harpooner":      { "fl":0.43,"sh":0.28,"rn":0.22,"cv":0.00,"sk":0.12,"ac":0.78,"aa":0.58,"ds":0.33 },
	"Leviathan Hunter":       { "fl":0.45,"sh":0.30,"rn":0.25,"cv":0.00,"sk":0.13,"ac":0.80,"aa":0.60,"ds":0.35 },
	"Boarding Infantry":      { "fl":0.65,"sh":0.75,"rn":0.00,"cv":0.00,"sk":0.10,"ac":0.20,"aa":0.35,"ds":0.20 },
	"Veteran Boarding Guard": { "fl":0.68,"sh":0.78,"rn":0.00,"cv":0.00,"sk":0.12,"ac":0.22,"aa":0.38,"ds":0.22 },
	"Sea Captain Guard":      { "fl":0.70,"sh":0.80,"rn":0.00,"cv":0.00,"sk":0.13,"ac":0.25,"aa":0.40,"ds":0.25 },
}

# --------------------------------------------------
# Army templates: role targets (0.0 = not needed, 1.0 = core requirement)
# "flex" is filled by whatever role is most missing from biome supply
# --------------------------------------------------
const ARMY_TEMPLATES: Dictionary = {
	"balanced":   { "fl":1.80,"sh":0.40,"rn":0.80,"cv":0.70,"sk":0.20,"ac":0.90,"aa":0.60,"ds":0.40 },
	"fortress":   { "fl":0.80,"sh":0.20,"rn":0.80,"cv":0.00,"sk":0.00,"ac":0.80,"aa":0.40,"ds":1.80 },
	"shock":      { "fl":0.80,"sh":1.80,"rn":0.60,"cv":0.80,"sk":0.20,"ac":0.20,"aa":0.40,"ds":0.20 },
	"skirmish":   { "fl":0.60,"sh":0.40,"rn":0.80,"cv":0.80,"sk":1.80,"ac":0.20,"aa":0.20,"ds":0.10 },
	"counter":    { "fl":0.80,"sh":0.20,"rn":0.80,"cv":0.20,"sk":0.20,"ac":0.90,"aa":0.90,"ds":0.80 },
	"marine":     { "fl":1.60,"sh":0.60,"rn":0.60,"cv":0.60,"sk":0.20,"ac":0.70,"aa":0.40,"ds":0.40 },
	"endurance":  { "fl":1.60,"sh":0.60,"rn":0.70,"cv":0.20,"sk":0.10,"ac":0.60,"aa":0.40,"ds":0.80 },
}

# Faction key → preferred template name
const FACTION_TEMPLATE: Dictionary = {
	"house_counsel":   "balanced",
	"house_war":       "shock",
	"house_crown":     "balanced",
	"house_coin":      "marine",
	"house_people":    "shock",
	"house_faith":     "fortress",
	"house_shadows":   "skirmish",
	"house_diplomacy": "balanced",
	"house_frontier":  "endurance",
	"house_law":       "counter",
	"house_strategy":  "counter",
	"house_roads":     "fortress",
	"house_blood":     "shock",
	"house_provinces": "balanced",
	"house_outsider":  "skirmish",
}


# ==================================================
# ENTRY POINT
# ==================================================

func _get_unit_active_heal_cost(state: GameState, unit_id: int) -> int:
	if state == null or not state.has_method("get_unit_active_heal_cost"):
		return -1
	return int(state.get_unit_active_heal_cost(unit_id))


func _pass0_active_healing(state: GameState, faction: FactionData, ai_id: int, owned: Array[int]) -> void:
	if state == null or faction == null or owned.is_empty():
		return
	var reserve_floor: int = maxi(150, int(faction.income) * 2)
	var healed_this_month: int = 0
	var heal_cap: int = 3
	var candidates: Array = []
	for pid in owned:
		var province: ProvinceData = state.map_data.provinces[pid] as ProvinceData
		if province == null:
			continue
		for lid_value in province.leader_ids:
			var leader: LeaderData = state.get_leader(int(lid_value))
			if leader == null:
				continue
			for uid_value in leader.army_unit_ids:
				var unit: UnitData = state.get_unit(int(uid_value))
				if unit == null or int(unit.max_hp) <= 0 or int(unit.hp) >= int(unit.max_hp):
					continue
				var hp_ratio: float = float(unit.hp) / float(unit.max_hp)
				if hp_ratio <= 0.45:
					candidates.append({"unit_id": int(unit.unit_id), "province_id": pid, "priority": (1.0 - hp_ratio) * 100.0})
		for unit in state.get_province_inventory_units(pid):
			if unit == null or int(unit.max_hp) <= 0 or int(unit.hp) >= int(unit.max_hp):
				continue
			var hp_ratio_inv: float = float(unit.hp) / float(unit.max_hp)
			if hp_ratio_inv <= 0.35:
				candidates.append({"unit_id": int(unit.unit_id), "province_id": pid, "priority": (1.0 - hp_ratio_inv) * 90.0})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("priority", 0.0)) > float(b.get("priority", 0.0)))
	for candidate in candidates:
		if healed_this_month >= heal_cap:
			break
		var unit_id: int = int(candidate.get("unit_id", -1))
		var province_id: int = int(candidate.get("province_id", -1))
		var cost: int = _get_unit_active_heal_cost(state, unit_id)
		if cost <= 0:
			continue
		if int(faction.gold) - cost < reserve_floor:
			continue
		if state.active_heal_unit(ai_id, unit_id, province_id):
			healed_this_month += 1


func plan_month(state: GameState, ai_id: int) -> void:
	if state == null or state.map_data == null:
		return

	var map_data: MapData  = state.map_data
	var ob:       OrderBook = state.order_book
	var log:      DebugLogger = state.logger

	ob.clear_orders_for_faction(ai_id)

	var faction: FactionData = _find_faction(map_data, ai_id)
	if faction == null:
		return

	# Gather owned province ids once
	var owned: Array[int] = []
	for item in map_data.provinces:
		var p: ProvinceData = item as ProvinceData
		if int(p.owner_id) == ai_id:
			owned.append(int(p.id))
	if owned.is_empty():
		return

	# --------------------------------------------------
	# Pass 0: Immediate Active Healing
	# --------------------------------------------------
	_pass0_active_healing(state, faction, ai_id, owned)

	# --------------------------------------------------
	# Pass 1: Faction Snapshot
	# --------------------------------------------------
	var snap: Dictionary = _pass1_snapshot(state, map_data, faction, ai_id, owned)

	# --------------------------------------------------
	# Pass 1b: Commander Acquisition
	# If the faction is short on leaders, immediately claim one from the
	# dismissed pool or reserve pool. Missions take too long and are blocked
	# in crisis — factions must be able to grow their leader count directly.
	# --------------------------------------------------
	_pass1b_acquire_commander(state, map_data, faction, ai_id, owned, snap)

	# --------------------------------------------------
	# Pass 2: Province Evaluation
	# --------------------------------------------------
	var peval: Dictionary = {}  # province_id(int) -> eval dict
	for pid in owned:
		peval[pid] = _pass2_eval_province(state, map_data, pid, ai_id)
	snap["front_state"] = _build_front_priority(state, map_data, faction, ai_id, owned, peval)

	# --------------------------------------------------
	# Pass 3: Army Evaluation
	# --------------------------------------------------
	var aeval: Dictionary = {}  # leader_id(int) -> eval dict
	for pid in owned:
		var p: ProvinceData = map_data.provinces[pid] as ProvinceData
		for lid_val in p.leader_ids:
			var lid: int = int(lid_val)
			var leader: LeaderData = state.get_leader(lid)
			if leader == null or bool(leader.on_mission):
				continue
			var tmpl_name: String = FACTION_TEMPLATE.get(str(faction.faction_key), "balanced")
			aeval[lid] = _pass3_eval_army(state, leader, tmpl_name)

	# --------------------------------------------------
	# Pass 4: Monthly Intent
	# --------------------------------------------------
	var intent: String = _pass4_intent(snap, peval, faction)
	if log != null:
		log.event("ai_intent", { "faction": ai_id, "intent": intent, "risk": snap["risk_state"] })

	# --------------------------------------------------
	# Pass 5: Province Posture Assignment
	# --------------------------------------------------
	for pid in owned:
		peval[pid]["posture"] = _pass5_posture(state, map_data, pid, ai_id, snap, peval)

	# --------------------------------------------------
	# Pass 6: Leader Role Assignment
	# --------------------------------------------------
	var leader_roles: Dictionary = {}  # leader_id -> role string
	for lid in aeval.keys():
		var leader: LeaderData = state.get_leader(lid)
		if leader == null:
			continue
		leader_roles[lid] = _pass6_leader_role(leader, peval, intent)

	# --------------------------------------------------
	# Pass 7: Defense Reservation
	# --------------------------------------------------
	# Compute defense floor for each province
	for pid in owned:
		var pe: Dictionary = peval[pid]
		var posture: String = str(pe.get("posture", POSTURE_INTERIOR))
		var mult: float = float(FLOOR.get(posture, 0.25))
		mult *= _tuning_float(state, "reserve_floor_mult", 1.0)
		var def_cp: int = _get_province_defense_cp(state, pid)
		var enemy_pressure: float = float(pe.get("enemy_attack_pressure", 0.0))
		if posture == POSTURE_SHIELD or posture == POSTURE_RESERVE:
			var pressure_ratio: float = enemy_pressure / maxf(1.0, float(def_cp))
			mult += clampf(pressure_ratio * _tuning_float(state, "hot_border_floor_bonus", 0.18), 0.0, 0.25)
			var active_leaders: int = _count_active_province_leaders(state, pid)
			if active_leaders >= 2 and float(pe.get("collapse_risk", 0.0)) < 0.60:
				mult *= _tuning_float(state, "noncritical_border_floor_mult", 0.92)
				if float(snap.get("neutral_ratio", 1.0)) <= _tuning_float(state, "neutral_exhaustion_ratio", 0.30):
					mult *= 0.96
		if _is_frontier_province(map_data, pid, ai_id) and _count_active_province_leaders(state, pid) <= 1:
			mult += _tuning_float(state, "single_leader_border_floor_bonus", 0.10)
		if float(pe.get("collapse_risk", 0.0)) >= 0.60:
			mult += _tuning_float(state, "collapse_floor_bonus", 0.12)
		# Cap SPEARHEAD provinces — they must retain attack headroom
		if posture == POSTURE_SPEARHEAD:
			mult = minf(mult, 0.60)
		mult = clampf(mult, 0.15, 0.95)
		pe["defense_floor"] = float(def_cp) * mult
		peval[pid] = pe

	# --------------------------------------------------
	# Pass 8: Army Template Assignment (already done in Pass 3)
	# Pass 9: Army Deficit Analysis
	# --------------------------------------------------
	for lid in aeval.keys():
		_pass9_deficit(aeval[lid])

	# --------------------------------------------------
	# Pass 10: Mission / Item-Hunt Screening
	# --------------------------------------------------
	var mission_candidates: Array = []
	var item_hunt_candidates: Array = []
	if snap["risk_state"] != "crisis":
		_pass10_mission_screening(state, map_data, faction, ai_id, owned, peval,
			leader_roles, aeval, snap, mission_candidates, item_hunt_candidates)

	# --------------------------------------------------
	# Pass 10b: AI Item Management
	# --------------------------------------------------
	# Equip items from province inventory to units before attack/recruit scoring,
	# so combat estimates reflect equipped bonuses. Sell duplicates under pressure.
	_pass10b_items(state, map_data, faction, ai_id, owned, snap)

	# --------------------------------------------------
	# Pass 10c: Promotions
	# Promote eligible units when leader level allows and gold permits.
	# --------------------------------------------------
	_pass10c_promotions(state, map_data, faction, ai_id, owned, snap)

	# --------------------------------------------------
	# Pass 11: Recruit Candidates
	# --------------------------------------------------
	var recruit_candidates: Array = []
	_pass11_recruits(state, map_data, faction, ai_id, owned, peval, aeval,
		leader_roles, snap, recruit_candidates)

	# --------------------------------------------------
	# Pass 12: Transfer Candidates (leaders moving between provinces)
	# --------------------------------------------------
	var transfer_candidates: Array = []
	_pass12_transfers(state, map_data, faction, ai_id, owned, peval,
		leader_roles, aeval, snap, transfer_candidates)

	# --------------------------------------------------
	# Pass 13: Fortify Candidates
	# --------------------------------------------------
	var fort_candidates: Array = []
	_pass13_forts(state, map_data, faction, ai_id, owned, peval, snap, fort_candidates)

	# --------------------------------------------------
	# Pass 14: Attack Candidates
	# --------------------------------------------------
	var attack_candidates: Array = []
	_pass14_attacks(state, map_data, faction, ai_id, owned, peval, aeval,
		snap, attack_candidates, log)

	# --------------------------------------------------
	# Pass 15: Score All Actions
	# --------------------------------------------------
	_pass15_score_all(faction, snap, peval, aeval,
		recruit_candidates, transfer_candidates, fort_candidates,
		attack_candidates, mission_candidates, item_hunt_candidates)

	# --------------------------------------------------
	# Pass 16 + 17: Priority Resolution + Wave Selection
	# --------------------------------------------------
	var reserved_leaders:   Dictionary = {}  # leader_id -> true
	var reserved_provinces: Dictionary = {}  # province_id -> true (as attack source)
	var reserved_targets:   Dictionary = {}  # province_id -> true (as attack target)
	var gold_spent: Array[int] = [0]  # wrapped in array so helpers mutate by reference

	# Wave 1 — Mandatory (defense-critical recruits + crisis forts)
	_commit_wave(recruit_candidates, "mandatory", faction, snap, peval,
		reserved_leaders, reserved_provinces, reserved_targets,
		gold_spent, ob, state, ai_id, log)
	_commit_forts("mandatory", fort_candidates, faction, snap, peval,
		reserved_provinces, gold_spent, ob, state, ai_id)

	# Wave 2 — Strategic (template completion recruits, transfers, reserve forts)
	_commit_wave(recruit_candidates, "strategic", faction, snap, peval,
		reserved_leaders, reserved_provinces, reserved_targets,
		gold_spent, ob, state, ai_id, log)
	_commit_transfers(transfer_candidates, faction, snap,
		reserved_leaders, reserved_provinces, gold_spent, ob, ai_id, log)
	_commit_forts("strategic", fort_candidates, faction, snap, peval,
		reserved_provinces, gold_spent, ob, state, ai_id)

	# Wave 3 — Offensive (attacks)
	_commit_attacks(attack_candidates, faction, snap, peval,
		reserved_leaders, reserved_provinces, reserved_targets,
		gold_spent, ob, state, ai_id, log)

	# Wave 4 — Optional (missions, item hunts, low-priority recruits)
	_commit_missions(mission_candidates, item_hunt_candidates, faction, snap,
		reserved_leaders, reserved_provinces, gold_spent, ob, state, ai_id, log)
	_commit_wave(recruit_candidates, "optional", faction, snap, peval,
		reserved_leaders, reserved_provinces, reserved_targets,
		gold_spent, ob, state, ai_id, log)

	var attack_quota_progress: Array = [int(reserved_targets.size())]
	_pass17_force_behavior(state, faction, ai_id, snap, peval, transfer_candidates,
		recruit_candidates, fort_candidates, attack_candidates,
		mission_candidates, item_hunt_candidates,
		reserved_leaders, reserved_provinces, reserved_targets,
		gold_spent, attack_quota_progress, ob, log)



func _pass17_force_behavior(state: GameState, faction: FactionData, ai_id: int,
		snap: Dictionary, peval: Dictionary, transfer_candidates: Array,
		recruit_candidates: Array, fort_candidates: Array, attack_candidates: Array,
		mission_candidates: Array, item_hunt_candidates: Array,
		reserved_leaders: Dictionary, reserved_provinces: Dictionary,
		reserved_targets: Dictionary, gold_spent: Array, attack_quota_progress: Array,
		ob: OrderBook, log: DebugLogger) -> void:
	if state == null or faction == null:
		return

	var neutral_ratio: float = float(snap.get("neutral_ratio", 1.0))
	var drought_limit: int = _tuning_int(state, "faction_war_drought_months", 4)
	var faction_war_drought: int = int(snap.get("months_since_faction_war", 0))
	var faction_war_window: bool = neutral_ratio <= _tuning_float(state, "neutral_exhaustion_ratio", 0.30)
	var available_leaders: int = int(snap.get("available_leaders", 0))
	var risk_state: String = str(snap.get("risk_state", "stable"))
	var month_index: int = int(state.month_index)
	var required_attacks: int = 1
	if risk_state == "stable" or risk_state == "snowball":
		required_attacks = 2
	if available_leaders <= 1 or risk_state == "crisis":
		required_attacks = 1

	var pressure_attacks: Array = []
	if month_index >= 24 or faction_war_window:
		pressure_attacks = _build_pressure_attack_candidates(state, faction, ai_id, snap, peval, attack_candidates)

	# Quota first: force enemy attacks in faction-war mode before anything else.
	if faction_war_window and faction_war_drought >= drought_limit:
		_commit_attack_quota(attack_candidates, required_attacks, faction, snap, peval,
			reserved_leaders, reserved_provinces, reserved_targets,
			gold_spent, attack_quota_progress, ob, state, ai_id, log, true)

	# If quota still not met, use transfers to open fronts, then force any legal attack.
	if int(attack_quota_progress[0]) < required_attacks:
		_commit_transfers(transfer_candidates, faction, snap,
			reserved_leaders, reserved_provinces, gold_spent, ob, ai_id, log)
		_commit_attack_quota(attack_candidates, required_attacks, faction, snap, peval,
			reserved_leaders, reserved_provinces, reserved_targets,
			gold_spent, attack_quota_progress, ob, state, ai_id, log, false)

	# Late-game override: pressure attacks bypass normal candidate gating.
	if int(attack_quota_progress[0]) < required_attacks and month_index >= 24 and not pressure_attacks.is_empty():
		_commit_attack_quota(pressure_attacks, required_attacks, faction, snap, peval,
			reserved_leaders, reserved_provinces, reserved_targets,
			gold_spent, attack_quota_progress, ob, state, ai_id, log, false)

	# Spend only after quota attempt.
	var reserve_target: int = _get_ai_treasury_reserve(state, faction, snap)
	var must_spend: bool = int(faction.gold) >= int(round(float(reserve_target) * 2.0))
	var spend_floor: int = int(round(float(int(faction.gold)) * 0.35))
	if must_spend and int(gold_spent[0]) < spend_floor:
		_commit_wave(recruit_candidates, "optional", faction, snap, peval,
			reserved_leaders, reserved_provinces, reserved_targets,
			gold_spent, ob, state, ai_id, log)
		_commit_forts("strategic", fort_candidates, faction, snap, peval,
			reserved_provinces, gold_spent, ob, state, ai_id)

	# Only after quota and transfers/spend do we allow missions.
	var reserved_count: int = reserved_leaders.size()
	var active_missions: int = int(snap.get("active_missions", 0))
	var unused_leaders: int = maxi(0, available_leaders - active_missions - reserved_count)
	if unused_leaders >= 2 and int(attack_quota_progress[0]) >= required_attacks:
		_commit_missions(mission_candidates, item_hunt_candidates, faction, snap,
			reserved_leaders, reserved_provinces, gold_spent, ob, state, ai_id, log)

	if log != null:
		log.event("ai_attack_quota", {
			"faction": ai_id,
			"required_attacks": required_attacks,
			"queued_attacks": int(attack_quota_progress[0]),
			"faction_war_window": faction_war_window,
			"faction_war_drought": faction_war_drought,
			"pressure_attack_candidates": pressure_attacks.size(),
			"unused_leaders": unused_leaders
		})

func _get_faction_mission_year(state: GameState) -> int:
	if state == null:
		return 0
	return int(floori(float(maxi(0, int(state.month_index))) / 12.0))


func _get_faction_mission_year_count(state: GameState, faction: FactionData) -> int:
	if faction == null:
		return 0
	var current_year: int = _get_faction_mission_year(state)
	var stored_year: int = int(faction.get_meta("ai_mission_year", current_year)) if faction.has_meta("ai_mission_year") else current_year
	if stored_year != current_year:
		faction.set_meta("ai_mission_year", current_year)
		faction.set_meta("ai_mission_year_count", 0)
		return 0
	return int(faction.get_meta("ai_mission_year_count", 0)) if faction.has_meta("ai_mission_year_count") else 0


func _register_faction_mission_commit(state: GameState, faction: FactionData) -> void:
	if faction == null:
		return
	var current_year: int = _get_faction_mission_year(state)
	var count: int = _get_faction_mission_year_count(state, faction)
	faction.set_meta("ai_mission_year", current_year)
	faction.set_meta("ai_mission_year_count", count + 1)
	if state != null:
		faction.set_meta("ai_last_mission_month", int(state.month_index))



# ==================================================
# PASS 1 — FACTION SNAPSHOT
# ==================================================

func _pass1b_acquire_commander(state: GameState, map_data: MapData,
		faction: FactionData, ai_id: int, owned: Array, snap: Dictionary) -> void:
	# Only acquire if genuinely short on leaders
	var target: int = state.get_target_general_count()
	var current: int = int(faction.leader_ids.size())
	if current >= target:
		return
	# Find the best province to place the new leader — prefer frontier with no leader
	var best_pid: int = -1
	for pid in owned:
		var p: ProvinceData = map_data.provinces[pid] as ProvinceData
		if p.leader_ids.is_empty():
			if _is_frontier_province(map_data, pid, ai_id):
				best_pid = pid
				break
	# Fall back to any empty province
	if best_pid < 0:
		for pid in owned:
			var p: ProvinceData = map_data.provinces[pid] as ProvinceData
			if p.leader_ids.is_empty():
				best_pid = pid
				break
	# Fall back to province with fewest leaders
	if best_pid < 0 and not owned.is_empty():
		var min_leaders: int = 999
		for pid in owned:
			var p: ProvinceData = map_data.provinces[pid] as ProvinceData
			if p.leader_ids.size() < min_leaders:
				min_leaders = p.leader_ids.size()
				best_pid = pid
	if best_pid < 0:
		return
	# Try dismissed pool first (these are experienced generals)
	var pool: Array = state.dismissed_general_pool as Array
	if not pool.is_empty():
		state.claim_dismissed_general(ai_id, best_pid)
		return
	# Try reserve pool for this faction
	var reserve: Dictionary = state.reserve_general_pool_by_faction as Dictionary
	var faction_key: String = str(faction.faction_key)
	var faction_pool: Array = reserve.get(faction_key, reserve.get(str(ai_id), [])) as Array
	if not faction_pool.is_empty():
		# Reserve pool leaders are assigned by mission_resolver normally,
		# but we can directly place one here for the AI
		var new_leader: LeaderData = faction_pool.pop_front() as LeaderData
		if new_leader != null:
			new_leader.faction_id = ai_id
			new_leader.current_province_id = best_pid
			new_leader.province_id = best_pid
			new_leader.status = "idle"
			state.leaders.append(new_leader)
			new_leader.id = state.leaders.size() - 1
			state._assign_leader_to_faction_and_province(new_leader)
			if state.logger != null:
				state.logger.event("ai_general_acquired", {
					"faction": ai_id,
					"province": best_pid,
					"source": "reserve_pool",
					"shortage": target - current,
				})


func _pass1_snapshot(state: GameState, map_data: MapData, faction: FactionData,
		ai_id: int, owned: Array) -> Dictionary:
	var wounded: int = 0
	var active_missions: int = 0
	var available: int = 0
	var biome_cov: Dictionary = {}
	var crisis_provs: Array = []
	var frontier: int = 0

	# Upkeep: sum actual upkeep_cost of all units under this faction's leaders
	var upkeep: int = 0
	for lid_val in faction.leader_ids:
		var leader: LeaderData = state.get_leader(int(lid_val))
		if leader == null:
			continue
		if str(leader.status) == "wounded":
			wounded += 1
		if bool(leader.on_mission):
			active_missions += 1
		else:
			available += 1
		# Leader salary
		upkeep += int(leader.upkeep_cost)
		for uid_val in leader.army_unit_ids:
			var u = state.get_unit(int(uid_val))
			if u != null:
				upkeep += int((u as UnitData).upkeep_cost)

	for pid in owned:
		var p: ProvinceData = map_data.provinces[pid] as ProvinceData
		var biome: String = str(p.biome)
		biome_cov[biome] = int(biome_cov.get(biome, 0)) + 1
		if _is_frontier_province(map_data, pid, ai_id):
			frontier += 1

	# Calculate income from owned provinces — faction.income is set by economy_resolver
	# which runs AFTER ai_planner, so it is stale or 0 at planning time
	var income: int = 0
	for pid2 in owned:
		var p2: ProvinceData = map_data.provinces[pid2] as ProvinceData
		if p2 != null:
			income += int(p2.income)
	if income == 0:
		income = maxi(int(faction.income_last_turn), int(faction.income))
	var gold_pressure: float = 0.0
	if income > 0:
		gold_pressure = float(upkeep) / float(income)

	# Item need: simplified — based on equipped items vs leaders
	var total_leaders: int = faction.leader_ids.size()
	var equipped: int = 0
	for lid_val in faction.leader_ids:
		var leader: LeaderData = state.get_leader(int(lid_val))
		if leader != null and int(leader.equipped_item_id) >= 0:
			equipped += 1
	var item_need: float = clampf(
		(float(total_leaders - equipped) / maxf(1.0, float(total_leaders))) * 0.8
		+ faction.item_hunting_bias * 0.2, 0.0, 1.0)

	# Risk state
	var risk_state: String = "stable"
	# A faction with large gold reserves is "pressured" not "crisis" even if
	# upkeep exceeds income — they have runway to act, not a true emergency.
	var base_reserve: int = maxi(int(MIN_GOLD_RESERVE), int(round(float(upkeep) * 2.0)))
	var is_gold_rich: bool = int(faction.gold) >= base_reserve * 3
	if (gold_pressure > 0.95 and not is_gold_rich) or wounded >= 2 or crisis_provs.size() >= 2:
		risk_state = "crisis"
	elif gold_pressure > 0.75 or frontier >= int(owned.size()):
		risk_state = "pressured"
	elif owned.size() >= 8 and available >= 3:
		risk_state = "snowball"

	var months_since_offense: int = int(faction.get_meta("months_since_offense", 0)) if faction.has_meta("months_since_offense") else 0
	var months_since_faction_war: int = int(faction.get_meta("months_since_faction_war", 0)) if faction.has_meta("months_since_faction_war") else 0
	var neutral_provinces: int = 0
	for province_item in map_data.provinces:
		var neutral_check: ProvinceData = province_item as ProvinceData
		if neutral_check != null and int(neutral_check.owner_id) < 0:
			neutral_provinces += 1
	var neutral_ratio: float = float(neutral_provinces) / maxf(1.0, float(map_data.provinces.size()))
	var target_general_count: int = state.get_target_general_count()
	var commander_shortage: int = maxi(0, target_general_count - total_leaders)
	var commander_surplus: int = maxi(0, total_leaders - target_general_count)

	var mission_capacity: int = 0
	# Stable/snowball: 1 spare leader is enough to send on a mission
	if available >= 1 and risk_state in ["stable", "snowball"]:
		mission_capacity = 1
	# Stable/snowball with real surplus: can afford 2 missions
	if available >= 2 and risk_state in ["stable", "snowball"]:
		mission_capacity = 2
	# Pressured: only send if 2+ spare (1 stays for defense)
	if available >= 2 and risk_state == "pressured":
		mission_capacity = maxi(mission_capacity, 1)
	# Crisis: no missions — everyone defends
	if risk_state == "crisis":
		mission_capacity = 0
	# Threatened with only 1 spare: keep them for defense
	if available <= 1 and risk_state == "pressured":
		mission_capacity = 0
	# Commander shortage bonus: always worth recruiting via hunt even under pressure
	if commander_shortage > 0 and available >= 1 and risk_state not in ["crisis"]:
		mission_capacity = maxi(mission_capacity, 1)
	var mission_year_count: int = _get_faction_mission_year_count(state, faction)
	var mission_year_cap_remaining: int = maxi(0, AI_MISSION_YEARLY_CAP - mission_year_count)
	mission_capacity = mini(mission_capacity, mission_year_cap_remaining)
	var last_mission_month: int = int(faction.get_meta("ai_last_mission_month", -99)) if faction.has_meta("ai_last_mission_month") else -99
	var months_since_mission: int = int(state.month_index) - last_mission_month
	if mission_capacity > 0 and months_since_mission >= 0 and months_since_mission < AI_MISSION_RECENT_COOLDOWN:
		mission_capacity = 0

	return {
		"gold":              int(faction.gold),
		"upkeep":            upkeep,
		"gold_pressure":     gold_pressure,
		"wounded_leaders":   wounded,
		"active_missions":   active_missions,
		"available_leaders": available,
		"owned_provinces":   owned,
		"frontier_count":    frontier,
		"crisis_provinces":  crisis_provs,
		"item_need":         item_need,
		"biome_coverage":    biome_cov,
		"risk_state":        risk_state,
		"target_general_count": target_general_count,
		"commander_shortage": commander_shortage,
		"commander_surplus": commander_surplus,
		"months_since_offense": months_since_offense,
		"months_since_faction_war": months_since_faction_war,
		"neutral_ratio": neutral_ratio,
		"mission_capacity":  mission_capacity,
		"mission_year_count": mission_year_count,
		"mission_year_cap_remaining": mission_year_cap_remaining,
		"months_since_mission": months_since_mission,
		"income":            income,
	}


# ==================================================
# PASS 2 — PROVINCE EVALUATION
# ==================================================

func _pass2_eval_province(state: GameState, map_data: MapData,
		pid: int, ai_id: int) -> Dictionary:
	var p: ProvinceData = map_data.provinces[pid] as ProvinceData

	# Friendly defense power
	var friendly_def: int = _get_province_defense_cp(state, pid)

	# Enemy attack pressure from adjacent enemy provinces
	var enemy_pressure: float = 0.0
	for adj_id in _get_adjacent(map_data, pid):
		var adj: ProvinceData = map_data.provinces[adj_id] as ProvinceData
		if int(adj.owner_id) != ai_id and int(adj.owner_id) >= 0:
			var enemy_cp: int = _get_province_attack_cp(state, adj_id)
			enemy_pressure += float(enemy_cp)

	var hold_score: float = float(friendly_def) - enemy_pressure * 0.8
	var collapse_risk: float = 0.0
	if hold_score < 0.0:
		collapse_risk = minf(1.0, (-hold_score) / maxf(1.0, float(friendly_def) + 1.0))
		# Chokepoints are higher risk if underdefended
		collapse_risk += (0.2 if bool(p.is_chokepoint) else 0.0)
		# Removed: income bonus was incorrectly making rich provinces more likely to shield
		collapse_risk = clampf(collapse_risk, 0.0, 1.0)

	# Mission safety: no enemy pressure and at least one other leader present
	var leader_count: int = 0
	for lid_val in p.leader_ids:
		var l: LeaderData = state.get_leader(int(lid_val))
		if l != null and not bool(l.on_mission):
			leader_count += 1
	var mission_safe: bool = (enemy_pressure < 10.0 and leader_count >= 1)

	# Biome supply (role strengths available from this biome's units)
	var biome_supply: Dictionary = _biome_supply(str(p.biome))

	return {
		"id":                    pid,
		"enemy_attack_pressure": enemy_pressure,
		"friendly_defense_power":float(friendly_def),
		"hold_score":            hold_score,
		"collapse_risk":         collapse_risk,
		"mission_safety":        mission_safe,
		"biome_supply":          biome_supply,
		"posture":               POSTURE_INTERIOR,
		"defense_floor":         0.0,
	}


# ==================================================
# PASS 3 — ARMY EVALUATION
# ==================================================

func _pass3_eval_army(state: GameState, leader: LeaderData,
		tmpl_name: String) -> Dictionary:
	var template: Dictionary = ARMY_TEMPLATES.get(tmpl_name, ARMY_TEMPLATES["balanced"])
	var role_totals: Dictionary = { "fl":0.0,"sh":0.0,"rn":0.0,"cv":0.0,
		"sk":0.0,"ac":0.0,"aa":0.0,"ds":0.0 }

	var damaged_units: int = 0
	var severe_injuries: int = 0
	var injured_role_flags: Dictionary = {}

	for uid_val in leader.army_unit_ids:
		var u = state.get_unit(int(uid_val))
		if u == null:
			continue
		var unit: UnitData = u as UnitData
		var utype: String = str(unit.unit_type)
		var weights: Dictionary = UNIT_ROLE_WEIGHTS.get(utype, {})
		var health_weight: float = _get_unit_template_health_weight(unit)
		if int(unit.hp) < int(unit.max_hp):
			damaged_units += 1
		if float(unit.hp) / maxf(1.0, float(unit.max_hp)) < 0.40:
			severe_injuries += 1
			for role_key in weights.keys():
				if float(weights.get(role_key, 0.0)) >= 0.60:
					injured_role_flags[str(role_key)] = true
		for role in role_totals.keys():
			role_totals[role] = float(role_totals[role]) + float(weights.get(role, 0.0)) * health_weight

	# Completion: how well each template target is met
	var total_target: float = 0.0
	var total_filled: float = 0.0
	for role in template.keys():
		var target: float = float(template[role])
		total_target += target
		total_filled += minf(float(role_totals.get(role, 0.0)), target)
	var completion: float = total_filled / maxf(1.0, total_target)

	var missing_roles: Array = []
	var excess_roles: Array = []
	for role in template.keys():
		var gap: float = float(template[role]) - float(role_totals.get(role, 0.0))
		if injured_role_flags.has(str(role)):
			gap = maxf(gap, 0.35)
		if gap > 0.3:
			missing_roles.append({ "role": role, "gap": gap })
		elif gap < -0.5:
			excess_roles.append(role)
	missing_roles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["gap"]) > float(b["gap"]))

	var used_cp: int = state.get_leader_used_cp(leader)
	var replacement_risk: float = 0.0
	if int(leader.army_unit_ids.size()) > 0:
		replacement_risk = float(int(leader.level) - 1) * 0.15
	var health_ratio: float = _get_leader_army_health_ratio(state, leader)
	var attack_ready: bool = completion >= 0.60 and health_ratio >= 0.68 and severe_injuries < 2
	var defense_ready: bool = completion >= 0.40 or health_ratio >= 0.70

	return {
		"leader_id":        int(leader.id),
		"template":         tmpl_name,
		"completion_score": completion,
		"role_totals":      role_totals,
		"missing_roles":    missing_roles,
		"excess_roles":     excess_roles,
		"attack_ready":     attack_ready,
		"defense_ready":    defense_ready,
		"replacement_risk": replacement_risk,
		"used_cp":          used_cp,
		"health_ratio":     health_ratio,
		"damaged_units":    damaged_units,
		"severe_injuries":  severe_injuries,
	}


# ==================================================
# PASS 4 — MONTHLY INTENT
# ==================================================

func _pass4_intent(snap: Dictionary, peval: Dictionary,
		faction: FactionData) -> String:
	var risk: String = str(snap.get("risk_state", "stable"))
	var gold_pressure: float = float(snap.get("gold_pressure", 0.0))
	var wounded: int = int(snap.get("wounded_leaders", 0))
	var available: int = int(snap.get("available_leaders", 0))
	var frontier: int = int(snap.get("frontier_count", 0))
	var owned_count: int = (snap.get("owned_provinces", []) as Array).size()

	if risk == "crisis":
		if wounded >= 2:
			return "recover_leaders"
		# Surplus escape: even in crisis, a gold-rich faction can attack.
		# Prevents permanently cash-flow-negative factions from total paralysis.
		var crisis_reserve: int = _get_ai_treasury_reserve(null, faction, snap)
		if int(faction.gold) >= int(round(float(crisis_reserve) * 3.0)):
			pass  # Fall through to normal intent selection
		else:
			return "border_defense"

	if gold_pressure > 0.80:
		# Surplus escape: if faction is sitting on a large gold reserve,
		# let them attack regardless of income/upkeep ratio.
		# This prevents the gold-hoarding freeze seen in long runs.
		var reserve: int = _get_ai_treasury_reserve(null, faction, snap)
		var surplus_escape_mult: float = 3.0
		if int(faction.gold) >= int(round(float(reserve) * surplus_escape_mult)):
			pass  # Fall through to normal intent selection below
		else:
			return "economy_stabilize"

	# Count armies ready to attack
	var ready_attackers: int = 0
	for pid_val in peval.keys():
		var pe: Dictionary = peval[int(pid_val)]
		if float(pe.get("hold_score", 0.0)) > 5.0:
			ready_attackers += 1

	if risk == "snowball" and ready_attackers >= 2 and faction.aggression >= 0.65:
		return "decisive_offensive"

	if risk == "pressured":
		if frontier >= 4 and faction.border_security >= 0.65:
			return "border_defense"
		if faction.aggression >= 0.60:
			return "controlled_expansion"
		return "recruit_push"

	# Stable
	if float(snap.get("item_need", 0.0)) > ITEM_HUNT_THRESHOLD and available >= 2 and faction.item_hunting_bias >= 0.55:
		return "item_hunt"
	if faction.fortify_bias >= 0.70 and gold_pressure < 0.50:
		return "fortify_front"
	if faction.mission_bias >= 0.65 and available >= 2:
		return "mission_focus"
	if faction.aggression >= 0.55 and ready_attackers >= 1:
		return "controlled_expansion"
	return "recruit_push"


# ==================================================
# PASS 5 — PROVINCE POSTURE
# ==================================================

func _pass5_posture(state: GameState, map_data: MapData, pid: int, ai_id: int,
		snap: Dictionary, peval: Dictionary) -> String:
	var pe: Dictionary = peval[pid]
	var p: ProvinceData = map_data.provinces[pid] as ProvinceData

	# Collapse risk → Shield — only lock down when genuinely overwhelmed
	if float(pe.get("collapse_risk", 0.0)) > 0.55:
		return POSTURE_SHIELD

	var is_border: bool = _is_frontier_province(map_data, pid, ai_id)

	# Wounded leaders → Recovery
	for lid_val in p.leader_ids:
		var l: LeaderData = state.get_leader(int(lid_val))
		if l != null and str(l.status) == "wounded":
			return POSTURE_RECOVERY

	# Border with attack pressure → Shield
	# Raised from 10 → 20: small-map armies routinely exceed 10 pressure,
	# permanently locking border provinces and preventing all attacks
	if is_border and float(pe.get("enemy_attack_pressure", 0.0)) > 20.0:
		return POSTURE_SHIELD

	# Safe, well-connected interior → Reserve
	var connections: int = _count_adjacent_all(map_data, pid)
	if not is_border and connections >= 3:
		return POSTURE_RESERVE

	# Border with positive hold → Spearhead if attacking intent
	if is_border and float(pe.get("hold_score", 0.0)) > 5.0:
		var adj_enemies: Array[int] = _adjacent_enemies_or_neutral(map_data, pid, ai_id)
		if not adj_enemies.is_empty():
			return POSTURE_SPEARHEAD
	# Border with a leader but thin/no army → Spearhead anyway so transfers fill it
	# Without this, empty frontier provinces never receive leaders or generate attacks
	if is_border:
		var p_check: ProvinceData = map_data.provinces[pid] as ProvinceData
		if not p_check.leader_ids.is_empty():
			var adj_enemies2: Array[int] = _adjacent_enemies_or_neutral(map_data, pid, ai_id)
			if not adj_enemies2.is_empty():
				return POSTURE_SPEARHEAD

	# Behind a Spearhead/Shield → Staging
	for adj_id in _get_adjacent(map_data, pid):
		if peval.has(adj_id):
			var adj_posture: String = str(peval[adj_id].get("posture", ""))
			if adj_posture == POSTURE_SPEARHEAD or adj_posture == POSTURE_SHIELD:
				return POSTURE_STAGING

	# Safe province, idle leaders, not border → Mission Base
	if not is_border and bool(pe.get("mission_safety", false)):
		return POSTURE_MISSION

	# High biome value interior → Hub
	var supply: Dictionary = pe.get("biome_supply", {}) as Dictionary
	var supply_sum: float = 0.0
	for v in supply.values():
		supply_sum += float(v)
	if not is_border and supply_sum > 3.0:
		return POSTURE_HUB

	return POSTURE_INTERIOR


# ==================================================
# PASS 6 — LEADER ROLE ASSIGNMENT
# ==================================================

func _pass6_leader_role(leader: LeaderData, peval: Dictionary,
		intent: String) -> String:
	if str(leader.status) == "wounded":
		return "recovery_hold"

	var atk: int = int(leader.attack)
	var def: int = int(leader.defense)
	var ldr: int = int(leader.leadership)
	var traits: Array[String] = leader.traits

	# Province posture of current location
	var pid: int = int(leader.current_province_id)
	var posture: String = str(peval.get(pid, {}).get("posture", POSTURE_INTERIOR))

	if posture == POSTURE_SHIELD and def >= 6:
		return "defense_commander"
	if posture == POSTURE_SPEARHEAD and atk >= 6:
		return "assault_commander"

	# Trait-based
	if traits.has("Scout") or traits.has("Cunning"):
		return "item_hunter" if intent == "item_hunt" else "mission_specialist"
	if ldr >= 7 and def >= 6:
		return "trainer"
	if ldr >= 7:
		return "recruiter"
	if atk >= 7:
		return "assault_commander"
	if def >= 7:
		return "defense_commander"
	if false:  # magic removed
		return "mission_specialist"

	return "reserve_commander"


# ==================================================
# PASS 9 — ARMY DEFICIT ANALYSIS
# ==================================================

func _pass9_deficit(ae: Dictionary) -> void:
	# Missing roles are already sorted by gap descending in Pass 3.
	# We just annotate a biome_need list here for Pass 11/12 to use.
	var needs: Array = []
	for mr in ae.get("missing_roles", []) as Array:
		needs.append(str(mr.get("role", "")))
	ae["priority_roles"] = needs


# ==================================================
# PASS 10 — MISSION / ITEM-HUNT SCREENING
# ==================================================

func _pass10_mission_screening(state: GameState, map_data: MapData,
		faction: FactionData, ai_id: int, owned: Array, peval: Dictionary,
		leader_roles: Dictionary, aeval: Dictionary, snap: Dictionary,
		mission_out: Array, item_out: Array) -> void:

	var mission_capacity: int = int(snap.get("mission_capacity", 0))
	if mission_capacity <= 0:
		return

	# Score weights by mission type — AI priorities
	var type_base_score: Dictionary = {
		"elite":         95.0,
		"hunt_capture":  90.0,
		"hunt_rescue":   85.0,
		"treasure":      60.0,
		"skirmish":      40.0,
	}

	for pid in owned:
		var pe: Dictionary = peval[pid]
		if not bool(pe.get("mission_safety", false)):
			continue
		var p: ProvinceData = map_data.provinces[pid] as ProvinceData

		# Find available missions in this province
		var province_missions: Array = []
		for mid in p.active_missions:
			var mission = state.active_missions.get(mid, null)
			if mission == null:
				continue
			if str(mission.phase) != "available":
				continue
			var mtype: String = str(mission.mission_type)
			var base: float = float(type_base_score.get(mtype, 30.0))
			# Bonus: need more generals → weight hunt higher
			if (mtype == "hunt_capture" or mtype == "hunt_rescue") and int(snap.get("commander_shortage", 0)) > 0:
				base += 25.0
			# Bonus: low items → weight treasure higher
			if mtype == "treasure" and float(snap.get("item_need", 0.0)) > ITEM_HUNT_THRESHOLD:
				base += 20.0
			# Risk penalty for low-strength factions
			var risk: String = str(mission.risk_level)
			if risk == "high" and float(snap.get("army_strength_ratio", 1.0)) < 0.6:
				base -= 30.0
			province_missions.append({
				"instance_id": str(mid),
				"mission_type": mtype,
				"score": base,
			})

		if province_missions.is_empty():
			continue

		# Sort missions by score descending
		province_missions.sort_custom(func(a, b): return float(a.score) > float(b.score))

		# Match idle leaders to best available missions
		for lid_val in p.leader_ids:
			var lid: int = int(lid_val)
			var leader: LeaderData = state.get_leader(lid)
			if leader == null or bool(leader.on_mission) or str(leader.status) == "wounded":
				continue
			# Primary attackers can take elite missions — too valuable to skip
			var role: String = str(leader_roles.get(lid, "reserve_commander"))
			var best_mission_type: String = str(province_missions[0].get("mission_type", ""))
			if role == "primary_attacker" and best_mission_type != "elite":
				continue
			# Pick best mission for this leader
			for pm in province_missions:
				mission_out.append({
					"leader_id":    lid,
					"province_id":  pid,
					"instance_id":  str(pm.get("instance_id", "")),
					"mission_type": str(pm.get("mission_type", "")),
					"score":        float(pm.get("score", 0.0)),
					"wave":         "optional",
				})
				break  # one mission candidate per leader


# ==================================================
# PASS 11 — RECRUIT CANDIDATES
# ==================================================


# ==================================================
# PASS 10b — AI ITEM MANAGEMENT
# ==================================================
# Equip available items from province inventory to units in the same province.
# Priority: fill empty slots → best units first → role matching.
# Sell duplicate low-tier equipment under economic pressure.
# Buy modest consumables when surplus allows.
# AI only equips locally — no cross-province item logistics in V1.

func _pass10b_items(state: GameState, map_data: MapData, faction: FactionData,
		ai_id: int, owned: Array, snap: Dictionary) -> void:
	if state == null or map_data == null:
		return
	var gold_pressure: float = float(snap.get("gold_pressure", 0.0))
	var reserve: int = _get_ai_treasury_reserve(state, faction, snap)

	for pid in owned:
		var province: ProvinceData = map_data.provinces[pid] as ProvinceData
		if province == null:
			continue

		# ── Sell duplicates under pressure ──────────────────
		if gold_pressure >= 0.70:
			_ai_sell_excess_items(state, province, faction, gold_pressure)

		# ── Buy consumables when surplus allows ─────────────
		if gold_pressure < 0.40 and int(faction.gold) > reserve * 2:
			_ai_buy_consumables(state, province, faction)

		# ── Equip items to units ────────────────────────────
		if province.item_inventory.is_empty():
			continue

		# Collect all active units in this province across all leaders
		var unit_candidates: Array = []
		for lid_val in province.leader_ids:
			var leader: LeaderData = state.get_leader(int(lid_val))
			if leader == null or bool(leader.on_mission):
				continue
			for uid_val in leader.army_unit_ids:
				var unit: UnitData = state.get_unit(int(uid_val)) as UnitData
				if unit != null and unit.is_alive():
					unit_candidates.append(unit)

		# Equip items to leaders in this province
		for lid_val in province.leader_ids:
			var leader: LeaderData = state.get_leader(int(lid_val))
			if leader == null or bool(leader.on_mission):
				continue
			# Find best equipment item for this leader
			var best_item_id: String = ""
			var best_tier: int = 0
			for item_entry in province.item_inventory.duplicate():
				var entry := item_entry as Dictionary
				var item_id: String = str(entry.get("item_id", ""))
				if item_id == "" or not ItemLibraryScript.is_valid_id(item_id):
					continue
				if ItemLibraryScript.is_consumable(item_id):
					continue
				var tier: int = ItemLibraryScript.get_tier(item_id)
				# Only consider if strictly better than what leader already has
				var current_tier: int = 0
				if str(leader.equipped_item_id) != "":
					current_tier = ItemLibraryScript.get_tier(str(leader.equipped_item_id))
				if tier > best_tier and tier > current_tier:
					best_tier = tier
					best_item_id = item_id
			if best_item_id != "":
				# Return old item to province inventory before equipping new one
				if str(leader.equipped_item_id) != "":
					province.add_item(str(leader.equipped_item_id), 1)
				leader.equipped_item_id = best_item_id
				province.remove_item(best_item_id, 1)
				DebugLogger.log("event:item_equipped", {
					"leader_id": int(leader.id), "item_id": best_item_id, "province_id": pid, "slot": "leader"
				})

		if unit_candidates.is_empty():
			continue

		# Sort units: higher level + active = higher priority
		unit_candidates.sort_custom(func(a: UnitData, b: UnitData) -> bool:
			return int(a.level) > int(b.level)
		)

		# Equip items to units that lack them
		for item_entry in province.item_inventory.duplicate():
			var entry := item_entry as Dictionary
			var item_id: String = str(entry.get("item_id", ""))
			if item_id == "" or not ItemLibraryScript.is_valid_id(item_id):
				continue
			if ItemLibraryScript.is_consumable(item_id):
				continue  # consumables: no passive equip in V1
			var effect_type: String = ItemLibraryScript.get_effect_type(item_id)
			# Find best unit to receive this item
			var best_unit: UnitData = null
			var best_score: float = -1.0
			for unit in unit_candidates:
				var unit_data := unit as UnitData
				# Skip if already has same-or-better subtype item
				if str(unit_data.equipped_item_id) != "":
					var current_effect: String = ItemLibraryScript.get_effect_type(str(unit_data.equipped_item_id))
					var current_tier: int = ItemLibraryScript.get_tier(str(unit_data.equipped_item_id))
					var new_tier: int = ItemLibraryScript.get_tier(item_id)
					# Only replace if strictly better (same effect type, higher tier)
					if current_effect != effect_type or new_tier <= current_tier:
						continue
				# Score by level + role match
				var score: float = float(unit_data.level) * 1.0
				# Role matching bonus
				match effect_type:
					"attack_bonus":
						if str(unit_data.damage_type) == "slash" or int(unit_data.attack) >= int(unit_data.defense):
							score += 5.0
					"defense_bonus":
						if int(unit_data.defense) >= int(unit_data.attack):
							score += 5.0
					"hp_bonus":
						if int(unit_data.max_hp) <= 20:
							score += 3.0
				if score > best_score:
					best_score = score
					best_unit = unit_data
			if best_unit != null:
				best_unit.equipped_item_id = item_id
				province.remove_item(item_id, 1)
				DebugLogger.log("event:item_equipped", {
					"unit_id": int(best_unit.unit_id), "item_id": item_id, "province_id": pid
				})

		# ── Equip sigils from province inventory ────────────────
		if not province.sigil_inventory.is_empty():
			_ai_equip_sigils(state, province)


func _ai_equip_sigils(state: GameState, province: ProvinceData) -> void:
	# Equip sigils from province inventory to leaders/units with empty sigil slots
	# Leaders get priority, then units matched by tag
	var sigil_inventory: Array = province.sigil_inventory.duplicate()
	for sigil_id in sigil_inventory:
		var sig: Dictionary = SigilLibraryScript.get_sigil(str(sigil_id))
		if sig.is_empty():
			continue
		var sig_tier: int = int(sig.get("tier", 1))
		var equipped: bool = false
		# Leaders first — highest value recipients
		for lid_val in province.leader_ids:
			if equipped:
				break
			var leader: LeaderData = state.get_leader(int(lid_val))
			if leader == null or bool(leader.on_mission):
				continue
			if str(leader.equipped_sigil_id) != "":
				continue
			var leader_tier: int = 1 if int(leader.level) < 5 else (2 if int(leader.level) < 10 else 3)
			if sig_tier > leader_tier:
				continue
			leader.equipped_sigil_id = str(sigil_id)
			province.remove_sigil(str(sigil_id))
			DebugLogger.log("event:sigil_equipped", {
				"leader_id": int(leader.id), "sigil_id": str(sigil_id),
				"province_id": int(province.id), "slot": "leader"
			})
			equipped = true
		if equipped:
			continue
		# Units — match by tag and tier compatibility
		for lid_val in province.leader_ids:
			if equipped:
				break
			var leader: LeaderData = state.get_leader(int(lid_val))
			if leader == null or bool(leader.on_mission):
				continue
			for uid_val in leader.army_unit_ids:
				if equipped:
					break
				var unit: UnitData = state.get_unit(int(uid_val)) as UnitData
				if unit == null or not unit.is_alive():
					continue
				if str(unit.equipped_sigil_id) != "":
					continue
				var allowed_tags: Array = unit.allowed_tags
				if not SigilLibraryScript.can_equip(str(sigil_id), int(unit.tier), allowed_tags):
					continue
				unit.equipped_sigil_id = str(sigil_id)
				province.remove_sigil(str(sigil_id))
				DebugLogger.log("event:sigil_equipped", {
					"unit_id": int(unit.unit_id), "sigil_id": str(sigil_id),
					"province_id": int(province.id), "slot": "unit"
				})
				equipped = true


func _ai_sell_excess_items(state: GameState, province: ProvinceData,
		faction: FactionData, gold_pressure: float) -> void:
	# Sell duplicate Tier 1 items and clearly excess inventory under pressure
	var sell_threshold: int = 1 if gold_pressure >= 0.85 else 2
	var seen_subtypes: Dictionary = {}
	for item_entry in province.item_inventory.duplicate():
		var entry := item_entry as Dictionary
		var item_id: String = str(entry.get("item_id", ""))
		if item_id == "" or ItemLibraryScript.is_consumable(item_id):
			continue
		var tier: int = ItemLibraryScript.get_tier(item_id)
		if tier > 2:
			continue  # never auto-sell Tier 3+
		var subtype: String = str(ItemLibraryScript.get_item(item_id).get("subtype", ""))
		var count: int = int(entry.get("quantity", 0))
		if count > sell_threshold:
			var to_sell: int = count - sell_threshold
			for _i in range(to_sell):
				state.sell_item_from_province(int(province.id), item_id, int(faction.id))


func _ai_buy_consumables(state: GameState, province: ProvinceData,
		faction: FactionData) -> void:
	# Buy modest consumables — caps per province from ItemLibrary
	var caps: Dictionary = ItemLibraryScript.AI_BUY_CAPS
	for item_id in caps.keys():
		var cap: int = int(caps[item_id])
		var current: int = province.get_item_quantity(str(item_id))
		if current < cap:
			state.buy_item_for_province(int(province.id), str(item_id), int(faction.id))


func _pass10c_promotions(state: GameState, map_data: MapData, faction: FactionData,
		ai_id: int, owned: Array, snap: Dictionary) -> void:
	# Promote eligible units: unit level >= threshold, leader level allows tier, gold permits.
	# Only promote when not under heavy gold pressure.
	var gold_pressure: float = float(snap.get("gold_pressure", 0.0))
	if gold_pressure >= 0.70:
		return

	for pid in owned:
		var province: ProvinceData = map_data.provinces[pid] as ProvinceData
		if province == null:
			continue
		for lid_val in province.leader_ids:
			var leader: LeaderData = state.get_leader(int(lid_val))
			if leader == null or bool(leader.on_mission) or str(leader.status) == "wounded":
				continue
			var leader_level: int = int(leader.level)
			for uid_val in leader.army_unit_ids:
				var unit: UnitData = state.get_unit(int(uid_val)) as UnitData
				if unit == null or not unit.is_alive():
					continue
				var tier: int = int(unit.tier)
				# Check unit level threshold
				var required_unit_level: int = 5 if tier == 1 else (10 if tier == 2 else 999)
				if int(unit.level) < required_unit_level:
					continue
				# Check leader level allows next tier
				var required_leader_level: int = 5 if tier == 1 else (10 if tier == 2 else 999)
				if leader_level < required_leader_level:
					continue
				# Check promotion path exists and get cost
				var promotes_to: String = UnitLibraryScript.get_promotion(str(unit.unit_type))
				if promotes_to == "":
					continue
				var tpl: Dictionary = UnitLibraryScript.get_template(promotes_to)
				if tpl.is_empty():
					continue
				var cost: int = int(tpl.get("gold_cost", 0))
				var reserve: int = _get_ai_treasury_reserve(state, faction, snap)
				if int(faction.gold) < cost + reserve:
					continue
				# Queue promotion
				state.order_book.queue_promotion(int(faction.id), int(unit.unit_id), cost)


func _pass11_recruits(state: GameState, map_data: MapData, faction: FactionData,
		ai_id: int, owned: Array, peval: Dictionary, aeval: Dictionary,
		leader_roles: Dictionary, snap: Dictionary, out: Array) -> void:

	for pid in owned:
		var p: ProvinceData = map_data.provinces[pid] as ProvinceData
		var pe: Dictionary = peval[pid]
		var posture: String = str(pe.get("posture", POSTURE_INTERIOR))
		var reserve: int = _get_ai_treasury_reserve(state, faction, snap)
		var gold_pressure: float = float(snap.get("gold_pressure", 0.0))
		# Skip recruits under pressure — but always allow SPEARHEAD and SHIELD to recruit
		# Frontier provinces need army to function; starving them causes the cascade freeze
		if gold_pressure >= 0.78 and posture != POSTURE_SHIELD and posture != POSTURE_RESERVE and posture != POSTURE_SPEARHEAD and posture != POSTURE_STAGING:
			continue

		for lid_val in p.leader_ids:
			var lid: int = int(lid_val)
			var leader: LeaderData = state.get_leader(lid)
			if leader == null or bool(leader.on_mission):
				continue

			var open_slots: int = int(leader.max_unit_slots) - int(leader.army_unit_ids.size())
			var used_cp: int = state.get_leader_used_cp(leader)
			var cp_headroom: int = (int(leader.get_effective_max_cp()) if leader.has_method("get_effective_max_cp") else int(leader.max_cp)) - used_cp

			# Tier-gated recruitment: leader level unlocks higher-tier units
			# Tier 1 always available, Tier 2 at Lv5+, Tier 3 at Lv10+
			var leader_biome: String = str(p.biome) if str(p.biome) != "" else "plains"
			var available_types: Array[String] = UnitLibraryScript.get_types_for_biome_at_leader_level(leader_biome, int(leader.level))
			if available_types.is_empty():
				continue
			var ae: Dictionary = aeval.get(lid, {}) as Dictionary
			var priority_roles: Array = ae.get("priority_roles", []) as Array
			var damaged_units: int = int(ae.get("damaged_units", 0))
			var severe_injuries: int = int(ae.get("severe_injuries", 0))
			var health_ratio: float = float(ae.get("health_ratio", 1.0))
			var recruit_to_inventory: bool = false
			if open_slots <= 0:
				# Cap province inventory at 2 unattached units — prevents warehousing
				var province_inventory_size: int = p.unit_inventory.size()
				var can_stockpile: bool = province_inventory_size < 2
				recruit_to_inventory = can_stockpile and (damaged_units > 0 or health_ratio < 0.80)
			if open_slots <= 0 and not recruit_to_inventory:
				continue

			for utype in available_types:
				var tmpl: Dictionary = UnitLibraryScript.get_template(utype) as Dictionary
				if tmpl.is_empty():
					continue
				var ucost: int = int(tmpl.get("gold_cost", 100))
				var ucp: int   = int(tmpl.get("cp_cost", 5))
				if not _can_ai_spend(state, faction, snap, ucost, "recruit"):
					continue
				if not recruit_to_inventory and ucp > cp_headroom:
					continue

				var utier: int = int(tmpl.get("tier", 1))
				var upkeep_cost: int = int(tmpl.get("upkeep_cost", 10))
				# Block T2/T3 if upkeep would push faction into sustained deficit
				var s_income: int = int(snap.get("income", int(faction.income)))
				var s_upkeep: int = int(snap.get("upkeep", 0))
				if utier >= 2 and s_income > 0 and (s_upkeep + upkeep_cost) > int(float(s_income) * 0.90):
					continue  # can't sustain the extra upkeep
				var risk_state_str: String = str(snap.get("risk_state", "stable"))
				var rscore: float = _score_recruit(utype, ucost, ucp, priority_roles,
					posture, faction, ae, utier, gold_pressure, risk_state_str)
				if recruit_to_inventory:
					rscore *= 0.88
					rscore += float(damaged_units) * 8.0 + float(severe_injuries) * 10.0
				rscore *= _front_province_action_mult(snap, pid, posture)
				if rscore <= 0.0:
					continue

				# Mandatory wave: Shield province with urgent role gap
				var wave: String = "optional"
				if posture == POSTURE_SHIELD and ae.get("defense_ready", false) == false:
					wave = "mandatory"
				elif posture == POSTURE_SPEARHEAD or posture == POSTURE_RESERVE:
					wave = "strategic"
				elif not priority_roles.is_empty():
					wave = "strategic"
				if int(faction.gold) < reserve and wave == "optional":
					continue
				if gold_pressure >= 0.85 and wave != "mandatory":
					continue

				out.append({
					"leader_id":   lid,
					"province_id": pid,
					"unit_type":   utype,
					"gold_cost":   ucost,
					"cp_cost":     ucp,
					"attach_immediately": not recruit_to_inventory,
					"score":       rscore,
					"wave":        wave,
				})

	# Sort by score descending
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"]))


# ==================================================
# PASS 12 — TRANSFER CANDIDATES
# ==================================================

func _pass12_transfers(state: GameState, map_data: MapData, faction: FactionData,
		ai_id: int, owned: Array, peval: Dictionary, leader_roles: Dictionary,
		aeval: Dictionary, snap: Dictionary, out: Array) -> void:

	# Move defense commanders to Shield provinces, assault commanders to Spearheads.
	# Also push leaders toward empty frontier provinces and thin border provinces (only 1 leader).
	# Thin border fix: border_backup_coverage counts provinces with >=2 leaders.
	# Without this pass, single-leader border provinces never attract a backup — causing
	# the persistent border_backup ~0.44 gap the AutoTuner cannot close via knobs alone.
	for pid in owned:
		var pe: Dictionary = peval[pid]
		var posture: String = str(pe.get("posture", POSTURE_INTERIOR))
		var p_xfer: ProvinceData = map_data.provinces[pid] as ProvinceData
		# Empty border: no leader at all on a frontier province
		var is_empty_border: bool = p_xfer.leader_ids.is_empty() and _is_frontier_province(map_data, pid, ai_id)
		# Thin border: exactly 1 leader on a frontier province — needs backup
		var is_thin_border: bool = (p_xfer.leader_ids.size() == 1) and _is_frontier_province(map_data, pid, ai_id) and posture != POSTURE_RECOVERY
		if posture != POSTURE_SHIELD and posture != POSTURE_SPEARHEAD and not is_empty_border and not is_thin_border:
			continue
		var p: ProvinceData = map_data.provinces[pid] as ProvinceData

		for adj_id in _get_adjacent(map_data, pid):
			if not peval.has(adj_id):
				continue
			var adj_p: ProvinceData = map_data.provinces[adj_id] as ProvinceData
			if int(adj_p.owner_id) != ai_id:
				continue
			for lid_val in adj_p.leader_ids:
				var lid: int = int(lid_val)
				var leader: LeaderData = state.get_leader(lid)
				if leader == null or bool(leader.on_mission):
					continue
				var role: String = str(leader_roles.get(lid, ""))
				var fits: bool = false
				if posture == POSTURE_SHIELD and role == "defense_commander":
					fits = true
				if posture == POSTURE_SPEARHEAD and role == "assault_commander":
					fits = true
				# Empty border provinces accept any available leader
				if is_empty_border and (role == "assault_commander" or role == "reserve_commander"):
					fits = true
				# Thin border provinces (1 leader) accept reserve commanders as backup
				# Lower score than empty-border fill to avoid over-clustering
				if is_thin_border and role == "reserve_commander":
					fits = true
				if not fits:
					continue
				# Check source defense floor
				var src_pe: Dictionary = peval[adj_id]
				var src_def: float = float(src_pe.get("friendly_defense_power", 0.0))
				var src_floor: float = float(src_pe.get("defense_floor", 0.0))
				if src_def - float(state.get_leader_used_cp(leader)) < src_floor:
					continue  # would strip source below floor
				var tscore: float = 30.0 * faction.aggression if posture == POSTURE_SPEARHEAD else 30.0 * faction.border_security
				if is_thin_border:
					tscore = 18.0 * faction.border_security  # lower priority than full fills
				tscore *= _front_province_action_mult(snap, pid, posture)
				out.append({
					"leader_id":   lid,
					"from_id":     adj_id,
					"to_id":       pid,
					"score":       tscore,
					"wave":        "strategic",
				})

	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"]))


# ==================================================
# PASS 13 — FORTIFY CANDIDATES
# ==================================================

func _pass13_forts(state: GameState, map_data: MapData, faction: FactionData, ai_id: int,
		owned: Array, peval: Dictionary, snap: Dictionary, out: Array) -> void:
	var anti_stalemate: bool = _is_ai_anti_stalemate_window(state, snap)
	var reserve: int = _get_ai_treasury_reserve(state, faction, snap)
	var fortify_surplus_mult: float = _tuning_float(state, "fortify_surplus_mult", 1.15)
	# AI caps fort upgrades at level 3 unless they have significant surplus
	var fort_cap: int = 3
	if int(faction.gold) >= reserve * 2:
		fort_cap = 5
	for pid in owned:
		var p: ProvinceData = map_data.provinces[pid] as ProvinceData
		if int(p.fort_level) >= fort_cap:
			continue
		var cost: int = TurnManager.FORT_BASE_COST * maxi(1, int(p.fort_level))
		if not _can_ai_spend(state, faction, snap, cost, "fortify"):
			continue
		var pe: Dictionary = peval[pid]
		var posture: String = str(pe.get("posture", POSTURE_INTERIOR))
		if anti_stalemate and posture != POSTURE_SHIELD and posture != POSTURE_RECOVERY:
			var fortify_gate: int = int(round(float(reserve) * fortify_surplus_mult))
			if int(faction.gold) < fortify_gate:
				continue
		var fscore: float = _score_fort(p, pe, faction)
		fscore *= _front_province_action_mult(snap, pid, posture)
		if fscore <= 0.0:
			continue
		var wave: String = "strategic"
		if posture == POSTURE_SHIELD and float(pe.get("collapse_risk", 0.0)) > 0.5:
			wave = "mandatory"
		out.append({ "province_id": pid, "cost": cost, "score": fscore, "wave": wave })
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"]))


# ==================================================
# PASS 14 — ATTACK CANDIDATES
# ==================================================

func _pass14_attacks(state: GameState, map_data: MapData, faction: FactionData,
		ai_id: int, owned: Array, peval: Dictionary, aeval: Dictionary,
		snap: Dictionary, out: Array, log: DebugLogger) -> void:

	var profile: Dictionary = PLAYSTYLE_PROFILES.get(str(faction.ai_playstyle),
		PLAYSTYLE_PROFILES["balanced"]) as Dictionary
	var min_pwin: float = float(profile.get("min_pwin", MIN_ACCEPTABLE_PWIN))
	# Doctrine softens or tightens the threshold
	min_pwin = clampf(min_pwin - (faction.aggression - 0.5) * 0.20, 0.15, 0.75)
	min_pwin = clampf(min_pwin + _tuning_float(state, "attack_pwin_offset", 0.0), 0.10, 0.85)
	var max_attacks: int = int(profile.get("max_attacks", 2))
	max_attacks += _tuning_int(state, "max_attacks_bonus", 0)
	max_attacks = clampi(max_attacks, 1, 5)
	if faction.aggression >= 0.75:
		max_attacks = mini(max_attacks + 1, 4)
	var war_surplus: bool = _has_ai_war_surplus(state, faction, snap)
	var anti_stalemate: bool = _is_ai_anti_stalemate_window(state, snap)
	var neutral_ratio: float = float(snap.get("neutral_ratio", 1.0))
	var faction_war_drought: int = int(snap.get("months_since_faction_war", 0))
	var faction_war_window: bool = neutral_ratio <= _tuning_float(state, "neutral_exhaustion_ratio", 0.30)
	if faction_war_window:
		min_pwin = clampf(min_pwin - _tuning_float(state, "faction_war_pwin_bonus", 0.04), 0.08, 0.85)
		if faction_war_drought >= _tuning_int(state, "faction_war_drought_months", 4):
			min_pwin = clampf(min_pwin - 0.02, 0.08, 0.85)
			max_attacks = mini(max_attacks + 1, 5)
	if war_surplus:
		min_pwin = clampf(min_pwin - _tuning_float(state, "surplus_attack_pwin_bonus", 0.10), 0.10, 0.85)
		max_attacks = mini(max_attacks + 1, 5)
	if anti_stalemate:
		min_pwin = clampf(min_pwin - _tuning_float(state, "anti_stalemate_pwin_bonus", 0.10), 0.08, 0.85)
		max_attacks = mini(max_attacks + _tuning_int(state, "anti_stalemate_max_attacks_bonus", 1), 5)
	if not _can_ai_spend(state, faction, snap, 0, "attack") and not war_surplus:
		max_attacks = 0

	# Build candidate buckets by target province
	var buckets: Dictionary = {}  # target_id -> bucket
	for src_id in owned:
		var src_cp: int = _get_province_attack_cp(state, src_id)
		if src_cp < MIN_SOURCE_CP:
			continue
		var pe: Dictionary = peval[src_id]
		var posture: String = str(pe.get("posture", POSTURE_INTERIOR))
		# Recovery provinces never attack; Mission bases are too exposed
		if posture == POSTURE_RECOVERY or posture == POSTURE_MISSION:
			continue
		var src_def: float = float(pe.get("friendly_defense_power", 0.0))
		var src_floor: float = float(pe.get("defense_floor", 0.0))
		var src_commit_cp: int = _get_attack_commit_cp(src_cp, src_def, src_floor)
		if posture == POSTURE_SHIELD and src_commit_cp < MIN_SOURCE_CP:
			continue
		if _is_frontier_province(map_data, src_id, ai_id) and _count_active_province_leaders(state, src_id) <= 1:
			src_commit_cp = mini(src_commit_cp, int(floor(float(src_cp) * 0.45)))
		if src_commit_cp < MIN_SOURCE_CP:
			continue

		var attack_health_ratio: float = _get_province_attack_health_ratio(state, src_id)
		var attack_health_floor: float = _tuning_float(state, "attack_health_floor", DEFAULT_ATTACK_HEALTH_FLOOR)
		var source_wounded_count: int = _get_province_wounded_commander_count(state, src_id)
		if source_wounded_count > 0:
			attack_health_floor += minf(0.10, float(source_wounded_count) * 0.04)
		if posture != POSTURE_SHIELD and attack_health_ratio < attack_health_floor:
			if log != null:
				log.event("ai_attack_skip", {
					"faction": ai_id, "from": src_id,
					"reason": "low_readiness",
					"health_ratio": attack_health_ratio,
					"health_floor": attack_health_floor
				})
			continue

		var src_p: ProvinceData = map_data.provinces[src_id] as ProvinceData
		for tid in _adjacent_enemies_or_neutral(map_data, src_id, ai_id):
			if not buckets.has(tid):
				buckets[tid] = { "target_id": tid, "sources": [], "combined_cp": 0 }
			var b: Dictionary = buckets[tid]
			b["sources"].append({ "from": src_id, "cp": src_commit_cp,
				"fort_level": int(src_p.fort_level), "total_cp": src_cp })
			b["combined_cp"] = int(b["combined_cp"]) + src_commit_cp
			buckets[tid] = b

	# Score each bucket
	for tid_val in buckets.keys():
		var tid: int = int(tid_val)
		var b: Dictionary = buckets[tid]
		var target: ProvinceData = map_data.provinces[tid] as ProvinceData

		var atk_base: int = int(b["combined_cp"])
		var fort_attack_mult: float = _tuning_float(state, "fort_attack_bonus_mult", 1.0)
		var fort_def_mult: float = _tuning_float(state, "fort_defense_mult", 1.0)
		var choke_def_mult: float = _tuning_float(state, "chokepoint_defense_mult", 1.0)
		for s in b["sources"] as Array:
			atk_base += int(round(float(int(s["fort_level"]) * TurnManager.FORT_ATTACK_BONUS_PER_LEVEL) * fort_attack_mult))
		var def_base: int = _get_province_defense_cp(state, tid)
		def_base += int(target.defense_value)
		def_base += int(round(float(int(target.fort_level) * TurnManager.FORT_DEF_MULT) * fort_def_mult))
		if bool(target.is_chokepoint):
			def_base += int(round(float(TurnManager.CHOKE_DEF_BONUS) * choke_def_mult))

		var target_health_ratio: float = _get_province_total_health_ratio(state, tid)
		var target_wounded_count: int = _get_province_wounded_commander_count(state, tid)
		var weak_target: bool = target_health_ratio <= 0.78 or target_wounded_count > 0
		var target_is_neutral: bool = int(target.owner_id) < 0
		var pwin_bonus: float = 0.0
		if weak_target and not target_is_neutral:
			pwin_bonus += _tuning_float(state, "weak_target_pwin_bonus", 0.03)
		if faction_war_window and not target_is_neutral:
			pwin_bonus += _tuning_float(state, "faction_war_pwin_bonus", 0.04)
			if faction_war_drought >= _tuning_int(state, "faction_war_drought_months", 4):
				pwin_bonus += 0.02
		var pwin: float = clampf(_estimate_win_probability(atk_base, def_base) + pwin_bonus, 0.0, 1.0)
		var anti_stalemate_floor: float = _tuning_float(state, "anti_stalemate_hard_floor", 0.42)
		if pwin < min_pwin:
			if log != null:
				log.event("ai_attack_skip", {
					"faction": ai_id, "to": tid,
					"reason": "low_pwin", "pwin": pwin,
					"attack_base": atk_base, "defense_base": def_base
				})
			continue
		if anti_stalemate and pwin < maxf(min_pwin, anti_stalemate_floor):
			if log != null:
				log.event("ai_attack_skip", {
					"faction": ai_id, "to": tid,
					"reason": "anti_stalemate_attrition_floor", "pwin": pwin,
					"attack_base": atk_base, "defense_base": def_base
				})
			continue
		# Only apply econ pressure gate when faction doesn't have a gold surplus
		var econ_reserve_check: int = _get_ai_treasury_reserve(state, faction, snap)
		var econ_surplus_ok: bool = int(faction.gold) >= int(round(float(econ_reserve_check) * 3.0))
		if not econ_surplus_ok and float(snap.get("gold_pressure", 0.0)) >= 0.80 and pwin < minf(0.85, min_pwin + 0.10):
			if log != null:
				log.event("ai_attack_skip", {
					"faction": ai_id, "to": tid,
					"reason": "econ_risk", "pwin": pwin,
					"attack_base": atk_base, "defense_base": def_base
				})
			continue

		var hold_value: float = _estimate_post_battle_hold_value(state, map_data, tid, ai_id, atk_base, pwin, b["sources"])
		var hold_margin: float = _tuning_float(state, "post_battle_hold_margin", DEFAULT_POST_BATTLE_HOLD_MARGIN)
		# Bypass cant_hold for high-confidence wins — at pwin >= 0.70 the AI
		# is projected to win decisively and post-battle exposure is acceptable.
		var hold_bypass_pwin: float = 0.70
		var skip_hold_check: bool = pwin >= hold_bypass_pwin and war_surplus
		if not skip_hold_check and hold_value < hold_margin:
			if log != null:
				log.event("ai_attack_skip", {
					"faction": ai_id, "to": tid,
					"reason": "cant_hold", "pwin": pwin,
					"hold_value": hold_value,
					"attack_base": atk_base, "defense_base": def_base
				})
			continue

		var attrition_penalty: float = _estimate_attack_attrition_penalty(state, map_data, b["sources"], tid, atk_base, def_base, pwin, aeval)
		var tval: float = _score_attack_target(state, map_data, target, ai_id, faction,
			b["sources"].size(), peval, aeval)
		tval *= _front_target_action_mult(state, snap, tid, int(target.owner_id))
		var readiness_bonus: float = 0.0
		for src in b["sources"] as Array:
			readiness_bonus += (_get_province_attack_health_ratio(state, int((src as Dictionary).get("from", -1))) - 0.70) * 18.0
		var ascore: float = (tval + pwin * 88.0 + hold_value * 5.5 + readiness_bonus - attrition_penalty) * faction.aggression * faction.opportunism
		if weak_target and not target_is_neutral:
			ascore += _tuning_float(state, "weak_target_attack_score_bonus", 18.0)
		if faction_war_window and not target_is_neutral:
			ascore *= _tuning_float(state, "faction_war_attack_score_mult", 1.22)
			if faction_war_drought >= _tuning_int(state, "faction_war_drought_months", 4):
				ascore *= 1.08
		if faction_war_window and target_is_neutral:
			ascore *= 0.90
		if war_surplus:
			ascore *= 1.20
		if anti_stalemate:
			ascore *= _tuning_float(state, "anti_stalemate_attack_score_mult", 1.20)
		ascore *= _tuning_float(state, "attack_score_mult", 1.0)
		ascore *= _front_target_action_mult(state, snap, tid, int(target.owner_id))
		b["pwin"]         = pwin
		b["atk_base"]     = atk_base
		b["def_base"]     = def_base
		b["hold_value"]   = hold_value
		b["attrition_penalty"] = attrition_penalty
		b["score"]        = ascore
		b["target_is_neutral"] = target_is_neutral
		b["weak_target"]  = weak_target
		b["wave"]         = "offensive"
		b["max_attacks"]  = max_attacks
		b["min_pwin"]     = min_pwin
		out.append(b)

	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"]))


# ==================================================
# PASS 15 — SCORE ALL (doctrine multipliers already folded in above)
# Nothing extra needed — scoring happened inline in each pass.
# ==================================================

func _pass15_score_all(_faction: FactionData, _snap: Dictionary, _peval: Dictionary,
		_aeval: Dictionary, _recruits: Array, _transfers: Array, _forts: Array,
		_attacks: Array, _missions: Array, _items: Array) -> void:
	pass  # Scoring done inline; this pass is a no-op placeholder.


# ==================================================
# COMMIT HELPERS (Pass 17-19)
# ==================================================

func _commit_wave(candidates: Array, wave: String, faction: FactionData,
		snap: Dictionary, peval: Dictionary, reserved_leaders: Dictionary,
		reserved_provinces: Dictionary, reserved_targets: Dictionary,
		gold_spent: Array, ob: OrderBook, state: GameState,
		ai_id: int, log: DebugLogger) -> void:

	for c in candidates:
		if str(c.get("wave", "")) != wave:
			continue
		var lid: int = int(c.get("leader_id", -1))
		var pid: int = int(c.get("province_id", -1))
		if reserved_leaders.has(lid) or reserved_provinces.has(pid):
			continue
		var cost: int = int(c.get("gold_cost", 0))
		if not _can_ai_spend_with_committed(state, faction, snap, cost, "recruit", gold_spent[0]):
			continue
		var utype: String = str(c.get("unit_type", ""))
		var new_uid: int = state.recruit_unit_id(ai_id, pid, utype)
		if new_uid >= 0:
			if bool(c.get("attach_immediately", true)):
				state.attach_unit(lid, new_uid)
			gold_spent[0] += cost
			if log != null:
				log.event("ai_recruited", { "faction": ai_id, "province": pid,
					"unit_type": utype, "leader": lid, "wave": wave,
					"attach_immediately": bool(c.get("attach_immediately", true)) })


func _commit_transfers(candidates: Array, faction: FactionData, snap: Dictionary,
		reserved_leaders: Dictionary, reserved_provinces: Dictionary,
		gold_spent: Array, ob: OrderBook, ai_id: int, log: DebugLogger) -> void:
	for c in candidates:
		var lid: int = int(c.get("leader_id", -1))
		var from_id: int = int(c.get("from_id", -1))
		var to_id: int = int(c.get("to_id", -1))
		if reserved_leaders.has(lid) or reserved_provinces.has(from_id):
			continue
		ob.queue_transfer(ai_id, from_id, to_id, [lid])
		reserved_leaders[lid] = true
		if log != null:
			log.event("ai_transfer", { "faction": ai_id, "leader": lid,
				"from": from_id, "to": to_id })


func _commit_forts(wave: String, candidates: Array, faction: FactionData,
		snap: Dictionary, peval: Dictionary, reserved_provinces: Dictionary,
		gold_spent: Array, ob: OrderBook, state: GameState, ai_id: int) -> void:
	for c in candidates:
		if str(c.get("wave", "")) != wave:
			continue
		var pid: int = int(c.get("province_id", -1))
		if reserved_provinces.has(pid):
			continue
		var cost: int = int(c.get("cost", 0))
		if not _can_ai_spend_with_committed(state, faction, snap, cost, "fortify", gold_spent[0]):
			continue
		ob.queue_upgrade(ai_id, pid, cost)
		gold_spent[0] += cost
		reserved_provinces[pid] = true




func _build_pressure_attack_candidates(state: GameState, faction: FactionData, ai_id: int,
		snap: Dictionary, peval: Dictionary, attack_candidates: Array) -> Array:
	var out: Array = []
	if state == null or state.map_data == null:
		return out
	var map_data: MapData = state.map_data
	var seen_targets: Dictionary = {}
	for pid_val in faction.provinces:
		var src_id: int = int(pid_val)
		if src_id < 0 or src_id >= map_data.provinces.size():
			continue
		var src_cp: int = _get_province_attack_cp(state, src_id)
		if src_cp < 4:
			continue
		var neighbors: Array = map_data.adjacency.get(src_id, []) as Array
		for n_val in neighbors:
			var tid: int = int(n_val)
			if tid < 0 or tid >= map_data.provinces.size():
				continue
			if seen_targets.has(str(src_id) + ":" + str(tid)):
				continue
			var target: ProvinceData = map_data.provinces[tid] as ProvinceData
			if target == null or int(target.owner_id) == ai_id or int(target.owner_id) < 0:
				continue
			var def_base: int = maxi(1, _get_province_defense_cp(state, tid))
			var pwin: float = _estimate_win_probability(src_cp, def_base)
			var pe: Dictionary = peval.get(src_id, {})
			var score: float = 5.0 + float(src_cp) * 0.25 - float(def_base) * 0.10
			score += float(pe.get("enemy_attack_pressure", 0.0)) * 0.05
			score += float(snap.get("gold_pressure", 0.0)) * 2.0
			out.append({
				"target_id": tid,
				"target_is_neutral": false,
				"pressure_attack": true,
				"min_pwin": 0.0,
				"max_attacks": 99,
				"score": score,
				"def_base": def_base,
				"hold_value": 0.0,
				"attrition_penalty": 0.0,
				"sources": [{
					"from": src_id,
					"cp": src_cp,
					"fort_level": int((map_data.provinces[src_id] as ProvinceData).fort_level)
				}]
			})
			seen_targets[str(src_id) + ":" + str(tid)] = true
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", 0.0)) > float(b.get("score", 0.0)))
	return out

func _commit_attack_quota(candidates: Array, required_attacks: int, faction: FactionData,
		snap: Dictionary, peval: Dictionary, reserved_leaders: Dictionary,
		reserved_provinces: Dictionary, reserved_targets: Dictionary,
		gold_spent: Array, attack_quota_progress: Array, ob: OrderBook,
		state: GameState, ai_id: int, log: DebugLogger, enemy_only: bool = false) -> void:

	var queued: int = int(attack_quota_progress[0]) if attack_quota_progress.size() > 0 else 0
	for plan_val in candidates:
		if queued >= required_attacks:
			break
		var plan: Dictionary = plan_val as Dictionary
		if enemy_only and bool(plan.get("target_is_neutral", false)):
			continue
		var tid: int = int(plan.get("target_id", -1))
		if reserved_targets.has(tid):
			continue

		var usable: Array = []
		for s in plan.get("sources", []) as Array:
			var src_id: int = int(s.get("from", -1))
			if not reserved_provinces.has(src_id):
				usable.append(s)
		if usable.is_empty():
			continue

		var is_pressure: bool = bool(plan.get("pressure_attack", false))
		if not is_pressure:
			var atk: int = 0
			for s2 in usable:
				atk += int(s2.get("cp", 0))
			var pwin2: float = _estimate_win_probability(atk, int(plan.get("def_base", 100)))
			if pwin2 < float(plan.get("min_pwin", MIN_ACCEPTABLE_PWIN)):
				continue

		for s2 in usable:
			var from_id: int = int(s2.get("from", -1))
			ob.queue_attack(ai_id, from_id, tid, 0)
			reserved_provinces[from_id] = true

		reserved_targets[tid] = true
		queued += 1
		if attack_quota_progress.size() > 0:
			attack_quota_progress[0] = queued
		if log != null:
			log.event("ai_attack_quota_commit", {
				"faction": ai_id,
				"target": tid,
				"queued_attacks": queued,
				"required_attacks": required_attacks,
				"enemy_only": enemy_only,
				"pressure_attack": is_pressure,
				"score": plan.get("score", 0.0),
				"target_is_neutral": bool(plan.get("target_is_neutral", false))
			})

func _commit_attacks(candidates: Array, faction: FactionData, snap: Dictionary,
		peval: Dictionary, reserved_leaders: Dictionary, reserved_provinces: Dictionary,
		reserved_targets: Dictionary, gold_spent: Array, ob: OrderBook,
		state: GameState, ai_id: int, log: DebugLogger) -> void:

	var attacks_queued: int = 0
	var max_att: int = 2
	if not candidates.is_empty():
		max_att = int(candidates[0].get("max_attacks", 2))

	for plan in candidates:
		if attacks_queued >= max_att:
			break

		if reserved_targets.has(int(plan.get("target_id", -1))):
			continue

		# Filter usable sources
		var usable: Array = []
		for s in plan.get("sources", []) as Array:
			var src_id: int = int(s.get("from", -1))
			if not reserved_provinces.has(src_id):
				usable.append(s)
		if usable.is_empty():
			continue

		# Re-check pwin with usable sources only
		var atk: int = 0
		var fort_attack_mult2: float = _tuning_float(state, "fort_attack_bonus_mult", 1.0)
		for s2 in usable:
			atk += int(s2.get("cp", 0))
			atk += int(round(float(int(s2.get("fort_level", 0)) * TurnManager.FORT_ATTACK_BONUS_PER_LEVEL) * fort_attack_mult2))
		var pwin2: float = _estimate_win_probability(atk, int(plan.get("def_base", 100)))
		if pwin2 < float(plan.get("min_pwin", MIN_ACCEPTABLE_PWIN)):
			continue

		var tid: int = int(plan.get("target_id", -1))
		for s3 in usable:
			var from_id: int = int(s3.get("from", -1))
			ob.queue_attack(ai_id, from_id, tid, 0)
			reserved_provinces[from_id] = true

		reserved_targets[tid] = true
		attacks_queued += 1

		if log != null:
			log.event("ai_attack", { "faction": ai_id, "target": tid,
				"sources": usable.size(), "pwin": pwin2, "score": plan.get("score", 0.0),
				"hold_value": plan.get("hold_value", 0.0),
				"attrition_penalty": plan.get("attrition_penalty", 0.0),
				"war_surplus": _has_ai_war_surplus(state, faction, snap),
				"anti_stalemate": _is_ai_anti_stalemate_window(state, snap),
				"target_is_neutral": bool(plan.get("target_is_neutral", false)),
				"weak_target": bool(plan.get("weak_target", false)) })


func _commit_missions(mission_cands: Array, item_cands: Array, faction: FactionData,
		snap: Dictionary, reserved_leaders: Dictionary, reserved_provinces: Dictionary,
		gold_spent: Array, ob: OrderBook, state: GameState, ai_id: int, log: DebugLogger) -> void:

	var mission_capacity: int = maxi(0, int(snap.get("mission_capacity", 0)) - int(snap.get("active_missions", 0)))
	mission_capacity = mini(mission_capacity, int(snap.get("mission_year_cap_remaining", mission_capacity)))
	if mission_capacity <= 0:
		return

	var all_m: Array = mission_cands + item_cands
	all_m.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", 0.0)) > float(b.get("score", 0.0)))

	var committed: int = 0
	var used_instances: Dictionary = {}
	for m in all_m:
		if committed >= mission_capacity:
			break
		var lid: int = int(m.get("leader_id", -1))
		var pid: int = int(m.get("province_id", -1))
		var instance_id: String = str(m.get("instance_id", ""))
		if reserved_leaders.has(lid) or reserved_provinces.has(pid):
			continue
		# Skip if this mission instance already claimed by another leader
		if instance_id == "" or used_instances.has(instance_id):
			continue
		# Verify mission still available in state
		var mission = state.active_missions.get(instance_id, null)
		if mission == null or str(mission.phase) != "available":
			continue
		ob.queue_mission(ai_id, pid, lid, instance_id, TurnManager.MISSION_DEFAULT_DURATION)
		reserved_leaders[lid] = true
		reserved_provinces[pid] = true
		used_instances[instance_id] = true
		committed += 1
		_register_faction_mission_commit(state, faction)
		if log != null:
			log.event("ai_mission", {
				"faction": ai_id,
				"leader": lid,
				"province": pid,
				"instance_id": instance_id,
				"type": str(m.get("mission_type", "")),
				"committed": committed,
				"capacity": mission_capacity,
				"year_count": int(faction.get_meta("ai_mission_year_count", 0)) if faction.has_meta("ai_mission_year_count") else committed,
			})


# ==================================================
# SCORING HELPERS
# ==================================================

func _score_recruit(utype: String, ucost: int, ucp: int, priority_roles: Array,
		posture: String, faction: FactionData, ae: Dictionary,
		tier: int = 1, gold_pressure: float = 0.0, risk_state: String = "stable") -> float:
	var weights: Dictionary = UNIT_ROLE_WEIGHTS.get(utype, {}) as Dictionary
	# Template need: how well this unit fills the top missing role
	var need_score: float = 0.0
	for i in range(mini(3, priority_roles.size())):
		var role: String = str(priority_roles[i])
		need_score += float(weights.get(role, 0.0)) * (1.0 - float(i) * 0.25)
	# Cost efficiency
	var combat_val: float = float(weights.get("fl", 0.0) + weights.get("sh", 0.0)
		+ weights.get("rn", 0.0) + weights.get("ds", 0.0))
	var efficiency: float = combat_val * float(ucp) / maxf(1.0, float(ucost)) * 100.0
	# Posture modifier
	var posture_mult: float = 1.0
	if posture == POSTURE_SHIELD:
		posture_mult = 1.4
	elif posture == POSTURE_SPEARHEAD:
		posture_mult = 1.2

	var health_ratio: float = float(ae.get("health_ratio", 1.0))
	var damaged_units: int = int(ae.get("damaged_units", 0))
	var severe_injuries: int = int(ae.get("severe_injuries", 0))
	var recovery_pressure: float = (1.0 - health_ratio) * 26.0 + float(damaged_units) * 3.5 + float(severe_injuries) * 5.0

	# Tier preference: higher tiers rewarded when stable and flush, penalized when pressured
	var tier_mult: float = 1.0
	if tier == 2:
		if risk_state in ["stable", "snowball"] and gold_pressure < 0.50:
			tier_mult = 1.30  # actively prefer veterans when in good shape
		elif gold_pressure >= 0.65 or risk_state == "crisis":
			tier_mult = 0.80  # prefer cheap bodies under pressure
		# threatened with moderate gold: neutral (1.0)
	elif tier == 3:
		if risk_state in ["stable", "snowball"] and gold_pressure < 0.35:
			tier_mult = 1.50  # elites are a luxury — reward when truly flush
		else:
			tier_mult = 0.60  # almost never recruit elite under pressure

	return (need_score * 60.0 + efficiency * 20.0 + recovery_pressure) * posture_mult * faction.recruit_bias * tier_mult


func _score_fort(p: ProvinceData, pe: Dictionary, faction: FactionData) -> float:
	var score: float = 0.0
	var posture: String = str(pe.get("posture", POSTURE_INTERIOR))
	var collapse_risk: float = float(pe.get("collapse_risk", 0.0))
	score += collapse_risk * 60.0
	if bool(p.is_chokepoint):
		score += 25.0
	if posture == POSTURE_SHIELD:
		score += 30.0
	score *= faction.fortify_bias
	return score


func _score_attack_target(state: GameState, map_data: MapData, target: ProvinceData, ai_id: int,
		faction: FactionData, source_count: int, peval: Dictionary,
		aeval: Dictionary) -> float:
	var score: float = 0.0
	var owner_id: int = int(target.owner_id)
	score += float(int(target.income)) * 2.0
	if owner_id < 0:
		score += 10.0 * faction.neutral_expansion
	else:
		score += 25.0  # enemy
	if bool(target.is_chokepoint):
		score += 20.0
	score += float(_count_adjacent_non_ai(map_data, int(target.id), ai_id)) * 15.0
	score += float(_count_adjacent_all(map_data, int(target.id))) * 4.0

	# Attrition opportunity: damaged armies and wounded commanders become better targets.
	var target_health_ratio: float = _get_province_total_health_ratio(state, int(target.id))
	var damaged_target_bonus: float = (1.0 - target_health_ratio) * DEFAULT_DAMAGED_TARGET_BONUS
	var wounded_target_bonus: float = float(_get_province_wounded_commander_count(state, int(target.id))) * DEFAULT_WOUNDED_TARGET_BONUS
	score += damaged_target_bonus + wounded_target_bonus

	# Cross-biome bonus: does capturing this biome fill army role gaps?
	var biome_supply: Dictionary = _biome_supply(str(target.biome))
	var biome_bonus: float = 0.0
	for ae_val in aeval.values():
		var ae: Dictionary = ae_val as Dictionary
		for mr in ae.get("missing_roles", []) as Array:
			var role: String = str(mr.get("role", ""))
			var gap: float = float(mr.get("gap", 0.0))
			biome_bonus += gap * float(biome_supply.get(role, 0.0))
	score += biome_bonus * BIOME_ROLE_WEIGHT * 0.1

	return score


func _score_mission(leader: LeaderData, faction: FactionData,
		pe: Dictionary, snap: Dictionary, mtype: String) -> float:
	var score: float = 20.0
	var commander_shortage: int = int(snap.get("commander_shortage", 0))
	var commander_surplus: int = int(snap.get("commander_surplus", 0))
	score += float(int(leader.leadership)) * 2.0
	if bool(pe.get("mission_safety", false)):
		score += 15.0
	match mtype:
		"talent_search":
			score += 16.0 + float(commander_shortage) * 18.0 - float(commander_surplus) * 6.0
		"rumor_investigation":
			score += 10.0 + float(commander_shortage) * 10.0 - float(commander_surplus) * 4.0
		"training_journey":
			score += 8.0 - float(int(leader.level)) - float(commander_shortage) * 4.0
	if int(snap.get("available_leaders", 0)) >= 3:
		score += 8.0
	if str(snap.get("risk_state", "stable")) == "stable":
		score += 6.0
	score *= faction.mission_bias
	return score


func _score_item_hunt(leader: LeaderData, faction: FactionData,
		pe: Dictionary, snap: Dictionary, mtype: String) -> float:
	var score: float = float(snap.get("item_need", 0.0)) * 40.0
	if bool(pe.get("mission_safety", false)):
		score += 10.0
	if mtype == "ruin_exploration":
		score += 8.0
	elif mtype == "caravan_escort":
		score += 4.0
	if int(snap.get("available_leaders", 0)) >= 3:
		score += 4.0
	score *= faction.item_hunting_bias
	return score


# ==================================================
# UTILITY HELPERS (reused from original planner)
# ==================================================

func _estimate_win_probability(attack_base: int, defense_base: int) -> float:
	if attack_base <= 0:
		return 0.0
	if defense_base <= 0:
		return 1.0
	var a2: float = float(attack_base) * float(attack_base)
	var d2: float = float(defense_base) * float(defense_base)
	return a2 / (a2 + d2)


func _count_active_province_leaders(state: GameState, province_id: int) -> int:
	if state == null or state.map_data == null:
		return 0
	var total: int = 0
	var p: ProvinceData = state.map_data.provinces[province_id] as ProvinceData
	for lid in p.leader_ids:
		var leader: LeaderData = state.get_leader(int(lid))
		if leader == null:
			continue
		if bool(leader.on_mission) or str(leader.status) == "wounded" or str(leader.status) == "injured":
			continue
		total += 1
	return total


func _get_attack_commit_cp(source_attack_cp: int, source_defense_cp: float, defense_floor: float) -> int:
	var surplus: int = int(floor(maxf(0.0, source_defense_cp - defense_floor)))
	# Guarantee a minimum commit even when surplus is near zero.
	# Without this, stretched factions can never generate any attack CP at all.
	var min_commit: int = int(floor(float(source_attack_cp) * 0.35))
	return maxi(min_commit, mini(source_attack_cp, surplus))


func _estimate_enemy_counter_pressure(map_data: MapData, state: GameState, province_id: int, ai_id: int, exclude_source_ids: Array = []) -> float:
	if map_data == null or state == null:
		return 0.0
	var excluded: Dictionary = {}
	for sid in exclude_source_ids:
		excluded[int(sid)] = true
	var pressure: float = 0.0
	for adj_id in _get_adjacent(map_data, province_id):
		if excluded.has(int(adj_id)):
			continue
		var adj: ProvinceData = map_data.provinces[adj_id] as ProvinceData
		if int(adj.owner_id) == ai_id:
			continue
		pressure += float(_get_province_attack_cp(state, adj_id))
	return pressure


func _estimate_post_battle_hold_value(state: GameState, map_data: MapData, target_id: int, ai_id: int, attack_base: int, pwin: float, sources: Array) -> float:
	var survivor_mult: float = lerpf(0.50, 0.90, clampf(pwin, 0.0, 1.0))
	var survivor_power: float = float(attack_base) * survivor_mult
	var exclude_source_ids: Array = []
	for s in sources:
		exclude_source_ids.append(int((s as Dictionary).get("from", -1)))
	var counter_pressure: float = _estimate_enemy_counter_pressure(map_data, state, target_id, ai_id, exclude_source_ids)
	# Scale counter_pressure via tuning knob — was overestimating threat by ~4x
	var cp_scale: float = _tuning_float(state, "hold_value_mult", 1.0)
	counter_pressure *= clampf(cp_scale * 0.45, 0.15, 1.0)
	var target: ProvinceData = map_data.provinces[target_id] as ProvinceData
	var fort_hold: float = float(int(target.fort_level)) * 5.0
	if bool(target.is_chokepoint):
		fort_hold += 8.0
	return survivor_power + fort_hold - counter_pressure


func _estimate_attack_attrition_penalty(state: GameState, map_data: MapData, sources: Array, target_id: int, attack_base: int, defense_base: int, pwin: float, aeval: Dictionary) -> float:
	var ratio: float = float(defense_base) / maxf(1.0, float(attack_base))
	var expected_loss: float = (1.0 - pwin) * 24.0 + maxf(0.0, ratio - 1.0) * 12.0
	var source_wounded_caution: float = 0.0
	var replacement_risk: float = 0.0
	var elite_load: float = 0.0
	var damaged_pressure: float = 0.0
	for s in sources:
		var source: Dictionary = s as Dictionary
		var src_id: int = int(source.get("from", -1))
		if state == null or state.map_data == null or src_id < 0:
			continue
		var p: ProvinceData = state.map_data.provinces[src_id] as ProvinceData
		for lid in p.leader_ids:
			var ae: Dictionary = aeval.get(int(lid), {}) as Dictionary
			replacement_risk += float(ae.get("replacement_risk", 0.0))
			elite_load += float(ae.get("used_cp", 0)) / 22.0
			var health_ratio: float = float(ae.get("health_ratio", 1.0))
			if health_ratio < 0.85:
				damaged_pressure += (0.85 - health_ratio) * 24.0
			source_wounded_caution += float(_get_province_wounded_commander_count(state, src_id)) * DEFAULT_SOURCE_WOUNDED_CAUTION
	var target: ProvinceData = map_data.provinces[target_id] as ProvinceData
	var terrain_penalty: float = 0.0
	if bool(target.is_chokepoint):
		terrain_penalty += 8.0
	terrain_penalty += float(int(target.fort_level)) * 2.0
	var weight: float = _tuning_float(state, "attrition_risk_weight", DEFAULT_ATTRITION_RISK_WEIGHT)
	return expected_loss + replacement_risk * weight + elite_load * 1.5 + damaged_pressure + terrain_penalty + source_wounded_caution


func _estimate_unit_level_mult(unit: UnitData) -> float:
	if unit == null:
		return 1.0
	return 1.0 + maxf(0.0, float(int(unit.level) - 1)) * UNIT_LEVEL_STEP


func _estimate_unit_offense(unit: UnitData) -> float:
	if unit == null or int(unit.hp) <= 0 or int(unit.max_hp) <= 0:
		return 0.0
	var hp_ratio: float = clampf(float(unit.hp) / float(unit.max_hp), 0.0, 1.0)
	return float(unit.attack) * hp_ratio * _estimate_unit_level_mult(unit)


func _estimate_unit_defense(unit: UnitData) -> float:
	if unit == null or int(unit.hp) <= 0 or int(unit.max_hp) <= 0:
		return 0.0
	var hp_ratio: float = clampf(float(unit.hp) / float(unit.max_hp), 0.0, 1.0)
	return float(unit.defense) * hp_ratio * _estimate_unit_level_mult(unit)


func _estimate_leader_offense_mult(leader: LeaderData) -> float:
	if leader == null:
		return 1.0
	return 1.0 + float(leader.attack) * LEADER_ATTACK_STEP + float(leader.leadership) * LEADER_LEADERSHIP_STEP


func _estimate_leader_defense_mult(leader: LeaderData) -> float:
	if leader == null:
		return 1.0
	return 1.0 + float(leader.defense) * LEADER_DEFENSE_STEP + float(leader.leadership) * LEADER_LEADERSHIP_STEP


func _get_biome_defense_mult(biome: String) -> float:
	return float(TERRAIN_DEFENSE_MULT.get(String(biome).to_lower(), 1.0))


func _get_leader_army_offense_strength(state: GameState, leader: LeaderData) -> float:
	if state == null or leader == null:
		return 0.0
	var total: float = 0.0
	for uid_val in leader.army_unit_ids:
		var unit := state.get_unit(int(uid_val)) as UnitData
		if unit == null:
			continue
		total += _estimate_unit_offense(unit)
	return total * _estimate_leader_offense_mult(leader)


func _get_leader_army_defense_strength(state: GameState, leader: LeaderData) -> float:
	if state == null or leader == null:
		return 0.0
	var total: float = 0.0
	for uid_val in leader.army_unit_ids:
		var unit := state.get_unit(int(uid_val)) as UnitData
		if unit == null:
			continue
		total += _estimate_unit_defense(unit)
	return total * _estimate_leader_defense_mult(leader)


func _get_province_attack_cp(state: GameState, province_id: int) -> int:
	if state == null or state.map_data == null:
		return 0
	var total_offense: float = 0.0
	var total_defense: float = 0.0
	var p: ProvinceData = state.map_data.provinces[province_id] as ProvinceData
	for lid in p.leader_ids:
		var leader := state.get_leader(int(lid)) as LeaderData
		if leader == null or bool(leader.on_mission):
			continue
		if str(leader.status) == "wounded" or str(leader.status) == "injured":
			continue
		total_offense += _get_leader_army_offense_strength(state, leader)
		total_defense += _get_leader_army_defense_strength(state, leader)
	var strength: float = total_offense + total_defense * ATTACKER_DEFENSE_WEIGHT
	return maxi(0, int(round(strength)))


func _get_province_defense_cp(state: GameState, province_id: int) -> int:
	if state == null or state.map_data == null:
		return 0
	var total_offense: float = 0.0
	var total_defense: float = 0.0
	var p: ProvinceData = state.map_data.provinces[province_id] as ProvinceData
	for lid in p.leader_ids:
		var leader := state.get_leader(int(lid)) as LeaderData
		if leader == null or bool(leader.on_mission):
			continue
		if str(leader.status) == "wounded" or str(leader.status) == "injured":
			continue
		total_offense += _get_leader_army_offense_strength(state, leader)
		total_defense += _get_leader_army_defense_strength(state, leader)
	for uid in p.unit_inventory:
		var unit := state.get_unit(int(uid)) as UnitData
		if unit == null or int(unit.hp) <= 0:
			continue
		total_offense += _estimate_unit_offense(unit)
		total_defense += _estimate_unit_defense(unit)
	var terrain_mult: float = _get_biome_defense_mult(str(p.biome))
	var strength: float = (total_defense + total_offense * DEFENDER_OFFENSE_WEIGHT) * terrain_mult
	return maxi(0, int(round(strength)))


func _adjacent_enemies_or_neutral(map_data: MapData, from_id: int,
		my_id: int) -> Array[int]:
	var out: Array[int] = []
	for item in map_data.routes:
		var r: RouteData = item as RouteData
		var other: int = -1
		if int(r.a) == from_id:
			other = int(r.b)
		elif int(r.b) == from_id:
			other = int(r.a)
		else:
			continue
		var p: ProvinceData = map_data.provinces[other] as ProvinceData
		if int(p.owner_id) != my_id:
			out.append(other)
	return out


func _get_adjacent(map_data: MapData, province_id: int) -> Array[int]:
	var out: Array[int] = []
	for item in map_data.routes:
		var r: RouteData = item as RouteData
		if int(r.a) == province_id:
			out.append(int(r.b))
		elif int(r.b) == province_id:
			out.append(int(r.a))
	return out


func _is_frontier_province(map_data: MapData, province_id: int, ai_id: int) -> bool:
	for adj_id in _get_adjacent(map_data, province_id):
		var adj: ProvinceData = map_data.provinces[adj_id] as ProvinceData
		if int(adj.owner_id) != ai_id:
			return true
	return false


func _count_adjacent_non_ai(map_data: MapData, province_id: int, ai_id: int) -> int:
	var count: int = 0
	for adj_id in _get_adjacent(map_data, province_id):
		var p: ProvinceData = map_data.provinces[adj_id] as ProvinceData
		if int(p.owner_id) != ai_id:
			count += 1
	return count


func _count_adjacent_all(map_data: MapData, province_id: int) -> int:
	var count: int = 0
	for item in map_data.routes:
		var r: RouteData = item as RouteData
		if int(r.a) == province_id or int(r.b) == province_id:
			count += 1
	return count


func _find_faction(map_data: MapData, id: int) -> FactionData:
	for item in map_data.factions:
		var f: FactionData = item as FactionData
		if int(f.id) == id:
			return f
	return null


func _biome_supply(biome: String) -> Dictionary:
	# Returns approximate role supply strengths for a biome's unit roster.
	match biome:
		"plains":   return { "fl":0.85,"sh":0.50,"rn":0.90,"cv":0.90,"sk":0.15,"ac":0.95,"aa":0.80,"ds":0.60 }
		"forest":   return { "fl":0.15,"sh":0.20,"rn":1.00,"cv":0.90,"sk":1.00,"ac":0.10,"aa":0.15,"ds":0.05 }
		"mountain": return { "fl":0.85,"sh":0.80,"rn":0.00,"cv":0.00,"sk":0.00,"ac":0.95,"aa":1.00,"ds":1.00 }
		"desert":   return { "fl":0.65,"sh":0.85,"rn":0.80,"cv":1.00,"sk":0.40,"ac":0.35,"aa":0.25,"ds":0.55 }
		"tundra":   return { "fl":0.90,"sh":0.80,"rn":0.85,"cv":0.15,"sk":0.20,"ac":0.25,"aa":0.40,"ds":0.55 }
		"swamp":    return { "fl":0.85,"sh":0.35,"rn":0.90,"cv":0.20,"sk":1.00,"ac":0.30,"aa":0.30,"ds":0.65 }
		"coast":    return { "fl":0.80,"sh":0.65,"rn":0.20,"cv":0.00,"sk":0.10,"ac":0.75,"aa":0.55,"ds":0.45 }
		_:          return { "fl":0.50,"sh":0.50,"rn":0.50,"cv":0.50,"sk":0.50,"ac":0.50,"aa":0.50,"ds":0.50 }


# ==================================================
# FRONT PRIORITY HELPERS
# ==================================================
# These functions support front-line prioritization scoring.
# _build_front_priority computes a per-province priority map based on
# enemy pressure and strategic value. The multiplier functions scale
# action scores up or down based on whether a province or target sits
# on a hot front.

func _build_front_priority(state: GameState, map_data: MapData,
		faction: FactionData, ai_id: int,
		owned: Array, peval: Dictionary) -> Dictionary:
	# Returns a dictionary: province_id -> priority float (0.0–2.0)
	# Higher = more strategically active front.
	var result: Dictionary = {}
	for pid in owned:
		var pe: Dictionary = peval[pid]
		var posture: String = str(pe.get("posture", POSTURE_INTERIOR))
		var enemy_pressure: float = float(pe.get("enemy_attack_pressure", 0.0))
		var collapse_risk: float = float(pe.get("collapse_risk", 0.0))
		var priority: float = 1.0
		if posture == POSTURE_SHIELD or posture == POSTURE_SPEARHEAD:
			priority += 0.4
		priority += clampf(enemy_pressure / 20.0, 0.0, 0.4)
		priority += clampf(collapse_risk, 0.0, 0.2)
		result[pid] = clampf(priority, 0.5, 2.0)
	return result


func _front_province_action_mult(snap: Dictionary, province_id: int,
		posture: String) -> float:
	# Scales recruit/fort/transfer scores based on front activity.
	# Active front provinces get a boost; interior provinces are neutral.
	var front_state: Dictionary = snap.get("front_state", {}) as Dictionary
	var priority: float = float(front_state.get(province_id, 1.0))
	match posture:
		POSTURE_SHIELD:     return clampf(priority * 1.10, 0.8, 1.8)
		POSTURE_SPEARHEAD:  return clampf(priority * 1.05, 0.8, 1.6)
		POSTURE_INTERIOR:   return clampf(priority * 0.85, 0.5, 1.2)
		_:                  return 1.0


func _front_target_action_mult(state: GameState, snap: Dictionary, target_id: int,
		owner_id: int) -> float:
	var front_state: Dictionary = snap.get("front_state", {}) as Dictionary
	var priority: float = float(front_state.get(target_id, 1.0))
	var is_primary: bool = priority >= 1.3
	if owner_id < 0:
		return _tuning_float(state, "front_primary_neutral_mult", 1.18) if is_primary \
			else _tuning_float(state, "front_secondary_neutral_mult", 0.95)
	else:
		return _tuning_float(state, "front_primary_enemy_mult", 1.22) if is_primary \
			else _tuning_float(state, "front_secondary_enemy_mult", 0.94)


# === AI PHASE 2 BEHAVIOR FIXES ===
# ANTI_STALEMATE_SYSTEM: force attacks if idle > threshold
# FORCE_SPENDING: spend gold if reserves exceed cap
# IDLE_LEADER_USAGE: assign missions or raids
# LATE_GAME_AGGRESSION: increase aggression scaling over time

# === SCORING REWRITE PHASE 2 ===
# Penalize passive gameplay
# Penalize gold hoarding
# Penalize idle units/leaders
# Reward map pressure
# Reward continuous combat
