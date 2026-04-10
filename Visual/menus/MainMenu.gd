# ==================================================
# MainMenu
# ==================================================
# First screen the player sees. Sets visual tone.
# Placeholder art — styled with code until assets arrive.
# ==================================================
extends Control
class_name MainMenu

func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	# --- Background ---
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.03, 0.07, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Placeholder art panel — replace with illustrated background later
	var art_hint := Label.new()
	art_hint.text = "[ Background Art — Throne Room / Illustrated Map ]"
	art_hint.add_theme_color_override("font_color", Color(0.25, 0.22, 0.30))
	art_hint.add_theme_font_size_override("font_size", 13)
	art_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	art_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(art_hint)

	# --- Center column ---
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)

	# --- Title ---
	var title := Label.new()
	title.text = "KINGDOM"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 80)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	col.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "A Grand Strategy of Conquest"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color(0.55, 0.50, 0.40))
	col.add_child(subtitle)

	# Divider gap
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 32)
	col.add_child(gap)

	# --- Menu buttons ---
	_add_button(col, "New Game",  _on_new_game,  false)
	_add_button(col, "Continue",  _on_continue,  true)   # disabled until save system exists
	_add_button(col, "Settings",  _on_settings,  false)
	_add_button(col, "Quit",      _on_quit,       false)

	# --- Version label ---
	var version := Label.new()
	version.text = "v0.1 — Visual Layer Alpha"
	version.add_theme_font_size_override("font_size", 10)
	version.add_theme_color_override("font_color", Color(0.30, 0.28, 0.25))
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.offset_left = -200
	version.offset_top = -30
	add_child(version)


func _add_button(parent: Control, label: String, callback: Callable, disabled: bool) -> void:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(300, 52)
	btn.add_theme_font_size_override("font_size", 18)
	btn.disabled = disabled
	if not disabled:
		btn.pressed.connect(callback)
	parent.add_child(btn)


func _on_new_game() -> void:
	SceneManager.go_to_faction_select()


func _on_continue() -> void:
	pass  # placeholder — save system not yet implemented


func _on_settings() -> void:
	var settings_scene: Node = load("res://Visual/menus/SettingsMenu.tscn").instantiate()
	add_child(settings_scene)


func _on_quit() -> void:
	get_tree().quit()
