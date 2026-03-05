class_name AIPlanner
extends RefCounted
## Very basic AI planner (debug opponent).
## Produces orders into the provided OrderBook.

const MAX_ATTACKS_PER_TURN: int = 2

func plan_month(state: GameState, ai_id: int) -> void:
	if state == null or state.map_data == null:
		return

	var map_data: MapData = state.map_data
	var ob: OrderBook = state.order_book
	var rng: RandomNumberGenerator = state.rng

	ob.clear_orders_for_faction(ai_id)

	var f: FactionData = _find_faction(map_data, ai_id)
	if f == null:
		return

	# 1) Upgrade a random owned province if affordable
	var owned: Array[int] = []
	for item in map_data.provinces:
		var p: ProvinceData = item as ProvinceData
		if int(p.owner_id) == ai_id:
			owned.append(int(p.id))

	if owned.size() > 0:
		var pick_index: int = rng.randi_range(0, owned.size() - 1)
		var pid: int = owned[pick_index]
		var pp: ProvinceData = map_data.provinces[pid] as ProvinceData
		var cost: int = TurnManager.FORT_BASE_COST * maxi(1, int(pp.fort_level))
		if int(f.gold) >= cost:
			ob.queue_upgrade(ai_id, pid, cost)

	# 2) Attack from strong border provinces into weakest neighbor
	var attacks: int = 0
	for pid in owned:
		if attacks >= MAX_ATTACKS_PER_TURN:
			break
		var psrc: ProvinceData = map_data.provinces[pid] as ProvinceData
		if int(psrc.garrison) < 120:
			continue

		var targets: Array[int] = _adjacent_enemies_or_neutral(map_data, pid, ai_id)
		if targets.is_empty():
			continue

		var best_t: int = targets[0]
		var best_dp: int = 999999
		for t in targets:
			var pt: ProvinceData = map_data.provinces[t] as ProvinceData
			var dp_est: int = int(pt.garrison) + int(pt.defense_value) + int(pt.fort_level) * TurnManager.FORT_DEF_MULT
			if bool(pt.is_chokepoint):
				dp_est += TurnManager.CHOKE_DEF_BONUS
			if dp_est < best_dp:
				best_dp = dp_est
				best_t = t

		var commit: int = clampi(int(psrc.garrison) / 2, 70, 200)
		ob.queue_attack(ai_id, pid, best_t, commit)
		attacks += 1


func _adjacent_enemies_or_neutral(map_data: MapData, from_id: int, my_id: int) -> Array[int]:
	var out: Array[int] = []
	for item in map_data.routes:
		var r: RouteData = item as RouteData
		var a: int = int(r.a)
		var b: int = int(r.b)

		var other: int = -1
		if a == from_id:
			other = b
		elif b == from_id:
			other = a
		else:
			continue

		var p: ProvinceData = map_data.provinces[other] as ProvinceData
		if int(p.owner_id) != my_id:
			out.append(other)

	return out


func _find_faction(map_data: MapData, id: int) -> FactionData:
	for item in map_data.factions:
		var f: FactionData = item as FactionData
		if int(f.id) == id:
			return f
	return null
