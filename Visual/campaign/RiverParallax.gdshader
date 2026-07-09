shader_type canvas_item;

uniform sampler2D parallax_tex : repeat_enable, hint_default_white;

void fragment() {
	vec4 tile = texture(TEXTURE, UV);

	if (tile.a < 0.1) {
		COLOR = vec4(0.0);
		return;
	}

	// Show red for ALL non-transparent pixels
	COLOR = vec4(1.0, 0.0, 0.0, 1.0);
}
