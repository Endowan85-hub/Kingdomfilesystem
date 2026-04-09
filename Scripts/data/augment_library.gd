# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: AugmentLibrary
#
# Role:
# Static data store for all Augments in KINGDOM.
# Augments modify an equipped Sigil. Requires 2 slots (Tier 3+ units).
#
# Fields per Augment:
#   id                    String   unique identifier
#   name                  String   display name
#   allowed_tags          Array    tags the SIGIL must have for this augment to apply
#   damage_mult           float    multiplier on top of sigil damage (1.0 = no change)
#   sp_cost_mult          float    multiplier on sigil sp_cost (1.0 = no change)
#   effect_mult           float    multiplier on sigil effect_value (1.0 = no change)
#   forces_full_action    bool     if true, always upgrades skill to Full Action
#   secondary_effect      String   extra effect applied on top of sigil ("", "pierce_bonus", "drain", "sunder", "accuracy_boost", "defense_penalty_self", "sweep", "extend_range", "pressure", "guarded")
#   secondary_value       float    magnitude of secondary_effect
#   description           String   player-facing tooltip
# ==================================================

const AUGMENTS: Array = [

	{
		"id": "overstrike",
		"name": "Overstrike",
		"allowed_tags": ["melee", "ranged"],
		"damage_mult": 1.25,
		"sp_cost_mult": 1.20,
		"effect_mult": 1.0,
		"forces_full_action": false,
		"secondary_effect": "",
		"secondary_value": 0.0,
		"description": "+25% damage, +20% SP cost.",
	},
	{
		"id": "measured",
		"name": "Measured",
		"allowed_tags": ["melee", "ranged", "support", "heal"],
		"damage_mult": 0.83,
		"sp_cost_mult": 0.80,
		"effect_mult": 0.83,
		"forces_full_action": false,
		"secondary_effect": "",
		"secondary_value": 0.0,
		"description": "-20% SP cost, -17% effectiveness.",
	},
	{
		"id": "sweep",
		"name": "Sweep",
		"allowed_tags": ["melee"],
		"damage_mult": 1.0,
		"sp_cost_mult": 1.0,
		"effect_mult": 1.0,
		"forces_full_action": true,
		"secondary_effect": "sweep",
		"secondary_value": 0.60,
		"description": "Converts hit to cross-pattern AoE. Secondary targets take 60% damage. Always Full Action.",
	},
	{
		"id": "extended_reach",
		"name": "Extended Reach",
		"allowed_tags": ["ranged"],
		"damage_mult": 1.0,
		"sp_cost_mult": 1.0,
		"effect_mult": 1.0,
		"forces_full_action": false,
		"secondary_effect": "extend_range",
		"secondary_value": 1.0,
		"description": "+1 tile range on ranged Sigils.",
	},
	{
		"id": "sunder",
		"name": "Sunder",
		"allowed_tags": ["melee"],
		"damage_mult": 1.0,
		"sp_cost_mult": 1.0,
		"effect_mult": 1.0,
		"forces_full_action": false,
		"secondary_effect": "sunder",
		"secondary_value": 0.15,
		"description": "Reduces target defense by 15% for 1 turn on hit.",
	},
	{
		"id": "drain",
		"name": "Drain",
		"allowed_tags": ["melee", "ranged"],
		"damage_mult": 1.0,
		"sp_cost_mult": 1.0,
		"effect_mult": 1.0,
		"forces_full_action": false,
		"secondary_effect": "drain",
		"secondary_value": 0.20,
		"description": "Restore 20% of damage dealt as HP.",
	},
	{
		"id": "focus",
		"name": "Focus",
		"allowed_tags": ["ranged", "support"],
		"damage_mult": 0.97,
		"sp_cost_mult": 1.0,
		"effect_mult": 1.0,
		"forces_full_action": false,
		"secondary_effect": "accuracy_boost",
		"secondary_value": 15.0,
		"description": "+15 accuracy, slight damage reduction.",
	},
	{
		"id": "pressure",
		"name": "Pressure",
		"allowed_tags": ["melee", "ranged"],
		"damage_mult": 1.0,
		"sp_cost_mult": 1.0,
		"effect_mult": 1.0,
		"forces_full_action": false,
		"secondary_effect": "pressure",
		"secondary_value": 0.30,
		"description": "+30% bonus damage against targets below 40% HP.",
	},
	{
		"id": "all_in",
		"name": "All-In",
		"allowed_tags": ["melee", "ranged"],
		"damage_mult": 1.35,
		"sp_cost_mult": 1.0,
		"effect_mult": 1.0,
		"forces_full_action": false,
		"secondary_effect": "defense_penalty_self",
		"secondary_value": 0.20,
		"description": "+35% damage. -20% own defense this turn.",
	},
	{
		"id": "guarded",
		"name": "Guarded",
		"allowed_tags": ["support", "heal"],
		"damage_mult": 0.85,
		"sp_cost_mult": 1.0,
		"effect_mult": 0.85,
		"forces_full_action": false,
		"secondary_effect": "guarded",
		"secondary_value": 0.20,
		"description": "+20% own defense this turn. -15% effectiveness.",
	},
]

# --------------------------------------------------
# STATIC ACCESSORS
# --------------------------------------------------

static func get_augment(augment_id: String) -> Dictionary:
	for a in AUGMENTS:
		if str(a.get("id", "")) == augment_id:
			return a as Dictionary
	return {}


static func can_equip(augment_id: String, sigil_tags: Array) -> bool:
	# Augment is compatible if ANY of sigil's tags match the augment's allowed_tags
	var a: Dictionary = get_augment(augment_id)
	if a.is_empty():
		return false
	var allowed: Array = a.get("allowed_tags", []) as Array
	for tag in sigil_tags:
		if allowed.has(tag):
			return true
	return false


static func get_effective_action_type(sigil_action_type: String, augment_id: String) -> String:
	# Returns "full" if augment forces full action, otherwise returns sigil's action type
	if augment_id == "":
		return sigil_action_type
	var a: Dictionary = get_augment(augment_id)
	if bool(a.get("forces_full_action", false)):
		return "full"
	return sigil_action_type

static func forces_full_action(augment_id: String) -> bool:
	var a: Dictionary = get_augment(augment_id)
	return bool(a.get("forces_full_action", false))

static func apply_sp_cost(base_cost: int, augment_id: String) -> int:
	var a: Dictionary = get_augment(augment_id)
	if a.is_empty():
		return base_cost
	var mult: float = float(a.get("sp_cost_mult", 1.0))
	return maxi(1, int(round(float(base_cost) * mult)))

static func apply_damage_mult(base_pct: float, augment_id: String) -> float:
	var a: Dictionary = get_augment(augment_id)
	if a.is_empty():
		return base_pct
	var mod: float = float(a.get("damage_mult", 0.0))
	return maxf(0.1, base_pct + mod)
