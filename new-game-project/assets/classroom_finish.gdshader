shader_type canvas_item;
render_mode unshaded;
uniform sampler2D scene_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float sharpness : hint_range(0.0, 0.6) = 0.24;
uniform float clarity : hint_range(0.0, 0.2) = 0.075;
uniform float vignette : hint_range(0.0, 0.3) = 0.10;

void fragment() {
	vec2 pixel = SCREEN_PIXEL_SIZE;
	vec3 center = texture(scene_texture, SCREEN_UV).rgb;
	vec3 near_blur = (texture(scene_texture, SCREEN_UV + vec2(pixel.x, 0.0)).rgb
		+ texture(scene_texture, SCREEN_UV - vec2(pixel.x, 0.0)).rgb
		+ texture(scene_texture, SCREEN_UV + vec2(0.0, pixel.y)).rgb
		+ texture(scene_texture, SCREEN_UV - vec2(0.0, pixel.y)).rgb) * 0.25;
	vec2 broad = pixel * 7.0;
	vec3 broad_blur = (texture(scene_texture, SCREEN_UV + broad).rgb
		+ texture(scene_texture, SCREEN_UV - broad).rgb
		+ texture(scene_texture, SCREEN_UV + vec2(broad.x, -broad.y)).rgb
		+ texture(scene_texture, SCREEN_UV + vec2(-broad.x, broad.y)).rgb) * 0.25;
	// Limit local contrast to avoid halos around window bars and fine chair legs.
	vec3 detail = clamp((center - near_blur) * sharpness + (center - broad_blur) * clarity, vec3(-0.025), vec3(0.025));
	vec3 color = max(center + detail, vec3(0.0));
	float edge = smoothstep(0.24, 0.68, length((SCREEN_UV - 0.5) * vec2(1.0, 0.85)));
	COLOR = vec4(color * (1.0 - edge * vignette), 1.0);
}
