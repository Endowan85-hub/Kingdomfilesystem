class_name UpgradeResolver
extends RefCounted

func resolve(state: GameState) -> void:
	var map_data: MapData = state.map_data
	var ob: OrderBook = state.order_book

	for item in map_data.factions:
		var f: FactionData = item as FactionData
		var fid: int = int(f.id)
		var orders: Array = ob.get_upgrades(fid)
		for o in orders:
			var pid: int = int(o["province_id"])
			var cost: int = int(o["cost"])

			var p: ProvinceData = map_data.provinces[pid] as ProvinceData
			if int(p.owner_id) != fid:
				continue
			if int(f.gold) < cost:
				continue

			f.gold = int(f.gold) - cost
			p.fort_level = int(p.fort_level) + 1
			p.defense_value = int(p.defense_value) + TurnManager.FORT_DEF_PER_LEVEL
			p.max_garrison = int(p.max_garrison) + TurnManager.FORT_CAP_PER_LEVEL
