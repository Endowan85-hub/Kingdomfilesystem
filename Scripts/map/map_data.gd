extends Resource
class_name MapData

@export var map_name: String = "Generated Map"
@export var map_seed: int = 0

@export var provinces: Array = [] # Array[ProvinceData]
@export var routes: Array = []    # Array[RouteData]
@export var adjacency: Dictionary = {} # int -> Array[int]

@export var river_polyline: Array = []     # Array[Vector2]
@export var mountain_polyline: Array = []  # Array[Vector2]

@export var factions: Array = [] # Array[FactionData]
