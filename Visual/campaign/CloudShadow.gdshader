shader_type canvas_item;

uniform sampler2D noise_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 cam_origin = vec2(0.0);
uniform float cam_zoom = 1.0;
uniform vec2 uv_scale = vec2(0.0009, 0.0009);
uniform vec2 wind = vec2(0.005, 0.0017);
uniform float shadow_strength = 0.30;
uniform float cloud_threshold = 0.62;
uniform float cloud_softness = 0.22;
uniform vec2 sun_world_pos = vec2(0.0, 0.0);
uniform float sun_radius = 2000.0;
uniform vec3 sun_color = vec3(1.0, 0.93, 0.72);
uniform float sun_strength = 0.48;

void fragment() {
	vec2 world = VERTEX / cam_zoom - cam_origin;

	vec2 uv = world * uv_scale + wind * TIME;
	float n = texture(noise_tex, uv).r;
	float cloud = smoothstep(cloud_threshold - cloud_softness, cloud_threshold + cloud_softness, n);

	float dist = length(world - sun_world_pos);
	float light = clamp(1.0 - dist / sun_radius, 0.0, 1.0);
	light = light * light;

	float shadow_alpha = cloud * shadow_strength;
	float light_alpha = light * sun_strength * (1.0 - cloud * 0.7);

	float total_alpha = clamp(shadow_alpha + light_alpha, 0.0, 1.0);
	vec3 rgb = (vec3(0.0) * shadow_alpha + sun_color * light_alpha) / max(shadow_alpha + light_alpha, 0.0001);

	COLOR = vec4(rgb, total_alpha);
}
