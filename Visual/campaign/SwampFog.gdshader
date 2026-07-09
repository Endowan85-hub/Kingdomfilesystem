shader_type canvas_item;

uniform sampler2D noise_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2  cam_origin    = vec2(0.0);
uniform float cam_zoom      = 1.0;
uniform float fog_strength  = 0.38;
uniform vec3  fog_color     = vec3(0.72, 0.80, 0.65);  // pale greenish-white

void fragment() {
	// Reconstruct world position the same way CloudShadow does.
	vec2 world = VERTEX / cam_zoom - cam_origin;

	// Two fast layers — detailed drifting wisps.
	vec2 uv1 = world * 0.00075 + vec2( 0.0028,  0.0011) * TIME;
	vec2 uv2 = world * 0.00120 + vec2(-0.0018,  0.0020) * TIME;
	float n1 = texture(noise_tex, uv1).r;
	float n2 = texture(noise_tex, uv2).r;
	float wisp = smoothstep(0.38, 0.68, n1 * 0.6 + n2 * 0.4);

	// Large-scale slow density map — creates thick and thin patches.
	vec2 uv3 = world * 0.00025 + vec2(0.0005, 0.0003) * TIME;
	float density = smoothstep(0.30, 0.75, texture(noise_tex, uv3).r);

	// COLOR.a is interpolated per-vertex alpha — 0 at polygon edge, 1 at interior.
	float edge_fade = COLOR.a;
	COLOR = vec4(fog_color, wisp * fog_strength * density * edge_fade);
}
