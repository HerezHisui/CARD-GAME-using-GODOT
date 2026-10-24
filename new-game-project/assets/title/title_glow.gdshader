shader_type canvas_item;
// Fake bloom for the title art: adds a blurred copy of the bright parts on top.
// The blur comes from the texture's mipmaps, so turn on mipmaps in the import tab.
// The threshold keeps the dark hallway dark; only the red circle and the eyes glow.

uniform float strength = 1.0;
uniform float threshold = 0.16;
// How much the glow swells and fades, and how fast (radians per second).
uniform float pulse_amount = 0.25;
uniform float pulse_speed = 1.1;
// UV x range where bright spots (the eyes) are shut. x > y means no eyes are shut.
uniform vec2 blink_band = vec2(1.0, 0.0);
uniform float eye_threshold = 0.6;

vec3 bright(vec3 color) {
	return max(color - vec3(threshold), vec3(0.0));
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec3 glow = bright(textureLod(TEXTURE, UV, 3.0).rgb) * 0.5;
	glow += bright(textureLod(TEXTURE, UV, 4.5).rgb) * 0.35;
	glow += bright(textureLod(TEXTURE, UV, 6.0).rgb) * 0.3;
	// Blink: bright spots inside the band go dark, and so does their glow.
	float in_band = step(blink_band.x, UV.x) * step(UV.x, blink_band.y);
	float lit = max(base.r, max(base.g, base.b));
	float eye = smoothstep(eye_threshold, eye_threshold + 0.15, lit) * in_band;
	base.rgb = mix(base.rgb, base.rgb * 0.1, eye);
	glow *= 1.0 - 0.7 * in_band;
	float pulse = 1.0 + pulse_amount * sin(TIME * pulse_speed);
	COLOR = vec4(base.rgb + glow * strength * pulse, base.a);
}
