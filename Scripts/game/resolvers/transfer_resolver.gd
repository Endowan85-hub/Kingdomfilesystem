class_name TransferResolver
extends RefCounted

func resolve(state: GameState) -> void:
	var map_data: MapData = state.map_data
	var ob: OrderBook = state.order_book

	for item in map_data.factions:
		var f: FactionData = item as FactionData
		var fid: int = int(f.id)
		var orders: Array = ob.get_transfers(fid)
		for o in orders:
			var a: int = int(o["from"])
			var b: int = int(o["to"])
			var sent: int = int(o["sent"])
			var arrive: int = int(o["arrive"])

			var pa: ProvinceData = map_data.provinces[a] as ProvinceData
			var pb: ProvinceData = map_data.provinces[b] as ProvinceData

			if int(pa.owner_id) != fid:
				continue
			if int(pb.owner_id) != fid:
				continue
			if int(pa.garrison) < sent:
				continue

			pa.garrison = int(pa.garrison) - sent
			pb.garrison = mini(int(pb.garrison) + arrive, int(pb.max_garrison))
