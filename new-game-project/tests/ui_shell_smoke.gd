# Covers: the UI shell built from scenes under scenes/ui and its named theme styles.
extends SceneTree

const UI = preload("res://scripts/ui_theme.gd")
const GAUGE_SCENE := "res://scenes/ui/ui_gauge.tscn"
const HEADER_SCENE := "res://scenes/ui/ui_header.tscn"
const PROMPT_SCENE := "res://scenes/ui/ui_board_prompt.tscn"
var failures := 0
var game: Node
var director: Node

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failures += 1
	push_error("FAILED: " + message)

func run() -> void:
	for source in [["file", load(UI.THEME_PATH)], ["build_theme", UI.build_theme()]]:
		theme_styles(source[1], source[0])
	await start_game()
	gauges()
	header()
	await board_prompt()
	await title_hides_header()
	if failures == 0: print("PASS: UI shell scenes and theme styles")
	quit(1 if failures else 0)

func start_game() -> void:
	root.size = Vector2i(1440, 900)
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	director.persistence.enabled = false
	await process_frame
	director.new_run()
	await process_frame

func gauges() -> void:
	var prep_box: Node = director.prep.get_parent()
	var threat_box: Node = director.threat.get_parent()
	check(prep_box.scene_file_path == GAUGE_SCENE, "energy gauge comes from ui_gauge.tscn")
	check(threat_box.scene_file_path == GAUGE_SCENE, "tension gauge comes from ui_gauge.tscn")
	check(prep_box.get_child_count() == 3 and threat_box.get_child_count() == 2, "gauge child counts")
	check(director.prep.theme_type_variation == &"EnergyBar", "energy bar style")
	check(director.threat.theme_type_variation == &"TensionBar", "tension bar style")
	check(director.prep.custom_minimum_size == Vector2(195, 20) and not director.prep.show_percentage,
		"gauge bar size and no percentage")

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

func header() -> void:
	var bar: Node = director.root.get_child(0)
	check(bar.scene_file_path == HEADER_SCENE, "top bar comes from ui_header.tscn and stays root child 0")
	check(director.summary == bar.get_node_or_null("%Summary"), "summary is the header's Summary label")
	check(director.map_button == bar.get_node_or_null("%MapButton"), "map button is the header's")
	check(director.menu_button == bar.get_node_or_null("%MenuButton"), "menu button is the header's")
	for button_name in ["%DeckButton", "%MapButton", "%MenuButton"]:
		var button: Node = bar.get_node_or_null(button_name)
		check(button != null and button.has_meta("hover_feedback"), button_name + " has hover feedback")

func title_hides_header() -> void:
	director.show_title()
	await process_frame
	check(not director.root.get_child(0).visible, "title screen hides the top bar")

func board_prompt() -> void:
	var prompt: Node = director.board_prompt
	check(prompt.scene_file_path == PROMPT_SCENE, "board prompt comes from ui_board_prompt.tscn")
	check(director.board_prompt_label == prompt.get_node_or_null("%PromptLabel"), "prompt label is the scene's")
	var cancel: Node = prompt.get_node_or_null("%CancelButton")
	check(cancel != null and cancel.has_meta("hover_feedback"), "prompt Cancel button has hover feedback")
	director.battle_active = true
	director.modal.hide()
	game.board_input.pick("Pick a test target", [], func(_card): pass, Callable())
	await process_frame
	check(prompt.visible and director.board_prompt_label.text == "Pick a test target", "open pick shows the prompt")
	if cancel: cancel.pressed.emit()
	check(game.board_input.action.is_empty(), "prompt Cancel button ends the pick")
	director.battle_active = false
