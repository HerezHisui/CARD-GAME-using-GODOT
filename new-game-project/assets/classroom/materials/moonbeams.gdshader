shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
void fragment() {
	float edge = smoothstep(0.0,.2,UV.x) * (1.0-smoothstep(.8,1.0,UV.x));
	float fade = (1.0-UV.y) * smoothstep(0.0,.08,UV.y);
	ALBEDO = vec3(.45,.6,.9);
	ALPHA = edge * fade * .04;
}
