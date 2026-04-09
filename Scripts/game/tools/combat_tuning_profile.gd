# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: CombatTuningProfile
#
# Role:
# Stores tweakable strategic-layer combat attrition and recovery knobs.
# These values apply equally to human and AI factions because the combat
# resolver is shared by both.
# ==================================================
extends Resource
class_name CombatTuningProfile

@export var attack_win_loss_min: float = 0.18
@export var attack_win_loss_max: float = 0.28
@export var attack_loss_loss_min: float = 0.32
@export var attack_loss_loss_max: float = 0.48
@export var defense_win_loss_min: float = 0.12
@export var defense_win_loss_max: float = 0.22
@export var defense_loss_loss_min: float = 0.28
@export var defense_loss_loss_max: float = 0.42

@export var minimum_damage_per_engaged_unit: int = 1

@export var wound_turns: int = 4
@export var attack_win_wound_chance: float = 0.08
@export var attack_loss_wound_chance: float = 0.18
@export var defense_win_wound_chance: float = 0.06
@export var defense_loss_wound_chance: float = 0.16

@export var safe_recovery_ratio: float = 0.10

# Immediate paid-heal model
# active_heal_base_cost + (missing_hp * active_heal_gold_per_hp)
@export var active_heal_base_cost: int = 25
@export var active_heal_gold_per_hp: int = 3

# Compatibility fields for the resolver/UI patch currently in use.
# These mirror the same heal model so older/newer scripts can read either name.
@export var active_heal_flat_cost: int = 25
@export var active_heal_missing_hp_cost: int = 3

func sanitize() -> void:
	attack_win_loss_min = clampf(attack_win_loss_min, 0.00, 1.00)
	attack_win_loss_max = clampf(attack_win_loss_max, attack_win_loss_min, 1.00)
	attack_loss_loss_min = clampf(attack_loss_loss_min, 0.00, 1.00)
	attack_loss_loss_max = clampf(attack_loss_loss_max, attack_loss_loss_min, 1.00)
	defense_win_loss_min = clampf(defense_win_loss_min, 0.00, 1.00)
	defense_win_loss_max = clampf(defense_win_loss_max, defense_win_loss_min, 1.00)
	defense_loss_loss_min = clampf(defense_loss_loss_min, 0.00, 1.00)
	defense_loss_loss_max = clampf(defense_loss_loss_max, defense_loss_loss_min, 1.00)

	minimum_damage_per_engaged_unit = clampi(minimum_damage_per_engaged_unit, 0, 99)

	wound_turns = clampi(wound_turns, 1, 12)
	attack_win_wound_chance = clampf(attack_win_wound_chance, 0.0, 1.0)
	attack_loss_wound_chance = clampf(attack_loss_wound_chance, 0.0, 1.0)
	defense_win_wound_chance = clampf(defense_win_wound_chance, 0.0, 1.0)
	defense_loss_wound_chance = clampf(defense_loss_wound_chance, 0.0, 1.0)

	safe_recovery_ratio = clampf(safe_recovery_ratio, 0.0, 1.0)

	active_heal_base_cost = clampi(active_heal_base_cost, 0, 9999)
	active_heal_gold_per_hp = clampi(active_heal_gold_per_hp, 0, 999)
	active_heal_flat_cost = clampi(active_heal_flat_cost, 0, 9999)
	active_heal_missing_hp_cost = clampi(active_heal_missing_hp_cost, 0, 999)

	# Keep both naming schemes in sync.
	active_heal_flat_cost = active_heal_base_cost if active_heal_base_cost != active_heal_flat_cost and active_heal_flat_cost == 25 else active_heal_flat_cost
	active_heal_missing_hp_cost = active_heal_gold_per_hp if active_heal_gold_per_hp != active_heal_missing_hp_cost and active_heal_missing_hp_cost == 3 else active_heal_missing_hp_cost
	active_heal_base_cost = active_heal_flat_cost
	active_heal_gold_per_hp = active_heal_missing_hp_cost

func get_active_heal_cost_for_missing_hp(missing_hp: int) -> int:
	var safe_missing_hp: int = maxi(0, missing_hp)
	return int(active_heal_flat_cost) + (safe_missing_hp * int(active_heal_missing_hp_cost))

func to_dictionary() -> Dictionary:
	return {
		"attack_win_loss_min": attack_win_loss_min,
		"attack_win_loss_max": attack_win_loss_max,
		"attack_loss_loss_min": attack_loss_loss_min,
		"attack_loss_loss_max": attack_loss_loss_max,
		"defense_win_loss_min": defense_win_loss_min,
		"defense_win_loss_max": defense_win_loss_max,
		"defense_loss_loss_min": defense_loss_loss_min,
		"defense_loss_loss_max": defense_loss_loss_max,
		"minimum_damage_per_engaged_unit": minimum_damage_per_engaged_unit,
		"wound_turns": wound_turns,
		"attack_win_wound_chance": attack_win_wound_chance,
		"attack_loss_wound_chance": attack_loss_wound_chance,
		"defense_win_wound_chance": defense_win_wound_chance,
		"defense_loss_wound_chance": defense_loss_wound_chance,
		"safe_recovery_ratio": safe_recovery_ratio,
		"active_heal_base_cost": active_heal_base_cost,
		"active_heal_gold_per_hp": active_heal_gold_per_hp,
		"active_heal_flat_cost": active_heal_flat_cost,
		"active_heal_missing_hp_cost": active_heal_missing_hp_cost,
	}
