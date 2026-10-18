extends SceneTree

var game: Node
var director: Node
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failures += 1
	push_error("FAILED: " + message)

func fixture() -> void:
	paused = false
	game.clear_battle()
	game.player_run_buffs.clear()
	game.enemy_run_buffs.clear()
	director.modal.hide()
	director.screen = ""
	director.battle_active = true
	game.turn = 1
	game.player_hp = 20
	game.enemy_hp = 40
	game.player_first = true
	game.preparedness = 5
	game.energy_cap = 5
	game._set_phase(game.Phase.PLAYER_PLAY)

func unit(side: String = "response", lane: int = -1, data: Dictionary = {}) -> Node:
	var definition := {"id":"fixture", "name":"Fixture", "type":side, "element":"brace",
		"cost":1, "attack":2, "health":8}
	definition.merge(data, true)
	var card: Node = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup(definition)
	if lane >= 0:
		card.place_on_slot((game._response_slots() if side == "response" else game._threat_slots())[lane])
	else:
		card.reparent(game.hand_parent())
		game.hand.append(card)
	return card

func placement() -> void:
	fixture()
	for view in [game.DESK_VIEW, game.BOARD_VIEW]:
		game._apply_view(view)
		for slot in game._response_slots():
			var point: Vector2 = game.camera.unproject_position(slot.global_position)
			check(game.slot_at_screen_position(point) == slot, "visible lane center selects the same lane")
	check(game.slot_at_screen_position(Vector2(-1000, -1000)) == null, "outside board rejects placement")

func draw_definition(id: String, cost: int) -> Dictionary:
	return {"id":id, "name":id, "type":"response", "element":"evac", "cost":cost, "attack":1, "health":5}

func turn_draw() -> void:
	fixture()
	game.preparedness = 0
	game.deck.assign([draw_definition("normal", 1)])
	game._set_phase(game.Phase.PLAYER_DRAW, "Old draw instruction")
	game._on_draw_button_pressed()
	check(not director.modal.visible and game.phase == game.Phase.PLAYER_PLAY, "draw enters play without a picker")
	check(game.preparedness == 0, "turn draw is free even with zero energy")
	check(game.deck.is_empty() and game.get_hand_cards().size() == 1, "normal turn draw takes exactly one card")
	game._on_draw_button_pressed()
	check(game.get_hand_cards().size() == 1 and game.preparedness == 0, "repeated Draw cannot draw or charge again")

func cheap_turn_draw() -> void:
	var selected: Array = []
	for seed_value in range(16):
		fixture()
		var held := unit("response", -1, {"cost":3})
		var high := draw_definition("high", 4)
		game.deck.assign([draw_definition("cheap_a", 1), draw_definition("cheap_b", 1), high])
		seed(seed_value)
		game._set_phase(game.Phase.PLAYER_DRAW)
		game._on_draw_button_pressed()
		var cards: Array = game.get_hand_cards()
		check(cards.size() == 2 and held in cards, "guarantee swaps only the new draw and preserves hand size")
		var drawn: Node = cards[1]
		check(drawn.card_data.cost == 1, "guarantee supplies a cost-1 card")
		if drawn.card_data.id not in selected: selected.append(drawn.card_data.id)
		check(game.deck.size() == 2 and high in game.deck, "the original draw returns to the pile")
		check(game.preparedness == 5 and game.player_graveyard.is_empty(), "swap spends nothing and is not destruction")
		check(game.battle_log.any(func(line): return "Turn draw: guaranteed" in line), "swap is logged")
	check(selected.size() == 2, "fixed seeds exercise both random cheap-card candidates")
	for held_cost in [0, 1]:
		fixture()
		unit("response", -1, {"cost":held_cost})
		var cheap := draw_definition("cheap", 1)
		game.deck.assign([cheap, draw_definition("high", 4)])
		game._set_phase(game.Phase.PLAYER_DRAW)
		game._on_draw_button_pressed()
		check(game.get_hand_cards()[1].card_data.id == "high" and game.deck == [cheap],
			"a held card costing at most one skips the guarantee")
		check(not game.battle_log.any(func(line): return "Turn draw: guaranteed" in line),
			"a skipped guarantee is not logged")

func unavailable_cheap_draw() -> void:
	for locked in [false, true]:
		fixture()
		var remaining := draw_definition("remaining", 1 if locked else 2)
		if locked: remaining.locked_until = game.turn + 1
		game.deck.assign([remaining, draw_definition("high", 4)])
		game._set_phase(game.Phase.PLAYER_DRAW)
		game._on_draw_button_pressed()
		check(game.get_hand_cards().size() == 1 and game.get_hand_cards()[0].card_data.id == "high",
			"no eligible cost-1 card leaves the original draw in hand")
		check(game.deck == [remaining], "the guarantee never takes a sealed card or a different cost")
	fixture()
	var sealed := draw_definition("sealed", 1)
	sealed.locked_until = game.turn + 1
	game.deck.assign([sealed])
	game._set_phase(game.Phase.PLAYER_DRAW)
	game._on_draw_button_pressed()
	check(game.get_hand_cards().is_empty() and game.deck == [sealed], "an entirely sealed pile draws nothing")
	check(game.phase == game.Phase.PLAYER_PLAY, "an unavailable draw still finishes the draw phase")

func other_draw_effects() -> void:
	fixture()
	var cheap := draw_definition("cheap", 1)
	var high := draw_definition("high", 4)
	game.deck.assign([cheap, high])
	game.draw_cards(1)
	check(game.get_hand_cards()[0].card_data.id == "high" and game.deck == [cheap],
		"normal effect draws do not use the turn-button guarantee")
	fixture()
	var tutor := unit("response", -1, {"id":"tutor", "cost":2, "utility":true, "effect":"tutor"})
	game.deck.assign([cheap, high])
	check(game.try_utility(tutor, game._response_slots()[0]), "Search and Rescue still opens its tutor picker")
	check(director.modal.visible and director.screen == "choice", "tutor selection is preserved")
	game.complete_utility_choice(high)
	check(game.get_hand_cards().size() == 1 and game.get_hand_cards()[0].card_data.id == "high",
		"tutor keeps the selected expensive card without replacing it")
	check(game.deck == [cheap] and game.preparedness == 3, "tutor still pays only its own card cost")

func turn_energy_refill() -> void:
	for player_first in [true, false]:
		fixture()
		game.player_first = player_first
		game.preparedness = 0
		game.energy_cap = 6
		game.deck.assign([draw_definition("next", 1)])
		game.enemy_hand.assign([{"id":"idle", "name":"Idle", "type":"disaster", "element":"fire",
			"cost":0, "tension_cost":99, "attack":0, "health":20}])
		await game.continue_round()
		check(game.phase == game.Phase.PLAYER_DRAW and game.preparedness == game.energy_cap,
			"energy is full at player-turn start in either turn order")

func plan_display() -> void:
	fixture()
	var ally := unit("response", 0)
	game.plans.tokens = 1
	director.begin_tactic("coordinate")
	ally._on_mouse_entered()
	check(ally.plan_attack_bonus == 0 and ally.card_data.health == 8, "target hover has no gameplay effect")
	game.board_input.click_card(ally)
	check(ally.plan_attack_bonus == 0, "arming does not apply a combat bonus early")
	game._set_phase(game.Phase.COMBAT)
	game.plans.apply_combat()
	check(ally._atk_label.text == "3", "plan attack displays synchronously")
	check(ally.art_sprite.modulate == Color.WHITE, "positive plan does not flash damage red")
	game.plans.finish_combat()
	check(ally._atk_label.text == "2", "expired plan displays synchronously")

func board_inspection() -> void:
	fixture()
	game._apply_view(game.BOARD_VIEW)
	game._set_phase(game.Phase.COMBAT)
	if game.camera_tween: game.camera_tween.kill()
	game._apply_view(game.BOARD_VIEW)
	var ally := unit("response", 0)
	await create_timer(0.5).timeout
	var point: Vector2 = game.camera.unproject_position(ally.global_position)
	check(game.card_at_board_position(point) == ally, "overhead picker finds a board card during combat")
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await process_frame
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = point
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await create_timer(0.4).timeout
	check(director.screen == "inspect", "overhead board hold opens inspection during combat")
	press = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = point
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	director.close_modal()

func run() -> void:
	root.size = Vector2i(1440, 900)
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	placement()
	turn_draw()
	cheap_turn_draw()
	unavailable_cheap_draw()
	other_draw_effects()
	await turn_energy_refill()
	plan_display()
	await board_inspection()
	game.clear_battle()
	print("OCT18 CARD LOGIC: %d failures" % failures)
	quit(1 if failures else 0)
