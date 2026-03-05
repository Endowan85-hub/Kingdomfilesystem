extends Resource
class_name GameState

@export var map_data: MapData
@export var month_index: int = 0

# Used to keep random outcomes stable/deterministic if desired.
@export var rng_seed: int = 0

# RNG instance used by AI + resolvers during Execute Month.
# Contract: systems may read state.rng, but no system should replace it.
var rng: RandomNumberGenerator

# Orders for the current planning phase.
@export var order_book: OrderBook


func init_with_map(new_map: MapData) -> void:
	map_data = new_map
	month_index = 0

	if rng_seed == 0:
		# Time is fine here; you can set this explicitly for reproducible runs.
		rng_seed = int(Time.get_ticks_msec())

	# Initialize RNG
	rng = RandomNumberGenerator.new()
	rng.seed = int(rng_seed)

	if order_book == null:
		order_book = OrderBook.new()

	# Ensure order arrays exist for all factions
	var fids: Array[int] = []
	if map_data != null:
		for f in map_data.factions:
			fids.append(int(f.id))
	order_book.clear_all(fids)
