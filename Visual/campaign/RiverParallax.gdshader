shader_type canvas_item;

// Scroll speed (world-UV units per second) — matches old _river_wind_uv accumulation rate
uniform vec2 scroll_speed = vec2(0.005, 0.0017);

void fragment() {
	// UV comes from the prebuilt river strip mesh (world_pos / tex_size).
	// TIME drives the scroll on the GPU so no CPU redraw is needed each frame.
	vec2 scrolled_uv = UV + scroll_speed * TIME;
	COLOR = texture(TEXTURE, scrolled_uv);
}
