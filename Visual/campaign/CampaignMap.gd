# ==================================================
# CampaignMap
# ==================================================
# The main in-game scene. Wraps the existing MapDebugView
# (simulation + dev tools) and places the player-facing
# visual layer on top as a CanvasLayer.
#
# Phase 1: thin shell — dev view is the primary display.
# Phase 2: player map rendered here; dev view toggled off by default.
#
# DOES NOT modify any simulation files.
# ==================================================
extends Node
class_name CampaignMap

const MapDebugViewScene := preload("res://map_debug_view.tscn")
const MapSettingsScript  := preload("res://Scripts/map/map_settings.gd")
const PauseMenuScene     := preload("res://Visual/menus/PauseMenu.tscn")

var _debug_view: Node          # MapDebugView instance
var _hud_layer: CanvasLayer    # Player HUD overlay
var _dev_mode_visible: bool = true
var _pause_open: bool = false


func _ready() -> void:
	_init_debug_view()
	_build_hud()


func _init_debug_view() -> void:
	# Instantiate the existing simulation + dev view
	_debug_view = MapDebugViewScene.instantiate()

	# If SceneManager has a pending game state from FactionSelect,
	# inject it. Otherwise let the debug view build its own fresh state.
	var gs: GameState = SceneManager.pending_game_state
	if gs != null and _debug_view.has_method("receive_game_state"):
		_debug_view.receive_game_state(gs, SceneManager.pending_map_data)
	# (Phase 2: full handoff — for now debug view self-initializes)

	add_child(_debug_view)

	# Connect win/lose signal once the debug view has initialized its turn_manager.
	# Use call_deferred so the debug view's _ready() has run first.
	call_deferred("_connect_game_over_signal")


func _connect_game_over_signal() -> void:
	if _debug_view == null:
		return
	var tm = _debug_view.get("turn_manager")
	if tm == null:
		return
	if tm.is_connected("game_over", _on_game_over):
		return
	tm.game_over.connect(_on_game_over)


func _on_game_over(result: String) -> void:
	var gs: GameState = null
	if _debug_view != null:
		gs = _debug_view.get("game_state") as GameState
	if result == "victory":
		SceneManager.show_victory(gs)
	else:
		SceneManager.show_defeat(gs)


func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 10   # above everything
	add_child(_hud_layer)

	# --- Top bar ---
	var top_bar := _hbox_bar(Color(0.05, 0.04, 0.08, 0.88))
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.custom_minimum_size = Vector2(0, 36)
	_hud_layer.add_child(top_bar)

	var game_title := _hud_label("KINGDOM", 14, Color(0.85, 0.75, 0.40))
	top_bar.add_child(game_title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)

	# Dev toggle button — small, unobtrusive
	var dev_btn := Button.new()
	dev_btn.text = "DEV"
	dev_btn.toggle_mode = true
	dev_btn.button_pressed = _dev_mode_visible
	dev_btn.custom_minimum_size = Vector2(48, 0)
	dev_btn.add_theme_font_size_override("font_size", 10)
	dev_btn.toggled.connect(_on_dev_toggle)
	top_bar.add_child(dev_btn)

	# --- Bottom bar ---
	var bot_bar := _hbox_bar(Color(0.05, 0.04, 0.08, 0.88))
	bot_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bot_bar.custom_minimum_size = Vector2(0, 40)
	bot_bar.offset_top = -40
	_hud_layer.add_child(bot_bar)

	var phase_note := _hud_label("Phase 1 — Dev View Active  ·  Player map coming in Phase 2", 11, Color(0.40, 0.38, 0.32))
	bot_bar.add_child(phase_note)

	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot_bar.add_child(spacer2)

	# Pause button
	var pause_btn := Button.new()
	pause_btn.text = "Menu  [Esc]"
	pause_btn.add_theme_font_size_override("font_size", 12)
	pause_btn.pressed.connect(_on_pause)
	bot_bar.add_child(pause_btn)


func _hbox_bar(color: Color) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.anchor_right = 1.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = color
	bar.add_theme_stylebox_override("panel", bg)
	bar.add_theme_constant_override("separation", 10)
	return bar


func _hud_label(text: String, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return lbl


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _pause_open:
		_on_pause()


func _on_dev_toggle(pressed: bool) -> void:
	_dev_mode_visible = pressed
	if _debug_view:
		_debug_view.visible = pressed


func _on_pause() -> void:
	if _pause_open:
		return
	_pause_open = true
	var pause := PauseMenuScene.instantiate() as PauseMenu
	pause.resumed.connect(func() -> void: _pause_open = false)
	add_child(pause)
