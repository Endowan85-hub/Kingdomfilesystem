# ==================================================
# VictoryScreen
# ==================================================
# Shown when the player eliminates all rival factions.
# Pulls campaign stats from SceneManager.pending_game_state.
# ==================================================
extends Control
class_name VictoryScreen


func _ready() -> void:
	var gs: GameState = SceneManager.pending_game_state
	_build_ui(gs)


func _build_ui(gs: GameState) -> void:
	# Background
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.06, 0.04)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Art placeholder
	var art := Label.new()
	art.text = "[ Victory — Illustrated Art ]"
	art.add_theme_color_override("font_color", Color(0.20, 0.28, 0.20))
	art.add_theme_font_size_override("font_size", 14)
	art.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	art.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(art)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	# Victory banner
	var banner := Label.new()
	banner.text = "VICTORY"
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 72)
	banner.add_theme_color_override("font_color", Color(0.95, 0.85, 0.35))
	vbox.add_child(banner)

	var subtitle := Label.new()
	subtitle.text = "Your house stands alone. The realm is yours."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.65, 0.70, 0.55))
	vbox.add_child(subtitle)

	# Campaign stats
	if gs != null:
		var stats_panel := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.07, 0.09, 0.07, 0.85)
		style.set_border_width_all(1)
		style.border_color = Color(0.35, 0.45, 0.30)
		stats_panel.add_theme_stylebox_override("panel", style)
		vbox.add_child(stats_panel)

		var stats_vbox := VBoxContainer.new()
		stats_vbox.add_theme_constant_override("separation", 6)
		stats_panel.add_child(stats_vbox)

		_stat_row(stats_vbox, "Months Survived",       str(gs.month_index))
		_stat_row(stats_vbox, "[ Battles Fought ]",    "— Phase 2")
		_stat_row(stats_vbox, "[ Factions Eliminated ]", "— Phase 2")

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(gap)

	var btn := Button.new()
	btn.text = "Return to Main Menu"
	btn.custom_minimum_size = Vector2(280, 50)
	btn.add_theme_font_size_override("font_size", 16)
	btn.pressed.connect(func() -> void: SceneManager.go_to_main_menu())
	vbox.add_child(btn)


func _stat_row(parent: Control, label: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", Color(0.65, 0.70, 0.60))
	lbl.add_theme_font_size_override("font_size", 13)
	row.add_child(lbl)
	var val := Label.new()
	val.text = value
	val.add_theme_color_override("font_color", Color(0.90, 0.85, 0.60))
	val.add_theme_font_size_override("font_size", 13)
	row.add_child(val)
