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
const ProvincePanelScript:= preload("res://Visual/campaign/ProvincePanel.gd")
const PauseMenuScene     := preload("res://Visual/menus/PauseMenu.tscn")

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


func _ready() -> void:
	_init_debug_view()
	_init_player_map()
	_init_hud()
	_init_tooltip()
	_init_province_panel()
	call_deferred("_post_init")


# --------------------------------------------------
# Initialization
# --------------------------------------------------
func _init_debug_view() -> void:
	_debug_view = MapDebugViewScene.instantiate()
	add_child(_debug_view)
	_debug_view.visible = false  # hidden by default — player map is primary


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


func _init_tooltip() -> void:
	_tooltip = TooltipScript.new()
	add_child(_tooltip)


func _init_province_panel() -> void:
	_province_panel = ProvincePanelScript.new()
	add_child(_province_panel)
	_province_panel.closed.connect(func() -> void: _player_map.refresh())


func _post_init() -> void:
	# Grab state from debug view after its _ready() has run
	_game_state = _debug_view.get("game_state") as GameState
	_map_data    = _debug_view.get("map_data")   as MapData
	_human_id    = int(_debug_view.get("HUMAN_ID") if _debug_view.get("HUMAN_ID") != null else 0)
	_turn_manager = _debug_view.get("turn_manager") as TurnManager

	# If SceneManager passed a state from FactionSelect, use that instead
	if SceneManager.pending_game_state != null:
		_game_state = SceneManager.pending_game_state
		_map_data    = SceneManager.pending_map_data
		_human_id    = SceneManager.pending_human_faction_id

	# Wire win/lose signal
	if _turn_manager != null and not _turn_manager.is_connected("game_over", _on_game_over):
		_turn_manager.game_over.connect(_on_game_over)

	# Init player map with voronoi data from debug view
	var voronoi: Dictionary = _debug_view.get("_voronoi_cells") if _debug_view.get("_voronoi_cells") != null else {}
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


# --------------------------------------------------
# Input
# --------------------------------------------------
func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _pause_open:
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
	_province_panel.open(province_id)
	_hud.refresh(province_id)


# --------------------------------------------------
# End Turn
# --------------------------------------------------
func _on_end_turn() -> void:
	if _processing_turn or _turn_manager == null or _game_state == null:
		return
	_processing_turn = true

	# Let the debug view handle the actual turn execution (it owns the turn pipeline)
	# We call its end-turn method if it exists, otherwise execute directly
	if _debug_view.visible and _debug_view.has_method("ui_end_turn"):
		_debug_view.call("ui_end_turn")
	elif _turn_manager != null:
		await _turn_manager.execute_month(_game_state, _human_id, -1, true)

	_processing_turn = false
	_player_map.refresh()
	_hud.refresh()


# --------------------------------------------------
# Dev toggle
# --------------------------------------------------
func _on_dev_toggle(active: bool) -> void:
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
# Game over
# --------------------------------------------------
func _on_game_over(result: String) -> void:
	if result == "victory":
		SceneManager.show_victory(_game_state)
	else:
		SceneManager.show_defeat(_game_state)
