# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: SkillLibrary (Sigil Integration Layer)
#
# Role:
# Bridge between battle_scene.gd skill UI and the new
# SigilLibrary / AugmentLibrary data + effect resolution.
# Replaces the old flat skill list with Sigil-based abilities.
#
# Allowed Interactions:
# - BattleScene (called for skill list + execute)
# - BattleState (reads units/targets)
# - SigilLibrary (reads sigil data)
# - AugmentLibrary (reads augment modifiers)
#
# Forbidden Responsibilities:
# - Must not own state
# - Must not call UI
# ==================================================

const SigilLibraryScript = preload("res://Scripts/data/sigil_library.gd")
const AugmentLibraryScript = preload("res://Scripts/data/augment_library.gd")

# Legacy SKILLS dict — kept for compatibility with any remaining references
const SKILLS: Dictionary = {}

# --------------------------------------------------
# UNIT SKILL RESOLUTION
# Returns list of skill names this unit can use
# --------------------------------------------------

static func get_unit_skills(unit) -> Array[String]:
	var result: Array[String] = []

	# Signature ability (leaders only, always available)
	if bool(unit.is_leader_combatant) and unit.leader_ref != null:
		var sig_id: String = str(unit.leader_ref.signature_ability_id) if unit.leader_ref.get("signature_ability_id") != null else ""
		if sig_id != "":
			var sig: Dictionary = SigilLibraryScript.get_signature_ability(sig_id)
			if not sig.is_empty():
				result.append(sig_id)

	# Equipped Sigil
	var sigil_id: String = _get_sigil_id(unit)
	if sigil_id != "":
		var s: Dictionary = SigilLibraryScript.get_sigil(sigil_id)
		if not s.is_empty():
			result.append(sigil_id)

	return result


static func _get_sigil_id(unit) -> String:
	if unit.has_method("get_equipped_sigil_id"):
		return unit.get_equipped_sigil_id()
	if bool(unit.is_leader_combatant):
		if unit.leader_ref != null:
			var sid = unit.leader_ref.get("equipped_sigil_id")
			if sid != null: return str(sid)
	else:
		if unit.unit_ref != null:
			var sid = unit.unit_ref.get("equipped_sigil_id")
			if sid != null: return str(sid)
	return ""


static func _get_augment_id(unit) -> String:
	if bool(unit.is_leader_combatant):
		if unit.leader_ref != null and "augment_id" in unit.leader_ref:
			return str(unit.leader_ref.augment_id)
	else:
		if unit.unit_ref != null and "augment_id" in unit.unit_ref:
			return str(unit.unit_ref.augment_id)
	return ""


static func get_skill_sp_cost(skill_id: String, unit) -> int:
	# Check signature abilities first
	var sig: Dictionary = SigilLibraryScript.get_signature_ability(skill_id)
	if not sig.is_empty():
		var base: int = int(sig.get("sp_cost", 10))
		# Apply augment SP modifier to signature abilities too
		var aug_id: String = _get_augment_id(unit)
		if aug_id != "":
			return AugmentLibraryScript.apply_sp_cost(base, aug_id)
		return base

	var s: Dictionary = SigilLibraryScript.get_sigil(skill_id)
	if s.is_empty():
		return 10
	var base: int = int(s.get("sp_cost", 10))
	var aug_id: String = _get_augment_id(unit)
	if aug_id != "":
		base = AugmentLibraryScript.apply_sp_cost(base, aug_id)
	# SP reduction cap: 30-40% max total
	var original: int = int(SigilLibraryScript.get_sigil(skill_id).get("sp_cost", 10))
	base = maxi(int(ceil(original * 0.60)), base)  # floor at 60% of original cost
	return base


static func get_skill_display_name(skill_id: String) -> String:
	var sig: Dictionary = SigilLibraryScript.get_signature_ability(skill_id)
	if not sig.is_empty():
		return str(sig.get("name", skill_id)) + " ✦"  # ✦ marks signature ability
	var s: Dictionary = SigilLibraryScript.get_sigil(skill_id)
	if not s.is_empty():
		return str(s.get("name", skill_id))
	return skill_id


static func get_skill_description(skill_id: String) -> String:
	var sig: Dictionary = SigilLibraryScript.get_signature_ability(skill_id)
	if not sig.is_empty():
		return str(sig.get("description", ""))
	var s: Dictionary = SigilLibraryScript.get_sigil(skill_id)
	return str(s.get("description", "")) if not s.is_empty() else ""


static func is_full_action(skill_id: String, unit) -> bool:
	var sig: Dictionary = SigilLibraryScript.get_signature_ability(skill_id)
	if not sig.is_empty():
		return str(sig.get("action_type", "standard")) == "full"
	var s: Dictionary = SigilLibraryScript.get_sigil(skill_id)
	if s.is_empty():
		return false
	if str(s.get("action_type", "standard")) == "full":
		return true
	# Check if augment forces full action
	var aug_id: String = _get_augment_id(unit)
	if aug_id != "":
		return AugmentLibraryScript.forces_full_action(aug_id)
	return false


static func needs_target(skill_id: String) -> bool:
	var data: Dictionary = SigilLibraryScript.get_signature_ability(skill_id)
	if data.is_empty():
		data = SigilLibraryScript.get_sigil(skill_id)
	var ttype: String = str(data.get("target_type", "enemy"))
	return ttype == "enemy" or ttype == "ally"


static func is_aoe(skill_id: String) -> bool:
	var data: Dictionary = SigilLibraryScript.get_signature_ability(skill_id)
	if data.is_empty():
		data = SigilLibraryScript.get_sigil(skill_id)
	var ttype: String = str(data.get("target_type", "enemy"))
	return ttype == "area"


static func get_skill_range(skill_id: String, unit) -> int:
	var data: Dictionary = SigilLibraryScript.get_signature_ability(skill_id)
	if data.is_empty():
		data = SigilLibraryScript.get_sigil(skill_id)
	var range_val: int = int(data.get("range", 1))
	if range_val == -1:
		# Use unit's attack range
		range_val = int(unit.attack_range) if "attack_range" in unit else 1
	# Extended Reach augment adds +1
	var aug_id: String = _get_augment_id(unit)
	if aug_id != "":
		var aug: Dictionary = AugmentLibraryScript.get_augment(aug_id)
		if str(aug.get("effect_modifier", "")) == "range_bonus":
			range_val += int(aug.get("effect_value", 0))
	return maxi(1, range_val)


# --------------------------------------------------
# EXECUTE SKILL
# Resolves Sigil effect and returns result dict
# --------------------------------------------------

static func execute(skill_id: String, user, target, state) -> Dictionary:
	var result: Dictionary = {
		"skill_id": skill_id,
		"effect":   "none",
		"target":   user.get_display_name() if target == null else target.get_display_name(),
	}

	# Get skill data (signature or sigil)
	var data: Dictionary = SigilLibraryScript.get_signature_ability(skill_id)
	var is_signature: bool = not data.is_empty()
	if data.is_empty():
		data = SigilLibraryScript.get_sigil(skill_id)
	if data.is_empty():
		result["effect"] = "unknown_skill"
		return result

	var effect_type: String = str(data.get("effect_type", ""))
	var aug_id: String = _get_augment_id(user)
	var aug: Dictionary = AugmentLibraryScript.get_augment(aug_id) if aug_id != "" else {}

	# -- DAMAGE effects --
	if effect_type in ["damage", "damage_armor_pierce", "damage_pct", "damage_pct_pierce", "flank_strike", "finisher", "momentum", "zone_strike", "volley_line"]:
		if target == null or not bool(target.is_alive):
			result["effect"] = "no_target"
			return result

		var base_pct: float = float(data.get("effect_value", float(data.get("damage_pct", 1.0))))

		# Apply augment damage modifier
		if not aug.is_empty():
			base_pct = AugmentLibraryScript.apply_damage_mult(base_pct, aug_id)

		# Cap combined damage multiplier at 2.5x
		base_pct = minf(base_pct, 2.50)

		# Conditional bonus
		var bonus_pct: float = 0.0
		var condition: String = str(data.get("condition", ""))
		if condition == "target_low_hp":
			var threshold: float = float(data.get("condition_value", 0.30))
			var hp_ratio: float = float(target.battle_hp) / float(maxi(1, target.final_max_hp))
			if hp_ratio <= threshold:
				bonus_pct = float(data.get("bonus_pct", 0.0))
		elif condition == "target_flanked":
			if _is_flanked(target, user, state):
				bonus_pct = float(data.get("bonus_pct", 0.0))
		elif condition == "self_killed_last_turn":
			if user.has_meta("killed_last_turn") and bool(user.get_meta("killed_last_turn")):
				bonus_pct = float(data.get("bonus_pct", 0.0))
		elif condition == "self_moved_this_turn":
			if bool(user.moved):
				bonus_pct = float(data.get("bonus_pct", 0.0))

		# Pressure augment bonus vs low HP
		if not aug.is_empty() and str(aug.get("effect_modifier", "")) == "bonus_vs_low_hp":
			var hp_ratio: float = float(target.battle_hp) / float(maxi(1, target.final_max_hp))
			if hp_ratio <= 0.30:
				# Only apply at full if no condition bonus already active
				if bonus_pct == 0.0:
					bonus_pct += float(aug.get("effect_value", 0.0))
				else:
					bonus_pct += float(aug.get("effect_value", 0.0)) * 0.5  # diminish when stacking

		var total_pct: float = minf(base_pct + bonus_pct, 2.50)  # hard cap

		# Armor pierce — sigils use effect_value2, legacy used armor_pierce
		var armor_pierce: float = float(data.get("effect_value2", float(data.get("armor_pierce", 0.0))))
		if not aug.is_empty() and str(aug.get("effect_modifier", "")) == "debuff_defense":
			armor_pierce += float(aug.get("effect_value", 0.0))

		# Accuracy modifier
		var acc_bonus: int = int(data.get("accuracy_bonus", 0))
		if not aug.is_empty() and str(aug.get("effect_modifier", "")) == "accuracy_bonus":
			acc_bonus += int(aug.get("effect_value", 0))

		# Calculate damage
		var raw_atk: int = int(user.final_attack)
		var eff_def: int = maxi(0, int(round(float(target.final_defense) * (1.0 - armor_pierce))))

		# Apply mark bonus
		var mark_bonus: float = 0.0
		if target.has_meta("marked"):
			mark_bonus = float(target.get_meta("marked_bonus", 0.35))
			target.remove_meta("marked")
			if target.has_meta("marked_bonus"):
				target.remove_meta("marked_bonus")

		var dmg: int = maxi(1, int(round(float(raw_atk) * (total_pct + mark_bonus))) - eff_def)

		# Lifesteal (Drain augment)
		if not aug.is_empty() and str(aug.get("effect_modifier", "")) == "lifesteal":
			var heal_amt: int = int(round(float(dmg) * float(aug.get("effect_value", 0.20))))
			user.battle_hp = mini(user.battle_hp + heal_amt, user.final_max_hp)
			result["lifesteal"] = heal_amt

		# Sunder augment — debuff target defense
		if not aug.is_empty() and str(aug.get("effect_modifier", "")) == "debuff_defense":
			var def_reduce: int = int(round(float(target.final_defense) * float(aug.get("effect_value", 0.15))))
			target.final_defense = maxi(1, target.final_defense - def_reduce)
			target.set_meta("defense_debuffed", true)
			result["defense_debuffed"] = def_reduce

		# Sweep AoE
		if not aug.is_empty() and str(aug.get("effect_modifier", "")) == "aoe_cross":
			var sec_pct: float = float(aug.get("secondary_damage_pct", 0.60))
			var enemies: Array = state.defender_units if user.side == "attacker" else state.attacker_units
			for enemy in enemies:
				if enemy == null or not bool(enemy.is_alive) or enemy == target:
					continue
				var dist: int = abs(enemy.grid_pos.x - target.grid_pos.x) + abs(enemy.grid_pos.y - target.grid_pos.y)
				if dist <= 1:
					var sec_dmg: int = maxi(1, int(round(float(raw_atk) * total_pct * sec_pct)) - eff_def)
					enemy.battle_hp -= sec_dmg
					if enemy.battle_hp <= 0:
						enemy.is_alive = false
			result["aoe_sweep"] = true

		# Zone Strike / Rain Volley AoE
		if effect_type == "aoe_line" or effect_type == "aoe_zone":
			var sec_pct: float = float(data.get("aoe_secondary_pct", 0.60))
			var enemies: Array = state.defender_units if user.side == "attacker" else state.attacker_units
			for enemy in enemies:
				if enemy == null or not bool(enemy.is_alive) or enemy == target:
					continue
				var dist: int = abs(enemy.grid_pos.x - target.grid_pos.x) + abs(enemy.grid_pos.y - target.grid_pos.y)
				var include: bool = false
				if effect_type == "aoe_zone" and dist <= 1:
					include = true
				elif effect_type == "aoe_line":
					# Line behind target from user
					var dx: int = target.grid_pos.x - user.grid_pos.x
					var dy: int = target.grid_pos.y - user.grid_pos.y
					if dx != 0: dx = int(sign(dx))
					if dy != 0: dy = int(sign(dy))
					if enemy.grid_pos == Vector2i(target.grid_pos.x + dx, target.grid_pos.y + dy):
						include = true
				if include:
					var sec_dmg: int = maxi(1, int(round(float(raw_atk) * total_pct * sec_pct)) - eff_def)
					enemy.battle_hp -= sec_dmg
					if enemy.battle_hp <= 0:
						enemy.is_alive = false
			result["aoe"] = true

		# All-In augment — self defense penalty
		if not aug.is_empty() and str(aug.get("effect_modifier", "")) == "self_defense_penalty":
			var pen: float = float(aug.get("effect_value", 0.20))
			var def_pen: int = int(round(float(user.final_defense) * pen))
			user.final_defense = maxi(1, user.final_defense - def_pen)
			user.set_meta("all_in_penalty", def_pen)
			result["self_defense_penalty"] = def_pen

		target.battle_hp -= dmg
		if target.battle_hp <= 0:
			target.is_alive = false
		result["damage"] = dmg
		result["effect"] = "skill_damage"
		result["xp_gained"] = dmg + (20 if target.battle_hp <= 0 else 0)
		result["killed"] = target.battle_hp <= 0

	# -- HEAL effects --
	elif effect_type in ["heal", "heal_pct"]:
		var heal_tgt = target if target != null else user
		var heal_pct: float = float(data.get("effect_value", float(data.get("heal_pct", 0.20))))
		if not aug.is_empty():
			heal_pct = maxf(0.05, heal_pct + float(aug.get("damage_mult", 0.0)))
		var heal_amt: int = int(round(float(heal_tgt.final_max_hp) * heal_pct))
		# Guarded augment — reduce effectiveness but add self defense
		if not aug.is_empty() and str(aug.get("effect_modifier", "")) == "self_defense_bonus":
			var def_bon: int = int(round(float(user.final_defense) * float(aug.get("effect_value", 0.20))))
			user.final_defense += def_bon
			user.set_meta("guarded_bonus", def_bon)
		heal_tgt.battle_hp = mini(heal_tgt.battle_hp + heal_amt, heal_tgt.final_max_hp)
		result["healed"] = heal_amt
		result["effect"] = "heal"
		result["xp_gained"] = 5

	# -- BUFF ATTACK --
	elif effect_type in ["buff_attack", "command_ally", "command_surge", "buff_team_attack"]:
		var tgt = target if target != null else user
		var buff: float = float(data.get("effect_value", float(data.get("buff_value", 0.15))))
		if not aug.is_empty():
			buff = maxf(0.01, buff + float(aug.get("damage_mult", 0.0)))
		var atk_gain: int = int(round(float(tgt.final_attack) * buff))
		tgt.final_attack += atk_gain
		tgt.set_meta("attack_buffed", int(tgt.get_meta("attack_buffed", 0)) + atk_gain)
		result["attack_buffed"] = atk_gain
		result["effect"] = "buff_attack"
		if effect_type == "command_ally" and tgt.has_method("get"):
			# SP reduction on next action — store as meta
			var sp_red: float = float(data.get("sp_reduction", 0.20))
			tgt.set_meta("sp_reduction_next", sp_red)
		result["xp_gained"] = 5

	# -- BUFF DEFENSE / BRACE --
	elif effect_type in ["buff_defense", "brace", "buff_team_defense"]:
		var tgt = target if target != null else user
		var buff: float = float(data.get("effect_value", float(data.get("buff_value", 0.20))))
		if not aug.is_empty():
			buff = maxf(0.01, buff + float(aug.get("damage_mult", 0.0)))
		var def_gain: int = int(round(float(tgt.final_defense) * buff))
		tgt.final_defense += def_gain
		tgt.set_meta("defense_buffed", int(tgt.get_meta("defense_buffed", 0)) + def_gain)
		result["defense_buffed"] = def_gain
		result["effect"] = "buff_defense"
		result["xp_gained"] = 5

	# -- DEBUFF DEFENSE --
	elif effect_type == "debuff_defense":
		if target == null or not bool(target.is_alive):
			result["effect"] = "no_target"
			return result
		var debuff: float = float(data.get("effect_value", float(data.get("debuff_value", 0.15))))
		var def_lose: int = int(round(float(target.final_defense) * debuff))
		target.final_defense = maxi(1, target.final_defense - def_lose)
		target.set_meta("defense_debuffed", true)
		result["debuff_defense"] = def_lose
		result["effect"] = "debuff_defense"
		result["xp_gained"] = 5

	# -- MARK --
	elif effect_type == "mark":
		if target == null or not bool(target.is_alive):
			result["effect"] = "no_target"
			return result
		var bonus: float = float(data.get("effect_value", float(data.get("bonus_pct", 0.35))))
		bonus = minf(bonus, 0.70)
		target.set_meta("marked", true)
		target.set_meta("marked_bonus", bonus)
		result["effect"] = "marked"
		result["mark_bonus"] = bonus
		result["xp_gained"] = 5

	# -- DISRUPT --
	elif effect_type == "disrupt":
		if target == null or not bool(target.is_alive):
			result["effect"] = "no_target"
			return result
		# Apply normal damage too
		var dmg: int = maxi(1, int(user.final_attack) - int(target.final_defense))
		target.battle_hp -= dmg
		if target.battle_hp <= 0:
			target.is_alive = false
		target.disrupted = true
		target.sigil_disabled = true
		result["damage"] = dmg
		result["effect"] = "disrupt"
		result["killed"] = target.battle_hp <= 0
		result["xp_gained"] = dmg + (20 if target.battle_hp <= 0 else 0)

	# -- PIN --
	elif effect_type == "pin":
		if target == null or not bool(target.is_alive):
			result["effect"] = "no_target"
			return result
		var dmg: int = maxi(1, int(user.final_attack) - int(target.final_defense))
		target.battle_hp -= dmg
		if target.battle_hp <= 0:
			target.is_alive = false
		target.pinned = true
		result["damage"] = dmg
		result["effect"] = "pinned"
		result["killed"] = target.battle_hp <= 0
		result["xp_gained"] = dmg + (20 if target.battle_hp <= 0 else 0)

	# -- RIPOSTE / COUNTER STANCE --
	elif effect_type in ["riposte", "counter_stance"]:
		user.set_meta("riposte_ready", true)
		result["effect"] = "riposte_ready"
		result["xp_gained"] = 0

	# -- LAST STAND --
	elif effect_type in ["last_stand", "survive_lethal"]:
		user.set_meta("last_stand_active", true)
		result["effect"] = "last_stand"
		result["xp_gained"] = 0

	# -- DELAYED STRIKE --
	elif effect_type == "delayed_strike":
		if target == null or not bool(target.is_alive):
			result["effect"] = "no_target"
			return result
		var dmg_pct: float = float(data.get("damage_pct", 1.80))
		target.set_meta("delayed_strike_pending", int(round(float(user.final_attack) * dmg_pct)))
		target.set_meta("delayed_strike_from", user)
		result["effect"] = "delayed_strike"
		result["xp_gained"] = 0

	# -- FORCE ENGAGE --
	elif effect_type == "force_engage":
		if target == null or not bool(target.is_alive):
			result["effect"] = "no_target"
			return result
		target.set_meta("force_engage", true)
		result["effect"] = "force_engage"
		result["xp_gained"] = 5

	# -- MOMENTUM --
	elif effect_type == "momentum":
		# Handled via damage block above with condition check
		result["effect"] = "momentum"

	else:
		result["effect"] = "unknown_skill"

	return result


static func _is_flanked(target, attacker, state) -> bool:
	# Target is flanked if an ally of the attacker is adjacent to it
	var attacker_allies: Array = state.attacker_units if attacker.side == "attacker" else state.defender_units
	for ally in attacker_allies:
		if ally == null or not bool(ally.is_alive) or ally == attacker:
			continue
		var dist: int = abs(ally.grid_pos.x - target.grid_pos.x) + abs(ally.grid_pos.y - target.grid_pos.y)
		if dist <= 1:
			return true
	return false


# --------------------------------------------------
# TURN RESET
# Called at start of each unit's turn
# --------------------------------------------------

static func reset_turn_effects(unit) -> void:
	# Clear per-turn buffs
	if unit.has_meta("attack_buffed"):
		unit.final_attack = maxi(1, unit.final_attack - int(unit.get_meta("attack_buffed")))
		unit.remove_meta("attack_buffed")
	if unit.has_meta("defense_buffed"):
		unit.final_defense = maxi(1, unit.final_defense - int(unit.get_meta("defense_buffed")))
		unit.remove_meta("defense_buffed")
	if unit.has_meta("guarded_bonus"):
		unit.final_defense = maxi(1, unit.final_defense - int(unit.get_meta("guarded_bonus")))
		unit.remove_meta("guarded_bonus")
	if unit.has_meta("all_in_penalty"):
		unit.final_defense = mini(unit.final_defense + int(unit.get_meta("all_in_penalty")), unit.final_max_hp)
		unit.remove_meta("all_in_penalty")

	# Control flag reset
	unit.disrupted = false
	unit.sigil_disabled = false
	unit.pinned = false

	# Delayed strike trigger
	if unit.has_meta("delayed_strike_pending"):
		var dmg: int = int(unit.get_meta("delayed_strike_pending"))
		unit.battle_hp -= dmg
		if unit.battle_hp <= 0:
			unit.is_alive = false
		unit.remove_meta("delayed_strike_pending")
		if unit.has_meta("delayed_strike_from"):
			unit.remove_meta("delayed_strike_from")

	# Last stand — survives lethal hit, gains attack boost
	if unit.has_meta("last_stand_triggered"):
		unit.battle_hp = maxi(1, unit.battle_hp)
		unit.final_attack = int(round(float(unit.final_attack) * 1.20))
		unit.set_meta("last_stand_attack_boost", true)
		unit.remove_meta("last_stand_triggered")
