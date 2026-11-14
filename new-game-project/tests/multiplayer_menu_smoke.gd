extends SceneTree
## The Multiplayer entry on the title: the panel has Versus, LAN Versus and Back, all by real mouse input.

const VersusMatch = preload("res://scripts/versus_match.gd")

var failures := 0
var checks := 0
var game: Node
var director: Node


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + label)


func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	game.presentation.automated_choice = 0
	await process_frame
	expect(VersusMatch.LAN_ENABLED, "LAN_ENABLED is true in the repo")
	await check_title_and_panel()
	await check_lan_and_back()
	await check_versus()
	game.set_seats("local", "local")
	game.clear_battle()
	game.queue_free()
	await process_frame
	if failures > 0:
		quit(1)
		return
	print("PASS: multiplayer_menu_smoke (%d checks)" % checks)
	quit(0)


# The title has Multiplayer and no LAN button. The panel has exactly three buttons.
func check_title_and_panel() -> void:
	director.show_title()
	await frames(3)
	expect(find_button("Multiplayer") != null, "title: Multiplayer button")
	expect(find_button("LAN Versus") == null, "title: no LAN Versus button")
	expect(find_button("Versus") == null, "title: no separate Versus button")
	expect(not is_instance_valid(director.lan_title), "title: nothing LAN is made yet")
	await click(find_button("Multiplayer"))
	expect(find_label("MULTIPLAYER") != null, "panel: heading MULTIPLAYER")
	var names: Array = []
	for node in director.content.find_children("*", "Button", true, false):
		names.append(node.text)
	expect(names == ["Versus", "LAN Versus", "Back"], "panel: exactly Versus, LAN Versus, Back (got %s)" % [names])
	expect(not is_instance_valid(director.lan_title), "panel: nothing LAN is made yet")


# LAN Versus opens the lobby. Back goes to the panel. Back again goes to the title.
func check_lan_and_back() -> void:
	await click(find_button("LAN Versus"))
	expect(find_label("LAN VERSUS") != null, "LAN Versus opens the lobby")
	expect(is_instance_valid(director.lan_title), "LAN Versus makes the lan_title node")
	await frames(3)
	await click(find_button("Back"))
	expect(find_label("MULTIPLAYER") != null, "lobby Back returns to the panel")
	await frames(3)
	await click(find_button("Back"))
	expect(director.screen == "title", "panel Back returns to the title")


func check_versus() -> void:
	await frames(3)
	await click(find_button("Multiplayer"))
	await frames(3)
	await click(find_button("Versus"))
	await frames(5)
	var running: bool = is_instance_valid(director.versus_match) and director.versus_match.running
	expect(running, "Versus starts a match")


func frames(count: int) -> void:
	for i in count:
		await process_frame


# A real mouse click: motion first, then press and release on the middle of the control.
func click(control: Control) -> void:
	if control == null:
		expect(false, "click: control exists")
		return
	var center := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = center
	motion.global_position = center
	root.push_input(motion, true)
	await process_frame
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = center
	press.global_position = center
	press.pressed = true
	root.push_input(press, true)
	var release: InputEventMouseButton = press.duplicate()
	release.pressed = false
	root.push_input(release, true)
	await process_frame


func find_button(text: String) -> Button:
	for node in director.find_children("*", "Button", true, false):
		if node.text == text and node.is_visible_in_tree():
			return node
	return null


func find_label(text: String) -> Label:
	for node in director.content.find_children("*", "Label", true, false):
		if node.text == text:
			return node
	return null
