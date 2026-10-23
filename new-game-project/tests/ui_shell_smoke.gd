# Covers: the UI shell built from scenes under scenes/ui and its named theme styles.
extends SceneTree

const UI = preload("res://scripts/ui_theme.gd")
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failures += 1
	push_error("FAILED: " + message)

func run() -> void:
	for source in [["file", load(UI.THEME_PATH)], ["build_theme", UI.build_theme()]]:
		theme_styles(source[1], source[0])
	if failures == 0: print("PASS: UI shell scenes and theme styles")
	quit(1 if failures else 0)

## Expected look of each named style, built the same way the old code built it.
func expected_styles() -> Array:
	return [
		["HeaderPanel", "PanelContainer", "panel", UI.panel(UI.PANEL)],
		["ModalPanel", "PanelContainer", "panel", UI.panel(UI.PANEL, UI.GOLD)],
		["DashboardPanel", "PanelContainer", "panel", UI.panel(UI.INSET, UI.BRONZE)],
		["PromptPanel", "PanelContainer", "panel", UI.panel(UI.BACKGROUND, UI.RESPONSE)],
		["EnergyBar", "ProgressBar", "background", UI.panel(UI.INSET, UI.BRONZE, 0)],
		["EnergyBar", "ProgressBar", "fill", UI.bar(UI.RESPONSE)],
		["TensionBar", "ProgressBar", "background", UI.panel(UI.INSET, UI.BRONZE, 0)],
		["TensionBar", "ProgressBar", "fill", UI.bar(UI.DANGER)],
	]

func theme_styles(theme: Theme, source: String) -> void:
	for spec in expected_styles():
		var label := "%s %s %s" % [source, spec[0], spec[2]]
		check(theme.get_type_variation_base(spec[0]) == StringName(spec[1]), label + " variation base")
		check(theme.has_stylebox(spec[2], spec[0]), label + " exists")
		if theme.has_stylebox(spec[2], spec[0]): same_style(theme.get_stylebox(spec[2], spec[0]), spec[3], label)
	check(theme.get_type_variation_base("HeadingLabel") == &"Label", source + " HeadingLabel variation base")
	var font: Font = theme.get_font("font", "HeadingLabel") if theme.has_font("font", "HeadingLabel") else null
	check(font is SystemFont and font.font_names == UI.font(true).font_names and font.font_weight == 700,
		source + " HeadingLabel uses the heading font")

func same_style(actual: StyleBox, expected: StyleBoxFlat, label: String) -> void:
	check(actual is StyleBoxFlat, label + " is flat")
	if not actual is StyleBoxFlat: return
	var box: StyleBoxFlat = actual
	check(box.bg_color.is_equal_approx(expected.bg_color), label + " bg_color")
	check(box.border_color.is_equal_approx(expected.border_color), label + " border_color")
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		check(box.get_border_width(side) == expected.get_border_width(side), label + " border width")
		check(is_equal_approx(box.get_content_margin(side), expected.get_content_margin(side)), label + " margin")
	for corner in [CORNER_TOP_LEFT, CORNER_TOP_RIGHT, CORNER_BOTTOM_RIGHT, CORNER_BOTTOM_LEFT]:
		check(box.get_corner_radius(corner) == expected.get_corner_radius(corner), label + " corner radius")
	check(box.corner_detail == expected.corner_detail, label + " corner detail")
