extends SceneTree
var game: Node
var director: Node
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAILED: " + message)

func fixture() -> void:
	paused = false
	game.clear_battle()
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game.player_run_buffs = {"cadet":1}
	game.turn = 1
	game.energy_cap = 10
	game.preparedness = 10
	game._set_phase(game.Phase.PLAYER_PLAY)

func unit(id: String, lane: int = -1, side: String = "response") -> Node:
	var card = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup({"id":id, "name":id.capitalize(), "type":side, "element":"evac" if side == "response" else "fire", "cost":1, "attack":2, "health":4})
	if lane < 0:
		card.reparent(game.hand_parent())
		game.hand.append(card)
		game.arrange_hand_centered()
	else: card.place_on_slot((game._response_slots() if side == "response" else game._threat_slots())[lane])
	return card

func spell() -> Node:
	var card = unit("recovery")
	card.setup(director.catalog_card("recovery_detail"))
	return card

func press_face(face: Control) -> void:
	await process_frame
	await process_frame
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = face.get_global_rect().get_center()
	event.global_position = event.position
	root.push_input(event)
	var release := event.duplicate()
	release.pressed = false
	root.push_input(release)
	await process_frame

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/artifacts/oct16_" + name + ".png")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		root.size = Vector2i(1440, 900)
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	director.persistence.discard()
	director.new_run()
	game.set_process(false)
	fixture()
	var left = unit("left", 0)
	var center = unit("center", 1)
	var right = unit("right", 3)
	game.plans.tokens = 1
	director.begin_tactic("coordinate")
	game.board_input.click_card(center)
	check(game.plans.tokens == 0 and game.plans.armed.targets == [center], "one board click arms one center without spending twice")
	game.plans.apply_combat()
	check([left, center, right].all(func(card): return card.plan_attack_bonus == 1), "chosen card and nearest allies across gaps gain the combat bonus")
	game.plans.finish_combat()
	check([left, center, right].all(func(card): return card.plan_attack_bonus == 0), "coordination expires after combat")
	var nearer = unit("nearer", 2)
	check(game.plans.coordination_targets(center) == [center, left, nearer], "coordination cannot skip the nearest ally")
	fixture()
	var original = unit("fallen", 0)
	game.increase_cost(original.card_data)
	original.add_status("poison", 3)
	original.take_damage(999, 1.0, true)
	var entry: Dictionary = game.player_graveyard[0]
	check(game.recoverable_units().size() == 1 and entry.recovery.health == 4, "graveyard records a clean pre-buff definition")
	var recovery = spell()
	var energy: int = game.preparedness
	check(game.try_utility(recovery, game._response_slots()[1]), "Recovery Detail offers destroyed units")
	game.cancel_utility_choice()
	check(game.preparedness == energy and game.player_graveyard.size() == 1 and recovery.in_hand, "cancel keeps the graveyard entry, energy and spell")
	check(game.try_utility(recovery, game._response_slots()[1]), "recovery can be selected again")
	game.complete_utility_choice(entry)
	var recovered = game.get_hand_cards().filter(func(card): return card.card_data.id == "fallen")[0]
	check(recovered.max_health == 5 and recovered.card_data.cost == 1 and not recovered.statuses.has("poison"), "recovery resets statuses/taxes without applying Steve health twice")
	check(game.preparedness == energy - 2 and game.player_graveyard.size() == 1 and game.player_graveyard[0].graveyard_reason == "Cast", "one entry is consumed and the recovery spell is recorded exactly once")
	game.complete_utility_choice(entry)
	check(game.get_hand_cards().size() == 1, "stale recovery callback cannot duplicate cards")
	recovered.place_on_slot(game._response_slots()[0])
	game.on_card_played(recovered)
	recovered.take_damage(999, 1.0, true)
	check(game.recoverable_units().is_empty(), "the same unit cannot be recovered a second time")
	recovery = spell()
	energy = game.preparedness
	check(not game.try_utility(recovery, game._response_slots()[1]) and game.preparedness == energy, "no eligible graveyard target spends nothing")
	unit("second", 1).take_damage(999, 1.0, true)
	var relief = unit("relief", 2)
	relief.setup(director.catalog_card("relief_crew"))
	game.on_card_played(relief)
	check(relief.statuses.get("barrier", 0) == 2, "Relief Crew gains capped protection from destroyed allies")
	check(director.persistence.checkpoint() and director.persistence.resume(), "graveyard and clean card definitions survive Continue")
	check(game.recoverable_units().size() == 1 and game.graveyard_serial == 4, "Continue preserves recovery limits and entry identity")
	director.show_graveyard()
	await create_timer(0.3).timeout
	check(director.screen == "graveyard" and paused and director.modal.size.x <= 700 and director.modal.size.y <= 500, "graveyards use a compact paused panel")
	check(director.content.find_children("*", "GridContainer", true, false).is_empty(), "graveyard entries do not use the deck grid")
	await capture("graveyard")
	director.close_modal()
	await process_frame
	await process_frame
	check(not paused and director.graveyard_button.visible, "closing the graveyard restores the battle button")
	fixture()
	unit("full_hand_target", 0).take_damage(999, 1.0, true)
	recovery = spell()
	for i in 7: unit("held_%d" % i)
	entry = game.player_graveyard[0]
	check(game.get_hand_cards().size() == 8 and game.try_utility(recovery, game._response_slots()[0]), "recovery can use the slot freed by its own spell in a full hand")
	game.complete_utility_choice(entry)
	check(game.get_hand_cards().size() == 8 and game.get_hand_cards().any(func(card): return card.card_data.id == "full_hand_target"), "full-hand recovery never overfills or loses the returned card")
	fixture()
	for i in 8: unit("hand_%d" % i)
	for i in 4:
		unit("ally_%d" % i, i)
		unit("enemy_%d" % i, i, "disaster")
	game.set_view(game.View.DESK)
	game.presentation.clear_banner()
	await create_timer(1.5).timeout
	await capture("board_hand")
	var hand_top := INF
	for card in game.get_hand_cards():
		for point in game.hand_card_polygon(card, true): hand_top = minf(hand_top, point.y)
	var nearest_slot: Vector2 = game.camera.unproject_position(game._response_slots()[0].global_position)
	check(nearest_slot.y < hand_top, "resting hand leaves the Response lane centers clear")
	var held = game.get_hand_cards()[0]
	held._start_drag()
	held.global_position = Vector3(1000, 80, -1000)
	held._process(0.016)
	check(game.DRAG_BOUNDS.grow(0.001).has_point(Vector2(held.global_position.x, held.global_position.z)), "dragged cards stay near the board even after an out-of-range position")
	var cancel := InputEventMouseButton.new()
	cancel.button_index = MOUSE_BUTTON_RIGHT
	cancel.pressed = true
	held._input(cancel)
	check(not held.is_dragging and held.in_hand, "bounded dragging still cancels to hand")
	director.battle_active = false
	director.screen = ""
	director.show_rewards()
	await create_timer(0.3).timeout
	var collection_size: int = director.collection.size()
	var offers: Array = director.reward_stock.duplicate(true)
	check(director.reward_faces.size() == 3 and not director.content.find_children("*", "Button", true, false).any(func(button): return button.text == "Take card"), "rewards have three faces and no Take card buttons")
	await capture("rewards")
	await press_face(director.reward_faces[1])
	await create_timer(0.3).timeout
	check(director.reward_selection == 1 and director.reward_faces.size() == 1 and director.collection.size() == collection_size, "first click enlarges and describes without acquiring")
	await capture("reward_inspect")
	var outside := InputEventMouseButton.new()
	outside.button_index = MOUSE_BUTTON_LEFT
	outside.pressed = true
	outside.position = Vector2(8, 8)
	outside.global_position = outside.position
	root.push_input(outside)
	await process_frame
	check(director.reward_selection == -1 and director.reward_faces.size() == 3 and director.reward_stock == offers, "outside click returns to the same three offers")
	await press_face(director.reward_faces[1])
	check(director.persistence.checkpoint() and director.persistence.resume(), "inspected rewards checkpoint without claiming")
	check(director.reward_selection == -1 and director.reward_stock == director.persistence.normalize(offers), "Continue restores the same unclaimed offers")
	await press_face(director.reward_faces[1])
	var chosen_id: String = director.reward_stock[1].id
	await press_face(director.reward_faces[0])
	director.select_reward(1)
	check(director.collection.size() == collection_size + 1 and director.collection.back().id == chosen_id, "second click claims exactly the inspected reward once")
	for kind in ["battle", "elite"]:
		for floor_level in [1, 2, 3, 4]:
			seed(56789)
			game.start_encounter(director.collection, kind, floor_level, 0)
			var base: Array = game.enemy_deck + game.enemy_hand.filter(func(card): return int(card.cost) == 0)
			var effects: int = base.filter(game.has_special_effect).size()
			if kind == "battle" and floor_level <= 2:
				check(base.size() == 18 and effects <= (2 if floor_level == 1 else 4), "early normal reserves keep their size with fewer special cards")
			else: check(effects > 4, "higher normal floors and elites retain their special-card frequency")
	game.clear_battle()
	director.battle_active = false
	director.show_map()
	await process_frame
	check(not director.graveyard_button.visible, "graveyard shortcut stays hidden between encounters")
	director.persistence.discard()
	if failures: quit(1)
	else:
		print("PASS: compact graveyard, recovery/status reset/limits/Continue, graveyard protection, one-click coordination, camera/hand clearance, bounded dragging/cancel, inspect-confirm rewards and early-only encounter tuning")
		quit()
