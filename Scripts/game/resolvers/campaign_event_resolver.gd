# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: CampaignEventResolver
#
# Role:
# Fires timed world events that inject free generals into factions
# as the campaign progresses. Ensures every faction can scale its
# leader count with its territory without depending solely on
# missions (which are blocked in crisis) or the dismissed pool.
#
# Allowed Interactions:
# - GameState (read province/faction/leader data, write leaders)
# - FactionData (read provinces/leaders, write meta)
# - DebugLogger
#
# Forbidden Responsibilities:
# - Must not queue orders
# - Must not modify UI
# - Must not run combat or economy logic
#
# Game Phase:
# Execution Phase — called from TurnManager after ownership resolver
#
# Design:
# Events fire every INJECT_INTERVAL months for every living faction.
# A faction receives a free general when:
#   1. It is alive (not eliminated)
#   2. It owns at least one province
# Every living faction receives exactly one general per interval — no
# conditions, no stretch checks. Simple and balanced.
# The general is pulled from reserve_general_pool_by_faction first,
# then dismissed_general_pool, then a procedurally generated fallback.
# The human faction receives a narrative popup message via event log.
# ==================================================

class_name CampaignEventResolver
extends RefCounted

# How often the resolver checks each faction (every N months)
const INJECT_INTERVAL: int = 12

# Flavor text pool — picked randomly for the human faction popup
const FLAVOR_LINES: Array = [
	"A wandering stranger arrives at your gates, sword in hand and oath on his lips.",
	"Word of your growing realm draws a veteran commander from distant lands.",
	"A knight errant seeks to pledge his blade to a worthy cause — yours.",
	"A seasoned warrior, tired of wandering, offers his service to your banner.",
	"An old soldier who once fought for fallen houses asks to serve under your colors.",
	"Rumors of your campaigns have reached far ears. A general rides in, alone, at dusk.",
	"A former mercenary captain, impressed by your victories, swears fealty.",
	"A young noble with fire in his eyes and steel in his veins joins your court.",
	"The roads bring unexpected fortune — a commander of some renown seeks employment.",
	"From the borderlands comes a rider bearing no colors but his own ambition.",
]


func resolve(state: GameState) -> void:
	if state == null or state.map_data == null:
		return

	var month: int = int(state.month_index)

	# Only fire on interval months
	if month % INJECT_INTERVAL != 0:
		return

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(state.rng_seed) ^ (month * 7919)

	for item in state.map_data.factions:
		var faction: FactionData = item as FactionData
		if faction == null:
			continue
		if bool(faction.is_eliminated):
			continue
		var province_count: int = int((faction.provinces as Array).size())
		if province_count == 0:
			continue

		# All living factions receive one general every 12 months, no conditions



		# Find the best province to place the new leader
		var target_pid: int = _find_best_province(state, faction)
		if target_pid < 0:
			continue

		# Acquire the new leader
		var new_leader: LeaderData = _acquire_leader(state, faction, target_pid, rng)
		if new_leader == null:
			continue

		DebugLogger.log("campaign_event_general_injected", {
			"faction": int(faction.id),
			"faction_name": str(faction.display_name),
			"leader_name": str(new_leader.display_name),
			"province": target_pid,
			"month": month,
			"province_count": province_count,
			"leader_count": int((faction.leader_ids as Array).size()),
		})

		# Queue a world event message for the human player
		_queue_world_event(state, faction, new_leader, target_pid, rng, month)


# --------------------------------------------------
# Find the most suitable province for the new leader.
# Prefer: empty frontier > empty interior > least crowded frontier
# --------------------------------------------------
func _find_best_province(state: GameState, faction: FactionData) -> int:
	var owned: Array = faction.provinces as Array
	if owned.is_empty():
		return -1

	# Pass 1: empty frontier province
	for pid_val in owned:
		var pid: int = int(pid_val)
		var p: ProvinceData = state.map_data.provinces[pid] as ProvinceData
		if p == null:
			continue
		if not p.leader_ids.is_empty():
			continue
		if _is_frontier(state, pid, int(faction.id)):
			return pid

	# Pass 2: any empty province
	for pid_val in owned:
		var pid: int = int(pid_val)
		var p: ProvinceData = state.map_data.provinces[pid] as ProvinceData
		if p == null:
			continue
		if p.leader_ids.is_empty():
			return pid

	# Pass 3: frontier province with fewest leaders
	var best_pid: int = -1
	var best_count: int = 999
	for pid_val in owned:
		var pid: int = int(pid_val)
		var p: ProvinceData = state.map_data.provinces[pid] as ProvinceData
		if p == null:
			continue
		if _is_frontier(state, pid, int(faction.id)) and p.leader_ids.size() < best_count:
			best_count = p.leader_ids.size()
			best_pid = pid

	return best_pid


# --------------------------------------------------
# Try to get a leader from: reserve pool → dismissed pool → generated
# --------------------------------------------------
func _acquire_leader(state: GameState, faction: FactionData,
		target_pid: int, rng: RandomNumberGenerator) -> LeaderData:

	var fid: int = int(faction.id)

	# 1. Reserve pool — stored as templates (Dictionaries), use the public API
	var tpl: Dictionary = state.claim_reserve_general_template(fid, target_pid)
	if not tpl.is_empty():
		var leader: LeaderData = state.create_leader_from_template(tpl, target_pid, true)
		if leader != null:
			return leader

	# 2. Dismissed general pool (experienced, any faction)
	if not (state.dismissed_general_pool as Array).is_empty():
		return state.claim_dismissed_general(fid, target_pid)

	# 3. Procedural fallback — generate a basic general
	return _generate_fallback_leader(state, faction, target_pid, rng)


func _assign_leader(state: GameState, leader: LeaderData,
		faction_id: int, province_id: int) -> LeaderData:
	leader.faction_id = faction_id
	leader.current_province_id = province_id
	leader.province_id = province_id
	leader.status = "idle"
	state.leaders.append(leader)
	leader.id = state.leaders.size() - 1
	state.assign_leader_to_faction_and_province(leader)
	return leader


func _generate_fallback_leader(state: GameState, faction: FactionData,
		province_id: int, rng: RandomNumberGenerator) -> LeaderData:
	# Create a modest procedural general — level 1, decent but not great stats
	var leader: LeaderData = LeaderData.new()
	leader.display_name  = _random_name(rng)
	leader.faction_id    = int(faction.id)
	leader.current_province_id = province_id
	leader.province_id   = province_id
	leader.status        = "idle"
	leader.is_story_leader = false
	leader.upkeep_cost   = 30  # standard procedural general cost
	leader.level         = 1
	# Stats in the mid range — enough to lead a small army
	leader.leadership    = rng.randi_range(4, 7)
	leader.attack        = rng.randi_range(3, 6)
	leader.defense       = rng.randi_range(3, 6)
	leader.magic         = rng.randi_range(2, 5)
	leader.max_cp        = 20
	leader.max_unit_slots = 4
	state.leaders.append(leader)
	leader.id = state.leaders.size() - 1
	state.assign_leader_to_faction_and_province(leader)
	return leader


# --------------------------------------------------
# Queue a world event message in GameState for the map view to display
# --------------------------------------------------
func _queue_world_event(state: GameState, faction: FactionData,
		leader: LeaderData, province_id: int,
		rng: RandomNumberGenerator, month: int) -> void:
	var flavor: String = FLAVOR_LINES[rng.randi() % FLAVOR_LINES.size()]
	var province_name: String = "Province %d" % province_id
	var p: ProvinceData = state.map_data.provinces[province_id] as ProvinceData
	if p != null and str(p.display_name) != "":
		province_name = str(p.display_name)
	var event: Dictionary = {
		"type":         "general_arrival",
		"month":        month,
		"faction_id":   int(faction.id),
		"leader_name":  str(leader.display_name),
		"province":     province_name,
		"flavor":       flavor,
		"headline":     "%s joins your banner." % str(leader.display_name),
	}
	# Store in GameState world event queue — map_debug_view polls this
	if state.has_method("queue_world_event"):
		state.queue_world_event(event)
	else:
		# Fallback: just log it
		DebugLogger.log("world_event_general_arrival", event)


# --------------------------------------------------
# Helpers
# --------------------------------------------------
func _is_frontier(state: GameState, province_id: int, faction_id: int) -> bool:
	if state.map_data == null:
		return false
	for route_item in state.map_data.routes:
		var r: RouteData = route_item as RouteData
		if r == null:
			continue
		var other: int = -1
		if int(r.a) == province_id:
			other = int(r.b)
		elif int(r.b) == province_id:
			other = int(r.a)
		else:
			continue
		if other < 0 or other >= state.map_data.provinces.size():
			continue
		var adj: ProvinceData = state.map_data.provinces[other] as ProvinceData
		if adj != null and int(adj.owner_id) != faction_id:
			return true
	return false


func _random_name(rng: RandomNumberGenerator) -> String:
	const FIRST: Array = [
		"Aldric", "Brennan", "Cassian", "Dorian", "Edric", "Faelen", "Gareth",
		"Hadwin", "Idris", "Jareth", "Kaelan", "Loric", "Maren", "Nolan",
		"Oryn", "Phelan", "Quen", "Rowan", "Seren", "Tomas", "Ulric",
		"Varen", "Wulfric", "Xander", "Yoren", "Zephyr",
	]
	const LAST: Array = [
		"Ashford", "Blackwood", "Crane", "Dunmore", "Everly", "Falk",
		"Greystone", "Hartwell", "Ironside", "Jarvis", "Keane", "Langford",
		"Marsh", "Nighthollow", "Oakhurst", "Peregrine", "Quill", "Ravenswood",
		"Steele", "Thorn", "Underhill", "Vale", "Warden", "Crossfield",
	]
	return "%s %s" % [FIRST[rng.randi() % FIRST.size()], LAST[rng.randi() % LAST.size()]]
