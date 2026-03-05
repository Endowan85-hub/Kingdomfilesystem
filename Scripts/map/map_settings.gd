extends Resource
class_name MapSettings

@export var seed: int = 0

@export var province_count: int = 20
@export var map_size: Vector2 = Vector2(2000, 2000)

# Point distribution
@export var min_point_distance: float = 140.0
@export var relaxation_passes: int = 2

# Graph density
@export var extra_edge_density: float = 0.20
@export var neighbor_k: int = 5

# Movement cost
@export var distance_cost_scale: float = 180.0
@export var min_route_cost: int = 1
@export var max_route_cost: int = 999

# Geography
@export var enable_river: bool = true
@export var enable_mountains: bool = true

@export var river_points: int = 5
@export var mountain_points: int = 5

@export var river_crossing_extra_cost: int = 2
@export var mountain_crossing_extra_cost: int = 4

# Chokepoints
@export var bridge_count: int = 2          # number of cheap river crossings
@export var mountain_pass_count: int = 2   # number of cheap mountain crossings
