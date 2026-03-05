class_name EconomyResolver
extends RefCounted

func resolve(state: GameState) -> void:
	var map_data: MapData = state.map_data

	# Reset income
	for item in map_data.factions:
		var f: FactionData = item as FactionData
		f.income = 0

	# Sum province income into faction income
	for item in map_data.provinces:
		var p: ProvinceData = item as ProvinceData
		var oid: int = int(p.owner_id)
		if oid < 0:
			continue
		var f2: FactionData = _find_faction(map_data, oid)
		if f2 != null:
			f2.income = int(f2.income) + int(p.income)

	# Add income to gold
	for item in map_data.factions:
		var f3: FactionData = item as FactionData
		f3.gold = int(f3.gold) + int(f3.income)
		f3.income_last_turn = int(f3.income)


func _find_faction(map_data: MapData, id: int) -> FactionData:
	for item in map_data.factions:
		var f: FactionData = item as FactionData
		if int(f.id) == id:
			return f
	return null
