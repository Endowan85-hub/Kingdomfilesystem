# ==================================================
# DefeatScreen
# ==================================================
# Shown when all player leaders are wounded AND
# all player provinces are lost.
# ==================================================
extends Control
class_name DefeatScreen


func _ready() -> void:
	var gs: GameState = SceneManager.pending_game_state
	_build_ui(gs)


func _build_ui(gs: GameState) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.03, 0.03)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var art := Label.new()
	art.text = "[ Defeat — Illustrated Art ]"
	art.add_theme_color_override("font_color", Color(0.25, 0.18, 0.18))
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

	var banner := Label.new()
	banner.text = "DEFEAT"
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 72)
	banner.add_theme_color_override("font_color", Color(0.75, 0.30, 0.25))
	vbox.add_child(banner)

	# Epitaph based on how far the player got
	var epitaph := _get_epitaph(gs)
	var sub := Label.new()
	sub.text = epitaph
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(0.60, 0.50, 0.45))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(600, 0)
	vbox.add_child(sub)

	if gs != null:
		var months_lbl := Label.new()
		months_lbl.text = "Survived %d months before the realm consumed you." % gs.month_index
		months_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		months_lbl.add_theme_font_size_override("font_size", 13)
		months_lbl.add_theme_color_override("font_color", Color(0.45, 0.40, 0.38))
		vbox.add_child(months_lbl)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(gap)

	var btn := Button.new()
	btn.text = "Return to Main Menu"
	btn.custom_minimum_size = Vector2(280, 50)
	btn.add_theme_font_size_override("font_size", 16)
	btn.pressed.connect(func() -> void: SceneManager.go_to_main_menu())
	vbox.add_child(btn)


func _get_epitaph(gs: GameState) -> String:
	if gs == null:
		return "Your house has fallen."
	var months: int = gs.month_index
	if months < 12:
		return "Your reign barely began before the wolves closed in."
	elif months < 36:
		return "You held the line longer than most dared hope."
	elif months < 72:
		return "Seasons passed under your banner. In the end, it was not enough."
	else:
		return "Yours was a campaign worthy of legend — but the realm demands a single master."
