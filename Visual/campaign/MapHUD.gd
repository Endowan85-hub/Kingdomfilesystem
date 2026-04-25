# ==================================================
# MapHUD
# ==================================================
# Persistent UI overlay on the campaign map.
# Shows month, faction gold, income/upkeep, End Turn.
# Reads from GameState — never modifies it.
# End Turn signal is caught by CampaignMap.
# ==================================================
extends CanvasLayer
class_name MapHUD

signal end_turn_pressed
signal dev_toggle_pressed(active: bool)
signal pause_pressed
signal attack_pressed
signal transfer_pressed
signal clear_orders_pressed
signal missions_toggled(active: bool)

var game_state: GameState = null
var human_faction_id: int = 0

# UI refs updated each refresh
var _month_label: Label
var _gold_label: Label
var _income_label: Label
var _province_label: Label
var _selected_label: Label
var _dev_btn: Button
var _attack_btn: Button
var _transfer_btn: Button
var _clear_btn: Button
var _missions_btn: Button


func _ready() -> void:
	layer = 10
	_build()


func _build() -> void:
	# ── TOP BAR ──────────────────────────────────────
	var top := _bar_container(true)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.custom_minimum_size = Vector2(0, 42)
	add_child(top)

	# Game title
	var title := _label("KINGDOM", 15, Color(0.85, 0.75, 0.40))
	top.add_child(title)

	var sep1 := _separator()
	top.add_child(sep1)

	# Month
	_month_label = _label("Month 0", 13, Color(0.80, 0.78, 0.65))
	top.add_child(_month_label)

	var sep2 := _separator()
	top.add_child(sep2)

	# Gold
	_gold_label = _label("Gold: —", 13, Color(0.90, 0.80, 0.35))
	top.add_child(_gold_label)

	# Income
	_income_label = _label("", 12, Color(0.55, 0.80, 0.45))
	top.add_child(_income_label)

	# Province count
	_province_label = _label("", 12, Color(0.65, 0.70, 0.80))
	top.add_child(_province_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)

	# DEV toggle
	_dev_btn = Button.new()
	_dev_btn.text = "DEV"
	_dev_btn.toggle_mode = true
	_dev_btn.button_pressed = false
	_dev_btn.custom_minimum_size = Vector2(46, 0)
	_dev_btn.add_theme_font_size_override("font_size", 10)
	_dev_btn.toggled.connect(func(on: bool) -> void: dev_toggle_pressed.emit(on))
	top.add_child(_dev_btn)


	# ── BOTTOM BAR ───────────────────────────────────
	var bot := _bar_container(true)
	bot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bot.custom_minimum_size = Vector2(0, 46)
	bot.offset_top = -46
	add_child(bot)

	# Selected province summary / mode indicator
	_selected_label = _label("Click a province to select it", 12, Color(0.55, 0.53, 0.48))
	bot.add_child(_selected_label)

	# Action buttons
	_attack_btn = _action_btn("⚔ Attack", Color(0.70, 0.25, 0.20))
	_attack_btn.disabled = true
	_attack_btn.pressed.connect(func() -> void: attack_pressed.emit())
	bot.add_child(_attack_btn)

	_transfer_btn = _action_btn("↔ Transfer", Color(0.20, 0.45, 0.70))
	_transfer_btn.disabled = true
	_transfer_btn.pressed.connect(func() -> void: transfer_pressed.emit())
	bot.add_child(_transfer_btn)

	_clear_btn = _action_btn("✕ Clear", Color(0.40, 0.38, 0.28))
	_clear_btn.pressed.connect(func() -> void: clear_orders_pressed.emit())
	bot.add_child(_clear_btn)

	_missions_btn = _action_btn("◆ Missions", Color(0.30, 0.50, 0.65))
	_missions_btn.toggle_mode = true
	_missions_btn.toggled.connect(func(on: bool) -> void: missions_toggled.emit(on))
	bot.add_child(_missions_btn)

	# End Turn button — prominent, placed with action buttons so it's always visible
	var end_btn := Button.new()
	end_btn.text = "End Turn ▶"
	end_btn.custom_minimum_size = Vector2(140, 0)
	end_btn.add_theme_font_size_override("font_size", 15)
	var end_style := StyleBoxFlat.new()
	end_style.bg_color = Color(0.25, 0.45, 0.20)
	end_style.border_color = Color(0.50, 0.80, 0.35)
	end_style.set_border_width_all(1)
	end_style.set_corner_radius_all(3)
	end_btn.add_theme_stylebox_override("normal", end_style)
	end_btn.pressed.connect(func() -> void: end_turn_pressed.emit())
	bot.add_child(end_btn)

	var bot_spacer := Control.new()
	bot_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot.add_child(bot_spacer)

	# Menu button — pushed to far right
	var menu_btn := Button.new()
	menu_btn.text = "Menu  [Esc]"
	menu_btn.add_theme_font_size_override("font_size", 12)
	menu_btn.pressed.connect(func() -> void: pause_pressed.emit())
	bot.add_child(menu_btn)


func hide_dev_button() -> void:
	if _dev_btn != null:
		_dev_btn.visible = false


func set_action_enabled(can_attack: bool, can_transfer: bool) -> void:
	if _attack_btn != null:
		_attack_btn.disabled = not can_attack
	if _transfer_btn != null:
		_transfer_btn.disabled = not can_transfer


func set_pick_mode_text(text: String) -> void:
	if _selected_label != null:
		_selected_label.text = text


func _action_btn(label: String, tint: Color) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.add_theme_font_size_override("font_size", 11)
	btn.custom_minimum_size = Vector2(96, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = tint.darkened(0.45)
	style.border_color = tint.lightened(0.1)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("normal", style)
	return btn


func refresh(selected_province_id: int = -1) -> void:
	if game_state == null:
		return

	# Month
	_month_label.text = "Month %d" % game_state.month_index

	# Find human faction
	var human_faction: FactionData = null
	for item in game_state.map_data.factions:
		var f: FactionData = item as FactionData
		if f != null and int(f.id) == human_faction_id:
			human_faction = f
			break

	if human_faction != null:
		_gold_label.text = "Gold: %d" % int(human_faction.gold)
		var income: int = int(human_faction.income_last_turn)
		var sign_str: String = "+" if income >= 0 else ""
		_income_label.text = "  Income: %s%d" % [sign_str, income]
		_province_label.text = "  Provinces: %d" % (human_faction.provinces as Array).size()

	# Selected province summary
	if selected_province_id >= 0 and game_state.map_data != null:
		var p: ProvinceData = game_state.map_data.provinces[selected_province_id] as ProvinceData
		if p != null:
			var owner_name: String = "Neutral"
			for item2 in game_state.map_data.factions:
				var f2: FactionData = item2 as FactionData
				if f2 != null and int(f2.id) == int(p.owner_id):
					owner_name = f2.display_name
					break
			_selected_label.text = "%s  ·  %s  ·  Fort %d  ·  Income %d" % [
				p.display_name,
				str(p.biome).capitalize(),
				int(p.fort_level),
				int(p.income)
			]
		else:
			_selected_label.text = "Click a province to select it"
	else:
		_selected_label.text = "Click a province to select it"


# --------------------------------------------------
# Helpers
# --------------------------------------------------
func _bar_container(horizontal: bool) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.anchor_right = 1.0
	bar.add_theme_constant_override("separation", 8)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.04, 0.08, 0.90)
	bar.add_theme_stylebox_override("panel", bg)
	return bar


func _label(text: String, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return lbl


func _separator() -> Label:
	var sep := Label.new()
	sep.text = "·"
	sep.add_theme_color_override("font_color", Color(0.35, 0.32, 0.25))
	return sep
