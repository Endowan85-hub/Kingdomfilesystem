extends Resource
class_name GameState

## CONTRACT NOTES (do not remove; append only):
## - GameState is the authoritative simulation state container.
## - Planning Phase: OrderBook is mutated only by UI/planners (queuing).
## - Execution Phase: TurnManager/resolvers mutate GameState on Execute Month.
## - Do not change public API signatures between systems without explicit instruction.
## - Leader mission state now belongs to LeaderData; provinces only store leader ids.
## - Story leaders are injected first, then starting generals are added per faction.
## - Start-of-campaign ownership may intentionally leave many provinces neutral; do not auto-fill neutral provinces with leaders.
## - Base leader stats use a 1-10 scale; final effective values may exceed 10 later.

const LeaderData = preload("res://Scripts/map/leader_data.gd")
const StoryLeaderLibrary = preload("res://Scripts/data/story_leader_library.gd")
const UnitLibrary = preload("res://Scripts/data/unit_library.gd")
const AITuningProfile = preload("res://Scripts/game/tools/ai_tuning_profile.gd")
const CombatTuningProfile = preload("res://Scripts/game/tools/combat_tuning_profile.gd")
const ItemLibraryScript = preload("res://Scripts/data/item_library.gd")

const COMMANDER_CAP_BASE: int = 3
const COMMANDER_CAP_STEP_MONTHS: int = 24
const COMMANDER_CAP_MAX: int = 9


const GENERAL_RELEASE_SCHEDULE := {
	12: 5,
	24: 5,
	36: 10,
	48: 10,
	60: 10,
	72: 15,
	84: 15,
	96: 15,
	108: 10,
	120: 10,
	132: 10
}

const PROCEDURAL_TRAIT_POOL: Array[String] = [
	"Brave",
	"Strategist",
	"Guardian",
	"Mystic",
	"Scout",
	"Greedy",
	"Inspiring"
]

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var logger: DebugLogger = DebugLogger.new()

func _register_logger() -> void:
	Engine.set_meta("kingdom_debug_logger", logger)
	logger.event("logger_registered")

@export var map_data: MapData
@export var month_index: int = 0
@export var rng_seed: int = 0
@export var human_faction_id: int = 0  # set by FactionPicker before init_with_map
@export var order_book: OrderBook
@export var ai_tuning_profile: AITuningProfile
@export var combat_tuning_profile: CombatTuningProfile
@export var reserve_general_pool_by_faction: Dictionary = {}
@export var dismissed_general_pool: Array = []  # global pool of dismissed generals (LeaderData), any faction can recruit

# Authoritative leader registry.
@export var leaders: Array = [] # Array[LeaderData]
@export var pending_leader_xp_events: Array = [] # Array[Dictionary]
@export var pending_mission_results: Array = []  # Array[Dictionary] — populated by MissionResolver each turn

# Active mission instances — keyed by instance_id String → MissionData
# Populated and managed entirely by MissionResolver
var active_missions: Dictionary = {}

# Sigil drop tracker — ensures all sigils in a tier drop before duplicates
# Keyed by tier (int) → Array[String] of sigil IDs already dropped this cycle
var sigils_dropped_by_tier: Dictionary = {}

# Authoritative unit registry.
@export var units: Array = [] # Array[UnitData]
var _next_unit_id: int = 0


func init_with_map(new_map: MapData) -> void:
	map_data = new_map
	_register_logger()
	month_index = 0
	pending_leader_xp_events.clear()
	pending_mission_results.clear()
	active_missions.clear()
	sigils_dropped_by_tier.clear()
	reserve_general_pool_by_faction.clear()
	dismissed_general_pool.clear()
	units.clear()
	_next_unit_id = 0

	if rng_seed == 0:
		rng_seed = int(Time.get_ticks_msec())

	rng.seed = rng_seed
	logger.event("state_init", {"rng_seed": rng_seed})
	if order_book == null:
		order_book = OrderBook.new()
	if ai_tuning_profile == null:
		ai_tuning_profile = AITuningProfile.new()
		ai_tuning_profile.sanitize()
	if combat_tuning_profile == null:
		combat_tuning_profile = CombatTuningProfile.new()
		combat_tuning_profile.sanitize()

	_initialize_leaders()

	var fids: Array[int] = []
	if map_data != null:
		for f in map_data.factions:
			fids.append(int(f.id))
	order_book.clear_all(fids)

	logger.event("session_start", {
		"rng_seed": rng_seed,
		"month": month_index,
		"province_count": map_data.provinces.size() if map_data != null else 0,
		"route_count": map_data.routes.size() if map_data != null else 0,
		"leader_count": leaders.size(),
		"faction_count": map_data.factions.size() if map_data != null else 0
	})





func get_combat_tuning_profile() -> CombatTuningProfile:
	if combat_tuning_profile == null:
		combat_tuning_profile = CombatTuningProfile.new()
		combat_tuning_profile.sanitize()
	return combat_tuning_profile

func get_ai_tuning_profile() -> AITuningProfile:
	if ai_tuning_profile == null:
		ai_tuning_profile = AITuningProfile.new()
		ai_tuning_profile.sanitize()
	if combat_tuning_profile == null:
		combat_tuning_profile = CombatTuningProfile.new()
		combat_tuning_profile.sanitize()
	return ai_tuning_profile

func get_leader(leader_id: int) -> LeaderData:
	if leader_id < 0 or leader_id >= leaders.size():
		return null
	return leaders[leader_id] as LeaderData


func get_province_leaders(province_id: int, include_on_mission: bool = false) -> Array:
	var out: Array = []
	if map_data == null or province_id < 0 or province_id >= map_data.provinces.size():
		return out
	var p: ProvinceData = map_data.provinces[province_id] as ProvinceData
	for lid_value in p.leader_ids:
		var leader: LeaderData = get_leader(int(lid_value))
		if leader == null:
			continue
		if not include_on_mission and (leader.status == "mission" or leader.status == "injured" or bool(leader.on_mission)):
			continue
		out.append(leader)
	return out


func get_first_available_leader_in_province(province_id: int) -> LeaderData:
	var stationed: Array = get_province_leaders(province_id, false)
	if stationed.is_empty():
		return null
	return stationed[0] as LeaderData


func move_leader_to_province(leader_id: int, province_id: int) -> void:
	var leader: LeaderData = get_leader(leader_id)
	if leader == null or map_data == null:
		return

	var old_province_id: int = int(leader.current_province_id)
	if old_province_id >= 0 and old_province_id < map_data.provinces.size():
		var old_p: ProvinceData = map_data.provinces[old_province_id] as ProvinceData
		old_p.leader_ids.erase(leader_id)
		if int(old_p.ruler_leader_id) == leader_id:
			old_p.ruler_leader_id = old_p.leader_ids[0] if not old_p.leader_ids.is_empty() else -1

	leader.current_province_id = province_id
	leader.province_id = province_id

	if province_id >= 0 and province_id < map_data.provinces.size():
		var new_p: ProvinceData = map_data.provinces[province_id] as ProvinceData
		if not new_p.leader_ids.has(leader_id):
			new_p.leader_ids.append(leader_id)
		if int(new_p.ruler_leader_id) == -1:
			new_p.ruler_leader_id = leader_id


# --------------------------------------------------
# Dismiss a general back to the global dismissed pool.
# Rules:
#   - Story leaders cannot be dismissed.
#   - General must have an empty army.
#   - Leader retains full stats/level — any faction can recruit them via mission.
# Returns true on success, false if conditions not met.
# --------------------------------------------------
func dismiss_general(leader_id: int) -> bool:
	var leader: LeaderData = get_leader(leader_id)
	if leader == null:
		return false
	if bool(leader.is_story_leader):
		return false
	for uid in leader.army_unit_ids:
		if int(uid) >= 0:
			return false

	var old_faction_id: int = int(leader.faction_id)
	var old_province_id: int = int(leader.current_province_id)

	# Remove from province
	if old_province_id >= 0 and old_province_id < map_data.provinces.size():
		var prov: ProvinceData = map_data.provinces[old_province_id] as ProvinceData
		if prov != null:
			prov.leader_ids.erase(leader_id)
			if int(prov.ruler_leader_id) == leader_id:
				prov.ruler_leader_id = prov.leader_ids[0] if not prov.leader_ids.is_empty() else -1

	# Remove from faction
	var faction: FactionData = _find_faction(old_faction_id)
	if faction != null:
		faction.leader_ids.erase(leader_id)

	# Park in global dismissed pool — stats/level intact
	leader.faction_id = -1
	leader.current_province_id = -1
	leader.province_id = -1
	leader.status = "idle"
	dismissed_general_pool.append(leader)

	logger.event("general_dismissed", {
		"leader_id": leader_id,
		"name": str(leader.display_name),
		"level": int(leader.level),
		"old_faction_id": old_faction_id,
		"pool_size": dismissed_general_pool.size()
	})
	return true


# Pull the oldest dismissed general from the pool and assign to a faction/province.
# Returns the LeaderData on success, null if pool is empty.
func claim_dismissed_general(faction_id: int, province_id: int) -> LeaderData:
	if dismissed_general_pool.is_empty():
		return null

	# Build set of names already active
	var active_names: Dictionary = {}
	for l in leaders:
		if l != null:
			active_names[str(l.display_name).to_lower()] = true

	# Find first dismissed general not already active
	var chosen_idx: int = -1
	for i in range(dismissed_general_pool.size()):
		var candidate: LeaderData = dismissed_general_pool[i] as LeaderData
		if candidate == null:
			continue
		if not active_names.has(str(candidate.display_name).to_lower()):
			chosen_idx = i
			break

	if chosen_idx < 0:
		return null

	var leader: LeaderData = dismissed_general_pool[chosen_idx] as LeaderData
	dismissed_general_pool.remove_at(chosen_idx)
	leader.faction_id = faction_id
	leader.current_province_id = province_id
	leader.province_id = province_id
	leader.status = "idle"
	leaders.append(leader)
	leader.id = leaders.size() - 1
	_assign_leader_to_faction_and_province(leader)
	logger.event("dismissed_general_recruited", {
		"leader_id": int(leader.id),
		"name": str(leader.display_name),
		"level": int(leader.level),
		"new_faction_id": faction_id,
		"pool_remaining": dismissed_general_pool.size()
	})
	return leader


# ==================================================
# Unit Registry API
# ==================================================

func get_unit(unit_id: int) -> Resource:
	if unit_id < 0 or unit_id >= units.size():
		return null
	return units[unit_id]


func get_leader_used_cp(leader) -> int:
	var total: int = 0
	for uid in leader.army_unit_ids:
		var u = get_unit(int(uid))
		if u != null:
			total += int(u.cp_cost)
	return total


# ==================================================
# Army Assignment (Phase 3)
# ==================================================

func can_attach_unit(leader_id: int, unit_id: int) -> bool:
	var leader = get_leader(leader_id)
	var unit = get_unit(unit_id)
	if leader == null or unit == null:
		return false
	if not leader.has_free_unit_slot():
		return false
	var used_cp: int = get_leader_used_cp(leader)
	if used_cp + int(unit.cp_cost) > int(leader.max_cp):
		return false
	return true


func attach_unit(leader_id: int, unit_id: int) -> bool:
	if not can_attach_unit(leader_id, unit_id):
		return false
	var leader = get_leader(leader_id)
	var unit = get_unit(unit_id)
	leader.add_army_unit(unit_id)
	unit.owner_leader_id = leader_id
	logger.event("unit_attached", {"leader_id": leader_id, "unit_id": unit_id})
	return true


func detach_unit(leader_id: int, unit_id: int) -> bool:
	var leader = get_leader(leader_id)
	var unit = get_unit(unit_id)
	if leader == null or unit == null:
		return false
	if not leader.has_unit(unit_id):
		return false
	leader.remove_army_unit(unit_id)
	unit.owner_leader_id = -1
	logger.event("unit_detached", {"leader_id": leader_id, "unit_id": unit_id})
	return true


# ==================================================
# Province Inventory (Phase 5)
# ==================================================

func get_province_inventory_units(province_id: int) -> Array:
	var out: Array = []
	if map_data == null or province_id < 0 or province_id >= map_data.provinces.size():
		return out
	var p: ProvinceData = map_data.provinces[province_id] as ProvinceData
	for uid in p.unit_inventory:
		var u = get_unit(int(uid))
		if u != null:
			out.append(u)
	return out


func move_unit_to_inventory(unit_id: int, province_id: int) -> bool:
	var unit = get_unit(unit_id)
	if unit == null or province_id < 0 or province_id >= map_data.provinces.size():
		return false
	if int(unit.owner_leader_id) >= 0:
		detach_unit(int(unit.owner_leader_id), unit_id)
	if int(unit.province_id) >= 0 and int(unit.province_id) < map_data.provinces.size():
		var old_p: ProvinceData = map_data.provinces[int(unit.province_id)] as ProvinceData
		old_p.remove_unit_from_inventory(unit_id)
	var new_p: ProvinceData = map_data.provinces[province_id] as ProvinceData
	new_p.add_unit_to_inventory(unit_id)
	unit.province_id = province_id
	logger.event("unit_moved_to_inventory", {"unit_id": unit_id, "province_id": province_id})
	return true


func move_unit_to_leader(unit_id: int, leader_id: int) -> bool:
	var unit = get_unit(unit_id)
	var leader = get_leader(leader_id)
	if unit == null or leader == null:
		return false
	var prov_id: int = int(unit.province_id)
	if prov_id >= 0 and prov_id < map_data.provinces.size():
		var p: ProvinceData = map_data.provinces[prov_id] as ProvinceData
		p.remove_unit_from_inventory(unit_id)
	return attach_unit(leader_id, unit_id)


# ==================================================
# Recruitment (Phase 6)
# Instant during Planning Phase — deducts gold, spawns unit into inventory.
# ==================================================

# Returns the new unit_id on success, or -1 on failure.
func recruit_unit_id(faction_id: int, province_id: int, unit_type: String) -> int:
	var ok: bool = recruit_unit(faction_id, province_id, unit_type)
	if ok:
		return _next_unit_id - 1
	return -1


func recruit_unit(faction_id: int, province_id: int, unit_type: String) -> bool:
	if map_data == null or province_id < 0 or province_id >= map_data.provinces.size():
		logger.event("recruit_failed", {"reason": "invalid_province", "province_id": province_id})
		return false
	var p: ProvinceData = map_data.provinces[province_id] as ProvinceData
	if int(p.owner_id) != faction_id:
		logger.event("recruit_failed", {"reason": "not_owner", "province_id": province_id})
		return false
	if not UnitLibrary.is_valid_type(unit_type):
		logger.event("recruit_failed", {"reason": "invalid_unit_type", "unit_type": unit_type})
		return false
	var gold_cost: int = UnitLibrary.get_gold_cost(unit_type)
	var faction: FactionData = _find_faction(faction_id)
	if faction == null:
		return false
	if int(faction.gold) < gold_cost:
		logger.event("recruit_failed", {"reason": "insufficient_gold", "have": int(faction.gold), "need": gold_cost})
		return false
	faction.gold -= gold_cost
	var new_id: int = _next_unit_id
	_next_unit_id += 1
	var unit = UnitLibrary.create_unit(unit_type, new_id)
	unit.province_id = province_id
	units.append(unit)
	p.add_unit_to_inventory(new_id)
	logger.event("unit_recruited", {
		"unit_id": new_id,
		"unit_type": unit_type,
		"province_id": province_id,
		"faction_id": faction_id,
		"gold_spent": gold_cost,
		"gold_remaining": int(faction.gold)
	})
	return true


# ==================================================
# Active Province Healing
# Instant during Planning Phase — deducts gold and fully heals one unit.
# ==================================================

func get_unit_active_heal_cost(unit_id: int) -> int:
	var unit = get_unit(unit_id)
	if unit == null:
		return -1
	if int(unit.hp) >= int(unit.max_hp):
		return 0
	var tuning: CombatTuningProfile = get_combat_tuning_profile()
	var base_cost: int = 25
	var gold_per_hp: int = 3
	if tuning != null:
		base_cost = int(tuning.active_heal_base_cost)
		gold_per_hp = int(tuning.active_heal_gold_per_hp)
	var missing_hp: int = maxi(0, int(unit.max_hp) - int(unit.hp))
	return base_cost + (missing_hp * gold_per_hp)


func can_active_heal_unit(faction_id: int, unit_id: int, province_id: int = -1) -> bool:
	var unit = get_unit(unit_id)
	if unit == null:
		return false
	if int(unit.hp) >= int(unit.max_hp):
		return false
	var resolved_province_id: int = province_id
	if resolved_province_id < 0:
		resolved_province_id = int(unit.province_id)
		if resolved_province_id < 0 and int(unit.owner_leader_id) >= 0:
			var owner_leader: LeaderData = get_leader(int(unit.owner_leader_id))
			if owner_leader != null:
				resolved_province_id = int(owner_leader.current_province_id)
	if resolved_province_id < 0 or map_data == null or resolved_province_id >= map_data.provinces.size():
		return false
	var province: ProvinceData = map_data.provinces[resolved_province_id] as ProvinceData
	if province == null or int(province.owner_id) != faction_id:
		return false
	var faction: FactionData = _find_faction(faction_id)
	if faction == null:
		return false
	var cost: int = get_unit_active_heal_cost(unit_id)
	if cost <= 0:
		return false
	return int(faction.gold) >= cost


func active_heal_unit(faction_id: int, unit_id: int, province_id: int = -1) -> bool:
	if not can_active_heal_unit(faction_id, unit_id, province_id):
		logger.event("active_heal_failed", {"faction_id": faction_id, "unit_id": unit_id, "province_id": province_id})
		return false
	var unit = get_unit(unit_id)
	var resolved_province_id: int = province_id
	if resolved_province_id < 0:
		resolved_province_id = int(unit.province_id)
		if resolved_province_id < 0 and int(unit.owner_leader_id) >= 0:
			var owner_leader: LeaderData = get_leader(int(unit.owner_leader_id))
			if owner_leader != null:
				resolved_province_id = int(owner_leader.current_province_id)
	var faction: FactionData = _find_faction(faction_id)
	if faction == null:
		return false
	var cost: int = get_unit_active_heal_cost(unit_id)
	faction.gold -= cost
	var before_hp: int = int(unit.hp)
	unit.hp = int(unit.max_hp)
	logger.event("unit_active_healed", {
		"faction_id": faction_id,
		"province_id": resolved_province_id,
		"unit_id": unit_id,
		"unit_type": str(unit.unit_type),
		"hp_before": before_hp,
		"hp_after": int(unit.hp),
		"gold_spent": cost,
		"gold_remaining": int(faction.gold)
	})
	return true


# ==================================================
# Leader Initialization (internal)
# ==================================================

func _initialize_leaders() -> void:
	leaders.clear()
	reserve_general_pool_by_faction.clear()
	if map_data == null:
		return

	for item_f in map_data.factions:
		var faction: FactionData = item_f as FactionData
		faction.leader_ids = []

	for item_p in map_data.provinces:
		var province: ProvinceData = item_p as ProvinceData
		province.leader_ids = []
		province.ruler_leader_id = -1

	var created_per_faction: Dictionary = {}

	# --------------------------------------------------
	# Pre-seed: guarantee the player's story leader lands on the chosen faction
	# before the story template loop and procedural fill run.
	# --------------------------------------------------
	var player_faction_pre: FactionData = _find_faction(human_faction_id)
	if player_faction_pre != null and not player_faction_pre.provinces.is_empty():
		var player_pid: int = int(player_faction_pre.provinces[0])
		var player_fkey: String = str(player_faction_pre.faction_key)
		var unifier_base: Dictionary = {}
		for base in StoryLeaderLibrary.STORY_ROSTER:
			if str(base.get("faction_key", "")) == player_fkey:
				unifier_base = base.duplicate(true)
				break
		if not unifier_base.is_empty():
			unifier_base["faction_id"] = human_faction_id
			unifier_base["province_id"] = player_pid
			var unifier: LeaderData = create_leader_from_template(unifier_base, player_pid, false)
			if unifier != null:
				unifier.is_story_leader = true
				unifier.story_id = player_fkey
				unifier.upkeep_cost = 0
				if player_fkey != "":
					unifier.signature_ability_id = player_fkey
				leaders.append(unifier)
				_assign_leader_to_faction_and_province(unifier)
				created_per_faction[human_faction_id] = 1

	var story_templates: Array = _get_story_leader_templates()
	for tpl_value in story_templates:
		var tpl: Dictionary = tpl_value as Dictionary
		# Skip player faction — already pre-seeded above
		if str(tpl.get("story_id", "")) == str(player_faction_pre.faction_key if player_faction_pre != null else ""):
			continue
		var story_leader: LeaderData = create_leader_from_template(tpl, int(tpl.get("province_id", -1)), false)
		if story_leader == null:
			continue
		story_leader.is_story_leader = true
		story_leader.story_id = str(tpl.get("story_id", ""))
		story_leader.upkeep_cost = 0
		# Set signature ability — story_id matches leader_id in SIGNATURE_ABILITIES
		if story_leader.story_id != "":
			story_leader.signature_ability_id = story_leader.story_id
		leaders.append(story_leader)
		_assign_leader_to_faction_and_province(story_leader)
		var faction_id: int = int(story_leader.faction_id)
		created_per_faction[faction_id] = int(created_per_faction.get(faction_id, 0)) + 1

	for item in map_data.provinces:
		var p: ProvinceData = item as ProvinceData
		var owner_id: int = int(p.owner_id)
		if owner_id < 0:
			continue
		if not p.leader_ids.is_empty():
			continue
		var leader := LeaderData.new()
		leader.id = leaders.size()
		leader.display_name = _make_procedural_leader_name(owner_id, int(p.id), int(created_per_faction.get(owner_id, 0)))
		leader.faction_id = owner_id
		leader.home_province_id = int(p.id)
		leader.current_province_id = int(p.id)
		_roll_procedural_leader_stats(leader)
		leaders.append(leader)
		_assign_leader_to_faction_and_province(leader)
		created_per_faction[owner_id] = int(created_per_faction.get(owner_id, 0)) + 1

	var starting_extra_count: int = _get_starting_extra_generals_per_faction()
	if starting_extra_count > 0:
		var extra_templates: Array = StoryLeaderLibrary.build_starting_extra_general_templates(map_data, starting_extra_count)
		for tpl_value in extra_templates:
			var tpl: Dictionary = tpl_value as Dictionary
			var province_id: int = _pick_extra_general_spawn_province(int(tpl.get("faction_id", -1)), int(tpl.get("province_id", -1)))
			var reserve_leader: LeaderData = create_leader_from_template(tpl, province_id, false)
			if reserve_leader == null:
				continue
			reserve_leader.story_id = str(tpl.get("story_id", ""))
			leaders.append(reserve_leader)
			_assign_leader_to_faction_and_province(reserve_leader)
			var rfaction_id: int = int(reserve_leader.faction_id)
			created_per_faction[rfaction_id] = int(created_per_faction.get(rfaction_id, 0)) + 1

	reserve_general_pool_by_faction = StoryLeaderLibrary.build_mission_general_pool(map_data, StoryLeaderLibrary.EXTRA_GENERAL_TARGET)
	logger.event("leaders_initialized", created_per_faction)
	logger.event("reserve_general_pool_initialized", {"factions": reserve_general_pool_by_faction.size(), "starting_extra_per_faction": starting_extra_count})


func _ensure_player_story_leader() -> void:
	# Guarantee the player faction (id=0, house_counsel) has The Unifier
	# in one of their owned provinces. If she ended up on another faction
	# due to the fallback in build_templates, reassign her.
	var player_faction: FactionData = _find_faction(0)
	if player_faction == null:
		return

	# Find The Unifier (story_id == "house_counsel")
	var story_leader: LeaderData = null
	for item in leaders:
		var l: LeaderData = item as LeaderData
		if l != null and str(l.story_id) == "house_counsel":
			story_leader = l
			break
	if story_leader == null:
		return

	# Already on the right faction — nothing to do
	if int(story_leader.faction_id) == 0:
		return

	# Remove from wrong faction
	var old_faction: FactionData = _find_faction(int(story_leader.faction_id))
	if old_faction != null:
		old_faction.leader_ids.erase(int(story_leader.id))

	# Remove from wrong province
	if map_data != null and int(story_leader.current_province_id) >= 0:
		var old_p: ProvinceData = map_data.provinces[int(story_leader.current_province_id)] as ProvinceData
		if old_p != null:
			old_p.leader_ids.erase(int(story_leader.id))

	# Pick first owned province for player
	var target_pid: int = -1
	if not player_faction.provinces.is_empty():
		target_pid = int(player_faction.provinces[0])
	if target_pid < 0:
		return

	story_leader.faction_id = 0
	story_leader.home_province_id = target_pid
	story_leader.current_province_id = target_pid
	story_leader.province_id = target_pid
	_assign_leader_to_faction_and_province(story_leader)
	logger.event("player_story_leader_reassigned", {"leader": story_leader.display_name, "province": target_pid})


func _assign_leader_to_faction_and_province(leader: LeaderData) -> void:
	var faction: FactionData = _find_faction(int(leader.faction_id))
	if faction != null and not faction.leader_ids.has(int(leader.id)):
		faction.leader_ids.append(int(leader.id))
	move_leader_to_province(int(leader.id), int(leader.current_province_id))


# Public wrapper so external resolvers (campaign_event_resolver, etc.)
# can place a leader into a faction+province without calling private methods.
func assign_leader_to_faction_and_province(leader: LeaderData) -> void:
	_assign_leader_to_faction_and_province(leader)


func _find_faction(faction_id: int) -> FactionData:
	if map_data == null:
		return null
	for item in map_data.factions:
		var f: FactionData = item as FactionData
		if int(f.id) == faction_id:
			return f
	return null


func create_leader_from_template(tpl: Dictionary, province_id_override: int = -1, auto_assign: bool = false) -> LeaderData:
	if map_data == null or tpl.is_empty():
		return null
	var faction_id: int = int(tpl.get("faction_id", -1))
	var province_id: int = province_id_override if province_id_override >= 0 else int(tpl.get("province_id", -1))
	if faction_id < 0 or province_id < 0 or province_id >= map_data.provinces.size():
		return null
	var leader := LeaderData.new()
	leader.id = leaders.size() if not auto_assign else leaders.size()
	leader.display_name = str(tpl.get("display_name", "Leader"))
	leader.name = leader.display_name
	leader.faction_id = faction_id
	leader.home_province_id = province_id
	leader.current_province_id = province_id
	leader.province_id = province_id
	leader.is_story_leader = bool(tpl.get("is_story_leader", false))
	leader.story_id = str(tpl.get("story_id", ""))
	# Assign signature ability — story_id matches leader_id in SIGNATURE_ABILITIES
	if leader.is_story_leader and leader.story_id != "":
		if leader.get("signature_ability_id") != null:
			leader.set("signature_ability_id", leader.story_id)
	leader.leadership = clampi(int(tpl.get("leadership", 6)), 1, 10)
	leader.attack = clampi(int(tpl.get("attack", 6)), 1, 10)
	leader.defense = clampi(int(tpl.get("defense", 6)), 1, 10)
	leader.traits = _normalize_traits(tpl.get("traits", []))
	if leader.get("damage_type") != null:
		leader.set("damage_type", str(tpl.get("damage_type", "slash")))
	if leader.get("speed") != null:
		leader.set("speed", int(tpl.get("speed", 4)))
	if leader.get("accuracy") != null:
		leader.set("accuracy", int(tpl.get("accuracy", 72)))
	if leader.get("evasion") != null:
		leader.set("evasion", int(tpl.get("evasion", 10)))
	if leader.get("unit_archetype") != null:
		leader.set("unit_archetype", str(tpl.get("unit_archetype", "")))
	if auto_assign:
		leaders.append(leader)
		leader.id = leaders.size() - 1
		_assign_leader_to_faction_and_province(leader)
	return leader


func get_target_general_count(month: int = -1) -> int:
	var month_value: int = month
	if month_value < 0:
		month_value = int(month_index)
	var target: int = COMMANDER_CAP_BASE + int(floor(float(month_value) / float(COMMANDER_CAP_STEP_MONTHS)))
	return clampi(target, COMMANDER_CAP_BASE, COMMANDER_CAP_MAX)


func get_faction_general_count(faction_id: int) -> int:
	var faction: FactionData = _find_faction(faction_id)
	if faction == null:
		return 0
	var total: int = 0
	for lid_value in faction.leader_ids:
		var leader: LeaderData = get_leader(int(lid_value))
		if leader == null:
			continue
		if int(leader.faction_id) != faction_id:
			continue
		total += 1
	return total


func can_faction_gain_general(faction_id: int, allowance: int = 0) -> bool:
	var current: int = get_faction_general_count(faction_id)
	var target: int = get_target_general_count() + maxi(0, allowance)
	return current < target


func claim_reserve_general_template(faction_id: int, province_id: int) -> Dictionary:
	if not reserve_general_pool_by_faction.has(faction_id):
		return {}
	var pool: Array = reserve_general_pool_by_faction.get(faction_id, []) as Array
	if pool.is_empty():
		return {}

	# Build set of names already active in the game (any faction)
	var active_names: Dictionary = {}
	for l in leaders:
		if l != null:
			active_names[str(l.display_name).to_lower()] = true

	# Build list of all valid (non-active) indices, then pick randomly
	var valid_indices: Array = []
	for i in range(pool.size()):
		var candidate: Dictionary = pool[i] as Dictionary
		var cname: String = str(candidate.get("display_name", "")).to_lower()
		if not active_names.has(cname):
			valid_indices.append(i)

	if valid_indices.is_empty():
		return {}  # All pool entries are already active

	var chosen_idx: int = valid_indices[rng.randi_range(0, valid_indices.size() - 1)]

	var tpl: Dictionary = (pool[chosen_idx] as Dictionary).duplicate(true)
	pool.remove_at(chosen_idx)
	tpl["province_id"] = province_id
	reserve_general_pool_by_faction[faction_id] = pool
	logger.event("reserve_general_claimed", {"faction_id": faction_id, "remaining": pool.size(), "province_id": province_id, "name": str(tpl.get("display_name", "Reserve General"))})
	return tpl


func _get_starting_extra_generals_per_faction() -> int:
	var profile: AITuningProfile = get_ai_tuning_profile()
	if profile == null:
		return 1
	return maxi(1, int(profile.starting_extra_generals_per_faction))


func _pick_extra_general_spawn_province(faction_id: int, suggested_province_id: int) -> int:
	if map_data == null:
		return suggested_province_id
	var best_pid: int = suggested_province_id
	var best_score: float = -INF
	for item in map_data.provinces:
		var p: ProvinceData = item as ProvinceData
		if p == null or int(p.owner_id) != faction_id:
			continue
		var score: float = 0.0
		var is_border: bool = false
		var neighbors: Array = []
		if map_data.adjacency.has(int(p.id)):
			neighbors = map_data.adjacency.get(int(p.id), []) as Array
		else:
			for route_item in map_data.routes:
				var route: RouteData = route_item as RouteData
				if route == null:
					continue
				if int(route.a) == int(p.id):
					neighbors.append(int(route.b))
				elif int(route.b) == int(p.id):
					neighbors.append(int(route.a))
		for other_id_variant in neighbors:
			var other_id: int = int(other_id_variant)
			if other_id < 0 or other_id >= map_data.provinces.size():
				continue
			var other: ProvinceData = map_data.provinces[other_id] as ProvinceData
			if other != null and int(other.owner_id) != faction_id:
				is_border = true
				break
		if is_border:
			score += 10.0
		score += float(int(p.fort_level)) * 2.0
		score -= float((p.leader_ids as Array).size()) * 1.5
		if int(p.id) == suggested_province_id:
			score += 1.0
		if score > best_score:
			best_score = score
			best_pid = int(p.id)
	return best_pid


func _get_story_leader_templates() -> Array:
	return StoryLeaderLibrary.build_templates(map_data)


func _make_procedural_leader_name(faction_id: int, province_id: int, ordinal: int) -> String:
	return "F%d Leader %02d (P%d)" % [faction_id, ordinal + 1, province_id]


func _roll_procedural_leader_stats(leader: LeaderData) -> void:
	leader.leadership = _roll_stat()
	leader.attack = _roll_stat()
	leader.defense = _roll_stat()
	leader.traits = _roll_procedural_traits()


func _roll_stat() -> int:
	var a: int = rng.randi_range(1, 10)
	var b: int = rng.randi_range(1, 10)
	return clampi(int(round((float(a + b) / 2.0))), 1, 10)


func _roll_procedural_traits() -> Array[String]:
	var pool: Array[String] = PROCEDURAL_TRAIT_POOL.duplicate()
	var count_roll: float = rng.randf()
	var desired_count: int = 0
	if count_roll >= 0.35 and count_roll < 0.80:
		desired_count = 1
	elif count_roll >= 0.80:
		desired_count = 2

	var out: Array[String] = []
	for _i in desired_count:
		if pool.is_empty():
			break
		var idx: int = rng.randi_range(0, pool.size() - 1)
		out.append(pool[idx])
		pool.remove_at(idx)
	return out


func _normalize_traits(raw_value) -> Array[String]:
	var out: Array[String] = []
	if raw_value is Array:
		for item in raw_value:
			var s: String = str(item).strip_edges()
			if s == "":
				continue
			if not out.has(s):
				out.append(s)
	return out


# ==================================================
# Promotion
# ==================================================

const PROMOTION_LEVEL_THRESHOLDS: Dictionary = { 1: 5, 2: 10 }

func promote_unit(faction_id: int, unit_id: int) -> bool:
	var unit = get_unit(unit_id)
	if unit == null:
		logger.event("promote_failed", {"reason": "unit_not_found", "unit_id": unit_id})
		return false

	var promotes_to: String = UnitLibrary.get_promotion(str(unit.unit_type))
	if promotes_to == "":
		logger.event("promote_failed", {"reason": "no_promotion_path", "unit_type": unit.unit_type})
		return false

	# Level threshold: tier 1 needs level 5, tier 2 needs level 10
	var current_tier: int = int(unit.tier)
	var required_level: int = PROMOTION_LEVEL_THRESHOLDS.get(current_tier, 999)
	if int(unit.level) < required_level:
		logger.event("promote_failed", {"reason": "level_too_low", "unit_id": unit_id, "level": int(unit.level), "required": required_level})
		return false

	var tpl: Dictionary = UnitLibrary.get_template(promotes_to)
	if tpl.is_empty():
		logger.event("promote_failed", {"reason": "template_not_found", "promotes_to": promotes_to})
		return false

	var cost: int = int(tpl.get("gold_cost", 0))
	var faction: FactionData = _find_faction(faction_id)
	if faction == null:
		return false
	if int(faction.gold) < cost:
		logger.event("promote_failed", {"reason": "insufficient_gold", "have": int(faction.gold), "need": cost})
		return false

	var old_type: String = str(unit.unit_type)
	faction.gold -= cost
	unit.unit_type = promotes_to
	unit.tier = int(tpl.get("tier", unit.tier))
	unit.cp_cost = int(tpl.get("cp_cost", unit.cp_cost))
	unit.upkeep_cost = int(tpl.get("upkeep_cost", unit.upkeep_cost))
	unit.attack = int(tpl.get("attack", unit.attack))
	unit.defense = int(tpl.get("defense", unit.defense))
	var new_max_hp: int = int(tpl.get("hp", unit.max_hp))
	var hp_diff: int = new_max_hp - int(unit.max_hp)
	unit.max_hp = new_max_hp
	unit.hp = mini(int(unit.hp) + hp_diff, new_max_hp)
	unit.skills = UnitLibrary._copy_string_array(tpl.get("skills", []))
	unit.traits = UnitLibrary._copy_string_array(tpl.get("traits", []))

	logger.event("unit_promoted", {
		"unit_id": unit_id,
		"from": old_type,
		"to": promotes_to,
		"faction_id": faction_id,
		"gold_spent": cost,
		"gold_remaining": int(faction.gold)
	})
	return true


func release_generals_for_month(month:int) -> void:
	if not GENERAL_RELEASE_SCHEDULE.has(month):
		return
	var count:int = GENERAL_RELEASE_SCHEDULE[month]
	for i in count:
		var leader := LeaderData.new()
		leader.display_name = "Wandering Commander %d" % randi()
		leader.attack = rng.randi_range(3,8)
		leader.defense = rng.randi_range(3,8)
		leader.leadership = rng.randi_range(4,8)
		dismissed_general_pool.append(leader)
	logger.event("generals_released", {"month":month,"count":count,"pool_size":dismissed_general_pool.size()})

# ==================================================
# ITEM SYSTEM API
# --------------------------------------------------
# All item mutations go through these functions.
# UI queues orders; these execute immediately for local province logistics.
# ==================================================

# Equip an item from a province inventory to a unit in the same province.
# Returns true on success. HP items update current_hp as well.
func equip_item_to_unit(unit_id: int, item_id: String, province_id: int) -> bool:
	var unit: UnitData = get_unit(unit_id) as UnitData
	if unit == null:
		return false
	if int(unit.province_id) != province_id:
		if logger != null:
			logger.event("equip_failed", {"reason": "unit_not_in_province", "unit_id": unit_id, "province_id": province_id})
		return false
	if map_data == null or province_id < 0 or province_id >= map_data.provinces.size():
		return false
	var province: ProvinceData = map_data.provinces[province_id] as ProvinceData
	if province == null:
		return false
	if not province.has_item(item_id):
		return false
	# If unit already has an item, unequip it first (returns to province)
	if str(unit.equipped_item_id) != "":
		_unequip_item_internal(unit, province)
	# Remove from province inventory
	province.remove_item(item_id, 1)
	unit.equipped_item_id = item_id
	# Apply HP bonus immediately if hp item
	var bonuses: Dictionary = ItemLibraryScript.get_unit_item_bonuses(item_id)
	var hp_bonus: int = int(bonuses.get("max_hp", 0))
	if hp_bonus > 0:
		unit.max_hp = int(unit.max_hp) + hp_bonus
		unit.hp = mini(int(unit.hp) + hp_bonus, int(unit.max_hp))
	if logger != null:
		logger.event("item_equipped", {"unit_id": unit_id, "item_id": item_id, "province_id": province_id})
	return true


# Remove an equipped item from a unit back to its province inventory.
func unequip_item_from_unit(unit_id: int) -> bool:
	var unit: UnitData = get_unit(unit_id) as UnitData
	if unit == null or str(unit.equipped_item_id) == "":
		return false
	if map_data == null or int(unit.province_id) < 0:
		return false
	var province: ProvinceData = map_data.provinces[int(unit.province_id)] as ProvinceData
	if province == null:
		return false
	_unequip_item_internal(unit, province)
	if logger != null:
		logger.event("item_unequipped", {"unit_id": unit_id, "province_id": int(unit.province_id)})
	return true


# Internal: strip item from unit and return to province. Reverses HP bonus.
func _unequip_item_internal(unit: UnitData, province: ProvinceData) -> void:
	var item_id: String = str(unit.equipped_item_id)
	var bonuses: Dictionary = ItemLibraryScript.get_unit_item_bonuses(item_id)
	var hp_bonus: int = int(bonuses.get("max_hp", 0))
	if hp_bonus > 0:
		unit.max_hp = maxi(1, int(unit.max_hp) - hp_bonus)
		unit.hp = mini(int(unit.hp), int(unit.max_hp))
	unit.equipped_item_id = ""
	province.add_item(item_id, 1)


# Sell an item from a province inventory. Returns gold gained (0 on failure).
func sell_item_from_province(province_id: int, item_id: String, faction_id: int) -> int:
	if map_data == null or province_id < 0 or province_id >= map_data.provinces.size():
		return 0
	var province: ProvinceData = map_data.provinces[province_id] as ProvinceData
	if province == null or not province.has_item(item_id):
		return 0
	var faction: FactionData = null
	for f in map_data.factions:
		if int((f as FactionData).id) == faction_id:
			faction = f as FactionData
			break
	if faction == null:
		return 0
	var gold: int = ItemLibraryScript.get_sell_value(item_id)
	province.remove_item(item_id, 1)
	faction.gold = int(faction.gold) + gold
	if logger != null:
		logger.event("item_sold", {"province_id": province_id, "item_id": item_id, "gold": gold, "faction_id": faction_id})
	return gold


# Buy a consumable from the store into a province inventory.
func buy_item_for_province(province_id: int, item_id: String, faction_id: int) -> bool:
	if map_data == null or province_id < 0 or province_id >= map_data.provinces.size():
		return false
	var province: ProvinceData = map_data.provinces[province_id] as ProvinceData
	if province == null:
		return false
	# Only consumables are purchasable in V1
	if not ItemLibraryScript.is_consumable(item_id):
		return false
	var cost: int = ItemLibraryScript.get_buy_value(item_id)
	if cost <= 0:
		return false
	var faction: FactionData = null
	for f in map_data.factions:
		if int((f as FactionData).id) == faction_id:
			faction = f as FactionData
			break
	if faction == null or int(faction.gold) < cost:
		return false
	faction.gold = int(faction.gold) - cost
	province.add_item(item_id, 1)
	if logger != null:
		logger.event("item_purchased", {"province_id": province_id, "item_id": item_id, "cost": cost, "faction_id": faction_id})
	return true


# Transfer an item from a dead unit to a destination province (called by CombatResolver).
# Clears the unit's equipped_item_id.
func transfer_item_from_dead_unit(unit_id: int, destination_province_id: int) -> void:
	var unit: UnitData = get_unit(unit_id) as UnitData
	if unit == null or str(unit.equipped_item_id) == "":
		return
	if map_data == null or destination_province_id < 0 or destination_province_id >= map_data.provinces.size():
		return
	var item_id: String = str(unit.equipped_item_id)
	var province: ProvinceData = map_data.provinces[destination_province_id] as ProvinceData
	if province != null:
		province.add_item(item_id, 1)
	unit.equipped_item_id = ""
	if logger != null:
		logger.event("item_transferred_from_death", {"unit_id": unit_id, "item_id": item_id, "destination": destination_province_id})


# Add a mission item reward directly to a province inventory.
func award_item_to_province(province_id: int, item_id: String) -> void:
	if map_data == null or province_id < 0 or province_id >= map_data.provinces.size():
		return
	if not ItemLibraryScript.is_valid_id(item_id):
		return
	var province: ProvinceData = map_data.provinces[province_id] as ProvinceData
	if province != null:
		province.add_item(item_id, 1)
		if logger != null:
			logger.event("item_awarded", {"province_id": province_id, "item_id": item_id})
