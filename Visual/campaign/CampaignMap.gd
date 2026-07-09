# ==================================================
# CampaignMap
# ==================================================
# Main in-game scene. Manages:
#   - MapDebugView (simulation engine + dev tools)
#   - PlayerMap    (player-facing visual map)
#   - MapHUD       (top/bottom bars, End Turn)
#   - ProvinceTooltip / ProvincePanel
#   - PauseMenu
#   - Win/lose routing via TurnManager signal
#
# Phase 2: PlayerMap is the default view.
#           DEV button toggles the debug view on top.
# ==================================================
extends Node
class_name CampaignMap

const MapDebugViewScene  := preload("res://map_debug_view.tscn")
const PlayerMapScript    := preload("res://Visual/campaign/PlayerMap.gd")
const MapHUDScript       := preload("res://Visual/campaign/MapHUD.gd")
const TooltipScript      := preload("res://Visual/campaign/ProvinceTooltip.gd")
const ProvincePanelScene := preload("res://Visual/campaign/ProvincePanel.tscn")
const PauseMenuScene     := preload("res://Visual/menus/PauseMenu.tscn")
const TurnManagerScript  := preload("res://Scripts/game/turn_manager.gd")

const PICK_NONE:     int = 0
const PICK_ATTACK:   int = 1
const PICK_TRANSFER: int = 2

const MUSIC_TRACKS: Array = [
	"res://Audio/music/campaign_map_theme.wav",
	"res://Audio/music/campaign_map_theme5.wav",
]
static var _music_index: int = 0

var _debug_view: Node
var _player_map: PlayerMap
var _hud: MapHUD
var _tooltip: ProvinceTooltip
var _province_panel: ProvincePanel

var _game_state: GameState
var _map_data: MapData
var _human_id: int = 0
var _turn_manager: TurnManager
var _processing_turn: bool = false
var _pause_open: bool = false

var _pick_mode: int = PICK_NONE
var _pick_source_id: int = -1
var _selected_province_id: int = -1
var _mission_panel: MissionPanel = null


func _ready() -> void:
	_init_debug_view()
	_init_player_map()
	_init_hud()
	_init_tooltip()
	_init_province_panel()
	call_deferred("_post_init")
	call_deferred("_fade_in")


func _fade_in() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var rect := ColorRect.new()
	rect.color = Color(0.0, 0.0, 0.0, 1.0)
	rect.position = Vector2.ZERO
	rect.size = get_viewport().get_visible_rect().size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	var tween := create_tween()
	tween.tween_interval(2.0)
	tween.tween_property(rect, "color:a", 0.0, 2.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(layer.queue_free)

	# Start campaign map music, cycle through tracks when each finishes
	var music := AudioStreamPlayer.new()
	music.name = "CampaignMusic"
	music.stream = load(MUSIC_TRACKS[_music_index]) as AudioStream
	_music_index = (_music_index + 1) % MUSIC_TRACKS.size()
	music.volume_db = -80.0
	music.autoplay = false
	add_child(music)
	music.finished.connect(_on_music_finished.bind(music))
	music.play()
	var music_tween := create_tween()
	music_tween.tween_property(music, "volume_db", 0.0, 3.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _on_music_finished(music: AudioStreamPlayer) -> void:
	if not is_instance_valid(music):
		return
	music.stream = load(MUSIC_TRACKS[_music_index]) as AudioStream
	_music_index = (_music_index + 1) % MUSIC_TRACKS.size()
	music.play()


# --------------------------------------------------
# Initialization
# --------------------------------------------------
func _init_debug_view() -> void:
	# When launched via FactionSelect, skip the debug view entirely —
	# its CanvasLayer children ignore parent visibility and would bleed through.
	# The debug view is only needed when launching directly from the editor.
	if SceneManager.pending_game_state != null:
		return
	_debug_view = MapDebugViewScene.instantiate()
	add_child(_debug_view)
	_debug_view.visible = false


func _init_player_map() -> void:
	_player_map = PlayerMapScript.new()
	add_child(_player_map)
	_player_map.province_hovered.connect(_on_province_hovered)
	_player_map.province_clicked.connect(_on_province_clicked)


func _init_hud() -> void:
	_hud = MapHUDScript.new()
	add_child(_hud)
	_hud.end_turn_pressed.connect(_on_end_turn)
	_hud.dev_toggle_pressed.connect(_on_dev_toggle)
	_hud.pause_pressed.connect(_on_pause)
	_hud.attack_pressed.connect(_on_attack_pressed)
	_hud.transfer_pressed.connect(_on_transfer_pressed)
	_hud.clear_orders_pressed.connect(_on_clear_orders_pressed)
	_hud.missions_toggled.connect(_on_missions_toggled)


func _init_tooltip() -> void:
	_tooltip = TooltipScript.new()
	add_child(_tooltip)


func _init_province_panel() -> void:
	_province_panel = ProvincePanelScene.instantiate()
	add_child(_province_panel)
	_province_panel.closed.connect(func() -> void: _player_map.refresh())
	_province_panel.leader_selection_changed.connect(func() -> void: _update_action_buttons(_selected_province_id))


func _post_init() -> void:
	if SceneManager.pending_game_state != null:
		# Launched from FactionSelect — use SceneManager state, create TurnManager directly
		_game_state   = SceneManager.pending_game_state
		_map_data     = SceneManager.pending_map_data
		_human_id     = SceneManager.pending_human_faction_id
		_turn_manager = TurnManagerScript.new()
	elif _debug_view != null:
		# Launched directly from editor — pull everything from the debug view
		_game_state   = _debug_view.get("game_state") as GameState
		_map_data     = _debug_view.get("map_data")   as MapData
		_human_id     = int(_debug_view.get("HUMAN_ID") if _debug_view.get("HUMAN_ID") != null else 0)
		_turn_manager = _debug_view.get("turn_manager") as TurnManager

	# Wire win/lose signal
	if _turn_manager != null and not _turn_manager.is_connected("game_over", _on_game_over):
		_turn_manager.game_over.connect(_on_game_over)

	DebugLogger.log("campaign_session_start", {
		"human_faction_id": _human_id,
		"province_count": _map_data.provinces.size() if _map_data != null else -1,
		"source": "editor" if _debug_view != null else "faction_select",
	})

	# Init player map — voronoi cells only available when debug view is present
	var voronoi: Dictionary = {}
	if _debug_view != null:
		voronoi = _debug_view.get("_voronoi_cells") if _debug_view.get("_voronoi_cells") != null else {}
	_player_map.init(_game_state, _map_data, _human_id, voronoi)

	# Init HUD
	_hud.game_state = _game_state
	_hud.human_faction_id = _human_id
	_hud.refresh()

	# Init tooltip
	_tooltip.game_state = _game_state
	_tooltip.human_faction_id = _human_id

	# Init province panel
	_province_panel.game_state = _game_state
	_province_panel.human_faction_id = _human_id

	# Hide DEV button when there's no debug view to show
	if _debug_view == null:
		_hud.hide_dev_button()

	# Mission panel — wrapped in its own CanvasLayer so it floats above the map
	var mission_layer := CanvasLayer.new()
	mission_layer.layer = 12
	add_child(mission_layer)
	_mission_panel = MissionPanel.new()
	_mission_panel.set_game_state(_game_state)
	_mission_panel.set_human_faction(_human_id)
	_mission_panel.position = Vector2(30, 80)
	_mission_panel.visible = false
	mission_layer.add_child(_mission_panel)


# --------------------------------------------------
# Input
# --------------------------------------------------
func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _pick_mode != PICK_NONE:
			_cancel_pick_mode()
		elif not _pause_open:
			_on_pause()


# --------------------------------------------------
# Province interaction
# --------------------------------------------------
func _on_province_hovered(province_id: int) -> void:
	if province_id >= 0:
		_tooltip.show_province(province_id)
		_hud.refresh(province_id)
	else:
		_tooltip.hide_tooltip()
		_hud.refresh(-1)


func _on_province_clicked(province_id: int) -> void:
	_tooltip.hide_tooltip()

	# Handle pick mode (attack / transfer targeting)
	if _pick_mode == PICK_ATTACK:
		_do_queue_attack(_pick_source_id, province_id)
		_cancel_pick_mode()
		return
	elif _pick_mode == PICK_TRANSFER:
		_do_queue_transfer(_pick_source_id, province_id)
		_cancel_pick_mode()
		return

	# Normal selection
	_selected_province_id = province_id
	_province_panel.open(province_id)
	_hud.refresh(province_id)
	_update_action_buttons(province_id)
	if _mission_panel != null and _mission_panel.visible:
		_mission_panel.refresh(province_id)


# --------------------------------------------------
# End Turn
# --------------------------------------------------
func _on_end_turn() -> void:
	if _processing_turn or _turn_manager == null or _game_state == null:
		return
	_processing_turn = true
	DebugLogger.log("player_end_turn", {"month": _game_state.month_index + 1})

	# Let the debug view handle turn execution when it's active (editor mode)
	if _debug_view != null and _debug_view.visible and _debug_view.has_method("ui_end_turn"):
		_debug_view.call("ui_end_turn")
	elif _turn_manager != null:
		await _turn_manager.execute_month(_game_state, _human_id, -1, true)

	_processing_turn = false
	_player_map.refresh()
	_hud.refresh()

	# Push mission results to the panel (clears them from game_state after display)
	if _mission_panel != null and _game_state != null:
		var results: Array = _game_state.pending_mission_results.duplicate()
		_game_state.pending_mission_results.clear()
		if not results.is_empty():
			_mission_panel.push_results(results)


# --------------------------------------------------
# Dev toggle
# --------------------------------------------------
func _on_dev_toggle(active: bool) -> void:
	if _debug_view != null:
		_debug_view.visible = active
	_player_map.visible = not active


# --------------------------------------------------
# Pause
# --------------------------------------------------
func _on_pause() -> void:
	if _pause_open:
		return
	_pause_open = true
	var pause: PauseMenu = PauseMenuScene.instantiate() as PauseMenu
	pause.resumed.connect(func() -> void: _pause_open = false)
	add_child(pause)


# --------------------------------------------------
# Action buttons — Attack / Transfer / Clear / Missions
# --------------------------------------------------
func _update_action_buttons(province_id: int) -> void:
	if _game_state == null or _map_data == null:
		return
	var can_act: bool = false
	if province_id >= 0 and _map_data.provinces.size() > province_id:
		var p: ProvinceData = _map_data.provinces[province_id] as ProvinceData
		var is_own: bool = p != null and int(p.owner_id) == _human_id
		var has_leader: bool = not _province_panel.get_selected_leader_ids().is_empty()
		can_act = is_own and has_leader
	_hud.set_action_enabled(can_act, can_act)


func _get_adjacent_ids(province_id: int) -> Array:
	if _map_data == null:
		return []
	var adj = _map_data.adjacency.get(province_id)
	if adj == null:
		return []
	return adj as Array


func _on_attack_pressed() -> void:
	if _selected_province_id < 0 or _game_state == null or _map_data == null:
		return
	var src: ProvinceData = _map_data.provinces[_selected_province_id] as ProvinceData
	if src == null or int(src.owner_id) != _human_id:
		return
	_pick_mode = PICK_ATTACK
	_pick_source_id = _selected_province_id
	var neighbors: Array = _get_adjacent_ids(_selected_province_id)
	_player_map.set_pick_mode(PICK_ATTACK, _pick_source_id, neighbors)
	_hud.set_pick_mode_text("⚔ ATTACK — Click an adjacent enemy province  (Esc to cancel)")


func _on_transfer_pressed() -> void:
	if _selected_province_id < 0 or _game_state == null or _map_data == null:
		return
	var src: ProvinceData = _map_data.provinces[_selected_province_id] as ProvinceData
	if src == null or int(src.owner_id) != _human_id:
		return
	_pick_mode = PICK_TRANSFER
	_pick_source_id = _selected_province_id
	_player_map.set_pick_mode(PICK_TRANSFER, _pick_source_id)
	_hud.set_pick_mode_text("↔ TRANSFER — Click a friendly province  (Esc to cancel)")


func _cancel_pick_mode() -> void:
	_pick_mode = PICK_NONE
	_pick_source_id = -1
	_player_map.set_pick_mode(PICK_NONE, -1, [])
	_hud.set_pick_mode_text("Click a province to select it")


func _on_clear_orders_pressed() -> void:
	if _game_state == null or _game_state.order_book == null:
		return
	_game_state.order_book.clear_orders_for_faction(_human_id)
	_player_map.refresh()
	_hud.refresh()


func _do_queue_attack(from_id: int, to_id: int) -> void:
	DebugLogger.log("player_queue_attack", {"from": from_id, "to": to_id})
	if _game_state == null or _game_state.order_book == null or _map_data == null:
		return
	var tgt: ProvinceData = _map_data.provinces[to_id] as ProvinceData
	if tgt == null or int(tgt.owner_id) == _human_id:
		return  # can't attack own province
	if not _get_adjacent_ids(from_id).has(to_id):
		return  # target not adjacent via road
	# Require at least one leader to be selected before queuing an attack
	var leaders: Array[int] = _province_panel.get_selected_leader_ids()
	if leaders.is_empty():
		return
	while leaders.size() > 3:
		leaders.remove_at(leaders.size() - 1)
	_game_state.order_book.queue_attack(_human_id, from_id, to_id, 0, leaders)
	_player_map.refresh()
	_hud.refresh()


func _do_queue_transfer(from_id: int, to_id: int) -> void:
	DebugLogger.log("player_queue_transfer", {"from": from_id, "to": to_id})
	if _game_state == null or _game_state.order_book == null or _map_data == null:
		return
	var tgt: ProvinceData = _map_data.provinces[to_id] as ProvinceData
	if tgt == null or int(tgt.owner_id) != _human_id:
		return  # transfer only to own provinces
	# Require at least one leader to be selected before queuing a transfer
	var leaders: Array[int] = _province_panel.get_selected_leader_ids()
	if leaders.is_empty():
		return
	while leaders.size() > 3:
		leaders.remove_at(leaders.size() - 1)
	_game_state.order_book.queue_transfer(_human_id, from_id, to_id, leaders)
	_player_map.refresh()
	_hud.refresh()


func _on_missions_toggled(active: bool) -> void:
	if _mission_panel == null:
		return
	_mission_panel.visible = active
	if active:
		_mission_panel.refresh(_selected_province_id)


# --------------------------------------------------
# Battle visibility — called by BattleManager to hide/show all campaign UI
# --------------------------------------------------
func set_campaign_visible(v: bool) -> void:
	for child in get_children():
		var cv = child.get("visible")
		if cv != null:
			child.visible = v
	# Invisible Node2Ds still receive _unhandled_input — disable it so hover
	# events don't re-show the tooltip while the battle scene is on top.
	if _player_map != null:
		_player_map.set_process_unhandled_input(v)


# --------------------------------------------------
# Game over
# --------------------------------------------------
func _on_game_over(result: String) -> void:
	DebugLogger.log("game_over", {"result": result, "month": _game_state.month_index if _game_state != null else -1})
	if result == "victory":
		SceneManager.show_victory(_game_state)
	else:
		SceneManager.show_defeat(_game_state)
