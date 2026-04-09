# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: MissionResolver
#
# Role:
# Manages the full mission lifecycle each execute:
#   1. Spawns new missions into province slots
#   2. Counts down mission duration (expiry)
#   3. Advances travel phase for assigned leaders
#   4. Queues battle_ready missions for the battle system
#   5. Applies rewards or wounds after battle resolves
#   6. Handles slot cooldowns and rerolls
#
# Allowed Interactions:
# - GameState
# - MapData / FactionData / ProvinceData / LeaderData
# - MissionData (creates and mutates)
# - MissionLibrary (read-only templates)
# - ItemLibrary (item reward rolls)
# - DebugLogger (logging only)
#
# Forbidden Responsibilities:
# - Must not interact with UI
# - Must not create campaign attack orders
# - Must not orchestrate the turn
#
# Game Phase:
# Execution Phase
#
# Notes:
# - Mission flow: available → travelling → battle_ready → completed/expired
# - Travel phase = 1 execute. Battle phase = next execute.
# - Old mission system (weighted outcome rolls) fully replaced.
# - active_missions on GameState is keyed by instance_id.
# ==================================================

class_name MissionResolver
extends RefCounted

const MissionLibraryScript  = preload("res://Scripts/data/mission_library.gd")
const MissionDataScript      = preload("res://Scripts/data/mission_data.gd")
const ItemLibraryScript      = preload("res://Scripts/data/item_library.gd")
const UnitLibraryScript      = preload("res://Scripts/data/unit_library.gd")
const SigilLibraryScript     = preload("res://Scripts/data/sigil_library.gd")
const MissionTuningProfileScript = preload("res://Scripts/game/tools/mission_tuning_profile.gd")

const MAX_PROVINCE_MISSIONS: int  = 2
const SLOT_COOLDOWN_MIN: int      = 2
const SLOT_COOLDOWN_MAX: int      = 4
const LOSS_WOUND_TURNS: int       = 4

var _instance_counter: int = 0


# --------------------------------------------------
# MAIN ENTRY POINT
# --------------------------------------------------

func resolve(state: GameState) -> void:
	if state == null or state.map_data == null:
		return

	# Ensure active_missions dict exists on state
	if not "active_missions" in state:
		return

	var log = state.logger

	var spawned:  int = 0
	var expired:  int = 0
	var assigned: int = 0

	# Clear last turn's pending results
	state.pending_mission_results.clear()

	# ── 1. Process queued mission assignments from OrderBook ─
	assigned += _process_mission_orders(state)

	# ── 2. Tick travel timers + detect battle_ready ──────────
	_advance_travel(state)

	# ── 3. Count down duration on available missions ─────────
	expired += _tick_durations(state)

	# ── 4. Tick slot cooldowns + spawn new missions ──────────
	spawned += _tick_cooldowns_and_spawn(state)

	# ── 5. Spawn tutorial missions on month 1 (once per faction) ─
	if int(state.month_index) == 1:
		spawned += _spawn_tutorial_missions(state)

	if log != null:
		log.event("mission_resolver_summary", {
			"spawned":  spawned,
			"expired":  expired,
			"assigned": assigned,
		})


# --------------------------------------------------
# ORDER BOOK PROCESSING
# --------------------------------------------------

func _process_mission_orders(state: GameState) -> int:
	if state.order_book == null:
		return 0

	var assigned: int = 0

	for faction_item in state.map_data.factions:
		var faction: FactionData = faction_item as FactionData
		if faction == null:
			continue
		var fid: int = int(faction.id)
		var orders: Array = state.order_book.get_missions(fid)

		for order_item in orders:
			var o: Dictionary = order_item as Dictionary
			var leader_id: int = int(o.get("leader_id", -1))
			var mission_instance_id: String = str(o.get("mission_instance_id", ""))

			if leader_id < 0 or mission_instance_id == "":
				DebugLogger.log("event:mission_assign_skip", {
					"reason": "bad_order", "leader_id": leader_id,
					"mission_instance_id": mission_instance_id
				})
				continue

			var leader: LeaderData = _find_leader(state, leader_id)
			if leader == null:
				DebugLogger.log("event:mission_assign_skip", {
					"reason": "leader_not_found", "leader_id": leader_id
				})
				continue

			if not state.active_missions.has(mission_instance_id):
				DebugLogger.log("event:mission_assign_skip", {
					"reason": "mission_not_found",
					"mission_instance_id": mission_instance_id,
					"leader_id": leader_id,
				})
				continue

			var mission: MissionData = state.active_missions[mission_instance_id] as MissionData
			if mission == null:
				continue

			var success: bool = assign_leader_to_mission(state, mission, leader)
			if success:
				assigned += 1

	return assigned


# --------------------------------------------------
# TRAVEL ADVANCEMENT
# --------------------------------------------------
# Each execute, leaders on mission have their travel timer decremented.
# When travel_turns_remaining hits 0 the mission becomes battle_ready.
# The TurnManager / BattleManager picks up battle_ready missions and
# triggers the tactical battle. Results come back via apply_mission_result().

func _advance_travel(state: GameState) -> void:
	for instance_id in state.active_missions.keys():
		var mission: MissionData = state.active_missions[instance_id] as MissionData
		if mission == null:
			continue
		if mission.phase != "travelling":
			continue

		mission.travel_turns_remaining = maxi(0, mission.travel_turns_remaining - 1)

		if mission.travel_turns_remaining <= 0:
			mission.phase = "battle_ready"
			DebugLogger.log("event:mission_battle_ready", {
				"instance_id":   mission.instance_id,
				"template_id":   mission.template_id,
				"display_name":  mission.display_name,
				"province_id":   mission.province_id,
				"leader_id":     mission.assigned_leader_id,
			})
			var BattleManagerScript = load("res://Scripts/game/battle/battle_manager.gd")
			if BattleManagerScript != null:
				BattleManagerScript.queue_mission_battle(state, str(mission.instance_id))


# --------------------------------------------------
# DURATION TICK
# --------------------------------------------------
# Available missions (not yet assigned) count down each execute.
# When duration hits 0 the mission expires and the slot enters cooldown.

func _tick_durations(state: GameState) -> int:
	var expired: int = 0
	for instance_id in state.active_missions.keys():
		var mission: MissionData = state.active_missions[instance_id] as MissionData
		if mission == null:
			continue
		if mission.phase != "available":
			continue

		mission.duration_remaining = maxi(0, mission.duration_remaining - 1)

		if mission.duration_remaining <= 0:
			mission.phase = "expired"
			expired += 1
			_expire_mission(state, mission)
			DebugLogger.log("event:mission_expired", {
				"instance_id":  mission.instance_id,
				"template_id":  mission.template_id,
				"province_id":  mission.province_id,
			})

	return expired


func _expire_mission(state: GameState, mission: MissionData) -> void:
	# Remove from province active list
	var province: ProvinceData = _get_province(state, mission.province_id)
	if province != null:
		province.active_missions.erase(mission.instance_id)
		# Set slot cooldown so this slot rerolls after a few turns
		var cooldown: int = state.rng.randi_range(SLOT_COOLDOWN_MIN, SLOT_COOLDOWN_MAX)
		if mission.slot_index < province.mission_slot_cooldowns.size():
			province.mission_slot_cooldowns[mission.slot_index] = cooldown
		else:
			province.mission_slot_cooldowns.append(cooldown)

	# Remove from global registry
	state.active_missions.erase(mission.instance_id)


# --------------------------------------------------
# COOLDOWN TICK + SPAWNING
# --------------------------------------------------

func _spawn_tutorial_missions(state: GameState) -> int:
	# Spawn one tutorial mission per faction in their home province.
	# Each of the 3 tutorials fires once and is tracked in faction.tutorial_missions_seen.
	# Tutorials do not use the cooldown/slot system — they are injected directly.
	var all_tutorials: Array = ["tutorial_broken_armor", "tutorial_cavalry_threat", "tutorial_light_infantry"]
	var spawned: int = 0

	for faction_item in state.map_data.factions:
		var faction: FactionData = faction_item as FactionData
		if faction == null or bool(faction.is_eliminated):
			continue

		# Find a province owned by this faction to spawn the tutorial in
		var home_province: ProvinceData = null
		for pid in faction.provinces:
			var p: ProvinceData = state.map_data.provinces[int(pid)] as ProvinceData
			if p != null and int(p.owner_id) == int(faction.id):
				home_province = p
				break
		if home_province == null:
			continue

		for tutorial_id in all_tutorials:
			# Skip if already seen
			if faction.tutorial_missions_seen.has(tutorial_id):
				continue
			var template: Dictionary = MissionLibraryScript.get_template(tutorial_id)
			if template.is_empty():
				continue
			# Find an open slot — tutorials bypass MAX_PROVINCE_MISSIONS cap
			while home_province.mission_slot_cooldowns.size() < MAX_PROVINCE_MISSIONS:
				home_province.mission_slot_cooldowns.append(0)
			var slot: int = -1
			for s in range(home_province.active_missions.size() + 1):
				if s >= home_province.active_missions.size() or str(home_province.active_missions[s]) == "":
					slot = s
					break
			if slot < 0:
				slot = home_province.active_missions.size()  # append beyond current slots
			var mission: MissionData = _spawn_mission(state, template, home_province, slot)
			if mission == null:
				continue
			state.active_missions[mission.instance_id] = mission
			if slot < home_province.active_missions.size():
				home_province.active_missions[slot] = mission.instance_id
			else:
				home_province.active_missions.append(mission.instance_id)
			# Extend cooldown array to match
			while home_province.mission_slot_cooldowns.size() <= slot:
				home_province.mission_slot_cooldowns.append(0)
			faction.tutorial_missions_seen.append(tutorial_id)
			spawned += 1
			DebugLogger.log("event:tutorial_mission_spawned", {
				"instance_id":  mission.instance_id,
				"template_id":  tutorial_id,
				"faction_id":   int(faction.id),
				"province_id":  int(home_province.id),
			})
			break  # one tutorial per faction per month — stagger them

	return spawned


func _tick_cooldowns_and_spawn(state: GameState) -> int:
	var spawned: int = 0
	for province_item in state.map_data.provinces:
		var province: ProvinceData = province_item as ProvinceData
		if province == null:
			continue
		# Only spawn missions in owned provinces
		if int(province.owner_id) < 0:
			continue

		# Ensure cooldown array is sized to MAX_PROVINCE_MISSIONS
		while province.mission_slot_cooldowns.size() < MAX_PROVINCE_MISSIONS:
			province.mission_slot_cooldowns.append(0)
		# Clean up stale mission ids
		_clean_province_missions(state, province)

		# Count how many non-tutorial missions are active in this province
		var non_tutorial_count: int = 0
		for mid in province.active_missions:
			if str(mid) == "":
				continue
			var m = state.active_missions.get(str(mid))
			if m != null and str(m.mission_type) != "tutorial":
				non_tutorial_count += 1

		for slot in range(MAX_PROVINCE_MISSIONS):
			# Skip if slot is already occupied
			if slot < province.active_missions.size() and str(province.active_missions[slot]) != "":
				continue

			# Skip if non-tutorial cap already reached (tutorials don't count)
			if non_tutorial_count >= MAX_PROVINCE_MISSIONS:
				continue

			# Tick cooldown
			var cd: int = int(province.mission_slot_cooldowns[slot])
			if cd > 0:
				province.mission_slot_cooldowns[slot] = cd - 1
				continue

			# Roll whether a mission spawns (spawn_roll_chance from MissionTuningProfile)
			var _spawn_profile := MissionTuningProfileScript.get_instance()
			if state.rng.randf() >= float(_spawn_profile.spawn_roll_chance):
				continue

			# Pick a template valid for this biome (regulator-aware)
			var template: Dictionary = _pick_template(state, str(province.biome), int(province.id))
			if template.is_empty():
				continue

			# Spawn the mission
			var mission: MissionData = _spawn_mission(state, template, province, slot)
			if mission != null:
				# Register globally
				state.active_missions[mission.instance_id] = mission
				# Register in province slot
				if slot < province.active_missions.size():
					province.active_missions[slot] = mission.instance_id
				else:
					province.active_missions.append(mission.instance_id)
				if str(mission.mission_type) != "tutorial":
					non_tutorial_count += 1
				# Record spawn for regulator
				var spawned_cat: String = MissionLibraryScript.get_type_category(str(mission.mission_type))
				_record_spawn(int(province.id), spawned_cat)
				spawned += 1
				DebugLogger.log("event:mission_spawned", {
					"instance_id":  mission.instance_id,
					"template_id":  mission.template_id,
					"display_name": mission.display_name,
					"province_id":  mission.province_id,
					"biome":        mission.biome,
					"type":         mission.mission_type,
					"risk":         mission.risk_level,
					"duration":     mission.duration_remaining,
				})

	return spawned


func _clean_province_missions(state: GameState, province: ProvinceData) -> void:
	# Remove any stale instance_ids that no longer exist in the global registry
	var cleaned: Array = []
	for entry in province.active_missions:
		var iid: String = str(entry)
		if iid != "" and state.active_missions.has(iid):
			cleaned.append(iid)
	province.active_missions = cleaned


# --------------------------------------------------
# TEMPLATE SELECTION
# --------------------------------------------------

# Per-province spawn counts — keyed by province_id, value is {category: count}
# Stored as instance var so it persists across the session without touching ProvinceData.
var _province_type_counts: Dictionary = {}

const _TYPE_CATEGORIES: Array = ["skirmish", "treasure", "hunt", "elite"]
# _REGULATOR_LAG_THRESHOLD is now read from MissionTuningProfile.regulator_lag_threshold

func _get_type_counts(province_id: int) -> Dictionary:
	if not _province_type_counts.has(province_id):
		_province_type_counts[province_id] = {"skirmish": 0, "treasure": 0, "hunt": 0, "elite": 0}
	return _province_type_counts[province_id]

func _record_spawn(province_id: int, category: String) -> void:
	var counts: Dictionary = _get_type_counts(province_id)
	counts[category] = int(counts.get(category, 0)) + 1

func _pick_forced_category(province_id: int) -> String:
	# Find least-spawned category. If it's >= REGULATOR_LAG_THRESHOLD behind
	# the most-spawned category, force it next.
	var counts: Dictionary = _get_type_counts(province_id)
	var min_count: int = 999999
	var max_count: int = 0
	var least_cat: String = ""
	for cat in _TYPE_CATEGORIES:
		var c: int = int(counts.get(cat, 0))
		if c < min_count:
			min_count = c
			least_cat = cat
		if c > max_count:
			max_count = c
	var _lag_thresh: int = MissionTuningProfileScript.get_instance().regulator_lag_threshold
	if max_count - min_count >= _lag_thresh:
		return least_cat
	return ""

func _pick_template(state: GameState, biome: String, province_id: int = -1) -> Dictionary:
	# Get all templates valid for this biome
	var candidates: Array = MissionLibraryScript.get_templates_for_biome(biome)
	if candidates.is_empty():
		return {}

	# Regulator: check if any category is lagging and needs a forced spawn
	var chosen_category: String = ""
	if province_id >= 0:
		chosen_category = _pick_forced_category(province_id)

	if chosen_category == "":
		# Equal random pick across categories (TYPE_WEIGHTS are now all 25)
		var cats_available: Array = []
		for cat in _TYPE_CATEGORIES:
			var has_match: bool = false
			for t in candidates:
				if MissionLibraryScript.get_type_category(str(t.get("mission_type", ""))) == cat:
					has_match = true
					break
			if has_match:
				cats_available.append(cat)
		if cats_available.is_empty():
			return candidates[state.rng.randi_range(0, candidates.size() - 1)] as Dictionary
		chosen_category = cats_available[state.rng.randi_range(0, cats_available.size() - 1)]

	# Filter candidates to chosen category
	var filtered: Array = []
	for t in candidates:
		if MissionLibraryScript.get_type_category(str(t.get("mission_type", ""))) == chosen_category:
			filtered.append(t)

	if filtered.is_empty():
		return candidates[state.rng.randi_range(0, candidates.size() - 1)] as Dictionary

	# Weighted pick within category by spawn_weight
	var total_weight: int = 0
	for t in filtered:
		total_weight += int(t.get("spawn_weight", 10))
	var w_roll: int = state.rng.randi_range(1, maxi(1, total_weight))
	var acc: int = 0
	for t in filtered:
		acc += int(t.get("spawn_weight", 10))
		if w_roll <= acc:
			return t as Dictionary

	return filtered[filtered.size() - 1] as Dictionary


# --------------------------------------------------
# MISSION SPAWN
# --------------------------------------------------

func _spawn_mission(state: GameState, template: Dictionary, province: ProvinceData, slot: int) -> MissionData:
	var mission: MissionData = MissionDataScript.new()
	_instance_counter += 1
	mission.instance_id   = "mission_%04d" % _instance_counter
	mission.template_id   = str(template.get("id", ""))
	mission.display_name  = str(template.get("display_name", "Unknown Mission"))
	mission.province_id   = int(province.id)
	mission.biome         = str(province.biome)
	mission.mission_type  = str(template.get("mission_type", "skirmish"))
	mission.risk_level    = str(template.get("risk_level", "medium"))
	mission.slot_index    = slot
	mission.phase         = "available"
	mission.assigned_leader_id = -1
	mission.travel_turns_remaining = 0

	# Duration: random within template range
	var dur_min: int = int(template.get("duration_min", 2))
	var dur_max: int = int(template.get("duration_max", 3))
	mission.duration_remaining = state.rng.randi_range(dur_min, dur_max)

	# Reward table — copy from template
	mission.reward_table = template.get("reward_table", {}).duplicate()

	return mission


# --------------------------------------------------
# MISSION ASSIGNMENT (called from OrderBook processing)
# --------------------------------------------------
# Called when a leader is assigned to a mission during the planning phase.
# Locks the leader, builds the scaled battle template, begins travel.

func assign_leader_to_mission(state: GameState, mission: MissionData, leader: LeaderData) -> bool:
	if mission == null or leader == null:
		DebugLogger.log("event:mission_assign_failed", {"reason": "null_args"})
		return false
	if mission.phase != "available":
		DebugLogger.log("event:mission_assign_failed", {
			"reason": "wrong_phase", "phase": mission.phase,
			"instance_id": mission.instance_id, "leader_id": leader.id
		})
		return false
	if bool(leader.on_mission) or str(leader.status) in ["wounded", "injured", "on_mission"]:
		DebugLogger.log("event:mission_assign_failed", {
			"reason": "leader_busy", "status": leader.status,
			"on_mission": leader.on_mission, "leader_id": leader.id
		})
		return false

	# Lock leader
	leader.on_mission = true
	leader.status = "on_mission"
	leader.mission_id = mission.instance_id
	leader.mission_type = mission.mission_type
	leader.mission_turns_remaining = 1  # 1 travel turn before battle
	leader.mission_origin_province_id = int(leader.province_id)

	# Remove leader from province (locked during mission)
	var province: ProvinceData = _get_province(state, int(leader.province_id))
	if province != null:
		province.leader_ids.erase(int(leader.id))

	# Build scaled battle template
	var template: Dictionary = MissionLibraryScript.get_template(mission.template_id)
	mission.battle_template = _build_battle_template(state, template, leader)

	# Advance mission phase
	mission.assigned_leader_id = int(leader.id)
	mission.travel_turns_remaining = 1
	mission.phase = "travelling"

	DebugLogger.log("event:mission_assigned", {
		"instance_id":  mission.instance_id,
		"template_id":  mission.template_id,
		"leader_id":    leader.id,
		"leader_name":  leader.display_name,
		"province_id":  mission.province_id,
	})

	return true


# --------------------------------------------------
# BATTLE TEMPLATE BUILDER
# --------------------------------------------------
# Scales enemy force to the player's army power.
# Returns a setup_dict compatible with the existing BattleState initialiser.

func _build_battle_template(state: GameState, template: Dictionary, leader: LeaderData) -> Dictionary:
	var enemy_profile: Dictionary = template.get("enemy_profile", {}) as Dictionary
	var scaling: String = str(enemy_profile.get("scaling", "player_power"))
	var special_rule: String = str(template.get("special_rule", "none"))

	# Calculate player power (leader attack + unit count contribution)
	var player_atk: int = int(leader.attack)
	var player_unit_count: int = leader.army_unit_ids.size()
	var player_power: float = float(player_atk) + float(player_unit_count) * 8.0

	# Stat scale factor — elite missions use dedicated scale range from MissionTuningProfile
	var _mtp := MissionTuningProfileScript.get_instance()
	var _is_elite_template: bool = str(template.get("mission_type", "")) == "elite"
	var scale_low: float = float(_mtp.elite_scale_low if _is_elite_template else _mtp.scale_low)
	var scale_high: float = float(_mtp.elite_scale_high if _is_elite_template else _mtp.scale_high)
	var stat_scale: float = scale_low + state.rng.randf() * (scale_high - scale_low)

	# Scale enemy unit count
	var unit_min: int = int(enemy_profile.get("unit_count_min", 3))
	var unit_max: int = int(enemy_profile.get("unit_count_max", 5))
	if scaling == "player_power":
		var scaled_count: int = clampi(player_unit_count + state.rng.randi_range(-1, 1), unit_min, unit_max)
		unit_min = scaled_count
		unit_max = scaled_count
	elif scaling == "fixed":
		stat_scale = 1.0  # no scaling for tutorials

	var unit_count: int = state.rng.randi_range(unit_min, unit_max)
	# For elite missions, enemy tier tracks leader level so the gap stays fair:
	# Lv 1-4 → Tier 1 enemies, Lv 5-9 → Tier 2, Lv 10+ → Tier 3
	var unit_tier: int = int(enemy_profile.get("unit_tier", 1))
	var mission_type_for_tier: String = str(template.get("mission_type", ""))
	if mission_type_for_tier == "elite":
		var lv: int = int(leader.level)
		# Tier tracks leader level
		if lv >= 10:
			unit_tier = 3
		elif lv >= 5:
			unit_tier = 2
		else:
			unit_tier = 1
		# Stat scale multiplier adjusts difficulty relative to leader progression
		# Early leaders face proportionally harder enemies to compensate for Tier 1 army
		if lv >= 10:
			stat_scale = stat_scale * 0.85  # late: slightly easier, army quality compensates
		elif lv >= 5:
			stat_scale = stat_scale * 1.0   # mid: no adjustment, fair fight
		else:
			stat_scale = stat_scale * 1.25  # early: enemies are harder to compensate for Tier 1 army
	var roles: Array = enemy_profile.get("roles", ["frontline"]) as Array
	var force_damage_type: String = str(enemy_profile.get("force_damage_type", ""))
	var has_leader: bool = int(enemy_profile.get("leader_count", 1)) > 0
	var has_ally: bool = bool(enemy_profile.get("has_ally", false))

	# Build enemy unit list from biome + tier + roles
	var mission_biome: String = "plains"
	var province: ProvinceData = _get_province(state, int(leader.mission_origin_province_id))
	if province != null:
		mission_biome = str(province.biome)
	var enemy_units: Array = _build_enemy_units(state, province, unit_tier, unit_count, roles, mission_biome, stat_scale, force_damage_type)

	# Build enemy leader — hunt_capture pulls a real general from reserve pool
	var enemy_leader_dict: Dictionary = {}
	var hunt_target_template: Dictionary = {}
	var mission_type_str: String = str(template.get("mission_type", ""))
	if has_leader:
		if mission_type_str == "hunt_capture":
			# Claim a reserve general template to use as the hunt target
			var faction_id: int = int(leader.faction_id)
			var tpl: Dictionary = state.claim_reserve_general_template(faction_id, int(leader.mission_origin_province_id))
			if not tpl.is_empty():
				hunt_target_template = tpl
				# Use their stats for the enemy leader in battle
				var tpl_atk: int = int(tpl.get("attack", 12))
				var tpl_def: int = int(tpl.get("defense", 10))
				enemy_leader_dict = {
					"name": str(tpl.get("display_name", "Rising General")),
					"attack":       tpl_atk,
					"defense":      tpl_def,
					"hp":           65,
					"damage_type":  str(tpl.get("damage_type", "slash")),
					"speed":        int(tpl.get("speed", 5)),
					"accuracy":     int(tpl.get("accuracy", 72)),
					"evasion":      int(tpl.get("evasion", 10)),
					"leadership":   int(tpl.get("leadership", 8)),
					"level":        1,
					"is_hunt_target": true,
				}
			else:
				# Fallback to generic if pool exhausted
				enemy_leader_dict = _build_enemy_leader(state, special_rule, stat_scale)
		else:
			enemy_leader_dict = _build_enemy_leader(state, special_rule, stat_scale)

	# Build rescue ally — claimed from reserve pool, fights on attacker side
	var ally_leader_template: Dictionary = {}
	if has_ally and str(enemy_profile.get("ally_pool", "")) == "rescue":
		var faction_id: int = int(leader.faction_id)
		var tpl: Dictionary = state.claim_reserve_general_template(faction_id, int(leader.mission_origin_province_id))
		if not tpl.is_empty():
			ally_leader_template = tpl

	return {
		"enemy_leader":        enemy_leader_dict,
		"enemy_units":         enemy_units,
		"has_ally":            has_ally,
		"ally_pool":           str(enemy_profile.get("ally_pool", "")),
		"ally_leader_template": ally_leader_template,
		"special_rule":        special_rule,
		"mission_type":        mission_type_str,
		"hunt_target_template": hunt_target_template,
		"is_tutorial":         mission_type_str == "tutorial",
	}


func _build_enemy_units(state: GameState, _province, tier: int, count: int, roles: Array, biome: String, stat_scale: float = 1.0, force_damage_type: String = "") -> Array:
	var units: Array = []
	# Get units matching biome + tier
	var pool: Array = []
	for tpl in UnitLibraryScript.UNIT_TEMPLATES:
		var t: Dictionary = tpl as Dictionary
		if int(t.get("tier", 1)) != tier:
			continue
		# If forcing a damage type, filter by it
		if force_damage_type != "" and str(t.get("damage_type", "")) != force_damage_type:
			continue
		var biomes: Array = t.get("biome", []) as Array
		if not biomes.has(biome) and not biomes.has("plains"):
			continue
		pool.append(t)

	if pool.is_empty():
		# Fallback: any tier 1 unit matching damage type if forced, else any
		for tpl in UnitLibraryScript.UNIT_TEMPLATES:
			var t: Dictionary = tpl as Dictionary
			if int(t.get("tier", 1)) != 1:
				continue
			if force_damage_type != "" and str(t.get("damage_type", "")) != force_damage_type:
				continue
			pool.append(t)

	if pool.is_empty():
		# Last resort: any tier 1
		for tpl in UnitLibraryScript.UNIT_TEMPLATES:
			if int((tpl as Dictionary).get("tier", 1)) == 1:
				pool.append(tpl)

	for i in range(count):
		if pool.is_empty():
			break
		var tpl: Dictionary = pool[state.rng.randi_range(0, pool.size() - 1)] as Dictionary
		units.append({
			"unit_type":    str(tpl.get("unit_type", "Militia Swordsman")),
			"attack":       maxi(6,  int(round(int(tpl.get("attack",  11)) * stat_scale))),
			"defense":      maxi(4,  int(round(int(tpl.get("defense", 10)) * stat_scale))),
			"hp":           maxi(20, int(round(int(tpl.get("hp",      45)) * stat_scale))),
			"damage_type":  str(tpl.get("damage_type", "slash")),
			"speed":        int(tpl.get("speed", 4)),
			"accuracy":     int(tpl.get("accuracy", 75)),
			"evasion":      int(tpl.get("evasion", 8)),
		})

	return units


func _build_enemy_leader(state: GameState, special_rule: String, stat_scale: float = 1.0) -> Dictionary:
	# Enemy leader stats scale with player power
	var base_atk: int = maxi(8,  int(round(state.rng.randi_range(12, 18) * stat_scale)))
	var base_def: int = maxi(6,  int(round(state.rng.randi_range(10, 16) * stat_scale)))
	var base_hp: int  = maxi(40, int(round(65 * stat_scale)))
	var evasion: int = 20 if special_rule == "evasive_boss" else state.rng.randi_range(8, 14)
	return {
		"name": "Enemy Leader",
		"attack":       base_atk,
		"defense":      base_def,
		"hp":           base_hp,
		"damage_type":  "slash",
		"speed":        state.rng.randi_range(4, 7),
		"accuracy":     state.rng.randi_range(68, 80),
		"evasion":      evasion,
		"leadership":   10,
		"level":        1,
	}


# --------------------------------------------------
# MISSION RESULT APPLICATION
# --------------------------------------------------
# Called by TurnManager / BattleManager after the tactical battle resolves.
# win = true if player won the mission battle.

func apply_mission_result(state: GameState, mission: MissionData, win: bool, battle_result: Dictionary = {}) -> Dictionary:
	if mission == null:
		return {}

	var leader: LeaderData = _find_leader(state, mission.assigned_leader_id)
	var result: Dictionary = {
		"instance_id":  mission.instance_id,
		"template_id":  mission.template_id,
		"display_name": mission.display_name,
		"leader_id":    mission.assigned_leader_id,
		"win":          win,
	}

	var origin_id: int = int(mission.province_id)
	var return_province: ProvinceData = _find_return_province(state, leader, origin_id)
	var return_id: int = int(return_province.id) if return_province != null else origin_id

	if win:
		mission.result = "win"
		result.merge(_apply_win_rewards(state, mission, leader, return_province, battle_result))
	else:
		mission.result = "loss"
		result.merge(_apply_loss_penalties(state, leader))

	# Sigil drop — controlled by MissionTuningProfile, uses win in scope here
	var _mtp2 := MissionTuningProfileScript.get_instance()
	var _is_elite: bool = str(mission.mission_type) == "elite"
	var _rng: RandomNumberGenerator = state.rng
	var _elite_drop: bool = _is_elite and win and _rng.randf() < float(_mtp2.elite_sigil_chance)
	var _elite_loss_drop: bool = _is_elite and (not win) and bool(_mtp2.elite_sigil_on_loss)
	var _non_elite_drop: bool = (not _is_elite) and win and _rng.randf() < float(_mtp2.non_elite_sigil_chance)
	var _sigil_province: ProvinceData = return_province
	if (_elite_drop or _elite_loss_drop or _non_elite_drop) and _sigil_province != null:
		var max_tier: int = _calc_sigil_tier_from_leaders(state)
		# Build eligible pool — exclude already-dropped sigils in each tier
		# until all sigils in that tier have dropped (then reset that tier)
		var eligible: Array = []
		for s in SigilLibraryScript.SIGILS:
			var stier: int = int(s.get("tier", 1))
			if stier > max_tier:
				continue
			# Count total sigils in this tier
			var tier_total: int = 0
			for ts in SigilLibraryScript.SIGILS:
				if int(ts.get("tier", 1)) == stier:
					tier_total += 1
			# Get already-dropped list for this tier
			if not state.sigils_dropped_by_tier.has(stier):
				state.sigils_dropped_by_tier[stier] = []
			var dropped: Array = state.sigils_dropped_by_tier[stier]
			# If all sigils in tier have dropped, reset the tracker
			if dropped.size() >= tier_total:
				state.sigils_dropped_by_tier[stier] = []
				dropped = []
			# Only include if not yet dropped this cycle
			if not dropped.has(str(s.get("id", ""))):
				eligible.append(s)
		if not eligible.is_empty():
			var picked: Dictionary = eligible[_rng.randi() % eligible.size()]
			var sigil_id: String = str(picked.get("id", ""))
			var sigil_tier: int = int(picked.get("tier", 1))
			if sigil_id != "":
				_sigil_province.add_sigil(sigil_id)
				# Record in tracker
				if not state.sigils_dropped_by_tier.has(sigil_tier):
					state.sigils_dropped_by_tier[sigil_tier] = []
				state.sigils_dropped_by_tier[sigil_tier].append(sigil_id)
				result["sigil_id"] = sigil_id
				result["sigil_name"] = str(picked.get("name", sigil_id))
				DebugLogger.log("event:mission_sigil_drop", {
					"instance_id": mission.instance_id,
					"sigil_id": sigil_id,
					"sigil_tier": sigil_tier,
					"max_tier_allowed": max_tier,
					"province_id": int(_sigil_province.id),
					"mission_type": mission.mission_type,
					"on_loss": not win,
				})

	# Return leader to province
	if leader != null:
		_return_leader(state, leader, return_id, return_province)

	# Complete the mission slot
	_complete_mission(state, mission)

	state.pending_mission_results.append(result)
	DebugLogger.log("event:mission_result", result)

	return result


func _apply_win_rewards(state: GameState, mission: MissionData, leader: LeaderData, province: ProvinceData, battle_result: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {}
	var reward: Dictionary = mission.reward_table as Dictionary
	var rng: RandomNumberGenerator = state.rng

	# XP — always
	var xp_min: int = int(reward.get("xp_min", 60))
	var xp_max: int = int(reward.get("xp_max", 120))
	var xp_gain: int = rng.randi_range(xp_min, xp_max)
	if leader != null:
		var levels_gained: int = leader.add_xp(xp_gain)
		out["xp_gain"] = xp_gain
		out["levels_gained"] = levels_gained
		state.pending_leader_xp_events.append({
			"leader_id": int(leader.id),
			"amount":    xp_gain,
			"source":    "mission_%s" % mission.mission_type,
			"success":   true,
		})

	# Gold
	var gold_min: int = int(reward.get("gold_min", 0))
	var gold_max: int = int(reward.get("gold_max", 0))
	if gold_max > 0 and leader != null:
		var gold_gain: int = rng.randi_range(gold_min, gold_max)
		var faction: FactionData = _find_faction(state.map_data, int(leader.faction_id))
		if faction != null:
			faction.gold = int(faction.gold) + gold_gain
		out["gold_gain"] = gold_gain

	# Skirmish unit capture — strongest enemy unit joins province inventory for free
	if str(mission.mission_type) == "skirmish":
		var captured_type: String = str(battle_result.get("skirmish_captured_unit_type", ""))
		if captured_type != "" and province != null and leader != null:
			var new_id: int = state._next_unit_id
			state._next_unit_id += 1
			var captured_unit = UnitLibraryScript.create_unit(captured_type, new_id)
			if captured_unit != null:
				captured_unit.province_id = int(province.id)
				state.units.append(captured_unit)
				province.add_unit_to_inventory(new_id)
				out["captured_unit_type"] = captured_type
				out["captured_unit_name"] = str(battle_result.get("skirmish_captured_unit_name", captured_type))
				DebugLogger.log("event:skirmish_unit_captured", {
					"instance_id":  mission.instance_id,
					"unit_type":    captured_type,
					"province_id":  int(province.id),
					"faction_id":   int(leader.faction_id),
				})

	# Item drop — always awarded to the leader's return province
	var _mtp3 := MissionTuningProfileScript.get_instance()
	var _base_item_chance: float = float(reward.get("item_chance", 0.0))
	# Override item chance per category from MissionTuningProfile
	var _mission_cat: String = str(mission.mission_type)
	var item_chance: float = _base_item_chance
	if _mission_cat == "skirmish": item_chance = float(_mtp3.item_chance_skirmish)
	elif _mission_cat == "treasure": item_chance = float(_mtp3.item_chance_treasure)
	elif _mission_cat in ["hunt_capture", "hunt_rescue"]: item_chance = float(_mtp3.item_chance_hunt)
	elif _mission_cat == "elite": item_chance = float(_mtp3.item_chance_elite)
	if item_chance > 0.0 and rng.randf() < item_chance:
		var item_id: String = ItemLibraryScript.roll_mission_item(rng)
		if item_id != "":
			if province != null:
				state.award_item_to_province(int(province.id), item_id)
				out["item_id"] = item_id
				out["item_name"] = str(ItemLibraryScript.get_item(item_id).get("name", item_id))
				out["item_province"] = int(province.id)
				DebugLogger.log("event:mission_item_awarded", {
					"instance_id":  mission.instance_id,
					"item_id":      item_id,
					"item_name":    out["item_name"],
					"province_id":  int(province.id),
					"mission_type": mission.mission_type,
				})
			else:
				DebugLogger.log("event:mission_item_drop_failed", {
					"instance_id": mission.instance_id,
					"reason": "no_return_province",
				})
		# Gem inside item roll
		var gem_chance: float = float(reward.get("gem_chance", 0.0))
		if gem_chance > 0.0 and rng.randf() < gem_chance:
			out["gem_found"] = true  # placeholder until skill gem system is built

	# Rising general recruit
	var bt: Dictionary = mission.battle_template as Dictionary
	var hunt_tpl: Dictionary = bt.get("hunt_target_template", {}) as Dictionary
	if not hunt_tpl.is_empty() and str(mission.mission_type) == "hunt_capture":
		# Hunt capture — recruit the pre-selected general from the template
		if leader != null and state.can_faction_gain_general(int(leader.faction_id), 1):
			var recruit_province_id: int = int(province.id if province != null else mission.province_id)
			var new_leader: LeaderData = state.create_leader_from_template(hunt_tpl, recruit_province_id, true)
			if new_leader != null:
				out["rising_general_id"]   = new_leader.id
				out["rising_general_name"] = new_leader.display_name
				DebugLogger.log("event:hunt_general_recruited", {
					"leader_id":   new_leader.id,
					"name":        new_leader.display_name,
					"faction_id":  new_leader.faction_id,
					"province_id": recruit_province_id,
				})
	elif str(mission.mission_type) == "hunt_rescue":
		# Rescue — recruit ally only if they survived the battle
		var ally_survived: bool = bool(battle_result.get("ally_survived", false))
		var ally_tpl: Dictionary = bt.get("ally_leader_template", {}) as Dictionary
		if ally_survived and not ally_tpl.is_empty() and leader != null and state.can_faction_gain_general(int(leader.faction_id), 1):
			var recruit_province_id: int = int(province.id if province != null else mission.province_id)
			var new_leader: LeaderData = state.create_leader_from_template(ally_tpl, recruit_province_id, true)
			if new_leader != null:
				out["rising_general_id"]   = new_leader.id
				out["rising_general_name"] = new_leader.display_name
				DebugLogger.log("event:rescue_general_recruited", {
					"leader_id":   new_leader.id,
					"name":        new_leader.display_name,
					"faction_id":  new_leader.faction_id,
					"province_id": recruit_province_id,
				})
		elif not ally_survived:
			DebugLogger.log("event:rescue_general_lost", {"instance_id": mission.instance_id})
	else:
		# Non-hunt leader recruit (chance-based fallback)
		var leader_recruit: bool = bool(reward.get("leader_recruit", false))
		var recruit_chance: float = float(reward.get("leader_recruit_chance", 0.0))
		if leader_recruit and rng.randf() < recruit_chance:
			if leader != null and state.can_faction_gain_general(int(leader.faction_id), 1):
				var new_leader: LeaderData = _recruit_rising_general(state, leader, int(province.id if province != null else mission.province_id))
				if new_leader != null:
					out["rising_general_id"]   = new_leader.id
					out["rising_general_name"] = new_leader.display_name

	return out


func _apply_loss_penalties(state: GameState, leader: LeaderData) -> Dictionary:
	if leader == null:
		return {}
	# Leader is wounded — unavailable for LOSS_WOUND_TURNS executes
	leader.status = "wounded"
	leader.on_mission = false
	leader.mission_id = ""
	leader.mission_type = ""
	leader.mission_turns_remaining = 0
	leader.wounded_turns_remaining = LOSS_WOUND_TURNS
	return { "wounded": true, "wound_turns": LOSS_WOUND_TURNS }


func _return_leader(state: GameState, leader: LeaderData, return_id: int, province: ProvinceData) -> void:
	leader.on_mission = false
	if str(leader.status) == "on_mission":
		leader.status = "idle"
	leader.mission_id = ""
	leader.mission_type = ""
	leader.mission_turns_remaining = 0
	leader.mission_origin_province_id = -1
	leader.province_id = return_id
	leader.current_province_id = return_id
	if province != null and not province.leader_ids.has(int(leader.id)):
		province.leader_ids.append(int(leader.id))


func _complete_mission(state: GameState, mission: MissionData) -> void:
	mission.phase = "completed"
	var province: ProvinceData = _get_province(state, mission.province_id)
	if province != null:
		province.active_missions.erase(mission.instance_id)
		var cooldown: int = state.rng.randi_range(SLOT_COOLDOWN_MIN, SLOT_COOLDOWN_MAX)
		if mission.slot_index < province.mission_slot_cooldowns.size():
			province.mission_slot_cooldowns[mission.slot_index] = cooldown
		else:
			province.mission_slot_cooldowns.append(cooldown)
	state.active_missions.erase(mission.instance_id)


# --------------------------------------------------
# RISING GENERAL HELPER
# --------------------------------------------------

func _recruit_rising_general(state: GameState, sponsoring_leader: LeaderData, province_id: int) -> LeaderData:
	var new_leader: LeaderData = null
	var faction_id: int = int(sponsoring_leader.faction_id)

	if not state.dismissed_general_pool.is_empty():
		new_leader = state.claim_dismissed_general(faction_id, province_id)
	if new_leader == null:
		var tpl: Dictionary = state.claim_reserve_general_template(faction_id, province_id)
		if not tpl.is_empty():
			new_leader = state.create_leader_from_template(tpl, province_id, true)
	if new_leader == null:
		var fallback: Dictionary = {
			"display_name": "Rising General (F%d)" % faction_id,
			"faction_id":   faction_id,
			"province_id":  province_id,
			"leadership":   state.rng.randi_range(7, 9),
			"attack":       state.rng.randi_range(7, 9),
			"defense":      state.rng.randi_range(5, 8),
			"traits":       ["Brave", "Resourceful"],
			"story_id":     "procedural_rising_general",
		}
		new_leader = state.create_leader_from_template(fallback, province_id, true)

	return new_leader


# --------------------------------------------------
# HELPERS
# --------------------------------------------------

func _get_province(state: GameState, province_id: int) -> ProvinceData:
	if province_id < 0 or province_id >= state.map_data.provinces.size():
		return null
	return state.map_data.provinces[province_id] as ProvinceData


func _find_return_province(state: GameState, leader: LeaderData, origin_id: int) -> ProvinceData:
	var origin: ProvinceData = _get_province(state, origin_id)
	if origin != null and int(origin.owner_id) == int(leader.faction_id if leader != null else -1):
		return origin
	# Find any owned province
	for item in state.map_data.provinces:
		var p: ProvinceData = item as ProvinceData
		if p != null and int(p.owner_id) == int(leader.faction_id if leader != null else -1):
			return p
	return origin


func _find_leader(state: GameState, leader_id: int) -> LeaderData:
	for item in state.leaders:
		var l: LeaderData = item as LeaderData
		if l != null and int(l.id) == leader_id:
			return l
	return null


func _find_faction(map_data: MapData, faction_id: int) -> FactionData:
	for item in map_data.factions:
		var f: FactionData = item as FactionData
		if f != null and int(f.id) == faction_id:
			return f
	return null


func _calc_sigil_tier_from_leaders(state: GameState) -> int:
	# Average level of all living story leaders across all factions
	# Lv 1-4  → Tier 1 sigils
	# Lv 5-9  → Tier 2 sigils
	# Lv 10-14 → Tier 3 sigils
	# Lv 15+  → Tier 4 sigils
	if state == null or state.leaders.is_empty():
		return 1
	var total_level: int = 0
	var count: int = 0
	for item in state.leaders:
		var leader = item
		if leader == null:
			continue
		if not bool(leader.is_story_leader):
			continue
		# Only count leaders of living (non-eliminated) factions
		var faction_alive: bool = false
		if state.map_data != null:
			for f_item in state.map_data.factions:
				var f: FactionData = f_item as FactionData
				if f != null and int(f.id) == int(leader.faction_id) and not bool(f.is_eliminated):
					faction_alive = true
					break
		if not faction_alive:
			continue
		total_level += int(leader.level)
		count += 1
	if count == 0:
		return 1
	var avg: float = float(total_level) / float(count)
	if avg >= 15.0:
		return 4
	elif avg >= 10.0:
		return 3
	elif avg >= 5.0:
		return 2
	return 1
