# ==================================================
# SceneManager — Autoload Singleton
# ==================================================
# Handles all scene transitions in the visual layer.
# Never modifies simulation state directly.
#
# Usage:
#   SceneManager.go_to_main_menu()
#   SceneManager.go_to_faction_select()
#   SceneManager.go_to_campaign(game_state, map_data, human_faction_id)
#   SceneManager.show_victory(game_state)
#   SceneManager.show_defeat(game_state)
# ==================================================
extends Node

const MAIN_MENU_SCENE    := "res://Visual/menus/MainMenu.tscn"
const FACTION_SELECT_SCENE := "res://Visual/menus/FactionSelect.tscn"
const CAMPAIGN_MAP_SCENE  := "res://Visual/campaign/CampaignMap.tscn"
const VICTORY_SCENE       := "res://Visual/menus/VictoryScreen.tscn"
const DEFEAT_SCENE        := "res://Visual/menus/DefeatScreen.tscn"

# Passed between scenes — set before transitioning
var pending_game_state: GameState = null
var pending_map_data: MapData = null
var pending_human_faction_id: int = 0
var pending_province_count: int = 20


func go_to_main_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func go_to_faction_select() -> void:
	get_tree().change_scene_to_file(FACTION_SELECT_SCENE)


func go_to_campaign(game_state: GameState, map_data: MapData, human_faction_id: int) -> void:
	pending_game_state = game_state
	pending_map_data = map_data
	pending_human_faction_id = human_faction_id
	get_tree().change_scene_to_file(CAMPAIGN_MAP_SCENE)


func show_victory(game_state: GameState) -> void:
	pending_game_state = game_state
	get_tree().change_scene_to_file(VICTORY_SCENE)


func show_defeat(game_state: GameState) -> void:
	pending_game_state = game_state
	get_tree().change_scene_to_file(DEFEAT_SCENE)
