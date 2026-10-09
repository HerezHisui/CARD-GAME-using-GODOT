extends SceneTree
var game: Node
var director: Node

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error("FAILED: " + message)
		quit(1)
		assert(condition, message)

func make_card(data: Dictionary, slot: Node3D = null) -> Node:
	var card = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup(data)
	if slot:
		card.current_slot = slot
		card.in_hand = false
	else:
		card.reparent(game.hand_parent())
		game.hand.append(card)
	return card

func definition(id: String) -> Dictionary:
	for card in director.catalog:
		if card.id == id: return card
	assert(false, "missing card " + id)
	return {}

func battle_fixture() -> void:
	paused = false
	game.clear_battle()
	game.player_run_buffs.clear()
	game.enemy_run_buffs.clear()
	game.player_hp = 20
	game.enemy_hp = 20
	game.turn = 1
	game.player_first = true
	game.player_buffs.clear()
	game.enemy_buffs.clear()
	game.energy_cap = 10
	game.preparedness = 10
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game._set_phase(game.Phase.PLAYER_PLAY)

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	director = game.run_director
	check(director.screen == "title", "boots to title")
	await capture("title")
	director.new_run()
	check(director.screen == "map" and director.collection.size() == 12, "title starts a fresh run")
	director.toggle_map()
	check(not director.modal.visible and director.screen == "", "M can close map between encounters")
	director.toggle_map()
	check(director.modal.visible and director.screen == "map", "M reopens map between encounters")
	battle_fixture()
	var attacker = make_card({"name":"Heavy", "type":"response", "element":"brace", "cost":1, "attack":8, "health":20}, game._response_slots()[0])
	var defender = make_card({"name":"Blocker", "type":"disaster", "element":"earthquake", "cost":0, "attack":1, "health":1}, game._threat_slots()[0])
	game.resolve_attack(attacker, defender, true)
	check(game.enemy_hp == 20 and not defender.is_alive(), "overkill never damages hero")
	attacker.add_modifier("piercing")
	defender = make_card({"name":"Wall", "type":"disaster", "element":"earthquake", "cost":0, "attack":1, "health":40}, game._threat_slots()[0])
	game.resolve_attack(attacker, defender, true)
	check(game.enemy_hp == 12 and defender.card_data.health == 32, "piercing hits both blocker and hero")
	game.enemy_hp = 20
	game.resolve_attack(attacker, null, true)
	check(game.enemy_hp == 12, "piercing does not hit open lanes twice")
	attacker.add_modifier("sluggish")
	check(not attacker.can_attack(2) and attacker.can_attack(3), "sluggish skips the following round")
	var health_before: int = attacker.card_data.health
	attacker.add_status("burn", 6)
	attacker.add_status("poison", 3)
	attacker.add_modifier("armored")
	attacker.status_upkeep()
	check(attacker.card_data.health == health_before - 9, "status damage bypasses armor")
	check(attacker.statuses.burn == 3 and attacker.statuses.poison == 2, "burn halves and poison decays")
	attacker.add_status("bleed", 2)
	health_before = attacker.card_data.health
	attacker.after_attack(3)
	check(attacker.card_data.health == health_before - 2 and attacker.statuses.bleed == 1, "bleed triggers after attacking")
	attacker.add_status("strength", 2)
	check(attacker.effective_attack() == 10, "strength increases attack")
	attacker.cleanse()
	check(not attacker.statuses.has("burn") and not attacker.statuses.has("poison") and not attacker.statuses.has("bleed") and attacker.statuses.strength == 2, "cleanse removes harmful statuses only")
	battle_fixture()
	attacker = make_card({"name":"Needle gale", "type":"disaster", "element":"typhoon", "cost":1, "attack":3, "health":20, "modifier":"piercing"}, game._threat_slots()[0])
	defender = make_card({"name":"Wall", "type":"response", "element":"evac", "cost":1, "attack":1, "health":20}, game._response_slots()[0])
	game.resolve_attack(attacker, defender, false)
	check(game.player_hp == 17 and defender.card_data.health == 17, "Disaster piercing is symmetric")
	game.tension = 10
	game.add_global_buff(false, "energy")
	check(game.enemy_action_limit() == 4, "Disaster resource buff grants another action")
	game.add_global_buff(false, "energy")
	game.add_global_buff(false, "energy")
	check(game.enemy_action_limit() == 5, "Disaster action bonus has a limit")
	battle_fixture()
	attacker = make_card(definition("steam_team"), game._response_slots()[0])
	defender = make_card({"name":"Wall", "type":"disaster", "element":"earthquake", "cost":0, "attack":1, "health":40}, game._threat_slots()[0])
	game.add_global_buff(true, "burn")
	game.resolve_attack(attacker, defender, true)
	check(defender.statuses.burn == 5, "global burn buff increases applied stacks")
	game.add_global_buff(true, "strength")
	check(attacker.effective_attack() == 3, "global strength affects existing units")
	game.add_global_buff(true, "health")
	check(attacker.max_health == 5, "global health affects existing units")
	var future = make_card(definition("steam_team"), game._response_slots()[1])
	check(future.max_health == 5 and future.effective_attack() == 3, "global buffs affect future units")
	var tutor = make_card(definition("tutor"))
	game.deck.append(definition("needle_team").duplicate(true))
	game.deck.append(definition("heavy_loader").duplicate(true))
	var original_energy: int = game.preparedness
	check(game.try_utility(tutor, game._response_slots()[3]), "tutor opens selection")
	check(paused and director.screen == "choice", "selection pauses")
	game.cancel_utility_choice()
	check(game.preparedness == original_energy and is_instance_valid(tutor) and tutor.in_hand, "cancel spends nothing")
	game.try_utility(tutor, game._response_slots()[3])
	game.complete_utility_choice(game.deck[0])
	check(game.deck.size() == 1 and game.preparedness == original_energy - 1, "tutor takes selected card and pays")
	var seal = make_card(definition("seal"))
	game.enemy_deck.append({"name":"Test hazard", "type":"disaster", "element":"fire", "cost":0, "attack":1, "health":3})
	game.try_utility(seal, game._response_slots()[3])
	game.complete_utility_choice(game.enemy_deck[0])
	game.enemy_draw_cards(1)
	check(game.enemy_hand.is_empty() and game.enemy_deck.size() == 1, "sealed deck card cannot be drawn")
	game.turn = 3
	game.enemy_draw_cards(1)
	check(game.enemy_hand.size() == 1, "seal expires after two rounds")
	var sealed_ally = make_card(definition("runner"))
	sealed_ally.card_data.locked_until = game.turn + 2
	check(not game.try_play_card(sealed_ally), "sealed Response cannot be played")
	var tax = make_card(definition("tax"))
	game.try_utility(tax, game._response_slots()[3])
	game.complete_utility_choice(game.enemy_hand[0])
	check(game.enemy_hand[0].tension_cost == 2 and game.enemy_hand[0].cost == 0, "tax raises base tension without changing deck category")
	var evo := {"type":"disaster", "cost":1}
	game.increase_cost(evo)
	check(evo.cost == 2, "tax raises evolution sacrifice requirement")
	var before_cards: int = game.get_hand_cards().size()
	game.deck.append(definition("needle_team").duplicate(true))
	var runner = make_card(definition("runner"), game._response_slots()[2])
	game.on_card_played(runner)
	check(game.get_hand_cards().size() == before_cards + 1, "unit on-play draws a card")
	var taxed_player = make_card(definition("runner"))
	game.enemy_utility({"effect":"tax"})
	check(game.get_hand_cards().any(func(c): return int(c.card_data.cost) > int(definition(c.card_data.id).cost)), "enemy tax affects Response hand")
	var scout = make_card(definition("scout"))
	game.try_utility(scout, game._response_slots()[3])
	check(director.screen == "intel" and director.intel_revealed, "scout reveals hand")
	director.close_modal()
	var key := InputEventKey.new()
	key.keycode = KEY_M
	key.pressed = true
	director._input(key)
	check(director.screen == "map" and paused, "M opens map")
	director._input(key)
	check(director.screen == "" and not paused, "M closes map")
	game.turn = 5
	game._begin_round()
	check(director.screen == "buff" and director.buff_choices.size() == 3, "fifth round offers three buffs")
	check(not game.enemy_buffs.is_empty(), "Disaster receives a buff too")
	await capture("adaptation")
	director.show_deck()
	director.close_modal()
	check(director.screen == "buff", "deck viewing preserves pending buff choices")
	director.select_buff(director.buff_choices[0].id)
	check(not paused and not director.modal.visible and game.adapted_round == 5, "choosing resumes the round")
	await create_timer(8).timeout
	game.player_hp = 0
	game._check_game_over()
	check(director.screen == "result", "defeat opens result")
	# Emit the real defeat-screen button instead of calling reset helpers.
	director.content.get_child(director.content.get_child_count() - 1).pressed.emit()
	await process_frame
	await process_frame
	game = current_scene
	director = game.run_director
	check(director.screen == "map" and director.modal.visible and game.player_hp == 20 and director.collection.size() == 12 and director.current == -1, "real New Run button reloads cleanly after defeat")
	check(game.player_buffs.is_empty() and game.enemy_buffs.is_empty() and game.energy_cap == 3, "restart clears buffs and resources")
	print("PASS: title, no overkill, piercing, sluggish, statuses, global buffs, tutors, cancellation, sealing/expiry, taxes, scouting, M toggle, adaptation, actual defeat-button restart")
	quit(0)

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts")
	root.get_texture().get_image().save_png("res://tests/artifacts/" + name + ".png")
