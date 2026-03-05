class_name TurnManager
extends RefCounted
## Orchestrates the month execution by delegating to AI + resolvers.
## Public API expected by MapDebugView:
##   execute_month(state, human_id, ai_id, run_ai)

# -----------------------------
# Balance knobs (tweak later)
# -----------------------------
const FORT_BASE_COST: int = 200
const FORT_DEF_PER_LEVEL: int = 25
const FORT_CAP_PER_LEVEL: int = 60

const CHOKE_DEF_BONUS: int = 35

const ATTACK_BASE_LOSS_MIN: int = 10
const ATTACK_BASE_LOSS_MAX: int = 80
const DEF_LOSS_MIN: int = 5
const DEF_LOSS_MAX: int = 60
const MIN_CAPTURE_GARRISON: int = 40

# Combat constants used by AI estimates & combat calc
const FORT_ATTACK_BONUS_PER_LEVEL: int = 6
const FORT_DEF_MULT: int = 18

# -----------------------------
# Modules
# -----------------------------
var ai_planner: AIPlanner = AIPlanner.new()
var upgrade_resolver: UpgradeResolver = UpgradeResolver.new()
var transfer_resolver: TransferResolver = TransferResolver.new()
var combat_resolver: CombatResolver = CombatResolver.new()
var economy_resolver: EconomyResolver = EconomyResolver.new()
var reinforcement_resolver: ReinforcementResolver = ReinforcementResolver.new()
var ownership_resolver: OwnershipResolver = OwnershipResolver.new()


func execute_month(state: GameState, human_id: int, ai_id: int, run_ai: bool) -> void:
	if state == null or state.map_data == null:
		return

	# Advance month
	state.month_index += 1

	# AI planning happens during the same "planning phase" snapshot
	if run_ai:
		ai_planner.plan_month(state, ai_id)

	# Resolution pipeline (matches your roadmap ordering)
	upgrade_resolver.resolve(state)
	transfer_resolver.resolve(state)
	combat_resolver.resolve(state)
	economy_resolver.resolve(state)
	reinforcement_resolver.resolve(state)
	ownership_resolver.recount_faction_provinces(state)

	# Clear orders for the next planning phase
	# (both players; keeps UI clean and prevents double-execution)
	var map_data: MapData = state.map_data
	for item in map_data.factions:
		var f: FactionData = item as FactionData
		state.order_book.clear_orders_for_faction(int(f.id))
