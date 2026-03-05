class_name ReinforcementResolver
extends RefCounted

func resolve(state: GameState) -> void:
	var map_data: MapData = state.map_data

	for item in map_data.provinces:
		var p: ProvinceData = item as ProvinceData
		if int(p.owner_id) < 0:
			continue

		var rein: int = maxi(5, int(p.income))
		p.garrison = mini(int(p.garrison) + rein, int(p.max_garrison))
