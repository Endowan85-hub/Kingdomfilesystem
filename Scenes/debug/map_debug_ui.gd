extends CanvasLayer
# MapDebugUI
# Version: 2026-03-04 (NO BANNER / SAFE Z)
# This script creates a small info overlay in screen-space that shows Selected + Mode.
# It intentionally avoids large z_index values to prevent CANVAS_ITEM_Z_MAX errors.

var selected_label: Label
var mode_label: Label

var orders_label: RichTextLabel
var attack_btn: Button
var transfer_btn: Button
var upgrade_btn: Button
var execute_btn: Button
var clear_btn: Button
var cancel_btn: Button

var view: Node = null


func _ready() -> void:
	view = get_parent()
	if view == null:
		push_warning("MapDebugUI: parent is null (expected MapDebugView).")
		return

	_ensure_screen_info_box()

	# Grab remaining nodes by name (from existing debug panel)
	orders_label = _find("Orders") as RichTextLabel
	attack_btn = _find("AttackBtn") as Button
	transfer_btn = _find("TransferBtn") as Button
	upgrade_btn = _find("UpgradeBtn") as Button
	execute_btn = _find("ExecuteBtn") as Button
	clear_btn = _find("ClearBtn") as Button
	cancel_btn = _find("CancelBtn") as Button

	if selected_label == null or mode_label == null or orders_label == null:
		_print_missing_and_abort()
		return
	if attack_btn == null or transfer_btn == null or upgrade_btn == null or execute_btn == null or clear_btn == null or cancel_btn == null:
		_print_missing_and_abort()
		return

	orders_label.fit_content = false
	orders_label.scroll_active = true

	attack_btn.pressed.connect(func() -> void: view.call("ui_start_attack"))
	transfer_btn.pressed.connect(func() -> void: view.call("ui_start_transfer"))
	upgrade_btn.pressed.connect(func() -> void: view.call("ui_queue_upgrade"))
	execute_btn.pressed.connect(func() -> void: view.call("ui_execute_month"))
	clear_btn.pressed.connect(func() -> void: view.call("ui_clear_orders"))
	cancel_btn.pressed.connect(func() -> void: view.call("ui_cancel_mode"))

	if view.has_signal("debug_state_changed"):
		view.connect("debug_state_changed", Callable(self, "_refresh"))

	_refresh()


func _ensure_screen_info_box() -> void:
	var box := get_node_or_null("__InfoOverlay") as PanelContainer
	if box == null:
		box = PanelContainer.new()
		box.name = "__InfoOverlay"
		box.position = Vector2(12, 12) # top-left
		box.size = Vector2(430, 58)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# Keep z_index small and safe. Default is 0; we use 1 so it stays above panel.
		box.z_index = 1
		add_child(box)

		var vb := VBoxContainer.new()
		vb.name = "VBox"
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(vb)

		selected_label = Label.new()
		selected_label.name = "Selected"
		vb.add_child(selected_label)

		mode_label = Label.new()
		mode_label.name = "Mode"
		vb.add_child(mode_label)
	else:
		selected_label = box.find_child("Selected", true, false) as Label
		mode_label = box.find_child("Mode", true, false) as Label

	_style_info_label(selected_label, "Selected: (none)")
	_style_info_label(mode_label, "Mode: None")


func _style_info_label(lbl: Label, default_text: String) -> void:
	if lbl == null:
		return

	lbl.visible = true
	lbl.modulate = Color(1, 1, 1, 1)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.clip_text = true
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.custom_minimum_size = Vector2(0, 22)

	# Force font size and color regardless of theme.
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	lbl.add_theme_color_override("font_color_shadow", Color(0, 0, 0, 0.80))

	lbl.text = default_text


func _refresh() -> void:
	if view == null:
		return

	var sel_text: String = str(view.call("ui_get_selected_text"))
	if sel_text == "":
		sel_text = "Selected: (none)"
	selected_label.text = sel_text

	var mode_text: String = str(view.call("ui_get_mode_text"))
	if mode_text == "":
		mode_text = "None"
	mode_label.text = "Mode: " + mode_text

	var orders_text: String = str(view.call("ui_get_orders_text"))
	orders_label.clear()
	orders_label.append_text(orders_text)

	var has_sel: bool = bool(view.call("ui_has_selection"))
	attack_btn.disabled = not has_sel
	transfer_btn.disabled = not has_sel
	upgrade_btn.disabled = not has_sel


func _find(node_name: String) -> Node:
	return find_child(node_name, true, false)


func _print_missing_and_abort() -> void:
	push_error("MapDebugUI: Missing required nodes.")
	push_error("Need: Orders, AttackBtn, TransferBtn, UpgradeBtn, ExecuteBtn, ClearBtn, CancelBtn")
