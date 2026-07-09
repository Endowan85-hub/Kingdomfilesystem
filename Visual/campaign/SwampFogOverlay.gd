extends Node2D

var swamp_polys: Array  = []  # Array of PackedVector2Array (world space)
var zoom:        float  = 1.0
var origin:      Vector2 = Vector2.ZERO

# How far beyond the province border the fog extends (matches vignette width).
const EXPAND_DIST: float = 30.0

func _draw() -> void:
	if swamp_polys.is_empty():
		return
	var mat := material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("cam_origin", origin)
		mat.set_shader_parameter("cam_zoom",   zoom)

	for world_poly in swamp_polys:
		var poly := world_poly as PackedVector2Array
		if poly.size() < 3:
			continue

		# Compute centroid in world space.
		var cx := 0.0; var cy := 0.0
		for v in poly:
			cx += v.x; cy += v.y
		var centroid := Vector2(cx / poly.size(), cy / poly.size())

		# Expand each vertex outward from centroid.
		var expanded := PackedVector2Array()
		for v in poly:
			var dir: Vector2 = (v - centroid)
			expanded.append(v + dir.normalized() * EXPAND_DIST)

		# Convert to screen space.
		var n := expanded.size()
		var sc_center := (centroid + origin) * zoom
		var sc_verts: Array = []
		for v in expanded:
			sc_verts.append((v + origin) * zoom)

		# Draw triangle fan: (center, v[i], v[i+1])
		# Center alpha = 1 (full fog), edge alpha = 0 (transparent).
		var c_full  := Color(1, 1, 1, 1)
		var c_edge  := Color(1, 1, 1, 0)
		for i in n:
			var v0: Vector2 = sc_center
			var v1: Vector2 = sc_verts[i]
			var v2: Vector2 = sc_verts[(i + 1) % n]
			draw_primitive(
				PackedVector2Array([v0, v1, v2]),
				PackedColorArray([c_full, c_edge, c_edge]),
				PackedVector2Array()
			)
