extends Node2D
class_name MapDebugView

const LeaderData = preload("res://Scripts/map/leader_data.gd")
const OrderBook = preload("res://Scripts/game/order_book.gd")
const AIBalanceLabScript = preload("res://Scripts/game/tools/ai_balance_lab.gd")
const BattleLabScript = preload("res://Scripts/game/tools/battle_lab.gd")
const BattleAutoTunerScript = preload("res://Scripts/game/tools/battle_autotuner.gd")
const MissionAutoTunerScript = preload("res://Scripts/game/tools/mission_autotuner.gd")

# =====================================================
# CONTRACT NOTES (do not change without updating all callers)
# - Planning Phase: UI queues orders into OrderBook ONLY (no state mutation).
# - Execution Phase: TurnManager.execute_month resolves queued orders via resolvers.
# - Hard rules enforced at UI layer:
#   * You can only issue orders from HUMAN-owned provinces.
#   * ATTACK targets must be non-HUMAN (enemy or neutral).
#   * TRANSFER targets must be HUMAN-owned.
# - Do NOT change public ui_* function signatures; MapDebugUI calls them via call().
# =====================================================


signal debug_state_changed

@export var settings: MapSettings

var map_data: MapData
var game_state: GameState
var turn_manager: TurnManager

var HUMAN_ID: int = 0
const AI_ID := 1
const MAP_SIZE_OPTIONS: Array[int] = [20, 40, 60, 80]
const AI_LAB_MONTH_OPTIONS: Array[int] = [36, 72, 144]

var selected_province_id: int = -1
var selected_leader_id: int = -1  # last selected (for compat)
var selected_leader_ids: Array[int] = []  # multi-select, max 3
var hover_province_id: int = -1

enum TargetPickMode { NONE, ATTACK, TRANSFER }
var pick_mode: int = TargetPickMode.NONE
var _pick_source_id: int = -1
var _ai_lab_running: bool = false
var _battle_lab_running: bool = false
var _battle_tune_running: bool = false
var _battle_autotuner: Node = null
var _mission_tune_running: bool = false
var _mission_autotuner: Node = null
var _autotune_running: bool = false
var _autotune_progress_text: String = "AutoTune: Idle"
var _autotune_month_live: int = 0
var _autotune_seed_live: int = 0
var _autotune_seed_total: int = 0
var _autotune_iteration_live: int = 0
var _ai_lab_progress_text: String = "AI Lab: Idle"
var _ai_lab_month_live: int = 0
var _ai_lab_preview_map_data: MapData = null
var _ai_lab_preview_owner_by_province: Dictionary = {}
var _ai_lab_months_setting: int = 36

# Camera
var _zoom: float = 1.0
var _origin: Vector2 = Vector2.ZERO
var _is_panning: bool = false
var _pan_last: Vector2 = Vector2.ZERO

# Voronoi
var _voronoi_cells: Dictionary = {} # int -> Array[Vector2]

# Leader Panel
var _leader_panel: LeaderPanel = null
var _recruit_panel: RecruitPanel = null
var _mission_panel: MissionPanel = null
var _injector_panel: DebugInjectorPanel = null

# Labels
var _label_font: Font

const NODE_RADIUS: float = 8.0
const PICK_RADIUS: float = 14.0


func _build_fresh_state() -> void:
	var generator := MapGenerator.new()
	map_data = generator.generate_map(settings)

	game_state = GameState.new()
	game_state.human_faction_id = HUMAN_ID
	game_state.init_with_map(map_data)

	turn_manager = TurnManager.new()
	selected_province_id = -1
	selected_leader_id = -1
	selected_leader_ids.clear()
	hover_province_id = -1
	pick_mode = TargetPickMode.NONE
	_pick_source_id = -1
	_ai_lab_running = false
	_ai_lab_month_live = 0
	_ai_lab_progress_text = "AI Lab: Idle"
	_autotune_running = false
	_autotune_month_live = 0
	_autotune_seed_live = 0
	_autotune_progress_text = "AutoTune: Idle"
	_clear_ai_lab_preview()

	DebugLogger.log("MapDebugView ready | map provinces=%d routes=%d month=%d" % [map_data.provinces.size(), map_data.routes.size(), int(game_state.month_index)])

	_rebuild_voronoi()
	_frame_map()

	if _leader_panel != null:
		_leader_panel.set_game_state(game_state)
		_leader_panel.human_faction_id = HUMAN_ID
		_leader_panel.refresh(selected_province_id)
	if _recruit_panel != null:
		_recruit_panel.set_view(self)
		_refresh_recruit_for_province(selected_province_id)
	if _mission_panel != null:
		_mission_panel.set_game_state(game_state)
		_mission_panel.set_human_faction(HUMAN_ID)
		_mission_panel.clear_results()
		_mission_panel.refresh(selected_province_id)

	debug_state_changed.emit()
	queue_redraw()


func _ready() -> void:
	_label_font = ThemeDB.fallback_font

	if settings == null:
		settings = load("res://data/default_map_settings.tres")

	# Generate map first so picker can read faction data
	var generator := MapGenerator.new()
	map_data = generator.generate_map(settings)

	# Show faction picker — finish init after selection
	var picker := FactionPicker.new()
	picker.init(map_data)
	picker.faction_selected.connect(_on_faction_picked)
	add_child(picker)


func _on_faction_picked(faction_id: int) -> void:
	HUMAN_ID = faction_id

	game_state = GameState.new()
	game_state.human_faction_id = faction_id
	game_state.init_with_map(map_data)

	turn_manager = TurnManager.new()
	selected_province_id = -1
	selected_leader_id = -1
	selected_leader_ids.clear()
	hover_province_id = -1
	pick_mode = TargetPickMode.NONE
	_pick_source_id = -1
	_ai_lab_running = false
	_ai_lab_month_live = 0
	_ai_lab_progress_text = "AI Lab: Idle"
	_autotune_running = false
	_autotune_month_live = 0
	_autotune_seed_live = 0
	_autotune_progress_text = "AutoTune: Idle"
	_clear_ai_lab_preview()

	DebugLogger.log("Faction chosen: %d | provinces=%d routes=%d" % [faction_id, map_data.provinces.size(), map_data.routes.size()])

	_rebuild_voronoi()
	_frame_map()

	# Debug UI
	var ui_scene: PackedScene = load("res://Scenes/debug/map_debug_ui.tscn")
	if ui_scene:
		var ui = ui_scene.instantiate()
		add_child(ui)

	# Leader Panel
	_leader_panel = LeaderPanel.new()
	_leader_panel.set_game_state(game_state)
	var vp_size: Vector2 = get_viewport_rect().size
	_leader_panel.position = Vector2(vp_size.x - 360.0, 40.0)
	_leader_panel.toggle_callback = func(lid: int) -> void: ui_toggle_leader_id(lid)
	_leader_panel.selected_ids_callback = func() -> Array: return selected_leader_ids.duplicate()
	_leader_panel.order_text_callback = func(lid: int) -> String: return _get_leader_order_text(lid)
	_leader_panel.dismiss_callback = func(lid: int) -> void: _on_dismiss_general(lid)
	_leader_panel.heal_unit_callback = func(unit_id: int, province_id: int) -> bool: return _on_heal_unit_requested(unit_id, province_id)
	_leader_panel.heal_cost_callback = func(unit_id: int) -> int:
		return game_state.get_unit_active_heal_cost(unit_id) if game_state != null else -1
	_leader_panel.human_faction_id = HUMAN_ID
	add_child(_leader_panel)

	_recruit_panel = RecruitPanel.new()
	_recruit_panel.set_view(self)
	_recruit_panel.position = Vector2(vp_size.x - 320.0, vp_size.y - 140.0)
	add_child(_recruit_panel)
	_refresh_recruit_for_province(selected_province_id)

	_mission_panel = MissionPanel.new()
	_mission_panel.set_game_state(game_state)
	_mission_panel.set_human_faction(HUMAN_ID)
	_mission_panel.position = Vector2(20.0, 40.0)
	add_child(_mission_panel)
	_mission_panel.refresh(selected_province_id)

	_injector_panel = DebugInjectorPanel.new()
	_injector_panel.set_view(self)
	_injector_panel.position = Vector2(vp_size.x - 620.0, 40.0)
	_injector_panel.hide()
	add_child(_injector_panel)

	debug_state_changed.emit()
	queue_redraw()


func _on_heal_unit_requested(unit_id: int, province_id: int) -> bool:
	if game_state == null or map_data == null or province_id < 0 or province_id >= map_data.provinces.size():
		return false
	var province: ProvinceData = map_data.provinces[province_id] as ProvinceData
	if province == null or int(province.owner_id) != HUMAN_ID:
		DebugLogger.log("Active heal blocked | not your province | P%d" % province_id)
		return false
	var cost: int = game_state.get_unit_active_heal_cost(unit_id)
	if cost <= 0:
		DebugLogger.log("Active heal blocked | unit not healable | unit=%d" % unit_id)
		return false
	var ok: bool = game_state.active_heal_unit(HUMAN_ID, unit_id, province_id)
	if ok:
		DebugLogger.log("Active heal | unit=%d province=%d cost=%d" % [unit_id, province_id, cost])
		if _leader_panel != null:
			_leader_panel.refresh(selected_province_id)
		_refresh_recruit_for_province(selected_province_id)
		if _mission_panel != null:
			_mission_panel.refresh(selected_province_id)
		debug_state_changed.emit()
	else:
		DebugLogger.log("Active heal failed | unit=%d province=%d cost=%d" % [unit_id, province_id, cost])
	return ok


# =====================================================
# INPUT
# =====================================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton

		# Middle mouse pan
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_is_panning = true
				_pan_last = mb.position
			else:
				_is_panning = false

		# Wheel zoom (do NOT rely on pressed flag)
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mb.position, 1.1)

		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mb.position, 0.9)

		# Left click
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_on_left_click(mb.position)

	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _is_panning:
			var delta: Vector2 = mm.position - _pan_last
			_pan_last = mm.position
			_origin += delta
			queue_redraw()
		else:
			hover_province_id = _pick_province_id(mm.position)
			queue_redraw()


# =====================================================
# CAMERA
# =====================================================

func _to_screen(world: Vector2) -> Vector2:
	return world * _zoom + _origin


func _to_world(screen: Vector2) -> Vector2:
	return (screen - _origin) / _zoom


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var world: Vector2 = _to_world(screen_pos)
	_zoom = clamp(_zoom * factor, 0.35, 2.5)
	_origin = screen_pos - world * _zoom
	queue_redraw()


func _frame_map() -> void:
	_frame_map_from(map_data)


func _frame_map_from(data: MapData) -> void:
	var rect: Rect2 = _compute_bounds_from(data)
	var vp: Vector2 = get_viewport_rect().size

	var sx: float = vp.x / rect.size.x
	var sy: float = vp.y / rect.size.y

	_zoom = min(sx, sy) * 0.85
	var center: Vector2 = rect.position + rect.size * 0.5
	_origin = vp * 0.5 - center * _zoom


func _compute_bounds() -> Rect2:
	return _compute_bounds_from(map_data)


func _compute_bounds_from(data: MapData) -> Rect2:
	if data == null:
		return Rect2(Vector2.ZERO, Vector2.ONE)
	var minx: float = 1.0e18
	var miny: float = 1.0e18
	var maxx: float = -1.0e18
	var maxy: float = -1.0e18

	for item in data.provinces:
		var p: ProvinceData = item as ProvinceData
		minx = minf(minx, p.center.x)
		miny = minf(miny, p.center.y)
		maxx = maxf(maxx, p.center.x)
		maxy = maxf(maxy, p.center.y)

	if maxx < minx or maxy < miny:
		return Rect2(Vector2.ZERO, Vector2.ONE)

	return Rect2(Vector2(minx, miny), Vector2(maxx - minx, maxy - miny))


# =====================================================
# SELECTION + ORDER PICKING
# =====================================================

func _on_left_click(screen_pos: Vector2) -> void:
	var pid: int = _pick_province_id(screen_pos)
	if pid == -1:
		return

	# If we are in a targeting mode, interpret this click as a target selection.
	if pick_mode != TargetPickMode.NONE and _pick_source_id != -1:
		if pid == _pick_source_id:
			# Clicking the source again just re-selects it.
			selected_province_id = pid
			queue_redraw()
			debug_state_changed.emit()
			return

		# Queue the appropriate order (planning phase only)
		if game_state == null or game_state.order_book == null:
			return

		# Hard rule: validate target by ownership before queuing
		var src_p: ProvinceData = map_data.provinces[_pick_source_id] as ProvinceData
		var tgt_p: ProvinceData = map_data.provinces[pid] as ProvinceData
		# Source must remain HUMAN-owned
		if int(src_p.owner_id) != HUMAN_ID:
			DebugLogger.log('Order blocked | source not HUMAN | P%d owner=%d' % [_pick_source_id, int(src_p.owner_id)])
			return
		# Attack cannot target HUMAN; Transfer must target HUMAN
		if pick_mode == TargetPickMode.ATTACK and int(tgt_p.owner_id) == HUMAN_ID:
			DebugLogger.log('ATTACK blocked | target is HUMAN | P%d -> P%d' % [_pick_source_id, pid])
			return
		if pick_mode == TargetPickMode.TRANSFER and int(tgt_p.owner_id) != HUMAN_ID:
			DebugLogger.log('TRANSFER blocked | target not HUMAN | P%d -> P%d owner=%d' % [_pick_source_id, pid, int(tgt_p.owner_id)])
			return

		match pick_mode:
			TargetPickMode.ATTACK:
				_queue_attack(_pick_source_id, pid)
			TargetPickMode.TRANSFER:
				_queue_transfer(_pick_source_id, pid)

		# Exit mode after queuing
		pick_mode = TargetPickMode.NONE
		_pick_source_id = -1
		selected_province_id = pid
		_sync_selected_leader_for_selected_province()
		if _leader_panel != null:
			_leader_panel.refresh(selected_province_id)
		if _mission_panel != null:
			_mission_panel.refresh(selected_province_id)
		_refresh_recruit_for_province(pid)
		DebugLogger.log("Click target P%d | mode resolved" % pid)
		queue_redraw()
		debug_state_changed.emit()
		return

	# Normal selection
	selected_province_id = pid
	_sync_selected_leader_for_selected_province()
	if _leader_panel != null:
		_leader_panel.refresh(selected_province_id)
	if _mission_panel != null:
		_mission_panel.refresh(selected_province_id)
	if _injector_panel != null:
		_injector_panel.refresh(selected_province_id)
	_refresh_recruit_for_province(pid)
	DebugLogger.log("Select P%d" % pid)
	queue_redraw()
	debug_state_changed.emit()


func _pick_province_id(screen_pos: Vector2) -> int:
	var data: MapData = _get_draw_map_data()
	if data == null:
		return -1

	var world: Vector2 = _to_world(screen_pos)
	var best: int = -1
	var best_d: float = 999999.0

	for item in data.provinces:
		var p: ProvinceData = item as ProvinceData
		var d: float = world.distance_to(p.center)
		if d < PICK_RADIUS and d < best_d:
			best = int(p.id)
			best_d = d

	return best


func _get_selected_province_leaders(include_on_mission: bool = true) -> Array:
	if game_state == null or selected_province_id == -1:
		return []
	return game_state.get_province_leaders(selected_province_id, include_on_mission)


func _sync_selected_leader_for_selected_province() -> void:
	var leaders_in_province: Array = _get_selected_province_leaders(true)
	if leaders_in_province.is_empty():
		selected_leader_id = -1
		selected_leader_ids.clear()
		return
	# Remove any leaders no longer in this province from multi-select
	var valid_ids: Array[int] = []
	for item in leaders_in_province:
		var leader: LeaderData = item as LeaderData
		if leader != null:
			valid_ids.append(int(leader.id))
	var new_multi: Array[int] = []
	for lid in selected_leader_ids:
		if valid_ids.has(lid):
			new_multi.append(lid)
	selected_leader_ids = new_multi
	# Sync single selected_leader_id
	if not valid_ids.has(selected_leader_id):
		selected_leader_id = int((leaders_in_province[0] as LeaderData).id)
	if not selected_leader_ids.has(selected_leader_id):
		selected_leader_ids.append(selected_leader_id)


func _get_selected_leader() -> LeaderData:
	_sync_selected_leader_for_selected_province()
	if game_state == null or selected_leader_id == -1:
		return null
	return game_state.get_leader(selected_leader_id)


func _format_leader_entry(leader: LeaderData) -> String:
	if leader == null:
		return "(none)"

	var piece: String = leader.display_name
	if piece == "":
		piece = leader.name

	if leader.is_story_leader:
		piece = "★ " + piece

	var busy: bool = false
	if "on_mission" in leader:
		busy = bool(leader.on_mission)
	else:
		busy = (str(leader.status) == "mission")

	if busy:
		piece += " [Mission: %s %dT]" % [leader.mission_type.capitalize(), int(leader.mission_turns_remaining)]
	else:
		piece += " [Idle]"

	piece += " | Lv:%d XP:%d" % [
		int(leader.level),
		int(leader.xp)
	]

	piece += " | L:%d A:%d D:%d M:%d" % [
		int(leader.leadership),
		int(leader.attack),
		int(leader.defense),
		int(leader.magic)
	]

	if not leader.traits.is_empty():
		piece += " | " + ", ".join(leader.traits)

	return piece


func _queue_attack(from_id: int, to_id: int) -> void:
	# Use selected leaders (max 3); fall back to all province leaders
	var leaders_to_commit: Array[int] = []
	if not selected_leader_ids.is_empty():
		leaders_to_commit = selected_leader_ids.duplicate()
	else:
		var all: Array = game_state.get_province_leaders(from_id, false)
		for item in all:
			var l: LeaderData = item as LeaderData
			if l != null:
				leaders_to_commit.append(int(l.id))
	while leaders_to_commit.size() > 3:
		leaders_to_commit.remove_at(leaders_to_commit.size() - 1)
	game_state.order_book.queue_attack(HUMAN_ID, from_id, to_id, 0, leaders_to_commit)
	DebugLogger.log("Queue ATTACK | P%d -> P%d | leaders=%s" % [from_id, to_id, str(leaders_to_commit)])
	# Deselect after queuing
	selected_leader_ids.clear()
	if _leader_panel != null:
		_leader_panel.refresh_highlights()


func _queue_transfer(from_id: int, to_id: int) -> void:
	var leaders_to_move: Array[int] = []
	if not selected_leader_ids.is_empty():
		leaders_to_move = selected_leader_ids.duplicate()
	else:
		var all: Array = game_state.get_province_leaders(from_id, false)
		for item in all:
			var l: LeaderData = item as LeaderData
			if l != null:
				leaders_to_move.append(int(l.id))
	while leaders_to_move.size() > 3:
		leaders_to_move.remove_at(leaders_to_move.size() - 1)
	game_state.order_book.queue_transfer(HUMAN_ID, from_id, to_id, leaders_to_move)
	DebugLogger.log("Queue TRANSFER | P%d -> P%d | leaders=%s" % [from_id, to_id, str(leaders_to_move)])
	# Deselect after queuing
	selected_leader_ids.clear()
	if _leader_panel != null:
		_leader_panel.refresh_highlights()


# =====================================================
# UI HELPERS (MapDebugUI reads these via call())
# =====================================================

func ui_has_selection() -> bool:
	return selected_province_id != -1


func ui_get_selected_text() -> String:
	if selected_province_id == -1:
		return "Selected: (none)"

	var p: ProvinceData = map_data.provinces[selected_province_id] as ProvinceData
	return "Province %d | %s | Fort:%d | Owner:%d" % [
		int(p.id),
		str(p.biome).capitalize(),
		int(p.fort_level),
		int(p.owner_id),
	]


func ui_get_mode_text() -> String:
	match pick_mode:
		TargetPickMode.ATTACK:
			return "Attack"
		TargetPickMode.TRANSFER:
			return "Transfer"
	return "None"


func ui_get_leader_list_text() -> Array:
	var out: Array = []
	for item in _get_selected_province_leaders(true):
		var leader: LeaderData = item as LeaderData
		if leader == null:
			continue
		out.append(_format_leader_entry(leader))
	return out


func _get_leader_order_text(leader_id: int) -> String:
	if game_state == null or game_state.order_book == null:
		return "Idle"
	var ob: OrderBook = game_state.order_book
	for o in ob.get_attacks(HUMAN_ID):
		if (o.get("leader_ids", []) as Array).has(leader_id):
			return "Attack P%d" % int(o["to"])
	for o in ob.get_transfers(HUMAN_ID):
		if (o.get("leader_ids", []) as Array).has(leader_id):
			return "→ P%d" % int(o["to"])
	for o in ob.get_missions(HUMAN_ID):
		if int(o.get("leader_id", -1)) == leader_id:
			return str(o.get("mission_type", "Mission")).capitalize()
	return "Idle"


func ui_toggle_leader_id(leader_id: int) -> void:
	selected_leader_id = leader_id
	if selected_leader_ids.has(leader_id):
		selected_leader_ids.erase(leader_id)
	else:
		if selected_leader_ids.size() >= 3:
			selected_leader_ids.remove_at(0)
		selected_leader_ids.append(leader_id)
	if _leader_panel != null:
		_leader_panel.refresh_highlights()
	debug_state_changed.emit()


func ui_get_selected_leader_ids() -> Array:
	return selected_leader_ids.duplicate()


func ui_get_selected_leader_index() -> int:
	var leaders_in_province: Array = _get_selected_province_leaders(true)
	for i in range(leaders_in_province.size()):
		var leader: LeaderData = leaders_in_province[i] as LeaderData
		if leader != null and int(leader.id) == selected_leader_id:
			return i
	return -1


func ui_select_leader_index(index: int) -> void:
	var leaders_in_province: Array = _get_selected_province_leaders(true)
	if index < 0 or index >= leaders_in_province.size():
		selected_leader_id = -1
		selected_leader_ids.clear()
		debug_state_changed.emit()
		return
	var leader: LeaderData = leaders_in_province[index] as LeaderData
	if leader == null:
		return
	var lid: int = int(leader.id)
	selected_leader_id = lid
	# Toggle in multi-select (max 3)
	if selected_leader_ids.has(lid):
		selected_leader_ids.erase(lid)
	else:
		if selected_leader_ids.size() < 3:
			selected_leader_ids.append(lid)
		else:
			# Replace oldest selection with new one
			selected_leader_ids.remove_at(0)
			selected_leader_ids.append(lid)
	debug_state_changed.emit()


func ui_get_selected_leader_indices() -> Array:
	var leaders_in_province: Array = _get_selected_province_leaders(true)
	var out: Array = []
	for i in range(leaders_in_province.size()):
		var leader: LeaderData = leaders_in_province[i] as LeaderData
		if leader != null and selected_leader_ids.has(int(leader.id)):
			out.append(i)
	return out


func ui_get_selected_leader_text() -> String:
	var leader: LeaderData = _get_selected_leader()
	if leader == null:
		return "Leader: (none)"
	var trait_text: String = "None"
	if not leader.traits.is_empty():
		trait_text = ", ".join(leader.traits)
	return "Leader: %s | Ld:%d At:%d Df:%d Mg:%d | Traits:%s" % [
		_format_leader_entry(leader),
		int(leader.leadership),
		int(leader.attack),
		int(leader.defense),
		int(leader.magic),
		trait_text
	]


func ui_get_mission_types() -> Array:
	return ["search", "recruit", "train"]


func ui_queue_selected_mission(mission_type: String) -> void:
	if selected_province_id == -1:
		return
	if game_state == null or game_state.order_book == null:
		return

	var p: ProvinceData = map_data.provinces[selected_province_id] as ProvinceData
	if int(p.owner_id) != HUMAN_ID:
		DebugLogger.log("Queue MISSION blocked | source not HUMAN | P%d owner=%d" % [selected_province_id, int(p.owner_id)])
		return

	var leader: LeaderData = _get_selected_leader()
	if leader == null:
		leader = game_state.get_first_available_leader_in_province(int(p.id))
	if leader == null:
		DebugLogger.log("Queue MISSION blocked | no leader selected | P%d" % selected_province_id)
		return

	var busy: bool = false
	if "on_mission" in leader:
		busy = bool(leader.on_mission)
	else:
		busy = (str(leader.status) == "mission")

	if busy:
		DebugLogger.log("Queue MISSION blocked | leader busy | %s" % leader.display_name)
		return

	var leader_province_id: int = int(leader.current_province_id)

	if leader_province_id != int(p.id):
		DebugLogger.log("Queue MISSION blocked | leader not stationed | %s" % leader.display_name)
		return

	var normalized_type: String = mission_type.strip_edges().to_lower()
	if normalized_type == "":
		normalized_type = "search"

	game_state.order_book.queue_mission(HUMAN_ID, int(p.id), int(leader.id), normalized_type, TurnManager.MISSION_DEFAULT_DURATION)
	DebugLogger.log("Queue MISSION | P%d | leader=%s | type=%s" % [int(p.id), leader.display_name, normalized_type])
	debug_state_changed.emit()


func ui_get_orders_text() -> String:
	if game_state == null or game_state.order_book == null:
		return ""

	var ob: OrderBook = game_state.order_book
	var lines: Array[String] = []

	lines.append("Your Upgrades")
	var ups: Array = ob.get_upgrades(HUMAN_ID)
	if ups.is_empty():
		lines.append("(none)")
	else:
		for o in ups:
			lines.append("Upgrade P%d (cost %d)" % [int(o["province_id"]), int(o["cost"])])

	lines.append("")
	lines.append("Your Transfers")
	var trs: Array = ob.get_transfers(HUMAN_ID)
	if trs.is_empty():
		lines.append("(none)")
	else:
		for o in trs:
			var lids: Array = o.get("leader_ids", [])
			lines.append("Transfer P%d -> P%d | leaders=%s" % [
				int(o["from"]),
				int(o["to"]),
				str(lids)
			])

	lines.append("")
	lines.append("Your Missions")
	var missions: Array = ob.get_missions(HUMAN_ID)
	if missions.is_empty():
		lines.append("(none)")
	else:
		for o in missions:
			var mission_leader: LeaderData = game_state.get_leader(int(o.get("leader_id", -1)))
			var mission_leader_name: String = mission_leader.display_name if mission_leader != null else "Leader ?"
			lines.append("Mission %s: P%d | %s (%dT)" % [
				str(o["mission_type"]).capitalize(),
				int(o["province_id"]),
				mission_leader_name,
				int(o["duration_turns"])
			])

	lines.append("")
	lines.append("Your Attacks")
	var atks: Array = ob.get_attacks(HUMAN_ID)
	if atks.is_empty():
		lines.append("(none)")
	else:
		for o in atks:
			var lids: Array = o.get("leader_ids", [])
			lines.append("Attack P%d -> P%d | leaders=%s" % [
				int(o["from"]),
				int(o["to"]),
				str(lids)
			])

	lines.append("")
	lines.append("Your Promotions")
	var promos: Array = ob.get_promotions(HUMAN_ID)
	if promos.is_empty():
		lines.append("(none)")
	else:
		for o in promos:
			var uid: int = int(o["unit_id"])
			var punit = game_state.get_unit(uid)
			var uname: String = str(punit.unit_type) if punit != null else "Unit?"
			lines.append("Promote unit#%d (%s) cost %dg" % [uid, uname, int(o["cost"])])

	return "\n".join(lines)


func ui_start_attack() -> void:
	if selected_province_id == -1:
		return
	# Hard rule: only HUMAN-owned provinces can issue orders
	var src: ProvinceData = map_data.provinces[selected_province_id] as ProvinceData
	if int(src.owner_id) != HUMAN_ID:
		DebugLogger.log('Mode ATTACK blocked | source not HUMAN | P%d owner=%d' % [selected_province_id, int(src.owner_id)])
		return

	_pick_source_id = selected_province_id
	pick_mode = TargetPickMode.ATTACK
	DebugLogger.log("Mode ATTACK | source=P%d" % _pick_source_id)
	debug_state_changed.emit()


func ui_start_transfer() -> void:
	if selected_province_id == -1:
		return
	# Hard rule: only HUMAN-owned provinces can issue orders
	var src: ProvinceData = map_data.provinces[selected_province_id] as ProvinceData
	if int(src.owner_id) != HUMAN_ID:
		DebugLogger.log('Mode TRANSFER blocked | source not HUMAN | P%d owner=%d' % [selected_province_id, int(src.owner_id)])
		return

	_pick_source_id = selected_province_id
	pick_mode = TargetPickMode.TRANSFER
	DebugLogger.log("Mode TRANSFER | source=P%d" % _pick_source_id)
	debug_state_changed.emit()


func ui_queue_upgrade() -> void:
	if selected_province_id == -1:
		return
	if game_state == null or game_state.order_book == null:
		return

	var p: ProvinceData = map_data.provinces[selected_province_id] as ProvinceData
	if int(p.owner_id) != HUMAN_ID:
		return

	var f: FactionData = _find_faction(HUMAN_ID)
	if f == null:
		return

	var cost: int = TurnManager.FORT_BASE_COST * maxi(1, int(p.fort_level))
	if int(f.gold) < cost:
		DebugLogger.log("Queue UPGRADE blocked | not enough gold | need=%d have=%d" % [cost, int(f.gold)])
		return

	game_state.order_book.queue_upgrade(HUMAN_ID, int(p.id), cost)
	DebugLogger.log("Queue UPGRADE | P%d | cost=%d" % [int(p.id), cost])
	debug_state_changed.emit()


func ui_queue_mission() -> void:
	ui_queue_selected_mission("search")


func ui_cancel_mode() -> void:
	pick_mode = TargetPickMode.NONE
	_pick_source_id = -1
	DebugLogger.log("Mode CANCEL")
	debug_state_changed.emit()


func ui_get_gold_text() -> String:
	var f: FactionData = _find_faction(HUMAN_ID)
	if f == null:
		return "Gold: --"
	return "Gold: %d" % int(f.gold)


func ui_get_upkeep_text() -> String:
	var f: FactionData = _find_faction(HUMAN_ID)
	if f == null or game_state == null:
		return "Upkeep: --/mo"
	var upkeep: int = 0
	for lid_val in f.leader_ids:
		var leader: LeaderData = game_state.get_leader(int(lid_val))
		if leader == null:
			continue
		upkeep += int(leader.upkeep_cost)
		for uid_val in leader.army_unit_ids:
			var unit = game_state.get_unit(int(uid_val))
			if unit != null:
				upkeep += int((unit as UnitData).upkeep_cost)
	return "Upkeep: %d/mo" % upkeep


func ui_recruit_unit(unit_type: String) -> void:
	if selected_province_id == -1 or game_state == null:
		return
	var p: ProvinceData = map_data.provinces[selected_province_id] as ProvinceData
	if int(p.owner_id) != HUMAN_ID:
		DebugLogger.log("Recruit blocked | not your province | P%d" % selected_province_id)
		return
	var success: bool = game_state.recruit_unit(HUMAN_ID, selected_province_id, unit_type)
	if success:
		DebugLogger.log("Recruited %s at P%d" % [unit_type, selected_province_id])
		if _leader_panel != null:
			_leader_panel.refresh(selected_province_id)
		if _recruit_panel != null:
			_refresh_recruit_for_province(selected_province_id)
		debug_state_changed.emit()
	else:
		DebugLogger.log("Recruit failed | %s at P%d" % [unit_type, selected_province_id])


func _on_dismiss_general(leader_id: int) -> void:
	if game_state == null:
		return
	var ok: bool = game_state.dismiss_general(leader_id)
	if ok:
		selected_leader_ids.erase(leader_id)
		if selected_leader_id == leader_id:
			selected_leader_id = -1
		if _leader_panel != null:
			_leader_panel.refresh(selected_province_id)
		debug_state_changed.emit()
		queue_redraw()


func ui_clear_orders() -> void:
	if game_state == null or game_state.order_book == null:
		return
	game_state.order_book.clear_orders_for_faction(HUMAN_ID)
	DebugLogger.log("Clear orders | faction=%d" % HUMAN_ID)
	debug_state_changed.emit()
	queue_redraw()


func ui_execute_month() -> void:
	if turn_manager == null or game_state == null:
		return

	DebugLogger.log("=== EXECUTE MONTH start | month=%d ===" % int(game_state.month_index))

	if _mission_panel != null:
		_mission_panel.clear_results()

	await turn_manager.execute_month(game_state, HUMAN_ID, AI_ID, true)
	DebugLogger.log("=== EXECUTE MONTH end | month=%d ===" % int(game_state.month_index))

	if _mission_panel != null:
		if not game_state.pending_mission_results.is_empty():
			_mission_panel.push_results(game_state.pending_mission_results)
		_mission_panel.refresh(selected_province_id)

	_rebuild_voronoi()
	if _leader_panel != null and selected_province_id >= 0:
		_leader_panel.refresh(selected_province_id)
	_refresh_recruit_for_province(selected_province_id)

	# Clear human orders — resolver has processed them; stale orders cause
	# arrows and province status to show outdated attack/transfer info.
	game_state.order_book.clear_orders_for_faction(HUMAN_ID)

	selected_leader_ids.clear()
	queue_redraw()
	# Deferred so the frame fully completes before UI reads month_index
	call_deferred("_post_execute_refresh")

	# --- Campaign end check ---
	_check_campaign_end()




func _post_execute_refresh() -> void:
	queue_redraw()
	debug_state_changed.emit()


# Run N months with no human player — all battles resolve headlessly.
var _headless_months_target: int = 72
var _headless_running: bool = false
var _headless_month_live: int = 0
const HEADLESS_MONTH_OPTIONS: Array = [1, 12, 24, 36, 72, 120]

func ui_cycle_headless_months() -> void:
	var idx: int = HEADLESS_MONTH_OPTIONS.find(_headless_months_target)
	idx = (idx + 1) % HEADLESS_MONTH_OPTIONS.size()
	_headless_months_target = int(HEADLESS_MONTH_OPTIONS[idx])
	debug_state_changed.emit()

func ui_get_headless_months_text() -> String:
	return "AI Headless: %dm" % _headless_months_target

func ui_execute_month_headless() -> void:
	if turn_manager == null or game_state == null or _headless_running:
		return
	_headless_running = true
	_headless_month_live = int(game_state.month_index)
	debug_state_changed.emit()
	# Run the full loop (including teardown) inside one coroutine — avoids cross-coroutine await drop
	call_deferred("_run_headless_loop", _headless_months_target, HUMAN_ID)

func _run_headless_loop(target: int, saved_human: int) -> void:
	HUMAN_ID = -1
	game_state.human_faction_id = -1
	if _mission_panel != null:
		_mission_panel.set_human_faction(-1)
	DebugLogger.log("=== HEADLESS RUN start | from_month=%d target=%d ===" % [int(game_state.month_index), target])

	for _i in range(target):
		var _alive: int = 0
		for _f in game_state.map_data.factions:
			var _fd = _f as FactionData
			if _fd != null and not bool(_fd.is_eliminated):
				_alive += 1
		if _alive <= 1:
			break
		var _month_before: int = int(game_state.month_index)
		DebugLogger.log("headless:month_attempt", {"month": _month_before + 1, "alive": _alive})
		# Crash fence: 15s timeout watchdog
		var _fence_timer := get_tree().create_timer(15.0)
		var _fence_timed_out := false
		_fence_timer.timeout.connect(func() -> void: _fence_timed_out = true)
		await turn_manager.execute_month_with_summary(game_state, -1, AI_ID, true)
		if _fence_timed_out or game_state.month_index <= _month_before:
			DebugLogger.log("headless:HANG_DETECTED", {"month": _month_before + 1})
			push_error("KINGDOM: Headless run hung at month %d — aborting" % (_month_before + 1))
			break
		_headless_month_live = int(game_state.month_index)
		debug_state_changed.emit()

	# Teardown — runs in the same coroutine that ran the loop
	_headless_running = false
	HUMAN_ID = saved_human
	game_state.human_faction_id = saved_human
	if _mission_panel != null:
		_mission_panel.set_human_faction(saved_human)
		if not game_state.pending_mission_results.is_empty():
			_mission_panel.push_results(game_state.pending_mission_results)
		_mission_panel.refresh(selected_province_id)
	DebugLogger.log("=== HEADLESS RUN end | month=%d ===" % int(game_state.month_index))
	_rebuild_voronoi()
	if _leader_panel != null and selected_province_id >= 0:
		_leader_panel.refresh(selected_province_id)
	_refresh_recruit_for_province(selected_province_id)
	selected_leader_ids.clear()
	queue_redraw()
	call_deferred("_post_execute_refresh")
	_check_campaign_end()


func _clear_ai_lab_preview() -> void:
	_ai_lab_preview_map_data = null
	_ai_lab_preview_owner_by_province.clear()
	if map_data != null:
		_rebuild_voronoi_from(map_data)
		_frame_map_from(map_data)
	queue_redraw()


func _get_draw_map_data() -> MapData:
	if _ai_lab_running and _ai_lab_preview_map_data != null:
		return _ai_lab_preview_map_data
	return map_data


func _get_draw_owner_id(province_id: int, fallback_owner_id: int) -> int:
	if _ai_lab_running and _ai_lab_preview_owner_by_province.has(province_id):
		return int(_ai_lab_preview_owner_by_province.get(province_id, fallback_owner_id))
	return fallback_owner_id


func ui_get_month_text() -> String:
	if _ai_lab_running:
		return "Month: %d (Lab)" % int(_ai_lab_month_live)
	if _headless_running:
		return "Month: %d / %d (Headless)" % [_headless_month_live, _headless_months_target]
	if game_state == null:
		return "Month: --"
	return "Month: %d" % int(game_state.month_index)


func ui_get_ai_lab_status_text() -> String:
	return _ai_lab_progress_text


func ui_get_ai_lab_running() -> bool:
	return _ai_lab_running or _autotune_running


func ui_get_autotune_status_text() -> String:
	return _autotune_progress_text


func ui_get_ai_lab_button_text() -> String:
	if _ai_lab_running:
		return "AI Lab Running..."
	return "AI Lab Pass"



func ui_get_ai_lab_months_text() -> String:
	return "AI Lab: %dm" % int(_ai_lab_months_setting)


func ui_cycle_ai_lab_months() -> void:
	if _ai_lab_running:
		return
	var idx: int = AI_LAB_MONTH_OPTIONS.find(_ai_lab_months_setting)
	if idx == -1:
		idx = 0
	else:
		idx = (idx + 1) % AI_LAB_MONTH_OPTIONS.size()
	_ai_lab_months_setting = AI_LAB_MONTH_OPTIONS[idx]
	debug_state_changed.emit()


func _on_ai_lab_progress(payload: Dictionary) -> void:
	var status: String = str(payload.get("status", "running"))
	var month: int = int(payload.get("month", 0))
	var months: int = int(payload.get("months", 0))
	var seed_index: int = int(payload.get("seed_index", -1))
	var seed_count: int = int(payload.get("seed_count", 0))
	var iteration: int = int(payload.get("iteration", 0))
	var candidate_index: int = int(payload.get("candidate_index", -1))
	_ai_lab_month_live = month
	if payload.has("preview_map_data"):
		var preview_map: MapData = payload.get("preview_map_data") as MapData
		if preview_map != null and preview_map != _ai_lab_preview_map_data:
			_ai_lab_preview_map_data = preview_map
			_rebuild_voronoi_from(_ai_lab_preview_map_data)
			_frame_map_from(_ai_lab_preview_map_data)
	if payload.has("owner_by_province"):
		_ai_lab_preview_owner_by_province = (payload.get("owner_by_province", {}) as Dictionary).duplicate(true)
	if status == "month_complete":
		_ai_lab_progress_text = "AI Lab: iter %d cand %d seed %d/%d month %d/%d" % [iteration, candidate_index, seed_index + 1, maxi(1, seed_count), month, maxi(1, months)]
	elif status == "seed_started":
		_ai_lab_progress_text = "AI Lab: iter %d cand %d seed %d/%d starting" % [iteration, candidate_index, seed_index + 1, maxi(1, seed_count)]
	elif status == "seed_finished":
		_ai_lab_progress_text = "AI Lab: iter %d cand %d seed %d/%d complete" % [iteration, candidate_index, seed_index + 1, maxi(1, seed_count)]
	else:
		_ai_lab_progress_text = "AI Lab: %s" % status
	queue_redraw()
	debug_state_changed.emit()


func _on_autotune_progress(payload: Dictionary) -> void:
	# Drives live map preview and status text during autotuner runs.
	# Mirrors _on_ai_lab_progress — both share the same preview infrastructure.
	var status: String  = str(payload.get("status", "running"))
	var month: int      = int(payload.get("month", 0))
	var months: int     = int(payload.get("months", 0))
	var seed_index: int = int(payload.get("seed_index", -1))
	var seed_count: int = int(payload.get("seed_count", 0))
	var iteration: int  = int(payload.get("iteration", 0))
	var score: float    = float(payload.get("score", 0.0))
	var phase: int      = int(payload.get("phase", 1))
	var stall: int      = int(payload.get("stall_count", 0))
	var candidate: int  = int(payload.get("candidate_index", -1))
	var cand_total: int = int(payload.get("candidate_count", 0))

	_autotune_month_live     = month
	_autotune_seed_live      = seed_index + 1
	_autotune_seed_total     = seed_count
	_autotune_iteration_live = iteration

	# Live map preview — identical to ai lab preview path
	if payload.has("preview_map_data"):
		var preview_map: MapData = payload.get("preview_map_data") as MapData
		if preview_map != null and preview_map != _ai_lab_preview_map_data:
			_ai_lab_preview_map_data = preview_map
			_rebuild_voronoi_from(_ai_lab_preview_map_data)
			_frame_map_from(_ai_lab_preview_map_data)
	if payload.has("owner_by_province"):
		_ai_lab_preview_owner_by_province = (payload.get("owner_by_province", {}) as Dictionary).duplicate(true)

	# Set _ai_lab_running so the existing draw path renders preview colours
	var is_active: bool = (status != "complete" and status != "stopped")
	if is_active and not _autotune_running:
		_autotune_running = true
		_ai_lab_running   = true

	# Sync month counter so the Month label shows current simulation month
	if _autotune_running:
		_ai_lab_month_live = month

	# Build status text with full counters
	match status:
		"baseline_start":
			_autotune_progress_text = "AutoTune: Baseline..."
		"baseline_complete":
			_autotune_progress_text = "AutoTune: Baseline score %.0f" % score
		"resumed":
			_autotune_progress_text = "AutoTune: Resumed iter %d score %.0f" % [iteration, score]
		"month_complete":
			_autotune_progress_text = "AutoTune: iter %d | seed %d/%d | month %d/%d" % [iteration, maxi(1, seed_index + 1), maxi(1, seed_count), month, maxi(1, months)]
		"seed_started":
			_autotune_progress_text = "AutoTune: iter %d | seed %d/%d | starting" % [iteration, seed_index + 1, maxi(1, seed_count)]
		"seed_finished":
			_autotune_progress_text = "AutoTune: iter %d | seed %d/%d | done" % [iteration, seed_index + 1, maxi(1, seed_count)]
		"candidate_evaluated":
			if cand_total > 0:
				_autotune_progress_text = "AutoTune: iter %d | cand %d/%d | Ph%d | Best %.0f" % [iteration, candidate + 1, cand_total, phase, score]
			else:
				_autotune_progress_text = "AutoTune: iter %d | Best %.0f" % [iteration, score]
		"iteration_complete":
			_autotune_progress_text = "AutoTune: iter %d done | Best %.0f | Stall %d" % [iteration, score, stall]
		"validation_start":
			_autotune_progress_text = "AutoTune: Validating..."
		"complete":
			var goals: bool = bool(payload.get("goals_met", false))
			var val: bool   = bool(payload.get("validation_passed", false))
			_autotune_progress_text = "AutoTune: Done %s | Score %.0f" % ["✓" if goals and val else "~", score]
			_autotune_running = false
			_ai_lab_running   = false
			_clear_ai_lab_preview()
		_:
			_autotune_progress_text = "AutoTune: %s" % status

	queue_redraw()
	debug_state_changed.emit()


func ui_get_settings() -> MapSettings:
	return settings


func ui_get_map_size_text() -> String:
	if settings == null:
		return "Map Size: --"
	return "Map Size: %d" % int(settings.province_count)


func ui_cycle_map_size() -> void:
	if settings == null or _ai_lab_running:
		return
	var current: int = int(settings.province_count)
	var idx: int = MAP_SIZE_OPTIONS.find(current)
	if idx == -1:
		idx = 0
	else:
		idx = (idx + 1) % MAP_SIZE_OPTIONS.size()
	settings.province_count = MAP_SIZE_OPTIONS[idx]
	DebugLogger.log("map_size_changed", {"province_count": int(settings.province_count)})
	_build_fresh_state()



func ui_run_ai_lab() -> void:
	if settings == null or game_state == null or _ai_lab_running:
		return
	_ai_lab_running = true
	_ai_lab_month_live = 0
	_ai_lab_progress_text = "AI Lab: starting..."
	_clear_ai_lab_preview()
	debug_state_changed.emit()
	DebugLogger.log("ai_lab_requested", {"months": int(_ai_lab_months_setting), "iterations": 4, "seed_count": 12})
	call_deferred("_run_ai_lab_deferred")


func _run_ai_lab_deferred() -> void:
	var lab = AIBalanceLabScript.new()
	var base_profile = null
	if game_state != null and game_state.has_method("get_ai_tuning_profile"):
		base_profile = game_state.get_ai_tuning_profile()
	var report: Dictionary = await lab.run_autotune_async(self, settings, int(_ai_lab_months_setting), 4, 12, base_profile)
	_ai_lab_running = false
	_ai_lab_month_live = 0
	if report.is_empty():
		_ai_lab_progress_text = "AI Lab: failed"
		DebugLogger.log("ai_lab_failed", {"reason": "empty_report"})
		debug_state_changed.emit()
		return
	if game_state != null and game_state.get_ai_tuning_profile() != null:
		game_state.get_ai_tuning_profile().apply_dictionary(report.get("best_profile", {}))
	_clear_ai_lab_preview()
	_ai_lab_progress_text = "AI Lab: complete"
	DebugLogger.log("ai_lab_applied", report)
	debug_state_changed.emit()

func _find_faction(fid: int) -> FactionData:
	for item in map_data.factions:
		var f: FactionData = item as FactionData
		if int(f.id) == fid:
			return f
	return null


# =====================================================
# VORONOI
# =====================================================

func _rebuild_voronoi() -> void:
	_rebuild_voronoi_from(map_data)


func _rebuild_voronoi_from(data: MapData) -> void:
	_voronoi_cells.clear()
	if data == null or data.provinces.is_empty():
		return

	var bounds: Rect2 = _compute_bounds_from(data)

	for item_a in data.provinces:
		var a: ProvinceData = item_a as ProvinceData

		var poly: Array = [
			bounds.position,
			bounds.position + Vector2(bounds.size.x, 0.0),
			bounds.position + bounds.size,
			bounds.position + Vector2(0.0, bounds.size.y)
		]

		for item_b in data.provinces:
			var b: ProvinceData = item_b as ProvinceData
			if a == b:
				continue

			poly = _clip_cell(poly, a.center, b.center)
			if poly.size() < 3:
				break

		_voronoi_cells[int(a.id)] = poly


func _clip_cell(poly: Array, a: Vector2, b: Vector2) -> Array:
	var out: Array = []

	var mid: Vector2 = (a + b) * 0.5
	var normal: Vector2 = (b - a).normalized()

	var prev: Vector2 = poly[poly.size() - 1]
	var prev_in: bool = (prev - mid).dot(normal) <= 0.0

	for curr in poly:
		var curr_v: Vector2 = curr
		var curr_in: bool = (curr_v - mid).dot(normal) <= 0.0

		if curr_in != prev_in:
			var dir: Vector2 = curr_v - prev
			var denom: float = dir.dot(normal)
			if absf(denom) > 0.000001:
				var t: float = ((mid - prev).dot(normal)) / denom
				out.append(prev + dir * t)

		if curr_in:
			out.append(curr_v)

		prev = curr_v
		prev_in = curr_in

	return out


# =====================================================
# DRAW
# =====================================================


func _refresh_recruit_for_province(pid: int) -> void:
	if _recruit_panel == null:
		return
	if pid >= 0 and map_data != null and pid < map_data.provinces.size():
		var p: ProvinceData = map_data.provinces[pid] as ProvinceData
		# Find highest-level human leader in this province to gate recruitable tiers
		var leader_level: int = 1
		if game_state != null:
			for leader in game_state.get_province_leaders(pid, false):
				if leader != null and int(leader.faction_id) == int(HUMAN_ID):
					leader_level = maxi(leader_level, int(leader.level))
		_recruit_panel.refresh(str(p.biome), leader_level)
	else:
		_recruit_panel.refresh()


func _draw() -> void:
	if _get_draw_map_data() == null:
		return

	_draw_cells()
	_draw_routes()
	_draw_orders()
	_draw_nodes()
	_draw_labels()


func _draw_cells() -> void:
	var draw_map: MapData = _get_draw_map_data()
	if draw_map == null:
		return
	for item in draw_map.provinces:
		var p: ProvinceData = item as ProvinceData
		if !_voronoi_cells.has(int(p.id)):
			continue

		var poly_pts: PackedVector2Array = PackedVector2Array()
		for v in _voronoi_cells[int(p.id)]:
			poly_pts.append(_to_screen(v))

		# Fill: biome color blended with a faction color tint for owned provinces
		var biome_c: Color = _biome_color(p.biome)
		var fill_c: Color = biome_c
		var owner_id: int = _get_draw_owner_id(int(p.id), int(p.owner_id))
		if owner_id >= 0:
			var faction_c: Color = _owner_color(owner_id)
			# Blend 30% faction color into the biome fill so ownership is visible
			fill_c = biome_c.lerp(faction_c, 0.30)
		fill_c.a = 0.70
		draw_colored_polygon(poly_pts, fill_c)

		# Border: thick faction-colored outline
		var border_c: Color = _owner_color(owner_id)
		border_c.a = 0.92
		var border_w: float = 3.0 if owner_id >= 0 else 1.0
		draw_polyline(poly_pts, border_c, border_w, true)


func _draw_routes() -> void:
	var draw_map: MapData = _get_draw_map_data()
	if draw_map == null:
		return
	for r in draw_map.routes:
		var a: ProvinceData = draw_map.provinces[int(r.a)] as ProvinceData
		var b: ProvinceData = draw_map.provinces[int(r.b)] as ProvinceData

		draw_line(_to_screen(a.center), _to_screen(b.center), Color(1, 1, 1, 0.4), 1.0)


func _draw_orders() -> void:
	if game_state == null or game_state.order_book == null:
		return

	var ob: OrderBook = game_state.order_book

	# Draw transfers (green)
	for o in ob.get_transfers(HUMAN_ID):
		var a: int = int(o["from"])
		var b: int = int(o["to"])
		var pa: ProvinceData = map_data.provinces[a] as ProvinceData
		var pb: ProvinceData = map_data.provinces[b] as ProvinceData
		draw_line(_to_screen(pa.center), _to_screen(pb.center), Color(0.2, 1.0, 0.2, 0.9), 3.0)

	# Draw attacks (red)
	for o in ob.get_attacks(HUMAN_ID):
		var a2: int = int(o["from"])
		var b2: int = int(o["to"])
		var pa2: ProvinceData = map_data.provinces[a2] as ProvinceData
		var pb2: ProvinceData = map_data.provinces[b2] as ProvinceData
		draw_line(_to_screen(pa2.center), _to_screen(pb2.center), Color(1.0, 0.2, 0.2, 0.9), 3.0)


func _draw_nodes() -> void:
	var draw_map: MapData = _get_draw_map_data()
	if draw_map == null:
		return
	for item in draw_map.provinces:
		var p: ProvinceData = item as ProvinceData
		var pos: Vector2 = _to_screen(p.center)

		draw_circle(pos, NODE_RADIUS, _owner_color(_get_draw_owner_id(int(p.id), int(p.owner_id))))

		if int(p.id) == selected_province_id:
			draw_arc(pos, 14.0, 0.0, TAU, 48, Color.WHITE, 2.0)

		if int(p.id) == hover_province_id and hover_province_id != selected_province_id:
			draw_arc(pos, 10.5, 0.0, TAU, 36, Color(1.0, 0.6, 0.2), 2.0)


func _draw_labels() -> void:
	var draw_map: MapData = _get_draw_map_data()
	if draw_map == null:
		return
	for item in draw_map.provinces:
		var p: ProvinceData = item as ProvinceData
		var pos: Vector2 = _to_screen(p.center) + Vector2(10, -10)

		var txt: String = "%s\nF%d I%d | %s" % [
			str(p.display_name),
			int(p.fort_level),
			int(p.income),
			str(p.biome).capitalize()
		]

		draw_multiline_string(
			_label_font,
			pos,
			txt,
			HORIZONTAL_ALIGNMENT_LEFT,
			220,
			14
		)


# =====================================================
# COLORS
# =====================================================

func _owner_color(owner: int) -> Color:
	# Look up faction color from game_state so all 15 factions get distinct colors
	if game_state != null and game_state.map_data != null:
		for item in game_state.map_data.factions:
			var f: FactionData = item as FactionData
			if f != null and int(f.id) == owner:
				return f.color
	# Fallback: player=red, first AI=blue, unowned=grey
	if owner == HUMAN_ID:
		return Color(0.9, 0.2, 0.2)
	return Color(0.55, 0.55, 0.55)


func _biome_color(biome: String) -> Color:
	match biome:
		"plains":   return Color(0.55, 0.78, 0.40)   # muted green
		"forest":   return Color(0.18, 0.50, 0.22)   # dark green
		"mountain": return Color(0.60, 0.57, 0.52)   # grey-brown
		"desert":   return Color(0.87, 0.75, 0.40)   # sandy yellow
		"tundra":   return Color(0.72, 0.85, 0.90)   # icy blue-white
		"swamp":    return Color(0.32, 0.48, 0.32)   # murky green
		"coast":    return Color(0.30, 0.60, 0.80)   # ocean blue
		_:          return Color(0.50, 0.50, 0.50)   # fallback grey

# =====================================================
# CAMPAIGN END
# =====================================================

var _campaign_ended: bool = false

func _check_campaign_end() -> void:
	if _campaign_ended or game_state == null or game_state.map_data == null:
		return

	# Check human elimination first
	var human_faction: FactionData = null
	for item in game_state.map_data.factions:
		var f: FactionData = item as FactionData
		if f != null and int(f.id) == HUMAN_ID:
			human_faction = f
			break

	if human_faction != null and bool(human_faction.is_eliminated):
		_campaign_ended = true
		_show_campaign_overlay(false, str(human_faction.display_name))
		return

	# Check if only one faction remains
	var alive_factions: Array = []
	for item2 in game_state.map_data.factions:
		var f2: FactionData = item2 as FactionData
		if f2 != null and not bool(f2.is_eliminated):
			alive_factions.append(f2)

	if alive_factions.size() == 1:
		var winner: FactionData = alive_factions[0] as FactionData
		_campaign_ended = true
		_show_campaign_overlay(int(winner.id) == HUMAN_ID, str(winner.display_name))


func _show_campaign_overlay(victory: bool, faction_name: String) -> void:
	# Full-screen overlay — blocks further input
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.80)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(vbox)

	var title := Label.new()
	var sub := Label.new()

	if victory:
		title.text = "VICTORY"
		title.add_theme_color_override("font_color", Color(1.0, 0.90, 0.30))
		sub.text = "%s has conquered the realm." % faction_name
	else:
		title.text = "DEFEAT"
		title.add_theme_color_override("font_color", Color(0.90, 0.25, 0.25))
		sub.text = "%s has been eliminated." % faction_name

	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)

	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.80, 0.80, 0.85))
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sub)

	var month_lbl := Label.new()
	month_lbl.text = "Month %d" % int(game_state.month_index)
	month_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	month_lbl.add_theme_font_size_override("font_size", 13)
	month_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	month_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(month_lbl)

	var btn := Button.new()
	btn.text = "New Campaign"
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(func() -> void:
		_campaign_ended = false
		overlay.queue_free()
		_restart_campaign()
	)
	vbox.add_child(btn)


func _restart_campaign() -> void:
	# Tear down all panels and rebuild from scratch via faction picker
	if _leader_panel != null:
		_leader_panel.queue_free()
		_leader_panel = null
	if _recruit_panel != null:
		_recruit_panel.queue_free()
		_recruit_panel = null
	if _mission_panel != null:
		_mission_panel.queue_free()
		_mission_panel = null
	# Remove existing debug UI (first CanvasLayer child)
	for child in get_children():
		if child is CanvasLayer or child.get_class() == "Node":
			child.queue_free()

	# Regenerate map and show picker again
	var generator := MapGenerator.new()
	map_data = generator.generate_map(settings)

	var picker := FactionPicker.new()
	picker.init(map_data)
	picker.faction_selected.connect(_on_faction_picked)
	add_child(picker)


# --------------------------------------------------
# BATTLE LAB — run one suite and log results
# --------------------------------------------------
func ui_run_battle_lab() -> void:
	if _battle_lab_running:
		return
	_battle_lab_running = true
	DebugLogger.log("event:battle_lab_requested", {"seeds": 20})
	call_deferred("_run_battle_lab_deferred")


func _run_battle_lab_deferred() -> void:
	var results: Dictionary = BattleLabScript.run_full_suite(20)
	var profile: BattleTuningProfile = BattleTuningProfile.get_instance()
	var score: float = BattleLabScript.score_results(results, profile)
	DebugLogger.log("event:battle_lab_complete", {
		"score": score,
		"typical_win_rate": results.get("even_typical", {}).get("attacker_win_rate", -1),
		"typical_avg_rounds": results.get("even_typical", {}).get("avg_rounds", -1),
		"typical_stalemate_rate": results.get("even_typical", {}).get("stalemate_rate", -1),
		"max_win_rate": results.get("even_max", {}).get("attacker_win_rate", -1),
		"max_avg_rounds": results.get("even_max", {}).get("avg_rounds", -1),
		"max_stalemate_rate": results.get("even_max", {}).get("stalemate_rate", -1),
		"10pct_win_rate": results.get("10pct_advantage", {}).get("attacker_win_rate", -1),
		"25pct_win_rate": results.get("25pct_advantage", {}).get("attacker_win_rate", -1),
		"type_dis_win_rate": results.get("type_disadvantage", {}).get("attacker_win_rate", -1),
		"leader_duel_avg_rounds": results.get("leader_duel", {}).get("avg_rounds", -1),
	})
	_battle_lab_running = false


# --------------------------------------------------
# BATTLE TUNER — hill-climb to find best knobs
# --------------------------------------------------
func ui_run_battle_tune() -> void:
	if _battle_tune_running:
		return
	_battle_tune_running = true
	DebugLogger.log("event:battle_tune_requested", {"iterations": 60, "seeds": 20})
	call_deferred("_run_battle_tune_deferred")


func _run_battle_tune_deferred() -> void:
	if _battle_autotuner != null:
		_battle_autotuner.queue_free()
	_battle_autotuner = BattleAutoTunerScript.new()
	add_child(_battle_autotuner)
	_battle_autotuner.tuning_complete.connect(func(best_score: float, best_profile: Dictionary):
		DebugLogger.log("event:battle_tune_complete", {
			"best_score": best_score, "best_profile": best_profile
		})
		# Apply best profile to singleton
		_battle_autotuner.apply_best_profile()
		_battle_tune_running = false
	)
	await _battle_autotuner.start(60, 20)


# =====================================================
# MISSION TUNER
# =====================================================

func ui_run_mission_tune() -> void:
	if _mission_tune_running:
		return
	_mission_tune_running = true
	DebugLogger.log("event:mission_tune_requested", {"iterations": 60})
	call_deferred("_run_mission_tune_deferred")


func _run_mission_tune_deferred() -> void:
	if _mission_autotuner != null:
		_mission_autotuner.queue_free()
	_mission_autotuner = MissionAutoTunerScript.new()
	add_child(_mission_autotuner)
	_mission_autotuner.tuning_complete.connect(func(best_score: float, best_profile: Dictionary):
		DebugLogger.log("event:mission_tune_complete", {
			"best_score": best_score, "best_profile": best_profile
		})
		_mission_autotuner.apply_best_profile()
		_mission_tune_running = false
	)
	await _mission_autotuner.start(60)


func ui_get_mission_tune_text() -> String:
	if _mission_tune_running:
		return "Mission Tune: Running..."
	return "Mission Tune"


# =====================================================
# DEBUG INJECTOR TOGGLE
# =====================================================

func ui_toggle_injector_panel() -> void:
	if _injector_panel == null:
		return
	if _injector_panel.visible:
		_injector_panel.hide()
	else:
		_injector_panel.refresh(selected_province_id)
		_injector_panel.show()


# =====================================================
# DEBUG LEVEL UP — levels all leaders + units in selected province
# =====================================================

func ui_levelup_province() -> void:
	if game_state == null or selected_province_id < 0:
		DebugLogger.log("levelup: no province selected")
		return
	var province = map_data.provinces[selected_province_id]
	if province == null:
		return

	var leveled: int = 0

	# Level up all leaders in province
	for lid in province.leader_ids:
		var leader = game_state.get_leader(int(lid))
		if leader == null:
			continue
		# Give enough XP to gain exactly 1 level
		var xp_needed: int = int(leader.xp_to_next_level) - int(leader.xp) + 1
		leader.add_xp(xp_needed)
		leveled += 1
		DebugLogger.log("debug:levelup_leader", {"name": str(leader.display_name), "new_level": int(leader.level)})

	# Level up all units assigned to leaders in province
	for lid in province.leader_ids:
		var leader = game_state.get_leader(int(lid))
		if leader == null:
			continue
		for uid in leader.army_unit_ids:
			var unit = game_state.get_unit(int(uid))
			if unit == null:
				continue
			var xp_needed: int = int(unit.xp_to_next_level) - int(unit.xp) + 1
			unit.add_xp(xp_needed)
			leveled += 1
			DebugLogger.log("debug:levelup_unit", {"type": str(unit.unit_type), "new_level": int(unit.level)})

	DebugLogger.log("debug:levelup_done", {"province": selected_province_id, "entities_leveled": leveled})

	if _leader_panel != null:
		_leader_panel.refresh(selected_province_id)
	debug_state_changed.emit()
