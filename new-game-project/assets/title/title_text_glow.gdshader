shader_type canvas_item;
// Used on a CanvasGroup: draws a blurred copy of what is inside it, as a soft halo.
// The group needs use_mipmaps on, and a fit margin big enough for the blur.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float strength = 0.5;

void fragment() {
	vec4 halo = textureLod(screen_texture, SCREEN_UV, 3.0) * 0.5;
	halo += textureLod(screen_texture, SCREEN_UV, 4.5) * 0.5;
	// The group's buffer has premultiplied alpha.
	if (halo.a > 0.0001) {
		halo.rgb /= halo.a;
	}
	COLOR = vec4(halo.rgb, halo.a * strength);
}
