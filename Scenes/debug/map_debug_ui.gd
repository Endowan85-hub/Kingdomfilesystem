# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: MapDebugUI
#
# Role:
# Compact planning controls panel — Attack, Transfer, Execute Month,
# Clear Orders, Cancel Mode. Draggable by title bar, resizable via
# bottom-right handle. All orders forwarded to MapDebugView ui_* helpers.
#
# Allowed Interactions:
# - MapDebugView ui_* helpers only
#
# Forbidden Responsibilities:
# - Must not modify GameState directly
# - Must not execute simulation logic
# - Must not create orders except by forwarding to MapDebugView
#
# Game Phase:
# Planning Phase
# ==================================================
extends CanvasLayer

const MIN_W: int = 200
const MIN_H: int = 120
const HANDLE: int = 16
const TITLE_H: int = 26

var _panel: Control = null
var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _resizing: bool = false
var _resize_start_mouse: Vector2 = Vector2.ZERO
var _resize_start_size: Vector2 = Vector2.ZERO
var _resize_handle: Control = null
var _title_bar: Panel = null

var _selected_label: Label = null
var _mode_label: Label = null
var _month_label: Label = null
var _gold_label: Label = null
var _ai_lab_status_label: Label = null
var _attack_btn: Button = null
var _transfer_btn: Button = null
var _execute_btn: Button = null
var _clear_btn: Button = null
var _cancel_btn: Button = null
var _ai_lab_btn: Button = null
var _ai_lab_months_btn: Button = null
var _map_size_btn: Button = null

var view: Node = null

# AutoTuner state
const AIAutoTunerScript = preload("res://Scripts/game/tools/ai_autotuner.gd")
var _autotuner: AIAutoTuner = null
var _autotune_status: String = "AutoTune: Idle"
var _autotune_btn: Button = null
var _battle_lab_btn: Button = null
var _battle_tune_btn: Button = null
var _mission_tune_btn: Button = null
var _headless_turn_btn: Button = null
var _headless_months_btn: Button = null
var _inject_btn: Button = null
var _levelup_btn: Button = null
var _autotune_status_label: Label = null

# Metrics panel — separate floating panel shown during AutoTune
var _metrics_panel: Control = null
var _metrics_rows: Dictionary = {}  # metric_key -> { "value_label": Label, "status_label": Label }
var _metrics_baseline: Dictionary = {}  # first snapshot of metrics
var _metrics_current: Dictionary = {}   # most recent metrics
var _metrics_iteration: int = 0


func _ready() -> void:
	view = get_parent()
	if view == null:
		push_warning("MapDebugUI: parent is null.")
		return

	_build_panel()
	set_process_input(true)

	if view.has_signal("debug_state_changed"):
		view.connect("debug_state_changed", Callable(self, "_refresh"))

	_refresh()


func _build_panel() -> void:
	_panel = Control.new()
	_panel.name = "Panel"
	_panel.position = Vector2(10, 10)
	_panel.size = Vector2(240, 332)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var bg := PanelContainer.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.10, 0.10, 0.14, 0.92)
	bg_style.border_color = Color(0.35, 0.35, 0.45, 1.0)
	bg_style.border_width_left = 1
	bg_style.border_width_right = 1
	bg_style.border_width_top = 1
	bg_style.border_width_bottom = 1
	bg.add_theme_stylebox_override("panel", bg_style)
	_panel.add_child(bg)

	_title_bar = Panel.new()
	var title_bar := _title_bar
	title_bar.position = Vector2.ZERO
	title_bar.size = Vector2(_panel.size.x, TITLE_H)
	title_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title_bar.custom_minimum_size = Vector2(0, TITLE_H)
	title_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title_style := StyleBoxFlat.new()
	title_style.bg_color = Color(0.15, 0.15, 0.22, 1.0)
	title_bar.add_theme_stylebox_override("panel", title_style)
	_panel.add_child(title_bar)

	var title_lbl := Label.new()
	title_lbl.text = "MAP DEBUG"
	title_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 1.0))
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_bar.add_child(title_lbl)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(6, TITLE_H + 4)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 6
	vbox.offset_top = TITLE_H + 4
	vbox.offset_right = -6
	vbox.offset_bottom = -6
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(vbox)

	_selected_label = _make_label("Selected: (none)", 11)
	_mode_label = _make_label("Mode: None", 11)
	_month_label = _make_label("Month: 0", 11)
	_gold_label = _make_label("Gold: -- | Upkeep: --/mo", 11)
	_ai_lab_status_label = _make_label("AI Lab: Idle", 11)
	_autotune_status_label = _make_label("AutoTune: Idle", 11)
	vbox.add_child(_selected_label)
	vbox.add_child(_mode_label)
	vbox.add_child(_month_label)
	vbox.add_child(_gold_label)
	vbox.add_child(_ai_lab_status_label)
	vbox.add_child(_autotune_status_label)
	vbox.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(grid)

	_attack_btn = _make_btn("Attack", grid)
	_transfer_btn = _make_btn("Transfer", grid)
	_execute_btn = _make_btn("Execute Month", grid)
	_clear_btn = _make_btn("Clear Orders", grid)
	_cancel_btn = _make_btn("Cancel Mode", grid)
	_ai_lab_btn = _make_btn("AI Lab Pass", grid)
	_ai_lab_months_btn = _make_btn("AI Lab: 36m", grid)
	_map_size_btn = _make_btn("Map Size: 20", grid)
	_autotune_btn = _make_btn("AutoTune", grid)
	_battle_lab_btn = _make_btn("Battle Lab", grid)
	_battle_tune_btn = _make_btn("Battle Tune", grid)
	_mission_tune_btn = _make_btn("Mission Tune", grid)
	_headless_turn_btn = _make_btn("AI Turn (Headless)", grid)
	_headless_months_btn = _make_btn("AI Headless: 72m", grid)
	_inject_btn = _make_btn("Inject Items/Sigils", grid)
	_levelup_btn = _make_btn("Level Up Province", grid)
	var spacer: Control = Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_child(spacer)

	_attack_btn.pressed.connect(func() -> void: view.call("ui_start_attack"))
	_transfer_btn.pressed.connect(func() -> void: view.call("ui_start_transfer"))
	_execute_btn.pressed.connect(func() -> void: view.call("ui_execute_month"))
	_clear_btn.pressed.connect(func() -> void: view.call("ui_clear_orders"))
	_cancel_btn.pressed.connect(func() -> void: view.call("ui_cancel_mode"))
	_ai_lab_btn.pressed.connect(func() -> void: view.call("ui_run_ai_lab"))
	_ai_lab_months_btn.pressed.connect(func() -> void: view.call("ui_cycle_ai_lab_months"))
	_map_size_btn.pressed.connect(func() -> void: view.call("ui_cycle_map_size"))
	_autotune_btn.pressed.connect(_on_autotune_pressed)
	_battle_lab_btn.pressed.connect(func() -> void: view.call("ui_run_battle_lab"))
	_battle_tune_btn.pressed.connect(func() -> void: view.call("ui_run_battle_tune"))
	_mission_tune_btn.pressed.connect(func() -> void: view.call("ui_run_mission_tune"))
	_headless_turn_btn.pressed.connect(func() -> void: view.call("ui_execute_month_headless"))
	_headless_months_btn.pressed.connect(func() -> void:
		view.call("ui_cycle_headless_months")
		_headless_months_btn.text = view.call("ui_get_headless_months_text")
	)
	_inject_btn.pressed.connect(func() -> void: view.call("ui_toggle_injector_panel"))
	_levelup_btn.pressed.connect(func() -> void: view.call("ui_levelup_province"))

	_resize_handle = Control.new()
	_resize_handle.custom_minimum_size = Vector2(HANDLE, HANDLE)
	_resize_handle.size = Vector2(HANDLE, HANDLE)
	_resize_handle.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	_resize_handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resize_handle.draw.connect(_draw_handle)
	_panel.add_child(_resize_handle)
	_reposition_handle()


func _make_label(txt: String, font_size: int) -> Label:
	var lbl := Label.new()
	lbl.text = txt
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.90))
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _make_btn(txt: String, parent: Control) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 11)
	parent.add_child(btn)
	return btn


func _reposition_handle() -> void:
	if _panel == null or _resize_handle == null:
		return
	_resize_handle.position = _panel.size - Vector2(HANDLE, HANDLE)
	if _title_bar != null:
		_title_bar.size = Vector2(_panel.size.x, TITLE_H)


func _draw_handle() -> void:
	var lines: Array[Vector2] = [
		Vector2(HANDLE - 4, 4), Vector2(4, HANDLE - 4),
		Vector2(HANDLE - 4, 8), Vector2(8, HANDLE - 4),
		Vector2(HANDLE - 4, 12), Vector2(12, HANDLE - 4),
	]
	for i in range(0, lines.size(), 2):
		_resize_handle.draw_line(lines[i], lines[i + 1], Color(0.6, 0.6, 0.7, 0.8), 1.0)


func _input(event: InputEvent) -> void:
	if _panel == null:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if not Rect2(_panel.global_position, _panel.size).has_point(mb.global_position):
					return
				var lp: Vector2 = mb.global_position - _panel.global_position
				var hrect := Rect2(_panel.size - Vector2(HANDLE, HANDLE), Vector2(HANDLE, HANDLE))
				if hrect.has_point(lp):
					_resizing = true
					_resize_start_mouse = mb.global_position
					_resize_start_size = _panel.size
					get_viewport().set_input_as_handled()
					return
				var trect := Rect2(Vector2.ZERO, Vector2(_panel.size.x, TITLE_H))
				if trect.has_point(lp):
					_dragging = true
					_drag_offset = _panel.global_position - mb.global_position
					get_viewport().set_input_as_handled()
					return
			else:
				_dragging = false
				_resizing = false
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			_panel.global_position = mm.global_position + _drag_offset
			_clamp_to_screen()
			get_viewport().set_input_as_handled()
		elif _resizing:
			var delta: Vector2 = mm.global_position - _resize_start_mouse
			var new_size: Vector2 = _resize_start_size + delta
			new_size.x = maxf(new_size.x, MIN_W)
			new_size.y = maxf(new_size.y, MIN_H)
			_panel.size = new_size
			_reposition_handle()
			get_viewport().set_input_as_handled()


func _clamp_to_screen() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_panel.global_position.x = clampf(_panel.global_position.x, 0.0, vp.x - _panel.size.x)
	_panel.global_position.y = clampf(_panel.global_position.y, 0.0, vp.y - _panel.size.y)


func _refresh() -> void:
	if view == null:
		return

	var sel: String = str(view.call("ui_get_selected_text"))
	_selected_label.text = sel if sel != "" else "Selected: (none)"

	var mode: String = str(view.call("ui_get_mode_text"))
	_mode_label.text = "Mode: " + (mode if mode != "" else "None")

	if _month_label != null:
		var month_txt: String = str(view.call("ui_get_month_text"))
		_month_label.text = month_txt if month_txt != "" else "Month: --"

	if _gold_label != null:
		var gold_txt: String = str(view.call("ui_get_gold_text"))
		var upkeep_txt: String = str(view.call("ui_get_upkeep_text"))
		# Strip prefixes to combine into one compact line
		var gold_val: String = gold_txt.trim_prefix("Gold: ")
		var upkeep_val: String = upkeep_txt.trim_prefix("Upkeep: ")
		_gold_label.text = "Gold: %s | Upkeep: %s" % [gold_val, upkeep_val]

	if _ai_lab_status_label != null:
		var ai_lab_txt: String = str(view.call("ui_get_ai_lab_status_text"))
		_ai_lab_status_label.text = ai_lab_txt if ai_lab_txt != "" else "AI Lab: Idle"

	var has_sel: bool = bool(view.call("ui_has_selection"))
	_attack_btn.disabled = not has_sel
	_transfer_btn.disabled = not has_sel

	if _ai_lab_btn != null:
		var ai_lab_btn_txt: String = str(view.call("ui_get_ai_lab_button_text"))
		_ai_lab_btn.text = ai_lab_btn_txt if ai_lab_btn_txt != "" else "AI Lab Pass"

	if _ai_lab_months_btn != null:
		var ai_lab_months_txt: String = str(view.call("ui_get_ai_lab_months_text"))
		_ai_lab_months_btn.text = ai_lab_months_txt if ai_lab_months_txt != "" else "AI Lab: 36m"

	if _map_size_btn != null:
		var map_size_txt: String = str(view.call("ui_get_map_size_text"))
		_map_size_btn.text = map_size_txt if map_size_txt != "" else "Map Size: --"

	if _autotune_status_label != null:
		var view_status: String = ""
		if view != null and view.has_method("ui_get_autotune_status_text"):
			view_status = str(view.call("ui_get_autotune_status_text"))
		_autotune_status_label.text = view_status if view_status != "" else _autotune_status

	if _autotune_btn != null:
		_autotune_btn.text = "Stop AutoTune" if _autotuner != null else "AutoTune"
		var lab_running: bool = bool(view.call("ui_get_ai_lab_running")) if view.has_method("ui_get_ai_lab_running") else false
		_autotune_btn.disabled = lab_running


# ==================================================
# AUTO TUNER
# ==================================================

func _on_autotune_pressed() -> void:
	# If already running, stop (abandon current run — checkpoint is safe)
	if _autotuner != null:
		_autotuner = null
		_autotune_status = "AutoTune: Stopped"
		_close_metrics_panel()
		if _autotune_btn != null:
			_autotune_btn.text = "AutoTune"
		_refresh()
		return

	# Get settings from view
	if view == null or not view.has_method("ui_get_settings"):
		push_warning("MapDebugUI: view has no ui_get_settings()")
		_autotune_status = "AutoTune: No settings"
		_refresh()
		return

	var settings: MapSettings = view.call("ui_get_settings") as MapSettings
	if settings == null:
		push_warning("MapDebugUI: ui_get_settings() returned null")
		_autotune_status = "AutoTune: No settings"
		_refresh()
		return

	_autotuner = AIAutoTunerScript.new()
	_autotuner.progress_updated.connect(_on_autotune_progress)
	_autotune_status = "AutoTune: Starting..."
	_metrics_baseline.clear()
	_metrics_current.clear()
	_metrics_iteration = 0
	_build_metrics_panel()
	_refresh()

	DebugLogger.log("ai_autotune_ui_start", { "source": "MapDebugUI" })

	# Fire and forget — result written to user:// files automatically
	_run_autotune_async(settings)


func _run_autotune_async(settings: MapSettings) -> void:
	if _autotuner == null:
		return
	# Pass view as render_host so the map gets live preview updates
	var render_host: Node = view if (view != null and is_instance_valid(view)) else null
	var result: Dictionary = await _autotuner.run_async(self, settings, null,
		AIAutoTuner.DEFAULT_MONTHS, AIAutoTuner.DEFAULT_SEEDS,
		AIAutoTuner.DEFAULT_MAX_ITERATIONS, AIAutoTuner.DEFAULT_STALL_LIMIT,
		render_host)
	_autotuner = null

	var goals_met: bool = bool(result.get("goals_met", false))
	var val_passed: bool = bool(result.get("validation_passed", false))
	var score: float     = float(result.get("best_score", 0.0))
	var iters: int       = int(result.get("iterations_run", 0))

	if goals_met and val_passed:
		_autotune_status = "AutoTune: Done ✓ Score %.0f / %d iters" % [score, iters]
	elif goals_met:
		_autotune_status = "AutoTune: Goals met, val failed / %d iters" % iters
	else:
		_autotune_status = "AutoTune: Best %.0f / %d iters (goals unmet)" % [score, iters]

	if _autotune_btn != null:
		_autotune_btn.text = "AutoTune"
	_refresh()


func _on_autotune_progress(payload: Dictionary) -> void:
	var status: String    = str(payload.get("status", ""))
	var iteration: int    = int(payload.get("iteration", 0))
	var score: float      = float(payload.get("score", 0.0))
	var candidate: int    = int(payload.get("candidate_index", -1))
	var total: int        = int(payload.get("candidate_count", 0))
	var phase: int        = int(payload.get("phase", 1))
	var stall: int        = int(payload.get("stall_count", 0))

	match status:
		"baseline_start":
			_autotune_status = "AutoTune: Baseline..."
		"baseline_complete":
			_autotune_status = "AutoTune: Baseline %.0f" % score
			var base_metrics: Dictionary = payload.get("metrics", {}) as Dictionary
			if not base_metrics.is_empty():
				_metrics_current["_score"] = score
				_update_metrics_panel(base_metrics, 0)
		"resumed":
			_autotune_status = "AutoTune: Resumed iter %d" % iteration
		"candidate_evaluated":
			if total > 0:
				_autotune_status = "AutoTune: Iter %d  C%d/%d  Ph%d  Best %.0f" % [iteration, candidate + 1, total, phase, score]
			else:
				_autotune_status = "AutoTune: Iter %d  Best %.0f" % [iteration, score]
			var cand_metrics: Dictionary = payload.get("metrics", {}) as Dictionary
			if not cand_metrics.is_empty():
				_metrics_current["_score"] = score
				_update_metrics_panel(cand_metrics, iteration)
		"iteration_complete":
			_autotune_status = "AutoTune: Iter %d done  Best %.0f  Stall %d" % [iteration, score, stall]
			var iter_metrics: Dictionary = payload.get("metrics", {}) as Dictionary
			if not iter_metrics.is_empty():
				_metrics_iteration = iteration
				_metrics_current["_score"] = score
				_update_metrics_panel(iter_metrics, iteration)
		"validation_start":
			_autotune_status = "AutoTune: Validating..."
		"complete":
			var goals: bool = bool(payload.get("goals_met", false))
			var val: bool   = bool(payload.get("validation_passed", false))
			_autotune_status = "AutoTune: Complete (%s)" % ("✓" if goals and val else "~")
			var final_metrics: Dictionary = payload.get("metrics", {}) as Dictionary
			if not final_metrics.is_empty():
				_update_metrics_panel(final_metrics, _metrics_iteration)
		_:
			_autotune_status = "AutoTune: %s" % status

	if _autotune_status_label != null:
		_autotune_status_label.text = _autotune_status


# ==================================================
# AUTOTUNE METRICS PANEL
# ==================================================
# Metric definition: [key, label, target_min, target_max, format, higher_is_better]
# target_min / target_max: use -1 to mean "no bound on that side"
# format: "float2", "float1", "pct", "int"
const METRIC_DEFS: Array = [
	# key                                label                      min     max    fmt       higher_better
	["avg_attacks_per_month",            "Attacks/month",           1.5,    2.5,   "float1", true],
	["avg_captures_per_month",           "Captures/month",          0.5,    0.8,   "float2", true],
	["avg_first_attack_month",           "First attack month",      -1,     3.0,   "float1", false],
	["unique_attacker_count",            "Unique attackers",        12,     -1,    "int",    true],
	["avg_passive_months",               "Passive months (avg)",    -1,     10.8,  "float1", false],
	["economic_collapse_run_rate",       "Collapse rate",           -1,     0.10,  "pct",    false],
	["avg_leader_density",               "Leader density",          1.2,    1.6,   "float2", true],
	["avg_border_backup_coverage",       "Border backup",           0.60,   -1,    "float2", true],
	["avg_frontline_overload",           "Frontline overload",      -1,     0.70,  "float2", false],
	["avg_attacks_vs_faction_per_month", "FvF attacks/month",       0.5,    -1,    "float2", true],
	["avg_passive_faction_war_months",   "War drought months",      -1,     6.0,   "float1", false],
]

const PANEL_W: int = 400
const ROW_H: int   = 20
const METRICS_TITLE_H: int = 24
const COL_LABEL: int  = 170
const COL_BASE: int   = 60
const COL_NOW: int    = 60
const COL_TARGET: int = 70
const COL_STATUS: int = 36

func _build_metrics_panel() -> void:
	if _metrics_panel != null:
		_metrics_panel.queue_free()
	_metrics_panel = null
	_metrics_rows.clear()

	var panel_h: int = METRICS_TITLE_H + 28 + METRIC_DEFS.size() * ROW_H + 14
	var vp: Vector2 = get_viewport().get_visible_rect().size

	var root := Control.new()
	root.name = "AutotuneMetricsPanel"
	root.position = Vector2(vp.x - PANEL_W - 20, 10)
	root.size = Vector2(PANEL_W, panel_h)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_metrics_panel = root

	# Background
	var bg := PanelContainer.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.06, 0.06, 0.10, 0.94)
	bg_style.border_color = Color(0.40, 0.45, 0.65, 1.0)
	bg_style.set_border_width_all(1)
	bg.add_theme_stylebox_override("panel", bg_style)
	root.add_child(bg)

	# Title bar
	var title_bar := Panel.new()
	title_bar.position = Vector2.ZERO
	title_bar.size = Vector2(PANEL_W, METRICS_TITLE_H)
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(0.12, 0.14, 0.26, 1.0)
	title_bar.add_theme_stylebox_override("panel", ts)
	title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(title_bar)

	var title_lbl := Label.new()
	title_lbl.text = "AUTOTUNE METRICS"
	title_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 11)
	title_lbl.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_bar.add_child(title_lbl)

	# Drag support on title bar
	var drag_state := {"dragging": false, "offset": Vector2.ZERO}
	title_bar.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				drag_state["dragging"] = mb.pressed
				if mb.pressed:
					drag_state["offset"] = root.global_position - mb.global_position
		elif ev is InputEventMouseMotion and drag_state["dragging"]:
			root.global_position = (ev as InputEventMouseMotion).global_position + drag_state["offset"]
	)

	# Column header row
	var header_y: int = METRICS_TITLE_H + 4
	_add_metrics_label(root, "Metric",   6,           header_y, COL_LABEL - 6, Color(0.60, 0.65, 0.80), 10)
	_add_metrics_label(root, "Start",    COL_LABEL,   header_y, COL_BASE,      Color(0.60, 0.65, 0.80), 10)
	_add_metrics_label(root, "Now",      COL_LABEL + COL_BASE, header_y, COL_NOW, Color(0.60, 0.65, 0.80), 10)
	_add_metrics_label(root, "Target",   COL_LABEL + COL_BASE + COL_NOW, header_y, COL_TARGET, Color(0.60, 0.65, 0.80), 10)
	_add_metrics_label(root, "✓",        COL_LABEL + COL_BASE + COL_NOW + COL_TARGET, header_y, COL_STATUS, Color(0.60, 0.65, 0.80), 10)

	# Separator
	var sep_y: int = header_y + ROW_H - 2
	var sep := ColorRect.new()
	sep.position = Vector2(4, sep_y)
	sep.size = Vector2(PANEL_W - 8, 1)
	sep.color = Color(0.30, 0.35, 0.50, 0.7)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(sep)

	# Metric rows
	var row_y: int = sep_y + 4
	for def_val in METRIC_DEFS:
		var def: Array = def_val as Array
		var key: String = str(def[0])
		var row_label: String = str(def[1])

		_add_metrics_label(root, row_label, 6, row_y, COL_LABEL - 6, Color(0.80, 0.82, 0.90), 10)

		var base_lbl := _add_metrics_label(root, "--", COL_LABEL, row_y, COL_BASE, Color(0.55, 0.65, 0.75), 10)
		var now_lbl  := _add_metrics_label(root, "--", COL_LABEL + COL_BASE, row_y, COL_NOW, Color(1.0, 1.0, 1.0), 11)
		var tgt_lbl  := _add_metrics_label(root, _format_target(def), COL_LABEL + COL_BASE + COL_NOW, row_y, COL_TARGET, Color(0.55, 0.65, 0.55), 10)
		var status_lbl := _add_metrics_label(root, "·", COL_LABEL + COL_BASE + COL_NOW + COL_TARGET, row_y, COL_STATUS, Color(0.5, 0.5, 0.5), 12)

		_metrics_rows[key] = {"base": base_lbl, "now": now_lbl, "status": status_lbl}
		row_y += ROW_H

	# Iteration counter at bottom
	var iter_lbl := _add_metrics_label(root, "Iteration: —", 6, row_y + 4, PANEL_W - 12, Color(0.55, 0.60, 0.75), 10)
	_metrics_rows["_iter"] = {"base": null, "now": iter_lbl, "status": null}


func _add_metrics_label(parent: Control, text: String, x: int, y: int, w: int, col: Color, sz: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = Vector2(x, y)
	lbl.size = Vector2(w, ROW_H)
	lbl.add_theme_font_size_override("font_size", sz)
	lbl.add_theme_color_override("font_color", col)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.clip_text = true
	parent.add_child(lbl)
	return lbl


func _format_target(def: Array) -> String:
	var lo: float  = float(def[2])
	var hi: float  = float(def[3])
	var fmt: String = str(def[4])
	if lo < 0 and hi < 0:
		return "any"
	if lo < 0:
		return "≤ %s" % _fmt_val(hi, fmt)
	if hi < 0:
		return "≥ %s" % _fmt_val(lo, fmt)
	return "%s–%s" % [_fmt_val(lo, fmt), _fmt_val(hi, fmt)]


func _fmt_val(v: float, fmt: String) -> String:
	match fmt:
		"float2": return "%.2f" % v
		"float1": return "%.1f" % v
		"pct":    return "%.0f%%" % (v * 100.0)
		"int":    return "%d" % int(v)
	return "%.2f" % v


func _get_metric_val(metrics: Dictionary, key: String) -> float:
	# avg_passive_months needs converting to rate for display comparison
	return float(metrics.get(key, -1.0))


func _update_metrics_panel(metrics: Dictionary, iteration: int) -> void:
	if _metrics_panel == null:
		return

	for def_val in METRIC_DEFS:
		var def: Array = def_val as Array
		var key: String    = str(def[0])
		var lo: float      = float(def[2])
		var hi: float      = float(def[3])
		var fmt: String    = str(def[4])
		var hi_good: bool  = bool(def[5])

		if not _metrics_rows.has(key):
			continue
		var row: Dictionary = _metrics_rows[key] as Dictionary
		var val: float = _get_metric_val(metrics, key)

		# Format current value
		var val_str: String = _fmt_val(val, fmt) if val >= 0.0 else "--"

		# Set baseline on first call — only from complete evaluations (iteration=0)
		# Guard against partial/zero data from mid-run candidate updates
		var looks_complete: bool = float(metrics.get("avg_attacks_per_month", 0.0)) > 0.0 or float(metrics.get("avg_captures_per_month", 0.0)) > 0.0
		if looks_complete and (_metrics_baseline.is_empty() or not _metrics_baseline.has(key)):
			_metrics_baseline[key] = val
			if row["base"] != null:
				(row["base"] as Label).text = val_str

		# Update "Now" column
		(row["now"] as Label).text = val_str

		# Colour and status indicator
		var pass_lo: bool = lo < 0.0 or val >= lo
		var pass_hi: bool = hi < 0.0 or val <= hi
		var passing: bool = pass_lo and pass_hi and val >= 0.0

		var now_lbl: Label = row["now"] as Label
		var status_lbl: Label = row["status"] as Label

		if val < 0.0:
			now_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			status_lbl.text = "·"
			status_lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		elif passing:
			now_lbl.add_theme_color_override("font_color", Color(0.45, 0.90, 0.45))
			status_lbl.text = "✓"
			status_lbl.add_theme_color_override("font_color", Color(0.45, 0.90, 0.45))
		else:
			# How far off are we?
			var pct_off: float = 0.0
			if not pass_lo and lo > 0.0:
				pct_off = (lo - val) / lo
			elif not pass_hi and hi > 0.0:
				pct_off = (val - hi) / hi
			if pct_off < 0.20:
				now_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
				status_lbl.text = "~"
				status_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
			else:
				now_lbl.add_theme_color_override("font_color", Color(0.95, 0.40, 0.30))
				status_lbl.text = "✗"
				status_lbl.add_theme_color_override("font_color", Color(0.95, 0.40, 0.30))

	# Update iteration counter
	if _metrics_rows.has("_iter"):
		var iter_row: Dictionary = _metrics_rows["_iter"] as Dictionary
		if iter_row["now"] != null:
			(iter_row["now"] as Label).text = "Iteration: %d  |  Score: %.0f" % [iteration, float(_metrics_current.get("_score", 0.0))]


func _close_metrics_panel() -> void:
	if _metrics_panel != null:
		_metrics_panel.queue_free()
		_metrics_panel = null
	_metrics_rows.clear()
	_metrics_baseline.clear()
	_metrics_current.clear()
	_metrics_iteration = 0
