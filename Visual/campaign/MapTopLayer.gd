extends Node2D
# Draws content that must appear above the river water strip:
# cell borders, roads, trees, province nodes, labels, and order indicators.
# Added as a child of PlayerMap AFTER RiverOverlay so it renders on top.

var pm  # PlayerMap — set by PlayerMap at init time


func _draw() -> void:
	if pm == null or pm.map_data == null:
		return
	_draw_cell_borders()
	_draw_routes()
	_draw_trees()
	_draw_nodes()
	_draw_labels()
	_draw_order_indicators()


func _to_screen(world: Vector2) -> Vector2:
	return (world + pm._origin) * pm._zoom


# --------------------------------------------------
# Cell borders (selection, hover, pick mode)
# --------------------------------------------------
func _draw_cell_borders() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var elapsed: float = now - pm._border_bounce_start
	var bounce: float
	if pm._border_bounce_start >= 0.0 and elapsed < pm.BORDER_BOUNCE_DURATION:
		bounce = 7.0 + sin(elapsed / pm.BORDER_BOUNCE_DURATION * PI) * 8.0
	else:
		bounce = 7.0

	for item in pm.map_data.provinces:
		var p: ProvinceData = item as ProvinceData
		var pid: int = int(p.id)
		if not pm._clipped_cells.has(pid):
			continue
		var world_pts: PackedVector2Array = pm._clipped_cells[pid]
		if world_pts.size() < 3:
			continue
		var pts := PackedVector2Array()
		for v in world_pts:
			pts.append(_to_screen(v))
		var is_selected: bool = pid == pm._selected_id
		var is_hover: bool    = pid == pm._hover_id
		if is_selected:
			var owner_id: int = int(p.owner_id)
			var neon_c: Color
			if owner_id < 0:
				neon_c = Color(0.6, 0.6, 0.6, 0.5)
			else:
				var base_c: Color = pm._faction_color(owner_id)
				neon_c = Color.from_hsv(base_c.h, 1.0, 1.0, 0.5)
			var closed_pts := pts.duplicate()
			if closed_pts.size() > 0:
				closed_pts.append(closed_pts[0])
			draw_polyline(closed_pts, neon_c, bounce, true)
		if is_hover and not is_selected:
			draw_polyline(pts, Color(1.0, 1.0, 1.0, 0.30), 1.5, true)
		if pm._pick_mode != 0:
			var owner_id: int = int(p.owner_id)
			var is_human:   bool = owner_id == pm.human_faction_id
			var is_neutral: bool = owner_id < 0
			if pid == pm._pick_source_id:
				draw_polyline(pts, Color(1.0, 0.90, 0.20, 1.0), 3.5, true)
			elif pm._pick_mode == 1:
				var is_valid: bool = pm._pick_valid_targets.is_empty() or pm._pick_valid_targets.has(pid)
				if is_valid and not is_human and not is_neutral:
					draw_polyline(pts, Color(1.0, 0.30, 0.25, 0.90), 2.5, true)
				elif is_valid and is_neutral:
					draw_polyline(pts, Color(1.0, 0.60, 0.20, 0.85), 2.5, true)
			elif pm._pick_mode == 2 and is_human and pid != pm._pick_source_id:
				draw_polyline(pts, Color(0.35, 0.70, 1.0, 0.90), 2.5, true)


# --------------------------------------------------
# Road routes
# --------------------------------------------------
func _draw_routes() -> void:
	if pm._road_straight_textures.is_empty() or pm._route_paths.is_empty():
		return
	var stamp_w: float = 1.6 * pm._zoom
	var step: float = stamp_w * 0.65
	for ri in pm._route_paths.size():
		var entry: Dictionary = pm._route_paths[ri]
		var world_pts: Array  = entry["pts"]
		var tex: Texture2D    = pm._road_straight_textures[entry["style"]]
		var screen_pts: Array = []
		for wp in world_pts:
			screen_pts.append(_to_screen(wp))
		for pass_i in 2:
			var w: float     = stamp_w * (1.6 if pass_i == 0 else 1.0)
			var alpha: float = 0.25   if pass_i == 0 else 1.0
			var col := Color(0.72, 0.65, 0.55, alpha)
			var accum: float = 0.0
			var last_dir := Vector2.RIGHT
			for ci in range(1, screen_pts.size()):
				var prev: Vector2 = screen_pts[ci - 1]
				var curr: Vector2 = screen_pts[ci]
				var seg: Vector2  = curr - prev
				var seg_len: float = seg.length()
				if seg_len > 0.0:
					last_dir = seg / seg_len
				accum += seg_len
				while accum >= step:
					accum -= step
					var stamp_pos: Vector2 = curr - last_dir * accum
					draw_set_transform_matrix(Transform2D(last_dir.angle(), stamp_pos))
					draw_texture_rect(tex, Rect2(-w * 0.5, -w * 0.5, w, w), false, col)
	draw_set_transform_matrix(Transform2D.IDENTITY)


# --------------------------------------------------
# Trees
# --------------------------------------------------
func _draw_trees() -> void:
	if pm._tree_meshes.is_empty():
		return
	var xform := Transform2D(Vector2(pm._zoom, 0.0), Vector2(0.0, pm._zoom), pm._origin * pm._zoom)
	for i in pm._tree_meshes.size():
		var mesh: ArrayMesh = pm._tree_meshes[i]
		if mesh == null:
			continue
		draw_mesh(mesh, pm._tree_textures[i], xform)


# --------------------------------------------------
# Province nodes + fort indicators
# --------------------------------------------------
func _draw_nodes() -> void:
	for item in pm.map_data.provinces:
		var p: ProvinceData = item as ProvinceData
		var pid: int = int(p.id)
		var pos: Vector2 = _to_screen(p.center)
		var owner_id: int = int(p.owner_id)
		var is_neutral: bool = owner_id < 0

		var province_tex: Texture2D = null
		if int(p.fort_level) >= 2:
			province_tex = pm._province_lvl2_tex
		else:
			var biome: String = str(p.biome) if p.biome != "" else "plains"
			var biome_arr: Array = pm._province_biome_textures.get(biome, [])
			if biome_arr.is_empty():
				province_tex = pm._province_lvl1_tex
			else:
				province_tex = biome_arr[pid % biome_arr.size()]

		if province_tex != null:
			var sz: float   = 128.0 * pm._zoom * 0.3
			var half: float = sz * 0.5
			var flip: bool  = (pid * 2654435761) % 3 == 0
			var rect := Rect2(pos.x - half, pos.y - half, sz, sz)

			var sun_t: float = fmod(pm._sun_time / pm.SUN_CYCLE_SECONDS, 1.0)
			var afternoon_stretch: float = clampf((sun_t - 0.5) * 2.0, 0.0, 1.0)
			var morning_stretch:   float = clampf((0.5 - sun_t) * 2.0, 0.0, 1.0)
			var sun_height: float = 1.0 - clampf(
					absf(pm._sun_world_pos.x - p.center.x) / maxf(pm._map_bounds_rect.size.x, 1.0), 0.0, 1.0)
			var base_rx: float  = lerpf(half * 1.45, half * 1.20, sun_height)
			var shad_rx: float  = base_rx * lerpf(1.0, 1.6, morning_stretch) * lerpf(1.0, 2.2, afternoon_stretch)
			var shad_ry: float  = lerpf(half * 0.55, half * 0.35, sun_height)
			var h_shift: float  = (half - shad_rx) + afternoon_stretch * half * 1.8
			var shad_pts := PackedVector2Array()
			for si in 20:
				var a: float = float(si) / 20.0 * TAU
				shad_pts.append(Vector2(pos.x + h_shift + cos(a) * shad_rx,
						pos.y + half * 0.45 + sin(a) * shad_ry))
			draw_colored_polygon(shad_pts, Color(0.0, 0.0, 0.0, 0.55))
			if flip:
				draw_set_transform_matrix(Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2(pos.x * 2.0, 0.0)))
			draw_texture_rect(province_tex, rect, false, Color(1.0, 1.0, 1.0, 1.0))
			if flip:
				draw_set_transform_matrix(Transform2D.IDENTITY)

		if pm.game_state != null and not is_neutral:
			var leaders: Array = pm.game_state.get_province_leaders(pid, false)
			if not leaders.is_empty():
				draw_circle(pos, 3.5, Color(1, 1, 1, 0.90))

		if not is_neutral:
			_draw_fort_indicator(p, pos)


func _draw_fort_indicator(p: ProvinceData, pos: Vector2) -> void:
	var fort: int = clamp(int(p.fort_level), 0, 5)
	if fort == 0:
		return
	var dot_r: float   = 3.0
	var spacing: float = 8.0
	var total_w: float = fort * spacing - spacing * 0.5
	var start_x: float = pos.x - total_w * 0.5
	for i in range(fort):
		draw_circle(Vector2(start_x + i * spacing, pos.y + pm.NODE_RADIUS + 6.0),
				dot_r, Color(0.90, 0.80, 0.40, 0.85))


# --------------------------------------------------
# Province labels
# --------------------------------------------------
func _draw_labels() -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var font_size: int = clamp(int(pm._zoom * 5.0), 13, 20)
	for item in pm.map_data.provinces:
		var p: ProvinceData = item as ProvinceData
		var pos: Vector2 = _to_screen(p.center)
		var label: String = str(p.display_name)
		var text_w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var draw_pos := Vector2(pos.x - text_w * 0.5, pos.y - pm.NODE_RADIUS - 5)
		draw_string(font, draw_pos + Vector2(1, 1), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.90))
		var text_c: Color = Color(0.68, 0.64, 0.56, 0.85) if int(p.owner_id) < 0 \
				else Color(1.0, 0.97, 0.88, 1.0)
		draw_string(font, draw_pos, label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_c)


# --------------------------------------------------
# Attack / transfer order arrows
# --------------------------------------------------
func _draw_order_indicators() -> void:
	if pm.game_state == null or pm.game_state.order_book == null:
		return
	for atk in pm.game_state.order_book.get_attacks(pm.human_faction_id):
		var from_id: int = int(atk.get("from", -1))
		var to_id:   int = int(atk.get("to",   -1))
		if from_id < 0 or to_id < 0: continue
		if from_id >= pm.map_data.provinces.size() or to_id >= pm.map_data.provinces.size(): continue
		var from_p: ProvinceData = pm.map_data.provinces[from_id] as ProvinceData
		var to_p:   ProvinceData = pm.map_data.provinces[to_id]   as ProvinceData
		if from_p == null or to_p == null: continue
		var from_s := _to_screen(from_p.center)
		var to_s   := _to_screen(to_p.center)
		draw_line(from_s, to_s, Color(1.0, 0.25, 0.20, 0.55), 2.0)
		_draw_arrowhead(from_s, to_s, Color(1.0, 0.30, 0.20, 0.90))
		_draw_crossed_swords(_to_screen(to_p.center) + Vector2(0.0, -pm.NODE_RADIUS - 16.0),
				10.0, Color(1.0, 0.28, 0.18, 1.0))
	for xfer in pm.game_state.order_book.get_transfers(pm.human_faction_id):
		var from_id: int = int(xfer.get("from", -1))
		var to_id:   int = int(xfer.get("to",   -1))
		if from_id < 0 or to_id < 0: continue
		if from_id >= pm.map_data.provinces.size() or to_id >= pm.map_data.provinces.size(): continue
		var from_p: ProvinceData = pm.map_data.provinces[from_id] as ProvinceData
		var to_p:   ProvinceData = pm.map_data.provinces[to_id]   as ProvinceData
		if from_p == null or to_p == null: continue
		var from_s := _to_screen(from_p.center)
		var to_s   := _to_screen(to_p.center)
		draw_line(from_s, to_s, Color(0.35, 0.70, 1.0, 0.55), 2.0)
		_draw_arrowhead(from_s, to_s, Color(0.35, 0.70, 1.0, 0.90))
		_draw_transfer_badge(_to_screen(to_p.center) + Vector2(0.0, -pm.NODE_RADIUS - 16.0),
				10.0, Color(0.35, 0.72, 1.0, 1.0))


func _draw_arrowhead(from: Vector2, to: Vector2, color: Color) -> void:
	var dir: Vector2  = (to - from).normalized()
	var tip: Vector2  = to - dir * (pm.NODE_RADIUS + 3.0)
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var sz: float = 7.0
	draw_line(tip, tip - dir * sz + perp * sz * 0.5, color, 2.0)
	draw_line(tip, tip - dir * sz - perp * sz * 0.5, color, 2.0)


func _draw_crossed_swords(center: Vector2, size: float, color: Color) -> void:
	draw_circle(center, size + 3.5, Color(0.05, 0.03, 0.06, 0.88))
	var h: float  = size * 0.82
	var g: float  = size * 0.38
	var go: float = size * 0.18
	draw_line(center + Vector2(-h, -h), center + Vector2(h, h), color, 2.0)
	var gp1 := center + Vector2(-go, -go)
	draw_line(gp1 - Vector2(1.0, -1.0).normalized() * g, gp1 + Vector2(1.0, -1.0).normalized() * g, color, 2.0)
	draw_line(center + Vector2(h, -h), center + Vector2(-h, h), color, 2.0)
	var gp2 := center + Vector2(go, -go)
	draw_line(gp2 - Vector2(1.0, 1.0).normalized() * g, gp2 + Vector2(1.0, 1.0).normalized() * g, color, 2.0)


func _draw_transfer_badge(center: Vector2, size: float, color: Color) -> void:
	draw_circle(center, size + 3.5, Color(0.04, 0.05, 0.10, 0.88))
	var h: float   = size * 0.72
	var tip: float = size * 0.32
	draw_line(Vector2(center.x - h, center.y), Vector2(center.x + h, center.y), color, 2.0)
	draw_line(Vector2(center.x + h, center.y), Vector2(center.x + h - tip, center.y - tip * 0.6), color, 2.0)
	draw_line(Vector2(center.x + h, center.y), Vector2(center.x + h - tip, center.y + tip * 0.6), color, 2.0)
