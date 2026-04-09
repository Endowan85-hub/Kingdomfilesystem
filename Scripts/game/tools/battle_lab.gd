# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: BattleLab
#
# Role:
# Headless battle simulation harness.
# Runs self-contained stat-dict battles (no BattleUnit/BattleState).
# Reports metrics for AutoTuner scoring.
# Uses real unit and leader stats from UNIT_TEMPLATES and STORY_ROSTER.
#
# Allowed Interactions:
# - BattleTuningProfile (reads knobs)
# - UnitLibrary (reads real unit stat templates)
# - StoryLeaderLibrary (reads real leader stat templates)
#
# Forbidden Responsibilities:
# - Must not modify GameState
# - Must not touch UI
# - Must not queue campaign orders
# ==================================================

class_name BattleLab

const DebugLogger = preload("res://Scripts/debug/debug_logger.gd")

# --------------------------------------------------
# REAL UNIT / LEADER POOLS
# Pulled directly from library definitions
# --------------------------------------------------

# All unit templates indexed by tier for fast random selection
static func _get_units_by_tier(tier: int) -> Array:
	var out: Array = []
	for tpl in UnitLibrary.UNIT_TEMPLATES:
		if int(tpl.get("tier", 1)) == tier:
			out.append(tpl)
	return out

# All story leader stat blocks
static func _get_leader_pool() -> Array:
	var out: Array = []
	for l in StoryLeaderLibrary.STORY_ROSTER:
		out.append(l)
	return out

# --------------------------------------------------
# ARMY BUILDER — real randomized armies
# tier_weights: [t1_chance, t2_chance, t3_chance] must sum to 1.0
# unit_count: number of units (not counting leader)
# --------------------------------------------------

static func _build_real_army(rng: RandomNumberGenerator,
		unit_count: int,
		tier_weights: Array = [1.0, 0.0, 0.0]) -> Dictionary:

	# Pick a random story leader
	var leader_pool: Array = _get_leader_pool()
	var leader_tpl: Dictionary = leader_pool[rng.randi() % leader_pool.size()] as Dictionary

	# Build unit roster by weighted tier draw
	var t1: Array = _get_units_by_tier(1)
	var t2: Array = _get_units_by_tier(2)
	var t3: Array = _get_units_by_tier(3)

	var units: Array = []
	for _i in range(unit_count):
		var roll: float = rng.randf()
		var pool: Array
		if roll < float(tier_weights[0]):
			pool = t1
		elif roll < float(tier_weights[0]) + float(tier_weights[1]):
			pool = t2
		else:
			pool = t3
		if pool.is_empty():
			pool = t1
		var tpl: Dictionary = pool[rng.randi() % pool.size()] as Dictionary
		# Sigil equip rate ~50% — reflects real campaign equip rates
		# Damage mult and SP cost by tier (offensive sigils only — defensive/heal don't affect win rate)
		var unit_tier: int = int(tpl.get("tier", 1))
		var sigil_dmg_mult: float = 0.0
		var sigil_sp_cost: int = 0
		var unit_max_sp: int = 0
		if rng.randf() < 0.50:
			match unit_tier:
				1: sigil_dmg_mult = 1.18; sigil_sp_cost = 9
				2: sigil_dmg_mult = 1.40; sigil_sp_cost = 13
				_: sigil_dmg_mult = 1.65; sigil_sp_cost = 17
			# SP from spec: 10 + (level - 1) * 2, using tier as proxy for avg level
			unit_max_sp = 10 + (unit_tier * 4)
		units.append({
			"attack": int(tpl.get("attack", 13)),
			"defense": int(tpl.get("defense", 9)),
			"hp": int(tpl.get("hp", 35)),
			"damage_type": str(tpl.get("damage_type", "slash")),
			"speed": int(tpl.get("speed", 4)),
			"accuracy": int(tpl.get("accuracy", 75)),
			"evasion": int(tpl.get("evasion", 8)),
			"sigil_dmg_mult": sigil_dmg_mult,
			"sigil_sp_cost": sigil_sp_cost,
			"max_sp": unit_max_sp,
		})

	return {
		"leader": {
			"attack": int(leader_tpl.get("attack", 14)),
			"defense": int(leader_tpl.get("defense", 14)),
			"hp": 65,
			"damage_type": str(leader_tpl.get("damage_type", "slash")),
			"speed": int(leader_tpl.get("speed", 4)),
			"accuracy": int(leader_tpl.get("accuracy", 72)),
			"evasion": int(leader_tpl.get("evasion", 10)),
			"sigil_dmg_mult": 1.40,  # leaders reliably have T2+ sigils
			"sigil_sp_cost": 13,
			"max_sp": 20,
		},
		"units": units,
	}


# Scale all stats of an army by a multiplier — used for controlled advantage scenarios
# Scale ATK and DEF only — HP stays equal so it's a pure combat power advantage
# Scaling HP too gives a compounded advantage that overwhelms the test
static func _scale_army(army: Dictionary, mult: float) -> Dictionary:
	var scaled_leader: Dictionary = {
		"attack": int(float(army["leader"].get("attack", 14)) * mult),
		"defense": int(float(army["leader"].get("defense", 14)) * mult),
		"hp": int(army["leader"].get("hp", 65)),
	}
	var scaled_units: Array = []
	for u in (army.get("units", []) as Array):
		scaled_units.append({
			"attack": int(float(u.get("attack", 13)) * mult),
			"defense": int(float(u.get("defense", 9)) * mult),
			"hp": int(u.get("hp", 40)),
			"damage_type": str(u.get("damage_type", "slash")),
		})
	return {"leader": scaled_leader, "units": scaled_units}

# --------------------------------------------------
# COMBATANT BUILDER
# --------------------------------------------------

static func _build_combatants(army: Dictionary, side: String, fort_def_mult: float = 0.0, fort_level: int = 0) -> Array:
	var out: Array = []
	var leader: Dictionary = army.get("leader", {}) as Dictionary
	if not leader.is_empty():
		out.append({
			"side": side, "is_leader": true,
			"spd": int(leader.get("speed", 4)),
			"acc": int(leader.get("accuracy", 72)),
			"eva": int(leader.get("evasion", 10)),
			"atk": int(leader.get("attack", 14)),
			"def": int(leader.get("defense", 14)),
			"hp": int(leader.get("hp", 65)),
			"dtype": str(leader.get("damage_type", "slash")), "alive": true,
			"current_sp": int(leader.get("max_sp", 0)),
			"sigil_dmg_mult": float(leader.get("sigil_dmg_mult", 0.0)),
			"sigil_sp_cost": int(leader.get("sigil_sp_cost", 0)),
		})
	for u in (army.get("units", []) as Array):
		out.append({
			"side": side, "is_leader": false,
			"spd": int(u.get("speed", 4)),
			"acc": int(u.get("accuracy", 75)),
			"eva": int(u.get("evasion", 8)),
			"atk": int(u.get("attack", 13)),
			"def": int(u.get("defense", 9)),
			"hp": int(u.get("hp", 35)),
			"dtype": str(u.get("damage_type", "slash")), "alive": true,
			"current_sp": int(u.get("max_sp", 0)),
			"sigil_dmg_mult": float(u.get("sigil_dmg_mult", 0.0)),
			"sigil_sp_cost": int(u.get("sigil_sp_cost", 0)),
		})

	# Apply fort bonus to defenders using percentage formula
	if side == "defender" and fort_level > 0 and fort_def_mult > 0.0:
		var fort_pct: float = float(fort_level) * fort_def_mult
		for c in out:
			c["def"] += int(float(c["def"]) * fort_pct)

	return out

# --------------------------------------------------
# DAMAGE TRIANGLE
# --------------------------------------------------

static func _type_mult(atk: String, def_type: String) -> float:
	if (atk == "slash" and def_type == "pierce") or \
	   (atk == "pierce" and def_type == "blunt") or \
	   (atk == "blunt" and def_type == "slash"):
		return 1.25
	if (atk == "slash" and def_type == "blunt") or \
	   (atk == "pierce" and def_type == "slash") or \
	   (atk == "blunt" and def_type == "pierce"):
		return 0.85
	return 1.0


static func _type_mult_tuned(atk: String, def_type: String, adv: float, dis: float) -> float:
	if (atk == "slash" and def_type == "pierce") or \
	   (atk == "pierce" and def_type == "blunt") or \
	   (atk == "blunt" and def_type == "slash"):
		return adv
	if (atk == "slash" and def_type == "blunt") or \
	   (atk == "pierce" and def_type == "slash") or \
	   (atk == "blunt" and def_type == "pierce"):
		return dis
	return 1.0

# --------------------------------------------------
# SINGLE BATTLE RUN — fully self-contained
# --------------------------------------------------

static func run_battle(atk_army: Dictionary, def_army: Dictionary,
		seed_val: int, fort_level: int = 0,
		fort_def_mult: float = 0.0,
		max_rounds: int = 30) -> Dictionary:

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var def_k: float = BattleTuningProfile.get_instance().def_constant
	var type_adv: float = BattleTuningProfile.get_instance().type_advantage_mult
	var type_dis: float = BattleTuningProfile.get_instance().type_disadvantage_mult

	var atk_side: Array = _build_combatants(atk_army, "attacker", 0.0, 0)
	var def_side: Array = _build_combatants(def_army, "defender", fort_def_mult, fort_level)

	var turn_order: Array = []
	turn_order.append_array(atk_side)
	turn_order.append_array(def_side)
	for c in turn_order:
		c["spd_jitter"] = c["spd"] * 100 + rng.randi_range(0, 99)
	turn_order.sort_custom(func(a, b): return int(a["spd_jitter"]) > int(b["spd_jitter"]))

	var rounds: int = 0
	var stalemate: bool = false

	while true:
		rounds += 1
		if rounds > max_rounds:
			stalemate = true
			break

		for c in turn_order:
			c["spd_jitter"] = c["spd"] * 100 + rng.randi_range(0, 99)
		turn_order.sort_custom(func(a, b): return int(a["spd_jitter"]) > int(b["spd_jitter"]))

		for c in turn_order:
			if not c["alive"]:
				continue
			var enemies: Array = def_side if c["side"] == "attacker" else atk_side
			var target = null
			var best_hp: int = 9999
			for e in enemies:
				if e["alive"] and int(e["hp"]) < best_hp:
					best_hp = int(e["hp"])
					target = e
			if target == null:
				continue
			# --- Hit/miss roll ---
			var speed_pen: int = maxi(0, (int(target["spd"]) - int(c["spd"])) * 2)
			var hit_floor: int = 70 if bool(c.get("is_leader", false)) else 50
			var hit_chance: int = clampi(int(c["acc"]) - speed_pen - int(target["eva"]), hit_floor, 95)
			if rng.randi_range(1, 100) > hit_chance:
				continue  # miss — no damage
			# --- Sigil use: apply damage multiplier if SP available ---
			var dmg_mult: float = 1.0
			var sp_cost: int = int(c.get("sigil_sp_cost", 0))
			var sig_mult: float = float(c.get("sigil_dmg_mult", 0.0))
			if sp_cost > 0 and sig_mult > 1.0 and int(c.get("current_sp", 0)) >= sp_cost:
				dmg_mult = sig_mult
				c["current_sp"] = int(c["current_sp"]) - sp_cost
			var raw: float = float(c["atk"]) * dmg_mult * _type_mult_tuned(c["dtype"], target["dtype"], type_adv, type_dis) \
				* (1.0 - float(target["def"]) / (float(target["def"]) + def_k))
			var vr: int = maxi(1, int(raw * 0.15))
			var dmg: int = maxi(1, int(raw) + rng.randi_range(-vr, vr))
			target["hp"] -= dmg
			if target["hp"] <= 0:
				target["alive"] = false

		var atk_alive: bool = false
		var def_alive: bool = false
		for c in atk_side:
			if c["alive"]:
				atk_alive = true
				break
		for c in def_side:
			if c["alive"]:
				def_alive = true
				break
		if not atk_alive or not def_alive:
			break

	var atk_surv: int = 0
	var def_surv: int = 0
	for c in atk_side:
		if c["alive"]: atk_surv += 1
	for c in def_side:
		if c["alive"]: def_surv += 1

	return {
		"attacker_won": atk_surv > 0 and def_surv == 0,
		"defender_won": def_surv > 0 and atk_surv == 0,
		"stalemate": stalemate,
		"rounds": rounds,
		"atk_survivors": atk_surv,
		"def_survivors": def_surv,
	}

# --------------------------------------------------
# SCENARIO RUNNERS — all use real randomized armies
# --------------------------------------------------

# Tier 1 only — early game feel
static func run_even_t1(seeds: int = 20) -> Dictionary:
	var wins: int = 0
	var total_rounds: float = 0.0
	var stalemates: int = 0
	for i in range(seeds):
		var rng := RandomNumberGenerator.new()
		rng.seed = i * 137 + 41
		var atk = _build_real_army(rng, 6, [1.0, 0.0, 0.0])
		var def = _build_real_army(rng, 6, [1.0, 0.0, 0.0])
		var result = run_battle(atk, def, i * 137 + 41)
		if result["attacker_won"]: wins += 1
		if result["stalemate"]: stalemates += 1
		total_rounds += float(result["rounds"])
	return {
		"scenario": "even_t1_real",
		"seeds": seeds,
		"attacker_win_rate": float(wins) / float(seeds),
		"avg_rounds": total_rounds / float(seeds),
		"stalemate_rate": float(stalemates) / float(seeds),
	}

# Typical army — mixed tiers (60% t1, 30% t2, 10% t3), 1 leader + 6 units
static func run_even_typical(seeds: int = 20) -> Dictionary:
	var wins: int = 0
	var total_rounds: float = 0.0
	var stalemates: int = 0
	for i in range(seeds):
		var rng := RandomNumberGenerator.new()
		rng.seed = i * 211 + 73
		var atk = _build_real_army(rng, 6, [0.6, 0.3, 0.1])
		var def = _build_real_army(rng, 6, [0.6, 0.3, 0.1])
		var result = run_battle(atk, def, i * 211 + 73)
		if result["attacker_won"]: wins += 1
		if result["stalemate"]: stalemates += 1
		total_rounds += float(result["rounds"])
	return {
		"scenario": "even_typical_real",
		"seeds": seeds,
		"attacker_win_rate": float(wins) / float(seeds),
		"avg_rounds": total_rounds / float(seeds),
		"stalemate_rate": float(stalemates) / float(seeds),
	}

# Max army — 3 leaders + 18 units, mixed tiers, no fort (fort tested separately)
static func run_even_max(seeds: int = 20) -> Dictionary:
	var wins: int = 0
	var total_rounds: float = 0.0
	var stalemates: int = 0
	for i in range(seeds):
		var rng := RandomNumberGenerator.new()
		rng.seed = i * 173 + 61
		var atk_leaders: Array = []
		var atk_units: Array = []
		var def_leaders: Array = []
		var def_units: Array = []
		for _j in range(3):
			var a = _build_real_army(rng, 6, [0.5, 0.35, 0.15])
			var d = _build_real_army(rng, 6, [0.5, 0.35, 0.15])
			atk_leaders.append(a["leader"])
			atk_units.append_array(a["units"])
			def_leaders.append(d["leader"])
			def_units.append_array(d["units"])
		var atk_combined: Dictionary = {"leader": atk_leaders[0], "units": atk_units}
		var def_combined: Dictionary = {"leader": def_leaders[0], "units": def_units}
		# No fort — equal fight, pure army size test
		var atk_side: Array = _build_combatants(atk_combined, "attacker", 0.0, 0)
		for li in range(1, 3):
			atk_side.append({
				"side": "attacker", "is_leader": true,
				"spd": int(atk_leaders[li].get("speed", 4)),
				"acc": int(atk_leaders[li].get("accuracy", 72)),
				"eva": int(atk_leaders[li].get("evasion", 10)),
				"atk": int(atk_leaders[li].get("attack", 14)),
				"def": int(atk_leaders[li].get("defense", 14)),
				"hp": 65,
				"dtype": str(atk_leaders[li].get("damage_type", "slash")),
				"alive": true,
				"current_sp": 20, "sigil_dmg_mult": 1.40, "sigil_sp_cost": 13,
			})
		var def_side: Array = _build_combatants(def_combined, "defender", 0.0, 0)
		for li in range(1, 3):
			def_side.append({
				"side": "defender", "is_leader": true,
				"spd": int(def_leaders[li].get("speed", 4)),
				"acc": int(def_leaders[li].get("accuracy", 72)),
				"eva": int(def_leaders[li].get("evasion", 10)),
				"atk": int(def_leaders[li].get("attack", 14)),
				"def": int(def_leaders[li].get("defense", 14)),
				"hp": 65,
				"dtype": str(def_leaders[li].get("damage_type", "slash")),
				"alive": true,
				"current_sp": 20, "sigil_dmg_mult": 1.40, "sigil_sp_cost": 13,
			})
		var result = _run_prebuilt(atk_side, def_side, i * 173 + 61, 40)
		if result["attacker_won"]: wins += 1
		if result["stalemate"]: stalemates += 1
		total_rounds += float(result["rounds"])
	return {
		"scenario": "even_max_real",
		"seeds": seeds,
		"attacker_win_rate": float(wins) / float(seeds),
		"avg_rounds": total_rounds / float(seeds),
		"stalemate_rate": float(stalemates) / float(seeds),
	}

# Attacker has exactly 10% stat advantage — build equal armies then scale attacker up
static func run_10pct_advantage(seeds: int = 20) -> Dictionary:
	var wins: int = 0
	var total_rounds: float = 0.0
	for i in range(seeds):
		var rng := RandomNumberGenerator.new()
		rng.seed = i * 317 + 89
		var base = _build_real_army(rng, 6, [0.6, 0.3, 0.1])
		var def = _build_real_army(rng, 6, [0.6, 0.3, 0.1])
		# Scale attacker stats up by exactly 10%
		var atk: Dictionary = _scale_army(base, 1.10)
		var result = run_battle(atk, def, i * 317 + 89)
		if result["attacker_won"]: wins += 1
		total_rounds += float(result["rounds"])
	return {
		"scenario": "10pct_advantage_real",
		"seeds": seeds,
		"attacker_win_rate": float(wins) / float(seeds),
		"avg_rounds": total_rounds / float(seeds),
	}

# Attacker has exactly 25% stat advantage — build equal armies then scale attacker up
static func run_25pct_advantage(seeds: int = 20) -> Dictionary:
	var wins: int = 0
	for i in range(seeds):
		var rng := RandomNumberGenerator.new()
		rng.seed = i * 251 + 103
		var base = _build_real_army(rng, 6, [0.6, 0.3, 0.1])
		var def = _build_real_army(rng, 6, [0.6, 0.3, 0.1])
		# Scale attacker stats up by exactly 25%
		var atk: Dictionary = _scale_army(base, 1.25)
		var result = run_battle(atk, def, i * 251 + 103)
		if result["attacker_won"]: wins += 1
	return {
		"scenario": "25pct_advantage_real",
		"seeds": seeds,
		"attacker_win_rate": float(wins) / float(seeds),
	}

# Type disadvantage — pure triangle test, no fort, no RNG stat variance
# Uses fixed average T1 stats with 10 units per side
# ATTACKER: pierce (disadvantaged vs slash — pierce.slash = 0.85x penalty)
# DEFENDER: slash (advantaged vs pierce)
# Triangle: slash > pierce > blunt > slash
# Target: attacker wins <40%
static func run_type_disadvantage(seeds: int = 20) -> Dictionary:
	var wins: int = 0
	var total_rounds: float = 0.0

	# Calculate average T1 stats across all units — removes stat lottery from test
	var t1_units: Array = _get_units_by_tier(1)
	var avg_atk: int = 0
	var avg_def: int = 0
	var avg_hp: int = 0
	for tpl in t1_units:
		avg_atk += int(tpl.get("attack", 13))
		avg_def += int(tpl.get("defense", 9))
		avg_hp  += int(tpl.get("hp", 40))
	avg_atk = int(float(avg_atk) / float(t1_units.size()))
	avg_def = int(float(avg_def) / float(t1_units.size()))
	avg_hp  = int(float(avg_hp)  / float(t1_units.size()))

	var leader_pool: Array = _get_leader_pool()
	# Average leader stats
	var avg_latk: int = 0
	var avg_ldef: int = 0
	for l in leader_pool:
		avg_latk += int(l.get("attack", 14))
		avg_ldef += int(l.get("defense", 14))
	avg_latk = int(float(avg_latk) / float(leader_pool.size()))
	avg_ldef = int(float(avg_ldef) / float(leader_pool.size()))

	for i in range(seeds):
		# Build 10 identical units per side — only damage type differs
		var atk_units: Array = []
		var def_units: Array = []
		for _j in range(10):
			# Attacker: pierce (disadvantaged vs slash — 0.85x penalty)
			atk_units.append({"attack": avg_atk, "defense": avg_def, "hp": avg_hp,
				"damage_type": "pierce", "speed": 4, "accuracy": 75, "evasion": 8})
			# Defender: slash (advantaged vs pierce)
			def_units.append({"attack": avg_atk, "defense": avg_def, "hp": avg_hp,
				"damage_type": "slash", "speed": 4, "accuracy": 75, "evasion": 8})
		# Leaders use the same forced damage types
		var atk = {"leader": {"attack": avg_latk, "defense": avg_ldef, "hp": 65,
			"damage_type": "pierce", "speed": 4, "accuracy": 72, "evasion": 10}, "units": atk_units}
		var def = {"leader": {"attack": avg_latk, "defense": avg_ldef, "hp": 65,
			"damage_type": "slash", "speed": 4, "accuracy": 72, "evasion": 10}, "units": def_units}
		# Vary only the RNG seed — all other variables fixed
		var result = run_battle(atk, def, i * 193 + 57, 0, 0.0)
		if result["attacker_won"]: wins += 1
		total_rounds += float(result["rounds"])
	return {
		"scenario": "type_disadvantage_real",
		"seeds": seeds,
		"attacker_win_rate": float(wins) / float(seeds),
		"avg_rounds": total_rounds / float(seeds),
	}

# Leader duel — two story leaders, no units
static func run_leader_duel(seeds: int = 20) -> Dictionary:
	var wins: int = 0
	var total_rounds: float = 0.0
	var pool: Array = _get_leader_pool()
	for i in range(seeds):
		var rng := RandomNumberGenerator.new()
		rng.seed = i * 251 + 103
		var al = pool[rng.randi() % pool.size()]
		var dl = pool[rng.randi() % pool.size()]
		var atk = {"leader": {"attack": int(al.get("attack",14)), "defense": int(al.get("defense",14)), "hp": 65,
			"damage_type": str(al.get("damage_type","slash")), "speed": int(al.get("speed",4)),
			"accuracy": int(al.get("accuracy",72)), "evasion": int(al.get("evasion",10))}, "units": []}
		var def = {"leader": {"attack": int(dl.get("attack",14)), "defense": int(dl.get("defense",14)), "hp": 65,
			"damage_type": str(dl.get("damage_type","slash")), "speed": int(dl.get("speed",4)),
			"accuracy": int(dl.get("accuracy",72)), "evasion": int(dl.get("evasion",10))}, "units": []}
		var result = run_battle(atk, def, i * 251 + 103)
		if result["attacker_won"]: wins += 1
		total_rounds += float(result["rounds"])
	return {
		"scenario": "leader_duel_real",
		"seeds": seeds,
		"attacker_win_rate": float(wins) / float(seeds),
		"avg_rounds": total_rounds / float(seeds),
	}

# Fortified defense — equal armies but defender in fort level 2
static func run_fortified_defense(seeds: int = 20) -> Dictionary:
	var wins: int = 0
	var total_rounds: float = 0.0
	for i in range(seeds):
		var rng := RandomNumberGenerator.new()
		rng.seed = i * 137 + 99
		var atk = _build_real_army(rng, 6, [0.6, 0.3, 0.1])
		var def = _build_real_army(rng, 6, [0.6, 0.3, 0.1])
		var fort_mult: float = BattleTuningProfile.get_instance().fort_def_mult
		var result = run_battle(atk, def, i * 137 + 99, 2, fort_mult)
		if result["attacker_won"]: wins += 1
		total_rounds += float(result["rounds"])
	return {
		"scenario": "fortified_defense_real",
		"seeds": seeds,
		"attacker_win_rate": float(wins) / float(seeds),
		"avg_rounds": total_rounds / float(seeds),
	}

# --------------------------------------------------
# PREBUILT BATTLE RUNNER (for max army scenario)
# --------------------------------------------------

static func _run_prebuilt(atk_side: Array, def_side: Array, seed_val: int, max_rounds: int = 30) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var def_k: float = BattleTuningProfile.get_instance().def_constant
	var type_adv: float = BattleTuningProfile.get_instance().type_advantage_mult
	var type_dis: float = BattleTuningProfile.get_instance().type_disadvantage_mult

	var turn_order: Array = []
	turn_order.append_array(atk_side)
	turn_order.append_array(def_side)
	for c in turn_order:
		c["spd_jitter"] = c["spd"] * 100 + rng.randi_range(0, 99)
	turn_order.sort_custom(func(a, b): return int(a["spd_jitter"]) > int(b["spd_jitter"]))

	var rounds: int = 0
	var stalemate: bool = false

	while true:
		rounds += 1
		if rounds > max_rounds:
			stalemate = true
			break
		for c in turn_order:
			c["spd_jitter"] = c["spd"] * 100 + rng.randi_range(0, 99)
		turn_order.sort_custom(func(a, b): return int(a["spd_jitter"]) > int(b["spd_jitter"]))
		for c in turn_order:
			if not c["alive"]: continue
			var enemies: Array = def_side if c["side"] == "attacker" else atk_side
			var target = null
			var best_hp: int = 9999
			for e in enemies:
				if e["alive"] and int(e["hp"]) < best_hp:
					best_hp = int(e["hp"])
					target = e
			if target == null: continue
			# --- Hit/miss roll ---
			var speed_pen: int = maxi(0, (int(target["spd"]) - int(c["spd"])) * 2)
			var hit_floor: int = 70 if bool(c.get("is_leader", false)) else 50
			var hit_chance: int = clampi(int(c["acc"]) - speed_pen - int(target["eva"]), hit_floor, 95)
			if rng.randi_range(1, 100) > hit_chance:
				continue  # miss
			# --- Sigil use: apply damage multiplier if SP available ---
			var dmg_mult: float = 1.0
			var sp_cost: int = int(c.get("sigil_sp_cost", 0))
			var sig_mult: float = float(c.get("sigil_dmg_mult", 0.0))
			if sp_cost > 0 and sig_mult > 1.0 and int(c.get("current_sp", 0)) >= sp_cost:
				dmg_mult = sig_mult
				c["current_sp"] = int(c["current_sp"]) - sp_cost
			var raw: float = float(c["atk"]) * dmg_mult * _type_mult_tuned(c["dtype"], target["dtype"], type_adv, type_dis) \
				* (1.0 - float(target["def"]) / (float(target["def"]) + def_k))
			var vr: int = maxi(1, int(raw * 0.15))
			var dmg: int = maxi(1, int(raw) + rng.randi_range(-vr, vr))
			target["hp"] -= dmg
			if target["hp"] <= 0:
				target["alive"] = false
		var atk_alive: bool = false
		var def_alive: bool = false
		for c in atk_side:
			if c["alive"]: atk_alive = true; break
		for c in def_side:
			if c["alive"]: def_alive = true; break
		if not atk_alive or not def_alive:
			break

	var atk_surv: int = 0
	var def_surv: int = 0
	for c in atk_side:
		if c["alive"]: atk_surv += 1
	for c in def_side:
		if c["alive"]: def_surv += 1

	return {
		"attacker_won": atk_surv > 0 and def_surv == 0,
		"defender_won": def_surv > 0 and atk_surv == 0,
		"stalemate": stalemate,
		"rounds": rounds,
		"atk_survivors": atk_surv,
		"def_survivors": def_surv,
	}

# --------------------------------------------------
# FULL SUITE
# --------------------------------------------------

static func run_full_suite(seeds: int = 20) -> Dictionary:
	return {
		"even_typical":       run_even_typical(seeds),
		"even_max":           run_even_max(seeds),
		"10pct_advantage":    run_10pct_advantage(seeds),
		"25pct_advantage":    run_25pct_advantage(seeds),
		"type_disadvantage":  run_type_disadvantage(seeds),
		"leader_duel":        run_leader_duel(seeds),
		"fortified_defense":  run_fortified_defense(seeds),
	}

# --------------------------------------------------
# SCORING
# --------------------------------------------------

static func score_results(results: Dictionary, profile: BattleTuningProfile) -> float:
	var score: float = 0.0

	var typical = results.get("even_typical", {})
	score -= abs(float(typical.get("attacker_win_rate", 0.5)) - 0.5) * 200.0
	score -= abs(float(typical.get("avg_rounds", profile.target_rounds_typical_even)) - profile.target_rounds_typical_even) * 20.0
	score -= float(typical.get("stalemate_rate", 0.0)) * 400.0

	var max_army = results.get("even_max", {})
	score -= abs(float(max_army.get("attacker_win_rate", 0.5)) - 0.5) * 200.0
	score -= abs(float(max_army.get("avg_rounds", profile.target_rounds_max_even)) - profile.target_rounds_max_even) * 15.0
	score -= float(max_army.get("stalemate_rate", 0.0)) * 400.0
	var adv10 = results.get("10pct_advantage", {})
	score -= abs(float(adv10.get("attacker_win_rate", 0.6)) - profile.target_win_rate_10pct_advantage) * 200.0

	var adv25 = results.get("25pct_advantage", {})
	score -= abs(float(adv25.get("attacker_win_rate", 0.8)) - profile.target_win_rate_25pct_advantage) * 300.0

	var type_dis = results.get("type_disadvantage", {})
	score -= maxf(0.0, float(type_dis.get("attacker_win_rate", 0.35)) - 0.40) * 400.0

	var duel = results.get("leader_duel", {})
	score -= abs(float(duel.get("avg_rounds", profile.target_rounds_leader_even)) - profile.target_rounds_leader_even) * 20.0

	# Fort defense: attacker should win 35-40% against fort level 2 equal army
	# Weighted strongly so fort_def_mult can't be sacrificed for other gains
	var fort_def = results.get("fortified_defense", {})
	score -= abs(float(fort_def.get("attacker_win_rate", 0.37)) - 0.37) * 300.0

	return score
