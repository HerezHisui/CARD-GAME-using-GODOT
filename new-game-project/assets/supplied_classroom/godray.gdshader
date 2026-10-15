shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D beam_texture : source_color, filter_linear_mipmap;
void fragment() {
	vec4 beam = texture(beam_texture, UV);
	ALBEDO = vec3(.25, .28, .32);
	ALPHA = beam.a * beam.r * .018;
}
