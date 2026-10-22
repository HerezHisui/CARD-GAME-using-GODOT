# Covers: the "Game" palette in data/ui_theme.tres and build_theme() keeps today's exact colors.
extends SceneTree

const UI = preload("res://scripts/ui_theme.gd")
const THEME_PATH := "res://data/ui_theme.tres"
# Frozen copy of the colors before the palette moved to the theme file. Update only on purpose.
const EXPECTED := {
	"background": "0b0b0d", "panel": "1e1c20", "raised": "2c292e", "inset": "111014",
	"bronze": "c69c49", "gold": "e0b963", "crimson": "8b1e24", "action": "b8252b",
	"amber": "d99b26", "text": "eae4dc", "muted": "8c867e", "disabled": "77716c",
	"response": "e0b963", "danger": "ed8985",
	"affinity_evac": "91ad59", "affinity_douse": "66a9b4", "affinity_clearance": "da9148",
	"affinity_brace": "b8bcc5", "affinity_earthquake": "c2aa57", "affinity_fire": "d65349",
	"affinity_flood": "598dc3", "affinity_typhoon": "a47bc1",
}
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failures += 1
	push_error("FAILED: " + message)

func run() -> void:
	check_palette(load(THEME_PATH), "file")
	check_palette(UI.build_theme(), "build_theme")
	if failures == 0: print("PASS: Game palette matches the frozen colors")
	quit(1 if failures else 0)

func check_palette(theme: Theme, source: String) -> void:
	var names: Array = Array(theme.get_color_list("Game"))
	names.sort()
	var expected_names: Array = EXPECTED.keys()
	expected_names.sort()
	check(names == expected_names, source + " Game color names")
	for name in EXPECTED:
		var color := theme.get_color(name, "Game")
		check(color.to_html(false) == EXPECTED[name] and is_equal_approx(color.a, 1.0), "%s %s" % [source, name])
