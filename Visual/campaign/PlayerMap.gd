# ==================================================
# PlayerMap
# ==================================================
# Player-facing campaign map rendered as a Node2D.
# Draws styled province fills, borders, route lines,
# and province nodes on top of a parchment background.
#
# Reads from GameState / MapData -- never modifies them.
# Emits signals for province hover and click.
#
# Phase 2 visual layer -- no simulation logic here.
# ==================================================
extends Node2D
class_name PlayerMap

signal province_hovered(province_id: int)
signal province_clicked(province_id: int)



# Set by CampaignMap after initialization
var game_state: GameState = null
var map_data: MapData = null
var human_faction_id: int = 0

# Pixels reserved on the left for the ProvincePanel
var left_margin: float = 1040.0

# Camera / pan / zoom
var _zoom: float = 1.0
var _zoom_min: float = 0.1
var _zoom_max: float = 20.0
var _origin: Vector2 = Vector2.ZERO

# Pan input state
var _is_panning: bool = false
var _left_held: bool = false
var _press_pos: Vector2 = Vector2.ZERO

# Momentum / fling
var _pan_velocity: Vector2 = Vector2.ZERO   # world units per second
var _velocity_samples: Array = []           # recent [relative_screen, dt] pairs
const PAN_FRICTION:     float = 8.0         # higher = stops faster
const PAN_FLING_FRAMES: int   = 5           # how many recent frames to average velocity

# Smooth center-on-province
var _cam_target: Vector2 = Vector2.ZERO
var _cam_lerping: bool = false

# Cached map bounds (set in _frame_map, used for zoom clamping)
var _map_bounds_rect: Rect2 = Rect2()

# Voronoi cells mirrored from debug view
var _voronoi_cells: Dictionary = {}        # int -> Array[Vector2]  (original, used for picking)
var _clipped_cells: Dictionary = {}        # int -> PackedVector2Array (clipped to continent)
var _continent_poly: PackedVector2Array = PackedVector2Array()
var _island_polys: Array = []              # Array of PackedVector2Array

# Perf tracking
var _perf_acc: float     = 0.0
var _perf_frames: int    = 0
var _perf_slow: int      = 0    # frames over spike threshold
var _perf_min_ms: float  = 9999.0
var _perf_max_ms: float  = 0.0
const PERF_LOG_INTERVAL: float = 10.0   # seconds between summary logs
const PERF_SPIKE_MS:     float = 33.3   # >33ms = below 30fps spike

var _grass_atlas_tex: Texture2D = null
var _terrain_tile_data: Array = []
var _terrain_mesh: ArrayMesh = null

var _light_atlas_tex: Texture2D = null
var _light_tile_data: Array = []
var _light_mesh: ArrayMesh = null

var _dark_atlas_tex: Texture2D = null
var _dark_tile_data: Array = []
var _dark_mesh: ArrayMesh = null

var _swamp_atlas_tex: Texture2D = null
var _swamp_tile_data: Array = []
var _swamp_ie_tex: Texture2D = null
var _swamp_ie_data: Array = []

var _desert_atlas_tex: Texture2D = null
var _desert_tile_data: Array = []
var _desert_mesh: ArrayMesh = null

var _tundra_atlas_tex: Texture2D = null
var _tundra_tile_data: Array = []
var _tundra_mesh: ArrayMesh = null

var _swamp_mesh: ArrayMesh = null
var _swamp_ie_mesh: ArrayMesh = null

var _tree_textures: Array = []   # Array of Texture2D
var _dead_tree_start_idx: int = 0
var _tundra_tree_start_idx: int = 0
var _grass_overlay_tex: Texture2D = null
var _province_lvl1_tex: Texture2D = null
var _province_lvl2_tex: Texture2D = null
var _province_biome_textures: Dictionary = {}  # biome -> Array[Texture2D]
var _road_straight_textures: Array = []  # road_straight_0..3
var _road_curve_textures: Array = []     # road_curve_0..3
var _route_paths: Array = []             # prebuilt world-space curve points per route

# River
const RIVER_TILE_WORLD: float = 45.0
var _river_tiles: Array = []
var _river_path_tiles: Array = []        # all tile placements (all branches)
var _river_parallax_tex: Texture2D = null
var _river_overlay: Node2D = null
var _river_grid_path: Array = []         # main river path
var _river_branch_paths: Array = []      # tributary paths
var _river_smooth_main: Array = []       # cached Chaikin-smoothed main path
var _river_smooth_branches: Array = []   # cached Chaikin-smoothed tributary paths

# Prebuilt river strip meshes — water fill rendered by RiverOverlay with TIME shader
var _river_main_strip_mesh: ArrayMesh = null
var _river_trib_strip_meshes: Array = []
# Per-tributary world-space bank edge data for GDScript bank-line drawing
var _river_trib_bank_data: Array = []

# Sun shadow redraw throttle — node shadow ellipses update every N seconds
var _last_sun_redraw_time: float = -999.0
const SUN_SHADOW_REDRAW_INTERVAL: float = 5.0

var _tree_positions: Array = []         # raw from terrain generator
var _drawable_trees: Array = []         # pre-filtered, coast trees removed
var _tree_meshes: Array = []            # one ArrayMesh per texture index (world-space quads)
const TREE_WORLD_SIZE: float = 16.0  # half-width/height in world units

# Weather: GPU shader-driven cloud shadows + sun light wash
const CloudShadowShader := preload("res://Visual/campaign/CloudShadow.gdshader")
const SwampFogShader    := preload("res://Visual/campaign/SwampFog.gdshader")
var _weather_overlay: ColorRect = null
var _sun_time: float = 0.0
var _swamp_fog_overlay: Node2D = null
var _sun_world_pos: Vector2 = Vector2.ZERO
const SUN_CYCLE_SECONDS: float = 300.0  # full east-to-west sweep duration



var _hover_id: int = -1
var _selected_id: int = -1
var _border_bounce_start: float = -1.0  # time the one-shot bounce began
const BORDER_BOUNCE_DURATION: float = 0.7

# Pick mode -- set by CampaignMap when attack/transfer is active
var _pick_mode: int = 0   # 0=none 1=attack 2=transfer
var _pick_source_id: int = -1
var _pick_valid_targets: Array = []  # when non-empty, only highlight these


func set_pick_mode(mode: int, source_id: int, valid_targets: Array = []) -> void:
	_pick_mode = mode
	_pick_source_id = source_id
	_pick_valid_targets = valid_targets
	queue_redraw()

const NODE_RADIUS: float = 9.0
const DRAG_THRESHOLD: float  = 6.0    # px before a click becomes a drag
const PAN_SPEED_FRAC: float  = 0.75   # fraction of visible map width per second
const PAN_SMOOTH: float      = 10.0   # lerp speed for click-to-center
const ZOOM_STEP: float       = 1.15
const CLOSE_ZOOM_FACTOR: float = 5.0  # default zoom = full-fit x this
const MIN_ZOOM_FACTOR: float   = 4.0  # zoom-out floor = full-fit x this
const PAD: float = 60.0

# Background and border palette
const OCEAN_COLOR     := Color(0.04, 0.10, 0.22)
const SHALLOW_COLOR   := Color(0.06, 0.16, 0.34, 0.80)
const LAND_BASE_COLOR := Color(0.26, 0.22, 0.16)
const BORDER_DARK     := Color(0.08, 0.06, 0.04, 0.95)
const BORDER_W_BASE   := 3.0


func init(gs: GameState, md: MapData, human_id: int, voronoi: Dictionary) -> void:
	game_state = gs
	map_data = md
	human_faction_id = human_id
	if voronoi.is_empty() and md != null:
		_build_voronoi(md)
	else:
		_voronoi_cells = voronoi
	_build_continent_poly()
	_build_clipped_cells()
	_init_weather()
	_load_terrain_from_scene_manager()
	_build_terrain_mesh()
	_frame_map()
	queue_redraw()


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	get_viewport().size_changed.connect(_on_viewport_resized)


func _on_viewport_resized() -> void:
	if map_data != null and _map_bounds_rect.size.x > 0:
		_recompute_zoom_bounds()
	_update_weather_overlay_rect()


func _recompute_zoom_bounds() -> void:
	var vp := get_viewport_rect().size
	var full_zoom := _full_fit_zoom(vp)
	_zoom_min = full_zoom * MIN_ZOOM_FACTOR
	_zoom_max = full_zoom * 15.0
	_zoom = clampf(_zoom, _zoom_min, _zoom_max)
	queue_redraw()


func _process(delta: float) -> void:
	var dirty := false
	var camera_moved := false

	# Perf tracking
	var frame_ms: float = delta * 1000.0
	_perf_acc    += delta
	_perf_frames += 1
	_perf_min_ms  = minf(_perf_min_ms, frame_ms)
	_perf_max_ms  = maxf(_perf_max_ms, frame_ms)
	if frame_ms > PERF_SPIKE_MS:
		_perf_slow += 1
	if _perf_acc >= PERF_LOG_INTERVAL:
		var avg_ms: float  = (_perf_acc / _perf_frames) * 1000.0
		var avg_fps: float = _perf_frames / _perf_acc
		DebugLogger.log("perf_summary", {
			"avg_fps": snappedf(avg_fps, 0.1),
			"avg_ms":  snappedf(avg_ms,  0.1),
			"min_ms":  snappedf(_perf_min_ms, 0.1),
			"max_ms":  snappedf(_perf_max_ms, 0.1),
			"spike_frames": _perf_slow,
			"total_frames": _perf_frames,
		})
		_perf_acc = 0.0; _perf_frames = 0; _perf_slow = 0
		_perf_min_ms = 9999.0; _perf_max_ms = 0.0

	# Cloud shadow shader params update — cheap uniform set, no queue_redraw needed
	_update_weather(delta)

	# Momentum fling — coast to stop after drag release
	if not _is_panning and _pan_velocity.length_squared() > 0.0001:
		_origin += _pan_velocity * delta
		_pan_velocity = _pan_velocity.lerp(Vector2.ZERO, minf(PAN_FRICTION * delta, 1.0))
		if _pan_velocity.length_squared() < 0.0001:
			_pan_velocity = Vector2.ZERO
		dirty = true
		camera_moved = true

	# Smooth camera lerp (click-to-center)
	if _cam_lerping:
		var diff := _cam_target - _origin
		if diff.length() < 0.5 / _zoom:
			_origin = _cam_target
			_cam_lerping = false
		else:
			_origin += diff * minf(delta * PAN_SMOOTH, 1.0)
		dirty = true
		camera_moved = true

	# Keyboard pan -- only when no GUI control has focus
	if get_viewport().gui_get_focus_owner() == null:
		var kp := Vector2.ZERO
		if Input.is_key_pressed(KEY_LEFT)  or Input.is_key_pressed(KEY_A): kp.x += 1
		if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D): kp.x -= 1
		if Input.is_key_pressed(KEY_UP)    or Input.is_key_pressed(KEY_W): kp.y += 1
		if Input.is_key_pressed(KEY_DOWN)  or Input.is_key_pressed(KEY_S): kp.y -= 1
		if kp != Vector2.ZERO:
			var vp := get_viewport_rect().size
			var visible_world_w := (vp.x - left_margin) / _zoom
			_origin += kp * visible_world_w * PAN_SPEED_FRAC * delta
			_cam_lerping = false
			dirty = true
			camera_moved = true

	# Selection border bounce — keep redrawing for the duration of the animation
	if _border_bounce_start >= 0.0:
		var elapsed := Time.get_ticks_msec() / 1000.0 - _border_bounce_start
		if elapsed < BORDER_BOUNCE_DURATION:
			dirty = true

	# Sun shadow throttle — province node shadow ellipses update slowly (5s interval)
	if _sun_time - _last_sun_redraw_time >= SUN_SHADOW_REDRAW_INTERVAL:
		_last_sun_redraw_time = _sun_time
		dirty = true

	# Sync overlay cameras when camera moved
	if camera_moved:
		if _swamp_fog_overlay != null:
			_swamp_fog_overlay.set("zoom", _zoom)
			_swamp_fog_overlay.set("origin", _origin)
			_swamp_fog_overlay.queue_redraw()
		if _river_overlay != null:
			_river_overlay.set("zoom", _zoom)
			_river_overlay.set("origin", _origin)
			_river_overlay.queue_redraw()

	if dirty:
		queue_redraw()


func _center_on_province(pid: int) -> void:
	if map_data == null:
		return
	var wp := Vector2.ZERO
	var found := false
	for item in map_data.provinces:
		var p: ProvinceData = item as ProvinceData
		if p != null and int(p.id) == pid:
			wp = p.center
			found = true
			break
	if not found:
		return
	var vp := get_viewport_rect().size
	var sc := Vector2(left_margin + (vp.x - left_margin) * 0.5, vp.y * 0.5)
	_cam_target = sc / _zoom - wp
	_cam_lerping = true


# --------------------------------------------------
# Voronoi generation (used when debug view is not present)
# --------------------------------------------------
func _build_voronoi(data: MapData) -> void:
	_voronoi_cells.clear()
	if data == null or data.provinces.is_empty():
		return
	var bounds: Rect2 = _map_bounds(data)
	for item_a in data.provinces:
		var a: ProvinceData = item_a as ProvinceData
		var poly: Array = [
			bounds.position,
			bounds.position + Vector2(bounds.size.x, 0.0),
			bounds.position + bounds.size,
			bounds.position + Vector2(0.0, bounds.size.y)
		]
		for item_b in data.provinces:
			var b: ProvinceData = item_b as ProvinceData
			if a == b:
				continue
			poly = _clip_half_plane(poly, a.center, b.center)
			if poly.size() < 3:
				break
		_voronoi_cells[int(a.id)] = poly


func _grid_key(pos: Vector2, grid: float) -> String:
	return "%d_%d" % [int(round(pos.x / grid)), int(round(pos.y / grid))]


func _precompute_desert_cells(bounds: Rect2, grid: float) -> Dictionary:
	var cells: Dictionary = {}
	var x := bounds.position.x - grid
	while x <= bounds.position.x + bounds.size.x + grid:
		var y := bounds.position.y - grid
		while y <= bounds.position.y + bounds.size.y + grid:
			if _biome_at_pos(Vector2(x, y)) in ["desert", "mountain"]:
				cells[_grid_key(Vector2(x, y), grid)] = true
			y += grid
		x += grid
	return cells


func _biome_at_pos(pos: Vector2) -> String:
	var best_biome := ""
	var best_dist := 1.0e18
	for item in map_data.provinces:
		var p: ProvinceData = item as ProvinceData
		var d := pos.distance_squared_to(p.center)
		if d < best_dist:
			best_dist = d
			best_biome = p.biome
	return best_biome


func _map_bounds(data: MapData) -> Rect2:
	var minx: float = 1.0e18; var miny: float = 1.0e18
	var maxx: float = -1.0e18; var maxy: float = -1.0e18
	for item in data.provinces:
		var p: ProvinceData = item as ProvinceData
		minx = minf(minx, p.center.x); miny = minf(miny, p.center.y)
		maxx = maxf(maxx, p.center.x); maxy = maxf(maxy, p.center.y)
	if maxx < minx or maxy < miny:
		return Rect2(Vector2.ZERO, Vector2.ONE)
	return Rect2(Vector2(minx, miny), Vector2(maxx - minx, maxy - miny))


func _clip_half_plane(poly: Array, a: Vector2, b: Vector2) -> Array:
	var out: Array = []
	var mid: Vector2 = (a + b) * 0.5
	var normal: Vector2 = (b - a).normalized()
	var prev: Vector2 = poly[poly.size() - 1]
	var prev_in: bool = (prev - mid).dot(normal) <= 0.0
	for curr in poly:
		var curr_v: Vector2 = curr
		var curr_in: bool = (curr_v - mid).dot(normal) <= 0.0
		if curr_in != prev_in:
			var dir: Vector2 = curr_v - prev
			var denom: float = dir.dot(normal)
			if absf(denom) > 0.000001:
				var t: float = ((mid - prev).dot(normal)) / denom
				out.append(prev + dir * t)
		if curr_in:
			out.append(curr_v)
		prev = curr_v
		prev_in = curr_in
	return out


func _build_continent_poly() -> void:
	_continent_poly = PackedVector2Array()
	_island_polys.clear()
	if map_data == null or map_data.provinces.is_empty():
		return
	var bounds := _map_bounds(map_data)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return

	# Deterministic seed from province positions
	var h: int = map_data.provinces.size()
	for item in map_data.provinces:
		var p := item as ProvinceData
		if p != null:
			h = h * 31 ^ (int(p.center.x * 37.0) + int(p.center.y * 13.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(h)

	var cx := bounds.position.x + bounds.size.x * 0.5
	var cy := bounds.position.y + bounds.size.y * 0.5
	# Ellipse at 45? reaches only 1/sqrt2 of the corner distance, so we need
	# expansion x min_r >= sqrt2 to safely contain every province center.
	# 1.55 x 0.95 = 1.47 > 1.414 -- safe for any aspect ratio.
	var rx := bounds.size.x * 0.5 * 1.55
	var ry := bounds.size.y * 0.5 * 1.55

	# Pre-generate phase offsets (10 waves)
	var ph: Array = []
	for i in 10:
		ph.append(rng.randf() * TAU)

	# More points + higher-frequency waves + per-vertex jitter = jagged coast
	const N := 140
	for i in N:
		var angle := float(i) / N * TAU
		var r := 1.0
		# Low frequency -- major peninsulas and gulfs
		r += 0.13 * sin(angle * 2.0 + ph[0])
		r += 0.10 * sin(angle * 3.0 + ph[1])
		# Medium frequency -- coves and headlands
		r += 0.07 * sin(angle * 5.0 + ph[2])
		r += 0.05 * sin(angle * 7.0 + ph[3])
		# High frequency -- jagged cliffs and inlets
		r += 0.04 * sin(angle * 11.0 + ph[4])
		r += 0.03 * sin(angle * 17.0 + ph[5])
		r += 0.025 * sin(angle * 23.0 + ph[6])
		# Per-vertex noise for truly irregular edges
		r += rng.randf_range(-0.04, 0.04)
		# Clamp: min 0.95 x 1.55 = 1.47 > sqrt2, all bbox corners stay inland
		r = maxf(r, 0.95)
		_continent_poly.append(Vector2(cx + cos(angle) * rx * r, cy + sin(angle) * ry * r))

	# Scatter small islands in the ocean
	var num_islands := rng.randi_range(4, 7)
	var attempts := 0
	while _island_polys.size() < num_islands and attempts < 80:
		attempts += 1
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(1.65, 2.30)
		var ic := Vector2(cx + cos(angle) * rx * dist, cy + sin(angle) * ry * dist)
		if Geometry2D.is_point_in_polygon(ic, _continent_poly):
			continue
		# Random small noisy ellipse
		var iph: Array = []
		for j in 4:
			iph.append(rng.randf() * TAU)
		var irx := rng.randf_range(rx * 0.04, rx * 0.11)
		var iry := rng.randf_range(ry * 0.03, ry * 0.09)
		var n_pts := rng.randi_range(7, 12)
		var poly := PackedVector2Array()
		for j in n_pts:
			var a := float(j) / n_pts * TAU
			var ir := 1.0
			ir += 0.28 * sin(a * 2.0 + iph[0])
			ir += 0.18 * sin(a * 3.0 + iph[1])
			ir += 0.12 * sin(a * 5.0 + iph[2])
			ir += rng.randf_range(-0.12, 0.12)
			ir = maxf(ir, 0.25)
			poly.append(Vector2(ic.x + cos(a) * irx * ir, ic.y + sin(a) * iry * ir))
		_island_polys.append(poly)


func _build_clipped_cells() -> void:
	_clipped_cells.clear()
	if _continent_poly.size() < 3:
		# No continent shape yet -- copy originals as fallback
		for pid in _voronoi_cells.keys():
			var raw: Array = _voronoi_cells[pid]
			var pv := PackedVector2Array()
			for v in raw:
				pv.append(v as Vector2)
			_clipped_cells[pid] = pv
		return

	for pid in _voronoi_cells.keys():
		var raw: Array = _voronoi_cells[pid]
		if raw.size() < 3:
			continue
		var cell := PackedVector2Array()
		for v in raw:
			cell.append(v as Vector2)
		var results := Geometry2D.intersect_polygons(cell, _continent_poly)
		if results.is_empty():
			_clipped_cells[pid] = cell  # interior province -- keep as-is
		else:
			# Take the largest result polygon (handles rare split cases)
			var best: PackedVector2Array = results[0]
			for r in results:
				if (r as PackedVector2Array).size() > best.size():
					best = r
			_clipped_cells[pid] = best


func refresh() -> void:
	queue_redraw()


# --------------------------------------------------
# Input
# --------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if game_state == null or map_data == null:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_left_held = true
					_press_pos = mb.position
					_is_panning = false
					_pan_velocity = Vector2.ZERO
				else:
					if _is_panning:
						_is_panning = false
						# Compute fling velocity from recent samples
						if not _velocity_samples.is_empty():
							var total_delta := Vector2.ZERO
							var total_dt := 0.0
							for s in _velocity_samples:
								total_delta += s[0]
								total_dt    += s[1]
							if total_dt > 0.0:
								_pan_velocity = total_delta / total_dt
						_velocity_samples.clear()
					elif mb.position.distance_to(_press_pos) < DRAG_THRESHOLD:
						# Clean click -- select province and smooth-pan to it
						var pid: int = _pick_province(mb.position)
						if pid >= 0:
							_selected_id = pid
							_border_bounce_start = Time.get_ticks_msec() / 1000.0
							province_clicked.emit(pid)
							_center_on_province(pid)
							queue_redraw()
					_left_held = false
			MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
				_is_panning = mb.pressed
				if not mb.pressed:
					_pan_velocity = Vector2.ZERO
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(mb.position, ZOOM_STEP)
				_cam_lerping = false
				_pan_velocity = Vector2.ZERO
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(mb.position, 1.0 / ZOOM_STEP)
				_cam_lerping = false
				_pan_velocity = Vector2.ZERO

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		# Start left-drag pan once past threshold
		if _left_held and not _is_panning:
			if mm.global_position.distance_to(_press_pos) >= DRAG_THRESHOLD:
				_is_panning = true
				_cam_lerping = false
				_pan_velocity = Vector2.ZERO
				_velocity_samples.clear()
		if _is_panning:
			var world_delta := mm.relative / _zoom
			_origin += world_delta
			# Track recent velocity samples for fling
			var dt: float = get_process_delta_time()
			if dt > 0.0:
				_velocity_samples.append([world_delta, dt])
				if _velocity_samples.size() > PAN_FLING_FRAMES:
					_velocity_samples.pop_front()
			queue_redraw()
		var new_hover: int = _pick_province(mm.position)
		if new_hover != _hover_id:
			_hover_id = new_hover
			province_hovered.emit(_hover_id)
			queue_redraw()


# --------------------------------------------------
# Drawing
# --------------------------------------------------
func _draw() -> void:
	if map_data == null:
		return
	_draw_background()
	_draw_cells()
	_draw_grass_overlays()
	_draw_swamp_pits()
	_draw_desert_ground()
	_draw_tundra_ground()
	_draw_rivers()
	_draw_cell_borders()
	_draw_routes()
	_draw_trees()
	_draw_nodes()
	_draw_labels()
	_draw_order_indicators()


func _draw_background() -> void:
	var vp := get_viewport_rect()
	draw_rect(Rect2(Vector2.ZERO, vp.size), OCEAN_COLOR)

	if _continent_poly.size() < 3:
		return

	# Build screen-space continent polygon
	var screen_poly := PackedVector2Array()
	for pt in _continent_poly:
		screen_poly.append(_to_screen(pt))

	# Shallow water fringe around continent
	var centroid := Vector2.ZERO
	for pt in screen_poly:
		centroid += pt
	centroid /= screen_poly.size()
	var shallow_poly := PackedVector2Array()
	for pt in screen_poly:
		shallow_poly.append(centroid + (pt - centroid) * 1.06)
	draw_colored_polygon(shallow_poly, SHALLOW_COLOR)

	# Terrain -- one draw_mesh call instead of N draw_polygon calls
	var xform := Transform2D(Vector2(_zoom, 0.0), Vector2(0.0, _zoom), _origin * _zoom)
	if _terrain_mesh != null and _grass_atlas_tex != null:
		draw_mesh(_terrain_mesh, _grass_atlas_tex, xform)
	else:
		draw_colored_polygon(screen_poly, LAND_BASE_COLOR)


	# Small islands -- same shallow fringe, same tile approach
	for island in _island_polys:
		var sc_i := PackedVector2Array()
		for pt in (island as PackedVector2Array):
			sc_i.append(_to_screen(pt))
		if sc_i.size() < 3:
			continue
		var ic := Vector2.ZERO
		for pt in sc_i:
			ic += pt
		ic /= sc_i.size()
		var shallow_i := PackedVector2Array()
		for pt in sc_i:
			shallow_i.append(ic + (pt - ic) * 1.10)
		draw_colored_polygon(shallow_i, SHALLOW_COLOR)
		draw_colored_polygon(sc_i, LAND_BASE_COLOR)


func _draw_cell_borders() -> void:
	# One-shot bounce: sin arch over BORDER_BOUNCE_DURATION seconds, then settle at base width.
	var now: float = Time.get_ticks_msec() / 1000.0
	var elapsed: float = now - _border_bounce_start
	var bounce: float
	if _border_bounce_start >= 0.0 and elapsed < BORDER_BOUNCE_DURATION:
		bounce = 7.0 + sin(elapsed / BORDER_BOUNCE_DURATION * PI) * 8.0
	else:
		bounce = 7.0

	for item in map_data.provinces:
		var p: ProvinceData = item as ProvinceData
		var pid: int = int(p.id)
		if not _clipped_cells.has(pid):
			continue
		var world_pts: PackedVector2Array = _clipped_cells[pid]
		if world_pts.size() < 3:
			continue
		var pts: PackedVector2Array = PackedVector2Array()
		for v in world_pts:
			pts.append(_to_screen(v))
		var is_selected: bool = pid == _selected_id
		var is_hover: bool    = pid == _hover_id
		if is_selected:
			var owner_id: int = int(p.owner_id)
			# Neon: max saturation + brightness on faction hue; gray for neutral.
			var neon_c: Color
			if owner_id < 0:
				neon_c = Color(0.6, 0.6, 0.6, 0.5)
			else:
				var base_c: Color = _faction_color(owner_id)
				neon_c = Color.from_hsv(base_c.h, 1.0, 1.0, 0.5)
			# Close the polygon by appending the first point.
			var closed_pts := pts.duplicate()
			if closed_pts.size() > 0:
				closed_pts.append(closed_pts[0])
			draw_polyline(closed_pts, neon_c, bounce, true)
		if _pick_mode != 0:
			var owner_id: int = int(p.owner_id)
			var is_human: bool = owner_id == human_faction_id
			var is_neutral: bool = owner_id < 0
			if pid == _pick_source_id:
				draw_polyline(pts, Color(1.0, 0.90, 0.20, 1.0), 3.5, true)
			elif _pick_mode == 1:
				var is_valid_target: bool = _pick_valid_targets.is_empty() or _pick_valid_targets.has(pid)
				if is_valid_target and not is_human and not is_neutral:
					draw_polyline(pts, Color(1.0, 0.30, 0.25, 0.90), 2.5, true)
				elif is_valid_target and is_neutral:
					draw_polyline(pts, Color(1.0, 0.60, 0.20, 0.85), 2.5, true)
			elif _pick_mode == 2 and is_human and pid != _pick_source_id:
				draw_polyline(pts, Color(0.35, 0.70, 1.0, 0.90), 2.5, true)


func _draw_grass_overlays() -> void:
	if _continent_poly.size() < 3:
		return
	var screen_poly := PackedVector2Array()
	for pt in _continent_poly:
		screen_poly.append(_to_screen(pt))
	var xform := Transform2D(Vector2(_zoom, 0.0), Vector2(0.0, _zoom), _origin * _zoom)

	if _grass_overlay_tex != null:
		var tex_sz := _grass_overlay_tex.get_size()
		var uvs := PackedVector2Array()
		for pt in _continent_poly:
			uvs.append(pt / tex_sz)
		draw_polygon(screen_poly, PackedColorArray(), uvs, _grass_overlay_tex)

	if _light_mesh != null and _light_atlas_tex != null:
		draw_mesh(_light_mesh, _light_atlas_tex, xform, Color(1, 1, 1, 0.15))

	if _dark_mesh != null and _dark_atlas_tex != null:
		draw_mesh(_dark_mesh, _dark_atlas_tex, xform, Color(1, 1, 1, 0.15))


func _load_terrain_from_scene_manager() -> void:
	_grass_atlas_tex = null
	_terrain_tile_data = []
	_light_atlas_tex = null
	_light_tile_data = []
	var terrain: MapTerrainGenerator = SceneManager.pending_terrain
	if terrain == null:
		# Editor / direct-launch fallback -- generate synchronously now
		terrain = MapTerrainGenerator.new()
		terrain.generate_from_map(map_data)
	_grass_atlas_tex = terrain.atlas
	_terrain_tile_data = terrain.tile_data
	_light_atlas_tex = terrain.light_atlas
	_light_tile_data = terrain.light_tile_data
	_dark_atlas_tex = terrain.dark_atlas
	_dark_tile_data = terrain.dark_tile_data
	_tree_textures = terrain.tree_textures
	_tree_positions = terrain.tree_positions
	_dead_tree_start_idx = terrain.dead_tree_start_idx
	_tundra_tree_start_idx = terrain.tundra_tree_start_idx
	_filter_coast_trees()
	_swamp_atlas_tex = terrain.swamp_atlas
	_swamp_tile_data = terrain.swamp_tile_data
	_swamp_ie_tex    = terrain.swamp_ie_atlas
	_swamp_ie_data   = terrain.swamp_ie_data
	_desert_atlas_tex = terrain.desert_atlas
	_desert_tile_data = terrain.desert_tile_data
	_tundra_atlas_tex = terrain.tundra_atlas
	_tundra_tile_data = terrain.tundra_tile_data
	_build_biome_meshes()
	_init_swamp_fog()
	_grass_overlay_tex = load("res://Art/map/terrain/grass.png") as Texture2D
	_province_lvl1_tex = load("res://Art/map/terrain/province_lvl1.png") as Texture2D
	_province_lvl2_tex = load("res://Art/map/terrain/province_lvl2.png") as Texture2D
	_province_biome_textures = {
		"plains":   _load_biome_texs("plains",   ["plainsprovince3", "plainsprovince4"]),
		"forest":   _load_biome_texs("forest",   ["forestprovince1"]),
		"mountain": _load_biome_texs("mountain", ["mountainprovince1", "mountainprovince2", "mountainprovince3", "mountainprovince4"]),
		"desert":   _load_biome_texs("desert",   ["desertprovince1", "desertprovince2", "desertprovince3", "desertprovince4"]),
		"tundra":   _load_biome_texs("tundra",   ["tundraprovince1", "tundraprovince2", "tundraprovince3", "tundraprovince4"]),
		"swamp":    _load_biome_texs("swamp",    ["swampprovince1", "swampprovince2", "swampprovince3", "swampprovince4"]),
		"coast":    _load_biome_texs("coast",    ["coastalprovince1", "coastalprovince2", "coastalprovince3", "coastalprovince4"]),
	}
	_road_straight_textures.clear()
	_road_curve_textures.clear()
	for i in 4:
		var st := load("res://Art/map/terrain/road_straight_%d.png" % i) as Texture2D
		if st:
			_road_straight_textures.append(st)
		var cv := load("res://Art/map/terrain/road_curve_%d.png" % i) as Texture2D
		if cv:
			_road_curve_textures.append(cv)
	_build_route_paths()
	_load_river_tiles()
	_build_river_path()
	_filter_river_trees()
	_scatter_river_trees()
	_build_tree_meshes()


func _load_biome_texs(biome: String, names: Array) -> Array:
	var arr: Array = []
	for n in names:
		var t := load("res://Art/map/terrain/%s.png" % n) as Texture2D
		if t:
			arr.append(t)
	return arr


func _build_route_paths() -> void:
	_route_paths.clear()
	if map_data == null:
		return
	for r in map_data.routes:
		var a: ProvinceData = map_data.provinces[int(r.a)] as ProvinceData
		var b: ProvinceData = map_data.provinces[int(r.b)] as ProvinceData
		var pa: Vector2 = a.center
		var pb: Vector2 = b.center

		var seed_val: int = absi(int(r.a) * 2654435761 ^ int(r.b) * 2246822519)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_val

		var diff: Vector2 = pb - pa
		var length: float = diff.length()
		var perp: Vector2 = Vector2(-diff.y, diff.x).normalized()
		# Build as rigid straight runs -- random length segments with sharp corrections
		var curve_pts: Array = [pa]
		var pos: Vector2 = pa
		# Max drift off the direct line before correction kicks in harder
		var max_drift: float = clampf(length * 0.12, 5.0, 25.0)

		while pos.distance_to(pb) > 8.0:
			var to_dest: Vector2 = pb - pos
			var dist_left: float = to_dest.length()

			# Random straight run length -- 8 to 22 world units
			var run_len: float = rng.randf_range(8.0, 22.0)
			run_len = minf(run_len, dist_left)

			# Base direction toward destination, with a perpendicular drift
			var base_dir: Vector2 = to_dest.normalized()
			var drift: float = rng.randf_range(-max_drift, max_drift)
			# Pull drift back toward center line as we get closer to destination
			var pull: float = clampf(1.0 - dist_left / length, 0.0, 1.0)
			drift *= (1.0 - pull * 0.85)

			var end_pos: Vector2 = pos + base_dir * run_len + perp * drift
			# Clamp so we don't overshoot too wildly
			end_pos = pos.lerp(pb, clampf(run_len / dist_left, 0.0, 1.0)) + perp * drift

			curve_pts.append(end_pos)
			pos = end_pos

		curve_pts.append(pb)

		var style_idx: int = seed_val % max(_road_straight_textures.size(), 1)
		_route_paths.append({ "pts": curve_pts, "style": style_idx })

func _load_river_tiles() -> void:
	_river_tiles.clear()
	for i in range(1, 8):
		var t := load("res://Art/map/terrain/river_tiles/River_%04d.png" % i) as Texture2D
		_river_tiles.append(t)
	# Index 7: T-junction, tributary enters from east
	_river_tiles.append(load("res://Art/map/terrain/river_tiles/River_000Teast8.png") as Texture2D)
	# Index 8: T-junction, tributary enters from west
	_river_tiles.append(load("res://Art/map/terrain/river_tiles/River_000Twest17.png") as Texture2D)
	_river_parallax_tex = load("res://Art/map/terrain/sky_parallax.png") as Texture2D
	# Set up overlay node with shader
	if _river_overlay == null:
		_river_overlay = load("res://Visual/campaign/RiverOverlay.gd").new()
		var mat := ShaderMaterial.new()
		mat.shader = load("res://Visual/campaign/RiverParallax.gdshader") as Shader
		# scroll_speed default is already set in shader; texture is passed per draw_mesh call
		_river_overlay.material = mat
		add_child(_river_overlay)
	_river_overlay.set("parallax_tex", _river_parallax_tex)


func _build_river_path() -> void:
	_river_path_tiles.clear()
	_river_branch_paths.clear()
	_river_grid_path.clear()
	if map_data == null:
		return
	var bounds := _map_bounds(map_data)
	if bounds.size.x <= 0:
		return

	var grid := RIVER_TILE_WORLD
	var rng := RandomNumberGenerator.new()
	var h: int = map_data.provinces.size() * 7919
	for item in map_data.provinces:
		var p := item as ProvinceData
		if p != null:
			h = h * 31 ^ (int(p.center.x * 7.0) + int(p.center.y * 13.0))
	rng.seed = absi(h)

	# --- Main river: headwater (upper-center) → south coast ---
	var cx := bounds.position.x + bounds.size.x * 0.5
	var headwater := Vector2(
		round(cx / grid) * grid,
		round((bounds.position.y + bounds.size.y * 0.15) / grid) * grid)

	# South terminus: 85% of the way from headwater to the continent's southern edge,
	# so the river ends well inside the landmass rather than poking into the ocean.
	var south_pt := headwater
	for pt in _continent_poly:
		if (pt as Vector2).y > south_pt.y:
			south_pt = pt
	var end_y: float = round(
		lerp(headwater.y, south_pt.y, 0.85) / grid) * grid

	# Pre-compute desert cells before any pathfinding
	var desert_cells: Dictionary = _precompute_desert_cells(bounds, grid)
	DebugLogger.log("river_build_start", {
		"headwater": str(headwater), "end_y": end_y,
		"blocked_cell_count": desert_cells.size(),
		"bounds": str(bounds)})

	var junction_fracs: Array = [0.25, 0.5, 0.75]
	var junction_indices: Array = []
	_river_grid_path = _build_branch(headwater, end_y, rng, bounds, grid, desert_cells, junction_fracs, junction_indices)
	DebugLogger.log("river_main_path", {
		"path_size": _river_grid_path.size(),
		"junction_indices": junction_indices})
	_add_tiles_from_path(_river_grid_path, true)

	# --- Tributaries: branch from junction outward NE or NW toward boundary ---
	# Build occupied set: all main river positions + junction points
	var occupied: Dictionary = {}
	for pt in _river_grid_path:
		var key := Vector2(round((pt as Vector2).x / grid), round((pt as Vector2).y / grid))
		occupied[key] = true

	var num_tribs := 3
	if junction_indices.size() < num_tribs:
		push_warning("PlayerMap: not enough junction_indices (%d), skipping tributaries" % junction_indices.size())
		return
	for t in num_tribs:
		var join_idx: int = junction_indices[t]
		var side := 1.0 if t % 2 == 0 else -1.0
		var outward := Vector2.RIGHT if side > 0 else Vector2.LEFT
		# Validate junction: need at least 2 clear outward steps.
		# Search nearby river points; if none work, flip to the opposite side.
		var path_len: int = _river_grid_path.size()
		var search_radius: int = maxi(1, path_len / 4)

		var _junction_has_clearance := func(idx: int, dir: Vector2) -> bool:
			var p: Vector2 = _river_grid_path[idx]
			for step in [1, 2, 3, 4]:
				var sp: Vector2 = p + dir * grid * step
				if desert_cells.has(_grid_key(sp, grid)):
					return false
				if occupied.has(Vector2(round(sp.x / grid), round(sp.y / grid))):
					return false
			return true

		var found_valid := false
		for delta in range(0, search_radius):
			for offset in ([0, delta, -delta] if delta > 0 else [0]):
				var ci: int = clampi(join_idx + offset, 1, path_len - 2)
				if _junction_has_clearance.call(ci, outward):
					join_idx = ci
					found_valid = true
					break
			if found_valid:
				break
		# If still no clearance, try flipping to the opposite side
		if not found_valid:
			var flipped := -outward
			for delta in range(0, search_radius):
				for offset in ([0, delta, -delta] if delta > 0 else [0]):
					var ci: int = clampi(join_idx + offset, 1, path_len - 2)
					if _junction_has_clearance.call(ci, flipped):
						join_idx = ci
						outward = flipped
						side = -side
						found_valid = true
						break
				if found_valid:
					break

		var join_pt: Vector2 = _river_grid_path[join_idx]
		DebugLogger.log("river_tributary_junction", {
			"trib": t, "join_idx": join_idx, "join_pt": str(join_pt),
			"outward": str(outward), "found_valid": found_valid})
		var raw: Array = _build_tributary_meander(join_pt, outward, grid, rng, bounds, occupied, desert_cells)
		DebugLogger.log("river_tributary_result", {"trib": t, "raw_size": raw.size()})
		# If trib is too short, flip to the opposite side and rebuild
		if raw.size() <= 20:  # flip if fewer than 20 steps
			var flipped_out := -outward
			var flipped_side := -side
			var raw_flip: Array = _build_tributary_meander(join_pt, flipped_out, grid, rng, bounds, occupied, desert_cells)
			DebugLogger.log("river_tributary_flip", {
				"trib": t, "original_size": raw.size(), "flipped_size": raw_flip.size()})
			if raw_flip.size() > raw.size():
				raw = raw_flip
				outward = flipped_out
				side = flipped_side
		if raw.size() < 2:
			DebugLogger.log("river_tributary_skipped", {"trib": t, "reason": "raw_size < 2"})
			continue
		var trib_slice: Array = raw.slice(0, raw.size() - 1)
		_add_tiles_from_path(trib_slice, false, {}, 1, true)
		var t_tile_idx := 7 if side > 0 else 8
		_replace_tile_at_pos(join_pt, t_tile_idx)
		# Add this tributary's positions to occupied so later ones don't cross it
		for pt in raw:
			var key := Vector2(round((pt as Vector2).x / grid), round((pt as Vector2).y / grid))
			occupied[key] = true
		_river_branch_paths.append(raw)

	# Cache smoothed paths once so _draw never re-runs Chaikin
	_river_smooth_main = _chaikin_smooth(_river_grid_path, 3)
	_river_smooth_branches.clear()
	for branch in _river_branch_paths:
		_river_smooth_branches.append(_chaikin_smooth(branch, 3))
	DebugLogger.log("river_smooth_cached", {
		"parallax_tex_loaded": _river_parallax_tex != null,
		"smooth_main_size": _river_smooth_main.size(),
		"smooth_branch_count": _river_smooth_branches.size(),
	})

	# Build world-space river strip meshes — drawn by RiverOverlay with TIME shader
	var tex_sz := Vector2(512.0, 512.0)
	if _river_parallax_tex != null:
		tex_sz = _river_parallax_tex.get_size()
	_river_main_strip_mesh = _build_river_strip_mesh(_river_smooth_main, tex_sz, false)
	_river_trib_strip_meshes.clear()
	_river_trib_bank_data.clear()
	for branch_smooth in _river_smooth_branches:
		_river_trib_strip_meshes.append(_build_river_strip_mesh(branch_smooth, tex_sz, true))
		_river_trib_bank_data.append(_build_river_bank_data(branch_smooth))
	if _river_overlay != null:
		_river_overlay.set("strip_main",  _river_main_strip_mesh)
		_river_overlay.set("strip_tribs", _river_trib_strip_meshes)
		_river_overlay.set("zoom",   _zoom)
		_river_overlay.set("origin", _origin)
		_river_overlay.queue_redraw()


func _chaikin_smooth(path: Array, passes: int) -> Array:
	var smooth: Array = path.duplicate()
	for _p in passes:
		var s2: Array = [smooth[0]]
		for i in range(smooth.size() - 1):
			var a: Vector2 = smooth[i]; var b: Vector2 = smooth[i + 1]
			s2.append(a.lerp(b, 0.25)); s2.append(a.lerp(b, 0.75))
		s2.append(smooth[smooth.size() - 1])
		smooth = s2
	return smooth


func _build_branch(start: Vector2, end_y: float, rng: RandomNumberGenerator,
		bounds: Rect2, grid: float, desert_cells: Dictionary = {},
		junction_fracs: Array = [], junction_indices: Array = []) -> Array:

	# --- A* pathfinding ---
	# Costs: DOWN cheap, lateral moderate, UP expensive.
	# Small per-seed noise on lateral costs gives natural variety without loops.
	const COST_DOWN    := 1.0
	const COST_UP      := 12.0
	var   cost_lateral := 2.5 + rng.randf() * 1.5   # 2.5–4.0, varies per seed

	# open_set entries: [f, g, pos]  — sorted by f (lowest first)
	var open_set: Array  = []
	var g_score: Dictionary = {}   # grid_key -> float
	var came_from: Dictionary = {} # grid_key -> Vector2
	var closed: Dictionary  = {}

	var sk := _grid_key(start, grid)
	g_score[sk] = 0.0
	open_set.append([maxf(0.0, end_y - start.y) / grid, 0.0, start])

	var goal := start
	var found := false

	while not open_set.is_empty():
		# Pop lowest-f entry (linear scan is fine — grid is ~50×50 at most)
		var bi := 0
		for idx in range(1, open_set.size()):
			if (open_set[idx] as Array)[0] < (open_set[bi] as Array)[0]:
				bi = idx
		var entry: Array = open_set[bi]
		open_set.remove_at(bi)

		var cur: Vector2 = entry[2]
		var ck := _grid_key(cur, grid)
		if closed.has(ck):
			continue
		closed[ck] = true

		if cur.y >= end_y:
			goal = cur
			found = true
			break

		var neighbors: Array = [
			[Vector2.DOWN,  COST_DOWN],
			[Vector2.LEFT,  cost_lateral],
			[Vector2.RIGHT, cost_lateral],
			[Vector2.UP,    COST_UP],
		]
		for nb in neighbors:
			var dir: Vector2 = nb[0]
			var cost: float  = nb[1]
			var np: Vector2  = cur + dir * grid
			var nk := _grid_key(np, grid)
			if closed.has(nk) or desert_cells.has(nk):
				continue
			# Must stay inside the continent polygon
			if _continent_poly.size() >= 3 and not Geometry2D.is_point_in_polygon(np, _continent_poly):
				continue
			# Keep within map bounds
			if np.x < bounds.position.x - grid or np.x > bounds.position.x + bounds.size.x + grid:
				continue
			var ng: float = g_score[ck] + cost
			if not g_score.has(nk) or ng < g_score[nk]:
				g_score[nk] = ng
				came_from[nk] = cur
				var h: float = maxf(0.0, end_y - np.y) / grid
				open_set.append([ng + h, ng, np])

	# Reconstruct path from came_from chain
	var path: Array = []
	if found:
		var pos := goal
		while came_from.has(_grid_key(pos, grid)):
			path.push_front(pos)
			pos = came_from[_grid_key(pos, grid)]
		path.push_front(pos)
	else:
		DebugLogger.log("river_astar_no_route", {"start": str(start), "end_y": end_y})
		path = [start]  # fallback — no route found

	# --- Junction selection (by path-index fraction, evenly spaced) ---
	if path.size() < 6 or junction_fracs.is_empty():
		return path
	var min_sep: int = maxi(3, path.size() / 8)
	var path_max: int = path.size() - 3  # guaranteed >= 3 since path.size() >= 6
	for frac in junction_fracs:
		var target_idx: int = clampi(int(path.size() * frac), 2, path_max)
		var best_idx: int = -1
		var search_w: int = maxi(1, mini(mini(target_idx - 2, path_max - target_idx), path.size() / 6))
		for delta in range(0, search_w + 1):
			for offset in ([0, delta, -delta] if delta > 0 else [0]):
				var ci2: int = clampi(target_idx + offset, 2, path_max)
				var too_close := false
				for prev in junction_indices:
					if absi(ci2 - prev) < min_sep:
						too_close = true
						break
				if too_close:
					continue
				var px: float = (path[ci2 - 1] as Vector2).x
				var cx2: float = (path[ci2] as Vector2).x
				var nx: float = (path[ci2 + 1] as Vector2).x
				if absf(px - cx2) < 1.0 and absf(nx - cx2) < 1.0:
					best_idx = ci2
					break
			if best_idx >= 0:
				break
		if best_idx < 0:
			best_idx = target_idx
			for prev in junction_indices:
				if absi(best_idx - prev) < min_sep:
					best_idx = clampi(prev + min_sep, 2, path_max)
		junction_indices.append(best_idx)
	return path


func _build_tributary(start: Vector2, join: Vector2, grid: float,
		rng: RandomNumberGenerator, _bounds: Rect2) -> Array:
	var path: Array = [start]
	var cur := start
	var h_streak := 0
	var safety := 0
	while safety < 30:
		safety += 1
		var dx := join.x - cur.x
		var dy := join.y - cur.y
		# Snap if close enough
		if absf(dx) < grid * 0.1 and absf(dy) < grid * 0.1:
			break
		var choices: Array = []
		# Horizontal: move toward junction x
		if absf(dx) >= grid * 0.9 and h_streak < 3:
			var h_dir := Vector2.RIGHT if dx > 0 else Vector2.LEFT
			choices.append(h_dir)
			if rng.randf() < 0.5:
				choices.append(h_dir)  # slight bias
		# Vertical: move down toward junction y
		if dy >= grid * 0.9:
			choices.append(Vector2.DOWN)
			choices.append(Vector2.DOWN)
		if choices.is_empty():
			break
		var next_dir: Vector2 = choices[rng.randi() % choices.size()]
		h_streak = h_streak + 1 if next_dir.x != 0 else 0
		cur += next_dir * grid
		path.append(cur)
	# Force exact junction endpoint
	if path.is_empty() or (path[path.size()-1] as Vector2).distance_to(join) > grid * 0.1:
		path.append(join)
	return path


func _build_tributary_meander(junction: Vector2, outward: Vector2, grid: float,
		rng: RandomNumberGenerator, bounds: Rect2, occupied: Dictionary = {}, desert_cells: Dictionary = {}) -> Array:
	var first_step := junction + outward * grid
	var path: Array = [junction, first_step]
	var cur := first_step
	var last_dir := outward
	for _s in 35:
		# outward 3x, UP 2x, DOWN 1x — all always in pool so trib can navigate around any obstacle
		var all_dirs: Array = [outward, outward, outward, Vector2.UP, Vector2.UP, Vector2.DOWN]
		var candidates: Array = []
		for dir in all_dirs:
			if dir == -last_dir:
				continue
			var np: Vector2 = cur + (dir as Vector2) * grid
			if occupied.has(Vector2(round(np.x / grid), round(np.y / grid))):
				continue
			if not Geometry2D.is_point_in_polygon(np, _continent_poly):
				continue
			if desert_cells.has(_grid_key(np, grid)):
				continue
			candidates.append(dir)
		if candidates.is_empty():
			break
		var next_dir: Vector2 = candidates[rng.randi() % candidates.size()]
		cur += next_dir * grid
		path.append(cur)
		last_dir = next_dir
	return path


func _replace_tile_at_pos(pos: Vector2, tile_idx: int, is_main: bool = false) -> void:
	for i in _river_path_tiles.size():
		var entry := _river_path_tiles[i] as Dictionary
		if (entry["pos"] as Vector2).distance_to(pos) < 1.0:
			_river_path_tiles[i] = {"pos": pos, "tile": tile_idx, "main": entry.get("main", is_main)}
			return
	_river_path_tiles.append({"pos": pos, "tile": tile_idx, "main": is_main})


func _add_tiles_from_path(path: Array, is_main: bool = false, forced_tiles: Dictionary = {}, skip_first: int = 0, taper: bool = false) -> void:
	for i in path.size():
		var from_dir := Vector2.ZERO
		var to_dir := Vector2.ZERO
		if i > 0:
			from_dir = (path[i] - path[i - 1]).normalized()
		if i < path.size() - 1:
			to_dir = (path[i + 1] - path[i]).normalized()
		if i < skip_first:
			continue
		var tile_idx: int = forced_tiles[i] if forced_tiles.has(i) else _select_river_tile(from_dir, to_dir)
		var entry := {"pos": path[i], "tile": tile_idx, "main": is_main}
		if taper:
			entry["taper_step"] = i - skip_first
		_river_path_tiles.append(entry)


func _select_river_tile(from_dir: Vector2, to_dir: Vector2) -> int:
	if from_dir == Vector2.ZERO: from_dir = to_dir
	if to_dir == Vector2.ZERO: to_dir = from_dir
	# 0=0001 H, 1=0002 H, 2=0003 V, 3=0004 V, 4=0005 NE, 5=0006 NW, 6=0007 SW, 7=0008 SE
	if from_dir.y != 0 and to_dir.y != 0: return 2  # vertical
	if from_dir.x != 0 and to_dir.x != 0: return 0  # horizontal
	var entry := -from_dir
	var exit_dir := to_dir
	var up := entry == Vector2.UP or exit_dir == Vector2.UP
	var down := entry == Vector2.DOWN or exit_dir == Vector2.DOWN
	var right := entry == Vector2.RIGHT or exit_dir == Vector2.RIGHT
	var left := entry == Vector2.LEFT or exit_dir == Vector2.LEFT
	if up and right: return 5    # NE (top->right) = 0006
	if up and left: return 6     # NW (top->left)  = 0007
	if down and right: return 3  # SE (right->down) = 0004
	if down and left: return 4   # SW (left->down)  = 0005
	return 2


func _draw_rivers() -> void:
	if _river_path_tiles.is_empty():
		return

	# Pass 1 (parallax water fill) is handled by the RiverOverlay child node.
	# Its ShaderMaterial scrolls UVs via TIME — no CPU redraw needed for animation.

	# --- Pass 2: tile sprites — main river N→S ---
	var tile_sz := RIVER_TILE_WORLD * _zoom * 1.12
	var main_tiles: Array = []
	for entry in _river_path_tiles:
		if (entry as Dictionary).get("main", false):
			main_tiles.append(entry)
	main_tiles.sort_custom(func(a, b): return (a["pos"] as Vector2).y < (b["pos"] as Vector2).y)
	for entry in main_tiles:
		var tile_idx: int = entry["tile"]
		if tile_idx < 0 or tile_idx >= _river_tiles.size():
			continue
		var tex: Texture2D = _river_tiles[tile_idx]
		if tex == null:
			continue
		var sp: Vector2 = _to_screen(entry["pos"])
		var draw_w := tile_sz
		var draw_h := tile_sz
		if entry.has("taper_step"):
			var step: int = entry["taper_step"]
			var t := clampf(float(step) / 35.0, 0.0, 1.0)
			var narrow := lerpf(tile_sz, 1.0, t)
			if tile_idx == 0 or tile_idx == 1:  # horizontal — shrink height only
				draw_h = narrow
			elif tile_idx == 2 or tile_idx == 3:  # vertical — shrink width only
				draw_w = narrow
			else:
				continue
		draw_texture_rect(tex, Rect2(sp.x - draw_w * 0.5, sp.y - draw_h * 0.5, draw_w, draw_h), false)

	# --- Pass 3: tributary bank lines (from precomputed world-space data) ---
	for bank_data in _river_trib_bank_data:
		_draw_trib_banks(bank_data)


func _draw_trib_banks(data: Dictionary) -> void:
	var left_world:  Array = data["left_pts"]
	var right_world: Array = data["right_pts"]
	var left_perps:  Array = data["left_perps"]
	var right_perps: Array = data["right_perps"]
	var bank_start_idx: int = data.get("bank_start_idx", 0)
	var n := left_world.size()
	if n <= bank_start_idx + 1:
		return
	var bank_colors: Array = [
		Color("#13646b"), Color("#58989a"), Color("#3c261a"), Color("#5c4027"), Color("#6e5134"),
	]
	var bank_widths:  Array = [4.0, 2.0, 2.0, 2.0, 6.0]
	var bank_offsets: Array = [0.0, 4.0, 6.0, 8.0, 10.0]
	var total_bank_pts := n - bank_start_idx
	var num_chunks := 8
	for side in 2:
		var edge_world: Array = left_world  if side == 0 else right_world
		var perps: Array      = left_perps  if side == 0 else right_perps
		for layer in bank_colors.size():
			var offset: float = bank_offsets[layer]
			var line_w: float = bank_widths[layer]
			for bk in num_chunks:
				var t_start := float(bk)     / float(num_chunks)
				var t_end   := float(bk + 1) / float(num_chunks)
				var idx_start := bank_start_idx + int(t_start * total_bank_pts)
				var idx_end   := mini(bank_start_idx + int(t_end * total_bank_pts) + 1, n)
				if idx_end <= idx_start + 1:
					continue
				var col: Color = bank_colors[layer]
				col.a = lerpf(1.0, 0.0, (t_start + t_end) * 0.5)
				var band := PackedVector2Array()
				for i in range(idx_start, idx_end):
					# Convert edge to screen first, then apply offset in screen space.
					# Offset values are screen-pixel distances; perp is a world-space unit vector
					# which acts as a direction in screen space (matching the original behaviour).
					band.append(_to_screen(edge_world[i] as Vector2) + (perps[i] as Vector2) * offset)
				draw_polyline(band, col, line_w)


func _build_river_strip_mesh(smooth: Array, tex_sz: Vector2, taper: bool) -> ArrayMesh:
	if smooth.size() < 2:
		return null
	var verts := PackedVector2Array()
	var uvs   := PackedVector2Array()
	var base_water_w := RIVER_TILE_WORLD * 0.22
	var n := smooth.size()
	var left_world:  Array = []
	var right_world: Array = []
	for i in n:
		var pt: Vector2 = smooth[i]
		var dir := Vector2.DOWN
		if i < n - 1: dir = (smooth[i + 1] - pt).normalized()
		elif i > 0:   dir = (pt - smooth[i - 1]).normalized()
		var perp := Vector2(-dir.y, dir.x)
		var water_w := base_water_w
		if taper:
			water_w = lerpf(base_water_w, 0.5, clampf(float(i) / float(n - 1), 0.0, 1.0))
		left_world.append(pt - perp * water_w)
		right_world.append(pt + perp * water_w)
	for i in range(n - 1):
		var lw0: Vector2 = left_world[i];   var rw0: Vector2 = right_world[i]
		var lw1: Vector2 = left_world[i+1]; var rw1: Vector2 = right_world[i+1]
		# Quad as two triangles; UVs are world-pos / tex_size (shader adds TIME scroll)
		verts.append(lw0); uvs.append(lw0 / tex_sz)
		verts.append(rw0); uvs.append(rw0 / tex_sz)
		verts.append(lw1); uvs.append(lw1 / tex_sz)
		verts.append(rw0); uvs.append(rw0 / tex_sz)
		verts.append(rw1); uvs.append(rw1 / tex_sz)
		verts.append(lw1); uvs.append(lw1 / tex_sz)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_river_bank_data(smooth: Array) -> Dictionary:
	var base_water_w := RIVER_TILE_WORLD * 0.22
	var n := smooth.size()
	var left_pts:   Array = []
	var right_pts:  Array = []
	var left_perps:  Array = []
	var right_perps: Array = []
	for i in n:
		var pt: Vector2 = smooth[i]
		var dir := Vector2.DOWN
		if i < n - 1: dir = (smooth[i + 1] - pt).normalized()
		elif i > 0:   dir = (pt - smooth[i - 1]).normalized()
		var perp := Vector2(-dir.y, dir.x)
		var water_w := lerpf(base_water_w, 0.5, clampf(float(i) / float(n - 1), 0.0, 1.0))
		left_pts.append(pt - perp * water_w)
		right_pts.append(pt + perp * water_w)
		left_perps.append(-perp)
		right_perps.append(perp)
	# bank_start_idx: skip ~1 tile inward from the junction
	var bank_start_idx := 0
	var dist_accum := 0.0
	for i in range(1, n):
		dist_accum += (smooth[i] as Vector2).distance_to(smooth[i - 1] as Vector2)
		if dist_accum >= RIVER_TILE_WORLD * 0.25:
			bank_start_idx = i
			break
	return {
		"left_pts": left_pts, "right_pts": right_pts,
		"left_perps": left_perps, "right_perps": right_perps,
		"bank_start_idx": bank_start_idx,
	}


func _build_biome_meshes() -> void:
	_swamp_mesh    = _triangulate_rect_tiles(_swamp_tile_data,  640.0, 320.0)
	_swamp_ie_mesh = _triangulate_rect_tiles(_swamp_ie_data,    384.0, 320.0)
	_desert_mesh   = _triangulate_rect_tiles(_desert_tile_data, 640.0, 320.0)
	_tundra_mesh   = _triangulate_rect_tiles(_tundra_tile_data, 640.0, 320.0)

func _triangulate_rect_tiles(tile_data: Array, atlas_w: float, atlas_h: float) -> ArrayMesh:
	if tile_data.is_empty():
		return null
	var verts  := PackedVector2Array()
	var uvs    := PackedVector2Array()
	var colors := PackedColorArray()
	for entry in tile_data:
		var wr: Rect2 = entry["world_rect"]
		var sr: Rect2 = entry["src_rect"]
		var mod: Color = entry.get("modulate", Color.WHITE)
		# Quad corners in world space
		var tl := wr.position
		var tr := Vector2(wr.end.x,    wr.position.y)
		var bl := Vector2(wr.position.x, wr.end.y)
		var br := wr.end
		# UV corners normalised to [0,1]
		var u0 := sr.position.x / atlas_w;  var v0 := sr.position.y / atlas_h
		var u1 := sr.end.x      / atlas_w;  var v1 := sr.end.y      / atlas_h
		# Triangle 1: tl, tr, bl
		verts.append(tl); uvs.append(Vector2(u0, v0)); colors.append(mod)
		verts.append(tr); uvs.append(Vector2(u1, v0)); colors.append(mod)
		verts.append(bl); uvs.append(Vector2(u0, v1)); colors.append(mod)
		# Triangle 2: tr, br, bl
		verts.append(tr); uvs.append(Vector2(u1, v0)); colors.append(mod)
		verts.append(br); uvs.append(Vector2(u1, v1)); colors.append(mod)
		verts.append(bl); uvs.append(Vector2(u0, v1)); colors.append(mod)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR]  = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _build_terrain_mesh() -> void:
	_terrain_mesh = null
	_light_mesh = null

	if not _terrain_tile_data.is_empty() and _grass_atlas_tex != null:
		_terrain_mesh = _triangulate_tiles(_terrain_tile_data)

	if not _light_tile_data.is_empty() and _light_atlas_tex != null:
		_light_mesh = _triangulate_tiles(_light_tile_data)

	if not _dark_tile_data.is_empty() and _dark_atlas_tex != null:
		_dark_mesh = _triangulate_tiles(_dark_tile_data)


func _triangulate_tiles(tile_data: Array) -> ArrayMesh:
	var verts := PackedVector2Array()
	var uvs   := PackedVector2Array()
	var colors := PackedColorArray()
	for td in tile_data:
		var pts: PackedVector2Array = td.world_pts
		var uv_pts: PackedVector2Array = td.uvs
		for i in range(1, pts.size() - 1):
			verts.append(pts[0]);   uvs.append(uv_pts[0]);   colors.append(Color.WHITE)
			verts.append(pts[i]);   uvs.append(uv_pts[i]);   colors.append(Color.WHITE)
			verts.append(pts[i+1]); uvs.append(uv_pts[i+1]); colors.append(Color.WHITE)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR]  = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


const TREE_DRAW_COAST_BUFFER: float = 60.0
const TREE_PROVINCE_BUFFER: float = 40.0

func _init_swamp_fog() -> void:
	if map_data == null:
		return
	# Collect world-space polygons for all swamp provinces.
	var polys: Array = []
	for item in map_data.provinces:
		var p := item as ProvinceData
		if p == null or p.biome != "swamp":
			continue
		var pid: int = int(p.id)
		if _clipped_cells.has(pid):
			polys.append(_clipped_cells[pid] as PackedVector2Array)
	if polys.is_empty():
		return

	if _swamp_fog_overlay == null:
		_swamp_fog_overlay = load("res://Visual/campaign/SwampFogOverlay.gd").new()
		var mat := ShaderMaterial.new()
		mat.shader = SwampFogShader

		var noise := FastNoiseLite.new()
		noise.seed = 7331
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = 4
		noise.frequency = 0.008

		var noise_tex := NoiseTexture2D.new()
		noise_tex.seamless = true
		noise_tex.width = 512
		noise_tex.height = 512
		noise_tex.noise = noise

		mat.set_shader_parameter("noise_tex", noise_tex)
		_swamp_fog_overlay.material = mat
		add_child(_swamp_fog_overlay)

	var fog := _swamp_fog_overlay as Node2D
	fog.set("swamp_polys", polys)
	fog.set("zoom",   _zoom)
	fog.set("origin", _origin)


func _init_weather() -> void:
	if _weather_overlay == null:
		_weather_overlay = ColorRect.new()
		_weather_overlay.name = "WeatherOverlay"
		_weather_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_weather_overlay.color = Color(1, 1, 1, 1)
		var mat := ShaderMaterial.new()
		mat.shader = CloudShadowShader

		var noise := FastNoiseLite.new()
		noise.seed = 1337
		noise.noise_type = FastNoiseLite.TYPE_PERLIN
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = 4
		noise.frequency = 0.01

		var noise_tex := NoiseTexture2D.new()
		noise_tex.seamless = true
		noise_tex.width = 512
		noise_tex.height = 512
		noise_tex.noise = noise

		mat.set_shader_parameter("noise_tex", noise_tex)
		_weather_overlay.material = mat
		add_child(_weather_overlay)

	var bounds := _map_bounds_rect
	if bounds.size.x <= 0:
		bounds = _map_bounds(map_data)
	if bounds.size.x > 0:
		var mat := _weather_overlay.material as ShaderMaterial
		mat.set_shader_parameter("sun_radius", maxf(bounds.size.x, bounds.size.y) * 1.4)

	_update_weather_overlay_rect()


func _update_weather_overlay_rect() -> void:
	if _weather_overlay == null:
		return
	_weather_overlay.position = Vector2.ZERO
	_weather_overlay.size = get_viewport_rect().size


func _update_weather(delta: float) -> void:
	if _weather_overlay == null:
		return
	var mat := _weather_overlay.material as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("cam_origin", _origin)
	mat.set_shader_parameter("cam_zoom", _zoom)

	# Slowly sweep the sun from east to west across the map, looping forever.
	var bounds := _map_bounds_rect
	if bounds.size.x <= 0:
		bounds = _map_bounds(map_data)
	if bounds.size.x > 0:
		_sun_time += delta
		var t := fmod(_sun_time / SUN_CYCLE_SECONDS, 1.0)
		var margin: float = bounds.size.x * 0.1
		var east_x: float = bounds.position.x + bounds.size.x + margin
		var west_x: float = bounds.position.x - margin
		var sun_x: float = lerp(east_x, west_x, t)
		var sun_y: float = bounds.position.y + bounds.size.y * 0.5
		_sun_world_pos = Vector2(sun_x, sun_y)
		mat.set_shader_parameter("sun_world_pos", _sun_world_pos)




const RIVER_TREE_BAND_OFFSET: float = 2.0   # units beyond river buffer where band starts
const RIVER_TREE_BAND_WIDTH: float  = 28.0  # band width — dense riparian zone
const RIVER_TREE_SPACING: float     = 10.0  # tight spacing for fertile bank look

func _scatter_river_trees() -> void:
	if _tree_textures.is_empty():
		return
	var all_pts: Array = []
	for pt in _river_grid_path:
		all_pts.append(pt as Vector2)
	for branch in _river_branch_paths:
		for pt in branch:
			all_pts.append(pt as Vector2)
	if all_pts.is_empty():
		return
	var check_pts: Array = all_pts

	var band_min: float = TREE_RIVER_BUFFER + RIVER_TREE_BAND_OFFSET
	var rng := RandomNumberGenerator.new()
	rng.seed = 88771234

	# Spatial grid of already-placed trees for spacing checks
	var placed_grid: Dictionary = {}
	var scell := RIVER_TREE_SPACING
	for entry in _drawable_trees:
		var p: Vector2 = entry["pos"]
		placed_grid[Vector2i(int(p.x / scell), int(p.y / scell))] = true

	var new_trees: Array = []
	for pt in all_pts:
		for _attempt in range(40):
			var angle: float = rng.randf() * TAU
			# Bias toward the inner edge of the band (closer to water)
			var t: float = pow(rng.randf(), 2.0)
			var dist: float = band_min + t * RIVER_TREE_BAND_WIDTH
			var candidate: Vector2 = pt + Vector2(cos(angle), sin(angle)) * dist

			# Reject if still inside the river — use a larger threshold than the
			# filter buffer to cover gaps between sparse grid path points.
			var in_river := false
			for rpt in check_pts:
				if candidate.distance_to(rpt as Vector2) < TREE_RIVER_BUFFER + 8.0:
					in_river = true
					break
			if in_river:
				continue

			# Spacing check against existing trees
			var sgk := Vector2i(int(candidate.x / scell), int(candidate.y / scell))
			var too_close := false
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					if placed_grid.has(Vector2i(sgk.x + dx, sgk.y + dy)):
						too_close = true
						break
				if too_close:
					break
			if too_close:
				continue

			# Pick tex_idx based on biome at candidate position
			var biome: String = _biome_at_pos(candidate)
			var tex_idx: int
			match biome:
				"swamp":
					var range_size := _tundra_tree_start_idx - _dead_tree_start_idx
					tex_idx = _dead_tree_start_idx + (rng.randi() % maxi(range_size, 1))
				"tundra":
					var range_size := _tree_textures.size() - _tundra_tree_start_idx
					tex_idx = _tundra_tree_start_idx + (rng.randi() % maxi(range_size, 1))
				_:
					tex_idx = rng.randi() % maxi(_dead_tree_start_idx, 1)

			placed_grid[sgk] = true
			new_trees.append({"pos": candidate, "tex_idx": tex_idx, "flip": rng.randi() % 2 == 1})

	_drawable_trees.append_array(new_trees)
	DebugLogger.log("river_trees_placed", {"count": new_trees.size()})


func _filter_coast_trees() -> void:
	_drawable_trees.clear()
	var province_centers: Array = []
	if map_data != null:
		for item in map_data.provinces:
			var p := item as ProvinceData
			if p != null:
				province_centers.append(p.center)

	var skip_coast := _continent_poly.size() < 3
	var n := _continent_poly.size()
	for entry in _tree_positions:
		var pos: Vector2 = entry["pos"]
		var near_province := false
		for c in province_centers:
			if (c as Vector2).distance_to(pos) < TREE_PROVINCE_BUFFER:
				near_province = true
				break
		if near_province:
			continue
		if skip_coast:
			_drawable_trees.append(entry)
			continue
		var min_d := INF
		for i in n:
			var a: Vector2 = _continent_poly[i]
			var b: Vector2 = _continent_poly[(i + 1) % n]
			min_d = minf(min_d, pos.distance_to(Geometry2D.get_closest_point_to_segment(pos, a, b)))
			if min_d < TREE_DRAW_COAST_BUFFER:
				break
		if min_d >= TREE_DRAW_COAST_BUFFER:
			_drawable_trees.append(entry)

const TREE_RIVER_BUFFER: float = 30.0  # no trees within this distance of river/trib paths

func _filter_river_trees() -> void:
	if _drawable_trees.is_empty():
		return
	# Build a spatial grid from river grid points for O(1) proximity checks
	var cell_size := TREE_RIVER_BUFFER
	var river_grid: Dictionary = {}
	for pt in _river_grid_path:
		var gk := Vector2i(int((pt as Vector2).x / cell_size), int((pt as Vector2).y / cell_size))
		river_grid[gk] = true
	for branch in _river_branch_paths:
		for pt in branch:
			var gk := Vector2i(int((pt as Vector2).x / cell_size), int((pt as Vector2).y / cell_size))
			river_grid[gk] = true
	if river_grid.is_empty():
		return
	var filtered: Array = []
	for entry in _drawable_trees:
		var pos: Vector2 = entry["pos"]
		var gk := Vector2i(int(pos.x / cell_size), int(pos.y / cell_size))
		var too_close := false
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				if river_grid.has(Vector2i(gk.x + dx, gk.y + dy)):
					too_close = true
					break
			if too_close:
				break
		if not too_close:
			filtered.append(entry)
	_drawable_trees = filtered

func _draw_swamp_pits() -> void:
	var xform := Transform2D(Vector2(_zoom, 0.0), Vector2(0.0, _zoom), _origin * _zoom)
	if _swamp_mesh != null and _swamp_atlas_tex != null:
		draw_mesh(_swamp_mesh, _swamp_atlas_tex, xform)
	if _swamp_ie_mesh != null and _swamp_ie_tex != null:
		draw_mesh(_swamp_ie_mesh, _swamp_ie_tex, xform)

func _draw_desert_ground() -> void:
	var xform := Transform2D(Vector2(_zoom, 0.0), Vector2(0.0, _zoom), _origin * _zoom)
	if _desert_mesh != null and _desert_atlas_tex != null:
		draw_mesh(_desert_mesh, _desert_atlas_tex, xform)

func _draw_tundra_ground() -> void:
	var xform := Transform2D(Vector2(_zoom, 0.0), Vector2(0.0, _zoom), _origin * _zoom)
	if _tundra_mesh != null and _tundra_atlas_tex != null:
		draw_mesh(_tundra_mesh, _tundra_atlas_tex, xform)


func _build_tree_meshes() -> void:
	_tree_meshes.clear()
	if _tree_textures.is_empty() or _drawable_trees.is_empty():
		return
	# Bucket verts/uvs by texture index
	var buckets: Array = []
	for i in _tree_textures.size():
		buckets.append({"verts": PackedVector2Array(), "uvs": PackedVector2Array()})
	var hw: float = TREE_WORLD_SIZE * 0.5   # half-width in world units
	var hh: float = TREE_WORLD_SIZE          # full height (root at pos, top is pos.y - hh)
	for entry in _drawable_trees:
		var idx: int = entry["tex_idx"] % _tree_textures.size()
		var pos: Vector2 = entry["pos"]
		var flip: bool = entry.get("flip", false)
		var tl := Vector2(pos.x - hw, pos.y - hh)
		var tr := Vector2(pos.x + hw, pos.y - hh)
		var bl := Vector2(pos.x - hw, pos.y)
		var br := Vector2(pos.x + hw, pos.y)
		var u0 := 1.0 if flip else 0.0
		var u1 := 0.0 if flip else 1.0
		var b: Dictionary = buckets[idx]
		var v: PackedVector2Array = b["verts"]
		var u: PackedVector2Array = b["uvs"]
		v.append(tl); u.append(Vector2(u0, 0.0))
		v.append(tr); u.append(Vector2(u1, 0.0))
		v.append(bl); u.append(Vector2(u0, 1.0))
		v.append(tr); u.append(Vector2(u1, 0.0))
		v.append(br); u.append(Vector2(u1, 1.0))
		v.append(bl); u.append(Vector2(u0, 1.0))
	_tree_meshes.resize(_tree_textures.size())
	for i in _tree_textures.size():
		var b: Dictionary = buckets[i]
		var verts: PackedVector2Array = b["verts"]
		if verts.is_empty():
			_tree_meshes[i] = null
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_TEX_UV] = b["uvs"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_tree_meshes[i] = mesh

func _draw_trees() -> void:
	if _tree_meshes.is_empty():
		return
	var xform := Transform2D(Vector2(_zoom, 0.0), Vector2(0.0, _zoom), _origin * _zoom)
	for i in _tree_meshes.size():
		var mesh: ArrayMesh = _tree_meshes[i]
		if mesh == null:
			continue
		draw_mesh(mesh, _tree_textures[i], xform)


func _draw_cells() -> void:
	for item in map_data.provinces:
		var p: ProvinceData = item as ProvinceData
		var pid: int = int(p.id)
		if not _clipped_cells.has(pid):
			continue

		var world_pts: PackedVector2Array = _clipped_cells[pid]
		if world_pts.size() < 3:
			continue
		var pts: PackedVector2Array = PackedVector2Array()
		for v in world_pts:
			pts.append(_to_screen(v))

		var owner_id: int = int(p.owner_id)
		var is_human: bool = owner_id == human_faction_id
		var is_neutral: bool = owner_id < 0
		var is_hover: bool = pid == _hover_id
		var is_selected: bool = pid == _selected_id

		# --- Fill: faction color dominant, biome as a subtle tint ---
		var biome_c: Color = _biome_color(p.biome)
		var fill_c: Color
		if is_neutral:
			fill_c = biome_c.darkened(0.20)
			fill_c.a = 0.70
		else:
			var faction_c: Color = _faction_color(owner_id)
			fill_c = faction_c.lerp(biome_c, 0.20)
			fill_c.a = 0.88

		if is_hover:
			fill_c = fill_c.lightened(0.15)
		if is_selected:
			fill_c = fill_c.lightened(0.22)

		# Province fill -- faction/biome tint over the grass base
		draw_colored_polygon(pts, fill_c)

		# Borders only appear on the selected province.
		if is_hover and not is_selected:
			draw_polyline(pts, Color(1.0, 1.0, 1.0, 0.30), 1.5, true)

		# --- Pick mode highlights (overlaid on top of base border) ---
		if _pick_mode != 0:
			if pid == _pick_source_id:
				draw_polyline(pts, Color(1.0, 0.90, 0.20, 1.0), 3.5, true)
			elif _pick_mode == 1:
				var is_valid_target: bool = _pick_valid_targets.is_empty() or _pick_valid_targets.has(pid)
				if is_valid_target and not is_human and not is_neutral:
					draw_colored_polygon(pts, Color(1.0, 0.20, 0.15, 0.20))
					draw_polyline(pts, Color(1.0, 0.30, 0.25, 0.90), 2.5, true)
				elif is_valid_target and is_neutral:
					draw_colored_polygon(pts, Color(1.0, 0.55, 0.10, 0.16))
					draw_polyline(pts, Color(1.0, 0.60, 0.20, 0.85), 2.5, true)
			elif _pick_mode == 2 and is_human and pid != _pick_source_id:
				draw_colored_polygon(pts, Color(0.25, 0.60, 1.0, 0.20))
				draw_polyline(pts, Color(0.35, 0.70, 1.0, 0.90), 2.5, true)

		# --- Fort level indicator (small dots) ---
		if not is_neutral:
			_draw_fort_indicator(p, pts)


func _draw_fort_indicator(p: ProvinceData, pts: PackedVector2Array) -> void:
	var center: Vector2 = _to_screen(p.center)
	var fort: int = clamp(int(p.fort_level), 0, 5)
	var dot_r: float = 3.0
	var spacing: float = 8.0
	var total_w: float = fort * spacing - spacing * 0.5
	var start_x: float = center.x - total_w * 0.5
	for i in range(fort):
		var dot_pos := Vector2(start_x + i * spacing, center.y + NODE_RADIUS + 6.0)
		draw_circle(dot_pos, dot_r, Color(0.90, 0.80, 0.40, 0.85))


func _draw_routes() -> void:
	if map_data == null or _road_straight_textures.is_empty() or _route_paths.is_empty():
		return

	var stamp_w: float = 1.6 * _zoom   # drawn tile size in screen pixels
	var step: float = stamp_w * 0.65
	var half: float = stamp_w * 0.5

	for ri in _route_paths.size():
		var entry: Dictionary = _route_paths[ri]
		var world_pts: Array = entry["pts"]
		var tex: Texture2D = _road_straight_textures[entry["style"]]

		var screen_pts: Array = []
		for wp in world_pts:
			screen_pts.append(_to_screen(wp))

		# Two-pass soft edge: wide faded halo then sharp core
		for pass_i in 2:
			var w: float = stamp_w * (1.6 if pass_i == 0 else 1.0)
			var alpha: float = 0.25 if pass_i == 0 else 1.0
			var col := Color(0.72, 0.65, 0.55, alpha)
			var accum: float = 0.0
			var last_dir: Vector2 = Vector2.RIGHT
			for ci in range(1, screen_pts.size()):
				var prev: Vector2 = screen_pts[ci - 1]
				var curr: Vector2 = screen_pts[ci]
				var seg: Vector2 = curr - prev
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


func _draw_nodes() -> void:
	for item in map_data.provinces:
		var p: ProvinceData = item as ProvinceData
		var pid: int = int(p.id)
		var pos: Vector2 = _to_screen(p.center)
		var owner_id: int = int(p.owner_id)
		var is_neutral: bool = owner_id < 0

		# Pick biome-specific texture, fall back to lvl1 default
		var province_tex: Texture2D = null
		if int(p.fort_level) >= 2:
			province_tex = _province_lvl2_tex
		else:
			var biome: String = str(p.biome) if p.biome != "" else "plains"
			var biome_arr: Array = _province_biome_textures.get(biome, [])
			if biome_arr.is_empty():
				province_tex = _province_lvl1_tex
			else:
				province_tex = biome_arr[pid % biome_arr.size()]
		if province_tex != null:
			var sz: float = 128.0 * _zoom * 0.3
			var half: float = sz * 0.5
			var flip: bool = (pid * 2654435761) % 3 == 0
			var rect := Rect2(pos.x - half, pos.y - half, sz, sz)
			# Shadow: right edge pinned at sprite right. morning_stretch grows it left;
			# afternoon_stretch grows it right.
			var sun_t: float = fmod(_sun_time / SUN_CYCLE_SECONDS, 1.0)
			var afternoon_stretch: float = clampf((sun_t - 0.5) * 2.0, 0.0, 1.0)
			var morning_stretch: float  = clampf((0.5 - sun_t) * 2.0, 0.0, 1.0)
			var sun_height: float = 1.0 - clampf(
					absf(_sun_world_pos.x - p.center.x) / maxf(_map_bounds_rect.size.x, 1.0), 0.0, 1.0)
			var base_rx: float = lerpf(half * 1.45, half * 1.20, sun_height)
			var shad_rx: float = base_rx * lerpf(1.0, 1.6, morning_stretch) * lerpf(1.0, 2.2, afternoon_stretch)
			var shad_ry: float = lerpf(half * 0.55, half * 0.35, sun_height)
			# Right edge always at pos.x + half. As shad_rx grows in the morning, the
			# left side stretches further left automatically. Evening also pushes center right.
			var h_shift: float = (half - shad_rx) + afternoon_stretch * half * 1.8
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

		# Leader presence dot (white pip if leaders are here)
		if game_state != null and not is_neutral:
			var leaders: Array = game_state.get_province_leaders(pid, false)
			if not leaders.is_empty():
				draw_circle(pos, 3.5, Color(1, 1, 1, 0.90))


func _draw_labels() -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	# Font size scales with zoom, clamped to always be readable
	var font_size: int = clamp(int(_zoom * 5.0), 13, 20)

	for item in map_data.provinces:
		var p: ProvinceData = item as ProvinceData
		var pos: Vector2 = _to_screen(p.center)
		var label: String = str(p.display_name)
		var text_w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		# Centered above the node dot -- fort indicators sit below so no clash
		var draw_pos: Vector2 = Vector2(pos.x - text_w * 0.5, pos.y - NODE_RADIUS - 5)

		# Shadow
		draw_string(font, draw_pos + Vector2(1, 1), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.90))
		# Warm white for owned, muted tan for neutral
		var text_c: Color = Color(0.68, 0.64, 0.56, 0.85) if int(p.owner_id) < 0 \
				else Color(1.0, 0.97, 0.88, 1.0)
		draw_string(font, draw_pos, label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_c)


# --------------------------------------------------
# Coordinate helpers
# --------------------------------------------------
func _to_screen(world: Vector2) -> Vector2:
	return (world + _origin) * _zoom


func _to_world(screen: Vector2) -> Vector2:
	return screen / _zoom - _origin


func _full_fit_zoom(vp: Vector2) -> float:
	if _map_bounds_rect.size.x <= 0 or _map_bounds_rect.size.y <= 0:
		return 1.0
	return minf((vp.x - left_margin - PAD * 2.0) / _map_bounds_rect.size.x,
				(vp.y - PAD * 2.0) / _map_bounds_rect.size.y)


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var world_before: Vector2 = _to_world(screen_pos)
	_zoom = clampf(_zoom * factor, _zoom_min, _zoom_max)
	_origin = screen_pos / _zoom - world_before
	queue_redraw()


func _frame_map() -> void:
	if map_data == null or map_data.provinces.is_empty():
		return
	_map_bounds_rect = _map_bounds(map_data)
	if _map_bounds_rect.size.x <= 0 or _map_bounds_rect.size.y <= 0:
		return

	var vp := get_viewport_rect().size
	var full_zoom := _full_fit_zoom(vp)
	_zoom_min = full_zoom * MIN_ZOOM_FACTOR
	_zoom_max = full_zoom * 15.0
	_zoom = clampf(full_zoom * CLOSE_ZOOM_FACTOR, _zoom_min, _zoom_max)

	# Focus on the starting province (human province with the ruler stationed),
	# fall back to centroid of all human provinces, then map center
	var focus_world: Vector2
	var ruler_province: ProvinceData = null
	var fallback_pts: Array = []
	if game_state != null:
		for item in map_data.provinces:
			var p: ProvinceData = item as ProvinceData
			if p == null or int(p.owner_id) != human_faction_id:
				continue
			fallback_pts.append(p.center)
			if p.ruler_leader_id >= 0 and ruler_province == null:
				ruler_province = p
	if ruler_province != null:
		focus_world = ruler_province.center
	elif not fallback_pts.is_empty():
		var sum := Vector2.ZERO
		for c in fallback_pts:
			sum += c as Vector2
		focus_world = sum / fallback_pts.size()
	else:
		focus_world = _map_bounds_rect.position + _map_bounds_rect.size * 0.5

	var sc := Vector2(vp.x * 0.5, vp.y * 0.5)
	_origin = sc / _zoom - focus_world


# --------------------------------------------------
# Province picking
# --------------------------------------------------
func _pick_province(screen_pos: Vector2) -> int:
	if map_data == null:
		return -1
	# Ignore clicks on the panel side
	if screen_pos.x < left_margin:
		return -1
	var world_pos: Vector2 = _to_world(screen_pos)

	# Primary: point-in-polygon (works well when provinces are large on screen)
	for item in map_data.provinces:
		var p: ProvinceData = item as ProvinceData
		var pid: int = int(p.id)
		if not _voronoi_cells.has(pid):
			continue
		var raw: Array = _voronoi_cells[pid]
		if raw.size() < 3:
			continue
		var pv := PackedVector2Array()
		for v in raw:
			pv.append(v as Vector2)
		if Geometry2D.is_point_in_polygon(world_pos, pv):
			return pid

	# Fallback: nearest center (catches clicks near edges/borders)
	var best_id: int = -1
	var best_dist: float = 32.0 / _zoom
	for item in map_data.provinces:
		var p: ProvinceData = item as ProvinceData
		var d: float = world_pos.distance_to(p.center)
		if d < best_dist:
			best_dist = d
			best_id = int(p.id)
	return best_id


# --------------------------------------------------
# Color helpers
# --------------------------------------------------
func _faction_color(owner_id: int) -> Color:
	if game_state != null and game_state.map_data != null:
		for item in game_state.map_data.factions:
			var f: FactionData = item as FactionData
			if f != null and int(f.id) == owner_id:
				return f.color
	return Color(0.55, 0.55, 0.55)


# --------------------------------------------------
# Order indicators
# --------------------------------------------------
func _draw_order_indicators() -> void:
	if game_state == null or game_state.order_book == null or map_data == null:
		return

	for atk in game_state.order_book.get_attacks(human_faction_id):
		var from_id: int = int(atk.get("from", -1))
		var to_id:   int = int(atk.get("to",   -1))
		if from_id < 0 or to_id < 0:
			continue
		if from_id >= map_data.provinces.size() or to_id >= map_data.provinces.size():
			continue
		var from_p: ProvinceData = map_data.provinces[from_id] as ProvinceData
		var to_p:   ProvinceData = map_data.provinces[to_id]   as ProvinceData
		if from_p == null or to_p == null:
			continue
		var from_s: Vector2 = _to_screen(from_p.center)
		var to_s:   Vector2 = _to_screen(to_p.center)
		# Connecting line
		draw_line(from_s, to_s, Color(1.0, 0.25, 0.20, 0.55), 2.0)
		_draw_arrowhead(from_s, to_s, Color(1.0, 0.30, 0.20, 0.90))
		# Icon above target node
		_draw_crossed_swords(_to_screen(to_p.center) + Vector2(0.0, -NODE_RADIUS - 16.0),
				10.0, Color(1.0, 0.28, 0.18, 1.0))

	for xfer in game_state.order_book.get_transfers(human_faction_id):
		var from_id: int = int(xfer.get("from", -1))
		var to_id:   int = int(xfer.get("to",   -1))
		if from_id < 0 or to_id < 0:
			continue
		if from_id >= map_data.provinces.size() or to_id >= map_data.provinces.size():
			continue
		var from_p: ProvinceData = map_data.provinces[from_id] as ProvinceData
		var to_p:   ProvinceData = map_data.provinces[to_id]   as ProvinceData
		if from_p == null or to_p == null:
			continue
		var from_s: Vector2 = _to_screen(from_p.center)
		var to_s:   Vector2 = _to_screen(to_p.center)
		# Connecting line
		draw_line(from_s, to_s, Color(0.35, 0.70, 1.0, 0.55), 2.0)
		_draw_arrowhead(from_s, to_s, Color(0.35, 0.70, 1.0, 0.90))
		# Icon above target node
		_draw_transfer_badge(_to_screen(to_p.center) + Vector2(0.0, -NODE_RADIUS - 16.0),
				10.0, Color(0.35, 0.72, 1.0, 1.0))


func _draw_arrowhead(from: Vector2, to: Vector2, color: Color) -> void:
	var dir: Vector2 = (to - from).normalized()
	var tip: Vector2 = to - dir * (NODE_RADIUS + 3.0)
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var sz: float = 7.0
	draw_line(tip, tip - dir * sz + perp * sz * 0.5, color, 2.0)
	draw_line(tip, tip - dir * sz - perp * sz * 0.5, color, 2.0)


func _draw_crossed_swords(center: Vector2, size: float, color: Color) -> void:
	# Dark backing circle
	draw_circle(center, size + 3.5, Color(0.05, 0.03, 0.06, 0.88))
	var h: float = size * 0.82
	var g: float = size * 0.38   # crossguard half-length
	var go: float = size * 0.18  # crossguard offset from center

	# Sword 1: top-left -> bottom-right
	draw_line(center + Vector2(-h, -h), center + Vector2(h, h), color, 2.0)
	var gp1: Vector2 = center + Vector2(-go, -go)
	var gd1: Vector2 = Vector2(1.0, -1.0).normalized() * g
	draw_line(gp1 - gd1, gp1 + gd1, color, 2.0)

	# Sword 2: top-right -> bottom-left
	draw_line(center + Vector2(h, -h), center + Vector2(-h, h), color, 2.0)
	var gp2: Vector2 = center + Vector2(go, -go)
	var gd2: Vector2 = Vector2(1.0, 1.0).normalized() * g
	draw_line(gp2 - gd2, gp2 + gd2, color, 2.0)


func _draw_transfer_badge(center: Vector2, size: float, color: Color) -> void:
	# Dark backing circle
	draw_circle(center, size + 3.5, Color(0.04, 0.05, 0.10, 0.88))
	var h: float = size * 0.72
	var tip: float = size * 0.32
	# Arrow pointing right (->)
	draw_line(Vector2(center.x - h, center.y), Vector2(center.x + h, center.y), color, 2.0)
	draw_line(Vector2(center.x + h, center.y),
			Vector2(center.x + h - tip, center.y - tip * 0.6), color, 2.0)
	draw_line(Vector2(center.x + h, center.y),
			Vector2(center.x + h - tip, center.y + tip * 0.6), color, 2.0)



func _biome_color(biome: String) -> Color:
	match biome:
		"plains":   return Color(0.48, 0.62, 0.32)
		"forest":   return Color(0.16, 0.42, 0.20)
		"mountain": return Color(0.52, 0.48, 0.44)
		"desert":   return Color(0.76, 0.64, 0.32)
		"tundra":   return Color(0.62, 0.74, 0.80)
		"swamp":    return Color(0.28, 0.42, 0.28)
		"coast":    return Color(0.24, 0.52, 0.72)
		_:          return Color(0.45, 0.45, 0.45)
