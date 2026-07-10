extends RefCounted
class_name MapGenerator

const FactionDataScript := preload("res://Scripts/map/faction_data.gd")

func generate_map(settings: MapSettings) -> MapData:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if settings.seed == 0:
		rng.randomize()
	else:
		rng.seed = settings.seed

	var map_data: MapData = MapData.new()
	map_data.map_name = "Generated Map"

	var points: Array = _generate_points(settings, rng)
	var provinces: Array = _create_provinces(points)
	var routes: Array = _generate_graph(settings, provinces, rng)

	# Geography lines
	var river: Array = []
	var mountains: Array = []

	if settings.enable_river:
		river = _generate_river_polyline(settings, rng)
	if settings.enable_mountains:
		mountains = _generate_mountain_polyline(settings, rng)

	_apply_geography_with_chokepoints(settings, provinces, routes, river, mountains, rng)
	ProvinceNameLibrary.assign_names(provinces, rng)

	map_data.map_seed = rng.seed
	map_data.provinces = provinces
	map_data.routes = routes
	map_data.adjacency = _build_adjacency(routes)

	map_data.river_polyline = river
	map_data.mountain_polyline = mountains

	_evaluate_provinces(settings, map_data)
	_create_factions_and_assign_owners(map_data, rng)

	# Summarise biome spread for diagnostics
	var biome_counts: Dictionary = {}
	for prov in map_data.provinces:
		var b: String = str((prov as ProvinceData).biome)
		biome_counts[b] = biome_counts.get(b, 0) + 1
	DebugLogger.log("map_generated", {
		"province_count": map_data.provinces.size(),
		"route_count": map_data.routes.size(),
		"seed": rng.seed,
		"map_size": str(settings.map_size),
		"biomes": biome_counts,
		"has_river": map_data.river_polyline.size() > 0,
		"has_mountains": map_data.mountain_polyline.size() > 0,
	})

	return map_data


func _generate_points(settings: MapSettings, rng: RandomNumberGenerator) -> Array:
	var points: Array = []
	var attempts: int = 0
	var max_attempts: int = settings.province_count * 100

	while points.size() < settings.province_count and attempts < max_attempts:
		var px: float = rng.randf_range(0.0, settings.map_size.x)
		var py: float = rng.randf_range(0.0, settings.map_size.y)
		var p: Vector2 = Vector2(px, py)

		var valid: bool = true
		for existing in points:
			var e: Vector2 = existing
			if e.distance_to(p) < settings.min_point_distance:
				valid = false
				break

		if valid:
			points.append(p)

		attempts += 1

	for _pass in range(settings.relaxation_passes):
		points = _relax_points(points, settings)

	return points


func _relax_points(points: Array, settings: MapSettings) -> Array:
	var relaxed: Array = points.duplicate()
	for i in range(relaxed.size()):
		var force: Vector2 = Vector2.ZERO
		var pi: Vector2 = relaxed[i]

		for j in range(relaxed.size()):
			if i == j:
				continue
			var pj: Vector2 = relaxed[j]
			var d: float = pi.distance_to(pj)
			if d > 0.0 and d < settings.min_point_distance:
				var push: Vector2 = (pi - pj).normalized() * (settings.min_point_distance - d) * 0.05
				force += push

		pi += force
		pi.x = clamp(pi.x, 0.0, settings.map_size.x)
		pi.y = clamp(pi.y, 0.0, settings.map_size.y)
		relaxed[i] = pi

	return relaxed


func _create_provinces(points: Array) -> Array:
	var provinces: Array = []
	for i in range(points.size()):
		var p: ProvinceData = ProvinceData.new()
		p.id = i
		p.display_name = "Province %d" % i
		p.center = points[i]
		p.owner_id = -1
		p.fort_level = 1
		provinces.append(p)
	return provinces


func _generate_graph(settings: MapSettings, provinces: Array, rng: RandomNumberGenerator) -> Array:
	var routes: Array = []
	if provinces.is_empty():
		return routes

	var connected: Dictionary = {}
	connected[0] = true

	while connected.size() < provinces.size():
		var best_a: int = -1
		var best_b: int = -1
		var best_dist: float = INF

		for a_id in connected.keys():
			var a_center: Vector2 = provinces[int(a_id)].center
			for b in provinces:
				var bp: ProvinceData = b
				if connected.has(bp.id):
					continue
				var d: float = a_center.distance_to(bp.center)
				if d < best_dist:
					best_dist = d
					best_a = int(a_id)
					best_b = bp.id

		if best_a == -1 or best_b == -1:
			break

		connected[best_b] = true
		routes.append(_create_route(settings, provinces[best_a], provinces[best_b]))

	for a in provinces:
		var ap: ProvinceData = a
		var neighbors: Array = _k_nearest(ap, provinces, settings.neighbor_k)
		for b in neighbors:
			var bp: ProvinceData = b
			if ap.id == bp.id:
				continue
			if _route_exists(routes, ap.id, bp.id):
				continue
			if rng.randf() < settings.extra_edge_density:
				routes.append(_create_route(settings, ap, bp))

	# Prune redundant routes: remove A->B if a two-hop A->C->B path exists
	# whose total distance <= direct * 1.5. Keeps map roads feeling natural.
	var pruned: Array = []
	for r in routes:
		var rr: RouteData = r
		var a_id: int = int(rr.a)
		var b_id: int = int(rr.b)
		var direct_dist: float = float(rr.distance)
		var is_redundant: bool = false
		for c in provinces:
			var cp: ProvinceData = c
			if cp.id == a_id or cp.id == b_id:
				continue
			if _route_exists(routes, a_id, cp.id) and _route_exists(routes, cp.id, b_id):
				var hop1: float = provinces[a_id].center.distance_to(cp.center)
				var hop2: float = cp.center.distance_to(provinces[b_id].center)
				if hop1 + hop2 <= direct_dist * 1.5:
					is_redundant = true
					break
		if not is_redundant:
			pruned.append(r)
	routes = pruned

	return routes


func _k_nearest(a: ProvinceData, provinces: Array, k: int) -> Array:
	var pairs: Array = []
	for b in provinces:
		var bp: ProvinceData = b
		if bp.id == a.id:
			continue
		var d: float = a.center.distance_to(bp.center)
		pairs.append({"p": bp, "d": d})

	pairs.sort_custom(func(x, y): return float(x["d"]) < float(y["d"]))

	var out: Array = []
	for i in range(min(k, pairs.size())):
		out.append(pairs[i]["p"])

	return out


func _create_route(settings: MapSettings, a: ProvinceData, b: ProvinceData) -> RouteData:
	var r: RouteData = RouteData.new()
	r.a = a.id
	r.b = b.id
	r.distance = a.center.distance_to(b.center)

	var cost_f: float = ceil(r.distance / settings.distance_cost_scale)
	var cost: int = int(cost_f)
	r.base_cost = clamp(cost, settings.min_route_cost, settings.max_route_cost)

	r.extra_cost = 0
	r.is_blocked = false
	r.tags = []

	return r


func _route_exists(routes: Array, a: int, b: int) -> bool:
	for r in routes:
		var rr: RouteData = r
		if (rr.a == a and rr.b == b) or (rr.a == b and rr.b == a):
			return true
	return false


func _build_adjacency(routes: Array) -> Dictionary:
	var adj: Dictionary = {}
	for r in routes:
		var rr: RouteData = r
		if not adj.has(rr.a):
			adj[rr.a] = []
		if not adj.has(rr.b):
			adj[rr.b] = []
		adj[rr.a].append(rr.b)
		adj[rr.b].append(rr.a)
	return adj


# -----------------------------
# Geography + Chokepoints
# -----------------------------

func _generate_river_polyline(settings: MapSettings, rng: RandomNumberGenerator) -> Array:
	var pts: Array = []
	var count: int = max(2, settings.river_points)

	var start_y: float = rng.randf_range(0.15, 0.85) * settings.map_size.y
	var end_y: float = rng.randf_range(0.15, 0.85) * settings.map_size.y

	var start: Vector2 = Vector2(0.0, start_y)
	var end: Vector2 = Vector2(settings.map_size.x, end_y)

	pts.append(start)

	for i in range(1, count - 1):
		var t: float = float(i) / float(count - 1)
		var x: float = lerp(0.0, settings.map_size.x, t)
		var wiggle: float = rng.randf_range(-0.20, 0.20) * settings.map_size.y
		var y: float = lerp(start.y, end.y, t) + wiggle
		y = clamp(y, 0.0, settings.map_size.y)
		pts.append(Vector2(x, y))

	pts.append(end)
	return pts


func _generate_mountain_polyline(settings: MapSettings, rng: RandomNumberGenerator) -> Array:
	var pts: Array = []
	var count: int = max(2, settings.mountain_points)

	var start_x: float = rng.randf_range(0.15, 0.85) * settings.map_size.x
	var end_x: float = rng.randf_range(0.15, 0.85) * settings.map_size.x

	var start: Vector2 = Vector2(start_x, 0.0)
	var end: Vector2 = Vector2(end_x, settings.map_size.y)

	pts.append(start)

	for i in range(1, count - 1):
		var t: float = float(i) / float(count - 1)
		var y: float = lerp(0.0, settings.map_size.y, t)
		var wiggle: float = rng.randf_range(-0.20, 0.20) * settings.map_size.x
		var x: float = lerp(start.x, end.x, t) + wiggle
		x = clamp(x, 0.0, settings.map_size.x)
		pts.append(Vector2(x, y))

	pts.append(end)
	return pts


func _apply_geography_with_chokepoints(
	settings: MapSettings,
	provinces: Array,
	routes: Array,
	river: Array,
	mountains: Array,
	rng: RandomNumberGenerator
) -> void:
	var river_crossings: Array = []
	var mountain_crossings: Array = []

	for r in routes:
		var rr: RouteData = r
		var a_center: Vector2 = provinces[rr.a].center
		var b_center: Vector2 = provinces[rr.b].center

		if settings.enable_river and river.size() >= 2:
			if _segment_intersects_polyline(a_center, b_center, river):
				river_crossings.append(rr)

		if settings.enable_mountains and mountains.size() >= 2:
			if _segment_intersects_polyline(a_center, b_center, mountains):
				mountain_crossings.append(rr)

	var bridges: Dictionary = {}
	var bridge_target: int = min(settings.bridge_count, river_crossings.size())
	_pick_random_routes(river_crossings, bridge_target, bridges, rng)

	var passes: Dictionary = {}
	var pass_target: int = min(settings.mountain_pass_count, mountain_crossings.size())
	_pick_random_routes(mountain_crossings, pass_target, passes, rng)

	for r in routes:
		var rr: RouteData = r
		rr.extra_cost = 0
		rr.tags = []

		var a_center2: Vector2 = provinces[rr.a].center
		var b_center2: Vector2 = provinces[rr.b].center

		if settings.enable_river and river.size() >= 2:
			if _segment_intersects_polyline(a_center2, b_center2, river):
				if bridges.has(rr):
					rr.tags.append(&"bridge")
				else:
					rr.extra_cost += settings.river_crossing_extra_cost
					rr.tags.append(&"river_crossing")

		if settings.enable_mountains and mountains.size() >= 2:
			if _segment_intersects_polyline(a_center2, b_center2, mountains):
				if passes.has(rr):
					rr.tags.append(&"mountain_pass")
				else:
					rr.extra_cost += settings.mountain_crossing_extra_cost
					rr.tags.append(&"mountain_crossing")


func _pick_random_routes(pool: Array, count: int, out_dict: Dictionary, rng: RandomNumberGenerator) -> void:
	if count <= 0:
		return

	var indices: Array = []
	for i in range(pool.size()):
		indices.append(i)

	for i in range(indices.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = indices[i]
		indices[i] = indices[j]
		indices[j] = tmp

	for n in range(count):
		var rr: RouteData = pool[indices[n]]
		out_dict[rr] = true


func _segment_intersects_polyline(a: Vector2, b: Vector2, poly: Array) -> bool:
	for i in range(poly.size() - 1):
		var p1: Vector2 = poly[i]
		var p2: Vector2 = poly[i + 1]
		if Geometry2D.segment_intersects_segment(a, b, p1, p2) != null:
			return true
	return false


# -----------------------------
# Province Gameplay Evaluation
# -----------------------------

func _evaluate_provinces(_settings: MapSettings, map_data: MapData) -> void:
	var adj: Dictionary = map_data.adjacency

	for p in map_data.provinces:
		var connections: int = 0
		if adj.has(p.id):
			connections = (adj[p.id] as Array).size()

		p.base_income = 80 + connections * 15
		p.population = 100 + connections * 25

		p.is_bridge_hub = false
		p.is_mountain_pass_hub = false

		for r in map_data.routes:
			if r.a == p.id or r.b == p.id:
				if r.tags.has(&"bridge"):
					p.is_bridge_hub = true
				if r.tags.has(&"mountain_pass"):
					p.is_mountain_pass_hub = true

		var bonus: int = 0
		if p.is_bridge_hub:
			bonus += 25
		if p.is_mountain_pass_hub:
			bonus += 20

		p.income = p.base_income + bonus
		p.defense_value = p.fort_level * 5 + connections * 3

		if connections <= 2:
			p.is_chokepoint = true
			p.defense_value += 8
		else:
			p.is_chokepoint = false

		p.strategic_value = float(p.income) * 0.6 + float(p.defense_value) * 0.4

	_assign_biomes(map_data)


func _assign_biomes(map_data: MapData) -> void:
	var provinces: Array = map_data.provinces
	if provinces.size() == 0:
		return

	var river: Array = map_data.river_polyline
	var mountains: Array = map_data.mountain_polyline

	# Map bounds
	var min_x: float = INF; var max_x: float = -INF
	var min_y: float = INF; var max_y: float = -INF
	for item in provinces:
		var p: ProvinceData = item as ProvinceData
		min_x = minf(min_x, p.center.x); max_x = maxf(max_x, p.center.x)
		min_y = minf(min_y, p.center.y); max_y = maxf(max_y, p.center.y)
	var map_w: float = max(max_x - min_x, 1.0)
	var map_h: float = max(max_y - min_y, 1.0)

	# Geography reference points
	var mountain_avg_x: float = _polyline_avg_x(mountains, map_w) * map_w + min_x
	var river_avg_y: float = _polyline_avg_y(river, map_h) * map_h + min_y

	# Build adjacency lookup from routes
	var adj: Dictionary = {}
	for item in provinces:
		var p: ProvinceData = item as ProvinceData
		adj[p.id] = []
	for r in map_data.routes:
		var rr: RouteData = r as RouteData
		(adj[rr.a] as Array).append(rr.b)
		(adj[rr.b] as Array).append(rr.a)

	# --- STEP 1: Score every province for each biome candidate ---
	# Each province gets a score per biome. Highest score wins the seed.
	# Then flood-fill from seeds through the adjacency graph so biomes are contiguous.

	# Biome score function: returns how "suitable" a province is for a biome
	# Higher = better seed candidate
	var biome_scores: Dictionary = {}
	for item in provinces:
		var p: ProvinceData = item as ProvinceData
		var cx: float = p.center.x
		var cy: float = p.center.y
		var nx: float = (cx - min_x) / map_w
		var ny: float = (cy - min_y) / map_h

		var near_left_edge: bool = nx < 0.12
		var near_right_edge: bool = nx > 0.88
		var near_top_edge: bool = ny < 0.12
		var near_bottom_edge: bool = ny > 0.88
		var near_any_edge: bool = near_left_edge or near_right_edge or near_top_edge or near_bottom_edge

		var dist_to_mountain: float = _dist_to_polyline(p.center, mountains)
		var dist_to_river: float = _dist_to_polyline(p.center, river)

		var west_of_mountains: bool = cx < mountain_avg_x
		var north_of_river: bool = cy < river_avg_y

		var scores: Dictionary = {
			"coast":    0.0,
			"mountain": 0.0,
			"tundra":   0.0,
			"desert":   0.0,
			"forest":   0.0,
			"swamp":    0.0,
			"plains":   0.0,
		}

		# Coast: strongly prefer left/right edges, weakly allow top/bottom
		if near_left_edge or near_right_edge:
			scores["coast"] = 1.0 - nx if near_left_edge else nx
		elif near_top_edge or near_bottom_edge:
			scores["coast"] = 0.3

		# Mountain: prefer provinces closest to the mountain polyline, not on edges
		if not near_any_edge:
			scores["mountain"] = max(0.0, 1.0 - (dist_to_mountain / (map_w * 0.25)))

		# Tundra: NW — west of mountains, top portion
		if west_of_mountains and north_of_river and not near_any_edge:
			scores["tundra"] = (1.0 - nx) * (1.0 - ny)

		# Desert: SW — west of mountains, bottom portion
		if west_of_mountains and not north_of_river and not near_any_edge:
			scores["desert"] = (1.0 - nx) * ny

		# Forest: NE — east of mountains, top portion
		if not west_of_mountains and north_of_river and not near_any_edge:
			scores["forest"] = nx * (1.0 - ny)

		# Swamp: SE — east of mountains, bottom, near river
		if not west_of_mountains and not north_of_river and not near_any_edge:
			var river_bonus: float = max(0.0, 1.0 - (dist_to_river / (map_h * 0.25)))
			scores["swamp"] = nx * ny * (0.5 + river_bonus * 0.5)

		# Plains: interior, neither extreme — fills remaining space
		if not near_any_edge:
			var centrality: float = 1.0 - (abs(nx - 0.5) * 2.0)
			scores["plains"] = centrality * 0.4

		biome_scores[p.id] = scores

	# --- STEP 2: Pick one seed province per biome (highest scorer not already taken) ---
	var biomes_to_seed: Array = ["coast", "mountain", "tundra", "desert", "forest", "swamp", "plains"]
	var seeds: Dictionary = {}      # biome -> province id
	var assigned: Dictionary = {}   # province id -> biome

	for biome in biomes_to_seed:
		var best_id: int = -1
		var best_score: float = -1.0
		for item in provinces:
			var p: ProvinceData = item as ProvinceData
			if assigned.has(p.id):
				continue
			var sc: float = float((biome_scores[p.id] as Dictionary)[biome])
			if sc > best_score:
				best_score = sc
				best_id = p.id
		if best_id >= 0:
			seeds[biome] = best_id
			assigned[best_id] = biome

	# --- STEP 3: Flood-fill BFS from each seed simultaneously ---
	# Priority queue: expand seeds in round-robin so each biome grows evenly
	# Use a simple FIFO per biome, process one step per biome per round
	var queues: Dictionary = {}
	for biome in seeds.keys():
		queues[biome] = [seeds[biome]]

	var remaining: int = provinces.size() - assigned.size()
	var max_iters: int = provinces.size() * 10
	var iters: int = 0

	while remaining > 0 and iters < max_iters:
		iters += 1
		var made_progress: bool = false
		for biome in biomes_to_seed:
			if not queues.has(biome):
				continue
			var q: Array = queues[biome] as Array
			if q.is_empty():
				continue
			var pid: int = int(q.pop_front())
			for neighbor_id in (adj[pid] as Array):
				var nid: int = int(neighbor_id)
				if not assigned.has(nid):
					# Prevent tundra and desert from being adjacent — border
					# provinces are left unassigned and fall through to plains.
					if biome == "tundra" or biome == "desert":
						var conflict: bool = false
						var opposing: String = "desert" if biome == "tundra" else "tundra"
						for nn_id in (adj[nid] as Array):
							if assigned.get(int(nn_id), "") == opposing:
								conflict = true
								break
						if conflict:
							continue
					assigned[nid] = biome
					q.append(nid)
					remaining -= 1
					made_progress = true
		if not made_progress:
			break

	# Apply assignments
	for item in provinces:
		var p: ProvinceData = item as ProvinceData
		if assigned.has(p.id):
			p.biome = str(assigned[p.id])
		else:
			p.biome = "plains"


func _dist_to_polyline(point: Vector2, poly: Array) -> float:
	if poly.size() < 2:
		return INF
	var best: float = INF
	for i in range(poly.size() - 1):
		var a: Vector2 = poly[i] as Vector2
		var b: Vector2 = poly[i + 1] as Vector2
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, a, b)
		var d: float = point.distance_to(closest)
		if d < best:
			best = d
	return best


func _polyline_avg_x(poly: Array, map_w: float) -> float:
	if poly.size() == 0:
		return 0.5
	var total: float = 0.0
	for v in poly:
		var pt: Vector2 = v as Vector2
		total += pt.x
	return (total / float(poly.size())) / max(map_w, 1.0)


func _polyline_avg_y(poly: Array, map_h: float) -> float:
	if poly.size() == 0:
		return 0.5
	var total: float = 0.0
	for v in poly:
		var pt: Vector2 = v as Vector2
		total += pt.y
	return (total / float(poly.size())) / max(map_h, 1.0)


func _near_polyline(point: Vector2, poly: Array, threshold: float) -> bool:
	for i in range(poly.size() - 1):
		var a: Vector2 = poly[i] as Vector2
		var b: Vector2 = poly[i + 1] as Vector2
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, a, b)
		if point.distance_to(closest) <= threshold:
			return true
	return false


func _create_factions_and_assign_owners(map_data: MapData, rng: RandomNumberGenerator) -> void:
	# --------------------------------------------------
	# The Fifteen Great Houses of the Realm
	# Each faction has a stable faction_key that links to
	# its story leader and ai_playstyle in the AI planner.
	# --------------------------------------------------
	const FACTION_DEFS: Array = [
		{
			"key": "house_counsel",   "name": "House of Counsel",
			"color": Color(0.85, 0.75, 0.25),  # gold
			"playstyle": "diplomatic",          "archetype": "Grand Strategist",
			"house": "House of Counsel",
			"doctrine": { "aggression":0.55,"caution":0.65,"elite_preservation":0.75,"economy_focus":0.65,"border_security":0.70,"neutral_expansion":0.60,"revenge_bias":0.45,"fortify_bias":0.60,"mission_bias":0.55,"item_hunting_bias":0.55,"recruit_bias":0.60,"mobility_preference":0.45,"combined_arms_bias":0.85,"opportunism":0.60,"hold_ground_bias":0.75 }
		},
		{
			"key": "house_war",       "name": "House of War",
			"color": Color(0.85, 0.15, 0.15),  # crimson
			"playstyle": "aggressive",          "archetype": "High Marshal",
			"house": "House of War",
			"doctrine": { "aggression":0.85,"caution":0.30,"elite_preservation":0.45,"economy_focus":0.40,"border_security":0.50,"neutral_expansion":0.40,"revenge_bias":0.80,"fortify_bias":0.25,"mission_bias":0.20,"item_hunting_bias":0.20,"recruit_bias":0.75,"mobility_preference":0.60,"combined_arms_bias":0.70,"opportunism":0.85,"hold_ground_bias":0.40 }
		},
		{
			"key": "house_crown",     "name": "House of the Crown",
			"color": Color(0.95, 0.90, 0.50),  # royal gold
			"playstyle": "balanced",            "archetype": "Banner Lord",
			"house": "House of the Crown",
			"doctrine": { "aggression":0.55,"caution":0.60,"elite_preservation":0.70,"economy_focus":0.60,"border_security":0.65,"neutral_expansion":0.55,"revenge_bias":0.50,"fortify_bias":0.55,"mission_bias":0.55,"item_hunting_bias":0.55,"recruit_bias":0.65,"mobility_preference":0.50,"combined_arms_bias":0.80,"opportunism":0.60,"hold_ground_bias":0.70 }
		},
		{
			"key": "house_coin",      "name": "House of Coin",
			"color": Color(0.60, 0.85, 0.30),  # merchant green
			"playstyle": "economic",            "archetype": "Guildmaster",
			"house": "House of Coin",
			"doctrine": { "aggression":0.45,"caution":0.70,"elite_preservation":0.75,"economy_focus":0.90,"border_security":0.60,"neutral_expansion":0.75,"revenge_bias":0.30,"fortify_bias":0.65,"mission_bias":0.75,"item_hunting_bias":0.85,"recruit_bias":0.60,"mobility_preference":0.45,"combined_arms_bias":0.70,"opportunism":0.75,"hold_ground_bias":0.70 }
		},
		{
			"key": "house_people",    "name": "House of the People",
			"color": Color(0.85, 0.35, 0.10),  # revolutionary red-orange
			"playstyle": "expansionist",        "archetype": "Free Militia Commander",
			"house": "House of the People",
			"doctrine": { "aggression":0.80,"caution":0.35,"elite_preservation":0.40,"economy_focus":0.35,"border_security":0.45,"neutral_expansion":0.40,"revenge_bias":0.75,"fortify_bias":0.20,"mission_bias":0.45,"item_hunting_bias":0.35,"recruit_bias":0.80,"mobility_preference":0.65,"combined_arms_bias":0.65,"opportunism":0.80,"hold_ground_bias":0.40 }
		},
		{
			"key": "house_faith",     "name": "House of Faith",
			"color": Color(0.90, 0.90, 0.90),  # temple white
			"playstyle": "defensive",           "archetype": "Templar Commander",
			"house": "House of Faith",
			"doctrine": { "aggression":0.35,"caution":0.80,"elite_preservation":0.80,"economy_focus":0.65,"border_security":0.90,"neutral_expansion":0.30,"revenge_bias":0.50,"fortify_bias":0.90,"mission_bias":0.45,"item_hunting_bias":0.40,"recruit_bias":0.65,"mobility_preference":0.30,"combined_arms_bias":0.75,"opportunism":0.50,"hold_ground_bias":0.90 }
		},
		{
			"key": "house_shadows",   "name": "House of Shadows",
			"color": Color(0.25, 0.15, 0.35),  # deep purple
			"playstyle": "opportunist",         "archetype": "Shadow Blade",
			"house": "House of Shadows",
			"doctrine": { "aggression":0.50,"caution":0.65,"elite_preservation":0.65,"economy_focus":0.55,"border_security":0.60,"neutral_expansion":0.50,"revenge_bias":0.45,"fortify_bias":0.40,"mission_bias":0.90,"item_hunting_bias":0.90,"recruit_bias":0.45,"mobility_preference":0.60,"combined_arms_bias":0.70,"opportunism":0.80,"hold_ground_bias":0.55 }
		},
		{
			"key": "house_diplomacy", "name": "House of Diplomacy",
			"color": Color(0.40, 0.70, 0.85),  # diplomatic blue
			"playstyle": "diplomatic",          "archetype": "Banner Guard Commander",
			"house": "House of Diplomacy",
			"doctrine": { "aggression":0.45,"caution":0.75,"elite_preservation":0.75,"economy_focus":0.75,"border_security":0.70,"neutral_expansion":0.80,"revenge_bias":0.30,"fortify_bias":0.60,"mission_bias":0.70,"item_hunting_bias":0.65,"recruit_bias":0.55,"mobility_preference":0.40,"combined_arms_bias":0.80,"opportunism":0.60,"hold_ground_bias":0.70 }
		},
		{
			"key": "house_frontier",  "name": "House of the Frontier",
			"color": Color(0.45, 0.65, 0.35),  # frontier green
			"playstyle": "defensive",           "archetype": "Master Ranger Warden",
			"house": "House of the Frontier",
			"doctrine": { "aggression":0.50,"caution":0.65,"elite_preservation":0.75,"economy_focus":0.50,"border_security":0.95,"neutral_expansion":0.35,"revenge_bias":0.55,"fortify_bias":0.75,"mission_bias":0.40,"item_hunting_bias":0.35,"recruit_bias":0.65,"mobility_preference":0.45,"combined_arms_bias":0.80,"opportunism":0.55,"hold_ground_bias":0.90 }
		},
		{
			"key": "house_law",       "name": "House of Law",
			"color": Color(0.70, 0.70, 0.80),  # slate blue-grey
			"playstyle": "balanced",            "archetype": "Justiciar Supreme",
			"house": "House of Law",
			"doctrine": { "aggression":0.60,"caution":0.65,"elite_preservation":0.70,"economy_focus":0.55,"border_security":0.75,"neutral_expansion":0.40,"revenge_bias":0.80,"fortify_bias":0.60,"mission_bias":0.45,"item_hunting_bias":0.45,"recruit_bias":0.60,"mobility_preference":0.50,"combined_arms_bias":0.85,"opportunism":0.70,"hold_ground_bias":0.75 }
		},
		{
			"key": "house_strategy",  "name": "House of Strategy",
			"color": Color(0.20, 0.40, 0.75),  # deep blue
			"playstyle": "calculated",          "archetype": "Grand Tactician",
			"house": "House of Strategy",
			"doctrine": { "aggression":0.60,"caution":0.70,"elite_preservation":0.85,"economy_focus":0.65,"border_security":0.65,"neutral_expansion":0.50,"revenge_bias":0.50,"fortify_bias":0.50,"mission_bias":0.75,"item_hunting_bias":0.70,"recruit_bias":0.60,"mobility_preference":0.55,"combined_arms_bias":0.90,"opportunism":0.65,"hold_ground_bias":0.75 }
		},
		{
			"key": "house_roads",     "name": "House of Roads",
			"color": Color(0.60, 0.50, 0.35),  # stone brown
			"playstyle": "fortify",             "archetype": "Siege Engineer Commander",
			"house": "House of Roads",
			"doctrine": { "aggression":0.40,"caution":0.70,"elite_preservation":0.80,"economy_focus":0.70,"border_security":0.80,"neutral_expansion":0.40,"revenge_bias":0.45,"fortify_bias":0.85,"mission_bias":0.55,"item_hunting_bias":0.45,"recruit_bias":0.65,"mobility_preference":0.35,"combined_arms_bias":0.75,"opportunism":0.55,"hold_ground_bias":0.85 }
		},
		{
			"key": "house_blood",     "name": "House of Blood",
			"color": Color(0.70, 0.10, 0.10),  # dark blood red
			"playstyle": "aggressive",          "archetype": "Crimson Champion",
			"house": "House of Blood",
			"doctrine": { "aggression":0.75,"caution":0.35,"elite_preservation":0.50,"economy_focus":0.40,"border_security":0.50,"neutral_expansion":0.45,"revenge_bias":0.70,"fortify_bias":0.25,"mission_bias":0.35,"item_hunting_bias":0.30,"recruit_bias":0.75,"mobility_preference":0.65,"combined_arms_bias":0.70,"opportunism":0.80,"hold_ground_bias":0.45 }
		},
		{
			"key": "house_provinces", "name": "House of Provinces",
			"color": Color(0.55, 0.75, 0.55),  # provincial green
			"playstyle": "economic",            "archetype": "Provincial Knight Commander",
			"house": "House of Provinces",
			"doctrine": { "aggression":0.50,"caution":0.60,"elite_preservation":0.65,"economy_focus":0.65,"border_security":0.65,"neutral_expansion":0.60,"revenge_bias":0.45,"fortify_bias":0.60,"mission_bias":0.50,"item_hunting_bias":0.45,"recruit_bias":0.60,"mobility_preference":0.40,"combined_arms_bias":0.75,"opportunism":0.55,"hold_ground_bias":0.75 }
		},
		{
			"key": "house_outsider",  "name": "The Steppe Khanate",
			"color": Color(0.80, 0.55, 0.15),  # steppe amber
			"playstyle": "conquest",            "archetype": "Horse Reaver Warlord",
			"house": "The Outsider",
			"doctrine": { "aggression":0.85,"caution":0.25,"elite_preservation":0.40,"economy_focus":0.35,"border_security":0.40,"neutral_expansion":0.55,"revenge_bias":0.60,"fortify_bias":0.20,"mission_bias":0.25,"item_hunting_bias":0.20,"recruit_bias":0.80,"mobility_preference":0.85,"combined_arms_bias":0.65,"opportunism":0.90,"hold_ground_bias":0.40 }
		},
	]

	var faction_count: int = FACTION_DEFS.size()
	var factions: Array = []

	for i in range(faction_count):
		var def: Dictionary = FACTION_DEFS[i]
		var f: FactionData = FactionDataScript.new() as FactionData
		f.id = i
		f.display_name = str(def["name"])
		f.faction_key = str(def["key"])
		f.color = def["color"] as Color
		f.gold = 500
		f.ai_playstyle = str(def["playstyle"])
		f.unit_archetype = str(def["archetype"])
		f.lore_house = str(def["house"])
		# Apply doctrine personality values
		var doc: Dictionary = def.get("doctrine", {}) as Dictionary
		if not doc.is_empty():
			f.aggression          = float(doc.get("aggression",          f.aggression))
			f.caution             = float(doc.get("caution",             f.caution))
			f.elite_preservation  = float(doc.get("elite_preservation",  f.elite_preservation))
			f.economy_focus       = float(doc.get("economy_focus",       f.economy_focus))
			f.border_security     = float(doc.get("border_security",     f.border_security))
			f.neutral_expansion   = float(doc.get("neutral_expansion",   f.neutral_expansion))
			f.revenge_bias        = float(doc.get("revenge_bias",        f.revenge_bias))
			f.fortify_bias        = float(doc.get("fortify_bias",        f.fortify_bias))
			f.mission_bias        = float(doc.get("mission_bias",        f.mission_bias))
			f.item_hunting_bias   = float(doc.get("item_hunting_bias",   f.item_hunting_bias))
			f.recruit_bias        = float(doc.get("recruit_bias",        f.recruit_bias))
			f.mobility_preference = float(doc.get("mobility_preference", f.mobility_preference))
			f.combined_arms_bias  = float(doc.get("combined_arms_bias",  f.combined_arms_bias))
			f.opportunism         = float(doc.get("opportunism",         f.opportunism))
			f.hold_ground_bias    = float(doc.get("hold_ground_bias",    f.hold_ground_bias))
		factions.append(f)

	map_data.factions = factions

	# Assign each faction one well-separated starting province
	var start_ids: Array[int] = _pick_far_apart_starts(map_data.provinces, faction_count, rng)

	for i in range(faction_count):
		var pid: int = start_ids[i]
		map_data.provinces[pid].owner_id = i
		map_data.factions[i].provinces.append(pid)

	# Starting setup rule: each faction begins with exactly one province.
	# Remaining provinces stay neutral for early expansion / mission tempo tradeoffs.


func _pick_far_apart_starts(provinces: Array, count: int, rng: RandomNumberGenerator) -> Array[int]:
	var result: Array[int] = []

	var first: int = rng.randi_range(0, provinces.size() - 1)
	result.append(first)

	while result.size() < count:
		var best_id: int = -1
		var best_score: float = -1.0

		for p in provinces:
			var pid: int = p.id
			if result.has(pid):
				continue

			var min_d: float = INF
			for chosen_id in result:
				var d: float = provinces[chosen_id].center.distance_to(p.center)
				min_d = min(min_d, d)

			if min_d > best_score:
				best_score = min_d
				best_id = pid

		if best_id == -1:
			break
		result.append(best_id)

	return result


# -----------------------------
# Garrisons (NEW)
# -----------------------------
