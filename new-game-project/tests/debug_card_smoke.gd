extends SceneTree

var failures := 0
var game: Node
var director: Node

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAILED: " + message)

func unlock() -> void:
	director.show_debug()
	var password: LineEdit = director.content.get_node("DebugPassword")
	password.text = "*****"
	password.text_submitted.emit(password.text)

func select_card(picker: OptionButton, card_name: String) -> void:
	for i in picker.item_count:
		if picker.get_item_text(i).ends_with(card_name):
			picker.select(i)
			picker.item_selected.emit(i)
			return
	check(false, "picker contains " + card_name)

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	director.new_run()
	director.screen = ""
	director.modal.hide()
	director.battle_active = true
	game.clear_battle()
	game._set_phase(game.Phase.PLAYER_PLAY)
	game.set_process(false)
	game.add_card_to_hand({"name":"Hand fixture", "type":"response", "element":"evac",
		"cost":1, "attack":2, "health":5})
	var hand: Node = game.get_hand_cards()[0]
	var board: Node = game.Card3DScene.instantiate()
	game.add_child(board)
	board.add_to_group("cards")
	board.setup({"name":"Board fixture", "type":"disaster", "element":"fire",
		"cost":1, "attack":3, "health":6})
	board.place_on_slot(game._threat_slots()[0])
	game.add_card_to_hand({"name":"Utility fixture", "type":"response", "element":"evac",
		"cost":1, "utility":true, "effect":"draw"})
	var utility: Node = game.get_hand_cards()[1]
	var original: Dictionary = hand.base_definition.duplicate(true)
	var collection: Array = director.collection.duplicate(true)
	unlock()
	check(director.screen == "debug" and paused, "editor opens in a paused battle")
	var picker: OptionButton = director.content.find_child("DebugCard", true, false)
	var cost: SpinBox = director.content.find_child("DebugCost", true, false)
	var attack: SpinBox = director.content.find_child("DebugATK", true, false)
	var health: SpinBox = director.content.find_child("DebugHP", true, false)
	check(picker.item_count == 3, "picker includes hand, ally utilities and enemy board units")
	select_card(picker, "Hand fixture")
	cost.value = 0
	attack.value = 8
	health.value = 12
	check(hand.card_data.cost == 0 and hand.card_data.attack == 8 and hand.card_data.health == 12,
		"hand stats change immediately")
	check(hand._cost_label.text == "0" and hand._atk_label.text == "8" and hand._hp_label.text == "12",
		"live card badges refresh")
	check(hand.max_health == 12, "raising HP raises its healing ceiling")
	health.value = 3
	check(hand.max_health == 12 and hand.card_data.health == 3, "lowering current HP keeps its healing ceiling")
	health.value = 0
	check(hand.card_data.health == 1, "HP stays positive")
	cost.value = -2
	attack.value = -2
	check(hand.card_data.cost == 0 and hand.card_data.attack == 0, "cost and attack stay nonnegative")
	select_card(picker, "Board fixture")
	check(cost.value == 1 and attack.value == 3 and health.value == 6, "selection loads board stats")
	check(board.card_data.health == 6 and hand.card_data.health == 1, "selection does not write stats")
	attack.value = 9
	health.value = 10
	check(board.card_data.attack == 9 and board.card_data.health == 10, "enemy board stats update live")
	check(hand.card_data.attack == 0, "editing a board card leaves the hand card alone")
	select_card(picker, "Utility fixture")
	check(cost.editable and not attack.editable and not health.editable, "utilities only expose cost")
	cost.value = 4
	attack.value = 7
	health.value = 7
	check(utility.card_data.cost == 4 and not utility.card_data.has("attack")
		and not utility.card_data.has("health"), "utility cards stay statless")
	check(hand.base_definition == original and director.collection == collection,
		"debug edits preserve recovery definitions and the deck collection")
	var saved: Dictionary = director.persistence.read_save()
	var saved_hand: Array = saved.cards.filter(func(entry): return entry.data.name == "Hand fixture")
	var saved_board: Array = saved.cards.filter(func(entry): return entry.data.name == "Board fixture")
	check(saved_hand.size() == 1 and saved_hand[0].data.health == 1
		and saved_hand[0].runtime.max_health == 12, "checkpoint includes edited hand stats and healing ceiling")
	check(saved_board.size() == 1 and saved_board[0].data.attack == 9, "checkpoint includes board edits")
	director.close_modal()
	check(director.persistence.resume(), "edited battle restores")
	await process_frame
	var restored: Node = game.get_hand_cards().filter(func(card): return card.card_data.name == "Hand fixture")[0]
	check(restored.card_data.health == 1 and restored.max_health == 12, "restored hand retains edited HP")
	var restored_board: Node = game._get_card_in_slot(game._threat_slots()[0])
	check(restored_board.card_data.attack == 9 and restored_board.card_data.health == 10,
		"restored board retains edited stats")
	unlock()
	picker = director.content.find_child("DebugCard", true, false)
	attack = director.content.find_child("DebugATK", true, false)
	select_card(picker, "Hand fixture")
	restored.free()
	attack.value = 5
	check(restored_board.card_data.attack == 9, "stale selection cannot edit another card")
	director.close_modal()
	game.clear_battle()
	game._set_phase(game.Phase.PLAYER_PLAY)
	await process_frame
	unlock()
	picker = director.content.find_child("DebugCard", true, false)
	cost = director.content.find_child("DebugCost", true, false)
	check(picker.disabled and not cost.editable, "empty battle disables the card editor")
	director.close_modal()
	director.persistence.discard()
	print("DEBUG CARDS: %d failures" % failures)
	quit(1 if failures else 0)
