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

func make_card(definition: Dictionary, slot: Node3D = null) -> Node:
	var card = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup(definition.duplicate(true))
	if slot:
		card.current_slot = slot
		card.in_hand = false
	else:
		card.reparent(game.hand_parent())
		game.hand.append(card)
	return card

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	director = game.run_director
	director.new_run()
	director.battle_active = true
	director.modal.hide()
	game._set_phase(game.Phase.PLAYER_PLAY)
	game.preparedness = 10
	game.energy_cap = 10
	var exit_card = make_card(director.catalog[-1])
	check(not game.try_utility(exit_card, game._response_slots()[2]), "move without ally fails")
	check(game.preparedness == 10, "failed utility does not spend energy")
	var ally = make_card(director.collection[0], game._response_slots()[0])
	check(game.try_utility(exit_card, game._response_slots()[2]), "Emergency Exit succeeds")
	check(ally.current_slot == game._response_slots()[2], "ally moves to chosen slot")
	check(game.preparedness == 9, "move costs energy")
	var neighbor = make_card(director.collection[0], game._response_slots()[3])
	check(game._synergy_bonus(ally) == 1, "adjacent matching type grants attack")
	neighbor.card_data.element = "brace"
	check(game._synergy_bonus(ally) == 0, "other types do not grant synergy")
	var defender = make_card({"name":"Test", "type":"disaster", "element":"earthquake", "cost":0, "attack":2, "health":5}, game._threat_slots()[2])
	check(game._calc_damage(ally, defender).dmg == 4, "Evac deals double vs Earthquake")
	defender.card_data.element = "flood"
	check(game._calc_damage(ally, defender).dmg == 1, "Evac deals half vs Flood")
	defender.card_data.element = "fire"
	check(game._calc_damage(ally, defender).dmg == 2, "neutral damage preserved")
	game.player_first = false
	ally.add_modifier("rampaging")
	check(game._calc_damage(ally, defender).dmg == 3, "Rampaging boosts second attack")
	var supply = make_card(director.catalog[-2])
	game.deck.append(director.collection[0].duplicate(true))
	game.deck.append(director.collection[1].duplicate(true))
	var hand_before: int = game.get_hand_cards().size()
	check(game.try_utility(supply, game._response_slots()[1]), "draw utility succeeds")
	check(game.get_hand_cards().size() == hand_before + 1, "utility consumed and two drawn")
	director.show_deck()
	check(paused and not game.can_player_act(), "deck pauses and blocks playing")
	director.close_modal()
	check(not paused and game.can_player_act(), "closing resumes battle")
	director.battle_active = false
	director.current = 0
	director.show_rewards()
	var reward_content = director.content
	director.show_deck()
	check(director.saved_content == reward_content, "deck preserves pending rewards")
	director.close_modal()
	check(director.screen == "reward" and director.content == reward_content, "reward choices restored without reroll")
	director.coins = 200
	director.show_shop()
	var owned: int = director.collection.size()
	var prices: int = director.shop_price(director.shop_stock[0]) + director.shop_price(director.shop_stock[1])
	director.buy(director.shop_stock[0])
	director.buy(director.shop_stock[1])
	check(director.coins == 200 - prices and director.collection.size() == owned + 2 and director.screen == "shop", "multiple shop purchases persist without leaving")
	director.coins = 15
	game.player_hp = 10
	director.buy_heal()
	check(director.coins == 0 and game.player_hp == 15, "shop healing")
	director.encounter = "boss"
	director.battle_active = true
	director.battle_finished(true)
	check(director.screen == "floor_buff", "boss opens permanent floor reward")
	director.select_floor_buff(director.buff_choices[0].id)
	check(director.floor_number == 2 and game.player_hp == 20 and director.current == -1, "next floor heals and generates fresh map")
	print("PASS: utility failure/cost/consumption/movement/draw, synergy, damage types, Rampaging, pause/resume, reward preservation, shops, boss continuation")
	quit(0)
