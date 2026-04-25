# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: BattleUnit
#
# Role:
# Wraps UnitData or LeaderData for tactical battle without copying core data.
#
# Allowed Interactions:
# - BattleState
# - ItemLibrary
#
# Forbidden Responsibilities:
# - Must not modify GameState
# - Must not create or destroy units
#
# Game Phase:
# Execution Phase (Battle Only)
# ==================================================

class_name BattleUnit

const ItemLibrary = preload("res://Scripts/data/item_library.gd")

var unit_ref
var leader_ref
var is_leader_combatant: bool = false

var grid_pos := Vector2i(-1, -1)

var battle_hp: int = 0
var is_alive: bool = true

var acted: bool = false
var moved: bool = false
var is_defending: bool = false
var is_captured: bool = false
var has_retreated: bool = false  # true on successful retreat — not wounded on writeback
var retreat_attempts: int = 0    # increments on each failed retreat, boosts next attempt chance

var side: String = ""
var facing: String = "south"      # current facing direction for sprite rendering
var sprite_key: String = ""       # e.g. "house_crown" — set at init for leader units

var final_attack: int = 0
var final_defense: int = 0
var final_max_hp: int = 0
var final_accuracy: int = 75   # hit chance base before speed/evasion calc
var final_evasion: int = 8     # reduces attacker hit chance
var move_range: int = 3
var attack_range: int = 1
var speed: int = 1
var kills: int = 0
var current_sp: int = 10  # set in _init from level
var max_sp: int = 10      # set in _init from level

var disrupted: bool = false
var pinned: bool = false
var sigil_disabled: bool = false
var last_stand_triggered: bool = false
var riposte_active: bool = false
var delayed_strike_pending: bool = false

func _init(unit_data, leader_data, side_str: String, represent_leader: bool = false):
	unit_ref = unit_data
	leader_ref = leader_data
	is_leader_combatant = represent_leader
	side = side_str

	_apply_final_stats()
	battle_hp = final_max_hp

	# SP from spec: 10 + (level - 1) * 2
	var unit_level: int = 1
	if is_leader_combatant and leader_ref != null:
		unit_level = int(leader_ref.level)
	elif unit_ref != null:
		unit_level = int(unit_ref.level)
	max_sp = 10 + (unit_level - 1) * 2
	current_sp = max_sp


func _apply_final_stats() -> void:
	if is_leader_combatant:
		_apply_leader_stats()
		return

	if unit_ref == null:
		final_attack = 14
		final_defense = 8
		final_max_hp = 35
		final_accuracy = 75
		final_evasion = 8
		move_range = 3
		attack_range = 1
		speed = 1
		return

	var bonuses: Dictionary = {}
	var item_id: String = ""

	if "equipped_item_id" in unit_ref:
		item_id = str(unit_ref.equipped_item_id)

	bonuses = ItemLibrary.get_unit_item_bonuses(item_id)

	final_attack = int(unit_ref.attack) + int((bonuses.attack if "attack" in bonuses else 0))
	final_defense = int(unit_ref.defense) + int((bonuses.defense if "defense" in bonuses else 0))
	final_max_hp = int(unit_ref.hp) + int((bonuses.max_hp if "max_hp" in bonuses else 0))
	var item_sp: int = int(bonuses.get("max_sp", 0))
	if item_sp > 0:
		max_sp += item_sp
		current_sp = max_sp
	final_accuracy = int((unit_ref.accuracy if "accuracy" in unit_ref else 75))
	final_evasion = int((unit_ref.evasion if "evasion" in unit_ref else 8))
	# Evasive trait grants +10 evasion
	if "Evasive" in unit_ref.traits:
		final_evasion += 10

	move_range = _infer_move_range()
	attack_range = _infer_attack_range()
	speed = int((unit_ref.speed if "speed" in unit_ref else 4))


func _apply_leader_stats() -> void:
	if leader_ref == null:
		final_attack = 18
		final_defense = 12
		final_max_hp = 65
		final_accuracy = 72
		final_evasion = 10
		move_range = 3
		attack_range = 1
		speed = 2
		return

	# Leaders scale with their own stats + level bonus + equipped item
	var lvl: int = int(leader_ref.level)
	var item_id: String = str(leader_ref.equipped_item_id) if "equipped_item_id" in leader_ref else ""
	var bonuses: Dictionary = ItemLibrary.get_unit_item_bonuses(item_id)
	var item_atk: int = int(bonuses.get("attack", 0))
	var item_def: int = int(bonuses.get("defense", 0))
	var item_hp: int = int(bonuses.get("max_hp", 0))
	var item_sp: int = int(bonuses.get("max_sp", 0))
	final_attack = maxi(18, int(leader_ref.attack) + lvl) + item_atk
	final_defense = maxi(12, int(leader_ref.defense) + int(lvl * 0.5)) + item_def
	final_max_hp = maxi(65, 65 + lvl * 3 + int(leader_ref.defense)) + item_hp
	if item_sp > 0:
		max_sp += item_sp
		current_sp = max_sp
	final_accuracy = int((leader_ref.accuracy if "accuracy" in leader_ref else 72))
	final_evasion = int((leader_ref.evasion if "evasion" in leader_ref else 10))
	move_range = 3
	attack_range = 1
	speed = int((leader_ref.speed if "speed" in leader_ref else 4)) + int(lvl * 0.2)


func _infer_move_range() -> int:
	if unit_ref == null:
		return 3
	var unit_type: String = str(unit_ref.unit_type).to_lower()
	if "rider" in unit_type or "cavalry" in unit_type or "knight" in unit_type or "raider" in unit_type:
		return 4
	if "scout" in unit_type or "ambusher" in unit_type or "skirmisher" in unit_type:
		return 4
	if "pathfinder" in unit_type or "shadow" in unit_type:
		return 4
	return 3


func _infer_attack_range() -> int:
	if unit_ref == null:
		return 1
	var unit_type: String = str(unit_ref.unit_type).to_lower()
	# Tier 3 elite ranged — longest range
	if "sniper" in unit_type or "arbalest" in unit_type or "blizzard" in unit_type or "master ranger" in unit_type:
		return 3
	# Standard ranged — medium range
	if "archer" in unit_type or "crossbow" in unit_type or "ranger" in unit_type or "harpoon" in unit_type or "hunter" in unit_type:
		return 2
	# Short ranged
	if "reed" in unit_type or "marsh" in unit_type:
		return 2
	return 1


func get_display_name() -> String:
	if is_leader_combatant and leader_ref != null:
		return str(leader_ref.name)
	if unit_ref != null:
		return str(unit_ref.unit_type)
	return "Unknown"


var xp: int = 0
var level: int = 1


func get_equipped_sigil_id() -> String:
	if is_leader_combatant:
		if leader_ref != null:
			var sid = leader_ref.get("equipped_sigil_id")
			return str(sid) if sid != null and str(sid) != "" else ""
	else:
		if unit_ref != null:
			var sid = unit_ref.get("equipped_sigil_id")
			return str(sid) if sid != null and str(sid) != "" else ""
	return ""
