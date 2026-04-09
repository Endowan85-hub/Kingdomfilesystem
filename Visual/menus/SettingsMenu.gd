# ==================================================
# SettingsMenu
# ==================================================
# Shown as an overlay on top of MainMenu or CampaignMap.
# Minimal Phase 1 scope — placeholders for audio/display.
# ==================================================
extends CanvasLayer
class_name SettingsMenu

signal closed


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	# Dim background
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.12)
	style.border_color = Color(0.35, 0.32, 0.22)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	panel.add_child(vbox)

	# Header
	_section_title(vbox, "Settings")

	# Display section
	_section_label(vbox, "DISPLAY")
	_placeholder_row(vbox, "Resolution", "1920 × 1080")
	_toggle_row(vbox, "Fullscreen", true)

	# Game section
	_section_label(vbox, "GAME")
	_toggle_row(vbox, "Autosave", false)
	_toggle_row(vbox, "Dev Mode", false)

	# Audio section
	_section_label(vbox, "AUDIO")
	_placeholder_row(vbox, "Master Volume", "— (no audio yet)")

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	var apply := Button.new()
	apply.text = "Apply"
	apply.custom_minimum_size = Vector2(120, 40)
	apply.pressed.connect(_on_close)
	btn_row.add_child(apply)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(120, 40)
	back.pressed.connect(_on_close)
	btn_row.add_child(back)


func _section_title(parent: Control, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	parent.add_child(lbl)


func _section_label(parent: Control, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.50, 0.48, 0.40))
	parent.add_child(lbl)


func _placeholder_row(parent: Control, label: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", Color(0.75, 0.73, 0.65))
	row.add_child(lbl)
	var val := Label.new()
	val.text = value
	val.add_theme_color_override("font_color", Color(0.45, 0.43, 0.38))
	row.add_child(val)


func _toggle_row(parent: Control, label: String, default_on: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", Color(0.75, 0.73, 0.65))
	row.add_child(lbl)
	var toggle := CheckButton.new()
	toggle.button_pressed = default_on
	row.add_child(toggle)


func _on_close() -> void:
	closed.emit()
	queue_free()
