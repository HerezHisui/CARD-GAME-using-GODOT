extends SceneTree
## The evolution offer: three cards in one centered row, equal gaps, equal-width Choose buttons on one line
## at the bottom of each card. Pass --render to save screenshots at 1280x720 and 1920x1080.
var checks := 0
var failures := 0
var game: Node

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + text)

func frames(count: int = 8) -> void:
	for i in count: await process_frame

func evolution(title: String, element: String, cost: int) -> Dictionary:
	return {"name": title, "type": "disaster", "element": element, "cost_type": "sacrifice", "cost": cost,
		"attack": 4 + cost, "health": 6 + cost}

func capture(label: String) -> void:
	if "--render" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	await frames(4)
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../docs/notes/queue-shots")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join(label + ".png"))

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	var director: Node = game.run_director
	director.persistence.enabled = false
	game.clear_battle()
	director.battle_active = true
	game.encounter_kind = "versus"
	game.disaster_is_human = true
	game.evolution_draw_choice_override = true
	game.set_seats("local", "local")
	game.enemy_evolution_deck.assign([evolution("Aftershock Choir", "earthquake", 2),
		evolution("Whiteout", "typhoon", 3), evolution("Firestorm", "fire", 1)])
	game.evolution_choice.reset()
	game.evolution_choice.draw()
	expect(game.evolution_choice.pending(), "an offer of three is pending")
	game.evolution_choice.show_offer()
	for target: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		if DisplayServer.get_name() != "headless": root.size = target
		await frames(12)
		check_row(director, str(target))
		await capture("evolution-offer-%dx%d" % [target.x, target.y])
	game.clear_battle()
	paused = false
	game.queue_free()
	await frames()
	print("%s: evolution_offer_layout (%d checks)" % ["FAIL" if failures else "PASS", checks])
	quit(1 if failures else 0)

func check_row(director: Node, label: String) -> void:
	var row: Control = director.content.get_node("Row")
	var tiles: Array = row.get_children()
	expect(tiles.size() == 3, label + ": three tiles")
	if tiles.size() != 3: return
	var screen: Rect2 = director.content.get_global_rect()
	var first: Rect2 = tiles[0].get_global_rect()
	var last: Rect2 = tiles[2].get_global_rect()
	var left_space := first.position.x - screen.position.x
	var right_space := screen.end.x - last.end.x
	expect(absf(left_space - right_space) <= 2.0, label + ": row centered (%.1f vs %.1f)" % [left_space, right_space])
	var gap_a: float = tiles[1].get_global_rect().position.x - first.end.x
	var gap_b: float = last.position.x - tiles[1].get_global_rect().end.x
	expect(absf(gap_a - gap_b) <= 1.0 and gap_a > 0.0, label + ": equal gaps (%.1f, %.1f)" % [gap_a, gap_b])
	var width: float = first.size.x
	var bottoms: Array = []
	# The Choose button is gone: a double click on the card chooses it.
	for tile in tiles:
		expect(absf(tile.get_global_rect().size.x - width) <= 1.0, label + ": tiles are equal width")
		expect(not tile.has_node("Box/ActionButton"), label + ": cards have no Choose button")
		expect(tile.has_meta("pick_name") and tile.focus_mode == Control.FOCUS_ALL,
			label + ": card is pickable by double click and focus")
		bottoms.append(tile.get_global_rect().end.y)
	var glow_before: StyleBox = tiles[0].get_theme_stylebox("panel")
	tiles[0].mouse_entered.emit()
	expect(tiles[0].get_theme_stylebox("panel") != glow_before, label + ": hover glows the card")
	tiles[0].mouse_exited.emit()
	expect(tiles[0].get_theme_stylebox("panel") == glow_before, label + ": glow ends when the mouse leaves")
	expect(absf(bottoms[0] - bottoms[1]) <= 1.0 and absf(bottoms[1] - bottoms[2]) <= 1.0,
		label + ": cards share one bottom line")
