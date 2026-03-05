class_name CombatResolver
extends RefCounted

func resolve(state: GameState) -> void:
	var map_data: MapData = state.map_data
	var ob: OrderBook = state.order_book
	var rng: RandomNumberGenerator = state.rng

	for item in map_data.factions:
		var f: FactionData = item as FactionData
		var fid: int = int(f.id)
		var orders: Array = ob.get_attacks(fid)

		for o in orders:
			var a: int = int(o["from"])
			var b: int = int(o["to"])
			var commit: int = int(o["commit"])

			var pa: ProvinceData = map_data.provinces[a] as ProvinceData
			var pb: ProvinceData = map_data.provinces[b] as ProvinceData

			if int(pa.owner_id) != fid:
				continue
			if int(pa.garrison) < commit:
				continue
			if int(pb.owner_id) == fid:
				continue

			# Spend commit immediately
			pa.garrison = int(pa.garrison) - commit

			var ap: int = _compute_attack_power(rng, commit, int(pa.fort_level))
			var dp: int = _compute_defense_power(
				rng,
				int(pb.garrison),
				int(pb.defense_value),
				int(pb.fort_level),
				bool(pb.is_chokepoint)
			)

			if ap > dp:
				var att_loss: int = rng.randi_range(
					TurnManager.ATTACK_BASE_LOSS_MIN,
					TurnManager.ATTACK_BASE_LOSS_MAX
				)
				var new_occ: int = maxi(TurnManager.MIN_CAPTURE_GARRISON, commit - att_loss)

				pb.owner_id = fid
				pb.garrison = mini(new_occ, int(pb.max_garrison))
			else:
				var def_loss2: int = rng.randi_range(
					TurnManager.DEF_LOSS_MIN,
					TurnManager.DEF_LOSS_MAX
				)
				pb.garrison = maxi(0, int(pb.garrison) - def_loss2)


func _compute_attack_power(rng: RandomNumberGenerator, commit: int, fort_level: int) -> int:
	var bonus: int = fort_level * TurnManager.FORT_ATTACK_BONUS_PER_LEVEL
	var roll: int = rng.randi_range(0, 50)
	return commit + bonus + roll


func _compute_defense_power(
	rng: RandomNumberGenerator,
	garrison: int,
	defense_value: int,
	fort_level: int,
	choke: bool
) -> int:
	var fort_bonus: int = fort_level * TurnManager.FORT_DEF_MULT
	var choke_bonus: int = TurnManager.CHOKE_DEF_BONUS if choke else 0
	var roll: int = rng.randi_range(0, 50)
	return garrison + defense_value + fort_bonus + choke_bonus + roll
