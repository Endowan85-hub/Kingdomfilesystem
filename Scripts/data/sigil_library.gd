# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: SigilLibrary
# Role: Static data for all Sigils in KINGDOM.
#
# Fields: id, name, tier, tags[], sp_cost, action_type,
#   effect_type, effect_value, effect_value2 (optional),
#   range (-1=unit base range, 0=self), target_type, description
# ==================================================

const SIGILS: Array = [
	# TIER 1
	{"id":"power_strike","name":"Power Strike","tier":1,"tags":["melee"],"sp_cost":9,"action_type":"standard","effect_type":"damage_pct","effect_value":1.18,"range":1,"target_type":"enemy","description":"118% weapon damage."},
	{"id":"piercing_thrust","name":"Piercing Thrust","tier":1,"tags":["melee"],"sp_cost":9,"action_type":"standard","effect_type":"damage_pct_pierce","effect_value":1.10,"effect_value2":0.20,"range":1,"target_type":"enemy","description":"110% damage, ignores 20% of target defense."},
	{"id":"quick_shot","name":"Quick Shot","tier":1,"tags":["ranged"],"sp_cost":9,"action_type":"standard","effect_type":"damage_pct","effect_value":1.18,"range":-1,"target_type":"enemy","description":"118% weapon damage at range."},
	{"id":"guard_stance","name":"Guard Stance","tier":1,"tags":["melee","support"],"sp_cost":8,"action_type":"standard","effect_type":"brace","effect_value":0.35,"range":0,"target_type":"self","description":"Reduce incoming damage by 35% this turn."},
	{"id":"minor_heal","name":"Minor Heal","tier":1,"tags":["heal","support"],"sp_cost":8,"action_type":"standard","effect_type":"heal_pct","effect_value":0.20,"range":2,"target_type":"ally","description":"Restore 20% of an ally's max HP."},
	# TIER 2
	{"id":"heavy_slash","name":"Heavy Slash","tier":2,"tags":["melee"],"sp_cost":13,"action_type":"standard","effect_type":"damage_pct","effect_value":1.40,"range":1,"target_type":"enemy","description":"140% weapon damage."},
	{"id":"armor_break","name":"Armor Break","tier":2,"tags":["melee"],"sp_cost":12,"action_type":"standard","effect_type":"damage_pct_pierce","effect_value":1.10,"effect_value2":0.15,"range":1,"target_type":"enemy","description":"110% damage, ignores 15% defense."},
	{"id":"focus_shot","name":"Focus Shot","tier":2,"tags":["ranged"],"sp_cost":13,"action_type":"standard","effect_type":"damage_pct","effect_value":1.40,"range":-1,"target_type":"enemy","description":"140% damage at range, high accuracy."},
	{"id":"rally","name":"Rally","tier":2,"tags":["support"],"sp_cost":12,"action_type":"standard","effect_type":"buff_attack","effect_value":0.15,"range":2,"target_type":"ally","description":"Boost an ally's attack by 15% this turn."},
	{"id":"field_mend","name":"Field Mend","tier":2,"tags":["heal","support"],"sp_cost":12,"action_type":"standard","effect_type":"heal_pct","effect_value":0.30,"range":2,"target_type":"ally","description":"Restore 30% of an ally's max HP."},
	# TIER 3 basic
	{"id":"crushing_blow","name":"Crushing Blow","tier":3,"tags":["melee"],"sp_cost":17,"action_type":"full","effect_type":"damage_pct","effect_value":1.65,"range":1,"target_type":"enemy","description":"165% weapon damage. Full Action."},
	{"id":"penetrating_arrow","name":"Penetrating Arrow","tier":3,"tags":["ranged"],"sp_cost":17,"action_type":"full","effect_type":"damage_pct_pierce","effect_value":1.65,"effect_value2":0.25,"range":-1,"target_type":"enemy","description":"165% damage, ignores 25% defense. Full Action."},
	{"id":"battle_cry","name":"Battle Cry","tier":3,"tags":["support"],"sp_cost":16,"action_type":"full","effect_type":"buff_team_attack","effect_value":0.18,"range":3,"target_type":"ally","description":"All nearby allies gain +18% attack. Full Action."},
	{"id":"reinforce","name":"Reinforce","tier":3,"tags":["support"],"sp_cost":16,"action_type":"full","effect_type":"buff_team_defense","effect_value":0.20,"range":2,"target_type":"ally","description":"All nearby allies gain +20% defense. Full Action."},
	{"id":"counter_stance","name":"Counter Stance","tier":3,"tags":["melee"],"sp_cost":14,"action_type":"standard","effect_type":"counter_stance","effect_value":1.00,"range":0,"target_type":"self","description":"Counter at 80-120% damage if attacked this turn."},
	# TIER 3 advanced
	{"id":"flank_strike","name":"Flank Strike","tier":3,"tags":["melee"],"sp_cost":14,"action_type":"standard","effect_type":"flank_strike","effect_value":1.10,"effect_value2":0.30,"range":1,"target_type":"enemy","description":"110% damage. +30% if target is adjacent to an ally."},
	{"id":"mark_target","name":"Mark Target","tier":3,"tags":["support"],"sp_cost":12,"action_type":"standard","effect_type":"mark","effect_value":0.35,"range":2,"target_type":"enemy","description":"Mark enemy. Next hit against them deals +35% damage."},
	{"id":"pinning_shot","name":"Pinning Shot","tier":3,"tags":["ranged"],"sp_cost":14,"action_type":"standard","effect_type":"pin","effect_value":1.0,"range":-1,"target_type":"enemy","description":"Reduces target movement next turn."},
	{"id":"brace","name":"Brace","tier":3,"tags":["support"],"sp_cost":14,"action_type":"full","effect_type":"brace","effect_value":0.45,"range":0,"target_type":"self","description":"Reduce all incoming damage by 45% this turn. Full Action."},
	{"id":"finisher","name":"Finisher","tier":3,"tags":["melee","ranged"],"sp_cost":16,"action_type":"standard","effect_type":"finisher","effect_value":1.20,"effect_value2":2.10,"range":-1,"target_type":"enemy","description":"120% damage. 210% if target below 30% HP."},
	{"id":"riposte","name":"Riposte","tier":3,"tags":["melee"],"sp_cost":14,"action_type":"standard","effect_type":"counter_stance","effect_value":1.00,"range":0,"target_type":"self","description":"Auto-counter if attacked next turn."},
	# TIER 4
	{"id":"execution_strike","name":"Execution Strike","tier":4,"tags":["melee"],"sp_cost":22,"action_type":"full","effect_type":"finisher","effect_value":1.80,"effect_value2":2.50,"range":1,"target_type":"enemy","description":"180% damage. Massive bonus vs weakened targets. Full Action."},
	{"id":"rain_volley","name":"Rain Volley","tier":4,"tags":["ranged"],"sp_cost":22,"action_type":"full","effect_type":"damage_pct","effect_value":1.90,"range":-1,"target_type":"enemy","description":"190% ranged damage. Full Action."},
	{"id":"war_command","name":"War Command","tier":4,"tags":["support"],"sp_cost":22,"action_type":"full","effect_type":"buff_team_attack","effect_value":0.20,"range":4,"target_type":"ally","description":"All nearby allies gain +20% attack. Full Action."},
	{"id":"last_stand","name":"Last Stand","tier":4,"tags":["support"],"sp_cost":22,"action_type":"full","effect_type":"survive_lethal","effect_value":0.25,"range":0,"target_type":"self","description":"Survive one lethal hit. Gain temp attack boost after. Full Action."},
	{"id":"surge_heal","name":"Surge Heal","tier":4,"tags":["heal"],"sp_cost":22,"action_type":"full","effect_type":"heal_pct","effect_value":0.60,"range":2,"target_type":"ally","description":"Restore 60% of an ally's max HP. Full Action."},
	{"id":"delayed_strike","name":"Delayed Strike","tier":4,"tags":["melee"],"sp_cost":18,"action_type":"full","effect_type":"delayed_strike","effect_value":1.80,"range":1,"target_type":"enemy","description":"180% damage triggers at start of your next turn. Full Action."},
	{"id":"disrupt","name":"Disrupt","tier":4,"tags":["melee"],"sp_cost":18,"action_type":"full","effect_type":"disrupt","effect_value":1.0,"range":1,"target_type":"enemy","description":"Target cannot use Sigils next turn. Full Action."},
	{"id":"momentum","name":"Momentum","tier":4,"tags":["melee"],"sp_cost":16,"action_type":"standard","effect_type":"momentum","effect_value":1.10,"effect_value2":0.40,"range":1,"target_type":"enemy","description":"110% damage. +40% if you secured a kill last turn."},
	{"id":"volley_line","name":"Volley Line","tier":4,"tags":["ranged"],"sp_cost":20,"action_type":"full","effect_type":"volley_line","effect_value":1.60,"effect_value2":0.70,"range":-1,"target_type":"enemy","description":"160% to primary. 70% to unit directly behind. Full Action."},
	{"id":"zone_strike","name":"Zone Strike","tier":4,"tags":["melee"],"sp_cost":20,"action_type":"full","effect_type":"zone_strike","effect_value":1.60,"effect_value2":0.50,"range":1,"target_type":"enemy","description":"160% to primary. 50% to adjacent enemies. Full Action."},
	{"id":"command_surge_sigil","name":"Command Surge","tier":4,"tags":["support"],"sp_cost":18,"action_type":"full","effect_type":"command_surge","effect_value":0.20,"effect_value2":0.20,"range":2,"target_type":"ally","description":"Ally gains +20% attack and 20% reduced SP cost next action. Full Action."},
]

static func get_sigil(sigil_id: String) -> Dictionary:
	for s in SIGILS:
		if str(s.get("id","")) == sigil_id:
			return s as Dictionary
	return {}

static func can_equip(sigil_id: String, unit_tier: int, allowed_tags: Array) -> bool:
	var s: Dictionary = get_sigil(sigil_id)
	if s.is_empty(): return false
	if int(s.get("tier",1)) > unit_tier: return false
	for tag in (s.get("tags",[]) as Array):
		if allowed_tags.has(tag): return true
	return false

const SIGNATURE_ABILITIES: Array = [
	{"id":"unified_command","name":"Unified Command ✦","leader_id":"house_counsel","action_type":"full","tags":["support"],"sp_cost":10,"effect_type":"buff_team_attack","effect_value":0.12,"effect_value2":0.08,"range":2,"target_type":"ally","description":"Allies in range gain +12% attack and +8% defense. Full Action."},
	{"id":"relentless_assault","name":"Relentless Assault ✦","leader_id":"house_war","action_type":"standard","tags":["melee"],"sp_cost":10,"effect_type":"damage_pct","effect_value":1.30,"effect_value2":0.20,"range":1,"target_type":"enemy","condition":"assault_followup","description":"130% damage. Gain +20% bonus damage next turn."},
	{"id":"command_surge","name":"Command Surge ✦","leader_id":"house_crown","action_type":"standard","tags":["support"],"sp_cost":10,"effect_type":"command_surge","effect_value":0.18,"effect_value2":0.20,"range":2,"target_type":"ally","description":"Target ally gains +18% attack and 20% reduced SP cost on next action."},
	{"id":"advance_order","name":"Advance Order ✦","leader_id":"house_coin","action_type":"standard","tags":["support"],"sp_cost":10,"effect_type":"buff_attack","effect_value":0.12,"move_bonus":1,"range":2,"target_type":"ally","description":"Target ally gains +1 movement and +12% attack next turn."},
	{"id":"rising_pressure","name":"Rising Pressure ✦","leader_id":"house_people","action_type":"standard","tags":["support"],"sp_cost":10,"effect_type":"buff_team_attack","effect_value":0.15,"range":2,"target_type":"ally","condition":"ally_damaged","description":"Nearby damaged allies gain +15% attack."},
	{"id":"sacred_formation","name":"Sacred Formation ✦","leader_id":"house_faith","action_type":"full","tags":["support"],"sp_cost":10,"effect_type":"buff_team_defense","effect_value":0.35,"range":1,"target_type":"ally","description":"Adjacent allies gain 35% damage reduction, -10% attack. Full Action."},
	{"id":"disrupt_order","name":"Disrupt Order ✦","leader_id":"house_shadows","action_type":"standard","tags":["melee"],"sp_cost":10,"effect_type":"disrupt","effect_value":1.0,"range":1,"target_type":"enemy","description":"Normal damage + target cannot use Sigils next turn."},
	{"id":"forced_engagement","name":"Forced Engagement ✦","leader_id":"house_diplomacy","action_type":"standard","tags":["support"],"sp_cost":10,"effect_type":"force_engage","effect_value":0,"range":2,"target_type":"enemy","description":"Target enemy must attack nearest unit next turn."},
	{"id":"hold_ground","name":"Hold Ground ✦","leader_id":"house_frontier","action_type":"full","tags":["support"],"sp_cost":10,"effect_type":"brace","effect_value":0.50,"range":0,"target_type":"self","description":"50% damage reduction this turn. Cannot be displaced. Full Action."},
	{"id":"enforce_order","name":"Enforce Order ✦","leader_id":"house_law","action_type":"standard","tags":["support"],"sp_cost":10,"effect_type":"debuff_defense","effect_value":0.15,"range":2,"target_type":"enemy","description":"Target takes -15% damage output and -1 movement next turn."},
	{"id":"calculated_strike","name":"Calculated Strike ✦","leader_id":"house_strategy","action_type":"standard","tags":["support"],"sp_cost":10,"effect_type":"mark","effect_value":0.40,"range":2,"target_type":"enemy","description":"Mark target — next attack gains +40% bonus damage."},
	{"id":"rapid_deployment","name":"Rapid Deployment ✦","leader_id":"house_roads","action_type":"full","tags":["support"],"sp_cost":10,"effect_type":"buff_defense","effect_value":0.15,"reposition":2,"range":2,"target_type":"ally","description":"Ally repositions up to 2 tiles and gains +15% defense. Full Action."},
	{"id":"rivals_fury","name":"Rival's Fury ✦","leader_id":"house_blood","action_type":"standard","tags":["melee"],"sp_cost":10,"effect_type":"buff_attack","effect_value":0.35,"range":0,"target_type":"self","description":"Self gains +35% attack, -20% defense this turn."},
	{"id":"reinforce_formation","name":"Reinforce Formation ✦","leader_id":"house_provinces","action_type":"full","tags":["support"],"sp_cost":10,"effect_type":"buff_team_defense","effect_value":0.20,"range":1,"target_type":"ally","description":"Adjacent allies gain +20% defense and small HP sustain. Full Action."},
	{"id":"warpath","name":"Warpath ✦","leader_id":"house_steppe","action_type":"standard","tags":["melee"],"sp_cost":10,"effect_type":"damage_pct","effect_value":1.20,"effect_value2":0.25,"move_bonus":1,"range":1,"target_type":"enemy","condition":"self_moved_this_turn","description":"Gain +1 move. If moved before attacking, deal +25% bonus damage."},
]

static func get_signature_ability(ability_id: String) -> Dictionary:
	for a in SIGNATURE_ABILITIES:
		if str(a.get("id","")) == ability_id:
			return a as Dictionary
		# Also match by leader_id (story_id is stored as signature_ability_id)
		if str(a.get("leader_id","")) == ability_id:
			return a as Dictionary
	return {}

static func get_sigils_for_tags(allowed_tags: Array, unit_tier: int) -> Array:
	var result: Array = []
	for s in SIGILS:
		if int(s.get("tier",1)) > unit_tier:
			continue
		for tag in (s.get("tags",[]) as Array):
			if allowed_tags.has(tag):
				result.append(s)
				break
	return result

static func is_full_action(sigil_id: String) -> bool:
	var s: Dictionary = get_sigil(sigil_id)
	if s.is_empty():
		s = get_signature_ability(sigil_id)
	return str(s.get("action_type","standard")) == "full"
