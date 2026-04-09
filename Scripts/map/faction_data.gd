# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: FactionData
#
# Role:
# Stores all persistent state for a single faction in the simulation.
# Includes identity, economy, owned provinces, assigned leaders,
# and AI behavior metadata.
#
# Allowed Interactions:
# - GameState (authoritative container)
# - MapData / ProvinceData (ownership)
# - LeaderData (leader_ids)
# - AIPlanner (reads ai_playstyle, faction_key)
#
# Forbidden Responsibilities:
# - Must not execute gameplay logic
# - Must not queue orders
# - Must not interact with UI directly
#
# Game Phase:
# Both
#
# Notes:
# - faction_key is a stable string identifier (e.g. "house_war") used to
#   match story leaders and AI playstyle regardless of numeric id.
# - ai_playstyle is read by AIPlanner to select behavior profile.
#   Valid values: aggressive / defensive / diplomatic / economic /
#                 expansionist / opportunist / balanced /
#                 calculated / fortify / conquest
# - unit_archetype is metadata for the tactical layer (future use).
# ==================================================
extends Resource
class_name FactionData

@export var id: int = -1
@export var display_name: String = "Faction"
@export var faction_key: String = ""        # stable lore identifier
@export var color: Color = Color.WHITE

@export var gold: int = 0
@export var income: int = 0
@export var income_last_turn: int = 0

@export var ai_playstyle: String = "balanced"   # drives AIPlanner behavior
@export var unit_archetype: String = ""         # tactical layer metadata (future)
@export var lore_house: String = ""             # display name of the great house

@export var provinces: Array[int] = []
@export var leader_ids: Array[int] = []
@export var is_eliminated: bool = false  # true once faction loses last province

# --------------------------------------------------
# Doctrine — persistent AI personality (0.0 – 1.0)
# Set by map_generator at campaign start via FACTION_DEFS.
# Read by AIPlanner every month to scale action utility scores.
# --------------------------------------------------
@export var aggression:          float = 0.50  # willingness to attack
@export var caution:             float = 0.50  # risk aversion / retreat threshold
@export var elite_preservation:  float = 0.60  # protect high-value leaders / units
@export var economy_focus:       float = 0.50  # income / gold management priority
@export var border_security:     float = 0.60  # defensive investment on frontiers
@export var neutral_expansion:   float = 0.50  # preference for neutral over enemy targets
@export var revenge_bias:        float = 0.40  # prioritise attacking recent attackers
@export var fortify_bias:        float = 0.50  # fort upgrade priority
@export var mission_bias:        float = 0.50  # mission / espionage priority
@export var item_hunting_bias:   float = 0.50  # item hunt priority
@export var recruit_bias:        float = 0.60  # army-filling priority
@export var mobility_preference: float = 0.45  # preference for fast / cavalry units
@export var combined_arms_bias:  float = 0.75  # prefer balanced mixed armies
@export var opportunism:         float = 0.55  # exploit unexpected openings
@export var hold_ground_bias:    float = 0.65  # defend held territory vs retreat

# Tutorial missions seen — prevents re-spawning once fired
@export var tutorial_missions_seen: Array[String] = []
