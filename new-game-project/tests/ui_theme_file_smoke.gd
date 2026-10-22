# Covers: data/ui_theme.tres matches the theme ui_theme.gd builds in code.
extends SceneTree

const UI = preload("res://scripts/ui_theme.gd")
const THEME_PATH := "res://data/ui_theme.tres"
const KINDS := ["stylebox", "color", "constant", "font", "font_size", "icon"]
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failures += 1
	push_error("FAILED: " + message)

func run() -> void:
	check(ResourceLoader.exists(THEME_PATH), "theme file exists")
	if failures:
		quit(1)
		return
	var saved: Theme = load(THEME_PATH)
	var built: Theme = UI.build_theme()
	check(saved != built, "file is a separate resource from the code-built theme")
	check(UI.get_theme() == saved, "get_theme() returns the theme file")
	same_value(saved.default_font, built.default_font, "default_font")
	check(saved.default_font_size == built.default_font_size, "default_font_size")
	check(is_equal_approx(saved.default_base_scale, built.default_base_scale), "default_base_scale")
	check(sorted(saved.get_type_list()) == sorted(built.get_type_list()), "type list")
	for type in built.get_type_list():
		check(saved.get_type_variation_base(type) == built.get_type_variation_base(type), type + " variation base")
		for kind in KINDS: compare_kind(saved, built, type, kind)
	if failures == 0: print("PASS: ui_theme.tres matches the code-built theme")
	quit(1 if failures else 0)

func compare_kind(saved: Theme, built: Theme, type: String, kind: String) -> void:
	var names: Array = sorted(built.call("get_%s_list" % kind, type))
	check(sorted(saved.call("get_%s_list" % kind, type)) == names, "%s %s names" % [type, kind])
	for item in names:
		var label := "%s %s %s" % [type, kind, item]
		same_value(saved.call("get_" + kind, item, type), built.call("get_" + kind, item, type), label)

func same_value(saved: Variant, built: Variant, label: String) -> void:
	if built is Texture2D:
		check(saved is Texture2D and same_pixels(saved, built), label + " pixels")
	elif built is Resource:
		check(saved is Resource and saved.get_class() == built.get_class(), label + " class")
		if saved is Resource: same_stored_properties(saved, built, label)
	elif built is float:
		check(saved is float and is_equal_approx(saved, built), label)
	elif built is Color:
		check(saved is Color and saved.is_equal_approx(built), label)
	else:
		check(saved == built, label)

func same_stored_properties(saved: Resource, built: Resource, label: String) -> void:
	for property in built.get_property_list():
		var name: String = property.name
		if not (property.usage & PROPERTY_USAGE_STORAGE): continue
		if name.begins_with("resource_") or name == "script": continue
		same_value(saved.get(name), built.get(name), label + "." + name)

func same_pixels(saved: Texture2D, built: Texture2D) -> bool:
	var left := saved.get_image()
	var right := built.get_image()
	if left == null or right == null or left.get_size() != right.get_size(): return false
	left.convert(Image.FORMAT_RGBA8)
	right.convert(Image.FORMAT_RGBA8)
	return left.get_data() == right.get_data()

func sorted(values: Variant) -> Array:
	var result: Array = Array(values)
	result.sort()
	return result
