extends RefCounted
# Biomes of the 1000 m map (V25). ONE formula, used by the ground shader (GPU), the streaming of trees / rocks (CPU) and the minimap.
# weights(x, z) = [farm, forest, rock, desert, swamp] (sum = 1).  North = -z.
#   farm   = the old 400 m map in the middle (green)
#   forest = north-west, rock = north-east, desert = south-east, swamp = south-west  (borders are wavy and blend softly)

const GROUND_SHADER := """
shader_type spatial;
varying vec3 wpos;
vec2 warp(vec2 p) {
	return vec2(p.x + sin(p.x * 0.011 + p.y * 0.007) * 60.0 + sin(p.y * 0.017 - p.x * 0.005) * 40.0,
		p.y + sin(p.y * 0.012 - p.x * 0.008) * 60.0 + sin(p.x * 0.019 + p.y * 0.006) * 40.0);
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wpos.xz;
	vec2 w = warp(p);
	vec2 q = (w - p) * 0.25 + p;
	float d = max(abs(q.x), abs(q.y));
	float farm = 1.0 - smoothstep(225.0, 285.0, d);
	float east = smoothstep(-70.0, 70.0, w.x);
	float south = smoothstep(-70.0, 70.0, w.y);
	float o = 1.0 - farm;
	float fo = o * (1.0 - east) * (1.0 - south);
	float ro = o * east * (1.0 - south);
	float de = o * east * south;
	float sw = o * (1.0 - east) * south;
	float n = fract(sin(dot(floor(p * 0.4), vec2(12.9898, 78.233))) * 43758.5453);
	float big = 0.5 + 0.5 * sin(p.x * 0.045) * sin(p.y * 0.04);
	float rip = 0.5 + 0.5 * sin(p.x * 0.35 + sin(p.y * 0.08) * 3.0);
	vec3 c_farm = mix(vec3(0.3, 0.55, 0.2), vec3(0.42, 0.66, 0.26), big) * (0.94 + 0.1 * n);
	vec3 c_for = mix(vec3(0.14, 0.34, 0.12), vec3(0.2, 0.42, 0.16), big) * (0.9 + 0.18 * n);
	vec3 c_rock = mix(vec3(0.46, 0.44, 0.41), vec3(0.58, 0.55, 0.5), big) * (0.88 + 0.2 * n);
	vec3 c_des = mix(vec3(0.85, 0.72, 0.44), vec3(0.93, 0.8, 0.52), big) * (0.94 + 0.06 * rip) * (0.96 + 0.06 * n);
	vec3 c_sw = mix(vec3(0.24, 0.3, 0.17), vec3(0.17, 0.24, 0.14), big) * (0.9 + 0.2 * n);
	ALBEDO = c_farm * farm + c_for * fo + c_rock * ro + c_des * de + c_sw * sw;
	ROUGHNESS = 1.0;
}
"""

const MINI := [Color(0.38, 0.65, 0.3), Color(0.17, 0.42, 0.17), Color(0.55, 0.53, 0.5), Color(0.9, 0.78, 0.5), Color(0.28, 0.36, 0.22)]


static func warp(x: float, z: float) -> Vector2:
	return Vector2(x + sin(x * 0.011 + z * 0.007) * 60.0 + sin(z * 0.017 - x * 0.005) * 40.0,
		z + sin(z * 0.012 - x * 0.008) * 60.0 + sin(x * 0.019 + z * 0.006) * 40.0)


static func weights(x: float, z: float) -> Array:
	var w := warp(x, z)
	var qx := (w.x - x) * 0.25 + x
	var qz := (w.y - z) * 0.25 + z
	var d := maxf(absf(qx), absf(qz))
	var farm := 1.0 - smoothstep(225.0, 285.0, d)
	var east := smoothstep(-70.0, 70.0, w.x)
	var south := smoothstep(-70.0, 70.0, w.y)
	var o := 1.0 - farm
	return [farm, o * (1.0 - east) * (1.0 - south), o * east * (1.0 - south), o * east * south, o * (1.0 - east) * south]


static func mini_color(x: float, z: float) -> Color:
	var w: Array = weights(x, z)
	var c := Color(0, 0, 0, 0.95)
	for i in 5:
		var m: Color = MINI[i]
		c.r += m.r * float(w[i])
		c.g += m.g * float(w[i])
		c.b += m.b * float(w[i])
	return c
