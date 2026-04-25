# ==================================================
# BattleCloudLayer
# --------------------------------------------------
# Renders a full-screen moving cloud-shadow overlay.
# BattleGrid calls set_grid_position() directly
# whenever its position changes so the shader offset
# is always perfectly in sync — no polling lag.
# ==================================================
extends CanvasLayer

const SHADER_PATH := "res://Visual/battle/cloud_shadow.gdshader"

var _mat : ShaderMaterial = null

func _ready() -> void:
	layer = 30
	add_to_group("battle_cloud_layer")

	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH) as Shader
	rect.material = _mat

	add_child(rect)

# Called by BattleGrid every time its position changes.
func set_grid_position(grid_pos: Vector2, vp_size: Vector2) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("cam_world_offset", grid_pos / vp_size)
