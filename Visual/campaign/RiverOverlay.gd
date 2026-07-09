extends Node2D

var river_tiles: Array = []
var river_path_tiles: Array = []
var zoom: float = 1.0
var origin: Vector2 = Vector2.ZERO
var tile_world: float = 45.0

func _draw() -> void:
	if river_tiles.is_empty() or river_path_tiles.is_empty():
		return
	var mat := material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("cam_origin", origin)
		mat.set_shader_parameter("cam_zoom", zoom)
	var tile_sz := tile_world * zoom * 1.12
	var half := tile_sz * 0.5
	for entry in river_path_tiles:
		var tile_idx: int = entry["tile"]
		if tile_idx < 0 or tile_idx >= river_tiles.size():
			continue
		var tex: Texture2D = river_tiles[tile_idx]
		if tex == null:
			continue
		var sp: Vector2 = (entry["pos"] + origin) * zoom
		draw_texture_rect(tex, Rect2(sp.x - half, sp.y - half, tile_sz, tile_sz), false)
