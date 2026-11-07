extends SceneTree
## An evolution waiting for sacrifices outlines and tags the cards that may be sacrificed, marks the chosen
## ones, dims the rest and shows "N of M chosen". Pass --render to save a screenshot.
var checks := 0
var failures := 0
var game: Node

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + text)

func frames(count: int = 5) -> void:
	for i in count: await process_frame

func add_threat(title: String, lane: int) -> Node:
	var card: Node = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup({"name": title, "type": "disaster", "element": "fire", "cost": 0, "attack": 1, "health": 3})
	card.place_on_slot(game._threat_slots()[lane])
	return card

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	game.run_director.persistence.enabled = false
	game.clear_battle()
	game.run_director.battle_active = true
	game.run_director.close_modal()
	game.encounter_kind = "versus"
	game.disaster_is_human = true
	game.disaster_seat_view = true
	game.set_seats("local", "local")
	game.run_director.privacy_serial = game.encounter_serial
	game.run_director.privacy_last = "disaster"
	game.run_director.privacy_screen.hide()
	game.disaster_waiting = true
	game._set_phase(game.Phase.ENEMY)
	await frames()
	var first := add_threat("First", 0)
	var second := add_threat("Second", 1)
	var third := add_threat("Third", 2)
	var sealed := add_threat("Sealed", 3)
	sealed.card_data.seal_round = game.turn
	await frames()
	var seat: Node = game.disaster_seat
	expect(seat.active, "the Disaster seat is on")
	var definition := {"name": "Evo", "type": "disaster", "element": "fire", "cost": 2, "attack": 4, "health": 6}
	seat.evo = {"card": first, "definition": definition, "slot": first.current_slot, "chosen": [first],
		"serial": game.encounter_serial}
	await frames()
	expect(first.sacrifice_mark == "chosen", "the first sacrifice is marked chosen")
	expect(second.sacrifice_mark == "pick" and third.sacrifice_mark == "pick", "other legal cards are marked pick")
	expect(sealed.sacrifice_mark == "dim", "a card that cannot be sacrificed is dimmed")
	expect(second._sacrifice_tag.visible and second._sacrifice_tag.text == "SACRIFICE", "a pickable card has the tag")
	expect(first._sacrifice_tag.text == "CHOSEN", "a chosen card says CHOSEN")
	expect(second._sacrifice_outline.visible, "a pickable card has an outline")
	var counter: Label = game.get_node("HUD/Root/SacrificeCounter")
	expect(counter.visible and counter.text == "Sacrifice: 1 of 2 chosen", "the counter reads 1 of 2 chosen")
	if "--render" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await create_timer(0.4, true).timeout
		await RenderingServer.frame_post_draw
		var folder := ProjectSettings.globalize_path("res://../docs/notes/queue-shots")
		DirAccess.make_dir_recursive_absolute(folder)
		root.get_texture().get_image().save_png(folder.path_join("sacrifice-marks.png"))
	seat.evo = {}
	await frames()
	expect(first.sacrifice_mark == "" and second.sacrifice_mark == "" and sealed.sacrifice_mark == "",
		"marks clear when no evolution is pending")
	expect(not counter.visible, "the counter hides when nothing is pending")
	game.clear_battle()
	paused = false
	game.queue_free()
	await frames()
	print("%s: sacrifice_marks (%d checks)" % ["FAIL" if failures else "PASS", checks])
	quit(1 if failures else 0)
