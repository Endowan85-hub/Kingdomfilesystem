# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: BattleResolver
#
# Role:
# Executes core battle actions (move, attack, death, win check).
# Implements full combat math per spec:
#   - Damage triangle (Slash / Pierce / Blunt)
#   - Defend bonus (doubled defense reduction)
#   - Leader stat bonuses (+1 atk/def at stat >= 7)
#   - RNG variance (±2)
#
# Allowed Interactions:
# - BattleState
# - BattleUnit
# - DebugLogger
#
# Forbidden Responsibilities:
# - Must not modify GameState
#
# Game Phase:
# Execution Phase (Battle Only)
# ==================================================

class_name BattleResolver

# ---------------------------------------------------------------------------
# Damage triangle
# Row = attacker damage type, Col = defender damage type
# 1.25 = advantage, 0.85 = disadvantage, 1.0 = neutral
# ---------------------------------------------------------------------------
const DAMAGE_TRIANGLE: Dictionary = {
	"slash":  {"slash": 1.0,  "pierce": 1.25, "blunt": 0.85},
	"pierce": {"slash": 0.85, "pierce": 1.0,  "blunt": 1.25},
	"blunt":  {"slash": 1.25, "pierce": 0.85, "blunt": 1.0},
}


static func attack(state, attacker, defender) -> Dictionary:
	if not attacker.is_alive or not defender.is_alive:
		return {}

	# --- Hit / Miss roll ---
	# hit_chance = clamp(accuracy - max(0, (def_spd - atk_spd) * 2) - def_evasion, floor, 95)
	# Leaders have a minimum floor of 70% — elite combatants never fumble badly
	# Units have a floor of 50%
	var atk_spd: int = int(attacker.speed)
	var def_spd: int = int(defender.speed)
	var speed_penalty: int = maxi(0, (def_spd - atk_spd) * 2)
	var hit_floor: int = 70 if bool(attacker.is_leader_combatant) else 50
	var hit_chance: int = clampi(
		int(attacker.final_accuracy) - speed_penalty - int(defender.final_evasion),
		hit_floor, 95
	)
	var hit_roll: int = state.rng.randi_range(1, 100)
	if hit_roll > hit_chance:
		state.log.append("%s misses %s" % [attacker.get_display_name(), defender.get_display_name()])
		DebugLogger.log("event:battle_action", {
			"round":       int(state.round),
			"unit_name":   attacker.get_display_name(),
			"target_name": defender.get_display_name(),
			"side":        str(attacker.side),
			"action":      "miss",
			"hit_chance":  hit_chance,
			"hit_roll":    hit_roll,
		})
		return {"xp_gained": 0, "killed": false, "missed": true}

	# --- Damage triangle ---
	var atk_type: String = _get_damage_type(attacker)
	var def_type: String = _get_damage_type(defender)
	var type_row: Dictionary = DAMAGE_TRIANGLE.get(atk_type, DAMAGE_TRIANGLE["slash"])
	var raw_mult: float = float(type_row.get(def_type, 1.0))
	var tuning: BattleTuningProfile = BattleTuningProfile.get_instance()
	var type_mult: float = raw_mult
	if raw_mult > 1.0:
		type_mult = tuning.type_advantage_mult
	elif raw_mult < 1.0:
		type_mult = tuning.type_disadvantage_mult

	# --- Base attack with leader bonus ---
	var base_attack: int = int(attacker.final_attack)
	var leader_atk_bonus: int = 0
	if bool(attacker.is_leader_combatant) and attacker.leader_ref != null:
		leader_atk_bonus = int(float(attacker.leader_ref.attack) * tuning.leader_atk_bonus_fraction)
	base_attack += leader_atk_bonus

	# --- Defense — percentage mitigation via tuning profile ---
	var base_defense: int = int(defender.final_defense)
	var leader_def_bonus: int = 0
	if bool(defender.is_leader_combatant) and defender.leader_ref != null:
		leader_def_bonus = int(float(defender.leader_ref.defense) * tuning.leader_def_bonus_fraction)
	base_defense += leader_def_bonus

	if bool(defender.is_defending):
		base_defense = int(float(base_defense) * tuning.defend_mult)

	var mitigation: float = float(base_defense) / (float(base_defense) + tuning.def_constant)
	var raw: float = float(base_attack) * type_mult * (1.0 - mitigation)

	# --- Variance: fraction of raw damage ---
	var variance_range: int = maxi(1, int(raw * tuning.variance_fraction))
	var variance: int = state.rng.randi_range(-variance_range, variance_range)
	var dmg: int = maxi(1, int(raw) + variance)

	var hp_before: int = int(defender.battle_hp)
	defender.battle_hp -= dmg

	# Last Stand — survive lethal hit once, trigger on next turn start
	if defender.battle_hp <= 0 and defender.has_meta("last_stand_active"):
		defender.battle_hp = 1
		defender.remove_meta("last_stand_active")
		defender.set_meta("last_stand_triggered", true)
		state.log.append("%s triggers Last Stand!" % defender.get_display_name())

	# Riposte — counter if defender has riposte active
	if defender.has_meta("riposte_ready") and bool(defender.is_alive) and defender.battle_hp > 0:
		var counter_dmg: int = maxi(1, int(defender.final_attack) - int(attacker.final_defense))
		attacker.battle_hp -= counter_dmg
		defender.remove_meta("riposte_ready")
		if attacker.battle_hp <= 0:
			attacker.is_alive = false
		state.log.append("%s ripostes for %d!" % [defender.get_display_name(), counter_dmg])

	# --- Log ---
	state.log.append("%s hits %s for %d" % [attacker.get_display_name(), defender.get_display_name(), dmg])
	DebugLogger.log("event:battle_action", {
		"round":           int(state.round),
		"unit_name":       attacker.get_display_name(),
		"target_name":     defender.get_display_name(),
		"side":            str(attacker.side),
		"action":          "attack",
		"damage":          dmg,
		"base_attack":     base_attack,
		"defense_used":    base_defense,
		"mitigation_pct":  int(mitigation * 100),
		"type_mult":       type_mult,
		"atk_damage_type": atk_type,
		"def_damage_type": def_type,
		"defending":       bool(defender.is_defending),
		"variance":        variance,
		"target_hp_before": hp_before,
		"target_hp_after":  max(0, int(defender.battle_hp)),
		"grid_pos":        [int(attacker.grid_pos.x), int(attacker.grid_pos.y)],
		"target_grid_pos": [int(defender.grid_pos.x), int(defender.grid_pos.y)],
		"is_leader":       bool(attacker.is_leader_combatant),
	})

	var killed: bool = defender.battle_hp <= 0
	if killed:
		defender.is_alive = false
		state.log.append("%s fell" % defender.get_display_name())
		DebugLogger.log("event:battle_unit_died", {
			"round":     int(state.round),
			"unit_name": defender.get_display_name(),
			"side":      str(defender.side),
			"grid_pos":  [int(defender.grid_pos.x), int(defender.grid_pos.y)],
			"is_leader": bool(defender.is_leader_combatant),
		})

	# XP for attacker: damage dealt + kill bonus
	var xp_gain: int = dmg + (20 if killed else 0)
	return {"xp_gained": xp_gain, "killed": killed}


static func check_win(state) -> void:
	var atk_alive: bool = false
	var def_alive: bool = false

	for u in state.attacker_units:
		if bool(u.is_alive):
			atk_alive = true
			break

	for u in state.defender_units:
		if bool(u.is_alive):
			def_alive = true
			break

	if not atk_alive or not def_alive:
		state.phase = "battle_end"
		var attacker_losses: int = 0
		var defender_losses: int = 0
		for u in state.attacker_units:
			if not bool(u.is_alive):
				attacker_losses += 1
		for u in state.defender_units:
			if not bool(u.is_alive):
				defender_losses += 1
		DebugLogger.log("event:battle_ended", {
			"outcome":         "attacker_win" if not def_alive else "defender_win",
			"rounds_taken":    int(state.round),
			"attacker_losses": attacker_losses,
			"defender_losses": defender_losses,
		})


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
static func _get_damage_type(unit) -> String:
	# Leader combatants use their own damage_type from LeaderData
	if bool(unit.is_leader_combatant):
		if unit.leader_ref != null and "damage_type" in unit.leader_ref:
			var ldt: String = str(unit.leader_ref.damage_type).to_lower().strip_edges()
			if ldt in DAMAGE_TRIANGLE:
				return ldt
		return "slash"  # fallback for leaders without damage_type set
	if unit.unit_ref == null:
		return "slash"
	if "damage_type" in unit.unit_ref:
		var dt: String = str(unit.unit_ref.damage_type).to_lower().strip_edges()
		if dt in DAMAGE_TRIANGLE:
			return dt
	# Infer from unit type name as fallback
	var utype: String = str(unit.unit_ref.unit_type).to_lower()
	if "spear" in utype or "pike" in utype or "lance" in utype or "archer" in utype \
			or "crossbow" in utype or "harpoon" in utype or "ranger" in utype or "sniper" in utype:
		return "pierce"
	if "hammer" in utype or "mace" in utype or "stonebreaker" in utype or "titan" in utype \
			or "breaker" in utype:
		return "blunt"
	return "slash"

# --- XP SYSTEM ---
static func _award_xp(attacker, damage: int, killed: bool) -> void:
	if attacker == null:
		return
	var gain := damage
	if killed:
		gain += 20
	attacker.xp += gain
	if attacker.xp >= attacker.level * 100:
		attacker.xp = 0
		attacker.level += 1


static func _build_unit_snapshots(state) -> Array:
	var snaps: Array = []
	if state == null:
		return snaps

	for unit in state.attacker_units:
		if unit == null:
			continue
		if bool(unit.is_leader_combatant) and unit.leader_ref != null:
			snaps.append({
				"leader_id": int(unit.leader_ref.id),
				"xp": int(unit.xp) if "xp" in unit else 0,
				"level": int(unit.level) if "level" in unit else 1
			})

	for unit in state.defender_units:
		if unit == null:
			continue
		if bool(unit.is_leader_combatant) and unit.leader_ref != null:
			snaps.append({
				"leader_id": int(unit.leader_ref.id),
				"xp": int(unit.xp) if "xp" in unit else 0,
				"level": int(unit.level) if "level" in unit else 1
			})

	return snaps
