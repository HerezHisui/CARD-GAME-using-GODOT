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
	game.presentation.automated_choice = 0
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
	if game.phase == game.Phase.PLAYER_DRAW and not game.deck.is_empty():
		game.complete_draw_choice(game.deck[0])
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
	await capture("triage_reward")
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
	await balance_checks()
	print("PASS: opening conservation, triage once-only, 100 routes, starter preservation, deck isolation, coinflip, combat, modifiers, rewards, upgrades, persistent health, elite scaling")
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

func preview_opening(cards: Array) -> Array:
	var pending := cards.duplicate(true)
	var opening := []
	for i in game.STARTING_HAND:
		var available := pending.filter(func(card): return not game.is_sealed(card))
		if available.is_empty(): break
		var picked: Dictionary = available.back()
		opening.append(picked)
		pending.erase(picked)
	return opening

func balance_checks() -> void:
	game.clear_battle()
	director.floor_number = 1
	game.encounter_kind = "battle"
	game.turn = 1
	var blocker := {"id":"quick_dash", "cost":1, "health":1}
	var other := {"id":"other", "cost":3, "health":3}
	var upgraded := {"id":"debris_clearance", "cost":1, "health":4, "upgrades":2}
	var sealed := blocker.duplicate(true)
	sealed.locked_until = 3
	var cases: Array = [[], [other], [blocker], [blocker, other, other, other, other], [other, blocker, other, other, other, other], [upgraded, other, other, other, other], [sealed, other, other, other], [blocker, other, upgraded], [blocker, other, other, other, other, other, other, other]]
	for cards in cases:
		game.deck.assign(cards.duplicate(true))
		var before: Array = game.deck.duplicate(true)
		var needs_blocker: bool = not preview_opening(before).any(game.is_opening_blocker)
		game.smooth_opening_hand()
		var remaining: Array = game.deck.duplicate(true)
		for definition in before:
			check(definition in remaining, "opening preserves every definition and duplicate count")
			remaining.erase(definition)
		check(remaining.is_empty() and game.deck.size() == before.size(), "opening preserves deck size")
		if before.any(game.is_opening_blocker):
			check(preview_opening(game.deck).any(game.is_opening_blocker), "eligible blocker enters actual opening")
		if not needs_blocker or not before.any(game.is_opening_blocker):
			check(game.deck == before, "already eligible or unavailable opening stays unchanged")
		else:
			var expected: Array = before.duplicate(true)
			for i in expected.size():
				if game.is_opening_blocker(expected[i]):
					expected.append(expected.pop_at(i))
					break
			check(game.deck == expected, "only one existing copy moves, preserving all other order")
	for floor_number in [1, 2, 3]:
		for kind in ["battle", "elite", "boss"]:
			director.floor_number = floor_number
			game.encounter_kind = kind
			game.deck.assign([blocker, other, other, other, other])
			var before: Array = game.deck.duplicate(true)
			game.smooth_opening_hand()
			if floor_number != 1 or kind != "battle": check(game.deck == before, "smoothing stays scoped to Floor 1 normals")
	game.clear_battle()
	game.presentation.blocking = false
	for floor_number in [1, 2, 3]:
		director.floor_number = floor_number
		for hp in [10, 18, 20]:
			director.battle_active = true
			director.encounter = "battle"
			game.player_hp = hp
			director.battle_finished(true)
			check(game.player_hp == mini(20, hp + 3), "normal victory triage caps at twenty on every floor")
			director.battle_finished(true)
			check(game.player_hp == mini(20, hp + 3), "duplicate victory callback cannot heal twice")
	for kind in ["elite", "boss"]:
		director.floor_number = 1
		director.encounter = kind
		director.battle_active = true
		game.player_hp = 10
		director.battle_finished(true)
		check(game.player_hp == 10, "Elite and Boss victories receive no triage")
	director.encounter = "battle"
	director.battle_active = true
	game.player_hp = 0
	director.battle_finished(false)
	check(game.player_hp == 0, "defeat receives no healing")
	director.new_run()
	game.clear_battle()
	director.battle_active = true
	director.encounter = "battle"
	game.player_hp = 10
	director.battle_finished(true)
	check(director.persistence.checkpoint(), "reward screen checkpoints")
	check(director.persistence.resume() and director.screen == "reward" and game.player_hp == 13, "reward Continue does not award triage twice")
	await capture("reward_continue")
	director.persistence.discard()
	await process_frame
