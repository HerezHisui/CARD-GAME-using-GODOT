shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_prepass_alpha;
uniform sampler2D card_face : source_color, filter_linear;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec4 face = texture(card_face, UV);
	vec2 cell = floor(UV * vec2(90.0, 120.0));
	float noise = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
	float threshold = UV.y * 0.65 + noise * 0.35;
	if (threshold < progress || face.a < 0.05) { discard; }
	float edge = 1.0 - smoothstep(progress, progress + 0.06, threshold);
	ALBEDO = mix(face.rgb, vec3(0.12, 0.055, 0.02), edge);
	EMISSION = vec3(1.3, 0.35, 0.04) * edge;
	ALPHA = face.a;
}
