# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: MissionLab
#
# Role:
# Headless mission battle simulation harness.
# Evaluates win rates across three campaign brackets
# (early/mid/late game) to give a realistic picture
# of mission difficulty across a 72-month campaign arc.
#
# Bracket design:
#   Early  (months  1-18): avg leader level 2, Tier 1 armies
#   Mid    (months 19-48): avg leader level 6, mixed Tier 1/2 armies
#   Late   (months 49-72): avg leader level 10, Tier 2/3 armies
#
# Per-bracket elite win rate targets:
#   Early  -> 20% (brutal - elites not meant for new leaders)
#   Mid    -> 40% (hard but achievable with prepared army)
#   Late   -> 60% (veterans should win more often than not)
#
# Allowed Interactions:
# - BattleLab (reuses battle runner)
# - MissionTuningProfile (reads knobs)
# - UnitLibrary (reads unit templates)
#
# Forbidden Responsibilities:
# - Must not modify GameState
# - Must not touch UI
# - Must not queue campaign orders
# ==================================================

class_name MissionLab

const DebugLogger = preload("res://Scripts/debug/debug_logger.gd")

# Brackets: [label, leader_level, month_weight]
const BRACKETS: Array = [
	["early", 2,  0.25],
	["mid",   6,  0.45],
	["late",  9,  0.30],   # lv9 keeps elite enemies at Tier 2 — Tier 3 is too punishing to tune against
]

const ELITE_TARGETS: Dictionary = {
	"early": 0.20,
	"mid":   0.40,
	"late":  0.60,
}

const HUNT_TARGET:     float = 0.50
const TREASURE_TARGET: float = 0.55
const SKIRMISH_TARGET: float = 0.65


static func _build_attacker(rng: RandomNumberGenerator, leader_level: int) -> Dictionary:
	var leader_atk: int = 10 + leader_level * 2
	var leader_def: int = 8  + leader_level * 2
	var leader_hp: int  = 65 + leader_level * 3

	var tier_weights: Array
	if leader_level <= 4:
		tier_weights = [1.0, 0.0, 0.0]
	elif leader_level <= 7:
		tier_weights = [0.05, 0.95, 0.0]  # lv6-7: nearly full Tier 2 army
	elif leader_level <= 9:
		tier_weights = [0.0, 0.70, 0.30]  # lv8-9: Tier 2 dominant with Tier 3 veterans
	else:
		tier_weights = [0.05, 0.55, 0.40]

	var unit_count: int = clampi(3 + (leader_level / 3), 3, 6)
	var army: Dictionary = BattleLab._build_real_army(rng, unit_count, tier_weights)
	army["leader"]["attack"]  = leader_atk
	army["leader"]["defense"] = leader_def
	army["leader"]["hp"]      = leader_hp
	return army


static func _build_enemy(rng: RandomNumberGenerator, category: String, stat_scale: float, leader_level: int = 3) -> Dictionary:
	var unit_tier: int
	var unit_count: int
	var leader_atk: int
	var leader_def: int
	var leader_hp: int = int(65.0 * stat_scale)

	match category:
		"skirmish":
			unit_tier  = 1
			unit_count = rng.randi_range(2, 4)
			leader_atk = int(12.0 * stat_scale)
			leader_def = int(10.0 * stat_scale)
		"treasure":
			unit_tier  = 1
			unit_count = rng.randi_range(3, 5)
			leader_atk = int(13.0 * stat_scale)
			leader_def = int(11.0 * stat_scale)
		"hunt":
			unit_tier  = 1
			unit_count = rng.randi_range(3, 5)
			leader_atk = int(14.0 * stat_scale)
			leader_def = int(12.0 * stat_scale)
		"elite":
			# Tier tracks leader level, count stays 5-7, stat scale adjusted per bracket
			if leader_level >= 10:
				unit_tier  = 3
				stat_scale = stat_scale * 0.85
			elif leader_level >= 5:
				unit_tier  = 2
				stat_scale = stat_scale * 1.0
			else:
				unit_tier  = 1
				stat_scale = stat_scale * 1.25
			unit_count = rng.randi_range(5, 7)
			leader_atk = int(18.0 * stat_scale)
			leader_def = int(16.0 * stat_scale)
		_:
			unit_tier  = 1
			unit_count = 3
			leader_atk = int(12.0 * stat_scale)
			leader_def = int(10.0 * stat_scale)

	var units: Array = BattleLab._get_units_by_tier(unit_tier)
	if units.is_empty():
		units = BattleLab._get_units_by_tier(1)

	var enemy_units: Array = []
	for _i in range(unit_count):
		var tpl: Dictionary = units[rng.randi() % units.size()] as Dictionary
		enemy_units.append({
			"attack":      maxi(6,  int(float(tpl.get("attack",  11)) * stat_scale)),
			"defense":     maxi(4,  int(float(tpl.get("defense", 10)) * stat_scale)),
			"hp":          maxi(20, int(float(tpl.get("hp",      45)) * stat_scale)),
			"damage_type": str(tpl.get("damage_type", "slash")),
			"speed":       int(tpl.get("speed", 4)),
			"accuracy":    int(tpl.get("accuracy", 75)),
			"evasion":     int(tpl.get("evasion", 8)),
		})

	return {
		"leader": {
			"attack":      leader_atk,
			"defense":     leader_def,
			"hp":          leader_hp,
			"damage_type": "slash",
			"speed":       rng.randi_range(4, 7),
			"accuracy":    rng.randi_range(68, 80),
			"evasion":     rng.randi_range(8, 14),
		},
		"units": enemy_units,
	}


static func run_bracket_category(category: String, leader_level: int,
		bracket_label: String, seeds: int) -> Dictionary:
	var profile: MissionTuningProfile = MissionTuningProfile.get_instance()
	var wins: int = 0
	var total_rounds: float = 0.0
	var rng := RandomNumberGenerator.new()

	for i in range(seeds):
		rng.seed = i * 131 + category.hash() % 997 + leader_level * 7919
		var _sl: float = profile.elite_scale_low if category == "elite" else profile.scale_low
		var _sh: float = profile.elite_scale_high if category == "elite" else profile.scale_high
		var stat_scale: float = _sl + rng.randf() * (_sh - _sl)
		var attacker: Dictionary = _build_attacker(rng, leader_level)
		var enemy: Dictionary    = _build_enemy(rng, category, stat_scale, leader_level)
		var result: Dictionary   = BattleLab.run_battle(attacker, enemy,
			i * 131 + category.hash() % 997 + leader_level * 7919)
		if result.get("attacker_won", false):
			wins += 1
		total_rounds += float(result.get("rounds", 1))

	return {
		"bracket":           bracket_label,
		"category":          category,
		"leader_level":      leader_level,
		"seeds":             seeds,
		"attacker_win_rate": float(wins) / float(seeds),
		"avg_rounds":        total_rounds / float(seeds),
	}


static func estimate_sigils_per_leader(bracket_results: Dictionary) -> float:
	var profile: MissionTuningProfile = MissionTuningProfile.get_instance()
	var weighted_elite_wr: float = 0.0
	for b in BRACKETS:
		var label: String = str(b[0])
		var weight: float = float(b[2])
		var elite_data: Dictionary = bracket_results.get(label, {}).get("elite", {})
		weighted_elite_wr += float(elite_data.get("attacker_win_rate", 0.0)) * weight

	var cycles_per_slot: float = 72.0 / 2.5
	var elite_per_province: float = cycles_per_slot * profile.spawn_roll_chance * 0.25
	var elite_per_faction: float  = elite_per_province * 8.0

	var sigils_wins: float = elite_per_faction * weighted_elite_wr * profile.elite_sigil_chance
	var sigils_losses: float = 0.0
	if profile.elite_sigil_on_loss:
		sigils_losses = elite_per_faction * (1.0 - weighted_elite_wr) * profile.elite_sigil_chance

	var non_elite_per_faction: float = elite_per_province * 8.0 * 3.0
	var sigils_background: float = non_elite_per_faction * profile.non_elite_sigil_chance * 0.57

	return (sigils_wins + sigils_losses + sigils_background) / float(profile.target_leaders_per_faction)


static func run_full_suite(seeds: int = 20) -> Dictionary:
	var results: Dictionary = {}
	for b in BRACKETS:
		var label: String     = str(b[0])
		var lv: int           = int(b[1])
		results[label] = {
			"skirmish": run_bracket_category("skirmish", lv, label, seeds),
			"treasure": run_bracket_category("treasure", lv, label, seeds),
			"hunt":     run_bracket_category("hunt",     lv, label, seeds),
			"elite":    run_bracket_category("elite",    lv, label, seeds),
		}
	return results


static func score_results(results: Dictionary) -> float:
	var profile: MissionTuningProfile = MissionTuningProfile.get_instance()
	var score: float = 0.0
	var log_data: Dictionary = {}

	for b in BRACKETS:
		var label: String  = str(b[0])
		var weight: float  = float(b[2])
		var b_data: Dictionary = results.get(label, {})

		var elite_wr:    float = float(b_data.get("elite",    {}).get("attacker_win_rate", 0.0))
		var hunt_wr:     float = float(b_data.get("hunt",     {}).get("attacker_win_rate", 0.0))
		var treasure_wr: float = float(b_data.get("treasure", {}).get("attacker_win_rate", 0.0))
		var skirmish_wr: float = float(b_data.get("skirmish", {}).get("attacker_win_rate", 0.0))
		var elite_target: float = float(ELITE_TARGETS.get(label, 0.40))

		score -= abs(elite_wr    - elite_target)    * 300.0 * weight
		score -= abs(hunt_wr     - HUNT_TARGET)     * 150.0 * weight
		score -= abs(treasure_wr - TREASURE_TARGET) * 100.0 * weight
		score -= abs(skirmish_wr - SKIRMISH_TARGET) *  75.0 * weight

		if abs(elite_wr - elite_target) < 0.05:
			score += 50.0 * weight

		log_data[label] = {
			"elite_wr": elite_wr, "elite_target": elite_target,
			"hunt_wr": hunt_wr, "treasure_wr": treasure_wr, "skirmish_wr": skirmish_wr,
		}

	var estimated_sigils: float = estimate_sigils_per_leader(results)
	score -= abs(estimated_sigils - profile.target_sigils_per_leader) * 200.0
	if abs(estimated_sigils - profile.target_sigils_per_leader) < 0.3:
		score += 75.0

	DebugLogger.log("event:mission_lab_score", {
		"score":          score,
		"sigils_per_ldr": estimated_sigils,
		"brackets":       log_data,
	})

	return score
