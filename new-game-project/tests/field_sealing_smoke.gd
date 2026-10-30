extends SceneTree

var game: Node
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAILED: " + message)

func unit(lane: int) -> Node:
	var card = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup({"id":"target", "name":"Target", "type":"disaster", "element":"fire",
		"cost":0, "attack":2, "health":10})
	card.in_hand = false
	card.current_slot = game._threat_slots()[lane]
	return card

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.set_process(false)
	game.run_director.new_run()
	game.clear_battle()
	game.run_director.battle_active = true
	game.run_director.modal.hide()
	game.turn = 3
	game.player_first = true
	game.phase = game.Phase.PLAYER_PLAY
	game.preparedness = 10
	var target := unit(0)
	var other := unit(1)
	var seal = game.Card3DScene.instantiate()
	game.add_child(seal)
	seal.add_to_group("cards")
	seal.setup({"id":"seal", "name":"Seal", "type":"response", "element":"evac",
		"cost":1, "utility":true, "effect":"seal"})
	seal.in_hand = true
	game.hand.append(seal)
	check(game.try_utility(seal, game._response_slots()[0]), "seal accepts live board targets")
	check(game.board_input.action.get("cards", []).has(target), "seal highlights deployed disaster")
	check(not game.run_director.modal.visible, "seal does not expose hidden hand")
	if not game.has_method("seal_field_card"):
		check(false, "field seal API exists")
	else:
		game.complete_utility_choice(target)
		check(game.field_seal_active(target.card_data), "first Response seal active this round")
		check(not game.can_sacrifice(target), "sealed unit cannot sacrifice")
		check(target.can_attack(3), "seal leaves attack eligibility intact")
		var evolution := {"id":"evo", "name":"Evolution", "type":"disaster", "element":"fire",
			"cost":2, "attack":100, "health":100}
		check(game.best_evolution_plan([target, other], [evolution]).is_empty(), "AI excludes sealed material")
		await target.sacrifice_dissolve()
		check(is_instance_valid(target.current_slot), "direct sacrifice entry also refuses sealed card")
		game.turn = 4
		check(not game.field_seal_active(target.card_data), "first seal expires at next round")
		game.player_first = false
		game.seal_field_card(target)
		check(not game.field_seal_active(target.card_data), "second Response seal pending this round")
		check(game.field_seal_text(target.card_data).contains("5"), "pending label names affected round")
		check(game.run_director.persistence.checkpoint(), "pending seal checkpoints")
		check(game.run_director.persistence.resume(), "pending seal restores")
		target = game._get_card_in_slot(game._threat_slots()[0])
		other = game._get_card_in_slot(game._threat_slots()[1])
		check(target.card_data.seal_round == 5 and not game.can_sacrifice(null), "save retains exact affected round")
		game.turn = 5
		check(game.field_seal_active(target.card_data), "pending seal activates next round")
		game.turn = 6
		check(not game.field_seal_active(target.card_data), "pending seal expires after one affected round")
		var recovered: Dictionary = game.recovered_definition(target.card_data)
		check(not recovered.has("seal_round"), "recovery removes field seal state")
		other.current_slot = null
		check(not game.seal_targets().has(other), "off-field card is not eligible")
		target.current_slot = null
		check(game.seal_targets().is_empty(), "no valid target returns an empty candidate list")
		var unused = game.Card3DScene.instantiate()
		game.add_child(unused)
		unused.add_to_group("cards")
		unused.setup({"id":"seal", "name":"Seal", "type":"response", "element":"evac",
			"cost":1, "utility":true, "effect":"seal"})
		unused.in_hand = true
		game.hand.append(unused)
		game.preparedness = 10
		var energy: int = game.preparedness
		check(not game.try_utility(unused, game._response_slots()[0]), "no targets refuses the cast")
		check(game.preparedness == energy and unused.in_hand, "no targets spends neither energy nor card")
		var replacement := unit(0)
		check(game.can_sacrifice(replacement), "replacement card does not inherit old lane seal")
		check(game.try_utility(unused, game._response_slots()[0]), "replacement becomes a valid selection")
		replacement.current_slot = null
		game.complete_utility_choice(replacement)
		check(game.preparedness == energy and unused.in_hand, "removed target cancels without spending")
		check(game.pending_utility == null and game.board_input.action.is_empty(), "stale selection is cleared")
	var definitions = JSON.parse_string(FileAccess.get_file_as_string("res://data/response_expansion.json"))
	check(definitions.filter(func(c): return c.id == "alarm_sweep")[0].cost == 4, "Alarm Sweep costs 4")
	game.queue_free()
	await process_frame
	print("Field sealing smoke: %d failures" % failures)
	quit(1 if failures else 0)
