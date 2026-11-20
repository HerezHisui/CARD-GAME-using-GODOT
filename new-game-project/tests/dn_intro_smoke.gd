extends SceneTree
## The Drill Night intro: shows on the first new run, closes by Begin, click, Space or Esc, then never again.
## The drill, Versus and LAN never show it. The menu "Intro" shows it again.
const CAP := 600
const LINES := [
	"Drill Night. The whole school sleeps over for the emergency drill.",
	"At midnight, the drill stops being a drill.",
	"Stay together. Use what you practised. Make it to dawn.",
]
var failures := 0
var game: Node
var director: Node

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failures += 1
	push_error(message)

func frames(count: int = 10) -> void:
	for i in count: await process_frame

func wait_until(test: Callable) -> bool:
	for i in CAP:
		if test.call(): return true
		await process_frame
	return test.call()

func texts(node: Node, out: Array) -> Array:
	if node is Label: out.append(node.text)
	for child in node.get_children(): texts(child, out)
	return out

func find_button(text: String) -> Button:
	for node in director.content.find_children("*", "Button", true, false):
		if node.text == text: return node
	return null

func frame(name: String) -> void:
	# Frames only in a real window; headless runs skip them.
	if DisplayServer.get_name() == "headless": return
	for size in [Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = size
		for i in 20: await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("C:/Users/0stef/Downloads/drrills-frames")
		root.get_texture().get_image().save_png("C:/Users/0stef/Downloads/drrills-frames/dn-intro-%s-%d.png"
			% [name, size.x])
	root.size = Vector2i(1280, 800)

## Writes seen_intro into this test's own settings file.
func set_seen(value: bool) -> void:
	var settings := ConfigFile.new()
	settings.load(game.visual_settings_path())
	settings.set_value("visuals", "seen_intro", value)
	settings.save(game.visual_settings_path())

func seen() -> bool:
	var settings := ConfigFile.new()
	settings.load(game.visual_settings_path())
	return bool(settings.get_value("visuals", "seen_intro", false))

func new_scene() -> void:
	if is_instance_valid(game):
		game.queue_free()
		await frames(2)
	paused = false
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	game.intro_override = true
	await frames()

## A real left click at a window point, press then release.
func click_at(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		root.push_input(event)
		await process_frame

func press_key(keycode: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		root.push_input(event)
		await process_frame

## A new run with the intro not seen yet. Returns true when the intro shows.
func fresh_intro() -> bool:
	set_seen(false)
	director.new_run()
	await frames()
	return director.screen == "intro"

func run() -> void:
	root.size = Vector2i(1280, 800)
	await new_scene()

	# First new run: the intro with its title and three exact lines, over a saved map.
	check(await fresh_intro(), "First new run shows the intro (screen %s)" % director.screen)
	var panel: Array = texts(director.content, [])
	check("DRILL NIGHT" in panel, "Intro title reads DRILL NIGHT: %s" % [panel])
	for line in LINES: check(line in panel, "Intro line shows: %s" % line)
	check(director.persistence.has_run(), "The new run is saved under the intro")
	await frame("first")

	# Begin closes it, goes to the map and saves seen_intro.
	var begin := find_button("Begin")
	check(begin != null, "Intro has a Begin button")
	if begin: begin.pressed.emit()
	await frames()
	check(director.screen == "map", "Begin opens the map (screen %s)" % director.screen)
	check(seen(), "Closing the intro saves seen_intro")

	# A real click on Begin closes it.
	check(await fresh_intro(), "Intro shows again with seen_intro false")
	begin = find_button("Begin")
	if begin: await click_at(begin.get_global_rect().get_center())
	check(await wait_until(func(): return director.screen == "map"), "A real click closes the intro")
	check(seen(), "The click saves seen_intro")

	# A real click anywhere closes it too.
	check(await fresh_intro(), "Intro shows for the empty-space click")
	await click_at(Vector2(20, 780))
	check(await wait_until(func(): return director.screen == "map"), "A click anywhere closes the intro")

	# Space, Enter and Esc each close it. Other keys do not.
	for key in [KEY_SPACE, KEY_ENTER, KEY_ESCAPE]:
		check(await fresh_intro(), "Intro shows for key %d" % key)
		await press_key(KEY_D)
		check(director.screen == "intro", "Key D does not close the intro or open the deck")
		await press_key(key)
		check(await wait_until(func(): return director.screen == "map"), "Key %d closes the intro" % key)
		check(seen(), "Key %d saves seen_intro" % key)

	# Second new run: seen_intro is true, so the map comes straight away.
	director.new_run()
	await frames()
	check(director.screen == "map", "Second new run skips the intro (screen %s)" % director.screen)

	# The menu "Intro" shows it again, keeps the flag, and Begin goes back to the menu.
	director.show_menu()
	await frames()
	var replay := find_button("Intro")
	check(replay != null, "The menu has an Intro entry")
	if replay: replay.pressed.emit()
	await frames()
	check(director.screen == "intro", "Menu Intro shows the intro (screen %s)" % director.screen)
	check(seen(), "Menu Intro keeps seen_intro true")
	await press_key(KEY_ESCAPE)
	check(await wait_until(func(): return director.screen == "menu"), "Closing a replay returns to the menu")
	director.close_modal()
	await frames()

	# Without intro_override a tests/ run never shows it.
	game.intro_override = null
	set_seen(false)
	director.new_run()
	await frames()
	check(director.screen == "map", "Under tests/ the intro stays off without the override")
	director.persistence.discard()

	# The drill never shows it.
	await new_scene()
	set_seen(false)
	game.tutorial_override = true
	check(preload("res://scripts/tutorial.gd").start(director), "The drill starts")
	await frames(30)
	check(director.screen != "intro" and director.encounter == "tutorial", "The drill starts without the intro")

	# Versus never shows it.
	await new_scene()
	set_seen(false)
	game.disaster_is_human = false
	director.start_versus_match()
	await frames(30)
	check(director.screen != "intro" and game.encounter_kind == "versus", "Versus starts without the intro")

	# LAN: the lobby opens without it. A LAN match starts as lan_title.start_lan_match does:
	# seats, then start_versus_match. No network here; lan_smoke covers the real link.
	await new_scene()
	set_seen(false)
	director.open_lan_lobby()
	await frames()
	check(director.screen != "intro", "The LAN lobby opens without the intro")
	game.disaster_is_human = false
	game.set_seats("local", "remote")
	director.start_versus_match()
	await frames(30)
	check(director.screen != "intro" and game.encounter_kind == "versus", "A LAN match starts without the intro")
	check(not seen(), "Nothing outside a new run marks the intro seen")

	game.queue_free()
	await frames(2)
	print("DN INTRO: %d failures" % failures)
	quit(1 if failures else 0)
