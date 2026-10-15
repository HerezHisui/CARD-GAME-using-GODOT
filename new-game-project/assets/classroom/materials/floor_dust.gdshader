shader_type spatial;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_map : filter_linear_mipmap_anisotropic;
varying float dust;
void vertex() { dust = COLOR.a; }
void fragment() {
	vec3 surface = texture(albedo_map, UV).rgb;
	vec3 orm = texture(orm_map, UV).rgb;
	ALBEDO = mix(surface, vec3(.21,.215,.22), dust * .6);
	ROUGHNESS = mix(orm.g, .9, dust);
	METALLIC = orm.b;
	AO = orm.r;
	NORMAL_MAP = texture(normal_map, UV).rgb;
	NORMAL_MAP_DEPTH = .6;
}
