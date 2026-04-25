# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: BattleState
#
# Role:
# Holds all mutable tactical battle state.
#
# Allowed Interactions:
# - BattleUnit
# - GameState (read-only during battle setup)
#
# Forbidden Responsibilities:
# - Must not modify GameState
#
# Game Phase:
# Execution Phase (Battle Only)
# ==================================================

class_name BattleState

const BattleUnit = preload("res://Scripts/game/battle/battle_unit.gd")
const BattleTuningProfile = preload("res://Scripts/game/battle/battle_tuning_profile.gd")

var setup: Dictionary

var attacker_units: Array = []
var defender_units: Array = []
var rescue_ally_leader_ref = null  # set for hunt_rescue missions; checked for ally_survived

var turn_order: Array = []
var current_turn_index: int = 0

var round: int = 1
var phase: String = "setup"

var log: Array = []
var result: Dictionary = {}

var rng := RandomNumberGenerator.new()

var grid: Array = []

const GRID_COLS: int = 19
const GRID_ROWS: int = 11

func _init(setup_dict: Dictionary):
	setup = setup_dict
	rng.randomize()
	_init_grid()
	_build_units()
	_build_turn_order()


func _init_grid() -> void:
	grid.clear()
	for _x in range(GRID_COLS):
		var col: Array = []
		for _y in range(GRID_ROWS):
			col.append(null)
		grid.append(col)


func _build_units() -> void:
	var state: GameState = setup.get("state") if not (setup.get("state") is Dictionary) else null

	for leader in setup.get("attacker_leaders", []):
		if leader is Dictionary:
			_build_lab_side_units(leader, setup.get("attacker_units_override", []), "attacker", attacker_units)
		else:
			_build_side_units(state, leader, "attacker", attacker_units)

	for leader in setup.get("defender_leaders", []):
		if leader is Dictionary:
			_build_lab_side_units(leader, setup.get("defender_units_override", []), "defender", defender_units)
		else:
			_build_side_units(state, leader, "defender", defender_units)

	# Build rescue ally — fights on attacker side, pre-engaged with enemies
	var ally_tpl: Dictionary = {}
	if setup.has("ally_leader_template"):
		ally_tpl = setup.get("ally_leader_template", {}) as Dictionary
	if not ally_tpl.is_empty():
		var mock_ally = _MockLeader.new(ally_tpl)
		mock_ally.name = str(ally_tpl.get("display_name", "Rescue Ally"))
		var ally_unit = BattleUnit.new(null, mock_ally, "attacker", true)
		ally_unit.set_meta("is_rescue_ally", true)
		attacker_units.append(ally_unit)
		rescue_ally_leader_ref = ally_unit

	# Apply fort defense bonus to all defenders — flat % per fort level
	# Formula: final_defense += base_defense * (fort_level * fort_def_mult)
	# Fort 1 = +10%, Fort 2 = +20%, Fort 3 = +30%, etc. (at default mult 0.10)
	# Scales proportionally so high-def tanks get more bonus but low-def ranged stay fragile
	var fort_level: int = int(setup.get("fort_level", 0))
	if fort_level > 0:
		var fort_pct: float = float(fort_level) * BattleTuningProfile.get_instance().fort_def_mult
		for u in defender_units:
			if u != null:
				u.final_defense += int(float(u.final_defense) * fort_pct)


# Lab-mode builder — creates BattleUnits directly from plain Dictionaries
func _build_lab_side_units(leader_dict: Dictionary, unit_dicts: Array, side_name: String, out_array: Array) -> void:
	# Build a mock LeaderData-like object using a lightweight inner class
	var mock_leader = _MockLeader.new(leader_dict)
	# _no_leader_unit: placeholder used when mission has no enemy leader — skip the leader combatant
	if not bool(leader_dict.get("_no_leader_unit", false)):
		var bu := BattleUnit.new(null, mock_leader, side_name, true)
		bu.sprite_key = str(leader_dict.get("faction_key", ""))
		out_array.append(bu)
	for u in unit_dicts:
		if not (u is Dictionary):
			continue
		var mock_unit = _MockUnit.new(u)
		out_array.append(BattleUnit.new(mock_unit, mock_leader, side_name, false))


func _build_side_units(state: GameState, leader: LeaderData, side_name: String, out_array: Array) -> void:
	if leader == null:
		return

	# Leaders always fight for themselves, even with zero army units.
	var leader_bu := BattleUnit.new(null, leader, side_name, true)
	# story_id equals faction_key for story leaders (e.g. "house_crown")
	if leader.is_story_leader and leader.story_id != "":
		leader_bu.sprite_key = leader.story_id
	out_array.append(leader_bu)

	if state == null:
		return

	for uid_value in leader.army_unit_ids:
		var uid: int = int(uid_value)
		var unit: UnitData = state.get_unit(uid) as UnitData
		if unit == null:
			continue
		if not unit.is_alive():
			continue
		out_array.append(BattleUnit.new(unit, leader, side_name, false))


func _build_turn_order() -> void:
	turn_order.clear()
	for u in attacker_units:
		if u != null and bool(u.is_alive):
			turn_order.append(u)
	for u in defender_units:
		if u != null and bool(u.is_alive):
			turn_order.append(u)

	turn_order.sort_custom(func(a, b): return int(a.speed) > int(b.speed))


# --------------------------------------------------
# MOCK OBJECTS FOR BATTLE LAB (headless simulation)
# --------------------------------------------------

class _MockLeader:
	var id: int
	var name: String
	var attack: int
	var defense: int
	var leadership: int
	var level: int
	var hp: int
	var max_hp: int
	var damage_type: String
	var speed: int
	var accuracy: int
	var evasion: int
	var army_unit_ids: Array = []
	var equipped_item_id: String = ""

	func _init(d: Dictionary) -> void:
		id = int(d.get("id", randi()))
		name = str(d.get("name", "Lab Leader"))
		attack = int(d.get("attack", 16))
		defense = int(d.get("defense", 12))
		leadership = int(d.get("leadership", 10))
		level = int(d.get("level", 1))
		hp = int(d.get("hp", 65))
		max_hp = int(d.get("max_hp", 65))
		damage_type = str(d.get("damage_type", "slash"))
		speed = int(d.get("speed", 4))
		accuracy = int(d.get("accuracy", 72))
		evasion = int(d.get("evasion", 10))


class _MockUnit:
	var unit_id: int
	var unit_type: String
	var attack: int
	var defense: int
	var hp: int
	var max_hp: int
	var damage_type: String
	var tier: int
	var level: int
	var speed: int
	var accuracy: int
	var evasion: int
	var traits: Array = []
	var xp: int = 0
	var equipped_item_id: String = ""

	func is_alive() -> bool:
		return hp > 0

	func _init(d: Dictionary) -> void:
		unit_id = int(d.get("unit_id", randi()))
		unit_type = str(d.get("unit_type", "Lab Unit"))
		attack = int(d.get("attack", 13))
		defense = int(d.get("defense", 9))
		hp = int(d.get("hp", 35))
		max_hp = int(d.get("max_hp", hp))
		damage_type = str(d.get("damage_type", "slash"))
		tier = int(d.get("tier", 1))
		level = int(d.get("level", 1))
		speed = int(d.get("speed", 4))
		accuracy = int(d.get("accuracy", 75))
		evasion = int(d.get("evasion", 8))
		traits = d.get("traits", []) as Array
