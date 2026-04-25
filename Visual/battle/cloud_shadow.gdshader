shader_type canvas_item;

uniform float shadow_opacity   : hint_range(0.0, 0.6)  = 0.38;
uniform float ray_opacity      : hint_range(0.0, 0.4)  = 0.0;
uniform float cloud_scale      : hint_range(1.0, 20.0) = 4.5;
uniform vec2  wind_dir                                 = vec2(0.75, 0.28);
uniform float speed            : hint_range(0.0, 0.05) = 0.022;
// Set every frame from BattleCloudLayer to keep shadows fixed to the world
uniform vec2  cam_world_offset                         = vec2(0.0);

// ── Noise helpers ──────────────────────────────────────────────────────────
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i),             hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i+vec2(0,1)),   hash(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

// 6-octave FBM — extra octave gives finer detail that softens hard edges
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	vec2 shift = vec2(1.7, 9.2);
	for (int i = 0; i < 6; i++) {
		v += a * vnoise(p);
		p  = p * 2.1 + shift;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	// Subtract camera offset so shadows stay fixed to world, not screen
	vec2 uv = (SCREEN_UV - cam_world_offset) * cloud_scale + wind_dir * TIME * speed;

	// ── Double domain warping ───────────────────────────────────────────────
	// First warp pass — pulls the UV into swirls
	vec2 q = vec2(
		fbm(uv  + vec2(0.0, 0.0)),
		fbm(uv  + vec2(5.2, 1.3))
	);
	// Second warp pass — warps the already-warped coords, destroying any
	// remaining straight edges completely
	vec2 r = vec2(
		fbm(uv + 2.8 * q + vec2(1.7, 9.2) + wind_dir * TIME * speed * 0.3),
		fbm(uv + 2.8 * q + vec2(8.3, 2.8) + wind_dir * TIME * speed * 0.3)
	);
	float cloud = fbm(uv + 3.2 * r);

	// Smoothstep kept wide so whatever boundaries remain are still feathered
	cloud = smoothstep(0.24, 0.82, cloud);

	COLOR = vec4(0.0, 0.0, 0.0, cloud * shadow_opacity);
}
