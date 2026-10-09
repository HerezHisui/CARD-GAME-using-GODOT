extends SceneTree
var game: Node
var director: Node

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error("FAILED: " + message)
		quit(1)
		assert(condition, message)

func make_card(data: Dictionary, slot: Node3D) -> Node:
	var card = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup(data)
	card.current_slot = slot
	card.in_hand = false
	return card

func fixture() -> void:
	paused = false
	game.clear_battle()
	game.player_run_buffs.clear()
	game.enemy_run_buffs.clear()
	game.player_hp = 20
	game.enemy_hp = 20
	game.preparedness = 10
	game.turn = 1
	game.player_first = false
	director.battle_active = true
	director.modal.hide()
	director.screen = ""
	game._set_phase(game.Phase.PLAYER_PLAY)

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	director = game.run_director
	director.new_run()
	var original_order: Array = director.collection.duplicate(true)
	var indices: Array = director.sorted_indices(director.collection, 2, false)
	for i in range(1, indices.size()): check(director.collection[indices[i - 1]].cost <= director.collection[indices[i]].cost, "cost sorting")
	var reversed: Array = director.sorted_indices(director.collection, 3, true)
	for i in range(1, reversed.size()): check(director.collection[reversed[i - 1]].attack >= director.collection[reversed[i]].attack, "descending attack sorting")
	check(director.collection == original_order, "sorting never reorders collection")
	director.show_deck()
	director.change_sort(2, false)
	director.reverse_sort(false)
	await capture("sorted_deck")
	director.current = 3
	director.show_upgrade()
	director.change_sort(4, true)
	director.show_upgrade_preview(1)
	check(director.collection[1] == original_order[1], "preview does not mutate original")
	check(director.upgraded_definition(director.collection[1]).on_play_draw == 1, "preview computes upgrade")
	await capture("upgrade_preview")
	director.upgrade(1)
	check(director.collection[0] == original_order[0] and director.collection[1].name.ends_with("+"), "only chosen duplicate upgraded")
	var spell := {"name":"Spell", "utility":true, "cost":0}
	check(director.can_upgrade(spell), "zero cost spell can gain an ability upgrade")
	director.current = 6
	director.coins = 200
	game.player_hp = 5
	director.show_shop()
	var stock: Array = director.shop_stock.duplicate(true)
	var count: int = director.collection.size()
	var prices: int = director.shop_price(director.shop_stock[0]) + director.shop_price(director.shop_stock[1])
	director.buy(director.shop_stock[0])
	director.buy(director.shop_stock[1])
	director.buy(director.shop_stock[0])
	check(director.collection.size() == count + 2 and director.coins == 200 - prices, "multiple purchases, no buying sold item again")
	check(director.shop_stock == stock and director.screen == "shop" and 6 not in director.cleared, "stock fixed and room stays open")
	director.buy_heal()
	director.buy_heal()
	check(game.player_hp == 15 and director.coins == 170 - prices, "repeatable healing")
	await capture("shop_stock")
	director.finish_room()
	check(6 in director.cleared, "only leaving completes shop")
	fixture()
	var ally = make_card({"name":"Ally", "type":"response", "element":"evac", "cost":1, "attack":2, "health":4}, game._response_slots()[0])
	var marshal = make_card({"name":"Marshal", "type":"response", "element":"evac", "cost":2, "attack":1, "health":3, "effect":"move_ally"}, game._response_slots()[1])
	game.on_card_played(marshal)
	check(director.screen == "choice" and paused, "summon opens optional move choice")
	game.select_moving_ally(ally)
	game.complete_move_effect(game._response_slots()[3])
	check(ally.current_slot == game._response_slots()[3] and marshal.current_slot == game._response_slots()[1] and not paused, "another card moves, source stays")
	game.add_global_buff(true, "glass")
	check(ally.effective_attack() == 4 and ally.max_health == 3, "strong battle buff has health downside")
	game.add_global_buff(true, "blood_pact")
	check(ally.statuses.bleed == 2, "blood pact applies its downside")
	game.add_global_buff(true, "beacon", true)
	director.battle_finished(true)
	check(game.player_buffs.is_empty() and game.enemy_buffs.is_empty() and game.player_run_buffs.beacon == 1, "battle buffs expire, permanent buff remains")
	fixture()
	game.encounter_kind = "boss"
	game.player_first = false
	var opposite = make_card({"name":"Evac", "type":"response", "element":"evac", "cost":1, "attack":2, "health":5}, game._response_slots()[0])
	var quake := {"name":"Quake", "type":"disaster", "element":"earthquake", "cost":0, "attack":2, "health":3}
	var flood := {"name":"Flood", "type":"disaster", "element":"flood", "cost":0, "attack":2, "health":3}
	check(game.choose_base_threat([quake, flood], [game._threat_slots()[0]]) == flood, "boss picks a counter over a weak matchup")
	var weak = make_card({"name":"Weak", "type":"disaster", "element":"flood", "cost":0, "attack":1, "health":1}, game._threat_slots()[0])
	var strong = make_card({"name":"Strong", "type":"disaster", "element":"flood", "cost":0, "attack":5, "health":8}, game._threat_slots()[1])
	var evolution := {"name":"Upgrade", "type":"disaster", "element":"flood", "cost":1, "attack":4, "health":6}
	var plan: Dictionary = game.best_evolution_plan([weak, strong], [evolution])
	check(not plan.is_empty() and weak in plan.sacrifices and strong not in plan.sacrifices, "boss preserves healthy valuable blockers")
	evolution.cost = 3
	check(game.best_evolution_plan([weak, strong], [evolution]).is_empty(), "cannot evolve without full sacrifice cost")
	var definitions: Array[Dictionary] = []
	game.load_deck_from_json("res://data/disaster_deck.json", definitions)
	check(definitions.filter(func(c): return c.id == "inferno")[0].cost == 3, "strong disasters have raised sacrifices")
	director.encounter = "boss"
	director.battle_active = true
	game._set_phase(game.Phase.GAME_OVER)
	director.battle_finished(true)
	check(director.screen == "floor_buff" and game.phase == game.Phase.GAME_OVER, "boss reward preserves combat termination")
	await capture("floor_reward")
	director.select_floor_buff(director.buff_choices[0].id)
	check(director.floor_number == 2 and not game.player_run_buffs.is_empty() and not game.enemy_run_buffs.is_empty(), "floor awards persistent buff to both sides")
	game.player_buffs.strength = 4
	var persistent: Dictionary = game.player_run_buffs.duplicate()
	director.battle_active = true
	game.start_encounter(director.collection, "elite", 2, 0)
	check(game.player_buffs.is_empty() and game.player_run_buffs == persistent, "new battle keeps only permanent buffs")
	game._set_phase(game.Phase.PLAYER_PLAY)
	director.screen = ""
	director.show_menu()
	check(director.content.get_children().any(func(c): return c is Button and c.text == "Quit game"), "battle menu has quit")
	print("PASS: stable sorting, exact duplicate upgrade/preview, multi-buy shop/stock/healing, summon movement, tradeoffs, battle expiry, permanent floors, tactical AI/sacrifices, menu quit")
	for child in director.content.get_children():
		if child is Button and child.text == "Quit game": child.pressed.emit()

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts")
	root.get_texture().get_image().save_png("res://tests/artifacts/" + name + ".png")
