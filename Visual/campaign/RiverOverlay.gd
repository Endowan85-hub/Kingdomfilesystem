extends Node2D

# Prebuilt world-space triangle strip meshes for the river parallax water fill.
# PlayerMap sets these after _build_river_path() runs.
# The ShaderMaterial on this node (RiverParallax.gdshader) scrolls UVs via TIME
# automatically — no queue_redraw() needed for the animation itself.
var strip_main: ArrayMesh = null
var strip_tribs: Array = []       # Array[ArrayMesh], one per tributary
var parallax_tex: Texture2D = null

# Camera params — synced by PlayerMap whenever the camera moves
var zoom: float = 1.0
var origin: Vector2 = Vector2.ZERO


func _draw() -> void:
	if parallax_tex == null:
		return
	var xform := Transform2D(Vector2(zoom, 0.0), Vector2(0.0, zoom), origin * zoom)
	if strip_main != null:
		draw_mesh(strip_main, parallax_tex, xform)
	for mesh in strip_tribs:
		if mesh != null:
			draw_mesh(mesh, parallax_tex, xform)
