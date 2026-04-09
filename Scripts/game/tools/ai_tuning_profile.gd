# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: AITuningProfile
#
# Role:
# Stores safe, high-level AI tuning knobs that may be adjusted by
# automated testing tools without rewriting core gameplay logic.
# ==================================================
extends Resource
class_name AITuningProfile

@export var attack_pwin_offset: float = -0.0209
@export var attack_score_mult: float = 1.05
@export var reserve_floor_mult: float = 0.80
@export var fort_defense_mult: float = 1.0
@export var chokepoint_defense_mult: float = 1.0
@export var fort_attack_bonus_mult: float = 1.0
@export var max_attacks_bonus: int = 1
@export var starting_extra_generals_per_faction: int = 1 # 1 ruler + 2 generals per faction at campaign start
@export var treasury_reserve_mult: float = 1.0
@export var recruit_econ_guard: float = 1.0
@export var fortify_econ_guard: float = 1.0
@export var attack_econ_guard: float = 1.0
@export var surplus_war_chest_mult: float = 1.73409947752952
@export var surplus_attack_pwin_bonus: float = 0.06
@export var anti_stalemate_month: int = 13
@export var anti_stalemate_pwin_bonus: float = 0.030554284453392
@export var anti_stalemate_attack_score_mult: float = 1.28
@export var anti_stalemate_max_attacks_bonus: int = 1
@export var fortify_surplus_mult: float = 1.15
@export var front_primary_enemy_mult: float = 1.30
@export var front_secondary_enemy_mult: float = 1.00
@export var front_primary_neutral_mult: float = 1.08
@export var front_secondary_neutral_mult: float = 0.88
@export var neutral_exhaustion_ratio: float = 0.30
@export var faction_war_drought_months: int = 4
@export var faction_war_pwin_bonus: float = 0.04
@export var faction_war_attack_score_mult: float = 1.55
@export var weak_target_pwin_bonus: float = 0.03
@export var weak_target_attack_score_bonus: float = 18.0
@export var noncritical_border_floor_mult: float = 0.92

func sanitize() -> void:
	attack_pwin_offset = clampf(attack_pwin_offset, -0.25, 0.25)
	attack_score_mult = clampf(attack_score_mult, 0.50, 1.75)
	reserve_floor_mult = clampf(reserve_floor_mult, 0.50, 1.50)
	fort_defense_mult = clampf(fort_defense_mult, 0.50, 1.50)
	chokepoint_defense_mult = clampf(chokepoint_defense_mult, 0.50, 1.50)
	fort_attack_bonus_mult = clampf(fort_attack_bonus_mult, 0.50, 1.75)
	max_attacks_bonus = clampi(max_attacks_bonus, -2, 3)
	starting_extra_generals_per_faction = clampi(starting_extra_generals_per_faction, 0, 3)
	treasury_reserve_mult = clampf(treasury_reserve_mult, 0.75, 2.0)
	recruit_econ_guard = clampf(recruit_econ_guard, 0.50, 1.75)
	fortify_econ_guard = clampf(fortify_econ_guard, 0.50, 1.75)
	attack_econ_guard = clampf(attack_econ_guard, 0.50, 1.75)
	surplus_war_chest_mult = clampf(surplus_war_chest_mult, 1.00, 3.00)
	surplus_attack_pwin_bonus = clampf(surplus_attack_pwin_bonus, 0.00, 0.20)
	anti_stalemate_month = clampi(anti_stalemate_month, 6, 60)
	anti_stalemate_pwin_bonus = clampf(anti_stalemate_pwin_bonus, 0.00, 0.20)
	anti_stalemate_attack_score_mult = clampf(anti_stalemate_attack_score_mult, 1.00, 2.00)
	anti_stalemate_max_attacks_bonus = clampi(anti_stalemate_max_attacks_bonus, 0, 3)
	fortify_surplus_mult = clampf(fortify_surplus_mult, 1.00, 2.50)
	front_primary_enemy_mult = clampf(front_primary_enemy_mult, 0.50, 2.00)
	front_secondary_enemy_mult = clampf(front_secondary_enemy_mult, 0.50, 2.00)
	front_primary_neutral_mult = clampf(front_primary_neutral_mult, 0.50, 2.00)
	front_secondary_neutral_mult = clampf(front_secondary_neutral_mult, 0.50, 2.00)
	neutral_exhaustion_ratio = clampf(neutral_exhaustion_ratio, 0.0, 1.0)
	faction_war_drought_months = clampi(faction_war_drought_months, 0, 24)
	faction_war_pwin_bonus = clampf(faction_war_pwin_bonus, 0.0, 0.20)
	faction_war_attack_score_mult = clampf(faction_war_attack_score_mult, 1.0, 2.0)
	weak_target_pwin_bonus = clampf(weak_target_pwin_bonus, 0.0, 0.20)
	weak_target_attack_score_bonus = clampf(weak_target_attack_score_bonus, 0.0, 60.0)
	noncritical_border_floor_mult = clampf(noncritical_border_floor_mult, 0.75, 1.05)
	shield_floor_mult = clampf(shield_floor_mult, 0.50, 1.50)
	source_exposure_mult = clampf(source_exposure_mult, 0.50, 2.00)
	hold_value_mult = clampf(hold_value_mult, 0.10, 3.00)
	attrition_floor_mult = clampf(attrition_floor_mult, 0.00, 2.00)
	econ_reserve_guard_mult = clampf(econ_reserve_guard_mult, 0.25, 2.00)
	war_pressure_bonus_mult = clampf(war_pressure_bonus_mult, 0.00, 3.00)
	post_neutral_war_bonus_mult = clampf(post_neutral_war_bonus_mult, 0.00, 3.00)

func duplicate_profile() -> AITuningProfile:
	var copy: AITuningProfile = AITuningProfile.new()
	copy.attack_pwin_offset = attack_pwin_offset
	copy.attack_score_mult = attack_score_mult
	copy.reserve_floor_mult = reserve_floor_mult
	copy.fort_defense_mult = fort_defense_mult
	copy.chokepoint_defense_mult = chokepoint_defense_mult
	copy.fort_attack_bonus_mult = fort_attack_bonus_mult
	copy.max_attacks_bonus = max_attacks_bonus
	copy.starting_extra_generals_per_faction = starting_extra_generals_per_faction
	copy.treasury_reserve_mult = treasury_reserve_mult
	copy.recruit_econ_guard = recruit_econ_guard
	copy.fortify_econ_guard = fortify_econ_guard
	copy.attack_econ_guard = attack_econ_guard
	copy.surplus_war_chest_mult = surplus_war_chest_mult
	copy.surplus_attack_pwin_bonus = surplus_attack_pwin_bonus
	copy.anti_stalemate_month = anti_stalemate_month
	copy.anti_stalemate_pwin_bonus = anti_stalemate_pwin_bonus
	copy.anti_stalemate_attack_score_mult = anti_stalemate_attack_score_mult
	copy.anti_stalemate_max_attacks_bonus = anti_stalemate_max_attacks_bonus
	copy.fortify_surplus_mult = fortify_surplus_mult
	copy.front_primary_enemy_mult = front_primary_enemy_mult
	copy.front_secondary_enemy_mult = front_secondary_enemy_mult
	copy.front_primary_neutral_mult = front_primary_neutral_mult
	copy.front_secondary_neutral_mult = front_secondary_neutral_mult
	copy.neutral_exhaustion_ratio = neutral_exhaustion_ratio
	copy.faction_war_drought_months = faction_war_drought_months
	copy.faction_war_pwin_bonus = faction_war_pwin_bonus
	copy.faction_war_attack_score_mult = faction_war_attack_score_mult
	copy.weak_target_pwin_bonus = weak_target_pwin_bonus
	copy.weak_target_attack_score_bonus = weak_target_attack_score_bonus
	copy.noncritical_border_floor_mult = noncritical_border_floor_mult
	copy.shield_floor_mult = shield_floor_mult
	copy.source_exposure_mult = source_exposure_mult
	copy.hold_value_mult = hold_value_mult
	copy.attrition_floor_mult = attrition_floor_mult
	copy.econ_reserve_guard_mult = econ_reserve_guard_mult
	copy.war_pressure_bonus_mult = war_pressure_bonus_mult
	copy.post_neutral_war_bonus_mult = post_neutral_war_bonus_mult
	copy.sanitize()
	return copy

func to_dictionary() -> Dictionary:
	return {
		"attack_pwin_offset": attack_pwin_offset,
		"attack_score_mult": attack_score_mult,
		"reserve_floor_mult": reserve_floor_mult,
		"fort_defense_mult": fort_defense_mult,
		"chokepoint_defense_mult": chokepoint_defense_mult,
		"fort_attack_bonus_mult": fort_attack_bonus_mult,
		"max_attacks_bonus": max_attacks_bonus,
		"starting_extra_generals_per_faction": starting_extra_generals_per_faction,
		"treasury_reserve_mult": treasury_reserve_mult,
		"recruit_econ_guard": recruit_econ_guard,
		"fortify_econ_guard": fortify_econ_guard,
		"attack_econ_guard": attack_econ_guard,
		"surplus_war_chest_mult": surplus_war_chest_mult,
		"surplus_attack_pwin_bonus": surplus_attack_pwin_bonus,
		"anti_stalemate_month": anti_stalemate_month,
		"anti_stalemate_pwin_bonus": anti_stalemate_pwin_bonus,
		"anti_stalemate_attack_score_mult": anti_stalemate_attack_score_mult,
		"anti_stalemate_max_attacks_bonus": anti_stalemate_max_attacks_bonus,
		"fortify_surplus_mult": fortify_surplus_mult,
		"front_primary_enemy_mult": front_primary_enemy_mult,
		"front_secondary_enemy_mult": front_secondary_enemy_mult,
		"front_primary_neutral_mult": front_primary_neutral_mult,
		"front_secondary_neutral_mult": front_secondary_neutral_mult,
		"neutral_exhaustion_ratio": neutral_exhaustion_ratio,
		"faction_war_drought_months": faction_war_drought_months,
		"faction_war_pwin_bonus": faction_war_pwin_bonus,
		"faction_war_attack_score_mult": faction_war_attack_score_mult,
		"weak_target_pwin_bonus": weak_target_pwin_bonus,
		"weak_target_attack_score_bonus": weak_target_attack_score_bonus,
		"noncritical_border_floor_mult": noncritical_border_floor_mult,
		"shield_floor_mult": shield_floor_mult,
		"source_exposure_mult": source_exposure_mult,
		"hold_value_mult": hold_value_mult,
		"attrition_floor_mult": attrition_floor_mult,
		"econ_reserve_guard_mult": econ_reserve_guard_mult,
		"war_pressure_bonus_mult": war_pressure_bonus_mult,
		"post_neutral_war_bonus_mult": post_neutral_war_bonus_mult,
	}

func apply_dictionary(values: Dictionary) -> void:
	attack_pwin_offset = float(values.get("attack_pwin_offset", attack_pwin_offset))
	attack_score_mult = float(values.get("attack_score_mult", attack_score_mult))
	reserve_floor_mult = float(values.get("reserve_floor_mult", reserve_floor_mult))
	fort_defense_mult = float(values.get("fort_defense_mult", fort_defense_mult))
	chokepoint_defense_mult = float(values.get("chokepoint_defense_mult", chokepoint_defense_mult))
	fort_attack_bonus_mult = float(values.get("fort_attack_bonus_mult", fort_attack_bonus_mult))
	max_attacks_bonus = int(values.get("max_attacks_bonus", max_attacks_bonus))
	starting_extra_generals_per_faction = int(values.get("starting_extra_generals_per_faction", starting_extra_generals_per_faction))
	treasury_reserve_mult = float(values.get("treasury_reserve_mult", treasury_reserve_mult))
	recruit_econ_guard = float(values.get("recruit_econ_guard", recruit_econ_guard))
	fortify_econ_guard = float(values.get("fortify_econ_guard", fortify_econ_guard))
	attack_econ_guard = float(values.get("attack_econ_guard", attack_econ_guard))
	surplus_war_chest_mult = float(values.get("surplus_war_chest_mult", surplus_war_chest_mult))
	surplus_attack_pwin_bonus = float(values.get("surplus_attack_pwin_bonus", surplus_attack_pwin_bonus))
	anti_stalemate_month = int(values.get("anti_stalemate_month", anti_stalemate_month))
	anti_stalemate_pwin_bonus = float(values.get("anti_stalemate_pwin_bonus", anti_stalemate_pwin_bonus))
	anti_stalemate_attack_score_mult = float(values.get("anti_stalemate_attack_score_mult", anti_stalemate_attack_score_mult))
	anti_stalemate_max_attacks_bonus = int(values.get("anti_stalemate_max_attacks_bonus", anti_stalemate_max_attacks_bonus))
	fortify_surplus_mult = float(values.get("fortify_surplus_mult", fortify_surplus_mult))
	front_primary_enemy_mult = float(values.get("front_primary_enemy_mult", front_primary_enemy_mult))
	front_secondary_enemy_mult = float(values.get("front_secondary_enemy_mult", front_secondary_enemy_mult))
	front_primary_neutral_mult = float(values.get("front_primary_neutral_mult", front_primary_neutral_mult))
	front_secondary_neutral_mult = float(values.get("front_secondary_neutral_mult", front_secondary_neutral_mult))
	neutral_exhaustion_ratio = float(values.get("neutral_exhaustion_ratio", neutral_exhaustion_ratio))
	faction_war_drought_months = int(values.get("faction_war_drought_months", faction_war_drought_months))
	faction_war_pwin_bonus = float(values.get("faction_war_pwin_bonus", faction_war_pwin_bonus))
	faction_war_attack_score_mult = float(values.get("faction_war_attack_score_mult", faction_war_attack_score_mult))
	weak_target_pwin_bonus = float(values.get("weak_target_pwin_bonus", weak_target_pwin_bonus))
	weak_target_attack_score_bonus = float(values.get("weak_target_attack_score_bonus", weak_target_attack_score_bonus))
	noncritical_border_floor_mult = float(values.get("noncritical_border_floor_mult", noncritical_border_floor_mult))
	shield_floor_mult = float(values.get("shield_floor_mult", shield_floor_mult))
	source_exposure_mult = float(values.get("source_exposure_mult", source_exposure_mult))
	hold_value_mult = float(values.get("hold_value_mult", hold_value_mult))
	attrition_floor_mult = float(values.get("attrition_floor_mult", attrition_floor_mult))
	econ_reserve_guard_mult = float(values.get("econ_reserve_guard_mult", econ_reserve_guard_mult))
	war_pressure_bonus_mult = float(values.get("war_pressure_bonus_mult", war_pressure_bonus_mult))
	post_neutral_war_bonus_mult = float(values.get("post_neutral_war_bonus_mult", post_neutral_war_bonus_mult))
	sanitize()

# --------------------------------------------------
# AutoTuner safe knobs — added for ai_autotuner.gd
# These are the only fields the autotuner is allowed to mutate.
# --------------------------------------------------
@export var shield_floor_mult: float = 1.09970644712448
@export var source_exposure_mult: float = 0.725532680749893
@export var hold_value_mult: float = 1.0862
@export var attrition_floor_mult: float = 1.0587
@export var econ_reserve_guard_mult: float = 0.757335364818573
@export var war_pressure_bonus_mult: float = 1.5
@export var post_neutral_war_bonus_mult: float = 1.5672286272049
