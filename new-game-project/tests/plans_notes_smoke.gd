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
	game.player_run_buffs.clear()
	game.enemy_run_buffs.clear()
	game.plans.auto_save = true
	game.turn = 1
	game.player_hp = 20
	game.enemy_hp = 20
	game.energy_cap = 3
	game.preparedness = 6
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game._set_phase(game.Phase.PLAYER_PLAY)

func card(name: String, element: String = "evac", lane: int = 0) -> Node:
	var result = game.Card3DScene.instantiate()
	game.add_child(result)
	result.add_to_group("cards")
	result.setup({"name":name, "type":"response", "element":element, "cost":1, "attack":2, "health":10})
	result.in_hand = false
	result.current_slot = game._response_slots()[lane]
	return result

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts")
	root.get_texture().get_image().save_png("res://tests/artifacts/" + name + ".png")

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	await process_frame
	director = game.run_director
	director.new_run()
	fixture()
	check(game.plans.bank_unused_energy() and game.preparedness == 4 and game.plans.tokens == 1, "two energy become one Plan")
	check(not game.plans.bank_unused_energy(), "only one token saved per round")
	game.turn = 2
	check(game.plans.bank_unused_energy() and game.plans.tokens == 2, "tokens can be held for a later turn")
	game.turn = 3
	check(not game.plans.bank_unused_energy(), "token cap prevents spending energy without receiving a token")
	var ally = card("Protected")
	director.show_plans()
	await capture("plans_menu")
	director.select_brace()
	director.arm_brace(ally)
	check(game.plans.tokens == 1 and not paused and game.plans.committed_round == 3, "actual Brace selection spends one token and resumes")
	check(not game.plans.arm("brace", [ally]), "one contingency per round")
	game.plans.apply_combat()
	ally.take_damage(4)
	check(ally.card_data.health == 8 and ally.planned_guard == 0, "Brace prevents two damage on the next attack")
	ally.take_damage(2)
	check(ally.card_data.health == 6, "Brace cannot protect every hit")
	game.plans.finish_combat()
	fixture()
	var first = card("First", "evac", 0)
	var second = card("Second", "evac", 1)
	game.plans.tokens = 1
	director.show_plans()
	director.select_coordination()
	game.board_input.click_card(first)
	check(game.plans.tokens == 0 and not paused, "actual coordination choice works")
	game.plans.apply_combat()
	check(first.effective_attack() == 3 and second.effective_attack() == 3, "both matching allies gain one temporary attack")
	game.plans.finish_combat()
	check(first.effective_attack() == 2 and second.effective_attack() == 2, "coordinated boost expires after combat")
	game.turn = 2
	game.plans.tokens = 1
	second.card_data.element = "brace"
	check(not game.plans.arm("coordinate", [first, first]) and game.plans.tokens == 1, "duplicate target spends nothing")
	fixture()
	ally = card("Overclocked")
	game.add_global_buff(true, "overclock")
	check(game.energy_cap == 5 and game.resource_growth(true) == 2 and game.buff_value(true, "draw") == 0, "Overclock grows two capacity each round and has no draw penalty")
	ally.take_damage(2)
	check(ally.card_data.health == 7, "Overclock causes 1.5x unit damage")
	ally.take_damage(1, 1.0, true)
	check(ally.card_data.health == 5, "damage penalty rounds up and includes periodic damage")
	game._damage_side(true, 2)
	check(game.player_hp == 17, "Overclock also increases hero damage")
	game._damage_side(true, 1, true)
	check(game.player_hp == 16, "fixed HP payments stay fixed")
	fixture()
	ally = card("Sealed card")
	ally.card_data.locked_until = 2
	for i in range(30): ally._refresh_face()
	check(ally._status_row.find_children("Sealed", "TextureRect", false, false).size() == 1, "sealed icon is rebuilt without accumulating")
	game.turn = 2
	ally._refresh_face()
	check(not ally._status_row.has_node("Sealed"), "sealed icon disappears on expiry")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	ally._input_event(game.camera, click, Vector3.ZERO, Vector3.ZERO, 0)
	await create_timer(0.4).timeout
	check(paused and director.screen == "inspect", "board hold opens paused inspection")
	await capture("board_inspection")
	director.show_deck()
	director.close_modal()
	check(director.screen == "inspect" and paused, "deck viewer preserves pending inspection")
	director.close_modal()
	check(not paused, "inspection closes back to battle")
	ally.take_damage(2)
	ally.add_status("burn", 2)
	ally.heal(1)
	check(game.battle_log.any(func(line): return line.contains("takes 2 damage")) and game.battle_log.any(func(line): return line.contains("Burn")), "damage and statuses appear in log")
	check(not director.root.has_node("CombatLogButton"), "combat log control is removed")
	for i in range(350): game.log_event("Event %d" % i)
	check(game.battle_log.size() == 300, "backlog has bounded memory")
	fixture()
	ally = card("Rescued", "evac", 0)
	ally.card_data.health = 5
	var route_data: Dictionary = director.character_deck(0).filter(func(item): return item.id == "evacuation")[0]
	check(route_data.health == 5 and route_data.effect == "move_ally" and route_data.move_heal == 2, "Evacuation Route has stronger health and a unique rescue")
	var route = card("Route", "evac", 1)
	route.card_data = route_data.duplicate(true)
	game.begin_move_effect(route)
	game.select_moving_ally(ally)
	game.complete_move_effect(game._response_slots()[3])
	check(ally.current_slot == game._response_slots()[3] and ally.card_data.health == 7, "route relocation also heals its ally")
	fixture()
	game.encounter_kind = "battle"
	game.player_first = true
	game.preparedness = 2
	var deployed = card("Turn flow", "evac", 0)
	var enemy = game.Card3DScene.instantiate()
	game.add_child(enemy)
	enemy.add_to_group("cards")
	enemy.setup({"name":"Holdout", "type":"disaster", "element":"flood", "cost":0, "attack":0, "health":30})
	enemy.in_hand = false
	enemy.current_slot = game._threat_slots()[3]
	await game._on_end_turn_pressed()
	for i in range(100):
		if game.phase in [game.Phase.PLAYER_DRAW, game.Phase.PLAYER_PLAY, game.Phase.GAME_OVER]: break
		await create_timer(0.1).timeout
	check(game.turn == 2 and game.plans.tokens == 1 and game.energy_cap == 4, "actual End Turn saves a Plan and advances to the next turn")
	fixture()
	director.battle_active = false
	director.new_run()
	director.collection[0] = director.upgraded_definition(director.collection[0])
	director.current = 3
	director.coins = 60
	director.show_shop()
	var stock: Array = director.shop_stock.duplicate(true)
	director.show_remove_cards("shop")
	director.preview_remove(1)
	await capture("remove_card")
	director.confirm_remove()
	check(director.collection.size() == 11 and director.collection[0].name.ends_with("+") and director.coins == 30, "shop removal keeps other duplicate and charges once")
	check(director.screen == "shop" and director.shop_stock == stock and 3 not in director.cleared, "shop removal preserves stock and allows more purchases")
	director.confirm_remove()
	check(director.coins == 30 and director.collection.size() == 11, "duplicate confirmation cannot remove another card")
	director.current = 4
	director.show_rest()
	director.show_remove_cards("rest")
	director.preview_remove(0)
	director.confirm_remove()
	check(director.collection.size() == 10 and director.coins == 30 and 4 in director.cleared, "free rest removal consumes the node")
	director.collection.resize(5)
	director.show_shop()
	director.show_remove_cards("shop")
	director.preview_remove(0)
	director.confirm_remove()
	check(director.collection.size() == 5 and director.coins == 30, "minimum deck size is protected")
	director.screen = ""
	director.confirm_title()
	for child in director.content.get_children():
		if child is Button and child.text == "Return to starting screen": child.pressed.emit()
	await process_frame
	await process_frame
	game = current_scene
	director = game.run_director
	check(director.screen == "title" and not director.battle_active and director.collection.is_empty(), "starting-screen button reloads the title without creating a run")
	if failures > 0:
		quit(1)
		return
	print("PASS: playable Plans/Brace/coordination/caps/expiry, Overclock growth/damage, sealed icon/expiry, board inspection, combat log bounds, rescue movement/heal, exact-copy shop/rest removal, actual return to title")
	quit(0)
