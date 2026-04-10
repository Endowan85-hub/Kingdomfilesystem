# ==================================================
# ProvinceTooltip
# ==================================================
# Small floating tooltip shown when hovering a province.
# Follows the mouse. Hidden when no province is hovered.
# ==================================================
extends CanvasLayer
class_name ProvinceTooltip

var game_state: GameState = null
var human_faction_id: int = 0

var _panel: PanelContainer
var _name_lbl: Label
var _biome_lbl: Label
var _owner_lbl: Label
var _fort_lbl: Label
var _income_lbl: Label


func _ready() -> void:
	layer = 20
	_build()
	hide()


func _build() -> void:
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.10, 0.92)
	style.border_color = Color(0.40, 0.36, 0.22)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.custom_minimum_size = Vector2(180, 0)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	_panel.add_child(vbox)

	_name_lbl  = _row(vbox, "",  14, Color(0.95, 0.85, 0.45))
	_biome_lbl = _row(vbox, "",  11, Color(0.60, 0.70, 0.60))
	_owner_lbl = _row(vbox, "",  11, Color(0.75, 0.73, 0.65))
	_fort_lbl  = _row(vbox, "",  11, Color(0.65, 0.72, 0.80))
	_income_lbl= _row(vbox, "",  11, Color(0.75, 0.80, 0.45))


func _row(parent: Control, text: String, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	parent.add_child(lbl)
	return lbl


func _process(_delta: float) -> void:
	if visible and _panel != null:
		var mp: Vector2 = get_viewport().get_mouse_position()
		_panel.position = mp + Vector2(14, 14)
		# Keep on screen
		var vp: Vector2 = get_viewport().get_visible_rect().size
		var ps: Vector2 = _panel.size
		if _panel.position.x + ps.x > vp.x:
			_panel.position.x = mp.x - ps.x - 8
		if _panel.position.y + ps.y > vp.y:
			_panel.position.y = mp.y - ps.y - 8


func show_province(province_id: int) -> void:
	if game_state == null or game_state.map_data == null or province_id < 0:
		hide()
		return

	if province_id >= game_state.map_data.provinces.size():
		hide()
		return

	var p: ProvinceData = game_state.map_data.provinces[province_id] as ProvinceData
	if p == null:
		hide()
		return

	_name_lbl.text = p.display_name
	_biome_lbl.text = str(p.biome).capitalize()

	var owner_name: String = "Neutral"
	for item in game_state.map_data.factions:
		var f: FactionData = item as FactionData
		if f != null and int(f.id) == int(p.owner_id):
			owner_name = f.display_name
			break
	_owner_lbl.text = "Owner: %s" % owner_name
	_fort_lbl.text  = "Fort: %d" % int(p.fort_level)
	_income_lbl.text = "Income: %d" % int(p.income)

	show()


func hide_tooltip() -> void:
	hide()
