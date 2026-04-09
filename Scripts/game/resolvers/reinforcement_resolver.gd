# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: ReinforcementResolver
#
# Role:
# Handles strategic recovery after combat in the post-economy step.
# With garrisons removed, "reinforcement" now means:
# - resolving paid province healing orders
# - ticking wounded leader recovery timers
# - healing damaged units while stationed in provinces
# - reducing or denying healing when a province is under border pressure
# ==================================================

class_name ReinforcementResolver
extends RefCounted


func resolve(state: GameState) -> void:
	var log = state.logger
	var tuning = null
	if state != null and state.has_method("get_combat_tuning_profile"):
		tuning = state.get_combat_tuning_profile()
		if tuning != null and tuning.has_method("sanitize"):
			tuning.sanitize()

	var healed_units: Array = []
	var active_heals: Array = []
	var recovered_leaders: Array = []
	var ticking_wounded: Array = []

	_resolve_paid_heals(state, tuning, active_heals, healed_units)

	# 1) Tick wounded leaders.
	for item in state.leaders:
		var leader: LeaderData = item as LeaderData
		if leader == null:
			continue
		if str(leader.status) != "wounded":
			continue
		leader.wounded_turns_remaining = maxi(0, int(leader.wounded_turns_remaining) - 1)
		ticking_wounded.append({
			"leader_id": int(leader.id),
			"remaining": int(leader.wounded_turns_remaining),
			"province_id": int(leader.current_province_id),
		})
		if int(leader.wounded_turns_remaining) <= 0:
			leader.status = "idle"
			leader.wounded_from_province_id = -1
			recovered_leaders.append(int(leader.id))

	# 2) Heal units in province inventories and leader armies.
	for item2 in state.map_data.provinces:
		var province: ProvinceData = item2 as ProvinceData
		if province == null:
			continue
		var pressure_ratio: float = float(tuning.safe_recovery_ratio)
		if pressure_ratio <= 0.0:
			continue

		var seen_units: Dictionary = {}
		for uid_val in province.unit_inventory:
			_heal_unit_if_needed(state, int(uid_val), int(province.id), pressure_ratio, healed_units, seen_units)
		for lid_val in province.leader_ids:
			var leader2: LeaderData = state.get_leader(int(lid_val))
			if leader2 == null:
				continue
			for uid_val2 in leader2.army_unit_ids:
				_heal_unit_if_needed(state, int(uid_val2), int(province.id), pressure_ratio, healed_units, seen_units)

	if log != null:
		log.event("reinforcement_result", {
			"status": "ok",
			"active_heals": active_heals,
			"recovered_leaders": recovered_leaders,
			"wounded_timers": ticking_wounded,
			"healed_units": healed_units,
		})


func _resolve_paid_heals(state: GameState, tuning, active_heals: Array, healed_units: Array) -> void:
	if state == null or state.order_book == null or state.map_data == null:
		return
	var flat_cost: int = int(tuning.active_heal_flat_cost) if tuning != null else 20
	var missing_hp_cost: int = int(tuning.active_heal_missing_hp_cost) if tuning != null else 4
	for item in state.map_data.factions:
		var faction: FactionData = item as FactionData
		if faction == null:
			continue
		var fid: int = int(faction.id)
		for heal_value in state.order_book.get_heals(fid):
			var heal: Dictionary = heal_value as Dictionary
			var unit_id: int = int(heal.get("unit_id", -1))
			var province_id: int = int(heal.get("province_id", -1))
			var unit: UnitData = state.get_unit(unit_id) as UnitData
			if unit == null or not unit.is_alive():
				active_heals.append({"unit_id": unit_id, "province_id": province_id, "status": "invalid_unit"})
				continue
			if province_id < 0 or province_id >= state.map_data.provinces.size():
				active_heals.append({"unit_id": unit_id, "province_id": province_id, "status": "invalid_province"})
				continue
			var province: ProvinceData = state.map_data.provinces[province_id] as ProvinceData
			if province == null or int(province.owner_id) != fid:
				active_heals.append({"unit_id": unit_id, "province_id": province_id, "status": "not_owner"})
				continue
			if int(unit.province_id) != province_id:
				active_heals.append({"unit_id": unit_id, "province_id": province_id, "status": "wrong_location"})
				continue
			if int(unit.hp) >= int(unit.max_hp):
				active_heals.append({"unit_id": unit_id, "province_id": province_id, "status": "already_full"})
				continue
			var missing_hp: int = maxi(0, int(unit.max_hp) - int(unit.hp))
			var cost: int = int(heal.get("cost", flat_cost + missing_hp * missing_hp_cost))
			if cost <= 0:
				cost = flat_cost + missing_hp * missing_hp_cost
			if int(faction.gold) < cost:
				active_heals.append({"unit_id": unit_id, "province_id": province_id, "status": "insufficient_gold", "cost": cost, "gold": int(faction.gold)})
				continue
			var before_hp: int = int(unit.hp)
			faction.gold -= cost
			unit.heal_full()
			active_heals.append({"unit_id": unit_id, "province_id": province_id, "status": "healed", "cost": cost, "before_hp": before_hp, "after_hp": int(unit.hp)})
			healed_units.append({"unit_id": unit_id, "province_id": province_id, "before_hp": before_hp, "after_hp": int(unit.hp), "paid": true})




func _heal_unit_if_needed(state: GameState, unit_id: int, province_id: int, heal_ratio: float, healed_units: Array, seen_units: Dictionary) -> void:
	if seen_units.has(unit_id):
		return
	seen_units[unit_id] = true
	var unit: UnitData = state.get_unit(unit_id) as UnitData
	if unit == null:
		return
	if not unit.is_alive():
		return
	if int(unit.hp) >= int(unit.max_hp):
		return
	var heal_amount: int = maxi(1, int(round(float(unit.max_hp) * heal_ratio)))
	var before_hp: int = int(unit.hp)
	unit.hp = mini(int(unit.max_hp), int(unit.hp) + heal_amount)
	unit.province_id = province_id
	if int(unit.hp) != before_hp:
		healed_units.append({
			"unit_id": unit_id,
			"province_id": province_id,
			"before_hp": before_hp,
			"after_hp": int(unit.hp),
			"paid": false,
		})
