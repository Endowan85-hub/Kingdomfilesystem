# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: BattleManager
#
# Role:
# Coordinates queued tactical battles and resolves them in a controlled path.
#
# Allowed Interactions:
# - BattleState
# - BattleAI
# - BattleResolver
# - TurnManager (via battles_resolved signal)
# - MapDebugView (launches battle scene)
#
# Forbidden Responsibilities:
# - Must not modify GameState during battle
# - Must not own campaign simulation state
#
# Game Phase:
# Execution Phase (Combat Intercept)
# ==================================================

class_name BattleManager
extends RefCounted

const BattleStateScript = preload("res://Scripts/game/battle/battle_state.gd")
const BattleAIScript = preload("res://Scripts/game/battle/battle_ai.gd")
const BattleResolverScript = preload("res://Scripts/game/battle/battle_resolver.gd")
const BattleScenePacked = preload("res://Scenes/battle/battle_scene.tscn")
const DebugLogger = preload("res://Scripts/debug/debug_logger.gd")
const MissionResolverScript = preload("res://Scripts/game/resolvers/mission_resolver.gd")

static var _queue: Array = []
static var _mission_queue: Array = []   # separate queue for mission battles
static var _emitter: _BattleEmitter = null
static var _mission_resolver = null     # lazy-init MissionResolver instance

class _BattleEmitter extends Node:
	signal battles_resolved

	func _continue_queue() -> void:
		BattleManager.process_queue()


static func _get_emitter() -> _BattleEmitter:
	if _emitter == null or not is_instance_valid(_emitter):
		_emitter = _BattleEmitter.new()
		_emitter.set_name("BattleManagerEmitter")
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			tree.root.add_child(_emitter)
	return _emitter


static func queue_battle(state, group: Dictionary, setup: Dictionary) -> void:
	if state != null:
		setup["human_faction_id"] = int(state.human_faction_id)

	DebugLogger.log("event:battle_queued", {
		"attacker_faction": int(setup.get("attacker_faction_id", -1)),
		"defender_faction": int(setup.get("defender_faction_id", -1)),
		"target_province": int(setup.get("target_province_id", -1)),
		"human_faction": int(state.human_faction_id) if state != null else -1,
		"has_combat": bool(setup.get("has_combat", true))
	})

	_queue.append({
		"state": state,
		"group": group,
		"setup": setup,
	})


# Queue a mission battle. Called by mission_resolver when travel is complete.
# setup_dict contains: attacker_leader (LeaderData), enemy_leader (Dict),
# enemy_units (Array[Dict]), mission_instance_id, human_faction_id.
static func queue_mission_battle(state, mission_instance_id: String) -> void:
	if state == null or not state.active_missions.has(mission_instance_id):
		return
	var mission = state.active_missions[mission_instance_id]
	if mission == null:
		return

	DebugLogger.log("event:mission_battle_queued", {
		"instance_id":  mission_instance_id,
		"display_name": mission.display_name,
		"leader_id":    mission.assigned_leader_id,
		"province_id":  mission.province_id,
	})

	_mission_queue.append({
		"state":               state,
		"mission_instance_id": mission_instance_id,
	})


static func has_pending_battles() -> bool:
	return not _queue.is_empty() or not _mission_queue.is_empty()


static func process_queue() -> void:
	if _queue.is_empty() and _mission_queue.is_empty():
		_get_emitter().emit_signal("battles_resolved")
		return

	# Process all campaign battles first
	while not _queue.is_empty():
		var entry: Dictionary = _queue.pop_front()
		var state = entry.get("state")
		var setup: Dictionary = entry.get("setup", {})

		var is_player: bool = false
		if state != null:
			is_player = int(setup.get("attacker_faction_id", -1)) == int(state.human_faction_id) \
				or int(setup.get("defender_faction_id", -1)) == int(state.human_faction_id)

		DebugLogger.log("event:battle_process_queue", {
			"is_player": is_player,
			"attacker_faction": int(setup.get("attacker_faction_id", -1)),
			"defender_faction": int(setup.get("defender_faction_id", -1)),
			"human_faction": int(state.human_faction_id) if state != null else -1,
			"has_combat": bool(setup.get("has_combat", true))
		})

		if is_player and bool(setup.get("has_combat", true)):
			# Re-evaluate live leader status — prior battles in this turn may have wounded leaders
			var atk_leaders: Array = []
			for leader in setup.get("attacker_leaders", []):
				if leader == null:
					continue
				var live = state.get_leader(int(leader.id)) if state != null else null
				if live != null and str(live.status) != "wounded":
					atk_leaders.append(leader)

			var def_leaders: Array = []
			for leader in setup.get("defender_leaders", []):
				if leader == null:
					continue
				var live = state.get_leader(int(leader.id)) if state != null else null
				if live != null and str(live.status) != "wounded":
					def_leaders.append(leader)

			# If all defenders are wounded, treat as empty province — instant capture, no battle
			if def_leaders.is_empty() and not atk_leaders.is_empty():
				var target_id: int = int(setup.get("target_province_id", -1))
				var attacker_fid: int = int(setup.get("attacker_faction_id", -1))
				if state != null and target_id >= 0:
					state.map_data.provinces[target_id].owner_id = attacker_fid
					for leader in atk_leaders:
						state.move_leader_to_province(int(leader.id), target_id)
					# Push wounded defenders to nearest friendly province
					for leader in setup.get("defender_leaders", []):
						if leader == null:
							continue
						var live = state.get_leader(int(leader.id)) if state != null else null
						if live != null and str(live.status) == "wounded":
							var fallback: int = _find_closest_owned_province(state, int(live.faction_id), target_id)
							if fallback >= 0:
								state.move_leader_to_province(int(live.id), fallback)
					DebugLogger.log("event:battle_skipped_wounded_defenders", {
						"target_province": target_id, "attacker_faction": attacker_fid
					})
				continue

			# If attackers are all wounded, skip this battle entirely
			if atk_leaders.is_empty():
				DebugLogger.log("event:battle_skipped_wounded_attackers", {
					"target_province": int(setup.get("target_province_id", -1))
				})
				continue

			# Skip if both sides have no leaders at all
			if atk_leaders.is_empty() and def_leaders.is_empty():
				var headless_result: Dictionary = _run_headless(setup)
				_writeback(state, setup, headless_result)
				continue
			var tree := Engine.get_main_loop() as SceneTree
			if tree == null:
				push_error("BattleManager: no scene tree")
			elif BattleScenePacked == null:
				push_error("BattleManager: BattleScenePacked failed to load")
			else:
				DebugLogger.log("event:battle_scene_launch", {
					"attacker_faction": int(setup.get("attacker_faction_id", -1)),
					"defender_faction": int(setup.get("defender_faction_id", -1)),
					"target_province": int(setup.get("target_province_id", -1))
				})

				# Find CampaignMap and hide all its UI layers
				var map_node = null
				for _child in tree.root.get_children():
					if _child.has_method("set_campaign_visible"):
						map_node = _child
						break
				if map_node != null:
					map_node.set_campaign_visible(false)

				var scene = BattleScenePacked.instantiate()
				scene.battle_finished.connect(func(result: Dictionary):
					var merged_result: Dictionary = _build_scene_result(scene, setup, result)
					DebugLogger.log("event:battle_scene_finished", merged_result)

					if map_node != null:
						map_node.set_campaign_visible(true)

					_writeback(state, setup, merged_result)

					# Use call_deferred to avoid re-entering the while loop (causes double launch)
					if not _queue.is_empty():
						_get_emitter().call_deferred("_continue_queue")
					else:
						_get_emitter().emit_signal("battles_resolved")
				)

				tree.root.add_child(scene)
				if scene.has_method("setup_battle"):
					scene.setup_battle(setup)
				# Inject Phase 3 visual overlay
				var _vl_script = load("res://Visual/battle/BattleVisualLayer.gd")
				if _vl_script != null:
					var _vl = _vl_script.new()
					scene.add_child(_vl)
					_vl.init_layer(scene, setup)
				return

		var result: Dictionary = _run_headless(setup)
		DebugLogger.log("event:battle_headless_finished", result)
		_writeback(state, setup, result)

	# Process mission battles after all campaign battles
	while not _mission_queue.is_empty():
		var entry: Dictionary = _mission_queue.pop_front()
		var state = entry.get("state")
		var mission_instance_id: String = str(entry.get("mission_instance_id", ""))
		_process_mission_battle(state, mission_instance_id)

	_get_emitter().emit_signal("battles_resolved")


static func _process_mission_battle(state, mission_instance_id: String) -> void:
	if state == null or mission_instance_id == "":
		return
	if not state.active_missions.has(mission_instance_id):
		return

	var mission = state.active_missions[mission_instance_id]
	if mission == null:
		return

	var leader_id: int = int(mission.assigned_leader_id)
	var attacker_leader = state.get_leader(leader_id)
	if attacker_leader == null:
		# Leader is gone — fail the mission silently
		_get_mission_resolver().apply_mission_result(state, mission, false)
		return

	var bt: Dictionary = mission.battle_template as Dictionary
	var is_player_mission: bool = int(state.human_faction_id) >= 0 \
		and int(attacker_leader.faction_id) == int(state.human_faction_id)

	# Build setup_dict using the same structure as campaign battles
	# Enemy side uses mock leader/unit dicts (same as battle lab)
	var setup: Dictionary = {
		"human_faction_id":    int(state.human_faction_id),
		"attacker_faction_id": int(attacker_leader.faction_id),
		"defender_faction_id": -1,       # no real faction — mission enemy
		"target_province_id":  int(mission.province_id),
		"source_province_id":  int(mission.province_id),
		"fort_level":          0,         # missions have no fort
		"has_combat":          true,
		"is_mission_battle":   true,
		"mission_instance_id": mission_instance_id,
		"state":               state,
		# Attacker: real leader + their army units
		"attacker_leaders":    [attacker_leader],
		# Defender: mock dict leader + mock unit dicts from battle_template
		# If no enemy leader, use a minimal placeholder so defender_units_override still gets built
		"defender_leaders":    [bt.get("enemy_leader", {})] if not (bt.get("enemy_leader", {}) as Dictionary).is_empty() else [{"name": "Enemy", "attack": 10, "defense": 8, "hp": 1, "damage_type": "slash", "speed": 1, "accuracy": 50, "evasion": 0, "leadership": 0, "level": 1, "_no_leader_unit": true}],
		"defender_units_override": bt.get("enemy_units", []),
	}

	DebugLogger.log("event:mission_battle_start", {
		"instance_id":  mission_instance_id,
		"display_name": mission.display_name,
		"leader_id":    leader_id,
		"is_player":    is_player_mission,
	})

	if is_player_mission:
		# Launch tactical battle scene for player
		var tree := Engine.get_main_loop() as SceneTree
		if tree == null or BattleScenePacked == null:
			# Fallback: headless
			var headless: Dictionary = _run_headless(setup)
			_apply_mission_battle_result(state, mission, headless)
			return

		# Find CampaignMap and hide all its UI layers
		var map_node = null
		for _child in tree.root.get_children():
			if _child.has_method("set_campaign_visible"):
				map_node = _child
				break
		if map_node != null:
			map_node.set_campaign_visible(false)

		var scene = BattleScenePacked.instantiate()
		scene.battle_finished.connect(func(result: Dictionary):
			var merged: Dictionary = _build_scene_result(scene, setup, result)
			DebugLogger.log("event:mission_battle_scene_finished", merged)

			if map_node != null:
				map_node.set_campaign_visible(true)

			_apply_mission_battle_result(state, mission, merged)

			if not _mission_queue.is_empty():
				_get_emitter().call_deferred("_continue_queue")
			else:
				_get_emitter().emit_signal("battles_resolved")
		)
		tree.root.add_child(scene)
		if scene.has_method("setup_battle"):
			scene.setup_battle(setup)
	else:
		# AI mission — run headless
		var result: Dictionary = _run_headless(setup)
		_apply_mission_battle_result(state, mission, result)


static func _apply_mission_battle_result(state, mission, result: Dictionary) -> void:
	var attacker_won: bool = bool(result.get("attacker_won", false))
	_get_mission_resolver().apply_mission_result(state, mission, attacker_won, result)


static func _get_mission_resolver():
	if _mission_resolver == null:
		_mission_resolver = MissionResolverScript.new()
	return _mission_resolver


static func _run_headless(setup: Dictionary) -> Dictionary:
	var bs = BattleStateScript.new(setup)

	const MAX_ROUNDS: int = 100  # safety cap — real battles end in 1-3 rounds
	while bs.phase != "battle_end" and bs.round <= MAX_ROUNDS:
		for u in bs.turn_order:
			if u != null and bool(u.is_alive):
				BattleAIScript.take_turn(bs, u)
		BattleResolverScript.check_win(bs)
		bs.round += 1
	if bs.phase != "battle_end":
		# Force-end stalled battle — defender win (attacker failed to break through)
		bs.phase = "battle_end"
		DebugLogger.log("event:battle_stalemate", {
			"rounds": bs.round,
			"context": str(setup.get("mission_instance_id", "campaign"))
		})

	var atk_alive: bool = false
	var def_alive: bool = false

	for u in bs.attacker_units:
		if u != null and bool(u.is_alive):
			atk_alive = true
			break

	for u in bs.defender_units:
		if u != null and bool(u.is_alive):
			def_alive = true
			break

	var result := {
		"attacker_won": atk_alive and not def_alive,
		"defender_won": def_alive and not atk_alive,
		"rounds_taken": int(bs.round),
		"dead_attacker_unit_ids": [],
		"dead_defender_unit_ids": [],
		"captured_attacker_unit_ids": [],
		"captured_defender_unit_ids": [],
		"wounded_leader_ids": [],
		"alive_attacker_leader_ids": [],
		"alive_defender_leader_ids": [],
		"dead_attacker_leader_ids": [],
		"dead_defender_leader_ids": [],
	}

	_collect_battle_state(bs, result)
	return result


static func _build_scene_result(scene, setup: Dictionary, base_result: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"attacker_won": bool(base_result.get("attacker_won", false)),
		"defender_won": bool(base_result.get("defender_won", false)),
		"rounds_taken": int(base_result.get("rounds_taken", 0)),
		"dead_attacker_unit_ids": base_result.get("dead_attacker_unit_ids", []),
		"dead_defender_unit_ids": base_result.get("dead_defender_unit_ids", []),
		"captured_attacker_unit_ids": base_result.get("captured_attacker_unit_ids", []),
		"captured_defender_unit_ids": base_result.get("captured_defender_unit_ids", []),
		"wounded_leader_ids": [],
		"alive_attacker_leader_ids": [],
		"alive_defender_leader_ids": [],
		"dead_attacker_leader_ids": [],
		"dead_defender_leader_ids": [],
		"item_transfers": base_result.get("item_transfers", []),
	}

	if scene == null or scene.state == null:
		return result

	_collect_battle_state(scene.state, result)
	return result


static func _collect_battle_state(bs, result: Dictionary) -> void:
	for unit in bs.attacker_units:
		_collect_unit_result(unit, "attacker", result)

	for unit in bs.defender_units:
		_collect_unit_result(unit, "defender", result)


static func _collect_unit_result(unit, side_name: String, result: Dictionary) -> void:
	if unit == null:
		return

	if bool(unit.is_leader_combatant):
		var leader_id: int = -1
		if unit.leader_ref != null and "id" in unit.leader_ref:
			leader_id = int(unit.leader_ref.id)
		if leader_id < 0:
			return

		if bool(unit.is_alive):
			if side_name == "attacker":
				result["alive_attacker_leader_ids"].append(leader_id)
			else:
				result["alive_defender_leader_ids"].append(leader_id)
		else:
			result["wounded_leader_ids"].append(leader_id)
			if side_name == "attacker":
				result["dead_attacker_leader_ids"].append(leader_id)
			else:
				result["dead_defender_leader_ids"].append(leader_id)
		return

	if unit.unit_ref == null:
		return
	if not ("id" in unit.unit_ref):
		return

	var unit_id: int = int(unit.unit_ref.unit_id)
	if unit_id < 0:
		return

	if unit.is_captured:
		if side_name == "attacker":
			result["captured_attacker_unit_ids"].append(unit_id)
		else:
			result["captured_defender_unit_ids"].append(unit_id)
		return

	if not bool(unit.is_alive):
		if side_name == "attacker":
			result["dead_attacker_unit_ids"].append(unit_id)
		else:
			result["dead_defender_unit_ids"].append(unit_id)


static func _writeback(state, setup: Dictionary, result: Dictionary) -> void:
	DebugLogger.log("event:battle_writeback", {
		"target_province": int(setup.get("target_province_id", -1)),
		"source_province": int(setup.get("source_province_id", -1)),
		"attacker_faction": int(setup.get("attacker_faction_id", -1)),
		"defender_faction": int(setup.get("defender_faction_id", -1)),
		"attacker_won": bool(result.get("attacker_won", false)),
		"defender_won": bool(result.get("defender_won", false)),
		"rounds_taken": int(result.get("rounds_taken", 0)),
		"wounded_leader_ids": result.get("wounded_leader_ids", []),
		"dead_attacker_unit_ids": result.get("dead_attacker_unit_ids", []),
		"dead_defender_unit_ids": result.get("dead_defender_unit_ids", []),
		"captured_attacker_unit_ids": result.get("captured_attacker_unit_ids", []),
		"captured_defender_unit_ids": result.get("captured_defender_unit_ids", [])
	})

	if state == null or state.map_data == null:
		return

	var source_id: int = int(setup.get("source_province_id", -1))
	var target_id: int = int(setup.get("target_province_id", -1))
	var attacker_faction_id: int = int(setup.get("attacker_faction_id", -1))
	var defender_faction_id: int = int(setup.get("defender_faction_id", -1))

	var attacker_won: bool = bool(result.get("attacker_won", false))
	var defender_won: bool = bool(result.get("defender_won", false))

	for unit_id_value in result.get("dead_attacker_unit_ids", []):
		_kill_unit(state, int(unit_id_value))

	for unit_id_value in result.get("dead_defender_unit_ids", []):
		_kill_unit(state, int(unit_id_value))

	for unit_id_value in result.get("captured_attacker_unit_ids", []):
		_capture_unit_to_faction(state, int(unit_id_value), defender_faction_id, target_id)

	for unit_id_value in result.get("captured_defender_unit_ids", []):
		_capture_unit_to_faction(state, int(unit_id_value), attacker_faction_id, target_id)

	for leader_id_value in result.get("wounded_leader_ids", []):
		var leader_id: int = int(leader_id_value)
		var leader = state.get_leader(leader_id)
		if leader == null:
			continue

		leader.status = "wounded"
		leader.on_mission = false
		leader.wounded_turns_remaining = 4

		var is_attacker_leader: bool = int(leader.faction_id) == attacker_faction_id
		if is_attacker_leader:
			leader.wounded_from_province_id = source_id
			if source_id >= 0:
				state.move_leader_to_province(leader_id, source_id)
		else:
			if defender_won:
				leader.wounded_from_province_id = target_id
				if target_id >= 0:
					state.move_leader_to_province(leader_id, target_id)
			else:
				leader.wounded_from_province_id = target_id
				var fallback_id: int = _find_closest_owned_province(state, defender_faction_id, target_id)
				if fallback_id >= 0:
					state.move_leader_to_province(leader_id, fallback_id)
				elif target_id >= 0:
					state.move_leader_to_province(leader_id, target_id)

	if attacker_won and target_id >= 0 and target_id < state.map_data.provinces.size():
		state.map_data.provinces[target_id].owner_id = attacker_faction_id

	for leader in setup.get("attacker_leaders", []):
		if leader == null:
			continue
		var lid: int = int(leader.id)
		var live_leader = state.get_leader(lid)
		if live_leader == null or str(live_leader.status) == "wounded":
			continue
		if attacker_won:
			if target_id >= 0:
				state.move_leader_to_province(lid, target_id)
		else:
			if source_id >= 0:
				state.move_leader_to_province(lid, source_id)

	for leader in setup.get("defender_leaders", []):
		if leader == null:
			continue
		var lid: int = int(leader.id)
		var live_leader = state.get_leader(lid)
		if live_leader == null or str(live_leader.status) == "wounded":
			continue
		if defender_won:
			if target_id >= 0:
				state.move_leader_to_province(lid, target_id)
		else:
			var fallback_id: int = _find_closest_owned_province(state, defender_faction_id, target_id)
			if fallback_id >= 0:
				state.move_leader_to_province(lid, fallback_id)
			elif target_id >= 0:
				state.move_leader_to_province(lid, target_id)
	# Unit XP: 75 XP per battle survived — skip if already applied by battle_scene
	if not bool(result.get("unit_xp_applied", false)):
		var dead_atk: Array = result.get("dead_attacker_unit_ids", [])
		var dead_def: Array = result.get("dead_defender_unit_ids", [])
		var cap_atk: Array = result.get("captured_attacker_unit_ids", [])
		var cap_def: Array = result.get("captured_defender_unit_ids", [])
		for leader in setup.get("attacker_leaders", []):
			if leader == null:
				continue
			for uid in leader.army_unit_ids:
				var unit_id: int = int(uid)
				if dead_atk.has(unit_id) or cap_atk.has(unit_id):
					continue
				var u = state.get_unit(unit_id)
				if u != null and u.has_method("add_xp"):
					u.add_xp(75)
		for leader in setup.get("defender_leaders", []):
			if leader == null:
				continue
			for uid in leader.army_unit_ids:
				var unit_id: int = int(uid)
				if dead_def.has(unit_id) or cap_def.has(unit_id):
					continue
				var u = state.get_unit(unit_id)
				if u != null and u.has_method("add_xp"):
					u.add_xp(75)
	# Item drops from dead units — give to winner, respecting province ownership
	for transfer in result.get("item_transfers", []):
		var item_id: String = str(transfer.get("item_id", ""))
		var from_side: String = str(transfer.get("from_side", ""))
		if item_id == "":
			continue
		# Winner gets items from the losing side
		if from_side == "attacker" and defender_won:
			# Defender gets attacker's dropped items — goes to target if still owned, else closest
			var dest: int = target_id
			if dest >= 0 and dest < state.map_data.provinces.size():
				if int(state.map_data.provinces[dest].owner_id) != defender_faction_id:
					dest = _find_closest_owned_province(state, defender_faction_id, target_id)
			if dest >= 0:
				state.award_item_to_province(dest, item_id)
				DebugLogger.log("event:battle_item_drop", {"item_id": item_id, "to_faction": defender_faction_id, "province": dest})
		elif from_side == "defender" and attacker_won:
			# Attacker gets defender's dropped items — goes to target if captured, else source
			var dest: int = target_id
			if dest >= 0 and dest < state.map_data.provinces.size():
				if int(state.map_data.provinces[dest].owner_id) != attacker_faction_id:
					dest = source_id if source_id >= 0 else _find_closest_owned_province(state, attacker_faction_id, target_id)
			if dest >= 0:
				state.award_item_to_province(dest, item_id)
				DebugLogger.log("event:battle_item_drop", {"item_id": item_id, "to_faction": attacker_faction_id, "province": dest})
	# Queue leader XP into pending_leader_xp_events for LeaderXPResolver
	var alive_atk_leaders: Array = result.get("alive_attacker_leader_ids", [])
	var alive_def_leaders: Array = result.get("alive_defender_leader_ids", [])
	if attacker_won:
		for lid in alive_atk_leaders:
			state.pending_leader_xp_events.append({"leader_id": int(lid), "amount": 150, "source": "tactical_capture"})
		for lid in alive_def_leaders:
			state.pending_leader_xp_events.append({"leader_id": int(lid), "amount": 40, "source": "tactical_repel_loss"})
	elif defender_won:
		for lid in alive_def_leaders:
			state.pending_leader_xp_events.append({"leader_id": int(lid), "amount": 40, "source": "tactical_repel"})
		for lid in alive_atk_leaders:
			state.pending_leader_xp_events.append({"leader_id": int(lid), "amount": 40, "source": "tactical_repel_loss"})
	_apply_xp_writeback(state, result)

static func _kill_unit(state, unit_id: int) -> void:
	if state == null or unit_id < 0:
		return

	var unit = state.get_unit(unit_id)
	if unit == null:
		return

	if "hp" in unit:
		unit.hp = 0

	for leader in state.leaders:
		if leader == null:
			continue
		if leader.army_unit_ids.has(unit_id):
			leader.army_unit_ids.erase(unit_id)

	if unit_id >= 0 and unit_id < state.units.size():
		state.units[unit_id] = null


static func _find_closest_owned_province(state, faction_id: int, start_province_id: int) -> int:
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
			var province = state.map_data.provinces[pid]
			if province != null and int(province.owner_id) == faction_id:
				return pid

		for next_id_value in adjacency.get(pid, []):
			var next_id: int = int(next_id_value)
			if visited.has(next_id):
				continue
			visited[next_id] = true
			queue.append(next_id)

	return -1




static func _capture_unit_to_faction(state, unit_id: int, captor_faction_id: int, start_province_id: int) -> void:
	if state == null or state.map_data == null:
		return
	if unit_id < 0 or captor_faction_id < 0:
		return

	var unit = state.get_unit(unit_id)
	if unit == null:
		return

	# Remove captured unit from any leader army it belongs to
	for leader in state.leaders:
		if leader == null:
			continue
		if leader.army_unit_ids.has(unit_id):
			leader.army_unit_ids.erase(unit_id)

	var destination_id: int = -1
	if start_province_id >= 0 and start_province_id < state.map_data.provinces.size():
		var start_province = state.map_data.provinces[start_province_id]
		if start_province != null and int(start_province.owner_id) == captor_faction_id:
			destination_id = start_province_id

	if destination_id < 0:
		destination_id = _find_closest_owned_province(state, captor_faction_id, start_province_id)

	if destination_id < 0:
		return

	if "is_captured" in unit:
		unit.is_captured = false

	state.move_unit_to_inventory(unit_id, destination_id)
	DebugLogger.log("event:battle_captured_unit_transferred", {
		"unit_id": unit_id,
		"captor_faction": captor_faction_id,
		"destination_province": destination_id
	})

static func _apply_xp_writeback(state, result: Dictionary) -> void:
	if state == null:
		return
	if not result.has("unit_snapshots"):
		return

	for snap_value in result.get("unit_snapshots", []):
		var snap: Dictionary = snap_value as Dictionary
		var leader_id: int = int(snap.get("leader_id", -1))
		if leader_id < 0:
			continue

		var leader = state.get_leader(leader_id)
		if leader == null:
			continue

		if "xp" in leader:
			leader.xp += int(snap.get("xp", 0))

		if "level" in leader:
			leader.level = max(int(leader.level), int(snap.get("level", int(leader.level))))
