shader_type spatial;
render_mode diffuse_burley;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 p = (UV - 0.5) * vec2(4.34, 2.5);
	float grain = hash(floor(UV * vec2(640.0, 380.0)));
	vec3 slate = mix(vec3(0.105, 0.125, 0.104), vec3(0.17, 0.19, 0.15), grain * 0.28);
	float column = clamp(floor((p.x + 1.82) / 0.91), 0.0, 3.0);
	vec2 local = abs(p - vec2((column - 1.5) * 0.91, sign(p.y) * 0.63));
	vec2 edge = abs(local - vec2(0.385, 0.525));
	float corners = max((1.0 - smoothstep(0.003, 0.012, edge.x)) * (1.0 - smoothstep(0.08, 0.14, edge.y)), (1.0 - smoothstep(0.003, 0.012, edge.y)) * (1.0 - smoothstep(0.08, 0.14, edge.x)));
	float wear = 0.55 + hash(floor(UV * 180.0)) * 0.45;
	ALBEDO = mix(slate, vec3(0.46, 0.48, 0.37), corners * wear * 0.55);
	ROUGHNESS = 0.94;
}
