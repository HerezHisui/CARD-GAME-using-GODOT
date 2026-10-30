extends SceneTree

var game: Node
var director: Node
var failures := 0
var output := ""

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failures += 1
	push_error(message)

func fixture() -> Node:
	paused = false
	game.clear_battle()
	game.player_buffs.clear()
	game.enemy_buffs.clear()
	game.player_run_buffs.clear()
	game.enemy_run_buffs.clear()
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game._set_phase(game.Phase.PLAYER_PLAY)
	game.turn = 1
	game.player_hp = 20
	game.enemy_hp = 34
	game.enemy_max_hp = 34
	game.final_boss = preload("res://scripts/final_boss.gd").new()
	game.add_child(game.final_boss)
	game.final_boss.setup(game)
	game._damage_side(false, 100)
	game.turn = 2
	game.final_boss.resolve_intent()
	return game.final_boss

func pillar(id: String) -> Node:
	for card in game.final_boss.pillars():
		if card.card_data.id == id: return card
	return null

func echoes() -> int:
	return game.get_hand_cards().filter(func(card): return card.card_data.get("curse", false)).size()

func remove_pillar(card: Node) -> void:
	card.current_slot = null
	card.remove_from_group("cards")
	card.queue_free()

func fill_hand(free_spaces: int = 0) -> void:
	while game.get_hand_cards().size() < game.HAND_SIZE_MAX - free_spaces:
		game.add_card_to_hand(director.catalog_card("quick_dash").duplicate(true))

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	root.size = Vector2i(1440, 900)
	game = preload("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	director.persistence.enabled = false
	director.new_run()
	await process_frame
	var boss := fixture()
	check(boss.stage == 2 and boss.pillars().size() == 2, "Actual phase transition creates both pillars")
	boss.prepare_round()
	check(echoes() == 0, "Pillars do not trigger on their spawn round")
	check(director.card_rules(pillar("pillar0").card_data).contains("additional Static Echo"),
		"West inspection explains its extra Echo")
	check(director.card_rules(pillar("pillar3").card_data).contains("1 HP"),
		"East inspection explains Guardian healing")
	boss.guardian().card_data.health = 2
	game.turn = 3
	boss.prepare_round()
	check(echoes() == 2, "West stacks one extra Echo with the existing baseline Echo")
	check(boss.guardian().card_data.health == 3, "East heals the living Guardian by exactly 1")
	boss.prepare_round()
	check(echoes() == 2 and boss.guardian().card_data.health == 3, "Repeated preparation applies neither twice")
	check(game.enemy_deck.is_empty() and game.enemy_hand.is_empty(), "Encounter stays scripted")
	await capture("pillar_support_round")
	if not output.is_empty():
		for id in ["pillar0", "pillar3"]:
			director.inspect_board_card(pillar(id))
			await capture(id + "_inspection")
			director.close_modal()
	check(director.persistence.checkpoint() and director.persistence.resume(), "Pillar turn saves and resumes")
	boss = game.final_boss
	boss.prepare_round()
	check(echoes() == 2 and boss.guardian().card_data.health == 3, "Continue cannot repeat applied support")
	game.turn = 4
	boss.prepare_round()
	check(echoes() == 4 and boss.guardian().card_data.health == 4, "Next round applies both support effects")
	game.turn = 5
	boss.prepare_round()
	check(boss.guardian().card_data.health == boss.guardian().max_health, "Guardian healing respects maximum HP")
	boss = fixture()
	boss.guardian().card_data.health = 2
	game.turn = 3
	check(director.persistence.checkpoint() and director.persistence.resume(), "Unprepared round resumes")
	boss = game.final_boss
	boss.prepare_round()
	check(echoes() == 2 and boss.guardian().card_data.health == 3,
		"Continue before preparation still applies support once")
	await removal_checks()
	await overflow_checks()
	director.persistence.discard()
	print("PILLAR SUPPORT: %d failures" % failures)
	quit(1 if failures else 0)

func capture(title: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(title + ".png"))

func removal_checks() -> void:
	var boss := fixture()
	game.turn = 3
	boss.prepare_round()
	pillar("pillar0").take_damage(99)
	check(echoes() == 2, "Destroying West does not erase Echoes already created")
	game.turn = 4
	boss.prepare_round()
	check(echoes() == 3, "Only baseline Echo continues after West is destroyed")
	boss = fixture()
	pillar("pillar0").take_damage(99)
	check(boss.stage == 2, "One surviving pillar keeps the existing boss shield")
	boss.guardian().card_data.health = 1
	game.turn = 3
	boss.prepare_round()
	check(echoes() == 1 and boss.guardian().card_data.health == 2, "Destroyed West stops only extra Echo")
	boss = fixture()
	pillar("pillar3").take_damage(99)
	boss.guardian().card_data.health = 1
	game.turn = 3
	boss.prepare_round()
	check(echoes() == 2 and boss.guardian().card_data.health == 1, "Destroyed East stops only healing")
	for id in ["pillar0", "pillar3"]:
		boss = fixture()
		remove_pillar(pillar(id))
		boss.guardian().card_data.health = 1
		game.turn = 3
		boss.prepare_round()
		check(echoes() == (1 if id == "pillar0" else 2), "West support requires a deployed pillar")
		check(boss.guardian().card_data.health == (2 if id == "pillar0" else 1),
			"East support requires a deployed pillar")
	boss = fixture()
	boss.guardian().take_damage(99)
	game.turn = 3
	boss.prepare_round()
	check(boss.guardian() == null and echoes() == 2, "East never revives a destroyed Guardian")
	boss = fixture()
	pillar("pillar0").take_damage(99)
	pillar("pillar3").take_damage(99)
	check(boss.stage == 3 and boss.accept_damage(3) == 3, "Last pillar still ends shielding")
	boss.guardian().card_data.health = 1
	game.turn = 3
	boss.prepare_round()
	check(echoes() == 0 and boss.guardian().card_data.health == 1, "Phase three receives no pillar support")

func overflow_checks() -> void:
	var boss := fixture()
	fill_hand()
	game.turn = 3
	boss.prepare_round()
	check(game.player_hp == 18 and game.get_hand_cards().size() == game.HAND_SIZE_MAX,
		"Full hand takes baseline 1 HP plus West 1 HP, with no extra cards")
	boss.prepare_round()
	check(game.player_hp == 18, "Repeated preparation cannot repeat overflow damage")
	boss = fixture()
	fill_hand(1)
	game.turn = 3
	boss.prepare_round()
	check(echoes() == 1 and game.player_hp == 19, "One free slot receives baseline Echo then West overflow")
	boss = fixture()
	game.turn = 3
	boss.prepare_round()
	boss.resolve_intent()
	check(game.player_hp == 18 and echoes() == 0, "Both unresolved Echoes cause actual curse damage")
	boss.resolve_intent()
	check(game.player_hp == 18, "Repeated resolution cannot repeat curse damage")
