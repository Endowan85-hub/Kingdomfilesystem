class_name OwnershipResolver
extends RefCounted

func recount_faction_provinces(state: GameState) -> void:
	var map_data: MapData = state.map_data

	for item in map_data.factions:
		var f: FactionData = item as FactionData
		f.provinces = []

	for item in map_data.provinces:
		var p: ProvinceData = item as ProvinceData
		var oid: int = int(p.owner_id)
		if oid < 0:
			continue
		var f2: FactionData = _find_faction(map_data, oid)
		if f2 != null:
			f2.provinces.append(int(p.id))


func _find_faction(map_data: MapData, id: int) -> FactionData:
	for item in map_data.factions:
		var f: FactionData = item as FactionData
		if int(f.id) == id:
			return f
	return null
