# Covers: Board relocation and targeting, Plans, enemy hands, events, and title flow.
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
	game.set_process(false)
	game.player_run_buffs.clear()
	game.enemy_run_buffs.clear()
	game.plans.reset_run()
	game.turn = 1
	game.player_hp = 20
	game.enemy_hp = 20
	game.preparedness = 10
	game.energy_cap = 10
	game.player_first = false
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game._set_phase(game.Phase.PLAYER_PLAY)

func data(name: String, side: String = "response") -> Dictionary:
	return {"id":name, "name":name, "type":side, "element":"evac" if side == "response" else "earthquake", "cost":1 if side == "response" else 0, "attack":2, "health":10}

func card(definition: Dictionary, lane: int = -1) -> Node:
	var unit = game.Card3DScene.instantiate()
	game.add_child(unit)
	unit.add_to_group("cards")
	unit.setup(definition)
	if lane >= 0:
		unit.in_hand = false
		unit.current_slot = (game._response_slots() if definition.type == "response" else game._threat_slots())[lane]
		unit.global_position = unit.current_slot.global_position + Vector3(0, 0.02, 0)
		unit._set_overlay(false)
	else:
		unit.reparent(game.hand_parent())
		game.hand.append(unit)
		game.arrange_hand_centered()
	return unit

func click(unit: Node) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	unit._input_event(game.camera, event, Vector3.ZERO, Vector3.UP, 0)

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts")
	root.get_texture().get_image().save_png("res://tests/artifacts/" + name + ".png")

func event_fixture(kind: String) -> void:
	fixture()
	director.battle_active = false
	director.new_run()
	director.current = 3
	director.rooms[3].kind = "event"
	director.rooms[3].event = kind
	director.event_key = ""
	director.show_event()

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	await process_frame
	director = game.run_director
	director.new_run()
	fixture()
	var ally = card(data("Ally"), 0)
	var source_data := data("Evac Route")
	source_data.effect = "move_ally"
	source_data.move_heal = 2
	var source = card(source_data, 1)
	ally.card_data.health = 5
	game.begin_move_effect(source)
	check(not paused and not game.board_input.action.is_empty(), "relocation uses board without pausing for a menu")
	click(ally)
	check(ally.is_dragging and ally.is_relocating and not ally.in_hand, "clicking ally begins actual board drag")
	ally.set_process(false)
	await physics_frame
	ally.global_position = game._response_slots()[3].global_position + Vector3(0, 1.6, 0)
	var motion := InputEventMouseMotion.new()
	motion.position = root.get_final_transform() * game.camera.unproject_position(game._response_slots()[3].global_position)
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	ally._input(release)
	check(ally.current_slot == game._response_slots()[3] and ally.card_data.health == 7 and source.current_slot == game._response_slots()[1], "physical drag-release moves and heals other ally, source stays")
	check(game.board_input.action.is_empty() and not ally.is_dragging, "successful move releases interaction lock")
	game.begin_move_effect(source)
	click(ally)
	var cancel := InputEventMouseButton.new()
	cancel.button_index = MOUSE_BUTTON_RIGHT
	cancel.pressed = true
	ally._input(cancel)
	check(ally.current_slot == game._response_slots()[3] and not ally.in_hand and not ally.is_dragging, "right-click cancellation restores board card")
	fixture()
	ally = card(data("Target"), 0)
	var rally_data := data("Rally")
	rally_data.utility = true
	rally_data.effect = "rally"
	var rally = card(rally_data)
	game.try_utility(rally, game._response_slots()[3])
	check(not paused and game.board_input.action.get("kind", "") == "pick", "targeted spell uses direct board pick")
	click(ally)
	check(ally.statuses.strength == 2 and game.preparedness == 9 and game.board_input.action.is_empty(), "clicking board target resolves spell and pays once")
	game.plans.tokens = 1
	director.show_plans()
	director.select_brace()
	click(ally)
	check(game.plans.tokens == 0 and game.plans.armed.kind == "brace", "Brace uses board click")
	fixture()
	ally = card(data("Extraction target"), 0)
	ally.card_data.health = 2
	game.plans.unlock("extract")
	game.plans.tokens = 1
	director.show_plans()
	director.begin_tactic("extract")
	click(ally)
	var choose := InputEventMouseButton.new()
	choose.button_index = MOUSE_BUTTON_LEFT
	choose.pressed = true
	game._response_slots()[2].get_node("StaticBody3D").input_event.emit(game.camera, choose, Vector3.ZERO, Vector3.UP, 0)
	check(game.plans.armed.kind == "extract" and game.plans.armed.destination == game._response_slots()[2], "extraction chooses ally then exact empty board lane")
	ally.take_damage(20)
	check(ally.is_alive() and ally.card_data.health == 2 and ally.current_slot == game._response_slots()[2], "extraction saves one lethal attack without losing HP")
	ally.take_damage(2)
	check(not ally.is_alive(), "extraction cannot save ally twice")
	fixture()
	ally = card(data("Medicine target"), 0)
	ally.card_data.health = 2
	ally.add_status("bleed", 3)
	game.plans.unlock("medicine")
	game.plans.tokens = 1
	game.plans.arm("medicine", [ally])
	game.plans.apply_combat()
	check(ally.card_data.health == 5 and not ally.statuses.has("bleed"), "Field Medicine heals and clears Bleed")
	game.plans.finish_combat()
	game.turn = 2
	game.plans.unlock("shelter")
	game.plans.tokens = 1
	game.plans.arm("shelter", [])
	game.plans.apply_combat()
	game._damage_side(true, 5)
	check(game.player_hp == 18, "Emergency Shelter blocks three hero damage")
	game.plans.finish_combat()
	check(game.plan_hero_barrier == 0, "temporary hero protection expires")
	game.turn = 3
	game.plans.unlock("precision")
	game.plans.tokens = 1
	check(not game.plans.arm("precision", [ally]), "two-token tactic cannot be bought for one")
	game.plans.tokens = 2
	game.plans.arm("precision", [ally])
	game.plans.apply_combat()
	check(ally.effective_attack() == 4, "Precision Team grants two temporary attack")
	game.plans.finish_combat()
	check(ally.effective_attack() == 2, "precision expires")
	game.turn = 4
	game.plans.unlock("flank")
	game.plans.tokens = 1
	game.plans.arm("flank", [ally])
	game.plans.apply_combat()
	check(ally.plan_ignore_taunt, "Flanking Route temporarily ignores Taunt")
	game.plans.finish_combat()
	check(not ally.plan_ignore_taunt, "flank expires")
	game.turn = 5
	game.plans.unlock("supply")
	game.plans.tokens = 1
	game.deck.append(data("Supply draw"))
	game.plans.arm("supply", [])
	game.plans.apply_combat()
	check(game.get_hand_cards().size() == 1, "Supply Line draws a card")
	fixture()
	director.encounter = "elite"
	director.battle_finished(true)
	check(director.screen == "contingency_reward" and director.buff_choices.size() == 3, "elite teaches one of three locked tactics")
	await capture("contingency_unlock")
	var chosen: String = director.buff_choices[0].id
	director.select_contingency_reward(chosen)
	check(chosen in game.plans.unlocked and director.screen == "reward", "unlock persists and normal card reward follows")
	game.clear_battle()
	check(chosen in game.plans.unlocked, "battle cleanup keeps unlocked tactics")
	game.plans.reset_run()
	check(game.plans.unlocked.size() == 2, "new run resets unlocks")
	fixture()
	game.enemy_deck.append(data("Future base", "disaster"))
	var evolution := data("Held evolution", "disaster")
	evolution.cost = 1
	game.enemy_evolution_deck.append(evolution)
	game.enemy_draw_cards(1)
	game.enemy_draw_evolutions(1)
	check(game.enemy_hand.size() == 2 and game.enemy_evolution_deck.is_empty(), "base cards and evolutions share actual hand")
	game.opponent_hand.refresh()
	await capture("opponent_hand")
	var seal_data := data("Seal")
	seal_data.utility = true
	seal_data.effect = "seal"
	var seal = card(seal_data)
	game.enemy_deck.append(data("Untargetable future", "disaster"))
	game.try_utility(seal, game._response_slots()[3])
	await capture("masked_hand_seal")
	game.complete_utility_choice(game.enemy_hand[1])
	check(game.is_sealed(game.enemy_hand[1]) and not game.enemy_deck[0].has("locked_until"), "seal locks held evolution, never draw pile")
	var human_hand = card(data("Human hand"))
	var human_board = card(data("Human board"), 0)
	game.deck.append(data("Human future"))
	game.enemy_utility({"effect":"seal"})
	check(game.is_sealed(human_hand.card_data) and not human_board.card_data.has("locked_until") and not game.deck[0].has("locked_until"), "enemy seal affects only player's hand")
	fixture()
	card(data("Response remains"), 0)
	game.enemy_hand.append(evolution)
	game._begin_round()
	check(game.phase == game.Phase.GAME_OVER, "unplayable evolution-only hand cannot stall exhausted encounter")
	event_fixture("radio")
	director.resolve_event("radio_buy")
	check(director.coins == 15 and director.collection.size() == 14, "radio trades supplies for two utility cards")
	event_fixture("rooftop")
	director.resolve_event("training")
	check(game.buff_value(true, "plan_start") == 1 and game.buff_value(true, "energy") == -1, "rooftop training has a permanent planning/resource tradeoff")
	event_fixture("science")
	var offer: Array = director.event_cards.duplicate(true)
	director.show_event()
	check(director.event_cards == offer, "event previews do not reroll rewards")
	await capture("science_event")
	director.resolve_event("science_0")
	check(game.player_hp == 17 and director.collection[-1].on_hit.burn == 5, "science event trades HP for stronger status unit")
	event_fixture("infirmary")
	game.player_hp = 5
	director.resolve_event("treatment")
	check(game.player_hp == 13 and director.collection[-1].effect == "delay", "full treatment heals with a deadweight downside")
	event_fixture("lost_found")
	director.show_remove_cards("event")
	director.preview_remove(0)
	director.confirm_remove()
	check(director.collection.size() == 11 and director.coins == 60 and 3 in director.cleared, "lost and found trades exact card for supplies")
	director.screen = ""
	director.show_menu()
	check(not director.content.get_children().any(func(node): return node is Button and node.text.to_lower().contains("new run")), "menu has no new-run shortcut")
	director.return_title()
	await process_frame
	await process_frame
	game = current_scene
	director = game.run_director
	check(director.screen == "title" and not director.content.get_children().any(func(node): return node is Button and node.text.to_lower().contains("new run")), "starting screen uses Start game")
	if failures > 0:
		quit(1)
		return
	print("PASS: physical board relocation/cancel, board spell/Plan targeting, six unlockable tactics/effects/progression, shared masked enemy hand/hand-only seals/no stall, five new event trades/stability, starting-screen flow")
	quit(0)
