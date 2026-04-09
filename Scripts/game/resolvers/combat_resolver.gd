# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: CombatResolver
#
# Role:
# Resolves queued attacks using unit stat totals (attack, defense)
# rather than raw CP. Damage type resistances apply per unit matchup.
# Attack power = sum of unit attack stats for participating leaders.
# Defense power = sum of unit defense stats for defending province units
#                 plus fort and chokepoint bonuses.
#
# Strategic attrition is now applied here so both human and AI armies
# take recoverable losses before the tactical battle layer exists.
# ==================================================

class_name CombatResolver
extends RefCounted

const BattleManager = preload("res://Scripts/game/battle/battle_manager.gd")

const FORT_ATTACK_BONUS_PER_LEVEL: int = 10
const FORT_DEF_MULT: int = 10
const CHOKE_DEF_BONUS: int = 20

# Damage type advantage multipliers
# attacker_type -> { defender_type -> multiplier }
const DAMAGE_ADVANTAGE: Dictionary = {
	"pierce": { "blunt": 1.25,  "slash": 0.85,  "pierce": 1.0 },
	"blunt":  { "slash": 1.25,  "pierce": 0.85, "blunt":  1.0 },
	"slash":  { "pierce": 1.25, "blunt": 0.85,  "slash":  1.0 },
}

# Destination province for item drops from dead units — set per battle before
# _apply_attrition so _apply_damage_to_leader_army can route items correctly.
var _item_destination_province: int = -1


func _tuning_float(state: GameState, field_name: String, default_value: float) -> float:
	if state == null or not state.has_method("get_ai_tuning_profile"):
		return default_value
	var profile = state.get_ai_tuning_profile()
	if profile == null:
		return default_value
	var values: Dictionary = profile.to_dictionary()
	return float(values.get(field_name, default_value))


func _combat_tuning(state: GameState):
	if state == null or not state.has_method("get_combat_tuning_profile"):
		return null
	var profile = state.get_combat_tuning_profile()
	if profile != null and profile.has_method("sanitize"):
		profile.sanitize()
	return profile


func resolve(state: GameState) -> void:
	var map_data: MapData = state.map_data
	var ob: OrderBook = state.order_book
	var rng: RandomNumberGenerator = state.rng
	var log: DebugLogger = state.logger

	var attempted: int = 0
	var applied: int = 0
	var skipped_owner: int = 0
	var skipped_no_strength: int = 0
	var skipped_friendly: int = 0
	var attacker_wins: int = 0
	var defender_holds: int = 0
	var captures: Array = []

	for item in map_data.factions:
		var f: FactionData = item as FactionData
		var fid: int = int(f.id)
		var orders: Array = ob.get_attacks(fid)

		var groups: Dictionary = {}

		for o in orders:
			attempted += 1
			var a: int = int(o["from"])
			var b: int = int(o["to"])
			var pa: ProvinceData = map_data.provinces[a] as ProvinceData
			var pb: ProvinceData = map_data.provinces[b] as ProvinceData

			if int(pa.owner_id) != fid:
				skipped_owner += 1
				continue
			if int(pb.owner_id) == fid:
				skipped_friendly += 1
				continue

			var order_leader_ids: Array = o.get("leader_ids", [])
			var atk_stats: Dictionary = _get_attack_stats(state, a, order_leader_ids)
			# FIX: allow leader-only attacks and neutral capture
			if int(atk_stats["total_attack"]) <= 0:
				pass

			var src: Dictionary = {
				"from": a,
				"attack_stats": atk_stats,
				"fort_level": int(pa.fort_level),
				"leader_ids": order_leader_ids
			}

			if not groups.has(b):
				groups[b] = { "to": b, "faction": fid, "sources": [] }
			(groups[b]["sources"] as Array).append(src)

		for target_id in groups.keys():
			var group: Dictionary = groups[target_id]
			var b: int = int(group["to"])
			var pb: ProvinceData = map_data.provinces[b] as ProvinceData

			if int(pb.owner_id) == fid:
				skipped_friendly += int((group["sources"] as Array).size())
				continue

			var before_owner: int = int(pb.owner_id)
			var attack_sources: Array = group["sources"] as Array

			if before_owner < 0:
				var neutral_attackers_before: Array = _get_source_leader_ids(state, attack_sources)
				pb.owner_id = fid
				attacker_wins += 1
				applied += 1
				# Move attacking leaders into the captured province
				for lid in neutral_attackers_before:
					state.move_leader_to_province(int(lid), b)
				var neutral_evt: Dictionary = {
					"faction": fid,
					"to": b,
					"sources": attack_sources,
					"prev_owner": before_owner,
					"ap": 0,
					"dp": 0,
					"outcome": "neutral_capture_free",
					"leaders_awarded": neutral_attackers_before,
					"attrition": {},
				}
				captures.append(neutral_evt)
				if log != null:
					log.event("combat_capture", neutral_evt)
				# No XP for free captures — XP only earned in real combat
				continue

			var defenders_before: Array = _get_defending_leader_ids(state, b)
			var attackers_before: Array = _get_source_leader_ids(state, attack_sources)

			# Empty owned province — instant capture, same as neutral
			if defenders_before.is_empty():
				pb.owner_id = fid
				attacker_wins += 1
				applied += 1
				for lid in attackers_before:
					state.move_leader_to_province(int(lid), b)
				var empty_evt: Dictionary = {
					"faction": fid, "to": b, "sources": attack_sources,
					"prev_owner": before_owner, "ap": 0, "dp": 0,
					"outcome": "empty_capture", "leaders_awarded": attackers_before, "attrition": {},
				}
				captures.append(empty_evt)
				if log != null:
					log.event("combat_capture", empty_evt)
				# No XP for empty captures — XP only earned in real combat
				continue

			var def_stats: Dictionary = _get_defense_stats(state, b)
			var attack: Dictionary = _compute_attack(state, rng, attack_sources, def_stats)
			var defense: Dictionary = _compute_defense(state, rng, b, int(pb.defense_value), int(pb.fort_level), bool(pb.is_chokepoint))

			var ap: int = int(attack["total"])
			var dp: int = int(defense["total"])

			if log != null:
				log.event("combat_math", { "faction": fid, "to": b, "attack": attack, "defense": defense, "ap": ap, "dp": dp })

			var setup_dict: Dictionary = {
				"state": state,
				"attacker_faction_id": fid,
				"defender_faction_id": before_owner,
				"source_province_id": int((attack_sources[0] as Dictionary).get("from", -1)) if attack_sources.size() > 0 else -1,
				"target_province_id": b,
				"attacker_leaders": _get_attacking_leaders_for_battle(state, attack_sources),
				"defender_leaders": _get_defending_leaders_for_battle(state, b),
				"attack_direction": "left",
				"biome": str(pb.biome),
				"fort_level": int(pb.fort_level),
				"is_chokepoint": bool(pb.is_chokepoint),
				"has_combat": true,
			}
			if int(group["faction"]) == state.human_faction_id or before_owner == state.human_faction_id:
				# Only intercept if there are actual leaders fighting — skip leaderless captures
				var attacking_leaders: Array = _get_attacking_leaders_for_battle(state, attack_sources)
				var defending_leaders: Array = _get_defending_leaders_for_battle(state, b)
				if attacking_leaders.is_empty() and defending_leaders.is_empty():
					pass  # Fall through to headless fast resolve
				else:
					if log != null:
						log.log("battle_intercept_fired | fid=%d human=%d before_owner=%d" % [fid, state.human_faction_id, before_owner])
					BattleManager.queue_battle(state, group, setup_dict)
					continue

			var attrition: Dictionary = {}
			if ap > dp:
				var awarded_leader_ids: Array = attackers_before.duplicate()
				# Attacker wins: dead-unit items go to the captured province (b)
				_item_destination_province = b
				attrition = _apply_attrition(state, attack_sources, b, true)
				for lid in awarded_leader_ids:
					state.pending_leader_xp_events.append({ "leader_id": int(lid), "amount": 150, "source": "combat_capture" })

				# Award XP to surviving attacker units
				_award_unit_xp(state, attack_sources, 75)
				pb.owner_id = fid
				# Move attacking leaders into the captured province
				var cap_leader_ids: Array = _get_source_leader_ids(state, attack_sources)
				for lid in cap_leader_ids:
					state.move_leader_to_province(int(lid), b)
				attacker_wins += 1
				applied += 1
				var evt: Dictionary = {
					"faction": fid,
					"to": b,
					"sources": attack_sources,
					"prev_owner": before_owner,
					"ap": ap,
					"dp": dp,
					"outcome": "capture",
					"leaders_awarded": awarded_leader_ids,
					"attrition": attrition,
					"attackers_before": attackers_before,
					"defenders_before": defenders_before,
				}
				captures.append(evt)
				if log != null:
					log.event("combat_battle", evt)
			else:
				# Attacker loses: dead-unit items go to attacking source province
				# Use the first source province as the destination
				var _first_src: int = -1
				if (attack_sources as Array).size() > 0:
					_first_src = int(((attack_sources as Array)[0] as Dictionary).get("from", -1))
				_item_destination_province = _first_src
				attrition = _apply_attrition(state, attack_sources, b, false)
				# Award XP to surviving units on both sides
				_award_unit_xp(state, attack_sources, 75)
				_award_defending_unit_xp(state, b, 75)
				defender_holds += 1
				applied += 1
				# Award XP to defenders for repelling an attack
				for def_lid in defenders_before:
					state.pending_leader_xp_events.append({ "leader_id": int(def_lid), "amount": 40, "source": "combat_defense" })
				if log != null:
					log.event("combat_battle", {
						"faction": fid,
						"to": b,
						"sources": attack_sources,
						"prev_owner": before_owner,
						"ap": ap,
						"dp": dp,
						"outcome": "repelled",
						"attrition": attrition,
						"attackers_before": attackers_before,
						"defenders_before": defenders_before,
					})

	if log != null:
		log.event("combat_result", { "attempted": attempted, "applied": applied, "skipped_owner": skipped_owner, "skipped_no_strength": skipped_no_strength, "skipped_friendly": skipped_friendly, "attacker_wins": attacker_wins, "defender_holds": defender_holds, "captures": captures })


# --------------------------------------------------
# Stat collection
# --------------------------------------------------

func _get_attack_stats(state: GameState, province_id: int, leader_ids: Array = []) -> Dictionary:
	var total_attack: int = 0
	var unit_count: int = 0
	var type_tally: Dictionary = { "slash": 0, "pierce": 0, "blunt": 0 }
	var p: ProvinceData = state.map_data.provinces[province_id] as ProvinceData
	var checked: int = 0

	for lid in p.leader_ids:
		if leader_ids.size() > 0 and not leader_ids.has(int(lid)):
			continue
		if checked >= 3:
			break
		var leader: LeaderData = state.get_leader(int(lid))
		if leader == null or bool(leader.on_mission) or str(leader.status) == "wounded" or str(leader.status) == "injured":
			continue
		checked += 1
		for uid in leader.army_unit_ids:
			var unit: UnitData = state.get_unit(int(uid)) as UnitData
			if unit == null or not unit.is_alive():
				continue
			total_attack += int(unit.attack)
			unit_count += 1
			var dt: String = str(unit.damage_type)
			if type_tally.has(dt):
				type_tally[dt] = int(type_tally[dt]) + 1

	var dominant: String = "slash"
	var best: int = -1
	for dt in type_tally.keys():
		if int(type_tally[dt]) > best:
			best = int(type_tally[dt])
			dominant = dt

	return { "total_attack": total_attack, "unit_count": unit_count, "dominant_damage_type": dominant }


func _get_defense_stats(state: GameState, province_id: int) -> Dictionary:
	var total_defense: int = 0
	var unit_count: int = 0
	var type_tally: Dictionary = { "slash": 0, "pierce": 0, "blunt": 0 }
	var p: ProvinceData = state.map_data.provinces[province_id] as ProvinceData

	for lid in p.leader_ids:
		var leader: LeaderData = state.get_leader(int(lid))
		if leader == null or bool(leader.on_mission) or str(leader.status) == "wounded" or str(leader.status) == "injured":
			continue
		for uid in leader.army_unit_ids:
			var unit: UnitData = state.get_unit(int(uid)) as UnitData
			if unit == null or not unit.is_alive():
				continue
			total_defense += int(unit.defense)
			unit_count += 1
			var dt: String = str(unit.damage_type)
			if type_tally.has(dt):
				type_tally[dt] = int(type_tally[dt]) + 1

	var dominant: String = "slash"
	var best: int = -1
	for dt in type_tally.keys():
		if int(type_tally[dt]) > best:
			best = int(type_tally[dt])
			dominant = dt

	return { "total_defense": total_defense, "unit_count": unit_count, "dominant_damage_type": dominant }


# --------------------------------------------------
# Combat math
# --------------------------------------------------

func _compute_attack(state: GameState, rng: RandomNumberGenerator, sources: Array, def_stats: Dictionary) -> Dictionary:
	var total_attack: int = 0
	var fort_bonus: int = 0
	var dominant_type: String = "slash"

	for item in sources:
		var s: Dictionary = item
		var atk: Dictionary = s["attack_stats"]
		total_attack += int(atk["total_attack"])
		var fort_mult: float = _tuning_float(state, "fort_attack_bonus_mult", 1.0)
		fort_bonus += int(round(float(int(s["fort_level"]) * FORT_ATTACK_BONUS_PER_LEVEL) * fort_mult))
		dominant_type = str(atk["dominant_damage_type"])

	var def_type: String = str(def_stats.get("dominant_damage_type", "slash"))
	var type_mult: float = 1.0
	if DAMAGE_ADVANTAGE.has(dominant_type):
		var matchup: Dictionary = DAMAGE_ADVANTAGE[dominant_type]
		if matchup.has(def_type):
			type_mult = float(matchup[def_type])

	var roll: int = rng.randi_range(0, 50)
	var raw: int = total_attack + fort_bonus + roll
	var adjusted: int = int(float(raw) * type_mult)

	return { "total_attack": total_attack, "fort_bonus": fort_bonus, "dominant_type": dominant_type, "type_mult": type_mult, "roll": roll, "total": adjusted }


func _compute_defense(
	state: GameState,
	rng: RandomNumberGenerator,
	province_id: int,
	defense_value: int,
	fort_level: int,
	choke: bool
) -> Dictionary:
	var def_stats: Dictionary = _get_defense_stats(state, province_id)
	var unit_defense: int = int(def_stats["total_defense"])
	var fort_mult: float = _tuning_float(state, "fort_defense_mult", 1.0)
	var choke_mult: float = _tuning_float(state, "chokepoint_defense_mult", 1.0)
	var fort_bonus: int = int(round(float(fort_level * FORT_DEF_MULT) * fort_mult))
	var choke_bonus: int = int(round(float(CHOKE_DEF_BONUS) * choke_mult)) if choke else 0
	var roll: int = rng.randi_range(0, 50)

	return { "unit_defense": unit_defense, "defense_value": defense_value, "fort_bonus": fort_bonus, "choke": choke, "choke_bonus": choke_bonus, "roll": roll, "total": unit_defense + defense_value + fort_bonus + choke_bonus + roll }


# --------------------------------------------------
# Unit XP helpers
# --------------------------------------------------

func _award_unit_xp(state: GameState, attack_sources: Array, amount: int) -> void:
	for src in attack_sources:
		var lids: Array = src.get("leader_ids", [])
		for lid in lids:
			var leader: LeaderData = state.get_leader(int(lid))
			if leader == null:
				continue
			for uid in leader.army_unit_ids:
				var unit: UnitData = state.get_unit(int(uid)) as UnitData
				if unit != null and unit.is_alive():
					unit.add_xp(amount)


func _award_defending_unit_xp(state: GameState, province_id: int, amount: int) -> void:
	if province_id < 0 or province_id >= state.map_data.provinces.size():
		return
	var p: ProvinceData = state.map_data.provinces[province_id] as ProvinceData
	for lid in p.leader_ids:
		var leader: LeaderData = state.get_leader(int(lid))
		if leader == null or bool(leader.on_mission):
			continue
		for uid in leader.army_unit_ids:
			var unit: UnitData = state.get_unit(int(uid)) as UnitData
			if unit != null and unit.is_alive():
				unit.add_xp(amount)


# --------------------------------------------------
# Attrition / wounds
# --------------------------------------------------

func _apply_attrition(state: GameState, attack_sources: Array, target_province_id: int, attacker_won: bool) -> Dictionary:
	var rng: RandomNumberGenerator = state.rng
	var tuning = _combat_tuning(state)
	var attacker_leaders: Dictionary = _get_attacking_leader_sources(state, attack_sources)
	var defender_leader_ids: Array = _get_defending_leader_ids(state, target_province_id)

	var result: Dictionary = {
		"attacker": _apply_side_attrition(state, rng, attacker_leaders, true, attacker_won, target_province_id, tuning),
		"defender": _apply_side_attrition(state, rng, defender_leader_ids, false, not attacker_won, target_province_id, tuning),
	}
	_process_captured_units(state)
	return result


func _apply_side_attrition(state: GameState, rng: RandomNumberGenerator, side_data, is_attacker: bool, side_won: bool, province_id: int, tuning) -> Dictionary:
	var min_loss: float = 0.0
	var max_loss: float = 0.0
	var wound_chance: float = 0.0
	if tuning != null:
		if is_attacker and side_won:
			min_loss = float(tuning.attack_win_loss_min)
			max_loss = float(tuning.attack_win_loss_max)
			wound_chance = float(tuning.attack_win_wound_chance)
		elif is_attacker and not side_won:
			min_loss = float(tuning.attack_loss_loss_min)
			max_loss = float(tuning.attack_loss_loss_max)
			wound_chance = float(tuning.attack_loss_wound_chance)
		elif not is_attacker and side_won:
			min_loss = float(tuning.defense_win_loss_min)
			max_loss = float(tuning.defense_win_loss_max)
			wound_chance = float(tuning.defense_win_wound_chance)
		else:
			min_loss = float(tuning.defense_loss_loss_min)
			max_loss = float(tuning.defense_loss_loss_max)
			wound_chance = float(tuning.defense_loss_wound_chance)

	var leaders_processed: Array = []
	var units_damaged: int = 0
	var units_killed: int = 0
	var total_hp_damage: int = 0
	var wounded_leaders: Array = []

	if is_attacker:
		for lid in side_data.keys():
			var leader: LeaderData = state.get_leader(int(lid))
			if leader == null:
				continue
			var source_province_id: int = int(side_data[lid])
			var hp_info: Dictionary = _apply_damage_to_leader_army(state, rng, leader, min_loss, max_loss, tuning)
			leaders_processed.append(int(lid))
			units_damaged += int(hp_info.get("units_damaged", 0))
			units_killed += int(hp_info.get("units_killed", 0))
			total_hp_damage += int(hp_info.get("hp_damage", 0))
			if _roll_leader_wound(rng, leader, wound_chance):
				_wound_attacking_leader(state, leader, source_province_id, tuning)
				wounded_leaders.append(int(lid))
	else:
		for lid_val in side_data:
			var leader2: LeaderData = state.get_leader(int(lid_val))
			if leader2 == null:
				continue
			var hp_info2: Dictionary = _apply_damage_to_leader_army(state, rng, leader2, min_loss, max_loss, tuning)
			leaders_processed.append(int(lid_val))
			units_damaged += int(hp_info2.get("units_damaged", 0))
			units_killed += int(hp_info2.get("units_killed", 0))
			total_hp_damage += int(hp_info2.get("hp_damage", 0))
			if _roll_leader_wound(rng, leader2, wound_chance):
				if side_won:
					_wound_defending_leader_hold(state, leader2, province_id, tuning)
				else:
					_wound_defending_leader_fallback(state, leader2, province_id, tuning)
				wounded_leaders.append(int(lid_val))

	return {
		"leaders": leaders_processed,
		"units_damaged": units_damaged,
		"units_killed": units_killed,
		"hp_damage": total_hp_damage,
		"wounded_leaders": wounded_leaders,
	}


func _apply_damage_to_leader_army(state: GameState, rng: RandomNumberGenerator, leader: LeaderData, min_loss: float, max_loss: float, tuning) -> Dictionary:
	var units_damaged: int = 0
	var units_killed: int = 0
	var hp_damage: int = 0
	var snapshot: Array = leader.army_unit_ids.duplicate()
	for uid_val in snapshot:
		var unit: UnitData = state.get_unit(int(uid_val)) as UnitData
		if unit == null or not unit.is_alive():
			continue
		var loss_ratio: float = rng.randf_range(min_loss, max_loss)
		var damage: int = int(round(float(unit.max_hp) * loss_ratio))
		if tuning != null:
			damage = maxi(damage, int(tuning.minimum_damage_per_engaged_unit))
		unit.take_damage(damage)
		units_damaged += 1
		hp_damage += damage
		if not unit.is_alive():
			units_killed += 1
			leader.remove_army_unit(int(uid_val))
			unit.owner_leader_id = -1
			unit.province_id = int(leader.current_province_id)
			# Item transfer: move equipped item to destination province before nulling unit.
			# destination_province_id must be set by caller before _apply_damage_to_leader_army.
			if str(unit.equipped_item_id) != "" and _item_destination_province >= 0:
				state.transfer_item_from_dead_unit(int(uid_val), _item_destination_province)
				# Sigil drop: equipped sigil drops when unit is killed
				var _usid: String = str(unit.equipped_sigil_id) if unit.get("equipped_sigil_id") != null else ""
				if _usid != "" and _item_destination_province >= 0:
					var _sdp: ProvinceData = state.map_data.provinces[_item_destination_province] if _item_destination_province < state.map_data.provinces.size() else null
					if _sdp != null and _sdp.has_method("add_sigil"):
						_sdp.add_sigil(_usid)
						DebugLogger.log("event:battle_sigil_drop", {"sigil_id": _usid, "from": "unit", "province": _item_destination_province})
					if unit.get("equipped_sigil_id") != null:
						unit.equipped_sigil_id = ""
			if int(uid_val) >= 0 and int(uid_val) < state.units.size():
				state.units[int(uid_val)] = null
	return {
		"units_damaged": units_damaged,
		"units_killed": units_killed,
		"hp_damage": hp_damage,
	}


func _roll_leader_wound(rng: RandomNumberGenerator, leader: LeaderData, wound_chance: float) -> bool:
	if leader == null:
		return false
	if str(leader.status) == "wounded" or str(leader.status) == "injured":
		return false
	if rng.randf() >= wound_chance:
		return false
	return true


func _wound_attacking_leader(state: GameState, leader: LeaderData, source_province_id: int, tuning) -> void:
	# Drop equipped item to the province being attacked (winner keeps it)
	if str(leader.equipped_item_id) != "" and _item_destination_province >= 0:
		state.award_item_to_province(_item_destination_province, str(leader.equipped_item_id))
		DebugLogger.log("event:battle_item_drop", {
			"item_id": str(leader.equipped_item_id), "from": "leader", "leader_id": int(leader.id),
			"province": _item_destination_province
		})
		leader.equipped_item_id = ""
	# Sigil drop: attacking leader loses sigil when wounded
	var _lsid_atk: String = str(leader.equipped_sigil_id) if leader.get("equipped_sigil_id") != null else ""
	if _lsid_atk != "" and _item_destination_province >= 0:
		var _sdp2: ProvinceData = state.map_data.provinces[_item_destination_province] if _item_destination_province < state.map_data.provinces.size() else null
		if _sdp2 != null and _sdp2.has_method("add_sigil"):
			_sdp2.add_sigil(_lsid_atk)
			DebugLogger.log("event:battle_sigil_drop", {"sigil_id": _lsid_atk, "from": "atk_leader", "province": _item_destination_province})
		if leader.get("equipped_sigil_id") != null:
			leader.equipped_sigil_id = ""
	leader.status = "wounded"
	leader.on_mission = false
	leader.wounded_turns_remaining = int(tuning.wound_turns) if tuning != null else 4
	leader.wounded_from_province_id = source_province_id
	state.move_leader_to_province(int(leader.id), source_province_id)


func _wound_defending_leader_hold(state: GameState, leader: LeaderData, province_id: int, tuning) -> void:
	leader.status = "wounded"
	leader.on_mission = false
	leader.wounded_turns_remaining = int(tuning.wound_turns) if tuning != null else 4
	leader.wounded_from_province_id = province_id
	state.move_leader_to_province(int(leader.id), province_id)


func _wound_defending_leader_fallback(state: GameState, leader: LeaderData, lost_province_id: int, tuning) -> void:
	# Drop equipped item to the lost province (attacker wins it)
	if str(leader.equipped_item_id) != "" and lost_province_id >= 0:
		state.award_item_to_province(lost_province_id, str(leader.equipped_item_id))
		DebugLogger.log("event:battle_item_drop", {
			"item_id": str(leader.equipped_item_id), "from": "leader", "leader_id": int(leader.id),
			"province": lost_province_id
		})
		leader.equipped_item_id = ""
	# Sigil drop: defending leader loses sigil when province is lost
	var _lsid_def: String = str(leader.equipped_sigil_id) if leader.get("equipped_sigil_id") != null else ""
	if _lsid_def != "" and lost_province_id >= 0:
		var _sdp3: ProvinceData = state.map_data.provinces[lost_province_id] if lost_province_id < state.map_data.provinces.size() else null
		if _sdp3 != null and _sdp3.has_method("add_sigil"):
			_sdp3.add_sigil(_lsid_def)
			DebugLogger.log("event:battle_sigil_drop", {"sigil_id": _lsid_def, "from": "def_leader", "province": lost_province_id})
		if leader.get("equipped_sigil_id") != null:
			leader.equipped_sigil_id = ""
	leader.status = "wounded"
	leader.on_mission = false
	leader.wounded_turns_remaining = int(tuning.wound_turns) if tuning != null else 4
	leader.wounded_from_province_id = lost_province_id
	var fallback_id: int = _find_closest_owned_province(state, int(leader.faction_id), lost_province_id)
	if fallback_id >= 0:
		state.move_leader_to_province(int(leader.id), fallback_id)
	else:
		state.move_leader_to_province(int(leader.id), lost_province_id)


func _find_closest_owned_province(state: GameState, faction_id: int, start_province_id: int) -> int:
	if state == null or state.map_data == null or faction_id < 0:
		return -1
	if start_province_id < 0 or start_province_id >= state.map_data.provinces.size():
		return -1
	var adjacency: Dictionary = state.map_data.adjacency
	var queue: Array = [start_province_id]
	var visited: Dictionary = {start_province_id: true}
	while not queue.is_empty():
		var pid: int = int(queue.pop_front())
		if pid != start_province_id:
			var p: ProvinceData = state.map_data.provinces[pid] as ProvinceData
			if p != null and int(p.owner_id) == faction_id:
				return pid
		for next_id_val in adjacency.get(pid, []):
			var next_id: int = int(next_id_val)
			if visited.has(next_id):
				continue
			visited[next_id] = true
			queue.append(next_id)
	return -1


# --------------------------------------------------
# Leader sourcing helpers
# --------------------------------------------------

func _get_defending_leader_ids(state: GameState, province_id: int) -> Array:
	var out: Array = []
	if province_id < 0 or province_id >= state.map_data.provinces.size():
		return out
	var p: ProvinceData = state.map_data.provinces[province_id] as ProvinceData
	for lid_val in p.leader_ids:
		var leader: LeaderData = state.get_leader(int(lid_val))
		if leader == null or bool(leader.on_mission) or str(leader.status) == "wounded" or str(leader.status) == "injured":
			continue
		if not out.has(int(lid_val)):
			out.append(int(lid_val))
	return out


func _get_attacking_leader_sources(state: GameState, sources: Array) -> Dictionary:
	var out: Dictionary = {}
	for item in sources:
		var src: Dictionary = item
		var province_id: int = int(src.get("from", -1))
		var leader_ids: Array = src.get("leader_ids", [])
		if province_id < 0 or province_id >= state.map_data.provinces.size():
			continue
		var p: ProvinceData = state.map_data.provinces[province_id] as ProvinceData
		var candidates: Array = leader_ids if leader_ids.size() > 0 else p.leader_ids
		for lid in candidates:
			var leader: LeaderData = state.get_leader(int(lid))
			if leader == null or bool(leader.on_mission) or str(leader.status) == "wounded" or str(leader.status) == "injured":
				continue
			out[int(lid)] = province_id
	return out


func _get_source_leader_ids(state: GameState, sources: Array) -> Array:
	var out: Array = []
	for lid in _get_attacking_leader_sources(state, sources).keys():
		out.append(int(lid))
	return out


func _get_attacking_leaders_for_battle(state: GameState, sources: Array) -> Array:
	var out: Array = []
	var leader_sources: Dictionary = _get_attacking_leader_sources(state, sources)
	for lid in leader_sources.keys():
		var leader: LeaderData = state.get_leader(int(lid))
		if leader != null:
			out.append(leader)
	return out


func _get_defending_leaders_for_battle(state: GameState, province_id: int) -> Array:
	var out: Array = []
	for lid in _get_defending_leader_ids(state, province_id):
		var leader: LeaderData = state.get_leader(int(lid))
		if leader != null:
			out.append(leader)
	return out


func _move_attacking_leaders_to_captured_province(state: GameState, attack_sources: Array, target_province_id: int) -> void:
	var moved_leaders: Dictionary = {}
	for src_entry in attack_sources:
		var from_pid: int = int((src_entry as Dictionary).get("from", -1))
		var source_leader_ids: Array = (src_entry as Dictionary).get("leader_ids", [])
		for lid_val in source_leader_ids:
			var lid: int = int(lid_val)
			if moved_leaders.has(lid):
				continue
			var leader: LeaderData = state.get_leader(lid)
			if leader == null:
				continue
			if from_pid >= 0 and from_pid < state.map_data.provinces.size():
				var p_from: ProvinceData = state.map_data.provinces[from_pid] as ProvinceData
				if p_from != null:
					p_from.leader_ids.erase(lid)
			if target_province_id >= 0 and target_province_id < state.map_data.provinces.size():
				var p_to: ProvinceData = state.map_data.provinces[target_province_id] as ProvinceData
				if p_to != null and not p_to.leader_ids.has(lid):
					p_to.leader_ids.append(lid)
			leader.current_province_id = target_province_id
			leader.province_id = target_province_id
			moved_leaders[lid] = true


func _process_captured_units(state):
	if state == null:
		return
	if not ("captured_units" in state):
		return
	if not ("map_data" in state):
		return
	if state.map_data == null:
		return
	if not ("provinces" in state.map_data):
		return

	for unit in state.captured_units:
		if unit == null:
			continue
		if not ("captured_by" in unit):
			continue

		var captor = unit.captured_by
		var nearest = null
		var best_dist := INF

		for province in state.map_data.provinces:
			if province == null:
				continue
			if not ("owner" in province):
				continue
			if province.owner != captor:
				continue
			if not ("position" in province):
				continue
			if not ("position" in unit):
				continue

			var dist = province.position.distance_to(unit.position)
			if dist < best_dist:
				best_dist = dist
				nearest = province

		if nearest != null:
			if "owner" in unit:
				unit.owner = captor
			if "province_id" in unit and "id" in nearest:
				unit.province_id = nearest.id
