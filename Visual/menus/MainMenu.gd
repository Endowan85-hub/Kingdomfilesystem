# ==================================================
# MainMenu
# ==================================================
# Throne room background. The painted torch flames stay untouched.
# Two additive warm-glow sprites pulse at each torch position to
# simulate firelight flickering on the surrounding stone — no
# particles drawn on top of the existing art.
#
# Torch UV fractions (0..1 within image, tweak to reposition):
#   _TORCH_LEFT_UV  = left torch flame center
#   _TORCH_RIGHT_UV = right torch flame center
# ==================================================
extends Control
class_name MainMenu

const _BG_PATH         := "res://Art/ui/main_menu.png"
const _TORCH_LEFT_UV   := Vector2(0.175, 0.34)
const _TORCH_RIGHT_UV  := Vector2(0.825, 0.34)
const _SIDEBAR_COLOR   := Color(0.098, 0.067, 0.106, 1.0)

# Glow sprites animated in _process
var _glow_sprites : Array[Sprite2D] = []
var _glow_timers  : Array[float]    = []


func _ready() -> void:
	DebugLogger.init(true)  # fresh log every launch
	_build_ui()


func _process(delta: float) -> void:
	for i in _glow_sprites.size():
		_glow_timers[i] += delta
		var t := _glow_timers[i]
		# Layered sines = organic flicker, never fully off
		var f := 0.32 + 0.07 * sin(t * 7.1 + i * 1.9) + 0.05 * sin(t * 13.7 + i * 3.1)
		_glow_sprites[i].modulate.a = f


func _build_ui() -> void:
	# --- Full-screen sidebar color base ---
	var base := ColorRect.new()
	base.color = _SIDEBAR_COLOR
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)

	# --- Background image ---
	var bg: TextureRect = null
	if ResourceLoader.exists(_BG_PATH):
		bg = TextureRect.new()
		bg.texture = load(_BG_PATH)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)

	# --- Compute image rect, then add fades and glows ---
	if bg != null:
		var vp_size   := get_viewport().get_visible_rect().size
		var tex_size  := Vector2(bg.texture.get_width(), bg.texture.get_height())
		var img_scale := minf(vp_size.x / tex_size.x, vp_size.y / tex_size.y)
		var img_size  := tex_size * img_scale
		var img_off   := (vp_size - img_size) * 0.5
		var img_rect  := Rect2(img_off, img_size)

		_add_edge_fades(img_rect, vp_size)
		_add_torch_glow(img_off + img_size * _TORCH_LEFT_UV,  img_scale, 0.00)
		_add_torch_glow(img_off + img_size * _TORCH_RIGHT_UV, img_scale, 0.85)

	# --- Title ---
	var title := Label.new()
	title.text = "KINGDOM"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 80)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 60
	title.offset_bottom = 160
	add_child(title)

	var subtitle := Label.new()
	subtitle.text = "A Grand Strategy of Conquest"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color(0.80, 0.70, 0.55))
	subtitle.set_anchors_preset(Control.PRESET_TOP_WIDE)
	subtitle.offset_top = 148
	subtitle.offset_bottom = 178
	add_child(subtitle)

	# --- Menu buttons — lower-left so throne stays clear ---
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.position = Vector2(100, 700)
	add_child(col)

	_add_button(col, "New Game", _on_new_game, false)
	_add_button(col, "Continue", _on_continue, true)
	_add_button(col, "Settings", _on_settings, false)
	_add_button(col, "Quit",     _on_quit,     false)

	# --- Version label ---
	var version := Label.new()
	version.text = "v0.1 — Visual Layer Alpha"
	version.add_theme_font_size_override("font_size", 10)
	version.add_theme_color_override("font_color", Color(0.40, 0.38, 0.35))
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.offset_left = -200
	version.offset_top = -30
	add_child(version)


func _add_edge_fades(img_rect: Rect2, vp_size: Vector2) -> void:
	# 320px wide strips, centred on the image edge (half inside, half outside)
	# so the transition is smooth with no visible seam
	var fade_w    := 320.0
	var bg_opaque := _SIDEBAR_COLOR
	var bg_clear  := Color(_SIDEBAR_COLOR.r, _SIDEBAR_COLOR.g, _SIDEBAR_COLOR.b, 0.0)

	for side in [0, 1]:  # 0 = left, 1 = right
		var grad := Gradient.new()
		if side == 0:
			grad.set_color(0, bg_opaque)
			grad.set_color(1, bg_clear)
		else:
			grad.set_color(0, bg_clear)
			grad.set_color(1, bg_opaque)
		var gtex := GradientTexture1D.new()
		gtex.gradient = grad
		var rect := TextureRect.new()
		rect.texture = gtex
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.size = Vector2(fade_w, vp_size.y)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if side == 0:
			rect.position = Vector2(img_rect.position.x - fade_w * 0.5, 0.0)
		else:
			rect.position = Vector2(img_rect.position.x + img_rect.size.x - fade_w * 0.5, 0.0)
		add_child(rect)


func _add_torch_glow(pos: Vector2, img_scale: float, time_offset: float) -> void:
	# Build a soft radial glow texture (warm amber, transparent at edges)
	var size  := 128
	var img   := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5, size * 0.5)
	for y in size:
		for x in size:
			var d := Vector2(x, y).distance_to(center) / (size * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a  # quadratic falloff — soft edge
			img.set_pixel(x, y, Color(1.0, 0.62, 0.18, a))
	var tex := ImageTexture.create_from_image(img)

	var glow := Sprite2D.new()
	glow.texture = tex
	glow.position = pos
	# Scale so the glow halo covers the stone around the torch
	var glow_radius := 260.0 * img_scale
	glow.scale = Vector2(glow_radius / (size * 0.5), glow_radius / (size * 0.5))
	glow.modulate = Color(1.0, 1.0, 1.0, 0.32)

	# Additive blend: brightens whatever is beneath without covering it
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = mat

	add_child(glow)
	_glow_sprites.append(glow)
	_glow_timers.append(time_offset)


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
	pass  # save system not yet implemented


func _on_settings() -> void:
	var settings_scene: Node = load("res://Visual/menus/SettingsMenu.tscn").instantiate()
	add_child(settings_scene)


func _on_quit() -> void:
	get_tree().quit()
