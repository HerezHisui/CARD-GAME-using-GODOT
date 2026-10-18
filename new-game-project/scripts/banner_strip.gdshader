shader_type canvas_item;
render_mode unshaded;

uniform vec4 fill_color : source_color = vec4(0.067, 0.063, 0.078, 0.94);
uniform vec4 line_color : source_color = vec4(1.0, 0.757, 0.420, 1.0);
uniform float line_width = 2.5;

void fragment() {
	float edge = min(UV.x, 1.0 - UV.x);
	float strip_fade = smoothstep(0.0, 0.2, edge);
	float line_fade = smoothstep(0.2, 0.35, edge);
	float line_distance = min(abs(UV.y - 0.09), abs(UV.y - 0.91));
	float pixel_distance = line_distance / max(fwidth(UV.y), 0.0001);
	float core = 1.0 - smoothstep(line_width * 0.5 - 0.5, line_width * 0.5 + 0.5, pixel_distance);
	float glow = (1.0 - smoothstep(0.0, 8.0, pixel_distance)) * 0.55;
	float line_alpha = max(core, glow) * line_fade * line_color.a;
	float fill_alpha = fill_color.a * strip_fade;
	float alpha = line_alpha + fill_alpha * (1.0 - line_alpha);
	vec3 rgb = mix(fill_color.rgb, line_color.rgb, line_alpha / max(alpha, 0.001));
	COLOR *= vec4(rgb, alpha);
}
