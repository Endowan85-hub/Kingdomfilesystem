# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: BattleTuningProfile
#
# Role:
# Holds all tunable parameters for battle simulation.
# Searched by BattleAutoTuner to find optimal balance.
#
# Allowed Interactions:
# - BattleResolver (combat math knobs)
# - BattleAI (behavior knobs)
# - BattleLab (simulation targets)
#
# Forbidden Responsibilities:
# - Must not modify GameState
# - Must not queue orders
#
# Tuned values — March 2026
# Converged profile with accuracy/evasion system active:
#   def_constant: 25.0
#   type_advantage_mult: 1.25
#   type_disadvantage_mult: 0.75
#   fort_def_mult: 0.05
# Targets updated to reflect real accuracy-system battle feel.
# Slight attacker disadvantage (~35-40% win rate) is intentional —
# defenders choose position, attackers must overcome miss chance.
# ==================================================

class_name BattleTuningProfile

# --------------------------------------------------
# COMBAT MATH KNOBS
# --------------------------------------------------

# Defense mitigation constant — higher = defense matters more
# Formula: mitigation = defense / (defense + def_constant)
# Tuned: 25.0 — calibrated for real unit stat ranges with accuracy active
@export var def_constant: float = 25.0

# Variance as fraction of raw damage (0.15 = ±15%)
@export var variance_fraction: float = 0.15

# Damage type advantage multiplier
# Tuned: 1.25 — meaningful without being overwhelming
@export var type_advantage_mult: float = 1.25

# Damage type disadvantage multiplier
# Tuned: 0.75 — decisive across mixed armies
@export var type_disadvantage_mult: float = 0.75

# Defend stance defense multiplier (default 1.5 = +50%)
@export var defend_mult: float = 1.5

# Leader attack bonus fraction of leader.attack stat
@export var leader_atk_bonus_fraction: float = 0.15

# Leader defense bonus fraction of leader.defense stat
@export var leader_def_bonus_fraction: float = 0.15

# Fort defense bonus — flat % of each defender's defense per fort level
# Formula: bonus = base_defense * (fort_level * fort_def_mult)
# Tuned: 0.05 → fort level 2 = +10% defense to all defenders
@export var fort_def_mult: float = 0.05

# --------------------------------------------------
# SIMULATION TARGETS
# Calibrated to real accuracy/evasion system feel
# --------------------------------------------------

# Target rounds for typical army (1 leader + 6 units) even match
# Accuracy system extends battles — real feel is ~12 rounds
@export var target_rounds_typical_even: float = 15.0

# Target rounds for max army (3 leaders + 18 units) even match
@export var target_rounds_max_even: float = 16.0

# Target rounds for leader duel (no units)
@export var target_rounds_leader_even: float = 9.0

# Target win rate for attacker with 10% stat advantage
@export var target_win_rate_10pct_advantage: float = 0.55

# Target win rate for attacker with 25% stat advantage
# Slight reduction from 0.80 — accuracy variance softens pure stat edges
@export var target_win_rate_25pct_advantage: float = 0.65

# Max rounds before battle considered a stalemate (penalized)
@export var stalemate_round_limit: int = 35

# --------------------------------------------------
# SINGLETON ACCESS
# --------------------------------------------------
static var _instance: BattleTuningProfile = null

static func get_instance() -> BattleTuningProfile:
	if _instance == null:
		_instance = BattleTuningProfile.new()
	return _instance
