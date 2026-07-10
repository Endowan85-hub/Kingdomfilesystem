# ==================================================
# MapTerrainGenerator
# ==================================================
# Self-contained terrain tile generation system.
# Call generate_from_map(map_data) to build the full
# terrain tile dataset used by PlayerMap.
#
# Triggered by FactionSelect after the player accepts
# a faction, so results are ready the moment CampaignMap
# loads. Stored in SceneManager.pending_terrain.
# ==================================================
class_name MapTerrainGenerator

# -- Asset paths — base grass --
const ATLAS_PATH:       String = "res://Art/map/terrain/tiles/grass_tileset.png"
const SOLID_TILES_PATH: String = "res://Art/map/terrain/tiles/grass_solid.txt"

# -- Asset paths — light grass clump overlay --
const LIGHT_ATLAS_PATH:        String = "res://Art/map/terrain/tiles/grasslight_tileset.png"
const LIGHT_SOLID_TILES_PATH:  String = "res://Art/map/terrain/tiles/grasslight_solid.txt"
const LIGHT_EDGE_TILES_PATH:   String = "res://Art/map/terrain/tiles/grasslight_edge.txt"
const LIGHT_INNER_TILES_PATH:  String = "res://Art/map/terrain/tiles/grasslight_inner.txt"

# -- Asset paths — dark grass clump overlay --
const DARK_ATLAS_PATH:        String = "res://Art/map/terrain/tiles/grassdark_tileset.png"
const DARK_SOLID_TILES_PATH:  String = "res://Art/map/terrain/tiles/grassdark_solid.txt"
const DARK_EDGE_TILES_PATH:   String = "res://Art/map/terrain/tiles/grassdark_edge.txt"
const DARK_INNER_TILES_PATH:  String = "res://Art/map/terrain/tiles/grassdark_inner.txt"


# -- Base tile dimensions (world units, 64px art at 4px/unit) --
const TILE_W: float = 16.0
const TILE_H: float = 16.0

# -- Light overlay tile dimensions (8 world units = finer detail) --
const LIGHT_TILE_W: float = 8.0
const LIGHT_TILE_H: float = 8.0

# -- Light overlay noise params --
const LIGHT_NOISE_FREQ:      float = 0.014
const LIGHT_NOISE_THRESHOLD: float = 0.18

# -- Dark overlay noise params --
const DARK_NOISE_FREQ:      float = 0.011  # slightly larger blobs than light
const DARK_NOISE_THRESHOLD: float = 0.22   # slightly less coverage than light

# -- Swamp biome overlay --
const SWAMP_ATLAS_PATH:      String = "res://Art/tiles/biomes/swamp/swamp_ground.png"
const SWAMP_EDGE_PATH:       String = "res://Art/map/terrain/tiles/swamp_edge.txt"
const SWAMP_INNER_PATH:      String = "res://Art/map/terrain/tiles/swamp_inner.txt"
const SWAMP_ATLAS_COLS:      int    = 10
const SWAMP_ATLAS_ROWS:      int    = 5
const SWAMP_TILE_W:          float  = 32.0
const SWAMP_TILE_H:          float  = 32.0
# Inner concave corner overlay atlas (6×5 grid of 32×32 px tiles)
const SWAMP_IE_PATH:         String = "res://Art/tiles/biomes/swamp/swamp_inneredge.png"
const SWAMP_IE_COLS:         int    = 6
const SWAMP_IE_ROWS:         int    = 5
# Indices in the 6×5 inneredge atlas for each concave corner direction
const SWAMP_IE_NW:           int    = 0                        # row 0, col 0
const SWAMP_IE_NE:           int    = 5                        # row 0, col 5
const SWAMP_IE_SW:           int    = 24                       # row 4, col 0
const SWAMP_IE_SE:           int    = 29                       # row 4, col 5

# -- Tundra biome overlay --
const TUNDRA_ATLAS_PATH:  String = "res://Art/tiles/biomes/tundra/mega_snow.png"
const TUNDRA_EDGE_PATH:   String = "res://Art/map/terrain/tiles/tundra_edge.txt"
const TUNDRA_INNER_PATH:  String = "res://Art/map/terrain/tiles/tundra_inner.txt"
const TUNDRA_ATLAS_COLS:  int    = 10
const TUNDRA_ATLAS_ROWS:  int    = 5
const TUNDRA_TILE_W:      float  = 32.0
const TUNDRA_TILE_H:      float  = 32.0

# -- Desert biome overlay --
const DESERT_ATLAS_PATH:  String = "res://Art/tiles/biomes/desert/mega_desert.png"
const DESERT_EDGE_PATH:   String = "res://Art/map/terrain/tiles/desert_edge.txt"
const DESERT_INNER_PATH:  String = "res://Art/map/terrain/tiles/desert_inner.txt"
const DESERT_ATLAS_COLS:  int    = 10
const DESERT_ATLAS_ROWS:  int    = 5
const DESERT_TILE_W:      float  = 32.0
const DESERT_TILE_H:      float  = 32.0

# -- Tree scatter --
const TREE_PATHS: Array = [
	"res://Art/map/terrain/trees/tree_01.png",
	"res://Art/map/terrain/trees/tree_02.png",
	"res://Art/map/terrain/trees/tree_03.png",
	"res://Art/map/terrain/trees/tree_04.png",
	"res://Art/map/terrain/trees/tree_05.png",
	"res://Art/map/terrain/trees/tree_06.png",
	"res://Art/map/terrain/trees/tree_07.png",
	"res://Art/map/terrain/trees/tree_08.png",
	"res://Art/map/terrain/trees/tree_09.png",
	"res://Art/map/terrain/trees/tree_10.png",
	"res://Art/map/terrain/trees/tree_11.png",
	"res://Art/map/terrain/trees/tree_12.png",
	"res://Art/map/terrain/trees/tree_13.png",
	"res://Art/map/terrain/trees/tree_14.png",
	"res://Art/map/terrain/trees/tree_15.png",
	"res://Art/map/terrain/trees/tree_16.png",
	"res://Art/map/terrain/trees/tree_17.png",
]
const DEAD_TREE_PATHS: Array = [
	"res://Art/map/terrain/dead_trees/dead_tree_01.png",
	"res://Art/map/terrain/dead_trees/dead_tree_02.png",
	"res://Art/map/terrain/dead_trees/dead_tree_03.png",
	"res://Art/map/terrain/dead_trees/dead_tree_04.png",
	"res://Art/map/terrain/dead_trees/dead_tree_05.png",
	"res://Art/map/terrain/dead_trees/dead_tree_06.png",
	"res://Art/map/terrain/dead_trees/dead_tree_07.png",
	"res://Art/map/terrain/dead_trees/dead_tree_08.png",
	"res://Art/map/terrain/dead_trees/dead_tree_09.png",
	"res://Art/map/terrain/dead_trees/dead_tree_10.png",
	"res://Art/map/terrain/dead_trees/dead_tree_11.png",
	"res://Art/map/terrain/dead_trees/dead_tree_12.png",
	"res://Art/map/terrain/dead_trees/dead_tree_13.png",
	"res://Art/map/terrain/dead_trees/dead_tree_14.png",
	"res://Art/map/terrain/dead_trees/dead_tree_15.png",
	"res://Art/map/terrain/dead_trees/dead_tree_16.png",
	"res://Art/map/terrain/dead_trees/dead_tree_17.png",
]
const TUNDRA_TREE_PATHS: Array = [
	"res://Art/map/terrain/tundra_trees/tundra_tree_01.png",
	"res://Art/map/terrain/tundra_trees/tundra_tree_02.png",
	"res://Art/map/terrain/tundra_trees/tundra_tree_03.png",
	"res://Art/map/terrain/tundra_trees/tundra_tree_04.png",
	"res://Art/map/terrain/tundra_trees/tundra_tree_05.png",
	"res://Art/map/terrain/tundra_trees/tundra_tree_06.png",
	"res://Art/map/terrain/tundra_trees/tundra_tree_07.png",
	"res://Art/map/terrain/tundra_trees/tundra_tree_08.png",
	"res://Art/map/terrain/tundra_trees/tundra_tree_09.png",
	"res://Art/map/terrain/tundra_trees/tundra_tree_10.png",
	"res://Art/map/terrain/tundra_trees/tundra_tree_11.png",
	"res://Art/map/terrain/tundra_trees/tundra_tree_12.png",
	"res://Art/map/terrain/tundra_trees/tundra_tree_13.png",
	"res://Art/map/terrain/tundra_trees/tundra_tree_14.png",
	"res://Art/map/terrain/tundra_trees/tundra_tree_15.png",
	"res://Art/map/terrain/tundra_trees/tundra_tree_16.png",
	"res://Art/map/terrain/tundra_trees/tundra_tree_17.png",
	"res://Art/map/terrain/tundra_trees/tundra_tree_18.png",
]
const TREE_COUNT:        int    = 300
const TREE_COAST_BUFFER: float  = 40.0  # min world units from coastline


# -- Atlas layout: 10 columns × 5 rows of 64×64 tiles (both atlases) --
const ATLAS_COLS: int = 10
const ATLAS_ROWS: int = 5

# -- Results (populated by generate_from_map) --
var atlas: Texture2D = null
# Each entry: { world_pts: PackedVector2Array, uvs: PackedVector2Array }
var tile_data: Array = []

var light_atlas: Texture2D = null
var light_tile_data: Array = []

var dark_atlas: Texture2D = null
var dark_tile_data: Array = []

var swamp_atlas: Texture2D = null
var swamp_tile_data: Array = []
var swamp_ie_atlas: Texture2D = null     # inner concave corner overlay
var swamp_ie_data: Array = []

var desert_atlas: Texture2D = null
var desert_tile_data: Array = []

var tundra_atlas: Texture2D = null
var tundra_tile_data: Array = []

var tree_textures: Array = []         # Array of Texture2D (regular, then dead, then tundra)
var dead_tree_start_idx: int = 0      # index where dead trees begin
var tundra_tree_start_idx: int = 0    # index where tundra trees begin
var tree_positions: Array = []        # Array of {pos: Vector2, tex_idx: int}



# --------------------------------------------------
# --------------------------------------------------
# Public entry points — called step-by-step from FactionSelect
# --------------------------------------------------
var _continent_poly: PackedVector2Array = PackedVector2Array()

func generate_base_tiles(map_data: MapData) -> void:
	tile_data.clear(); atlas = null
	light_tile_data.clear(); light_atlas = null
	dark_tile_data.clear();  dark_atlas  = null
	swamp_tile_data.clear(); swamp_atlas   = null
	swamp_ie_data.clear();   swamp_ie_atlas = null
	desert_tile_data.clear(); desert_atlas  = null
	tundra_tile_data.clear(); tundra_atlas  = null
	tree_textures.clear();   tree_positions.clear()
	if map_data == null or map_data.provinces.is_empty():
		return
	_continent_poly = _build_continent_poly(map_data)
	if _continent_poly.size() < 3:
		return
	atlas = load(ATLAS_PATH) as Texture2D
	var solid_indices := _load_solid_indices()
	if solid_indices.is_empty() or atlas == null:
		return
	tile_data = _build_tiles(_continent_poly, solid_indices)

func generate_noise_tiles(map_data: MapData) -> void:
	if _continent_poly.size() < 3:
		return
	light_atlas = load(LIGHT_ATLAS_PATH) as Texture2D
	var light_edge_indices  := _load_indices_from(LIGHT_EDGE_TILES_PATH)
	var light_inner_indices := _load_indices_from(LIGHT_INNER_TILES_PATH)
	if light_atlas != null and (not light_edge_indices.is_empty() or not light_inner_indices.is_empty()):
		light_tile_data = _build_noise_tiles_edge_aware(_continent_poly,
			light_edge_indices, light_inner_indices, map_data,
			LIGHT_NOISE_FREQ, LIGHT_NOISE_THRESHOLD, 0xBAADF00D, LIGHT_TILE_W, LIGHT_TILE_H)
	dark_atlas = load(DARK_ATLAS_PATH) as Texture2D
	var dark_edge_indices  := _load_indices_from(DARK_EDGE_TILES_PATH)
	var dark_inner_indices := _load_indices_from(DARK_INNER_TILES_PATH)
	if dark_atlas != null and (not dark_edge_indices.is_empty() or not dark_inner_indices.is_empty()):
		dark_tile_data = _build_noise_tiles_edge_aware(_continent_poly,
			dark_edge_indices, dark_inner_indices, map_data,
			DARK_NOISE_FREQ, DARK_NOISE_THRESHOLD, 0xDEADC0DE, LIGHT_TILE_W, LIGHT_TILE_H)

func generate_biome_tiles(map_data: MapData) -> void:
	if _continent_poly.size() < 3:
		return
	swamp_atlas = load(SWAMP_ATLAS_PATH) as Texture2D
	var swamp_edge_indices  := _load_indices_from(SWAMP_EDGE_PATH)
	var swamp_inner_indices := _load_indices_from(SWAMP_INNER_PATH)
	if swamp_atlas != null:
		swamp_tile_data = _build_tiles_biome("swamp", map_data, _continent_poly,
				swamp_edge_indices, swamp_inner_indices, SWAMP_TILE_W, SWAMP_TILE_H,
				SWAMP_ATLAS_COLS, SWAMP_ATLAS_ROWS)
		DebugLogger.log("swamp_tiles_built", {"total": swamp_tile_data.size(), "tile_w": SWAMP_TILE_W})
	desert_atlas = load(DESERT_ATLAS_PATH) as Texture2D
	var desert_edge_indices  := _load_indices_from(DESERT_EDGE_PATH)
	var desert_inner_indices := _load_indices_from(DESERT_INNER_PATH)
	if desert_atlas != null:
		desert_tile_data = _build_tiles_biome("desert", map_data, _continent_poly,
				desert_edge_indices, desert_inner_indices, DESERT_TILE_W, DESERT_TILE_H,
				DESERT_ATLAS_COLS, DESERT_ATLAS_ROWS)
		DebugLogger.log("desert_tiles_built", {"total": desert_tile_data.size(), "tile_w": DESERT_TILE_W})
	tundra_atlas = load(TUNDRA_ATLAS_PATH) as Texture2D
	var tundra_edge_indices  := _load_indices_from(TUNDRA_EDGE_PATH)
	var tundra_inner_indices := _load_indices_from(TUNDRA_INNER_PATH)
	if tundra_atlas != null:
		tundra_tile_data = _build_tiles_biome("tundra", map_data, _continent_poly,
				tundra_edge_indices, tundra_inner_indices, TUNDRA_TILE_W, TUNDRA_TILE_H,
				TUNDRA_ATLAS_COLS, TUNDRA_ATLAS_ROWS)
		DebugLogger.log("tundra_tiles_built", {"total": tundra_tile_data.size(), "tile_w": TUNDRA_TILE_W})

func generate_trees(map_data: MapData) -> void:
	if _continent_poly.size() < 3:
		return
	tree_textures.clear()
	for path in TREE_PATHS:
		var t := load(path) as Texture2D
		if t != null:
			tree_textures.append(t)
	dead_tree_start_idx = tree_textures.size()
	for path in DEAD_TREE_PATHS:
		var t := load(path) as Texture2D
		if t != null:
			tree_textures.append(t)
	tundra_tree_start_idx = tree_textures.size()
	for path in TUNDRA_TREE_PATHS:
		var t := load(path) as Texture2D
		if t != null:
			tree_textures.append(t)
	if not tree_textures.is_empty():
		tree_positions = _scatter_trees(_continent_poly, map_data, dead_tree_start_idx, tundra_tree_start_idx)

# Legacy single-call entry point (editor/debug fallback)
func generate_from_map(map_data: MapData) -> void:
	generate_base_tiles(map_data)
	generate_noise_tiles(map_data)
	generate_biome_tiles(map_data)
	generate_trees(map_data)



# --------------------------------------------------
# Continent polygon — same algorithm as PlayerMap
# --------------------------------------------------
func _build_continent_poly(map_data: MapData) -> PackedVector2Array:
	var result := PackedVector2Array()
	var bounds := _map_bounds(map_data)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return result

	# Deterministic seed from province positions
	var h: int = map_data.provinces.size()
	for item in map_data.provinces:
		var p := item as ProvinceData
		if p != null:
			h = h * 31 ^ (int(p.center.x * 37.0) + int(p.center.y * 13.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(h)

	var cx: float = bounds.position.x + bounds.size.x * 0.5
	var cy: float = bounds.position.y + bounds.size.y * 0.5
	var rx: float = bounds.size.x * 0.5 * 1.55
	var ry: float = bounds.size.y * 0.5 * 1.55

	var ph: Array = []
	for i in 10:
		ph.append(rng.randf() * TAU)

	const N := 140
	for i in N:
		var angle: float = float(i) / N * TAU
		var r: float = 1.0
		r += 0.13 * sin(angle * 2.0 + ph[0])
		r += 0.10 * sin(angle * 3.0 + ph[1])
		r += 0.07 * sin(angle * 5.0 + ph[2])
		r += 0.05 * sin(angle * 7.0 + ph[3])
		r += 0.04 * sin(angle * 11.0 + ph[4])
		r += 0.03 * sin(angle * 17.0 + ph[5])
		r += 0.025 * sin(angle * 23.0 + ph[6])
		r += rng.randf_range(-0.04, 0.04)
		r = maxf(r, 0.95)
		result.append(Vector2(cx + cos(angle) * rx * r, cy + sin(angle) * ry * r))

	return result


func _map_bounds(map_data: MapData) -> Rect2:
	var minx: float = 1.0e18; var miny: float = 1.0e18
	var maxx: float = -1.0e18; var maxy: float = -1.0e18
	for item in map_data.provinces:
		var p: ProvinceData = item as ProvinceData
		minx = minf(minx, p.center.x); miny = minf(miny, p.center.y)
		maxx = maxf(maxx, p.center.x); maxy = maxf(maxy, p.center.y)
	if maxx < minx or maxy < miny:
		return Rect2(Vector2.ZERO, Vector2.ONE)
	return Rect2(Vector2(minx, miny), Vector2(maxx - minx, maxy - miny))


# --------------------------------------------------
# Atlas / solid tile index loading
# --------------------------------------------------
func _load_light_indices() -> Array:
	return _load_indices_from(LIGHT_SOLID_TILES_PATH)


func _load_solid_indices() -> Array:
	return _load_indices_from(SOLID_TILES_PATH)


func _atlas_src(idx: int, cols: int, pw: float, ph: float) -> Rect2:
	return Rect2((idx % cols) * pw, (idx / cols) * ph, pw, ph)


func _load_indices_from(path: String) -> Array:
	var indices: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return indices
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line != "":
			indices.append(int(line))
	f.close()
	return indices


# --------------------------------------------------
# Tile mesh generation
# --------------------------------------------------
func _build_tiles(continent_poly: PackedVector2Array, solid_indices: Array) -> Array:
	var result: Array = []

	# Bounding box of continent
	var min_x: float = continent_poly[0].x
	var min_y: float = continent_poly[0].y
	var max_x: float = min_x
	var max_y: float = min_y
	for pt in continent_poly:
		var p: Vector2 = pt
		min_x = minf(min_x, p.x); min_y = minf(min_y, p.y)
		max_x = maxf(max_x, p.x); max_y = maxf(max_y, p.y)

	var x0: float = floor(min_x / TILE_W) * TILE_W
	var y0: float = floor(min_y / TILE_H) * TILE_H
	var u_step: float = 1.0 / ATLAS_COLS
	var v_step: float = 1.0 / ATLAS_ROWS

	var gx: int = 0
	var wx: float = x0
	while wx < max_x + TILE_W:
		var gy: int = 0
		var wy: float = y0
		while wy < max_y + TILE_H:
			var cell := PackedVector2Array([
				Vector2(wx, wy),
				Vector2(wx + TILE_W, wy),
				Vector2(wx + TILE_W, wy + TILE_H),
				Vector2(wx, wy + TILE_H),
			])
			var clipped_arr := Geometry2D.intersect_polygons(cell, continent_poly)
			if not clipped_arr.is_empty():
				var clipped: PackedVector2Array = clipped_arr[0]
				if clipped.size() >= 3:
					# Deterministic tile selection via position hash
					var h: int = (gx * 1664525 + gy * 1013904223) ^ 0x27D4EB2F
					h = ((h >> 16) ^ h) * 0x45D9F3B
					h = (h >> 16) ^ h
					var tile_idx: int = solid_indices[abs(h) % solid_indices.size()]
					var col: int = tile_idx % ATLAS_COLS
					var row: int = tile_idx / ATLAS_COLS
					var u0: float = col * u_step
					var v0: float = row * v_step
					var uvs := PackedVector2Array()
					for cp in clipped:
						var p: Vector2 = cp
						var local_u: float = (p.x - wx) / TILE_W
						var local_v: float = (p.y - wy) / TILE_H
						uvs.append(Vector2(u0 + local_u * u_step, v0 + local_v * v_step))
					result.append({world_pts = clipped, uvs = uvs})
			gy += 1
			wy += TILE_H
		gx += 1
		wx += TILE_W

	return result


# --------------------------------------------------
# Noise-shaped overlay — shared by light and dark layers
# --------------------------------------------------
func _build_noise_tiles(continent_poly: PackedVector2Array, indices: Array, map_data: MapData,
		freq: float, threshold: float, seed_xor: int, tile_w: float, tile_h: float) -> Array:
	var result: Array = []

	var h: int = map_data.provinces.size()
	for item in map_data.provinces:
		var p := item as ProvinceData
		if p != null:
			h = h * 31 ^ (int(p.center.x * 53.0) + int(p.center.y * 19.0))

	var noise := FastNoiseLite.new()
	noise.seed = absi(h) ^ seed_xor
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = freq
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3

	# Bounding box
	var min_x: float = continent_poly[0].x
	var min_y: float = continent_poly[0].y
	var max_x: float = min_x
	var max_y: float = min_y
	for pt in continent_poly:
		var p: Vector2 = pt
		min_x = minf(min_x, p.x); min_y = minf(min_y, p.y)
		max_x = maxf(max_x, p.x); max_y = maxf(max_y, p.y)

	var u_step: float = 1.0 / ATLAS_COLS
	var v_step: float = 1.0 / ATLAS_ROWS
	var x0: float = floor(min_x / tile_w) * tile_w
	var y0: float = floor(min_y / tile_h) * tile_h

	var gx: int = 0
	var wx: float = x0
	while wx < max_x + tile_w:
		var gy: int = 0
		var wy: float = y0
		while wy < max_y + tile_h:
			var n: float = noise.get_noise_2d(wx + tile_w * 0.5, wy + tile_h * 0.5)
			if n > threshold:
				var cell := PackedVector2Array([
					Vector2(wx, wy),
					Vector2(wx + tile_w, wy),
					Vector2(wx + tile_w, wy + tile_h),
					Vector2(wx, wy + tile_h),
				])
				var clipped_arr := Geometry2D.intersect_polygons(cell, continent_poly)
				if not clipped_arr.is_empty():
					var clipped: PackedVector2Array = clipped_arr[0]
					if clipped.size() >= 3:
						var th: int = (gx * 22695477 + gy * 1664525) ^ 0x27D4EB2F
						th = ((th >> 16) ^ th) * 0x45D9F3B
						var tile_idx: int = indices[absi(th) % indices.size()]
						var col: int = tile_idx % ATLAS_COLS
						var row: int = tile_idx / ATLAS_COLS
						var u0: float = col * u_step
						var v0: float = row * v_step
						var uvs := PackedVector2Array()
						for cp in clipped:
							var cp2: Vector2 = cp
							var local_u: float = (cp2.x - wx) / tile_w
							var local_v: float = (cp2.y - wy) / tile_h
							uvs.append(Vector2(u0 + local_u * u_step, v0 + local_v * v_step))
						result.append({world_pts = clipped, uvs = uvs})
			gy += 1
			wy += tile_h
		gx += 1
		wx += tile_w

	return result


# --------------------------------------------------
# Edge-aware noise overlay — dark grass only
# Pass 1: collect all noise-passing cells into a set.
# Pass 2: cells with any non-passing neighbor get an
#         edge tile; fully-surrounded cells get an inner tile.
# --------------------------------------------------
func _build_noise_tiles_edge_aware(continent_poly: PackedVector2Array,
		edge_indices: Array, inner_indices: Array, map_data: MapData,
		freq: float, threshold: float, seed_xor: int,
		tile_w: float, tile_h: float) -> Array:
	var result: Array = []

	var h: int = map_data.provinces.size()
	for item in map_data.provinces:
		var p := item as ProvinceData
		if p != null:
			h = h * 31 ^ (int(p.center.x * 53.0) + int(p.center.y * 19.0))

	var noise := FastNoiseLite.new()
	noise.seed = absi(h) ^ seed_xor
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = freq
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3

	var min_x: float = continent_poly[0].x; var min_y: float = continent_poly[0].y
	var max_x: float = min_x;               var max_y: float = min_y
	for pt in continent_poly:
		var p: Vector2 = pt
		min_x = minf(min_x, p.x); min_y = minf(min_y, p.y)
		max_x = maxf(max_x, p.x); max_y = maxf(max_y, p.y)

	var x0: float = floor(min_x / tile_w) * tile_w
	var y0: float = floor(min_y / tile_h) * tile_h

	# Pass 1 — collect all noise-passing cells
	var passing := {}
	var gx: int = 0
	var wx: float = x0
	while wx < max_x + tile_w:
		var gy: int = 0
		var wy: float = y0
		while wy < max_y + tile_h:
			if noise.get_noise_2d(wx + tile_w * 0.5, wy + tile_h * 0.5) > threshold:
				passing[gx * 100000 + gy] = true
			gy += 1; wy += tile_h
		gx += 1; wx += tile_w

	var u_step: float = 1.0 / ATLAS_COLS
	var v_step: float = 1.0 / ATLAS_ROWS
	var fallback: Array = edge_indices if inner_indices.is_empty() else inner_indices

	# Pass 2 — assign edge or inner tile per cell
	gx = 0; wx = x0
	while wx < max_x + tile_w:
		var gy: int = 0
		var wy: float = y0
		while wy < max_y + tile_h:
			if passing.has(gx * 100000 + gy):
				var is_border: bool = false
				for dx in [-1, 0, 1]:
					for dy in [-1, 0, 1]:
						if dx == 0 and dy == 0:
							continue
						if not passing.has((gx + dx) * 100000 + (gy + dy)):
							is_border = true
							break
					if is_border:
						break

				var pool: Array = edge_indices if is_border else fallback
				var cell := PackedVector2Array([
					Vector2(wx, wy), Vector2(wx + tile_w, wy),
					Vector2(wx + tile_w, wy + tile_h), Vector2(wx, wy + tile_h),
				])
				var clipped_arr := Geometry2D.intersect_polygons(cell, continent_poly)
				if not clipped_arr.is_empty():
					var clipped: PackedVector2Array = clipped_arr[0]
					if clipped.size() >= 3:
						var th: int = (gx * 22695477 + gy * 1664525) ^ 0x27D4EB2F
						th = ((th >> 16) ^ th) * 0x45D9F3B
						var tile_idx: int = pool[absi(th) % pool.size()]
						var col: int = tile_idx % ATLAS_COLS
						var row: int = tile_idx / ATLAS_COLS
						var uvs := PackedVector2Array()
						for cp in clipped:
							var cp2: Vector2 = cp
							uvs.append(Vector2(
								col * u_step + ((cp2.x - wx) / tile_w) * u_step,
								row * v_step + ((cp2.y - wy) / tile_h) * v_step))
						result.append({world_pts = clipped, uvs = uvs})
			gy += 1; wy += tile_h
		gx += 1; wx += tile_w

	return result


# --------------------------------------------------
# Biome-specific tile overlay
# --------------------------------------------------
# Finds non-biome cells that sit at an L-shaped concave corner of the biome
# (exactly two perpendicular cardinal neighbours are biome, the other two are not)
# and fills them with a regular inner biome tile so the staircase notch blends in.
# --------------------------------------------------
func _build_corner_fill_tiles(biome: String, map_data: MapData,
		continent_poly: PackedVector2Array,
		inner_indices: Array,
		tile_w: float, tile_h: float,
		atlas_cols: int, atlas_rows: int) -> Array:
	var result: Array = []
	if map_data == null or map_data.provinces.is_empty() or inner_indices.is_empty():
		return result

	var prov_centers: Array = []
	var prov_biomes: Array = []
	for item in map_data.provinces:
		var p := item as ProvinceData
		if p != null:
			prov_centers.append(p.center)
			prov_biomes.append(p.biome)

	var nearest_biome := func(pt: Vector2) -> String:
		var best_d := 1.0e18
		var best_b := ""
		for i in prov_centers.size():
			var d: float = pt.distance_squared_to(prov_centers[i])
			if d < best_d:
				best_d = d
				best_b = prov_biomes[i]
		return best_b

	var min_x: float = continent_poly[0].x; var min_y: float = continent_poly[0].y
	var max_x: float = min_x;               var max_y: float = min_y
	for pt in continent_poly:
		var p: Vector2 = pt
		min_x = minf(min_x, p.x); min_y = minf(min_y, p.y)
		max_x = maxf(max_x, p.x); max_y = maxf(max_y, p.y)
	var x0: float = floor(min_x / tile_w) * tile_w
	var y0: float = floor(min_y / tile_h) * tile_h

	var biome_cells: Dictionary = {}
	var gx: int = 0; var wx: float = x0
	while wx < max_x + tile_w:
		var gy: int = 0; var wy: float = y0
		while wy < max_y + tile_h:
			var center := Vector2(wx + tile_w * 0.5, wy + tile_h * 0.5)
			if Geometry2D.is_point_in_polygon(center, continent_poly):
				if nearest_biome.call(center) == biome:
					biome_cells[gx * 100000 + gy] = true
			gy += 1; wy += tile_h
		gx += 1; wx += tile_w

	var px_w: float = float(640 / atlas_cols)
	var px_h: float = float(320 / atlas_rows)

	gx = 0; wx = x0
	while wx < max_x + tile_w:
		var gy: int = 0; var wy: float = y0
		while wy < max_y + tile_h:
			if not biome_cells.has(gx * 100000 + gy):
				var sw_n: bool = biome_cells.has(gx * 100000 + (gy - 1))
				var sw_s: bool = biome_cells.has(gx * 100000 + (gy + 1))
				var sw_w: bool = biome_cells.has((gx - 1) * 100000 + gy)
				var sw_e: bool = biome_cells.has((gx + 1) * 100000 + gy)
				var is_lcorner: bool = (sw_n and sw_w and not sw_s and not sw_e) or \
									   (sw_n and sw_e and not sw_s and not sw_w) or \
									   (sw_s and sw_w and not sw_n and not sw_e) or \
									   (sw_s and sw_e and not sw_n and not sw_w)
				if is_lcorner:
					var th: int = hash(gx * 374761393 ^ gy * 668265263)
					var tile_idx: int = inner_indices[absi(th) % inner_indices.size()]
					var col: int = tile_idx % atlas_cols
					var row: int = tile_idx / atlas_cols
					result.append({
						world_rect = Rect2(wx, wy, tile_w, tile_h),
						src_rect   = Rect2(col * px_w, row * px_h, px_w, px_h),
						is_edge    = false
					})
			gy += 1; wy += tile_h
		gx += 1; wx += tile_w
	return result

# --------------------------------------------------
# Inner concave corner overlay pass.
# For each biome cell whose DIAGONAL neighbour is outside the biome while BOTH
# cardinal neighbours in that diagonal direction are inside — place a concave
# corner tile from the inneredge atlas on top of the normal swamp tile.
# --------------------------------------------------
func _build_inneredge_tiles(biome: String, map_data: MapData,
		continent_poly: PackedVector2Array,
		tile_w: float, tile_h: float,
		ie_cols: int, ie_rows: int) -> Array:
	var result: Array = []
	if map_data == null or map_data.provinces.is_empty():
		return result

	var prov_centers: Array = []
	var prov_biomes: Array = []
	for item in map_data.provinces:
		var p := item as ProvinceData
		if p != null:
			prov_centers.append(p.center)
			prov_biomes.append(p.biome)

	var nearest_biome := func(pt: Vector2) -> String:
		var best_d := 1.0e18
		var best_b := ""
		for i in prov_centers.size():
			var d: float = pt.distance_squared_to(prov_centers[i])
			if d < best_d:
				best_d = d
				best_b = prov_biomes[i]
		return best_b

	# Compute grid origin the same way _build_tiles_biome does — from continent_poly bounds.
	var min_x: float = continent_poly[0].x; var min_y: float = continent_poly[0].y
	var max_x: float = min_x;               var max_y: float = min_y
	for pt in continent_poly:
		var p: Vector2 = pt
		min_x = minf(min_x, p.x); min_y = minf(min_y, p.y)
		max_x = maxf(max_x, p.x); max_y = maxf(max_y, p.y)
	var x0: float = floor(min_x / tile_w) * tile_w
	var y0: float = floor(min_y / tile_h) * tile_h

	var biome_cells: Dictionary = {}
	var gx: int = 0
	var wx: float = x0
	while wx < max_x + tile_w:
		var gy: int = 0
		var wy: float = y0
		while wy < max_y + tile_h:
			var center := Vector2(wx + tile_w * 0.5, wy + tile_h * 0.5)
			if Geometry2D.is_point_in_polygon(center, continent_poly):
				if nearest_biome.call(center) == biome:
					biome_cells[gx * 100000 + gy] = true
			gy += 1; wy += tile_h
		gx += 1; wx += tile_w

	var px_w: float = 64.0
	var px_h: float = 64.0

	# Pass 2: for biome cells that are inner (no missing cardinal neighbours) but
	# have a non-biome diagonal, swap their tile for the matching inneredge corner.
	gx = 0; wx = x0
	while wx < max_x + tile_w:
		var gy: int = 0
		var wy: float = y0
		while wy < max_y + tile_h:
			if biome_cells.has(gx * 100000 + gy):
				var in_n: bool = biome_cells.has(gx * 100000 + (gy - 1))
				var in_s: bool = biome_cells.has(gx * 100000 + (gy + 1))
				var in_w: bool = biome_cells.has((gx - 1) * 100000 + gy)
				var in_e: bool = biome_cells.has((gx + 1) * 100000 + gy)
				# Only inner cells (no missing cardinal neighbours)
				if in_n and in_s and in_w and in_e:
					var tile_idx: int = -1
					if not biome_cells.has((gx - 1) * 100000 + (gy - 1)): tile_idx = SWAMP_IE_NW
					elif not biome_cells.has((gx + 1) * 100000 + (gy - 1)): tile_idx = SWAMP_IE_NE
					elif not biome_cells.has((gx - 1) * 100000 + (gy + 1)): tile_idx = SWAMP_IE_SW
					elif not biome_cells.has((gx + 1) * 100000 + (gy + 1)): tile_idx = SWAMP_IE_SE
					if tile_idx >= 0:
						var col: int = tile_idx % ie_cols
						var row: int = tile_idx / ie_cols
						result.append({
							world_rect = Rect2(wx, wy, tile_w, tile_h),
							src_rect   = Rect2(col * px_w, row * px_h, px_w, px_h)
						})
			gy += 1; wy += tile_h
		gx += 1; wx += tile_w
	return result

# --------------------------------------------------
# Covers cells whose nearest province matches the target biome.
# Adjacent biome provinces are treated as one continuous area.
# Edge tiles placed where any neighbour cell belongs to a different biome.
# --------------------------------------------------
func _build_tiles_biome(biome: String, map_data: MapData,
		continent_poly: PackedVector2Array,
		edge_indices: Array, inner_indices: Array,
		tile_w: float, tile_h: float,
		atlas_cols: int, atlas_rows: int) -> Array:
	var result: Array = []
	if map_data == null or map_data.provinces.is_empty():
		return result

	# Build flat list of province centers + biomes for fast lookup
	var prov_centers: Array = []
	var prov_biomes: Array = []
	for item in map_data.provinces:
		var p := item as ProvinceData
		if p != null:
			prov_centers.append(p.center)
			prov_biomes.append(p.biome)

	# Nearest-province biome for a world point
	var nearest_biome := func(pt: Vector2) -> String:
		var best_d := 1.0e18
		var best_b := ""
		for i in prov_centers.size():
			var d: float = pt.distance_squared_to(prov_centers[i])
			if d < best_d:
				best_d = d
				best_b = prov_biomes[i]
		return best_b

	# Bounds
	var min_x: float = continent_poly[0].x; var min_y: float = continent_poly[0].y
	var max_x: float = min_x;               var max_y: float = min_y
	for pt in continent_poly:
		var p: Vector2 = pt
		min_x = minf(min_x, p.x); min_y = minf(min_y, p.y)
		max_x = maxf(max_x, p.x); max_y = maxf(max_y, p.y)
	var x0: float = floor(min_x / tile_w) * tile_w
	var y0: float = floor(min_y / tile_h) * tile_h

	# Pass 1 — mark cells that belong to this biome
	var biome_cells: Dictionary = {}
	var gx: int = 0
	var wx: float = x0
	while wx < max_x + tile_w:
		var gy: int = 0
		var wy: float = y0
		while wy < max_y + tile_h:
			var center := Vector2(wx + tile_w * 0.5, wy + tile_h * 0.5)
			if Geometry2D.is_point_in_polygon(center, continent_poly):
				if nearest_biome.call(center) == biome:
					biome_cells[gx * 100000 + gy] = true
			gy += 1; wy += tile_h
		gx += 1; wx += tile_w

	var fallback: Array = edge_indices if inner_indices.is_empty() else inner_indices
	var px_w: float = float(640 / atlas_cols)
	var px_h: float = float(320 / atlas_rows)

	# Directional edge pools: pick atlas row/col whose dark border faces the missing neighbour.
	# Atlas layout (10×5): row 0 = top border, row 4 = bottom, col 0 = left, col 9 = right.
	var last_col: int = atlas_cols - 1
	var last_row: int = atlas_rows - 1
	var pool_n: Array = []  # dark at top    → atlas row 0, inner cols
	var pool_s: Array = []  # dark at bottom → atlas row last, inner cols
	var pool_w: Array = []  # dark at left   → atlas col 0, inner rows
	var pool_e: Array = []  # dark at right  → atlas col last, inner rows
	# Corner tiles — dark on two sides simultaneously
	var tile_nw: int = 0                          # row 0, col 0
	var tile_ne: int = last_col                   # row 0, col last
	var tile_sw: int = last_row * atlas_cols      # row last, col 0
	var tile_se: int = last_row * atlas_cols + last_col  # row last, col last
	for ei in edge_indices:
		var ec: int = int(ei) % atlas_cols
		var er: int = int(ei) / atlas_cols
		if er == 0 and ec > 0 and ec < last_col:           pool_n.append(ei)
		elif er == last_row and ec > 0 and ec < last_col:  pool_s.append(ei)
		elif ec == 0 and er > 0 and er < last_row:         pool_w.append(ei)
		elif ec == last_col and er > 0 and er < last_row:  pool_e.append(ei)

	# Pass 2 — directional edge selection, emit world rect + atlas source rect
	gx = 0; wx = x0
	while wx < max_x + tile_w:
		var gy: int = 0
		var wy: float = y0
		while wy < max_y + tile_h:
			var key: int = gx * 100000 + gy
			if biome_cells.has(key):
				var miss_n: bool = not biome_cells.has(gx * 100000 + (gy - 1))
				var miss_s: bool = not biome_cells.has(gx * 100000 + (gy + 1))
				var miss_w: bool = not biome_cells.has((gx - 1) * 100000 + gy)
				var miss_e: bool = not biome_cells.has((gx + 1) * 100000 + gy)
				var is_edge: bool = miss_n or miss_s or miss_w or miss_e

				var diag_nw: bool = not biome_cells.has((gx - 1) * 100000 + (gy - 1))
				var diag_ne: bool = not biome_cells.has((gx + 1) * 100000 + (gy - 1))
				var diag_sw: bool = not biome_cells.has((gx - 1) * 100000 + (gy + 1))
				var diag_se: bool = not biome_cells.has((gx + 1) * 100000 + (gy + 1))

				var pool: Array
				var is_inner_corner: bool = false
				if not is_edge or edge_indices.is_empty():
					pool = inner_indices if not inner_indices.is_empty() else fallback
					if diag_nw or diag_ne or diag_sw or diag_se:
						is_inner_corner = true
				else:
					# Corner tiles when two perpendicular sides are missing.
					if miss_n and miss_w:
						pool = [tile_nw]
					elif miss_n and miss_e:
						pool = [tile_ne]
					elif miss_s and miss_w:
						pool = [tile_sw]
					elif miss_s and miss_e:
						pool = [tile_se]
					elif miss_n:
						pool = pool_n
					elif miss_s:
						pool = pool_s
					elif miss_w:
						pool = pool_w
					else:
						pool = pool_e
					if pool.is_empty():
						pool = fallback

				var th: int = hash(gx * 374761393 ^ gy * 668265263)
				var tile_idx: int = pool[absi(th) % pool.size()]
				var col: int = tile_idx % atlas_cols
				var row: int = tile_idx / atlas_cols
				var sr := Rect2(col * px_w, row * px_h, px_w, px_h)
				var wr := Rect2(wx, wy, tile_w, tile_h)
				result.append({world_rect = wr, src_rect = sr, is_edge = is_edge})

				# Draw the edge vignette tile shifted outward so it overlaps the edge tile
				# by 1/4 and bleeds into the adjacent non-swamp terrain.
				if is_edge:
					if miss_n:
						result.append({world_rect = Rect2(wx, wy - tile_h * 0.375, tile_w, tile_h), src_rect = sr, is_edge = true})
					if miss_s:
						result.append({world_rect = Rect2(wx, wy + tile_h * 0.375, tile_w, tile_h), src_rect = sr, is_edge = true})
					if miss_w:
						result.append({world_rect = Rect2(wx - tile_w * 0.375, wy, tile_w, tile_h), src_rect = sr, is_edge = true})
					if miss_e:
						result.append({world_rect = Rect2(wx + tile_w * 0.375, wy, tile_w, tile_h), src_rect = sr, is_edge = true})
			gy += 1; wy += tile_h
		gx += 1; wx += tile_w

	return result


# --------------------------------------------------
# Tree scatter — clustered irregular forest placement
# --------------------------------------------------
const CLUSTER_COUNT:      int   = 28     # number of forest clumps
const CLUSTER_TREES:      int   = 30     # avg trees per clump
const CLUSTER_RADIUS:     float = 70.0   # spread radius per clump (world units)
const OUTLIER_COUNT:      int   = 60     # lone trees scattered outside clumps
const FILL_EDGE_COUNT:    int   = 600    # minitrees filling gaps across the map
const FILL_EDGE_SPACING:  float = 38.0   # spacing between fill trees
const MIN_TREE_SPACING:   float = 10.0   # min distance between any two trees
const PROVINCE_CLEAR_RADIUS: float = 0.0  # no trees within this radius of a province center
# indices into TREE_PATHS for the sparse/scattered edge variants
const EDGE_TEX_INDICES:   Array = [3, 6, 8, 11, 12]  # minitree4,8,10,13,14
const EDGE_TREES:         int   = 5      # edge trees placed around each cluster perimeter

func _near_province(pt: Vector2, province_centers: Array) -> bool:
	for c in province_centers:
		if (c as Vector2).distance_to(pt) < PROVINCE_CLEAR_RADIUS:
			return true
	return false

func _tree_grid_key(pos: Vector2) -> Vector2i:
	return Vector2i(int(pos.x / MIN_TREE_SPACING), int(pos.y / MIN_TREE_SPACING))

func _tree_too_close(pos: Vector2, grid: Dictionary) -> bool:
	var gk := _tree_grid_key(pos)
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			var cell := Vector2i(gk.x + dx, gk.y + dy)
			if grid.has(cell):
				for existing in grid[cell]:
					if (existing as Vector2).distance_to(pos) < MIN_TREE_SPACING:
						return true
	return false

func _tree_grid_add(pos: Vector2, grid: Dictionary) -> void:
	var gk := _tree_grid_key(pos)
	if not grid.has(gk):
		grid[gk] = []
	(grid[gk] as Array).append(pos)

func _scatter_trees(continent_poly: PackedVector2Array, map_data: MapData, dead_start: int = 0, tundra_start: int = 0) -> Array:
	var result: Array = []
	var spatial_grid: Dictionary = {}  # Vector2i → Array[Vector2], O(1) neighbor checks
	var min_x := continent_poly[0].x; var min_y := continent_poly[0].y
	var max_x := min_x;               var max_y := min_y
	for pt in continent_poly:
		var p: Vector2 = pt
		min_x = minf(min_x, p.x); min_y = minf(min_y, p.y)
		max_x = maxf(max_x, p.x); max_y = maxf(max_y, p.y)

	# Collect all province centers for castle-clear zone
	var province_centers: Array = []
	for item in map_data.provinces:
		var p := item as ProvinceData
		if p != null:
			province_centers.append(p.center)

	var h: int = map_data.provinces.size()
	for item in map_data.provinces:
		var p := item as ProvinceData
		if p != null:
			h = h * 31 ^ (int(p.center.x * 17.0) + int(p.center.y * 41.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(h) ^ 0x7EE55EED

	# Biome tree density — 1 (bare) to 10 (dense). 0 = no trees at all.
	const BIOME_DENSITY: Dictionary = {
		"forest":   10,  # density scale drives cluster count below
		"swamp":    10,
		"plains":    2,
		"coast":     2,
		"tundra":    8,
		"mountain":  0,
		"desert":    0,
	}
	# Density → clusters per province (density 10 = 4 clusters, 1 = 0 clusters)
	# Density → outlier weight  (density 10 = high chance, 1 = rare)

	# Build cluster centers driven by per-province biome density
	var centers: Array = []
	for item in map_data.provinces:
		var p := item as ProvinceData
		if p == null:
			continue
		var density: int = BIOME_DENSITY.get(str(p.biome), 1)
		if density == 0:
			continue
		# density 10 → 12 clusters, density 5 → 3, density 2 → 0-1 (sparse, no tight clumps)
		var cluster_target: int = int(round(density * density * 0.12))
		# Low-density biomes (≤3): 50% chance to skip entirely — keeps them truly sparse
		if density <= 3 and rng.randf() > float(density) / 3.0:
			cluster_target = 0
		var prov_attempts: int = 0
		var prov_placed: int = 0
		while prov_placed < cluster_target and prov_attempts < cluster_target * 30:
			prov_attempts += 1
			var spread: float = CLUSTER_RADIUS * (1.0 + density * 0.15)
			var offset := Vector2(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread))
			var c: Vector2 = p.center + offset
			if not Geometry2D.is_point_in_polygon(c, continent_poly):
				continue
			if _dist_to_poly_edge(c, continent_poly) < TREE_COAST_BUFFER:
				continue
			centers.append({"pos": c, "density": density, "biome": str(p.biome)})
			prov_placed += 1

	var biome_tree_counts: Dictionary = {}  # biome string → int, for logging

	# Scatter trees around each cluster center using gaussian-like spread
	for entry in centers:
		var center: Vector2 = entry["pos"]
		var density_here: int = entry["density"]
		var biome_here: String = entry["biome"]
		# Low-density biomes get small, loose clusters; high-density get full clumps
		var max_count: int = CLUSTER_TREES * 2 if density_here >= 8 else (CLUSTER_TREES if density_here >= 5 else 6)
		var count: int = rng.randi_range(2, max_count)
		var rx: float = rng.randf_range(CLUSTER_RADIUS * 0.4, CLUSTER_RADIUS * 1.6)
		var ry: float = rng.randf_range(CLUSTER_RADIUS * 0.3, CLUSTER_RADIUS * 1.2)
		var angle_offset: float = rng.randf_range(0.0, TAU)
		var placed: int = 0
		var tries: int = 0
		while placed < count and tries < count * 12:
			tries += 1
			var gx: float = (rng.randf() + rng.randf() + rng.randf() - 1.5) / 1.5
			var gy: float = (rng.randf() + rng.randf() + rng.randf() - 1.5) / 1.5
			var lx: float = gx * rx * cos(angle_offset) - gy * ry * sin(angle_offset)
			var ly: float = gx * rx * sin(angle_offset) + gy * ry * cos(angle_offset)
			var pt: Vector2 = center + Vector2(lx, ly)
			if not Geometry2D.is_point_in_polygon(pt, continent_poly):
				continue
			if _dist_to_poly_edge(pt, continent_poly) < TREE_COAST_BUFFER:
				continue
			if _near_province(pt, province_centers):
				continue
			if _tree_too_close(pt, spatial_grid):
				continue
			var dead_count: int   = tundra_start - dead_start
			var tundra_count: int = tree_textures.size() - tundra_start
			var tex_idx: int
			var roll: float = rng.randf()
			if biome_here == "swamp" and dead_count > 0 and roll < 0.55:
				# Swamp: ~55% dead trees
				tex_idx = dead_start + rng.randi() % dead_count
			elif biome_here == "tundra" and tundra_count > 0:
				if roll < 0.80:
					# Tundra: 80% tundra trees, 15% dead, 5% regular
					tex_idx = tundra_start + rng.randi() % tundra_count
				elif roll < 0.95 and dead_count > 0:
					tex_idx = dead_start + rng.randi() % dead_count
				else:
					tex_idx = rng.randi() % dead_start
			else:
				tex_idx = rng.randi() % dead_start
			var tree_type: String = "regular" if tex_idx < dead_start else ("dead" if tex_idx < tundra_start else "tundra")
			result.append({ "pos": pt, "tex_idx": tex_idx, "flip": rng.randi() % 2 == 1 })
			_tree_grid_add(pt, spatial_grid)
			placed += 1
			var ck: String = biome_here + ":" + tree_type
			biome_tree_counts[ck] = biome_tree_counts.get(ck, 0) + 1

		# Edge trees scattered around each individual core tree that was placed
		var core_end: int = result.size()
		var core_start: int = core_end - placed
		for ci in placed:
			var core_pos: Vector2 = result[core_start + ci]["pos"]
			var edge_placed: int = 0
			var edge_tries: int = 0
			while edge_placed < EDGE_TREES and edge_tries < EDGE_TREES * 20:
				edge_tries += 1
				var edge_angle: float = rng.randf_range(0.0, TAU)
				var edge_dist: float = rng.randf_range(MIN_TREE_SPACING * 1.1, MIN_TREE_SPACING * 2.2)
				var pt: Vector2 = core_pos + Vector2(cos(edge_angle) * edge_dist, sin(edge_angle) * edge_dist)
				if not Geometry2D.is_point_in_polygon(pt, continent_poly):
					continue
				if _dist_to_poly_edge(pt, continent_poly) < TREE_COAST_BUFFER:
					continue
				if _near_province(pt, province_centers):
					continue
				if _tree_too_close(pt, spatial_grid):
					continue
				var edge_idx: int
				var edge_type: String
				var dead_count_e: int = tundra_start - dead_start
				var tundra_count_e: int = tree_textures.size() - tundra_start
				if biome_here == "tundra" and tundra_count_e > 0:
					var er: float = rng.randf()
					if er < 0.80:
						edge_idx = tundra_start + rng.randi() % tundra_count_e
						edge_type = "tundra"
					elif er < 0.95 and dead_count_e > 0:
						edge_idx = dead_start + rng.randi() % dead_count_e
						edge_type = "dead"
					else:
						edge_idx = rng.randi() % dead_start
						edge_type = "regular"
				else:
					edge_idx = EDGE_TEX_INDICES[rng.randi() % EDGE_TEX_INDICES.size()]
					edge_type = "regular"
				result.append({ "pos": pt, "tex_idx": edge_idx, "flip": rng.randi() % 2 == 1 })
				_tree_grid_add(pt, spatial_grid)
				edge_placed += 1
				var eck: String = biome_here + ":" + edge_type
				biome_tree_counts[eck] = biome_tree_counts.get(eck, 0) + 1

	# Build nearest-province lookup used by outlier and fill passes
	var all_province_data: Array = []
	for item in map_data.provinces:
		var pd := item as ProvinceData
		if pd != null:
			all_province_data.append(pd)

	# Outlier lone trees — regular trees only, skip tundra zones
	var tree_provinces: Array = []
	var tundra_province_set: Dictionary = {}
	for item in map_data.provinces:
		var p := item as ProvinceData
		if p == null:
			continue
		var density: int = BIOME_DENSITY.get(str(p.biome), 1)
		if str(p.biome) == "tundra":
			tundra_province_set[p.center] = true
			continue
		for _d in density:
			tree_provinces.append(p.center)
	var outlier_attempts: int = 0
	var outliers: int = 0
	while outliers < OUTLIER_COUNT and outlier_attempts < OUTLIER_COUNT * 30:
		if tree_provinces.is_empty():
			break
		var anchor: Vector2 = tree_provinces[rng.randi() % tree_provinces.size()]
		var pt := anchor + Vector2(rng.randf_range(-CLUSTER_RADIUS * 3.0, CLUSTER_RADIUS * 3.0),
			rng.randf_range(-CLUSTER_RADIUS * 3.0, CLUSTER_RADIUS * 3.0))
		if not Geometry2D.is_point_in_polygon(pt, continent_poly):
			continue
		if _dist_to_poly_edge(pt, continent_poly) < TREE_COAST_BUFFER:
			continue
		if _near_province(pt, province_centers):
			continue
		if _tree_too_close(pt, spatial_grid):
			continue
		# Don't let outliers wander into tundra/barren provinces
		var nb := ""
		var nd := 1.0e18
		for pd in all_province_data:
			var d: float = pt.distance_squared_to((pd as ProvinceData).center)
			if d < nd:
				nd = d
				nb = (pd as ProvinceData).biome
		if nb in ["tundra", "desert", "mountain"]:
			continue
		result.append({ "pos": pt, "tex_idx": rng.randi() % dead_start, "flip": rng.randi() % 2 == 1 })
		_tree_grid_add(pt, spatial_grid)
		outliers += 1

	# Build exclusion lists for fill passes
	var barren_centers: Array = []
	var tundra_centers: Array = []
	for item in map_data.provinces:
		var p := item as ProvinceData
		if p == null:
			continue
		if BIOME_DENSITY.get(str(p.biome), 1) == 0:
			barren_centers.append(p.center)
		if str(p.biome) == "tundra":
			tundra_centers.append(p.center)
	const BARREN_EXCLUSION: float = 160.0
	const TUNDRA_EXCLUSION: float = 180.0

	# Fill pass — regular minitrees, skipping barren and tundra provinces
	var fill_placed: int = 0
	var fill_attempts: int = 0
	while fill_placed < FILL_EDGE_COUNT and fill_attempts < FILL_EDGE_COUNT * 20:
		fill_attempts += 1
		var pt := Vector2(rng.randf_range(min_x, max_x), rng.randf_range(min_y, max_y))
		if not Geometry2D.is_point_in_polygon(pt, continent_poly):
			continue
		if _dist_to_poly_edge(pt, continent_poly) < TREE_COAST_BUFFER:
			continue
		if _near_province(pt, province_centers):
			continue
		if _tree_too_close(pt, spatial_grid):
			continue
		# Find nearest province and skip if it's barren or tundra
		var nearest_biome := ""
		var nearest_d := 1.0e18
		for pd in all_province_data:
			var d: float = pt.distance_squared_to((pd as ProvinceData).center)
			if d < nearest_d:
				nearest_d = d
				nearest_biome = (pd as ProvinceData).biome
		if nearest_biome in ["desert", "mountain", "tundra"]:
			continue
		var edge_idx: int = EDGE_TEX_INDICES[rng.randi() % EDGE_TEX_INDICES.size()]
		result.append({ "pos": pt, "tex_idx": edge_idx, "flip": rng.randi() % 2 == 1 })
		_tree_grid_add(pt, spatial_grid)
		fill_placed += 1

	# Tundra fill pass — tundra/dead trees scattered across tundra zones
	var tundra_fill: int = 0
	var tundra_fill_count: int = tundra_centers.size() * 20
	var tundra_fill_attempts: int = 0
	var tundra_dead_count: int = tundra_start - dead_start
	var tundra_tex_count: int = tree_textures.size() - tundra_start
	if tundra_tex_count > 0:
		while tundra_fill < tundra_fill_count and tundra_fill_attempts < tundra_fill_count * 20:
			tundra_fill_attempts += 1
			if tundra_centers.is_empty():
				break
			var anchor: Vector2 = tundra_centers[rng.randi() % tundra_centers.size()]
			var pt := anchor + Vector2(rng.randf_range(-CLUSTER_RADIUS * 2.5, CLUSTER_RADIUS * 2.5),
					rng.randf_range(-CLUSTER_RADIUS * 2.5, CLUSTER_RADIUS * 2.5))
			if not Geometry2D.is_point_in_polygon(pt, continent_poly):
				continue
			if _dist_to_poly_edge(pt, continent_poly) < TREE_COAST_BUFFER:
				continue
			if _near_province(pt, province_centers):
				continue
			if _tree_too_close(pt, spatial_grid):
				continue
			# Confirm the candidate is actually in a tundra province
			var pt_biome := ""
			var pt_d := 1.0e18
			for pd in all_province_data:
				var d: float = pt.distance_squared_to((pd as ProvinceData).center)
				if d < pt_d:
					pt_d = d
					pt_biome = (pd as ProvinceData).biome
			if pt_biome != "tundra":
				continue
			var tr: float = rng.randf()
			var tex_idx: int
			if tr < 0.80:
				tex_idx = tundra_start + rng.randi() % tundra_tex_count
			elif tr < 0.95 and tundra_dead_count > 0:
				tex_idx = dead_start + rng.randi() % tundra_dead_count
			else:
				tex_idx = rng.randi() % dead_start
			result.append({ "pos": pt, "tex_idx": tex_idx, "flip": rng.randi() % 2 == 1 })
			_tree_grid_add(pt, spatial_grid)
			tundra_fill += 1

	# Extra dead tree scatter anchored around swamp provinces
	var swamp_centers: Array = []
	for item in map_data.provinces:
		var p := item as ProvinceData
		if p != null and str(p.biome) == "swamp":
			swamp_centers.append(p.center)
	var dead_extra: int = 0
	var dead_count_total: int = tundra_start - dead_start
	if not swamp_centers.is_empty() and dead_count_total > 0:
		const DEAD_EXTRA_COUNT: int = 80
		var de_attempts: int = 0
		while dead_extra < DEAD_EXTRA_COUNT and de_attempts < DEAD_EXTRA_COUNT * 30:
			de_attempts += 1
			var anchor: Vector2 = swamp_centers[rng.randi() % swamp_centers.size()]
			var pt := anchor + Vector2(rng.randf_range(-CLUSTER_RADIUS * 2.5, CLUSTER_RADIUS * 2.5),
					rng.randf_range(-CLUSTER_RADIUS * 2.5, CLUSTER_RADIUS * 2.5))
			if not Geometry2D.is_point_in_polygon(pt, continent_poly):
				continue
			if _dist_to_poly_edge(pt, continent_poly) < TREE_COAST_BUFFER:
				continue
			if _near_province(pt, province_centers):
				continue
			if _tree_too_close(pt, spatial_grid):
				continue
			var tex_idx: int = dead_start + rng.randi() % dead_count_total
			result.append({ "pos": pt, "tex_idx": tex_idx, "flip": rng.randi() % 2 == 1 })
			_tree_grid_add(pt, spatial_grid)
			dead_extra += 1

	biome_tree_counts["_outliers"] = outliers
	biome_tree_counts["_fill_edge"] = fill_placed
	biome_tree_counts["_tundra_fill"] = tundra_fill
	biome_tree_counts["_dead_extra"] = dead_extra
	biome_tree_counts["_total"] = result.size()
	DebugLogger.log("tree_placement", biome_tree_counts)

	return result


func _dist_to_poly_edge(pt: Vector2, poly: PackedVector2Array) -> float:
	var min_d := INF
	var n := poly.size()
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		var ab := b - a
		var len_sq := ab.dot(ab)
		var t := 0.0
		if len_sq > 0.0001:
			t = clampf((pt - a).dot(ab) / len_sq, 0.0, 1.0)
		min_d = minf(min_d, pt.distance_to(a + ab * t))
	return min_d
