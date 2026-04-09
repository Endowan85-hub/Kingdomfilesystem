# ==================================================
# PauseMenu
# ==================================================
# In-game pause overlay. Press Escape to open.
# Added as a child of CampaignMap.
# ==================================================
extends CanvasLayer
class_name PauseMenu

signal resumed


func _ready() -> void:
	_build_ui()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_resume()


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.12)
	style.border_color = Color(0.35, 0.32, 0.22)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	vbox.add_child(title)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(gap)

	_menu_button(vbox, "Resume",              _on_resume)
	_menu_button(vbox, "Settings",            _on_settings)
	_menu_button(vbox, "Save Game  (soon)",   _on_save,         true)
	_menu_button(vbox, "Return to Main Menu", _on_main_menu)
	_menu_button(vbox, "Quit to Desktop",     _on_quit)


func _menu_button(parent: Control, text: String, callback: Callable, disabled: bool = false) -> void:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(280, 46)
	btn.add_theme_font_size_override("font_size", 15)
	btn.disabled = disabled
	if not disabled:
		btn.pressed.connect(callback)
	parent.add_child(btn)


func _on_resume() -> void:
	resumed.emit()
	queue_free()


func _on_settings() -> void:
	var s := load("res://Visual/menus/SettingsMenu.tscn").instantiate()
	get_parent().add_child(s)


func _on_save() -> void:
	pass  # placeholder


func _on_main_menu() -> void:
	# Confirm dialog
	var confirm := ConfirmationDialog.new()
	confirm.dialog_text = "Return to Main Menu?\nUnsaved progress will be lost."
	confirm.confirmed.connect(func() -> void: SceneManager.go_to_main_menu())
	get_parent().add_child(confirm)
	confirm.popup_centered()


func _on_quit() -> void:
	get_tree().quit()
