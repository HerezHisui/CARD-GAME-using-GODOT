shader_type canvas_item;
// Fake bloom for the title art: adds a blurred copy of the bright parts on top.
// The blur comes from the texture's mipmaps, so turn on mipmaps in the import tab.
// The threshold keeps the dark hallway dark; only the bright spots glow.
// The picture also gets a light blur, except a soft oval around the silhouette.

uniform float strength = 0.3;
uniform float threshold = 0.16;
// How much the glow swells and fades, and how fast (radians per second).
uniform float pulse_amount = 0.25;
uniform float pulse_speed = 1.1;
// Blur reach in texture pixels.
uniform float blur_pixels = 5.0;
// Oval (center and radius in UV) where the silhouette stays sharper.
uniform vec2 sharp_center = vec2(0.5, 0.54);
uniform vec2 sharp_radius = vec2(0.22, 0.38);
// 1.0 means fully sharp in the middle of the oval.
uniform float sharp_amount = 1.0;

vec3 bright(vec3 color) {
	return max(color - vec3(threshold), vec3(0.0));
}

void fragment() {
	vec4 sharp = texture(TEXTURE, UV);
	// A small 3x3 gaussian blur (weights 1-2-1). TEXTURE can not be passed to a function.
	vec2 step_size = TEXTURE_PIXEL_SIZE * blur_pixels;
	vec4 soft = vec4(0.0);
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			float weight = (2.0 - abs(float(x))) * (2.0 - abs(float(y)));
			soft += texture(TEXTURE, UV + vec2(float(x), float(y)) * step_size) * weight;
		}
	}
	soft /= 16.0;
	float oval = length((UV - sharp_center) / sharp_radius);
	vec4 base = mix(soft, sharp, (1.0 - smoothstep(0.6, 1.0, oval)) * sharp_amount);
	vec3 glow = bright(textureLod(TEXTURE, UV, 3.0).rgb) * 0.5;
	glow += bright(textureLod(TEXTURE, UV, 4.5).rgb) * 0.35;
	glow += bright(textureLod(TEXTURE, UV, 6.0).rgb) * 0.3;
	float pulse = 1.0 + pulse_amount * sin(TIME * pulse_speed);
	COLOR = vec4(base.rgb + glow * strength * pulse, base.a);
}
