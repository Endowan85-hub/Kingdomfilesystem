extends Resource
class_name ProvinceData

@export var id: int = -1
@export var display_name: String = "Province"
@export var center: Vector2 = Vector2.ZERO

# Ownership
@export var owner_id: int = -1 # -1 = neutral

# Economy / strategy
@export var population: int = 0
@export var base_income: int = 0
@export var income: int = 0

@export var fort_level: int = 1
@export var defense_value: int = 0
@export var strategic_value: float = 0.0

@export var is_chokepoint: bool = false
@export var is_bridge_hub: bool = false
@export var is_mountain_pass_hub: bool = false

# Military (new)
@export var garrison: int = 100
@export var max_garrison: int = 250
