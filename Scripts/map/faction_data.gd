extends Resource
class_name FactionData

@export var id: int = -1
@export var display_name: String = "Faction"
@export var color: Color = Color.WHITE

@export var gold: int = 0

# Current-turn income accumulator (used by EconomyResolver during Execute Month).
# This is reset each month.
@export var income: int = 0

# Optional historical/debug value.
@export var income_last_turn: int = 0

@export var provinces: Array[int] = []
