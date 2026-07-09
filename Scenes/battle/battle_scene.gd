# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: BattleScene
#
# Role:
# Minimal playable tactical battle scene for human-involved combat.
#
# Allowed Interactions:
# - BattleState
# - BattleGrid
# - BattleResolver
# - BattleAI
#
# Forbidden Responsibilities:
# - Must not modify GameState directly
# - Must not own campaign state
#
# Game Phase:
# Execution Phase (Battle Only)
# ==================================================

extends Node2D
class_name BattleScene

signal battle_finished(result: Dictionary)
signal battle_ended(result: Dictionary)  # fires when battle resolves, before scorecard close

const BattleStateScript = preload("res://Scripts/game/battle/battle_state.gd")
const DebugLogger = preload("res://Scripts/debug/debug_logger.gd")
const BattleResolverScript = preload("res://Scripts/game/battle/battle_resolver.gd")
const ItemLibrary = preload("res://Scripts/data/item_library.gd")
const BattleAIScript = preload("res://Scripts/game/battle/battle_ai.gd")
const SkillLibraryScript = preload("res://Scripts/game/battle/skill_library.gd")
const SigilLibraryScript = preload("res://Scripts/data/sigil_library.gd")

@onready var battle_grid = $CanvasLayer/BattleGrid
@onready var turn_label: Label        = $CanvasLayer/UI/TopBar/TopHBox/TurnLabel
@onready var info_label: Label        = $CanvasLayer/UI/TopBar/TopHBox/InfoLabel
@onready var log_label: RichTextLabel = $CanvasLayer/UI/LogPanel/LogLabel
@onready var scorecard_panel: PanelContainer = $CanvasLayer/Scorecard
# Left unit panel (friendly)
@onready var stat_panel: PanelContainer  = $CanvasLayer/UI/LeftUnitPanel
@onready var stat_label: RichTextLabel   = $CanvasLayer/UI/LeftUnitPanel/LeftHBox/LeftVBox/StatLabel
@onready var _left_unit_name: Label      = $CanvasLayer/UI/LeftUnitPanel/LeftHBox/LeftVBox/LeftUnitName
@onready var _left_hp_bar: ProgressBar   = $CanvasLayer/UI/LeftUnitPanel/LeftHBox/LeftVBox/LeftHPRow/LeftHPBar
@onready var _left_portrait: TextureRect = $CanvasLayer/UI/LeftUnitPanel/LeftHBox/LeftPortrait
# Right unit panel (enemy)
@onready var _right_unit_panel: PanelContainer = $CanvasLayer/UI/RightUnitPanel
@onready var _right_unit_name: Label           = $CanvasLayer/UI/RightUnitPanel/RightHBox/RightVBox/RightUnitName
@onready var _right_hp_bar: ProgressBar        = $CanvasLayer/UI/RightUnitPanel/RightHBox/RightVBox/RightHPRow/RightHPBar
@onready var _right_stat_label: RichTextLabel  = $CanvasLayer/UI/RightUnitPanel/RightHBox/RightVBox/RightStatLabel
@onready var _right_portrait: TextureRect      = $CanvasLayer/UI/RightUnitPanel/RightHBox/RightPortrait
# Action buttons — created dynamically in popup, stored for state queries
var move_button: Button    = null
var attack_button: Button  = null
var defend_button: Button  = null
var skill_button: Button   = null
var item_button: Button    = null
var skip_button: Button    = null
var retreat_button: Button = null

var state: BattleState = null
var current_unit = null
var selected_unit = null
var action_mode: String = "none"
var _is_animating: bool = false  # blocks input during walk animation
var _pending_skill: String = ""
var _battle_result: Dictionary = {}
var _player_side: String = "attacker"  # set from setup
var _buttons_wired: bool = false
var _action_popup: PanelContainer = null
var _facing_popup: PanelContainer  = null   # direction picker shown after a unit acts

# --------------------------------------------------
# DEPLOYMENT PHASE
# --------------------------------------------------
var _deployment_phase: bool = false
var _deploy_panel: Control = null
var _deploy_leaders_to_place: Array = []  # BattleUnit leaders queued for placement
var _deploy_selected_leader = null         # leader the player has clicked in the panel
var _deploy_occupied: Dictionary = {}      # cell → true, tracks all placed cells

func _ready() -> void:
	battle_grid.set_scene(self)
	battle_grid.walk_completed.connect(_on_walk_completed)
	_setup_atmosphere()
	# Side panels hidden until a unit is clicked
	stat_panel.visible        = false
	_right_unit_panel.visible = false

func _setup_atmosphere() -> void:
	# Slight cool ambient tint — makes the scene feel overcast/outdoor
	var mod := CanvasModulate.new()
	mod.color = Color(0.88, 0.90, 0.95)
	add_child(mod)
	# Moving cloud shadow overlay (CanvasLayer 30, above everything)
	var cloud_layer := CanvasLayer.new()
	cloud_layer.set_script(load("res://Visual/battle/BattleCloudLayer.gd"))
	add_child(cloud_layer)


func _unhandled_input(event: InputEvent) -> void:
	# Consume all unhandled mouse button events so they cannot pass through
	# to the campaign map scene that sits below the battle scene in the tree.
	if event is InputEventMouseButton:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_BACKSPACE or event.keycode == KEY_ESCAPE:
			if action_mode != "none":
				action_mode = "none"
				_pending_skill = ""
				battle_grid.clear_move_range()
				battle_grid.set_attack_range_cells([])
				info_label.text = "Action cancelled."
				_show_action_popup(current_unit)


func _process(_delta: float) -> void:
	# Track the unit every frame so the popup stays next to it during camera drag
	if _action_popup != null and is_instance_valid(_action_popup) and current_unit != null:
		_action_popup.position = _calc_popup_screen_pos()
	if _facing_popup != null and is_instance_valid(_facing_popup) and current_unit != null:
		_facing_popup.position = _calc_popup_screen_pos()


func _calc_popup_screen_pos() -> Vector2:
	# Recalculates every frame from the unit's current screen position.
	# This way the popup tracks the unit during camera drag.
	if current_unit == null:
		return Vector2(200.0, 200.0)
	var screen_pos: Vector2 = battle_grid.cell_to_screen(current_unit.grid_pos)
	var popup_h: float = 7 * 37.0 + 16.0  # 7 buttons × ~37px + padding
	const GAP := 10.0
	var px: float = screen_pos.x + 42.0 + GAP
	var py: float = screen_pos.y - 94.0 - popup_h
	return Vector2(px, py)


func _reposition_action_popup() -> void:
	if _action_popup == null or not is_instance_valid(_action_popup) or current_unit == null:
		return
	_action_popup.position = _calc_popup_screen_pos()


func _on_walk_completed(_unit) -> void:
	_is_animating = false
	_hide_action_popup()
	_hide_facing_picker()


var _setup_dict: Dictionary = {}

func setup_battle(setup_dict: Dictionary) -> void:
	_setup_dict = setup_dict
	state = BattleStateScript.new(setup_dict)
	var human_id: int = int(setup_dict.get("human_faction_id", -1))
	var atk_id: int = int(setup_dict.get("attacker_faction_id", -1))
	_player_side = "attacker" if human_id == atk_id else "defender"
	battle_grid.set_player_side(_player_side)
	battle_grid.set_units(state.attacker_units, state.defender_units)
	_wire_buttons()
	_update_button_state()
	var fort_level: int = int(setup_dict.get("fort_level", 0))
	if fort_level > 0:
		DebugLogger.log("event:battle_fort_bonus_applied", {
			"fort_level": fort_level,
			"def_bonus": fort_level * 10,
			"target_province": int(setup_dict.get("target_province_id", -1)),
		})
		_append_log("[color=cyan]Fort Lv%d — defenders +%d defense[/color]" % [fort_level, fort_level * 10])
	_begin_deployment()


# --------------------------------------------------
# DEPLOYMENT PHASE
# --------------------------------------------------

func _begin_deployment() -> void:
	_deployment_phase = true
	_deploy_occupied.clear()

	# Enemy auto-deploys on their side — opposite of the player
	# If player is attacker (left), enemy is defender (right, cols 10-18)
	# If player is defender (right), enemy is attacker (left, cols 0-8)
	var enemy_units: Array = state.defender_units if _player_side == "attacker" else state.attacker_units
	var enemy_side: String = "defender" if _player_side == "attacker" else "attacker"
	var enemy_leaders: Array = []
	for u in enemy_units:
		if u != null and bool(u.is_leader_combatant):
			enemy_leaders.append(u)

	for i in range(enemy_leaders.size()):
		var ldr = enemy_leaders[i]
		var center_row: int = [4, 9, 14][mini(i, 2)]
		var depth_offset: int = _get_playstyle_depth(ldr)
		# Enemy on right (defender side) starts at col 13; enemy on left (attacker side) starts at col 5
		var center_col: int
		if enemy_side == "defender":
			center_col = 13 + depth_offset
		else:
			center_col = 5 - depth_offset
		var center_cell := Vector2i(center_col, center_row)
		_place_formation(ldr, center_cell, enemy_units, enemy_side)

	# Leaderless enemies (e.g. tutorials) — place units directly in a column
	if enemy_leaders.is_empty():
		var base_col: int = 12 if enemy_side == "defender" else 6
		var row: int = 0
		for u in enemy_units:
			if u == null or not bool(u.is_alive):
				continue
			var placed: bool = false
			for try_row in range(BattleGrid.GRID_ROWS):
				var cell := Vector2i(base_col, (row + try_row) % BattleGrid.GRID_ROWS)
				if _try_place_unit(u, cell, enemy_side):
					placed = true
					break
			if placed:
				row += 1

	# Deploy zone is always the player's half
	# Attacker = left (cols 0-8), Defender = right (cols 10-18)
	battle_grid.set_divider_visible(true)
	var zone_cells: Array = []
	var zone_min: int = 0 if _player_side == "attacker" else 10
	var zone_max: int = 8 if _player_side == "attacker" else 18
	for x in range(zone_min, zone_max + 1):
		for y in range(0, BattleGrid.GRID_ROWS):
			var zc := Vector2i(x, y)
			if not _deploy_occupied.has(zc) and battle_grid.is_cell_passable(zc):
				zone_cells.append(zc)
	battle_grid.set_deploy_zone(zone_cells)

	# Collect player leaders to place
	var player_units: Array = state.attacker_units if _player_side == "attacker" else state.defender_units
	_deploy_leaders_to_place.clear()
	for u in player_units:
		if u != null and bool(u.is_leader_combatant):
			_deploy_leaders_to_place.append(u)

	_deploy_selected_leader = null
	_build_deploy_panel()
	battle_grid.queue_redraw()


func _get_playstyle_depth(leader_unit) -> int:
	# Returns column offset from the divider edge for this leader's starting depth
	# Attacker: higher = further from divider (deeper into own territory)
	# Defender: higher = further from divider (deeper into own territory)
	if leader_unit == null or leader_unit.leader_ref == null:
		return 1
	var playstyle: String = str(leader_unit.leader_ref.get("ai_playstyle") if "ai_playstyle" in leader_unit.leader_ref else "balanced").to_lower()
	match playstyle:
		"aggressive", "conquest", "expansionist":
			return 0  # at the new base col (13 / 5)
		"balanced", "opportunist", "calculated", "economic":
			return 1
		"defensive", "diplomatic", "fortify":
			return 2  # deepest — col 15 for defender, col 3 for attacker
	return 1


func _place_formation(leader_unit, center_cell: Vector2i, all_units: Array, side: String) -> void:
	# Collect the units belonging to this leader
	var leader_ref = leader_unit.leader_ref
	var my_units: Array = [leader_unit]
	for u in all_units:
		if u == null or bool(u.is_leader_combatant):
			continue
		if u.leader_ref == leader_ref:
			my_units.append(u)

	# Sort units into formation ranks based on role
	var front: Array = []   # tank, anti_cav — closest to enemy
	var mid: Array = []     # frontline, shock, cavalry
	var back: Array = []    # ranged, skirmisher

	for u in my_units:
		if bool(u.is_leader_combatant):
			continue
		var role: String = _get_unit_role(u)
		match role:
			"tank", "anti_cav":
				front.append(u)
			"ranged", "skirmisher":
				back.append(u)
			_:
				mid.append(u)

	# Column direction: attacker side moves right toward enemy (higher col = closer to divider)
	# Defender side moves left toward enemy (lower col = closer to divider)
	var front_col_offset: int = 2 if side == "attacker" else -2
	var mid_col_offset: int = 1 if side == "attacker" else -1
	var back_col_offset: int = -1 if side == "attacker" else 1

	# Place leader — search surrounding cells if center is blocked
	var leader_placed: bool = false
	var row_offsets: Array = [0, -1, 1, -2, 2, -3, 3, -4, 4]
	var col_deltas: Array = [0, -1, 1, -2, 2] if side == "attacker" else [0, 1, -1, 2, -2]
	for col_delta in col_deltas:
		if leader_placed:
			break
		for row_off in row_offsets:
			var try_cell := Vector2i(center_cell.x + col_delta, center_cell.y + row_off)
			if _try_place_unit(leader_unit, try_cell, side):
				leader_placed = true
				break
	# Use actual placed cell as anchor for ranks
	var anchor_cell: Vector2i = leader_unit.grid_pos if leader_placed else center_cell

	# Place formation ranks relative to where the leader actually landed
	_place_rank(front, Vector2i(anchor_cell.x + front_col_offset, anchor_cell.y), side)
	_place_rank(mid,   Vector2i(anchor_cell.x + mid_col_offset,   anchor_cell.y), side)
	_place_rank(back,  Vector2i(anchor_cell.x + back_col_offset,  anchor_cell.y), side)


func _place_rank(units: Array, anchor: Vector2i, side: String) -> void:
	var row_offsets: Array = [0, -1, 1, -2, 2, -3, 3, -4, 4]
	for u in units:
		var found: bool = false
		for offset in row_offsets:
			var candidate := Vector2i(anchor.x, anchor.y + offset)
			if _try_place_unit(u, candidate, side):
				found = true
				break
		if not found:
			# Fall back to adjacent columns, retreating away from the divider
			var col_deltas: Array = [-1, -2, -3] if side == "attacker" else [1, 2, 3]
			for col_delta in col_deltas:
				for offset in row_offsets:
					var candidate := Vector2i(anchor.x + col_delta, anchor.y + offset)
					if _try_place_unit(u, candidate, side):
						found = true
						break
				if found:
					break


func _try_place_unit(unit, cell: Vector2i, side: String = "") -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= BattleGrid.GRID_COLS or cell.y >= BattleGrid.GRID_ROWS:
		return false
	# Enforce side column boundaries — neither side crosses the divider
	if side == "attacker" and cell.x > 8:
		return false
	if side == "defender" and cell.x < 10:
		return false
	if _deploy_occupied.has(cell):
		return false
	if not battle_grid.is_cell_passable(cell):
		return false
	if _get_unit_at_cell(cell) != null:
		return false
	unit.grid_pos = cell
	_deploy_occupied[cell] = true
	return true


func _get_unit_role(unit) -> String:
	if unit == null or unit.unit_ref == null:
		return "frontline"
	var utype: String = str(unit.unit_ref.unit_type).to_lower()
	if "guard" in utype and ("mountain" in utype or "bog" in utype or "shield" in utype or "iron" in utype or "mire" in utype):
		return "tank"
	if "pike" in utype or "spear" in utype or "phalanx" in utype or "sentinel" in utype:
		return "anti_cav"
	if "archer" in utype or "crossbow" in utype or "ranger" in utype or "hunter" in utype \
			or "sniper" in utype or "harpoon" in utype or "harpooner" in utype or "blizzard" in utype \
			or "arbalest" in utype or "reed" in utype or "marsh" in utype:
		return "ranged"
	if "skirmisher" in utype or "ambusher" in utype or "pathfinder" in utype or "shadow" in utype or "stalker" in utype:
		return "skirmisher"
	if "rider" in utype or "cavalry" in utype or "knight" in utype or "raider" in utype or "scout" in utype or "warlord" in utype:
		return "cavalry"
	if "hammer" in utype or "breaker" in utype or "crusher" in utype or "brawler" in utype \
			or "stonebreaker" in utype or "titan" in utype or "boarding" in utype or "northern" in utype \
			or "war chief" in utype or "fist" in utype:
		return "shock"
	return "frontline"


func _build_deploy_panel() -> void:
	if _deploy_panel != null:
		_deploy_panel.queue_free()

	var scene := preload("res://Scenes/battle/deploy_panel.tscn")
	_deploy_panel = scene.instantiate()
	_deploy_panel.name = "DeployPanel"
	_deploy_panel.set_anchors_preset(Control.PRESET_CENTER)

	var hbox: HBoxContainer = _deploy_panel.get_node("VBox/LeaderButtons")

	for ldr_unit in _deploy_leaders_to_place:
		var ldr_name: String = ldr_unit.get_display_name() if ldr_unit.has_method("get_display_name") else "Leader"
		var btn := Button.new()
		btn.text = ldr_name
		btn.add_theme_font_size_override("font_size", 12)
		btn.custom_minimum_size = Vector2(130, 36)
		var captured: Object = ldr_unit
		btn.pressed.connect(func() -> void:
			_on_deploy_leader_selected(captured, btn)
		)
		hbox.add_child(btn)

	var auto_btn := Button.new()
	auto_btn.text = "Auto Deploy"
	auto_btn.add_theme_font_size_override("font_size", 12)
	auto_btn.custom_minimum_size = Vector2(120, 36)
	auto_btn.pressed.connect(_auto_deploy_player)
	hbox.add_child(auto_btn)

	var ready_btn := Button.new()
	ready_btn.text = "Ready"
	ready_btn.name = "ReadyBtn"
	ready_btn.add_theme_font_size_override("font_size", 12)
	ready_btn.custom_minimum_size = Vector2(90, 36)
	ready_btn.disabled = _deploy_leaders_to_place.size() > 0
	ready_btn.pressed.connect(_finish_deployment)
	hbox.add_child(ready_btn)

	$CanvasLayer/UI.add_child(_deploy_panel)


func _on_deploy_leader_selected(leader_unit, btn: Button) -> void:
	_deploy_selected_leader = leader_unit
	# Visually highlight selected button
	if _deploy_panel != null:
		var hbox = _deploy_panel.get_node_or_null("VBox/LeaderButtons")
		if hbox:
			for child in hbox.get_children():
				if child is Button:
					child.modulate = Color(1, 1, 1, 1)
	btn.modulate = Color(0.4, 1.0, 0.5, 1.0)
	_append_log("Click your side of the field to place %s" % _deploy_selected_leader.get_display_name())


func _auto_deploy_player() -> void:
	# Auto-place all remaining leaders using formation logic
	var player_units: Array = state.attacker_units if _player_side == "attacker" else state.defender_units
	var remaining := _deploy_leaders_to_place.duplicate()
	_deploy_leaders_to_place.clear()

	for i in range(remaining.size()):
		var ldr = remaining[i]
		var center_row: int = [5, 2, 8][mini(i, 2)]
		var depth_offset: int = _get_playstyle_depth(ldr)
		var center_col: int
		if _player_side == "attacker":
			center_col = clampi(8 - depth_offset, 1, 8)
		else:
			center_col = clampi(10 + depth_offset, 10, 17)
		var center_cell := Vector2i(center_col, center_row)
		_place_formation(ldr, center_cell, player_units, _player_side)

	_finish_deployment()


func _finish_deployment() -> void:
	_deployment_phase = false
	_deploy_selected_leader = null
	_deploy_leaders_to_place.clear()

	# Safety pass: any unit still at (0,0) that isn't actually supposed to be there
	# means placement failed entirely — force-place it in any valid cell on its side
	var all_units: Array = state.attacker_units + state.defender_units
	for u in all_units:
		if u == null or not bool(u.is_alive):
			continue
		if _deploy_occupied.has(u.grid_pos):
			continue  # already properly placed
		# Find any open valid cell on the unit's side
		var s: String = u.side
		var x_range: Array = range(0, 9) if s == "attacker" else range(10, 19)
		for col in x_range:
			var placed: bool = false
			for row in range(BattleGrid.GRID_ROWS):
				var fc := Vector2i(col, row)
				if _try_place_unit(u, fc, s):
					placed = true
					break
			if placed:
				break

	# Hide deployment UI
	if _deploy_panel != null:
		_deploy_panel.queue_free()
		_deploy_panel = null

	battle_grid.set_divider_visible(false)
	battle_grid.set_deploy_zone([])
	battle_grid.queue_redraw()
	_start_round()


func _place_units() -> void:
	pass  # Replaced by deployment system — kept as no-op for safety


func _wire_buttons() -> void:
	if _buttons_wired:
		return
	_buttons_wired = true
	scorecard_panel.get_node("VBox/CloseButton").pressed.connect(_on_scorecard_close_pressed)


func _refill_sp(unit) -> void:
	pass  # SP is fixed per battle — no regen. current_sp set at battle_unit init.


func _start_round() -> void:
	state.turn_order.clear()
	for unit in state.attacker_units:
		if unit != null and unit.is_alive:
			unit.acted = false
			unit.moved = false
			unit.is_defending = false
			_refill_sp(unit)
			state.turn_order.append(unit)
	for unit in state.defender_units:
		if unit != null and unit.is_alive:
			unit.acted = false
			unit.moved = false
			unit.is_defending = false
			_refill_sp(unit)
			state.turn_order.append(unit)

	state.turn_order.sort_custom(func(a, b): return int(a.speed) > int(b.speed))
	state.current_turn_index = 0
	_next_turn()


func _next_turn() -> void:
	if state == null:
		return

	while state.current_turn_index < state.turn_order.size():
		var unit = state.turn_order[state.current_turn_index]
		state.current_turn_index += 1
		if unit == null or not unit.is_alive or ("is_captured" in unit and bool(unit.is_captured)) or ("has_retreated" in unit and bool(unit.has_retreated)) or bool(unit.acted):
			continue
		current_unit = unit
		selected_unit = unit
		action_mode = "none"
		_pending_skill = ""
		# Reset per-turn sigil effects (buffs, control flags, delayed strike triggers)
		SkillLibraryScript.reset_turn_effects(unit)
		battle_grid.set_selected_unit(selected_unit)
		battle_grid.set_active_unit(current_unit)
		battle_grid.clear_move_range()
		_refresh_labels()
		_update_button_state()

		if unit.side == _player_side:
			_append_log("[color=cyan]Player turn:[/color] %s" % _unit_name(unit))
			info_label.text = "Current: %s" % _unit_name(unit)
			return

		_append_log("[color=orange]AI turn:[/color] %s" % _unit_name(unit))
		_run_ai_turn(unit)
		return

	state.round += 1
	_start_round()


# ==================================================
# TACTICAL AI SYSTEM
# --------------------------------------------------
# Evaluates battlefield state each turn and picks
# a situational tactic. Feels like a real opponent.
# ==================================================

func _run_ai_turn(unit) -> void:
	# --- Item use: heal self if badly hurt ---
	if unit.unit_ref != null and str(unit.unit_ref.equipped_item_id) != "":
		var hp_ratio: float = float(unit.battle_hp) / float(maxi(1, unit.final_max_hp))
		if hp_ratio < 0.4:
			var ai_item: Dictionary = ItemLibrary.get_item(str(unit.unit_ref.equipped_item_id))
			if str(ai_item.get("effect_type", "")) == "heal_hp":
				_use_item(unit)
				unit.acted = true
				call_deferred("_check_battle_end_or_continue")
				return

	# --- Build battlefield picture ---
	var snap := _ai_battlefield_snapshot(unit.side)

	# --- Leader retreat decision ---
	if bool(unit.is_leader_combatant):
		var hp_ratio: float = float(unit.battle_hp) / float(maxi(1, unit.final_max_hp))
		var losing_badly: bool = snap.ally_strength < snap.enemy_strength * 0.4
		var hopeless: bool = snap.enemy_strength > snap.ally_strength * 2.5 and snap.enemy_count > snap.ally_count

		# Hopeless check — but before retreating, evaluate if we can get a meaningful hit this round
		if hopeless:
			# Can we reach and kill or seriously wound a target?
			var kill_opportunity: bool = false
			for enemy in snap.enemies:
				if enemy == null or not bool(enemy.is_alive):
					continue
				var enemy_hp_ratio: float = float(enemy.battle_hp) / float(maxi(1, enemy.final_max_hp))
				var reachable: bool = _ai_can_attack(unit, enemy) or _distance(unit.grid_pos, enemy.grid_pos) <= int(unit.move_range) + 1
				# Worth swinging if enemy is already wounded (below 50% HP) and reachable
				if reachable and enemy_hp_ratio < 0.5:
					kill_opportunity = true
					break
			if kill_opportunity:
				# Fight this round, but mark intent to retreat — next round hopeless check will fire again
				DebugLogger.log("event:ai_tactical", {
					"unit": unit.get_display_name(),
					"decision": "hopeless_last_swing",
					"ally_strength": snap.ally_strength,
					"enemy_strength": snap.enemy_strength,
				})
				# Fall through to tactic execution — will try to hit before retreating next round
			else:
				# No kill opportunity — cut losses and run now
				DebugLogger.log("event:ai_tactical", {
					"unit": unit.get_display_name(),
					"decision": "retreat_hopeless",
					"ally_strength": snap.ally_strength,
					"enemy_strength": snap.enemy_strength,
					"hp_ratio": hp_ratio
				})
				_attempt_retreat(unit)
				unit.acted = true
				return

		# Standard retreat conditions (regardless of hopeless)
		var should_retreat: bool = (
			hp_ratio < 0.2 or
			(hp_ratio < 0.4 and snap.ally_count <= 1) or
			(hp_ratio < 0.5 and losing_badly)
		)
		if should_retreat:
			DebugLogger.log("event:ai_tactical", {
				"unit": unit.get_display_name(),
				"decision": "retreat",
				"ally_strength": snap.ally_strength,
				"enemy_strength": snap.enemy_strength,
				"hp_ratio": hp_ratio
			})
			_attempt_retreat(unit)
			unit.acted = true
			return

	# --- Pick tactic for this turn ---
	var tactic: String = _ai_choose_tactic(unit, snap)
	DebugLogger.log("event:ai_tactical", {"unit": unit.get_display_name(), "tactic": tactic, "round": state.round})

	# --- Execute tactic (async — animations play before continuing) ---
	match tactic:
		"protect_leader":
			await _ai_protect_leader(unit, snap)
		"hunt_leader":
			await _ai_attack_target(unit, snap.enemy_leader)
		"thin_ranks":
			await _ai_attack_priority(unit, snap.enemies, false)
		"flank":
			await _ai_flank(unit, snap)
		"finish_weak":
			await _ai_attack_priority(unit, snap.enemies, true)  # lowest HP first
		_:
			await _ai_attack_priority(unit, snap.enemies, false)

	unit.acted = true
	call_deferred("_check_battle_end_or_continue")


func _ai_battlefield_snapshot(side: String) -> Dictionary:
	var allies: Array = _get_ally_units(side)
	var enemies: Array = _get_enemy_units(side)

	var alive_allies := []
	var alive_enemies := []
	var ally_leader = null
	var enemy_leader = null
	var ally_strength: float = 0.0
	var enemy_strength: float = 0.0

	for u in allies:
		if u == null or not bool(u.is_alive) or ("is_captured" in u and bool(u.is_captured)):
			continue
		alive_allies.append(u)
		ally_strength += float(u.battle_hp) / float(maxi(1, u.final_max_hp)) * float(u.final_attack)
		if bool(u.is_leader_combatant):
			ally_leader = u

	for u in enemies:
		if u == null or not bool(u.is_alive) or ("is_captured" in u and bool(u.is_captured)):
			continue
		alive_enemies.append(u)
		enemy_strength += float(u.battle_hp) / float(maxi(1, u.final_max_hp)) * float(u.final_attack)
		if bool(u.is_leader_combatant):
			enemy_leader = u

	return {
		"allies": alive_allies,
		"enemies": alive_enemies,
		"ally_leader": ally_leader,
		"enemy_leader": enemy_leader,
		"ally_count": alive_allies.size(),
		"enemy_count": alive_enemies.size(),
		"ally_strength": ally_strength,
		"enemy_strength": enemy_strength,
	}


func _ai_choose_tactic(unit, snap: Dictionary) -> String:
	var ally_leader = snap.ally_leader
	var enemy_leader = snap.enemy_leader
	var round_num: int = int(state.round)

	# PROTECT LEADER — only when a non-leader enemy is directly adjacent to our leader
	# Leaders can handle other leaders themselves — this is for units screening the leader
	if ally_leader != null and not bool(unit.is_leader_combatant):
		for enemy in snap.enemies:
			if not bool(enemy.is_leader_combatant) and _distance(ally_leader.grid_pos, enemy.grid_pos) <= 1:
				return "protect_leader"

	# FINISH WEAK — opportunistic kill if any enemy is nearly dead and in range
	for enemy in snap.enemies:
		var hp_ratio: float = float(enemy.battle_hp) / float(maxi(1, enemy.final_max_hp))
		if hp_ratio < 0.3 and _distance(unit.grid_pos, enemy.grid_pos) <= maxi(1, int(unit.attack_range)):
			return "finish_weak"

	# HUNT LEADER — leaders only go after the enemy leader
	# Non-leader units always thin the ranks instead
	if bool(unit.is_leader_combatant) and enemy_leader != null:
		var all_enemies_are_leaders: bool = true
		for enemy in snap.enemies:
			if not bool(enemy.is_leader_combatant):
				all_enemies_are_leaders = false
				break
		var enemy_hp_ratio: float = float(enemy_leader.battle_hp) / float(maxi(1, enemy_leader.final_max_hp))
		var field_thinned: bool = snap.enemy_count <= snap.ally_count
		if all_enemies_are_leaders or field_thinned or enemy_hp_ratio < 0.65:
			return "hunt_leader"

	# FLANK — early game with ranged/mobile units, try to get angles
	if round_num <= 3 and int(unit.attack_range) > 1:
		return "flank"
	if round_num <= 2 and int(unit.move_range) >= 4:
		return "flank"

	# DEFAULT — thin the enemy ranks
	return "thin_ranks"


# Attempt to use equipped sigil if conditions are met
# Returns true if sigil was used (unit action consumed)
func _ai_try_use_sigil(unit, enemies: Array) -> bool:
	if unit == null or bool(unit.acted) or bool(unit.sigil_disabled):
		return false
	var sigil_id: String = ""
	if unit.has_method("get_equipped_sigil_id"):
		sigil_id = str(unit.get_equipped_sigil_id())
	if sigil_id == "":
		return false
	var sig: Dictionary = SigilLibraryScript.get_sigil(sigil_id)
	if sig.is_empty():
		return false
	var sp_cost: int = int(sig.get("sp_cost", 99))
	if int(unit.current_sp) < sp_cost:
		return false
	# Decide whether to use sigil based on situation
	var effect_type: String = str(sig.get("effect_type", ""))
	var target_type: String = str(sig.get("target_type", "enemy"))
	# Offensive sigils — use when we have a reachable target
	if target_type == "enemy":
		var best_target = null
		var best_score: float = -1.0
		for enemy in enemies:
			if enemy == null or not bool(enemy.is_alive):
				continue
			if not _ai_can_attack(unit, enemy):
				continue
			var score: float = _ai_target_score(unit, enemy, false)
			# Prefer finisher sigils on low-HP targets
			if effect_type == "finisher" and float(enemy.battle_hp) / float(maxi(1, enemy.final_max_hp)) > 0.30:
				continue  # finisher only worth it sub-30% HP
			if score > best_score:
				best_score = score
				best_target = enemy
		if best_target != null:
			_execute_skill(sigil_id, unit, best_target)
			return true
	# Defensive/self sigils — use when unit is below 50% HP
	elif target_type == "self":
		var hp_ratio: float = float(unit.battle_hp) / float(maxi(1, unit.final_max_hp))
		if hp_ratio < 0.50:
			_execute_skill(sigil_id, unit, unit)
			return true
	# Heal/support sigils — use on lowest-HP ally below 60% HP
	elif target_type == "ally":
		var allies: Array = _get_ally_units(unit.side)
		var worst_ally = null
		var worst_ratio: float = 0.60
		for ally in allies:
			if ally == null or not bool(ally.is_alive) or ally == unit:
				continue
			var ratio: float = float(ally.battle_hp) / float(maxi(1, ally.final_max_hp))
			if ratio < worst_ratio:
				worst_ratio = ratio
				worst_ally = ally
		if worst_ally != null:
			_execute_skill(sigil_id, unit, worst_ally)
			return true
	return false


func _ai_attack_priority(unit, enemies: Array, lowest_hp_first: bool) -> void:
	# Score all reachable enemies and pick best target
	var best_target = null
	var best_score: float = -1.0

	for enemy in enemies:
		if enemy == null or not bool(enemy.is_alive):
			continue
		if not _ai_can_attack(unit, enemy):
			continue
		var score: float = _ai_target_score(unit, enemy, lowest_hp_first)
		if score > best_score:
			best_score = score
			best_target = enemy

	if best_target != null:
		# Try sigil first — offensive sigils are used before normal attack
		if not _ai_try_use_sigil(unit, enemies):
			_do_attack(unit, best_target)
			await get_tree().create_timer(1.3).timeout
		return

	# No target in range — move toward nearest enemy first, then re-check
	var moved: bool = _ai_move_smart(unit, enemies)
	if moved:
		await battle_grid.walk_completed

	# After moving, re-check if we can now attack
	best_target = null
	best_score = -1.0
	for enemy in enemies:
		if enemy == null or not bool(enemy.is_alive):
			continue
		if not _ai_can_attack(unit, enemy):
			continue
		var score: float = _ai_target_score(unit, enemy, lowest_hp_first)
		if score > best_score:
			best_score = score
			best_target = enemy
	if best_target != null:
		_do_attack(unit, best_target)
		await get_tree().create_timer(1.3).timeout


func _ai_attack_target(unit, target) -> void:
	if target == null:
		var moved: bool = _ai_move_smart(unit, _get_enemy_units(unit.side))
		if moved:
			await battle_grid.walk_completed
		return
	if _ai_can_attack(unit, target):
		if not _ai_try_use_sigil(unit, [target]):
			_do_attack(unit, target)
			await get_tree().create_timer(1.3).timeout
	else:
		var moved: bool = _ai_move_toward(unit, target.grid_pos)
		if moved:
			await battle_grid.walk_completed
		# After moving, re-check if now in range
		if _ai_can_attack(unit, target):
			if not _ai_try_use_sigil(unit, [target]):
				_do_attack(unit, target)
				await get_tree().create_timer(1.3).timeout


func _ai_protect_leader(unit, snap: Dictionary) -> void:
	# Move to intercept the closest threatening enemy to our leader
	if snap.ally_leader == null:
		await _ai_attack_priority(unit, snap.enemies, false)
		return
	var leader_pos: Vector2i = snap.ally_leader.grid_pos
	var closest_threat = null
	var closest_dist: int = 999
	for enemy in snap.enemies:
		if enemy == null or not bool(enemy.is_alive):
			continue
		var d: int = _distance(enemy.grid_pos, leader_pos)
		if d < closest_dist:
			closest_dist = d
			closest_threat = enemy
	if closest_threat != null:
		if _ai_can_attack(unit, closest_threat):
			_do_attack(unit, closest_threat)
			await get_tree().create_timer(1.3).timeout
		else:
			# Move directly toward the threat to intercept it
			var moved: bool = _ai_move_toward(unit, closest_threat.grid_pos)
			if moved:
				await battle_grid.walk_completed
			# After moving, attack if now in range
			if _ai_can_attack(unit, closest_threat):
				_do_attack(unit, closest_threat)
				await get_tree().create_timer(1.3).timeout


func _ai_flank(unit, snap: Dictionary) -> void:
	# Try to get to a position that has LOS to an enemy without being in the thick of it
	var enemies: Array = snap.enemies
	if enemies.is_empty():
		return
	# Find enemy furthest from the main cluster
	var best_pos: Vector2i = unit.grid_pos
	var best_score: float = -1.0
	for x in range(BattleGrid.GRID_COLS):
		for y in range(BattleGrid.GRID_ROWS):
			var cell := Vector2i(x, y)
			if not _cell_is_free(cell):
				continue
			if _distance(unit.grid_pos, cell) > int(unit.move_range):
				continue
			# Score = number of enemies we'd have LOS to from here
			var los_count: int = 0
			for enemy in enemies:
				if enemy == null or not bool(enemy.is_alive):
					continue
				if _distance(cell, enemy.grid_pos) <= int(unit.attack_range):
					if battle_grid.has_line_of_sight(cell, enemy.grid_pos):
						los_count += 1
			if float(los_count) > best_score:
				best_score = float(los_count)
				best_pos = cell
	if best_pos != unit.grid_pos:
		var from_pos: Vector2i = unit.grid_pos
		unit.grid_pos = best_pos
		unit.moved = true
		battle_grid.start_walk(unit, from_pos, best_pos)
		await battle_grid.walk_completed
	# Then attack if possible
	await _ai_attack_priority(unit, enemies, false)


func _ai_can_attack(unit, target) -> bool:
	if target == null or not bool(target.is_alive):
		return false
	var in_range: bool = _distance(unit.grid_pos, target.grid_pos) <= maxi(1, int(unit.attack_range))
	if not in_range:
		return false
	if int(unit.attack_range) > 1 and not battle_grid.has_line_of_sight(unit.grid_pos, target.grid_pos):
		return false
	return true


func _ai_target_score(unit, target, lowest_hp_first: bool) -> float:
	var score: float = 0.0
	# HP weight — prefer low HP targets for kills
	var hp_ratio: float = float(target.battle_hp) / float(maxi(1, target.final_max_hp))
	if lowest_hp_first:
		score += (1.0 - hp_ratio) * 100.0
	else:
		score += (1.0 - hp_ratio) * 40.0
	# Leader bonus — leaders are high value
	if bool(target.is_leader_combatant):
		score += 30.0
	# Distance penalty — prefer closer targets
	score -= float(_distance(unit.grid_pos, target.grid_pos)) * 5.0
	# Hit chance bonus — prefer targets we can reliably hit
	# Low evasion or slow targets are easier to land hits on
	var atk_spd: int = int(unit.speed)
	var def_spd: int = int(target.speed)
	var speed_pen: int = maxi(0, (def_spd - atk_spd) * 2)
	var hit_floor: int = 70 if bool(unit.is_leader_combatant) else 50
	var hit_chance: int = clampi(int(unit.final_accuracy) - speed_pen - int(target.final_evasion), hit_floor, 95)
	# Add up to 20 points for a reliable hit, subtract up to 10 for a likely miss
	score += (float(hit_chance) - 70.0) * 0.4
	return score


func _ai_move_smart(unit, enemies: Array) -> bool:
	# Move toward best reachable attack position
	var nearest = null
	var nearest_dist: int = 999
	for enemy in enemies:
		if enemy == null or not bool(enemy.is_alive):
			continue
		var d: int = _distance(unit.grid_pos, enemy.grid_pos)
		if d < nearest_dist:
			nearest_dist = d
			nearest = enemy
	if nearest != null:
		return _ai_move_toward(unit, nearest.grid_pos)
	return false


func _ai_move_toward(unit, target_pos: Vector2i) -> bool:
	if unit.moved:
		return false
	var best_pos: Vector2i = unit.grid_pos
	var best_dist: int = _distance(unit.grid_pos, target_pos)
	# Prefer landing adjacent to target (distance 1) over just getting closer
	var found_adjacent: bool = false
	for x in range(BattleGrid.GRID_COLS):
		for y in range(BattleGrid.GRID_ROWS):
			var cell := Vector2i(x, y)
			if not _cell_is_free(cell):
				continue
			if _distance(unit.grid_pos, cell) > int(unit.move_range):
				continue
			var d: int = _distance(cell, target_pos)
			if d == 1 and not found_adjacent:
				found_adjacent = true
				best_pos = cell
				best_dist = 1
			elif d == 1 and found_adjacent:
				if _distance(unit.grid_pos, cell) < _distance(unit.grid_pos, best_pos):
					best_pos = cell
			elif not found_adjacent and d < best_dist:
				best_dist = d
				best_pos = cell
	if best_pos != unit.grid_pos:
		var from_pos: Vector2i = unit.grid_pos
		unit.grid_pos = best_pos
		unit.moved = true
		battle_grid.start_walk(unit, from_pos, best_pos)
		return true
	return false


func _get_ally_units(side: String) -> Array:
	return state.attacker_units if side == "attacker" else state.defender_units


func _move_toward_nearest_enemy(unit) -> void:
	_ai_move_smart(unit, _get_enemy_units(unit.side))


func _on_move_pressed() -> void:
	if not _is_player_turn() or current_unit == null:
		return
	if current_unit.acted:
		info_label.text = "This unit already acted."
		return
	if current_unit.moved:
		info_label.text = "This unit already moved."
		return
	action_mode = "move"
	info_label.text = "Select a tile to move to."
	battle_grid.set_attack_range_cells([])
	battle_grid.set_move_range_cells(_compute_move_cells(current_unit))
	_hide_action_popup()


func _on_attack_pressed() -> void:
	if not _is_player_turn() or current_unit == null:
		return
	if current_unit.acted:
		info_label.text = "This unit already acted."
		return
	action_mode = "attack"
	info_label.text = "Select an enemy to attack."
	battle_grid.set_attack_range_cells(_compute_attack_cells(current_unit))
	_hide_action_popup()


func _on_defend_pressed() -> void:
	if not _is_player_turn() or current_unit == null or current_unit.acted:
		return
	current_unit.is_defending = true
	current_unit.acted = true
	action_mode = "none"
	_hide_action_popup()
	_append_log("%s defends." % _unit_name(current_unit))
	_show_facing_picker(current_unit)


func _on_skill_pressed() -> void:
	DebugLogger.log("event:skill_btn_pressed", {"is_player_turn": _is_player_turn(), "has_unit": current_unit != null})
	if not _is_player_turn() or current_unit == null or current_unit.acted:
		DebugLogger.log("event:skill_blocked", {"reason": "turn_or_acted"})
		return
	var sp: int = int(current_unit.current_sp)
	DebugLogger.log("event:skill_sp", {"sp": sp})
	if sp <= 0:
		info_label.text = "No SP remaining."
		return
	var skills: Array[String] = []
	if SkillLibraryScript != null:
		skills = SkillLibraryScript.get_unit_skills(current_unit)
	DebugLogger.log("event:skill_list", {"count": skills.size()})
	if skills.is_empty():
		info_label.text = "No Sigils equipped."
		return
	_open_skill_picker(skills)


func _open_skill_picker(skills: Array[String]) -> void:
	var old := $CanvasLayer.get_node_or_null("SkillPicker")
	if old != null:
		old.queue_free()

	var scene := preload("res://Scenes/battle/skill_picker.tscn")
	var picker: PanelContainer = scene.instantiate()
	picker.name = "SkillPicker"

	var hdr: Label = picker.get_node("VBoxContainer/Header")
	var _sp: int = int(current_unit.current_sp)
	var _max_sp: int = int(current_unit.max_sp) if "max_sp" in current_unit else 10
	hdr.text = "Sigils  (SP: %d/%d)" % [_sp, _max_sp]

	var skill_list: VBoxContainer = picker.get_node("VBoxContainer/SkillList")
	for skill_id in skills:
		var display_name: String = SkillLibraryScript.get_skill_display_name(skill_id)
		var desc: String = SkillLibraryScript.get_skill_description(skill_id)
		var cost: int = SkillLibraryScript.get_skill_sp_cost(skill_id, current_unit)
		var full_action: bool = SkillLibraryScript.is_full_action(skill_id, current_unit)
		var can_use: bool = int(current_unit.current_sp) >= cost and not current_unit.disrupted

		var row := VBoxContainer.new()
		var btn := Button.new()
		btn.text = "%s  (%d SP)%s" % [display_name, cost, "  [FULL]" if full_action else ""]
		btn.add_theme_font_size_override("font_size", 11)
		btn.disabled = not can_use

		var desc_lbl := Label.new()
		desc_lbl.text = desc
		desc_lbl.add_theme_font_size_override("font_size", 9)
		desc_lbl.add_theme_color_override("font_color",
			Color(0.7, 0.7, 0.8) if can_use else Color(0.45, 0.45, 0.5))
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD

		var c_skill: String = skill_id
		if can_use:
			btn.pressed.connect(func() -> void:
				picker.queue_free()
				_on_skill_selected(c_skill)
			)
		row.add_child(btn)
		row.add_child(desc_lbl)
		skill_list.add_child(row)

	var cancel: Button = picker.get_node("VBoxContainer/CancelButton")
	cancel.pressed.connect(func() -> void: picker.queue_free())

	$CanvasLayer.add_child(picker)
	picker.position = Vector2(500, 150)


func _on_skill_selected(skill_name: String) -> void:
	if current_unit == null or not current_unit.is_alive:
		return

	# Full Action — disable move button
	if SkillLibraryScript.is_full_action(skill_name, current_unit):
		if move_button != null:
			move_button.disabled = true
		current_unit.moved = true  # prevent movement after full action

	# AOE — no target click needed, fire immediately
	if SkillLibraryScript.is_aoe(skill_name):
		_show_skill_range(skill_name, false)
		_execute_skill(skill_name, current_unit, null)
		return

	# Self-targeting — fire immediately
	if not SkillLibraryScript.needs_target(skill_name):
		_execute_skill(skill_name, current_unit, null)
		return

	# Targeted — show highlight and wait for grid click
	# Determine target type from sigil data
	var sig_data: Dictionary = SigilLibraryScript.get_signature_ability(skill_name)
	if sig_data.is_empty():
		sig_data = SigilLibraryScript.get_sigil(skill_name)
	var ttype: String = str(sig_data.get("target_type", "enemy"))
	var is_ally: bool = ttype == "ally"
	_show_skill_range(skill_name, is_ally)

	action_mode = "skill"
	_pending_skill = skill_name
	if is_ally:
		info_label.text = "%s: select a green ally." % SkillLibraryScript.get_skill_display_name(skill_name)
	else:
		info_label.text = "%s: select a purple enemy." % SkillLibraryScript.get_skill_display_name(skill_name)


func _show_skill_range(skill_name: String, ally_mode: bool) -> void:
	var cells: Array = []
	if current_unit == null:
		return
	var range_val: int = SkillLibraryScript.get_skill_range(skill_name, current_unit)
	var my_side: String = str(current_unit.side)
	var all_units: Array = (state.attacker_units if my_side == "attacker" else state.defender_units)
	var enemies: Array = (state.defender_units if my_side == "attacker" else state.attacker_units)
	var check_pool: Array = all_units if ally_mode else enemies

	for u in check_pool:
		if u == null or not bool(u.is_alive) or ("is_captured" in u and bool(u.is_captured)):
			continue
		if u == current_unit:
			continue
		var dist: int = abs(u.grid_pos.x - current_unit.grid_pos.x) + abs(u.grid_pos.y - current_unit.grid_pos.y)
		if dist <= range_val:
			cells.append(u.grid_pos)

	battle_grid.set_skill_range_cells(cells, ally_mode)


func _execute_skill(skill_name: String, user, target) -> void:
	var cost: int = SkillLibraryScript.get_skill_sp_cost(skill_name, user)
	user.current_sp = maxi(0, int(user.current_sp) - cost)

	var result: Dictionary = SkillLibraryScript.execute(skill_name, user, target, state)

	DebugLogger.log("event:battle_skill", {
		"skill": skill_name,
		"user": user.get_display_name(),
		"target": result.get("target", ""),
		"effect": result.get("effect", ""),
		"sp_cost": cost,
		"sp_remaining": int(user.current_sp),
		"round": int(state.round),
		"side": str(user.side),
	})

	_spawn_float_text(user.grid_pos, "-%d SP" % cost, Color(0.8, 0.5, 1.0))

	var effect: String = str(result.get("effect", ""))
	if result.has("damage"):
		var tgt_pos = target.grid_pos if target != null else user.grid_pos
		_spawn_float_text(tgt_pos, "-%d" % int(result["damage"]), Color(1.0, 0.3, 0.3))
	if result.has("healed"):
		var tgt_pos = target.grid_pos if target != null else user.grid_pos
		_spawn_float_text(tgt_pos, "+%d HP" % int(result["healed"]), Color(0.3, 1.0, 0.5))
	if result.has("lifesteal"):
		_spawn_float_text(user.grid_pos, "+%d" % int(result["lifesteal"]), Color(0.5, 1.0, 0.7))
	if effect == "buff_attack":
		_spawn_float_text(user.grid_pos, "ATK UP", Color(1.0, 0.85, 0.3))
	if effect == "buff_defense":
		_spawn_float_text(user.grid_pos, "DEF UP", Color(0.5, 0.8, 1.0))
	if effect == "marked" and target != null:
		_spawn_float_text(target.grid_pos, "Marked!", Color(0.9, 0.4, 1.0))
	if effect == "disrupt" and target != null:
		_spawn_float_text(target.grid_pos, "Disrupted!", Color(0.8, 0.5, 1.0))
	if effect == "pinned" and target != null:
		_spawn_float_text(target.grid_pos, "Pinned!", Color(0.8, 0.7, 0.3))
	if effect == "riposte_ready":
		_spawn_float_text(user.grid_pos, "Riposte!", Color(0.6, 0.9, 1.0))
	if effect == "last_stand":
		_spawn_float_text(user.grid_pos, "Last Stand!", Color(1.0, 0.6, 0.1))
	if effect == "delayed_strike":
		_spawn_float_text(user.grid_pos, "Delayed...", Color(0.9, 0.5, 0.2))
	if effect == "force_engage" and target != null:
		_spawn_float_text(target.grid_pos, "Forced!", Color(0.8, 0.5, 1.0))
	if result.get("aoe_sweep", false):
		_spawn_float_text(user.grid_pos, "Sweep!", Color(1.0, 0.7, 0.2))

	if int(result.get("xp_gained", 0)) > 0:
		_apply_battle_xp(user, int(result["xp_gained"]))

	if bool(result.get("killed", false)) and target != null:
		_spawn_float_text(target.grid_pos, "KO", Color(1.0, 0.5, 0.0))

	battle_grid.set_skill_range_cells([], false)
	current_unit.acted = true
	action_mode = "none"
	_pending_skill = ""
	_show_facing_picker(current_unit)


func _on_item_pressed() -> void:
	if not _is_player_turn() or current_unit == null or current_unit.acted:
		return
	_use_item(current_unit)
	_show_facing_picker(current_unit)


func _use_item(unit) -> void:
	if unit == null or unit.unit_ref == null:
		info_label.text = "No item equipped."
		return
	var item_id: String = str(unit.unit_ref.equipped_item_id)
	if item_id == "":
		info_label.text = "No item equipped."
		return
	var item: Dictionary = ItemLibrary.get_item(item_id)
	if item.is_empty():
		info_label.text = "Unknown item."
		return
	if not bool(item.get("is_consumable", false)):
		info_label.text = "%s is equipment - passive bonus only." % str(item.get("name", item_id))
		return
	var effect: String = str(item.get("effect_type", ""))
	var value: int = int(item.get("effect_value", 0))
	if effect == "heal_hp":
		var healed: int = mini(value, int(unit.final_max_hp) - int(unit.battle_hp))
		unit.battle_hp = mini(int(unit.battle_hp) + value, int(unit.final_max_hp))
		_append_log("%s used %s - healed %d HP." % [_unit_name(unit), str(item.get("name", item_id)), healed])
		_spawn_float_text(unit.grid_pos, "+%d HP" % healed, Color(0.2, 1.0, 0.4))
	else:
		info_label.text = "Item has no battle effect."
		return
	unit.unit_ref.equipped_item_id = ""
	unit.acted = true
	action_mode = "none"
	battle_grid.queue_redraw()


func _on_skip_pressed() -> void:
	if not _is_player_turn() or current_unit == null or current_unit.acted:
		return
	current_unit.acted = true
	action_mode = "none"
	_hide_action_popup()
	_append_log("%s skips." % _unit_name(current_unit))
	_show_facing_picker(current_unit)


func _on_retreat_pressed() -> void:
	if not _is_player_turn() or current_unit == null or current_unit.acted:
		return
	if not bool(current_unit.is_leader_combatant):
		info_label.text = "Only leaders can retreat."
		return
	_hide_action_popup()
	_attempt_retreat(current_unit)


func _attempt_retreat(unit) -> void:
	# Base chance: clamp(leadership * 5, 10, 90)
	# Each failed attempt adds +15%, capped at 95
	var leadership: int = 5
	if unit.leader_ref != null:
		leadership = int(unit.leader_ref.leadership)
	var base_chance: int = clampi(leadership * 5, 10, 90)
	var prior_failures: int = int(unit.retreat_attempts)
	var retreat_chance: int = clampi(base_chance + prior_failures * 15, base_chance, 95)
	var roll: int = state.rng.randi_range(1, 100)
	var success: bool = roll <= retreat_chance

	DebugLogger.log("event:battle_retreat_attempt", {
		"round": int(state.round),
		"unit_name": _unit_name(unit),
		"side": str(unit.side),
		"leadership": leadership,
		"base_chance": base_chance,
		"retreat_chance": retreat_chance,
		"prior_failures": prior_failures,
		"roll": roll,
		"success": success,
	})

	if success:
		var same_side: Array = state.attacker_units if unit.side == "attacker" else state.defender_units
		var same_leader_units: Array = []
		var capturable: Array = []
		for u in same_side:
			if u == null or not bool(u.is_alive):
				continue
			if unit.leader_ref == null or u.leader_ref == null:
				continue
			if int(u.leader_ref.id) != int(unit.leader_ref.id):
				continue
			same_leader_units.append(u)
			if not bool(u.is_leader_combatant) and u != unit:
				capturable.append(u)

		var captured_name: String = ""
		var left_behind = null
		if not capturable.is_empty():
			var idx: int = state.rng.randi_range(0, capturable.size() - 1)
			left_behind = capturable[idx]
			left_behind.is_captured = true
			captured_name = _unit_name(left_behind)
			DebugLogger.log("event:battle_unit_captured", {
				"round": int(state.round),
				"unit_name": captured_name,
				"side": str(left_behind.side),
				"grid_pos": [int(left_behind.grid_pos.x), int(left_behind.grid_pos.y)],
			})
			_append_log("[color=yellow]%s left behind (captured).[/color]" % captured_name)

		for retreating_unit in same_leader_units:
			if retreating_unit == left_behind:
				continue
			retreating_unit.has_retreated = true
			retreating_unit.acted = true
			_remove_unit_from_battle(retreating_unit)

		_append_log("[color=cyan]%s retreated successfully.[/color]" % _unit_name(unit))
		DebugLogger.log("event:battle_leader_retreated", {
			"round": int(state.round),
			"unit_name": _unit_name(unit),
			"side": str(unit.side),
			"captured_unit": captured_name,
			"retreated_count": int(maxi(0, same_leader_units.size() - (1 if left_behind != null else 0))),
		})
	else:
		# Failure: leader stays on grid, loses their turn — but next attempt will be easier
		unit.retreat_attempts = int(unit.retreat_attempts) + 1
		unit.acted = true
		_append_log("[color=red]%s failed to retreat![/color]" % _unit_name(unit))
		DebugLogger.log("event:battle_retreat_failed", {
			"round": int(state.round),
			"unit_name": _unit_name(unit),
			"side": str(unit.side),
			"hp_remaining": int(unit.battle_hp),
			"next_retreat_chance": clampi(clampi(int(unit.leader_ref.leadership if unit.leader_ref != null else 5) * 5, 10, 90) + unit.retreat_attempts * 15, 10, 95),
		})

	action_mode = "none"
	_check_battle_end_or_continue()


func on_grid_clicked(cell: Vector2i) -> void:
	if _is_animating:
		return
	# --- Deployment phase ---
	if _deployment_phase:
		if _deploy_selected_leader == null:
			return
		# Must click on player's side (cols 0-5 for attacker, cols 7-12 for defender)
		var valid_col: bool = (cell.x <= 8) if _player_side == "attacker" else (cell.x >= 10)
		if not valid_col:
			_append_log("Place units on your side of the divider.")
			return
		if _deploy_occupied.has(cell):
			_append_log("That cell is occupied.")
			return
		if not battle_grid.is_cell_passable(cell):
			_append_log("Can't deploy on impassable terrain.")
			return
		# Place the selected leader + formation
		var player_units: Array = state.attacker_units if _player_side == "attacker" else state.defender_units
		_place_formation(_deploy_selected_leader, cell, player_units, _player_side)
		_deploy_leaders_to_place.erase(_deploy_selected_leader)
		_deploy_selected_leader = null
		# Refresh deploy zone
		var zone_cells: Array = []
		var max_col: int = 8 if _player_side == "attacker" else 18
		var min_col: int = 0 if _player_side == "attacker" else 10
		for x in range(min_col, max_col + 1):
			for y in range(0, BattleGrid.GRID_ROWS):
				var zc := Vector2i(x, y)
				if not _deploy_occupied.has(zc) and battle_grid.is_cell_passable(zc):
					zone_cells.append(zc)
		battle_grid.set_deploy_zone(zone_cells)
		battle_grid.queue_redraw()
		# Rebuild panel to update button states
		_build_deploy_panel()
		# If all leaders placed, enable Ready button automatically
		if _deploy_leaders_to_place.is_empty():
			_append_log("All leaders placed. Press Ready to begin!")
		return

	if not _is_player_turn() or current_unit == null:
		var any_unit = _get_unit_at_cell(cell)
		if any_unit != null:
			selected_unit = any_unit
			battle_grid.set_selected_unit(selected_unit)
			if any_unit.side == _player_side:
				_show_stat_panel(any_unit)
				_hide_enemy_panel()
			else:
				_show_enemy_panel(any_unit)
		else:
			_hide_stat_panel()
			_hide_enemy_panel()
		return

	if action_mode == "move":
		if current_unit.moved:
			action_mode = "none"
			info_label.text = "This unit already moved."
			return
		if _cell_is_free(cell) and _distance(current_unit.grid_pos, cell) <= maxi(1, int(current_unit.move_range)):
			var from_cell: Vector2i = current_unit.grid_pos
			current_unit.facing = _facing_from_move(from_cell, cell)
			current_unit.grid_pos = cell
			current_unit.moved = true
			action_mode = "none"
			info_label.text = "Moved. Choose action."
			battle_grid.clear_move_range()
			_is_animating = true
			battle_grid.start_walk(current_unit, from_cell, cell)
			battle_grid.queue_redraw()
		else:
			info_label.text = "Invalid move tile."
		return

	if action_mode == "attack":
		var target = _get_unit_at_cell(cell)
		var in_range: bool = target != null and target.side != current_unit.side and _distance(current_unit.grid_pos, cell) <= maxi(1, int(current_unit.attack_range))
		var los_ok: bool = in_range and (int(current_unit.attack_range) <= 1 or battle_grid.has_line_of_sight(current_unit.grid_pos, cell))
		if target != null and target.side != current_unit.side:
			_show_enemy_panel(target)
		if los_ok:
			_do_attack(current_unit, target)
			current_unit.acted = true
			action_mode = "none"
			battle_grid.set_attack_range_cells([])
			_show_facing_picker(current_unit)
		elif in_range and not los_ok:
			info_label.text = "Blocked — no line of sight."
		else:
			info_label.text = "No valid target in range."
		return

	if action_mode == "skill" and _pending_skill != "":
		var sig_data: Dictionary = SigilLibraryScript.get_signature_ability(_pending_skill)
		if sig_data.is_empty():
			sig_data = SigilLibraryScript.get_sigil(_pending_skill)
		var ttype: String = str(sig_data.get("target_type", "enemy"))
		var target = _get_unit_at_cell(cell)
		var skill_range: int = SkillLibraryScript.get_skill_range(_pending_skill, current_unit)
		if ttype == "ally":
			if target != null and target.side == current_unit.side and target != current_unit:
				var dist: int = abs(target.grid_pos.x - current_unit.grid_pos.x) + abs(target.grid_pos.y - current_unit.grid_pos.y)
				if dist <= skill_range:
					_execute_skill(_pending_skill, current_unit, target)
				else:
					info_label.text = "Target out of range."
			else:
				info_label.text = "Select an ally target."
		else:
			# Enemy-targeted skill
			if target != null and target.side != current_unit.side:
				var dist: int = abs(target.grid_pos.x - current_unit.grid_pos.x) + abs(target.grid_pos.y - current_unit.grid_pos.y)
				if dist <= skill_range:
					_execute_skill(_pending_skill, current_unit, target)
				else:
					info_label.text = "Target out of range."
			else:
				info_label.text = "Select an enemy target."
		return

	var clicked = _get_unit_at_cell(cell)
	if clicked != null:
		selected_unit = clicked
		battle_grid.set_selected_unit(selected_unit)
		if clicked.side == _player_side:
			_show_stat_panel(clicked)
			_hide_enemy_panel()
			if clicked == current_unit:
				info_label.text = "Selected %s" % _unit_name(clicked)
				_show_action_popup(clicked)
			else:
				_hide_action_popup()
		else:
			_show_enemy_panel(clicked)
			_hide_action_popup()
	else:
		_hide_enemy_panel()
		_hide_action_popup()



func _remove_unit_from_battle(unit) -> void:
	if unit == null or state == null:
		return
	# Clear any pending walk so _is_animating doesn't get stuck
	if battle_grid._walking.has(unit):
		battle_grid._walking.erase(unit)
		_is_animating = false
	# Retreated leaders stay in attacker/defender arrays so _collect_battle_state
	# can find them during writeback. Only remove from turn_order and grid.
	# Non-leader units (and defeated units) are fully erased.
	var is_retreating: bool = bool(unit.has_retreated) if "has_retreated" in unit else false
	if not is_retreating or not bool(unit.is_leader_combatant):
		unit.is_alive = false
		if state.attacker_units.has(unit):
			state.attacker_units.erase(unit)
		if state.defender_units.has(unit):
			state.defender_units.erase(unit)
	else:
		# Retreated leader: mark alive (they survived), keep in array for writeback
		unit.is_alive = true
	if state.turn_order.has(unit):
		state.turn_order.erase(unit)
	if current_unit == unit:
		current_unit = null
		battle_grid.set_active_unit(null)
	if selected_unit == unit:
		selected_unit = null
	battle_grid.queue_redraw()




func _check_battle_end_or_continue() -> void:
	battle_grid.queue_redraw()
	if _check_force_end_on_no_leaders():
		return
	BattleResolverScript.check_win(state)
	if state.phase == "battle_end":
		_finish_battle()
		return
	_next_turn()

func _check_force_end_on_no_leaders() -> bool:
	var attacker_has_leader := false
	var defender_has_leader := false

	for u in state.attacker_units:
		if u != null and u.is_alive and u.is_leader_combatant and not ("has_retreated" in u and bool(u.has_retreated)):
			attacker_has_leader = true
			break

	for u in state.defender_units:
		if u != null and u.is_alive and u.is_leader_combatant and not ("has_retreated" in u and bool(u.has_retreated)):
			defender_has_leader = true
			break

	if not attacker_has_leader:
		for u in state.attacker_units:
			if u != null and bool(u.is_alive) and not bool(u.is_leader_combatant) and not (("is_captured" in u) and bool(u.is_captured)):
				u.is_captured = true
				DebugLogger.log("event:battle_unit_captured", {
					"round": int(state.round),
					"unit_name": _unit_name(u),
					"side": str(u.side),
					"reason": "battle_lost",
				})
		_battle_result["attacker_won"] = false
		_battle_result["defender_won"] = true
		_finish_battle()
		return true

	if not defender_has_leader:
		# Check if this is a tutorial mission — look up the mission type directly
		var is_tutorial: bool = false
		var _ms = _setup_dict.get("state", null)
		var _mid: String = str(_setup_dict.get("mission_instance_id", ""))
		if _ms != null and _mid != "" and _ms.active_missions.has(_mid):
			is_tutorial = str(_ms.active_missions[_mid].mission_type) == "tutorial"
		if is_tutorial:
			var defender_units_alive: bool = false
			for u in state.defender_units:
				if u != null and bool(u.is_alive) and not (("is_captured" in u) and bool(u.is_captured)):
					defender_units_alive = true
					break
			if defender_units_alive:
				return false  # battle still in progress
			# All defenders dead — fall through to normal win resolution
		var is_mission: bool = bool(_setup_dict.get("is_mission_battle", false))
		if not is_mission:
			for u in state.defender_units:
				if u != null and bool(u.is_alive) and not bool(u.is_leader_combatant) and not (("is_captured" in u) and bool(u.is_captured)):
					u.is_captured = true
					DebugLogger.log("event:battle_unit_captured", {
						"round": int(state.round),
						"unit_name": _unit_name(u),
						"side": str(u.side),
						"reason": "battle_lost",
					})
		else:
			# Skirmish mission: capture the strongest enemy unit
			var mission_type: String = str(_setup_dict.get("state", null).active_missions.get(
				str(_setup_dict.get("mission_instance_id", "")), null
			).mission_type if _setup_dict.get("state", null) != null else "")
			if mission_type == "skirmish":
				var best_unit = null
				var best_atk: int = -1
				for u in state.defender_units:
					if u != null and not bool(u.is_leader_combatant) and u.unit_ref != null:
						if int(u.final_attack) > best_atk:
							best_atk = int(u.final_attack)
							best_unit = u
				if best_unit != null:
					_battle_result["skirmish_captured_unit_type"] = str(best_unit.unit_ref.unit_type)
					_battle_result["skirmish_captured_unit_name"] = _unit_name(best_unit)
		_battle_result["attacker_won"] = true
		_battle_result["defender_won"] = false
		_finish_battle()
		return true

	return false

func _finish_battle() -> void:
	var attacker_alive: bool = _find_first_alive(state.attacker_units) != null
	var defender_alive: bool = _find_first_alive(state.defender_units) != null
	var captured_attacker: Array = []
	var captured_defender: Array = []
	var dead_attacker: Array = []
	var dead_defender: Array = []
	for u in state.attacker_units:
		if u == null:
			continue
		if u.is_captured and u.unit_ref != null:
			captured_attacker.append(int(u.unit_ref.unit_id))
		elif not u.is_alive and not u.is_leader_combatant and u.unit_ref != null:
			dead_attacker.append(int(u.unit_ref.unit_id))
	for u in state.defender_units:
		if u == null:
			continue
		if u.is_captured and u.unit_ref != null:
			captured_defender.append(int(u.unit_ref.unit_id))
		elif not u.is_alive and not u.is_leader_combatant and u.unit_ref != null:
			dead_defender.append(int(u.unit_ref.unit_id))
	# Collect item drops from dead units
	var item_transfers: Array = []
	for u in state.attacker_units + state.defender_units:
		if u == null or u.unit_ref == null:
			continue
		if not u.is_alive and not u.is_captured:
			var dropped: String = str(u.unit_ref.equipped_item_id)
			if dropped != "":
				item_transfers.append({"item_id": dropped, "from_side": str(u.side)})
	_battle_result = {
		"attacker_won": bool(_battle_result.get("attacker_won", attacker_alive and not defender_alive)),
		"defender_won": bool(_battle_result.get("defender_won", defender_alive and not attacker_alive)),
		"rounds_taken": int(state.round),
		"captured_attacker_unit_ids": captured_attacker,
		"captured_defender_unit_ids": captured_defender,
		"dead_attacker_unit_ids": dead_attacker,
		"dead_defender_unit_ids": dead_defender,
		"item_transfers": item_transfers,
		"unit_xp_applied": true,
	}
	_append_log("[b]Battle ended[/b]")
	# Apply end-of-battle unit XP now so stat panel shows updated values
	var player_units_final: Array = state.attacker_units if _player_side == "attacker" else state.defender_units
	for u in player_units_final:
		if u == null or not u.is_alive or u.is_captured or u.is_leader_combatant:
			continue
		if u.unit_ref != null and u.unit_ref.has_method("add_xp"):
			u.unit_ref.add_xp(75)
	_show_scorecard()


func _show_scorecard() -> void:
	var result: Dictionary = _battle_result
	var player_won: bool = (result.get("attacker_won", false) and _player_side == "attacker") \
		or (result.get("defender_won", false) and _player_side == "defender")
	var outcome_text: String = "[color=green][b]VICTORY[/b][/color]" if player_won else "[color=red][b]DEFEAT[/b][/color]"

	# Emit early so visual layer can show its styled result overlay
	battle_ended.emit(_battle_result)

	scorecard_panel.visible = true

	var rt: RichTextLabel = scorecard_panel.get_node("VBox/Content")
	rt.clear()
	rt.append_text(outcome_text + "  —  Round %d\n\n" % int(state.round))

	# Enemy units captured by player
	var enemy_captured_ids: Array = result.get("captured_defender_unit_ids", []) if _player_side == "attacker" else result.get("captured_attacker_unit_ids", [])
	var enemy_source: Array = state.defender_units if _player_side == "attacker" else state.attacker_units
	rt.append_text("[b]Enemy Units Captured:[/b]\n")
	if enemy_captured_ids.is_empty():
		rt.append_text("  None\n")
	else:
		for uid in enemy_captured_ids:
			var found_name: String = "Unit #%d" % uid
			for u in enemy_source:
				if u != null and u.unit_ref != null and int(u.unit_ref.unit_id) == uid:
					found_name = _unit_name(u)
					break
			rt.append_text("  • %s\n" % found_name)

	# Ally units left behind (captured by enemy)
	var ally_captured_ids: Array = result.get("captured_attacker_unit_ids", []) if _player_side == "attacker" else result.get("captured_defender_unit_ids", [])
	var ally_source: Array = state.attacker_units if _player_side == "attacker" else state.defender_units
	rt.append_text("\n[b]Ally Units Captured by Enemy:[/b]\n")
	if ally_captured_ids.is_empty():
		rt.append_text("  None\n")
	else:
		for uid in ally_captured_ids:
			var found_name: String = "Unit #%d" % uid
			for u in ally_source:
				if u != null and u.unit_ref != null and int(u.unit_ref.unit_id) == uid:
					found_name = _unit_name(u)
					break
			rt.append_text("  • %s\n" % found_name)

	# Losses
	var player_dead: Array = result.get("dead_attacker_unit_ids", []) if _player_side == "attacker" else result.get("dead_defender_unit_ids", [])
	var enemy_dead: Array = result.get("dead_defender_unit_ids", []) if _player_side == "attacker" else result.get("dead_attacker_unit_ids", [])
	rt.append_text("\n[b]Your Losses:[/b] %d unit(s)\n" % player_dead.size())
	rt.append_text("[b]Enemy Losses:[/b] %d unit(s)\n" % enemy_dead.size())

	# XP summary and floats
	rt.append_text("\n[b]XP Gained This Battle:[/b]\n")
	var player_units: Array = state.attacker_units if _player_side == "attacker" else state.defender_units
	var xp_found: bool = false
	for u in player_units:
		if u == null or not u.is_alive or u.is_captured:
			continue
		if u.is_leader_combatant and u.leader_ref != null:
			var xp_amt: int = 150 if player_won else 40
			rt.append_text("  • %s (Leader): +%d XP\n" % [_unit_name(u), xp_amt])
			_spawn_float_text(u.grid_pos, "+%d XP" % xp_amt, Color(0.4, 1.0, 0.4))
			xp_found = true
		elif not u.is_leader_combatant and u.unit_ref != null:
			rt.append_text("  • %s: +75 XP (Lv%d)\n" % [_unit_name(u), int(u.unit_ref.level)])
			_spawn_float_text(u.grid_pos, "+75 XP", Color(0.4, 1.0, 0.4))
			xp_found = true
	if not xp_found:
		rt.append_text("  None\n")
	# Mission item reward
	if bool(_setup_dict.get("is_mission_battle", false)):
		var game_state = _setup_dict.get("state", null)
		if game_state != null and not game_state.pending_mission_results.is_empty():
			var mission_result: Dictionary = game_state.pending_mission_results.back() as Dictionary
			var item_name: String = str(mission_result.get("item_name", ""))
			if item_name != "":
				rt.append_text("\n[color=gold][b]Item Found:[/b][/color] %s\n" % item_name)
			var gen_name: String = str(mission_result.get("rising_general_name", ""))
			if gen_name != "":
				rt.append_text("[color=cyan][b]General Recruited:[/b][/color] %s\n" % gen_name)
			var cap_name: String = str(mission_result.get("captured_unit_name", ""))
			if cap_name != "":
				rt.append_text("[color=yellow][b]Unit Captured:[/b][/color] %s\n" % cap_name)

	# Refresh stat panel so XP values are current
	if selected_unit != null:
		_show_stat_panel(selected_unit)


func _on_scorecard_close_pressed() -> void:
	battle_finished.emit(_battle_result)
	queue_free()


func _get_enemy_units(side_name: String) -> Array:
	return state.defender_units if side_name == "attacker" else state.attacker_units


func _get_unit_at_cell(cell: Vector2i):
	for unit in state.attacker_units:
		if unit != null and unit.is_alive and not ("is_captured" in unit and bool(unit.is_captured)) and unit.grid_pos == cell:
			return unit
	for unit in state.defender_units:
		if unit != null and unit.is_alive and not ("is_captured" in unit and bool(unit.is_captured)) and unit.grid_pos == cell:
			return unit
	return null


func _cell_is_free(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= battle_grid.GRID_COLS or cell.y >= battle_grid.GRID_ROWS:
		return false
	if not battle_grid.is_cell_passable(cell):
		return false
	return _get_unit_at_cell(cell) == null


func _distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(abs(a.x - b.x), abs(a.y - b.y))


func _facing_from_move(from: Vector2i, to: Vector2i) -> String:
	var dx: int = to.x - from.x
	var dy: int = to.y - from.y
	# Snap to 4 isometric diagonal directions.
	# Grid east (dx>0) = screen lower-right = SE
	# Grid south (dy>0) = screen lower-left = SW
	# Ties go to the x-axis (SE/NW preferred)
	if abs(dx) >= abs(dy):
		return "south-east" if dx > 0 else "north-west"
	return "south-west" if dy > 0 else "north-east"


func _find_first_alive(units: Array):
	for unit in units:
		if unit != null and unit.is_alive and not ("is_captured" in unit and bool(unit.is_captured)):
			return unit
	return null


func _compute_move_cells(unit) -> Array:
	var cells: Array = []
	if unit == null:
		return cells
	var range_val: int = maxi(1, int(unit.move_range))
	for x in range(BattleGrid.GRID_COLS):
		for y in range(BattleGrid.GRID_ROWS):
			var cell := Vector2i(x, y)
			if _distance(unit.grid_pos, cell) <= range_val and cell != unit.grid_pos:
				if _cell_is_free(cell):
					cells.append(cell)
	return cells


func _compute_attack_cells(unit) -> Array:
	var cells: Array = []
	if unit == null:
		return cells
	var range_val: int = maxi(1, int(unit.attack_range))
	var is_ranged: bool = range_val > 1
	for x in range(BattleGrid.GRID_COLS):
		for y in range(BattleGrid.GRID_ROWS):
			var cell := Vector2i(x, y)
			if cell == unit.grid_pos:
				continue
			if _distance(unit.grid_pos, cell) <= range_val:
				# Ranged units require clear LOS; melee always can attack
				if is_ranged and not battle_grid.has_line_of_sight(unit.grid_pos, cell):
					continue
				cells.append(cell)
	return cells


func _load_portrait(skey: String, variant: String = "") -> Texture2D:
	# Try variant first (e.g. "determined"), then plain portrait, then null
	var candidates: Array[String] = []
	if variant != "":
		candidates.append("res://Art/leaders/%s/portraits/%s_portrait_%s.png" % [skey, skey, variant])
	candidates.append("res://Art/leaders/%s/portraits/%s_portrait.png" % [skey, skey])
	for p in candidates:
		if ResourceLoader.exists(p):
			return load(p) as Texture2D
	return null


func _show_stat_panel(unit) -> void:
	if unit == null:
		_clear_unit_panel_left()
		return
	# Name + color
	_left_unit_name.text = _unit_name(unit)
	_left_unit_name.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	# Portrait — use "determined" variant as default for player leaders
	var skey: String = str(unit.get("sprite_key") if unit.get("sprite_key") != null else "")
	if skey != "":
		var variant: String = "determined" if unit.side == _player_side else ""
		_left_portrait.texture = _load_portrait(skey, variant)
	else:
		_left_portrait.texture = null
	# HP bar
	_left_hp_bar.max_value = float(unit.final_max_hp)
	_left_hp_bar.value     = float(unit.battle_hp)
	# Stats text
	var rt: RichTextLabel = stat_label
	rt.clear()
	if not bool(unit.is_leader_combatant) and unit.unit_ref != null:
		var _pname: String = str(unit.unit_ref.unit_name) if "unit_name" in unit.unit_ref and str(unit.unit_ref.unit_name) != "" else ""
		if _pname != "":
			rt.append_text("[color=gold]%s[/color]\n" % _pname)
	rt.append_text("ATK %d  DEF %d  SPD %d\n" % [int(unit.final_attack), int(unit.final_defense), int(unit.speed)])
	rt.append_text("Move %d  Range %d  SP %d/%d\n" % [int(unit.move_range), int(unit.attack_range), int(unit.current_sp), int(unit.max_sp)])
	var _sigil_id: String = unit.get_equipped_sigil_id() if unit.has_method("get_equipped_sigil_id") else ""
	if _sigil_id != "":
		var _sig_data: Dictionary = SigilLibraryScript.get_sigil(_sigil_id)
		if _sig_data.is_empty():
			_sig_data = SigilLibraryScript.get_signature_ability(_sigil_id)
		if not _sig_data.is_empty():
			rt.append_text("Sigil: [color=plum]%s[/color]\n" % str(_sig_data.get("name", _sigil_id)))
	if unit.is_leader_combatant and unit.leader_ref != null:
		var ldr_level: int = int(unit.leader_ref.level) if "level" in unit.leader_ref else 1
		var ldr_xp: int    = int(unit.leader_ref.xp)    if "xp"    in unit.leader_ref else 0
		var thresh: int    = 50 + (ldr_level - 1) * 15
		var ldr_dtype: String = str(unit.leader_ref.damage_type).capitalize() if "damage_type" in unit.leader_ref else "Slash"
		rt.append_text("%s  Lv %d  XP %d/%d\n" % [ldr_dtype, ldr_level, ldr_xp, thresh])
	elif unit.unit_ref != null:
		var _tier: int  = int(unit.unit_ref.tier)  if "tier"  in unit.unit_ref else 1
		var _level: int = int(unit.unit_ref.level) if "level" in unit.unit_ref else 1
		var _xp: int    = int(unit.unit_ref.xp)    if "xp"    in unit.unit_ref else 0
		var _xp_next: int = int(unit.unit_ref.xp_to_next_level) if "xp_to_next_level" in unit.unit_ref else 0
		if _xp_next > 0:
			rt.append_text("Tier %d  Lv %d  XP %d/%d\n" % [_tier, _level, _xp, _xp_next])
		else:
			rt.append_text("Tier %d  Lv %d\n" % [_tier, _level])
	stat_panel.visible = true


func _hide_stat_panel() -> void:
	_clear_unit_panel_left()


func _clear_unit_panel_left() -> void:
	stat_panel.visible = false
	_left_unit_name.text = "-"
	_left_unit_name.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
	_left_hp_bar.value = 0.0
	_left_portrait.texture = null
	stat_label.clear()


# ── Right panel: shows hovered / targeted enemy ──────────────────────────────
func _show_enemy_panel(unit) -> void:
	if unit == null:
		_clear_unit_panel_right()
		return
	_right_unit_name.text = _unit_name(unit)
	_right_unit_name.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	# Portrait — load for leaders if available, null for non-leaders
	var skey: String = str(unit.get("sprite_key") if unit.get("sprite_key") != null else "")
	if skey != "" and bool(unit.is_leader_combatant):
		_right_portrait.texture = _load_portrait(skey)
	else:
		_right_portrait.texture = null
	_right_hp_bar.max_value = float(unit.final_max_hp)
	_right_hp_bar.value     = float(unit.battle_hp)
	var rt: RichTextLabel = _right_stat_label
	rt.clear()
	if not bool(unit.is_leader_combatant) and unit.unit_ref != null:
		var _pname: String = str(unit.unit_ref.unit_name) if "unit_name" in unit.unit_ref and str(unit.unit_ref.unit_name) != "" else ""
		if _pname != "":
			rt.append_text("[color=gold]%s[/color]\n" % _pname)
	rt.append_text("ATK %d  DEF %d  SPD %d\n" % [int(unit.final_attack), int(unit.final_defense), int(unit.speed)])
	rt.append_text("Move %d  Range %d\n" % [int(unit.move_range), int(unit.attack_range)])
	if unit.is_leader_combatant and unit.leader_ref != null:
		var ldr_level: int = int(unit.leader_ref.level) if "level" in unit.leader_ref else 1
		var ldr_dtype: String = str(unit.leader_ref.damage_type).capitalize() if "damage_type" in unit.leader_ref else "Slash"
		rt.append_text("%s  Lv %d\n" % [ldr_dtype, ldr_level])
	elif unit.unit_ref != null:
		var _tier: int  = int(unit.unit_ref.tier)  if "tier"  in unit.unit_ref else 1
		var _level: int = int(unit.unit_ref.level) if "level" in unit.unit_ref else 1
		rt.append_text("Tier %d  Lv %d\n" % [_tier, _level])
	_right_unit_panel.visible = true


func _hide_enemy_panel() -> void:
	_clear_unit_panel_right()


func _clear_unit_panel_right() -> void:
	_right_unit_panel.visible = false
	_right_unit_name.text = "-"
	_right_unit_name.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
	_right_hp_bar.value = 0.0
	_right_portrait.texture = null
	_right_stat_label.clear()


func _is_player_turn() -> bool:
	return current_unit != null and current_unit.side == _player_side


func _cell_to_screen(grid_pos: Vector2i) -> Vector2:
	const TILE_SIZE: int = 64
	const ORIGIN := Vector2(48, 56)
	return ORIGIN + Vector2(grid_pos.x * TILE_SIZE + TILE_SIZE * 0.5, grid_pos.y * TILE_SIZE + TILE_SIZE * 0.5)


func _spawn_float_text(grid_pos: Vector2i, text: String, color: Color) -> void:
	var canvas: CanvasLayer = $CanvasLayer
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.z_index = 100
	var screen_pos: Vector2 = _cell_to_screen(grid_pos)
	lbl.position = screen_pos + Vector2(-20, -24)
	canvas.add_child(lbl)
	var tween := create_tween()
	tween.tween_property(lbl, "position", lbl.position + Vector2(0, -48), 1.2)
	tween.parallel().tween_property(lbl, "modulate:a", 0.0, 1.2)
	tween.tween_callback(lbl.queue_free)


func _do_attack(attacker, defender) -> void:
	attacker.facing = _facing_from_move(attacker.grid_pos, defender.grid_pos)
	battle_grid.play_attack_anim(attacker)
	var hp_before: int = int(defender.battle_hp)
	var alive_before: bool = defender.is_alive
	var xp_result: Dictionary = BattleResolverScript.attack(state, attacker, defender)
	var dmg: int = hp_before - int(max(0, defender.battle_hp))
	if dmg > 0:
		_spawn_float_text(defender.grid_pos, "-%d" % dmg, Color(1.0, 0.25, 0.25))
	if alive_before and not defender.is_alive:
		_spawn_float_text(defender.grid_pos, "KO", Color(1.0, 0.5, 0.0))
	var xp_gain: int = int(xp_result.get("xp_gained", 0))
	if xp_gain > 0:
		_apply_battle_xp(attacker, xp_gain)
	# Refresh panel HP bars after the attack resolves
	_show_stat_panel(attacker)
	if defender.is_alive:
		_show_enemy_panel(defender)
	else:
		_hide_enemy_panel()
	battle_grid.queue_redraw()


func _apply_battle_xp(unit, xp_gain: int) -> void:
	if unit == null:
		return
	if unit.is_leader_combatant and unit.leader_ref != null:
		var ldr = unit.leader_ref
		if not ("xp" in ldr) or not ("level" in ldr):
			return
		var thresh: int = 50 + (int(ldr.level) - 1) * 15
		ldr.xp += xp_gain
		var leveled: bool = false
		while ldr.xp >= thresh:
			ldr.xp -= thresh
			ldr.level += 1
			thresh = 50 + (int(ldr.level) - 1) * 15
			leveled = true
		_spawn_float_text(unit.grid_pos, "+%d XP" % xp_gain, Color(0.4, 1.0, 0.4))
		if leveled:
			_spawn_float_text(unit.grid_pos, "LEVEL UP!", Color(1.0, 1.0, 0.2))
	elif not unit.is_leader_combatant and unit.unit_ref != null:
		if not unit.unit_ref.has_method("add_xp"):
			return
		var levels_gained: int = unit.unit_ref.add_xp(xp_gain)
		_spawn_float_text(unit.grid_pos, "+%d XP" % xp_gain, Color(0.4, 1.0, 0.4))
		if levels_gained > 0:
			_spawn_float_text(unit.grid_pos, "LEVEL UP!", Color(1.0, 1.0, 0.2))


func _refresh_labels() -> void:
	turn_label.text = "Round %d" % int(state.round)
	info_label.text = "Current: %s" % _unit_name(current_unit)
	battle_grid.queue_redraw()
	_refresh_log()


func _refresh_log() -> void:
	if state == null:
		return
	var lines: Array[String] = []
	for entry in state.log:
		lines.append(str(entry))
	log_label.text = "\n".join(lines)


func _append_log(text: String) -> void:
	state.log.append(text)
	_refresh_log()


func _update_button_state() -> void:
	# Update button disabled states IN PLACE — never rebuild/reposition the popup
	if current_unit == null:
		return
	var unit = current_unit
	if move_button != null and is_instance_valid(move_button):
		move_button.disabled = bool(unit.moved) or bool(unit.acted)
	if attack_button != null and is_instance_valid(attack_button):
		attack_button.disabled = bool(unit.acted)
	if defend_button != null and is_instance_valid(defend_button):
		defend_button.disabled = bool(unit.acted)
	if skip_button != null and is_instance_valid(skip_button):
		skip_button.disabled = bool(unit.acted)
	if retreat_button != null and is_instance_valid(retreat_button):
		retreat_button.disabled = bool(unit.acted)
	if skill_button != null and is_instance_valid(skill_button):
		var skill_off := true
		if not bool(unit.acted) and not bool(unit.get("sigil_disabled")):
			var skills: Array[String] = SkillLibraryScript.get_unit_skills(unit)
			if not skills.is_empty():
				var sp: int = int(unit.current_sp)
				var min_cost := 999
				for sid in skills:
					var c: int = SkillLibraryScript.get_skill_sp_cost(sid, unit)
					if c < min_cost: min_cost = c
				skill_off = sp < min_cost
		skill_button.disabled = skill_off


func _hide_facing_picker() -> void:
	if _facing_popup != null and is_instance_valid(_facing_popup):
		_facing_popup.queue_free()
	_facing_popup = null


func _show_facing_picker(unit) -> void:
	_hide_facing_picker()
	if unit == null:
		_check_battle_end_or_continue()
		return

	var scene := preload("res://Scenes/battle/facing_picker.tscn")
	_facing_popup = scene.instantiate()

	const DIR_BUTTONS := [
		["north-west", "NWButton"],
		["north-east", "NEButton"],
		["south-west", "SWButton"],
		["south-east", "SEButton"],
	]
	for entry in DIR_BUTTONS:
		var captured_dir: String = entry[0]
		var btn: Button = _facing_popup.get_node("VBoxContainer/GridMargin/DirectionGrid/" + entry[1])
		if str(unit.get("facing")) == captured_dir:
			btn.modulate = Color(0.4, 0.9, 1.0)
		btn.pressed.connect(func() -> void:
			unit.facing = captured_dir
			battle_grid.queue_redraw()
			_hide_facing_picker()
			_check_battle_end_or_continue()
		)

	_facing_popup.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_facing_popup.grow_horizontal = Control.GROW_DIRECTION_END
	_facing_popup.grow_vertical   = Control.GROW_DIRECTION_END
	$CanvasLayer/UI.add_child(_facing_popup)
	_facing_popup.position = _calc_popup_screen_pos()


func _hide_action_popup() -> void:
	if _action_popup != null and is_instance_valid(_action_popup):
		_action_popup.queue_free()
	_action_popup = null
	move_button    = null
	attack_button  = null
	defend_button  = null
	skill_button   = null
	item_button    = null
	skip_button    = null
	retreat_button = null


func _show_action_popup(unit) -> void:
	# If popup is already showing for this unit, just update button states in-place
	if _action_popup != null and is_instance_valid(_action_popup):
		_update_button_state()
		return
	_hide_action_popup()
	_hide_facing_picker()
	if unit == null or not _is_player_turn() or unit != current_unit:
		return

	var scene := preload("res://Scenes/battle/action_popup.tscn")
	_action_popup = scene.instantiate()

	move_button    = _action_popup.get_node("VBoxContainer/MoveButton")
	attack_button  = _action_popup.get_node("VBoxContainer/AttackButton")
	defend_button  = _action_popup.get_node("VBoxContainer/DefendButton")
	skill_button   = _action_popup.get_node("VBoxContainer/SkillButton")
	item_button    = _action_popup.get_node("VBoxContainer/ItemButton")
	skip_button    = _action_popup.get_node("VBoxContainer/SkipButton")
	retreat_button = _action_popup.get_node("VBoxContainer/RetreatButton")

	# Disable buttons based on unit state
	move_button.disabled   = bool(unit.moved) or bool(unit.acted)
	attack_button.disabled = bool(unit.acted)
	defend_button.disabled = bool(unit.acted)
	skip_button.disabled   = bool(unit.acted)
	retreat_button.disabled = bool(unit.acted)

	var skill_off := true
	if not bool(unit.acted) and not bool(unit.get("sigil_disabled")):
		var skills: Array[String] = SkillLibraryScript.get_unit_skills(unit)
		if not skills.is_empty():
			var sp: int = int(unit.current_sp)
			var min_cost := 999
			for sid in skills:
				var c: int = SkillLibraryScript.get_skill_sp_cost(sid, unit)
				if c < min_cost: min_cost = c
			skill_off = sp < min_cost
	skill_button.disabled = skill_off

	move_button.pressed.connect(_on_move_pressed)
	attack_button.pressed.connect(_on_attack_pressed)
	defend_button.pressed.connect(_on_defend_pressed)
	skill_button.pressed.connect(_on_skill_pressed)
	item_button.pressed.connect(_on_item_pressed)
	skip_button.pressed.connect(_on_skip_pressed)

	# Retreat — leaders only
	if bool(unit.is_leader_combatant):
		retreat_button.visible = true
		retreat_button.pressed.connect(_on_retreat_pressed)

	_action_popup.set_anchors_preset(Control.PRESET_TOP_LEFT)
	$CanvasLayer/UI.add_child(_action_popup)
	_action_popup.position = _calc_popup_screen_pos()



func _unit_name(unit) -> String:
	if unit == null:
		return "Unknown"
	if unit.is_leader_combatant and unit.leader_ref != null:
		if unit.leader_ref.has_method("get_display_name"):
			return unit.leader_ref.get_display_name()
		if "display_name" in unit.leader_ref:
			return str(unit.leader_ref.display_name)
		if "name" in unit.leader_ref:
			return str(unit.leader_ref.name)
	return unit.get_display_name()
