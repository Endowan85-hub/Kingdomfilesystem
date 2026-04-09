# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: ProgressionTuningProfile
#
# Role:
# Centralised tuning knobs for unit and leader stat growth on level-up.
# All progression math reads from this profile.
# AutoTuner searches this knob space to balance progression.
#
# Allowed Interactions:
# - UnitData.add_xp()
# - LeaderData.add_xp()
# - ProgressionAutoTuner (future)
#
# Forbidden Responsibilities:
# - Must not mutate any game state
# - Must not queue orders
# ==================================================
extends Resource
class_name ProgressionTuningProfile

# --------------------------------------------------
# UNIT STAT GROWTH (per level gained)
# --------------------------------------------------
# Each stat gains this flat amount per level.
# Tuner will search these as independent knobs.
@export var unit_attack_per_level: float = 1.2
@export var unit_defense_per_level: float = 0.8
@export var unit_hp_per_level: float = 4.0

# --------------------------------------------------
# LEADER STAT GROWTH (per level gained)
# Rotates: leadership → attack → defense
# Each full cycle = all 3 stats gained once.
# --------------------------------------------------
@export var leader_leadership_per_level: float = 1.0
@export var leader_attack_per_level: float = 0.8
@export var leader_defense_per_level: float = 0.8

# --------------------------------------------------
# XP THRESHOLDS
# --------------------------------------------------
# Unit: xp_to_next = unit_xp_base + (level-1) * unit_xp_growth
@export var unit_xp_base: int = 20
@export var unit_xp_growth: int = 12

# Leader: xp_to_next = leader_xp_base + (level-1) * leader_xp_growth
@export var leader_xp_base: int = 100
@export var leader_xp_growth: int = 15

# --------------------------------------------------
# SINGLETON ACCESS
# --------------------------------------------------
static var _instance: ProgressionTuningProfile = null

static func get_instance() -> ProgressionTuningProfile:
	if _instance == null:
		_instance = ProgressionTuningProfile.new()
	return _instance
