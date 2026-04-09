# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: MissionTuningProfile
#
# Role:
# Holds all tunable knobs for the mission system.
# Singleton pattern — get_instance() returns the live profile.
# MissionAutoTuner mutates this during search.
# MissionResolver reads it at runtime.
#
# Allowed Interactions:
# - MissionResolver (reads knobs)
# - MissionAutoTuner (mutates knobs during search)
#
# Forbidden Responsibilities:
# - Must not modify GameState
# - Must not touch UI
# ==================================================

class_name MissionTuningProfile
extends Resource

# --------------------------------------------------
# ENEMY SCALING KNOBS
# --------------------------------------------------

# Stat multiplier range applied to enemy units/leaders (non-elite missions)
# enemy_stats = player_power * rng(scale_low .. scale_high)
@export var scale_low: float  = 0.80
@export var scale_high: float = 1.20

# Separate scale range for elite missions — lets tuner soften elites
# without affecting skirmish/treasure/hunt difficulty
@export var elite_scale_low: float  = 0.60
@export var elite_scale_high: float = 0.90

# --------------------------------------------------
# SIGIL DROP KNOBS
# --------------------------------------------------

# Elite missions: drop sigil on win (always 1.0 = guaranteed)
@export var elite_sigil_chance: float = 1.0

# Elite missions: also drop sigil on loss (gets sigils into economy faster)
@export var elite_sigil_on_loss: bool = false

# Non-elite missions: small baseline sigil drop chance on win
# 0.0 = off, 0.05 = 5% chance
@export var non_elite_sigil_chance: float = 0.03

# --------------------------------------------------
# ITEM DROP KNOBS (per category)
# --------------------------------------------------

@export var item_chance_skirmish: float = 0.10
@export var item_chance_treasure: float = 0.60
@export var item_chance_hunt: float     = 0.40
@export var item_chance_elite: float    = 0.70

# --------------------------------------------------
# SPAWN RATE KNOBS
# --------------------------------------------------

# Probability per empty slot per month that a mission spawns
@export var spawn_roll_chance: float = 0.50

# How many spawns behind triggers forced category correction
@export var regulator_lag_threshold: int = 2

# --------------------------------------------------
# TARGET METRICS (used by tuner scoring)
# --------------------------------------------------

@export var target_elite_win_rate: float    = 0.40
@export var target_hunt_win_rate: float     = 0.50
@export var target_treasure_win_rate: float = 0.55
@export var target_skirmish_win_rate: float = 0.65

# Target: 2 sigils per leader per alive faction by month 72
# With ~2 leaders per faction and 8 factions alive at month 72 → ~32 sigils total
@export var target_sigils_per_leader: float = 2.0
@export var target_alive_factions: int      = 8
@export var target_leaders_per_faction: int = 2

# --------------------------------------------------
# SINGLETON
# --------------------------------------------------

static var _instance: MissionTuningProfile = null

static func get_instance() -> MissionTuningProfile:
	if _instance == null:
		_instance = MissionTuningProfile.new()
	return _instance
