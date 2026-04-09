# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: TransferResolver
#
# Role:
# Moves leaders (and their army units) between provinces
# based on queued transfer orders.
#
# Allowed Interactions:
# - GameState (move_leader_to_province)
# - MapData / ProvinceData
# - OrderBook (read-only)
# - DebugLogger (logging only)
#
# Forbidden Responsibilities:
# - Must not interact with UI
# - Must not create orders
# - Must not run turn sequencing
#
# Game Phase:
# Execution Phase
#
# Notes:
# - Transfer orders carry a leader_ids array of leaders to move.
# - Source must still be owned by the faction at resolve time.
# - Destination must still be owned by the faction at resolve time.
# - Leaders on mission are skipped.
# ==================================================

class_name TransferResolver
extends RefCounted


func resolve(state: GameState) -> void:
	var map_data: MapData = state.map_data
	var ob: OrderBook = state.order_book
	var log = state.logger

	var attempted := 0
	var applied := 0
	var skipped_owner := 0
	var skipped_no_leaders := 0
	var moved_leaders: Array = []

	for item in map_data.factions:
		var f: FactionData = item as FactionData
		var fid: int = int(f.id)
		var orders: Array = ob.get_transfers(fid)

		for o in orders:
			attempted += 1

			var a: int = int(o["from"])
			var b: int = int(o["to"])
			var leader_ids: Array = o.get("leader_ids", [])

			var pa: ProvinceData = map_data.provinces[a] as ProvinceData
			var pb: ProvinceData = map_data.provinces[b] as ProvinceData

			if int(pa.owner_id) != fid:
				skipped_owner += 1
				continue
			if int(pb.owner_id) != fid:
				skipped_owner += 1
				continue

			# Move each requested leader
			var moved_this_order: int = 0
			for lid in leader_ids:
				var leader = state.get_leader(int(lid))
				if leader == null:
					continue
				if bool(leader.on_mission) or str(leader.status) == "wounded" or str(leader.status) == "injured":
					continue
				# Verify leader is actually in the source province
				var leader_prov: int = int(leader.current_province_id)
				if leader_prov != a:
					continue
				state.move_leader_to_province(int(lid), b)
				moved_this_order += 1
				moved_leaders.append({"leader_id": int(lid), "from": a, "to": b})

			if moved_this_order == 0:
				skipped_no_leaders += 1
				continue

			applied += 1

	if log != null:
		log.event("transfer_result", {
			"attempted": attempted,
			"applied": applied,
			"skipped_owner": skipped_owner,
			"skipped_no_leaders": skipped_no_leaders,
			"moved_leaders": moved_leaders
		})
