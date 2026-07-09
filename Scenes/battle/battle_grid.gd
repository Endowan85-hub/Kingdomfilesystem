# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: BattleGrid
#
# Role:
# Renders the tactical grid in isometric perspective and
# forwards grid clicks to BattleScene.
#
# Tile layout:
#   - Each cell (x, y) maps to an isometric diamond
#   - TILE_W x TILE_H with visible side depth TILE_DEPTH
#   - Origin = top-vertex of cell (0,0) in screen space
#   - Draw order: back-to-front by (x+y) sum
#
# Allowed Interactions:
# - BattleScene
#
# Forbidden Responsibilities:
# - Must not modify GameState
# ==================================================

extends Node2D
class_name BattleGrid

# Maps long facing names (used internally) to the short codes in unit sprite filenames
const UNIT_DIR_SHORT : Dictionary = {
	"south": "s", "north": "n", "east": "e", "west": "w",
	"south-east": "se", "south-west": "sw", "north-east": "ne", "north-west": "nw"
}

const GRID_COLS  : int = 19
const GRID_ROWS  : int = 19
const TILE_W     : int = 128   # full diamond width  (2:1 ratio)
const TILE_H     : int = 64    # full diamond height
const TILE_DEPTH : int = 18    # visible side face height
const CAM_ZOOM   : float = 2.0  # how much to scale the grid
const CAM_SPEED  : float = 5.0  # camera lerp speed
const BORDER     : int   = 16    # extra tile rows/cols drawn outside the playable grid

var _cam_target   : Vector2 = Vector2.ZERO
var _dragging     : bool    = false
var _recentering  : bool    = false

# Computed at runtime from actual viewport size — covers 1920 and 2560 monitors
var _origin : Vector2 = Vector2.ZERO

var _scene_ref    = null
var _cloud_layer  = null   # BattleCloudLayer — set lazily on first push
var _attacker_units : Array = []
var _defender_units : Array = []
var _selected_unit  = null
var _player_side    : String = "attacker"
var _move_range_cells       : Array = []
var _attack_range_cells     : Array = []
var _skill_range_cells      : Array = []
var _skill_ally_range_cells : Array = []
var _active_unit    = null
var _flash_time     : float = 0.0
var _show_divider   : bool = false
var _deploy_zone_cells : Array = []

var _sprite_cache : Dictionary = {}
var _anim_cache   : Dictionary = {}
# battle_grid_template covers the full 19x19 playable area as one polygon
var _template_tex    : Texture2D  = null
# Dirt mega-clusters: 2×2 cells share UV sub-regions of the 256x128 mega texture
var _mega_tex        : Texture2D  = null
var _mega_tile_map   : Dictionary = {}   # Vector2i -> int quadrant 0-3
const MEGA_UVS := [
	[Vector2(0.5,0.0), Vector2(0.75,0.25), Vector2(0.5,0.5),  Vector2(0.25,0.25)],  # TL
	[Vector2(0.75,0.25),Vector2(1.0,0.5),  Vector2(0.75,0.75),Vector2(0.5,0.5) ],   # TR
	[Vector2(0.25,0.25),Vector2(0.5,0.5),  Vector2(0.25,0.75),Vector2(0.0,0.5) ],   # BL
	[Vector2(0.5,0.5),  Vector2(0.75,0.75),Vector2(0.5,1.0),  Vector2(0.25,0.75)],  # BR
]
# Grass patches: clusters sharing UV sub-regions of the 640x320 grass sheet
var _grass_sheet     : Texture2D  = null
var _grass_uvs       : Array      = []   # [25] PackedVector2Array, indexed by ly*5+lx
var _grass_patch_map : Dictionary = {}   # Vector2i -> int uv_index into _grass_uvs
# Swamp pit patches: same 5x5 mega-UV system on the pit sheet
var _pit_sheet       : Texture2D  = null
var _pit_placements  : Array      = []   # Array[Vector2i] — top-left corner of each 5×5 pit
var _pit_blocked     : Dictionary = {}   # Vector2i -> true for all cells inside a pit footprint
# World props: trees, stumps, skeletons drawn back-to-front after tiles
var _prop_textures   : Array      = []   # Array[Texture2D]
var _prop_placements : Array      = []   # [{cell, tex_idx, flip}]
var _prop_cell_map   : Dictionary = {}   # Vector2i -> tex_idx, for O(1) passability/LoS lookup

var _attacking : Dictionary = {}
const ANIM_FRAME_TIME      : float = 0.13
const IDLE_ANIM_FRAME_TIME : float = ANIM_FRAME_TIME * 2.0

signal walk_completed(unit)
var _walking : Dictionary = {}
const WALK_SPEED : float = 220.0


# ==================================================
# Init
# ==================================================
func _ready() -> void:
	add_to_group("battle_grid")
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scale = Vector2(CAM_ZOOM, CAM_ZOOM)
	_compute_origin()
	_load_textures()
	_build_grass_uvs()
	_build_patches()
	# Start camera centered on grid
	var mid := _cell_top(Vector2i(GRID_COLS / 2, GRID_ROWS / 2)) + Vector2(0, TILE_H * 0.5)
	_cam_target = mid
	var vp := get_viewport().get_visible_rect().size
	position = vp * 0.5 - _cam_target * CAM_ZOOM

func _load_textures() -> void:
	var b := "res://Art/tiles/biomes/swamp/"
	_try_load(b + "battle_grid_template.png", func(t): _template_tex = t)
	_try_load(b + "mega_grass_tile_1.png",    func(t): _mega_tex     = t)
	_try_load(b + "640x320grass.png",         func(t): _grass_sheet  = t)
	_try_load(b + "mega_swamp_pit.png",       func(t): _pit_sheet    = t)
	# Props — order determines tex_idx used in _prop_placements
	for name : String in ["swamp_tree_1.png","swamp_tree_2.png","swamp_tree_3.png","swamp_stump_1.png","swamp_skeleton_1.png"]:
		var p := b + name
		if ResourceLoader.exists(p):
			_prop_textures.append(load(p) as Texture2D)

func _try_load(path: String, setter: Callable) -> void:
	if ResourceLoader.exists(path):
		setter.call(load(path) as Texture2D)


func _build_grass_uvs() -> void:
	# 5×5 mega-tile UV derivation.
	# For a grid of N cols × M rows using a single texture:
	#   step = 1 / (N + M)  →  here 1/10 = 0.1
	#   top  = ((M + lx - ly) * step,  (lx + ly) * step)
	#   east = top + (step, step)
	#   south= top + (0, 2*step)
	#   west = top + (-step, step)
	const STEP := 0.1
	const M    := 5   # rows in sheet
	for ly in range(5):
		for lx in range(5):
			var tu := (M + lx - ly) * STEP
			var tv := (lx + ly) * STEP
			_grass_uvs.append(PackedVector2Array([
				Vector2(tu,        tv         ),  # top
				Vector2(tu + STEP, tv + STEP  ),  # east
				Vector2(tu,        tv + 2*STEP),  # south
				Vector2(tu - STEP, tv + STEP  ),  # west
			]))

func _build_patches() -> void:
	_mega_tile_map.clear()
	_grass_patch_map.clear()
	_pit_placements.clear()
	_pit_blocked.clear()
	_prop_placements.clear()
	_prop_cell_map.clear()
	var rng := RandomNumberGenerator.new()
	# No fixed seed — different layout every battle
	var used : Dictionary = {}

	# ── 1. Swamp pit — placed FIRST so 5×5 space is available ──────────────
	# The pit image (640×320) is designed as one complete isometric diamond over
	# a 5×5 tile area.  We store the top-left corner and draw it in one call.
	if _pit_sheet != null:
		var pit_count := 1
		var attempts := 0
		while pit_count > 0 and attempts < 300:
			attempts += 1
			var cx := rng.randi_range(0, GRID_COLS - 5)
			var cy := rng.randi_range(0, GRID_ROWS - 5)
			# Reject if any cell in the 5×5 footprint is already occupied
			var blocked := false
			for bx in range(cx, cx + 5):
				for by in range(cy, cy + 5):
					if used.has(Vector2i(bx, by)): blocked = true; break
				if blocked: break
			if blocked: continue
			_pit_placements.append(Vector2i(cx, cy))
			for bx in range(cx, cx + 5):
				for by in range(cy, cy + 5):
					var cell := Vector2i(bx, by)
					_pit_blocked[cell] = true
					used[cell] = true
			pit_count -= 1

	# ── 2. Dirt mega clusters (2×2 each) ────────────────────────────────────
	var mega_positions : Array = []
	var mega_count := rng.randi_range(3, 5)
	var attempts   := 0
	while mega_count > 0 and attempts < 300:
		attempts += 1
		var cx := rng.randi_range(2, GRID_COLS - 4)
		var cy := rng.randi_range(2, GRID_ROWS - 4)
		var blocked := false
		for bx in range(cx - 3, cx + 5):
			for by in range(cy - 3, cy + 5):
				if used.has(Vector2i(bx, by)):
					blocked = true; break
			if blocked: break
		if blocked:
			continue
		_mega_tile_map[Vector2i(cx,   cy  )] = 0
		_mega_tile_map[Vector2i(cx+1, cy  )] = 1
		_mega_tile_map[Vector2i(cx,   cy+1)] = 2
		_mega_tile_map[Vector2i(cx+1, cy+1)] = 3
		for lx in range(2):
			for ly in range(2):
				used[Vector2i(cx + lx, cy + ly)] = true
		mega_positions.append(Vector2i(cx, cy))
		mega_count -= 1

	# ── 3. Small grass patches scattered densely across the whole grid ───────
	var small_sizes := [[1,1],[1,1],[1,1],[1,2],[2,1],[1,3],[3,1],[2,2],[2,2],[3,2],[2,3]]
	var smalls := rng.randi_range(40, 60)
	attempts   = 0
	while smalls > 0 and attempts < 800:
		attempts += 1
		var pick : Array = small_sizes[rng.randi_range(0, small_sizes.size() - 1)]
		var sw   : int   = pick[0]
		var sh   : int   = pick[1]
		var cx := rng.randi_range(0, GRID_COLS - sw)
		var cy := rng.randi_range(0, GRID_ROWS - sh)
		var blocked := false
		for bx in range(cx, cx + sw):
			for by in range(cy, cy + sh):
				if used.has(Vector2i(bx, by)): blocked = true; break
			if blocked: break
		if blocked: continue
		_place_grass_patch(cx, cy, sw, sh, used)
		smalls -= 1

	# ── 4. Scatter world props on free cells ─────────────────────────────────
	# Load order: tree1=0, tree2=1, stump=2, skeleton=3
	const TREE1_IDX    := 0
	const TREE2_IDX    := 1
	const TREE3_IDX    := 2
	const STUMP_IDX    := 3
	const SKELETON_IDX := 4
	if not _prop_textures.is_empty():
		# Build the desired prop list upfront so the tree split is always even.
		var prop_total := rng.randi_range(8, 14)
		var prop_list  : Array = []

		# 1 skeleton (if loaded)
		if _prop_textures.size() > SKELETON_IDX:
			prop_list.append(SKELETON_IDX)

		# 1-2 stumps (if loaded)
		if _prop_textures.size() > STUMP_IDX:
			var stump_n := rng.randi_range(1, 2)
			for _s in range(stump_n):
				prop_list.append(STUMP_IDX)

		# Fill remaining slots cycling evenly across all loaded tree variants
		var tree_pool : Array = []
		for tidx in [TREE1_IDX, TREE2_IDX, TREE3_IDX]:
			if _prop_textures.size() > tidx:
				tree_pool.append(tidx)
		var trees_needed := prop_total - prop_list.size()
		for i in range(trees_needed):
			if tree_pool.size() > 0:
				prop_list.append(tree_pool[i % tree_pool.size()])

		# Randomise placement order so trees aren't always alternating spatially
		prop_list.shuffle()

		# Place each entry in a random free cell
		attempts = 0
		var list_idx := 0
		while list_idx < prop_list.size() and attempts < 600:
			attempts += 1
			var cx := rng.randi_range(1, GRID_COLS - 2)
			var cy := rng.randi_range(1, GRID_ROWS - 2)
			var cell := Vector2i(cx, cy)
			if used.has(cell): continue
			var pidx : int = prop_list[list_idx]
			_prop_placements.append({"cell": cell, "tex_idx": pidx, "flip": false})
			_prop_cell_map[cell] = pidx
			used[cell] = true
			list_idx += 1


func _place_grass_patch(cx: int, cy: int, sw: int, sh: int, used: Dictionary) -> void:
	# Centre the patch within the 5×5 UV grid on both axes independently
	var uv_ox := (5 - sw) / 2
	var uv_oy := (5 - sh) / 2
	for ly in range(sh):
		for lx in range(sw):
			var cell := Vector2i(cx + lx, cy + ly)
			_grass_patch_map[cell] = (ly + uv_oy) * 5 + (lx + uv_ox)
			used[cell] = true


func _compute_origin() -> void:
	var vp := get_viewport().get_visible_rect().size
	# Pin grid to fill edge-to-edge horizontally, top bar offset vertically
	_origin = Vector2(
		float(GRID_ROWS) * TILE_W * 0.5,
		36.0  # clear the 36px top bar
	)

# ==================================================
# Public API
# ==================================================
func set_scene(scene_ref) -> void:
	_scene_ref = scene_ref

func set_player_side(side: String) -> void:
	_player_side = side
	queue_redraw()

func set_units(attacker_units: Array, defender_units: Array) -> void:
	_attacker_units = attacker_units
	_defender_units = defender_units
	_cache_sprites()
	queue_redraw()

func set_selected_unit(unit) -> void:
	_selected_unit = unit
	queue_redraw()

func set_move_range_cells(cells: Array) -> void:
	_move_range_cells = cells
	queue_redraw()

func set_attack_range_cells(cells: Array) -> void:
	_attack_range_cells = cells
	queue_redraw()

func set_skill_range_cells(cells: Array, ally: bool = false) -> void:
	if ally:
		_skill_ally_range_cells = cells
		_skill_range_cells = []
	else:
		_skill_range_cells = cells
		_skill_ally_range_cells = []
	queue_redraw()

func clear_move_range() -> void:
	_move_range_cells       = []
	_attack_range_cells     = []
	_skill_range_cells      = []
	_skill_ally_range_cells = []
	queue_redraw()

func set_active_unit(unit) -> void:
	_active_unit = unit
	queue_redraw()

# Returns the screen-space position of a unit accounting for zoom and camera
func unit_screen_pos(unit) -> Vector2:
	return position + _unit_visual_pos(unit) * CAM_ZOOM

func set_divider_visible(show: bool) -> void:
	_show_divider = show
	queue_redraw()

func set_deploy_zone(cells: Array) -> void:
	_deploy_zone_cells = cells
	queue_redraw()


# ==================================================
# Sprite / animation cache
# ==================================================
# Maps a unit_type string (from UnitLibrary) to the sprite folder key under Art/units/.
# Folder: Art/units/{key}/sprites/
# Files:  unit_{key}_{dir}.png  |  unit_{key}_{anim}_{dir}_f{n}.png
func _unit_type_to_sprite_key(unit_type: String) -> String:
	match unit_type:
		# Plains
		"Militia Spearman":    return "militia_spearman"
		"Militia Swordsman":   return "militia_swordsman"
		"Militia Crossbowman": return "militia_crossbowman"
		"Light Rider":         return "light_rider"
		# Forest
		"Hunter":              return "hunter"
		"Forest Skirmisher":   return "forest_skirmisher"
		"Forest Rider":        return "forest_rider"
		# Mountain
		"Mountain Guard":      return "mountain_guard"
		"Stonebreaker":        return "stonebreaker"
		"Mountain Pikeman":    return "mountain_pikeman"
		# Desert
		"Sand Raider":         return "sand_raider"
		"Caravan Guard":       return "caravan_guard"
		"Dune Archer":         return "dune_archer"
		"Dust Crusher":        return "dust_crusher"
		# Tundra
		"Ice Warrior":         return "ice_warrior"
		"Ice Archer":          return "ice_archer"
		"Northern Raider":     return "northern_raider"
		# Swamp
		"Bog Fighter":         return "bog_fighter"
		"Reed Archer":         return "reed_archer"
		"Swamp Ambusher":      return "swamp_ambusher"
		# Coast
		"Marine":              return "marine"
		"Harpoon Fighter":     return "harpoon_fighter"
		"Boarding Infantry":   return "boarding_infantry"
		"Dockhand Brawler":    return "dockhand_brawler"
	return ""

# Returns the attack animation name for a given unit type.
# This controls both which files are cached and which are played during combat.
# Add new entries here when a unit uses a non-sword attack animation.
func _unit_attack_anim_key(unit_type: String) -> String:
	match unit_type:
		"Militia Spearman", "Mountain Pikeman", "Harpoon Fighter":
			return "spear_thrust"
		"Militia Crossbowman", "Dune Archer", "Ice Archer", "Reed Archer", "Hunter":
			return "bow_shoot"
	return "sword_slash"

func _leader_attack_anim_key(unit) -> String:
	var dt: String = str(unit.get("damage_type") if unit.get("damage_type") != null else "slash").to_lower()
	match dt:
		"blunt":  return "mace_swing"
		"pierce": return "spear_thrust"
	return "sword_slash"

func _cache_sprites() -> void:
	_sprite_cache.clear()
	_anim_cache.clear()
	var dirs := ["south","north","east","west","south-east","south-west","north-east","north-west"]
	for unit in _attacker_units + _defender_units:
		if unit == null or not unit.is_leader_combatant:
			continue
		var skey: String = str(unit.get("sprite_key") if unit.get("sprite_key") != null else "")
		if skey == "":
			continue
		for d in dirs:
			var path := "res://Art/leaders/%s/sprites/%s_%s.png" % [skey, skey, d]
			if ResourceLoader.exists(path):
				_sprite_cache[skey + "_" + d] = load(path) as Texture2D
		var attack_anim: String = _leader_attack_anim_key(unit)
		for anim_name in [attack_anim, "idle", "walk"]:
			for d in dirs:
				var base_key := "%s_%s_%s" % [skey, anim_name, d]
				var sheet_path := "res://Art/leaders/%s/sprites/%s_%s_%s_sheet.png" % [skey, skey, anim_name, d]
				if ResourceLoader.exists(sheet_path):
					_slice_anim_sheet(base_key, load(sheet_path) as Texture2D)
				else:
					var frame := 0
					while true:
						var path := "res://Art/leaders/%s/sprites/%s_%s_%s_f%d.png" % [skey, skey, anim_name, d, frame]
						if not ResourceLoader.exists(path):
							break
						_anim_cache["%s_%d" % [base_key, frame]] = load(path) as Texture2D
						frame += 1

	# ── Unit sprites (non-leaders) from Art/units/{key}/ ─────────────────────
	# Filenames use short direction codes: unit_spearman_s.png, unit_spearman_idle_s_f0.png
	var dirs_long := ["south","north","east","west","south-east","south-west","north-east","north-west"]
	for unit in _attacker_units + _defender_units:
		if unit == null or unit.is_leader_combatant:
			continue
		var utype : String = str(unit.unit_ref.unit_type if unit.unit_ref != null else "")
		var uskey : String = _unit_type_to_sprite_key(utype)
		if uskey == "":
			continue
		var prefix := "unit_%s" % uskey
		# Skip if already cached for this key
		if _sprite_cache.has("%s_south" % prefix):
			continue
		for d in dirs_long:
			var sd : String = UNIT_DIR_SHORT.get(d, "s")
			var path := "res://Art/units/%s/sprites/unit_%s_%s.png" % [uskey, uskey, sd]
			if ResourceLoader.exists(path):
				_sprite_cache["%s_%s" % [prefix, d]] = load(path) as Texture2D
		var attack_anim := _unit_attack_anim_key(utype)
		for anim_name in ["idle", "walk", attack_anim]:
			for d in dirs_long:
				var sd : String = UNIT_DIR_SHORT.get(d, "s")
				var base_key := "%s_%s_%s" % [prefix, anim_name, d]
				var sheet_path := "res://Art/units/%s/sprites/unit_%s_%s_%s_sheet.png" % [uskey, uskey, anim_name, sd]
				if ResourceLoader.exists(sheet_path):
					_slice_anim_sheet(base_key, load(sheet_path) as Texture2D)
				else:
					var frame := 0
					while true:
						var path := "res://Art/units/%s/sprites/unit_%s_%s_%s_f%d.png" % [uskey, uskey, anim_name, sd, frame]
						if not ResourceLoader.exists(path):
							break
						_anim_cache["%s_%d" % [base_key, frame]] = load(path) as Texture2D
						frame += 1


# Slices a horizontal spritesheet into individual AtlasTexture frames.
# Assumes square frames: frame_width = image_height, frame_count = image_width / image_height.
# Stores results in _anim_cache as "{base_key}_0", "{base_key}_1", etc.
func _slice_anim_sheet(base_key: String, tex: Texture2D) -> void:
	if tex == null:
		return
	var img_h := tex.get_height()
	if img_h == 0:
		return
	var frame_w := img_h  # each frame is square
	var frame_count := maxi(1, tex.get_width() / frame_w)
	for i in range(frame_count):
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(i * frame_w, 0, frame_w, img_h)
		_anim_cache["%s_%d" % [base_key, i]] = atlas


# ==================================================
# Walk / attack animation triggers
# ==================================================
func start_walk(unit, from_cell: Vector2i, to_cell: Vector2i) -> void:
	var from_px := _cell_center(from_cell)
	var to_px   := _cell_center(to_cell)
	_walking[unit] = {
		"from":     from_px,
		"to":       to_px,
		"dist":     maxf(from_px.distance_to(to_px), 1.0),
		"progress": 0.0
	}

func play_attack_anim(unit) -> void:
	var skey: String = str(unit.get("sprite_key") if unit.get("sprite_key") != null else "")
	if skey == "":
		return
	var facing: String = str(unit.get("facing") if unit.get("facing") != null else "south-east")
	var flip_h : bool   = facing == "south-west" or facing == "north-west"
	var lookup  : String = "south-east" if facing == "south-west" else ("north-east" if facing == "north-west" else facing)
	var attack_anim: String = _leader_attack_anim_key(unit)
	var frames: int = 0
	while _anim_cache.has("%s_%s_%s_%d" % [skey, attack_anim, lookup, frames]):
		frames += 1
	if frames == 0:
		return
	_attacking[unit] = {"skey": skey, "frames": frames, "frame_idx": 0, "timer": 0.0, "facing": facing, "attack_anim": attack_anim}


# ==================================================
# Process: advance animations
# ==================================================
func _process(delta: float) -> void:
	_flash_time += delta
	var needs_redraw := _active_unit != null or not _attacking.is_empty() or not _walking.is_empty()

	var atk_finished: Array = []
	for unit in _attacking:
		var anim: Dictionary = _attacking[unit]
		anim["timer"] += delta
		if anim["timer"] >= ANIM_FRAME_TIME:
			anim["timer"] -= ANIM_FRAME_TIME
			anim["frame_idx"] += 1
			if anim["frame_idx"] >= anim["frames"]:
				atk_finished.append(unit)
	for unit in atk_finished:
		_attacking.erase(unit)

	var walk_finished: Array = []
	for unit in _walking:
		var w: Dictionary = _walking[unit]
		w["progress"] += delta * WALK_SPEED / w["dist"]
		if w["progress"] >= 1.0:
			walk_finished.append(unit)
	for unit in walk_finished:
		_walking.erase(unit)
		walk_completed.emit(unit)

	if needs_redraw:
		queue_redraw()

	# Camera lerps to _cam_target only when Space triggers a recenter.
	# Dragging syncs _cam_target so releasing the mouse holds position.
	if _recentering:
		var vp := get_viewport().get_visible_rect().size
		var target_pos := vp * 0.5 - _cam_target * CAM_ZOOM
		position = position.lerp(target_pos, delta * CAM_SPEED)
		_push_cloud_offset()
		if position.distance_to(target_pos) < 1.0:
			position = target_pos
			_push_cloud_offset()
			_recentering = false


# ==================================================
# Draw
# ==================================================
func _draw() -> void:
	var C0 := -BORDER
	var C1 := GRID_COLS + BORDER
	var R0 := -BORDER
	var R1 := GRID_ROWS + BORDER

	var white4 := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])

	# --- Solid background covers the full extended border area ---
	var bg_top  := _cell_top(Vector2i(C0, R0))
	var bg_r    := _cell_top(Vector2i(C1 - 1, R0)) + Vector2( TILE_W * 0.5,  TILE_H * 0.5)
	var bg_bot  := _cell_top(Vector2i(C1 - 1, R1 - 1)) + Vector2(0.0, TILE_H)
	var bg_left := _cell_top(Vector2i(C0, R1 - 1)) + Vector2(-TILE_W * 0.5,  TILE_H * 0.5)
	var bg := Color(0.28, 0.35, 0.18)
	draw_polygon(PackedVector2Array([bg_top, bg_r, bg_bot, bg_left]),
		PackedColorArray([bg, bg, bg, bg]))

	# --- Template: single polygon covering the full 19×19 playable grid ---
	# The 2432×1216 image is already the isometric view of the grid, so the
	# standard diamond UVs map it correctly onto the playable area.
	if _template_tex != null:
		var t := _cell_top(Vector2i(0, 0))
		var r := _cell_top(Vector2i(GRID_COLS - 1, 0)) + Vector2(TILE_W * 0.5, TILE_H * 0.5)
		var b := _cell_top(Vector2i(GRID_COLS - 1, GRID_ROWS - 1)) + Vector2(0.0, TILE_H)
		var l := _cell_top(Vector2i(0, GRID_ROWS - 1)) + Vector2(-TILE_W * 0.5, TILE_H * 0.5)
		var d_uvs := PackedVector2Array([Vector2(0.5,0.0), Vector2(1.0,0.5), Vector2(0.5,1.0), Vector2(0.0,0.5)])
		draw_polygon(PackedVector2Array([t, r, b, l]), white4, d_uvs, _template_tex)

	# --- Grass patches on top of template: back-to-front ---
	# Non-patch cells are skipped — template shows through, saving draw calls.
	for depth_sum in range(GRID_COLS + GRID_ROWS - 1):
		for cx in range(GRID_COLS):
			var cy := depth_sum - cx
			if cy < 0 or cy >= GRID_ROWS:
				continue
			_draw_tile(Vector2i(cx, cy))

	# --- Swamp pits: each drawn as one textured diamond polygon ---
	# UV corners match the isometric diamond: top=(0.5,0) east=(1,0.5) south=(0.5,1) west=(0,0.5)
	if _pit_sheet != null:
		var pit_uvs := PackedVector2Array([
			Vector2(0.5, 0.0),
			Vector2(1.0, 0.5),
			Vector2(0.5, 1.0),
			Vector2(0.0, 0.5),
		])
		var pit_white := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
		for corner : Vector2i in _pit_placements:
			var pt := _cell_top(corner)
			var pe := _cell_top(Vector2i(corner.x + 4, corner.y)) + Vector2(TILE_W * 0.5, TILE_H * 0.5)
			var ps := _cell_top(Vector2i(corner.x + 4, corner.y + 4)) + Vector2(0.0, TILE_H)
			var pw := _cell_top(Vector2i(corner.x,     corner.y + 4)) + Vector2(-TILE_W * 0.5, TILE_H * 0.5)
			draw_polygon(PackedVector2Array([pt, pe, ps, pw]), pit_white, pit_uvs, _pit_sheet)

	# --- Deployment divider (column 9 / 10 boundary) ---
	if _show_divider:
		_draw_divider()

	# --- Props + units: single back-to-front pass (painter's algorithm) ---
	# Sort key = visual Y of each object's ground point so trees occlude units behind them.
	var draw_items: Array = []

	for prop in _prop_placements:
		var cell: Vector2i = prop["cell"]
		var ground_y: float = (_cell_top(cell) + Vector2(0.0, TILE_H)).y
		draw_items.append({"type": "prop", "key": ground_y, "prop": prop})

	var _is_att: Dictionary = {}
	for u in _attacker_units:
		if u != null:
			_is_att[u] = true
	for u in _defender_units:
		if u != null:
			_is_att[u] = false

	for u in _attacker_units + _defender_units:
		if u == null:
			continue
		draw_items.append({"type": "unit", "key": _unit_visual_pos(u).y, "unit": u})

	draw_items.sort_custom(func(a, b): return a["key"] < b["key"])

	for item in draw_items:
		if item["type"] == "prop":
			var prop = item["prop"]
			var cell: Vector2i  = prop["cell"]
			var tex : Texture2D = _prop_textures[prop["tex_idx"]]
			var sz  := tex.get_size()
			var ground := _cell_top(cell) + Vector2(0.0, TILE_H)
			draw_texture_rect(tex, Rect2(ground - Vector2(sz.x * 0.5, sz.y), sz), false, Color.WHITE)
		else:
			var unit = item["unit"]
			var is_att: bool = _is_att.get(unit, true)
			# Selection / active outline drawn just before the unit sprite
			if unit == _selected_unit:
				var top   := _cell_top(unit.grid_pos)
				var east  := top + Vector2( TILE_W * 0.5,  TILE_H * 0.5)
				var south := top + Vector2(0.0,            TILE_H)
				var west  := top + Vector2(-TILE_W * 0.5,  TILE_H * 0.5)
				draw_polyline(PackedVector2Array([top, east, south, west, top]),
					Color(1.0, 1.0, 0.3, 0.45), 2.5)
			if unit == _active_unit:
				var pulse := 0.5 + 0.5 * sin(_flash_time * 6.0)
				var top   := _cell_top(unit.grid_pos)
				var east  := top + Vector2( TILE_W * 0.5,  TILE_H * 0.5)
				var south := top + Vector2(0.0,            TILE_H)
				var west  := top + Vector2(-TILE_W * 0.5,  TILE_H * 0.5)
				draw_polyline(PackedVector2Array([top, east, south, west, top]),
					Color(1.0, 1.0, 1.0, 0.35 * pulse), 2.0)
			var player_color := Color(0.2, 0.75, 1.0)
			var enemy_color  := Color(1.0, 0.35, 0.35)
			var col: Color = player_color if (is_att == (_player_side == "attacker")) else enemy_color
			_draw_unit(unit, col)



func _draw_tile(cell: Vector2i) -> void:
	var top   := _cell_top(cell)
	var east  := top + Vector2( TILE_W * 0.5,  TILE_H * 0.5)
	var south := top + Vector2( 0.0,            TILE_H)
	var west  := top + Vector2(-TILE_W * 0.5,  TILE_H * 0.5)
	var pts   := PackedVector2Array([top, east, south, west])

	# Priority: dirt mega > grass patch > template (pits drawn separately as polygons)
	var white := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	if _mega_tile_map.has(cell) and _mega_tex != null:
		draw_polygon(pts, white, PackedVector2Array(MEGA_UVS[_mega_tile_map[cell]]), _mega_tex)
	elif _grass_patch_map.has(cell) and _grass_sheet != null:
		draw_polygon(pts, white, _grass_uvs[_grass_patch_map[cell]], _grass_sheet)

	# Highlight overlay
	const BLEND := 0.50
	var hl := Color(0, 0, 0, 0)
	if   _deploy_zone_cells.has(cell):      hl = Color(0.18, 0.72, 0.28, BLEND)
	elif _move_range_cells.has(cell):       hl = Color(0.18, 0.52, 1.00, BLEND)
	elif _attack_range_cells.has(cell):     hl = Color(1.00, 0.22, 0.22, BLEND)
	elif _skill_range_cells.has(cell):      hl = Color(0.78, 0.28, 1.00, BLEND)
	elif _skill_ally_range_cells.has(cell): hl = Color(0.18, 0.88, 0.38, BLEND)
	if hl.a > 0:
		draw_polygon(pts, PackedColorArray([hl, hl, hl, hl]))

	# Grid edge (hidden — uncomment to show)
	#draw_polyline(PackedVector2Array([top, east, south, west, top]),
		#Color(0.10, 0.12, 0.10, 0.4), 1.0)

	# Side faces (hidden — uncomment to restore depth strips)
	#var c_left  := Color(0.10, 0.14, 0.08)
	#var c_right := Color(0.07, 0.10, 0.05)
	#draw_polygon(PackedVector2Array([west, south, south + dv, west + dv]),
		#PackedColorArray([c_left, c_left, c_left.darkened(0.5), c_left.darkened(0.5)]))
	#draw_polygon(PackedVector2Array([south, east, east + dv, south + dv]),
		#PackedColorArray([c_right, c_right, c_right.darkened(0.5), c_right.darkened(0.5)]))
	#var edge_col := Color(0.05, 0.08, 0.04, 0.7)
	#draw_line(west,  west  + dv, edge_col, 1.0)
	#draw_line(south, south + dv, edge_col, 1.0)
	#draw_line(east,  east  + dv, edge_col, 1.0)
	#draw_line(west + dv,  south + dv, edge_col.darkened(0.2), 1.0)
	#draw_line(south + dv, east  + dv, edge_col.darkened(0.2), 1.0)


func _draw_divider() -> void:
	# Draw a glowing line along the east-ridge of column 9 (deploy boundary)
	for row in range(GRID_ROWS):
		var a := _cell_top(Vector2i(9, row)) + Vector2(TILE_W * 0.5, TILE_H * 0.5)
		var b := _cell_top(Vector2i(9, row + 1)) + Vector2(TILE_W * 0.5, TILE_H * 0.5) \
				if row + 1 < GRID_ROWS else \
				_cell_top(Vector2i(10, row)) + Vector2(-TILE_W * 0.5, TILE_H * 0.5)
		draw_line(a, b, Color(1.0, 0.9, 0.2, 0.35), 8.0)
		draw_line(a, b, Color(1.0, 0.85, 0.1, 0.90), 2.0)


func _draw_unit_shadow(foot: Vector2, radius: float) -> void:
	# Flat isometric ellipse — squish vertically to look like it lies on the ground plane
	draw_set_transform(foot, 0.0, Vector2(1.0, 0.38))
	draw_circle(Vector2.ZERO, radius, Color(0.0, 0.0, 0.0, 0.28))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_unit(unit, color: Color) -> void:
	if unit == null or not unit.is_alive:
		return

	var foot := _unit_visual_pos(unit)

	# Shadow — drawn at the tile foot reference point, squished into an isometric ellipse.
	var shadow_radius := 26.0 if unit.is_leader_combatant else 20.0
	_draw_unit_shadow(foot, shadow_radius)

	# sprite_top_y — top of the drawn sprite; fallback for circle units
	var sprite_top_y: float = foot.y - 30.0

	# --- Try sprite / animation frames ---
	var sprite_drawn := false
	if unit.is_leader_combatant:
		var skey: String  = str(unit.get("sprite_key") if unit.get("sprite_key") != null else "")
		var facing: String = str(unit.get("facing")    if unit.get("facing")    != null else "south-east")
		# SW mirrors SE; NW mirrors NE — only SE and NE need real art files
		var flip_h  : bool   = facing == "south-west" or facing == "north-west"
		var lookup  : String = "south-east" if facing == "south-west" else ("north-east" if facing == "north-west" else facing)
		var tex: Texture2D = null

		if _attacking.has(unit):
			var anim: Dictionary = _attacking[unit]
			var atk_anim: String = str(anim.get("attack_anim", "sword_slash"))
			tex = _anim_cache.get("%s_%s_%s_%d" % [skey, atk_anim, lookup, anim["frame_idx"]], null)

		if tex == null and _walking.has(unit):
			var wfc := 0
			while _anim_cache.has("%s_walk_%s_%d" % [skey, lookup, wfc]):
				wfc += 1
			if wfc > 0:
				tex = _anim_cache.get("%s_walk_%s_%d" % [skey, lookup, int(_flash_time / ANIM_FRAME_TIME) % wfc], null)

		if tex == null:
			var ifc := 0
			while _anim_cache.has("%s_idle_%s_%d" % [skey, lookup, ifc]):
				ifc += 1
			if ifc > 0:
				tex = _anim_cache.get("%s_idle_%s_%d" % [skey, lookup, int(_flash_time / IDLE_ANIM_FRAME_TIME) % ifc], null)

		if tex == null:
			tex = _sprite_cache.get(skey + "_" + lookup, null)

		if tex != null:
			var sz  := tex.get_size()
			var dsz := sz   # raw size — no scaling
			var top_left := foot - Vector2(dsz.x * 0.5, dsz.y - TILE_H * 0.65)
			sprite_top_y = top_left.y
			if flip_h:
				draw_texture_rect(tex, Rect2(Vector2(top_left.x + dsz.x, top_left.y), Vector2(-dsz.x, dsz.y)), false)
			else:
				draw_texture_rect(tex, Rect2(top_left, dsz), false)
			sprite_drawn = true

	# ── Non-leader unit sprites ───────────────────────────────────────────────
	if not sprite_drawn and unit.unit_ref != null:
		var utype  : String = str(unit.unit_ref.unit_type if unit.unit_ref != null else "")
		var uskey  : String = _unit_type_to_sprite_key(utype)
		if uskey != "":
			var prefix : String = "unit_%s" % uskey
			var facing : String = str(unit.get("facing") if unit.get("facing") != null else "south-east")
			# SW mirrors SE; NW mirrors NE — only SE and NE need real art files
			var flip_h  : bool   = facing == "south-west" or facing == "north-west"
			var lookup  : String = "south-east" if facing == "south-west" else ("north-east" if facing == "north-west" else facing)
			var tex : Texture2D = null

			if _attacking.has(unit):
				var anim : Dictionary = _attacking[unit]
				var atk_anim := _unit_attack_anim_key(utype)
				tex = _anim_cache.get("%s_%s_%s_%d" % [prefix, atk_anim, lookup, anim["frame_idx"]], null)

			if tex == null and _walking.has(unit):
				var wfc := 0
				while _anim_cache.has("%s_walk_%s_%d" % [prefix, lookup, wfc]):
					wfc += 1
				if wfc > 0:
					tex = _anim_cache.get("%s_walk_%s_%d" % [prefix, lookup, int(_flash_time / ANIM_FRAME_TIME) % wfc], null)

			if tex == null:
				var ifc := 0
				while _anim_cache.has("%s_idle_%s_%d" % [prefix, lookup, ifc]):
					ifc += 1
				if ifc > 0:
					tex = _anim_cache.get("%s_idle_%s_%d" % [prefix, lookup, int(_flash_time / IDLE_ANIM_FRAME_TIME) % ifc], null)

			if tex == null:
				tex = _sprite_cache.get("%s_%s" % [prefix, lookup], null)

			if tex != null:
				var sz  := tex.get_size()
				var dsz := sz   # raw size — no scaling
				var top_left := foot - Vector2(dsz.x * 0.5, dsz.y - TILE_H * 0.65)
				sprite_top_y = top_left.y
				if flip_h:
					draw_texture_rect(tex, Rect2(Vector2(top_left.x + dsz.x, top_left.y), Vector2(-dsz.x, dsz.y)), false)
				else:
					draw_texture_rect(tex, Rect2(top_left, dsz), false)
				sprite_drawn = true

	if not sprite_drawn:
		draw_circle(foot, 14.0, color)

	_draw_unit_hud(unit, foot, sprite_top_y)


func _draw_unit_hud(unit, foot: Vector2, sprite_top_y: float) -> void:
	var hp_ratio: float = clampf(float(unit.battle_hp) / float(maxi(1, unit.final_max_hp)), 0.0, 1.0)

	var level: int = 1
	if unit.is_leader_combatant and unit.leader_ref != null and "level" in unit.leader_ref:
		level = int(unit.leader_ref.level)
	elif not unit.is_leader_combatant and unit.unit_ref != null and "level" in unit.unit_ref:
		level = int(unit.unit_ref.level)

	var font      := ThemeDB.fallback_font
	var font_size := 10
	var lv_text   := str(level)
	var lv_w      := font.get_string_size(lv_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var ascent    := font.get_ascent(font_size)

	const BAR_W   := 36.0
	const BAR_H   := 5.0
	const GAP     := 3.0
	const OUTLINE := 1.0

	var total_w := lv_w + GAP + BAR_W
	var hud_y   := sprite_top_y - 10.0
	var hud_x   := foot.x - total_w * 0.5

	# Level number (bold black outline, white for allies / red for enemies)
	var is_enemy: bool = str(unit.get("side") if unit.get("side") != null else "") != _player_side
	var lv_color: Color = Color(1.0, 0.25, 0.25) if is_enemy else Color.WHITE
	var lv_baseline := hud_y + BAR_H * 0.5 + ascent * 0.5
	var lv_pos := Vector2(hud_x, lv_baseline)
	draw_string_outline(font, lv_pos, lv_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 2, Color.BLACK)
	draw_string(font, lv_pos, lv_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, lv_color)

	# HP bar
	var bar_x := hud_x + lv_w + GAP
	var bar_y := hud_y

	# Black outline border
	draw_rect(Rect2(bar_x - OUTLINE, bar_y - OUTLINE, BAR_W + OUTLINE * 2.0, BAR_H + OUTLINE * 2.0), Color.BLACK)

	# Dark background
	draw_rect(Rect2(bar_x, bar_y, BAR_W, BAR_H), Color(0.12, 0.12, 0.12))

	# HP fill
	var fill_w := BAR_W * hp_ratio
	var hp_color: Color
	if is_enemy:
		hp_color = Color(0.9, 0.15, 0.15)
	else:
		hp_color = Color(0.2, 0.82, 0.2)
	if fill_w > 0.0:
		draw_rect(Rect2(bar_x, bar_y, fill_w, BAR_H), hp_color)



# Push current position to the cloud shader immediately (no polling lag).
func _push_cloud_offset() -> void:
	if _cloud_layer == null or not is_instance_valid(_cloud_layer):
		_cloud_layer = get_tree().get_first_node_in_group("battle_cloud_layer")
	if _cloud_layer == null:
		return
	_cloud_layer.set_grid_position(position, get_viewport().get_visible_rect().size)

# ==================================================
# Input
# ==================================================
func _unit_at_screen(local_pos: Vector2):
	# Returns the unit whose sprite bounding box contains local_pos, or null.
	# Sprites are 48x48, grounded so top = foot.y - 6, bottom = foot.y + 42.
	# Used so units behind props can still be clicked.
	var best = null
	var best_dist := INF
	for unit in _attacker_units + _defender_units:
		if unit == null or not unit.is_alive:
			continue
		var foot := _unit_visual_pos(unit)
		var dx := local_pos.x - foot.x
		var dy := local_pos.y - foot.y
		if abs(dx) <= 26.0 and dy >= -14.0 and dy <= 44.0:
			var dist := Vector2(dx, dy).length()
			if dist < best_dist:
				best_dist = dist
				best = unit
	return best


func _unhandled_input(event: InputEvent) -> void:
	# --- Left click: grid cell selection ---
	# Uses _unhandled_input so UI elements (popup buttons etc.) consume the event first
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local := to_local(event.position)
		var cell  := _screen_to_cell(local)
		# Unit sprite hit-test overrides the raw cell so units behind props are selectable.
		var hit = _unit_at_screen(local)
		if hit != null:
			cell = hit.grid_pos
		if cell.x >= 0 and cell.y >= 0 and cell.x < GRID_COLS and cell.y < GRID_ROWS:
			if _scene_ref != null:
				_scene_ref.on_grid_clicked(cell)

func _input(event: InputEvent) -> void:
	# --- Middle mouse: drag camera ---
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_dragging = event.pressed

	if event is InputEventMouseMotion and _dragging:
		position += event.relative
		_push_cloud_offset()
		# Sync _cam_target so lerp doesn't fight the drag when released
		var vp := get_viewport().get_visible_rect().size
		_cam_target = (vp * 0.5 - position) / CAM_ZOOM

	# --- Space: recenter on active/selected unit ---
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			var focus = _active_unit if _active_unit != null else _selected_unit
			if focus != null:
				_cam_target = _unit_visual_pos(focus)
				_recentering = true


# ==================================================
# Coordinate helpers
# ==================================================
func _cell_top(cell: Vector2i) -> Vector2:
	# Top vertex (northernmost point) of the isometric diamond for this cell
	return _origin+ Vector2(
		float(cell.x - cell.y) * TILE_W * 0.5,
		float(cell.x + cell.y) * TILE_H * 0.5
	)

func _cell_center(cell: Vector2i) -> Vector2:
	# Center of the tile diamond face — walk target and unit stand point
	return _cell_top(cell) + Vector2(0.0, TILE_H * 0.5)

func cell_to_screen(cell: Vector2i) -> Vector2:
	# Returns the screen-space position of a cell center (accounts for camera drag + zoom)
	return position + _cell_center(cell) * CAM_ZOOM

func _unit_visual_pos(unit) -> Vector2:
	# Foot position: south point of tile diamond, lerped during walk
	if _walking.has(unit):
		var w: Dictionary = _walking[unit]
		return w["from"].lerp(w["to"], w["progress"])
	return _cell_center(unit.grid_pos)

func _screen_to_cell(screen_pos: Vector2) -> Vector2i:
	# Inverse isometric transform:
	#   iso_x = (cx - cy) * TILE_W/2  →  cx = local.x/TILE_W + local.y/TILE_H
	#   iso_y = (cx + cy) * TILE_H/2  →  cy = local.y/TILE_H - local.x/TILE_W
	var local := screen_pos - _origin
	var cx := local.x / float(TILE_W) + local.y / float(TILE_H)
	var cy := local.y / float(TILE_H) - local.x / float(TILE_W)
	return Vector2i(floori(cx), floori(cy))


# ==================================================
# Terrain Passability & Line of Sight
# ==================================================

# Returns false if the cell contains an impassable terrain feature.
# Props (any), dirt mega-clusters, and swamp pit tiles all block movement.
func is_cell_passable(cell: Vector2i) -> bool:
	if _prop_cell_map.has(cell):   return false   # any prop blocks movement
	if _mega_tile_map.has(cell):   return false   # dirt cluster
	if _pit_blocked.has(cell):     return false   # swamp pit
	return true

# Returns true if the cell contains a tree prop (the only terrain that
# blocks archer line of sight). Stumps, skeletons, and ground tiles are
# transparent to ranged attacks.
func is_cell_los_blocker(cell: Vector2i) -> bool:
	if _prop_cell_map.has(cell):
		var tidx : int = _prop_cell_map[cell]
		return tidx == 0 or tidx == 1 or tidx == 2   # TREE1/2/3_IDX
	return false

func has_line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	var cells := _bresenham_cells(from, to)
	var occupied: Dictionary = {}
	for u in _attacker_units:
		if u != null and bool(u.is_alive) and not ("is_captured" in u and bool(u.is_captured)):
			occupied[u.grid_pos] = true
	for u in _defender_units:
		if u != null and bool(u.is_alive) and not ("is_captured" in u and bool(u.is_captured)):
			occupied[u.grid_pos] = true
	for i in range(1, cells.size() - 1):
		if occupied.has(cells[i]):
			return false
		if is_cell_los_blocker(cells[i]):   # trees block archer LoS
			return false
	return true

func _bresenham_cells(from: Vector2i, to: Vector2i) -> Array:
	var cells: Array = []
	var x0: int = from.x
	var y0: int = from.y
	var x1: int = to.x
	var y1: int = to.y
	var dx: int = abs(x1 - x0)
	var dy: int = abs(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx - dy
	while true:
		cells.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy
	return cells
