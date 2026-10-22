# Covers: scenes/ui_gallery.tscn loads with the theme file and shows every UI group.
extends SceneTree

const SCENE_PATH := "res://scenes/ui_gallery.tscn"
const THEME_PATH := "res://data/ui_theme.tres"
const GROUPS := ["Buttons", "Labels", "Panels", "Gauges", "CardPlates", "Dialog", "Tooltip", "Toggles",
	"ScrollBars"]
const PREVIEW_TYPES := ["Button", "PrimaryButton", "TerminalButton"]
const PREVIEW_STATES := ["normal", "hover", "pressed", "disabled"]
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failures += 1
	push_error("FAILED: " + message)

func run() -> void:
	check(ResourceLoader.exists(SCENE_PATH), "gallery scene exists")
	if failures:
		quit(1)
		return
	var gallery: Control = load(SCENE_PATH).instantiate()
	root.add_child(gallery)
	await process_frame
	await process_frame
	check(gallery.theme == load(THEME_PATH), "gallery root uses the theme file")
	for group in GROUPS:
		check(gallery.find_child(group, true, false) != null, group + " group exists")
	check_previews(gallery)
	check_game_styles(gallery)
	await check_live_palette(gallery)
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene")
	check(not main_scene.contains("ui_gallery"), "game never starts the gallery")
	if failures == 0: print("PASS: ui gallery loads with every group")
	quit(1 if failures else 0)

func check_previews(gallery: Control) -> void:
	var found := {}
	for preview in gallery.find_children("*", "Control", true, false):
		if not preview.has_method("preview_style"): continue
		found["%s/%s" % [preview.theme_type, preview.state]] = true
		check(preview.preview_style() is StyleBox, "%s %s preview has a style" % [preview.theme_type, preview.state])
	for type in PREVIEW_TYPES:
		for state in PREVIEW_STATES:
			check(found.has("%s/%s" % [type, state]), "%s %s preview exists" % [type, state])

## Edits the loaded theme in memory only (never saved), like recoloring it in the editor.
func check_live_palette(gallery: Control) -> void:
	var file: Theme = gallery.theme
	var bar: ProgressBar = gallery.find_child("EnergyBar", true, false)
	var original := file.get_color("response", "Game")
	file.set_color("response", "Game", Color("123456"))
	await process_frame
	var fill: StyleBoxFlat = bar.get_theme_stylebox("fill")
	check(fill.bg_color.to_html(false) == "123456", "energy gauge follows a palette edit")
	file.set_color("response", "Game", original)
	await process_frame
	fill = bar.get_theme_stylebox("fill")
	check(fill.bg_color.is_equal_approx(original), "energy gauge returns when the edit is undone")

func check_game_styles(gallery: Control) -> void:
	for gauge in ["EnergyBar", "TensionBar", "PlayerHealthBar", "EnemyHealthBar"]:
		var bar: ProgressBar = gallery.find_child(gauge, true, false)
		check(bar != null and bar.has_theme_stylebox_override("fill"), gauge + " uses the game fill style")
	for plate in ["ResponsePlate", "DisasterPlate"]:
		var node: Control = gallery.find_child(plate, true, false)
		check(node != null and node.has_theme_stylebox_override("panel"), plate + " uses the card frame style")
	var dialog: Control = gallery.find_child("DialogBox", true, false)
	check(dialog != null and dialog.has_node("IndustrialTrim"), "dialog box has the game trim")
