extends SceneTree
## Integration checks for run state, route legality, and battle transitions.
var game: Node
var director: Node

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error("FAILED: " + message)
		quit(1)
		assert(condition, message)

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	director = game.run_director
	director.new_run()
	check(director.collection.size() == 12, "original starter deck preserved")
	for seed_value in range(100):
		director.rng.seed = seed_value
		director.generate_map()
		check(director.rooms.size() == 31, "map room count")
		for room in director.rooms:
			if room.row < 10: check(not room.links.is_empty(), "no dead ends")
			for id in room.links:
				check(director.rooms[id].row == room.row + 1, "only forward edges")
		var reachable_rooms: Array = [0, 1, 2]
		for room in director.rooms:
			if room.id in reachable_rooms:
				for id in room.links:
					if id not in reachable_rooms: reachable_rooms.append(id)
		check(reachable_rooms.size() == 31, "all rooms reachable from starting lanes")
	director.rng.seed = director.run_seed
	director.generate_map()
	check(not director.reachable(30), "boss cannot be skipped to")
	director.show_map()
	await capture("map")
	director.show_deck()
	await capture("deck")
	director.screen = ""
	director.visit(0)
	check(director.battle_active, "battle begins at room")
	check(not director.reachable(1), "cannot leave active encounter")
	await until_player_turn()
	game._on_draw_button_pressed()
	check(game.can_player_act(), "coinflip and turn flow reach player play")
	await capture("battle")
	var permanent_hp: int = director.collection[0].health
	var card = game.get_hand_cards()[0]
	card.card_data.health = 99
	check(director.collection[0].health == permanent_hp, "battle mutation cannot affect collection")
	card.card_data.health = card.max_health
	card.add_modifier("armored")
	check(card.adjusted_damage(4) == 3, "armor damage adjustment")
	card.add_modifier("fragile")
	check(card.adjusted_damage(4) == 4, "fragile stacks with armor")
	game.on_card_played(card)
	card.reparent(game)
	card.place_on_slot(game._response_slots()[0])
	await create_timer(0.4).timeout
	game._on_end_turn_pressed()
	for i in range(250):
		if game.turn >= 2 or game.phase == game.Phase.GAME_OVER: break
		await create_timer(0.1).timeout
	check(game.turn >= 2 or game.phase == game.Phase.GAME_OVER, "combat completes without hanging")
	if director.battle_active:
		game.enemy_hp = 0
		game._check_game_over()
	check(director.screen == "reward", "battle victory opens reward")
	var count: int = director.collection.size()
	director.collection.append(director.offers(1)[0])
	director.finish_room()
	check(director.collection.size() == count + 1, "reward extends permanent deck")
	check(0 in director.cleared, "cleared room recorded")
	check(director.reachable(director.rooms[0].links[0]), "connected next room unlocked")
	director.current = director.rooms[0].links[0]
	var attack: int = director.collection[0].attack
	director.upgrade(0)
	check(director.collection[0].attack == attack + 1, "upgrade persists")
	var hp: int = game.player_hp
	game.start_encounter(director.collection, "elite", 2, 1)
	check(game.player_hp == hp, "health persists between encounters")
	check(game.enemy_max_hp == 27, "elite floor scaling")
	check(game.deck.size() + game.get_hand_cards().size() == director.collection.size(), "fresh encounter restores owned cards")
	print("PASS: 100 routes, starter preservation, deck isolation, coinflip, combat, modifiers, rewards, upgrades, persistent health, elite scaling")
	quit(0)

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await create_timer(0.4).timeout
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts")
	root.get_texture().get_image().save_png("res://tests/artifacts/" + name + ".png")

func until_player_turn() -> void:
	for i in range(200):
		if game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY, game.Phase.GAME_OVER]: return
		await create_timer(0.1).timeout
