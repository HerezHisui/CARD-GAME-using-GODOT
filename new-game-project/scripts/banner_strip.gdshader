shader_type canvas_item;
render_mode unshaded;

uniform vec4 fill_color : source_color = vec4(0.067, 0.063, 0.078, 0.82);
uniform vec4 line_color : source_color = vec4(0.851, 0.608, 0.149, 1.0);

void fragment() {
	float edge = min(UV.x, 1.0 - UV.x);
	float strip_fade = smoothstep(0.0, 0.2, edge);
	float line_fade = smoothstep(0.2, 0.35, edge);
	float line_distance = min(abs(UV.y - 0.09), abs(UV.y - 0.91));
	float core = 1.0 - smoothstep(0.005, 0.018, line_distance);
	float glow = (1.0 - smoothstep(0.0, 0.07, line_distance)) * 0.3;
	float line_alpha = max(core, glow) * line_fade * line_color.a;
	float fill_alpha = fill_color.a * strip_fade;
	float alpha = line_alpha + fill_alpha * (1.0 - line_alpha);
	vec3 rgb = mix(fill_color.rgb, line_color.rgb, line_alpha / max(alpha, 0.001));
	COLOR *= vec4(rgb, alpha);
}
