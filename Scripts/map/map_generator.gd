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

	map_data.provinces = provinces
	map_data.routes = routes
	map_data.adjacency = _build_adjacency(routes)

	map_data.river_polyline = river
	map_data.mountain_polyline = mountains

	_evaluate_provinces(settings, map_data)
	_create_factions_and_assign_owners(map_data, rng)

	_assign_initial_garrisons(map_data, rng)

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
		p.garrison = 100
		p.max_garrison = 250
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

		p.base_income = 50 + connections * 10
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
		p.defense_value = p.fort_level * 50 + connections * 15

		if connections <= 2:
			p.is_chokepoint = true
			p.defense_value += 40
		else:
			p.is_chokepoint = false

		p.strategic_value = float(p.income) * 0.6 + float(p.defense_value) * 0.4


# -----------------------------
# Factions + Ownership
# -----------------------------

func _create_factions_and_assign_owners(map_data: MapData, rng: RandomNumberGenerator) -> void:
	var faction_count: int = 2
	var factions: Array = []

	var f0: FactionData = FactionDataScript.new() as FactionData
	f0.id = 0
	f0.display_name = "Crimson League"
	f0.color = Color(0.9, 0.2, 0.2)
	f0.gold = 500
	factions.append(f0)

	var f1: FactionData = FactionDataScript.new() as FactionData
	f1.id = 1
	f1.display_name = "Azure Pact"
	f1.color = Color(0.2, 0.5, 0.95)
	f1.gold = 500
	factions.append(f1)

	map_data.factions = factions

	var start_ids: Array[int] = _pick_far_apart_starts(map_data.provinces, faction_count, rng)

	for i in range(faction_count):
		var pid: int = start_ids[i]
		map_data.provinces[pid].owner_id = i
		map_data.factions[i].provinces.append(pid)

	for i in range(faction_count):
		var start_pid: int = start_ids[i]
		var neighbors: Array = []
		if map_data.adjacency.has(start_pid):
			neighbors = map_data.adjacency[start_pid]
		if neighbors.size() > 0:
			var pick_index: int = rng.randi_range(0, neighbors.size() - 1)
			var n_pid: int = int(neighbors[pick_index])

			if map_data.provinces[n_pid].owner_id == -1:
				map_data.provinces[n_pid].owner_id = i
				map_data.factions[i].provinces.append(n_pid)


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

func _assign_initial_garrisons(map_data: MapData, rng: RandomNumberGenerator) -> void:
	for p in map_data.provinces:
		# Max garrison scales with value/income
		p.max_garrison = clamp(200 + int(p.income * 2), 220, 600)

		if p.owner_id < 0:
			# Neutrals: meaningful defenders
			p.garrison = rng.randi_range(70, 140)
		else:
			# Factions: stronger starts
			p.garrison = rng.randi_range(140, 230)

		# Chokepoints tend to be tougher
		if p.is_chokepoint:
			p.garrison = int(round(float(p.garrison) * 1.15))

		p.garrison = clamp(p.garrison, 0, p.max_garrison)
