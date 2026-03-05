extends Resource
class_name RouteData

@export var a: int = -1
@export var b: int = -1

@export var distance: float = 0.0
@export var base_cost: int = 1

@export var extra_cost: int = 0
@export var is_blocked: bool = false

@export var tags: Array[StringName] = []

func total_cost() -> int:
	if is_blocked:
		return 999999
	return base_cost + extra_cost
