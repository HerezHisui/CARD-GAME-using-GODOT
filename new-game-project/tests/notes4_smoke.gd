extends SceneTree
var game: Node
var director: Node
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error("FAILED: " + message)

func unit(name: String, lane: int, element: String = "evac", side: String = "response") -> Node:
	var card = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup({"id":name, "name":name, "type":side, "element":element, "cost":1, "attack":3, "health":6})
	if lane < 0:
		card.reparent(game.hand_parent())
		game.hand.append(card)
		game.arrange_hand_centered()
	else: card.place_on_slot((game._response_slots() if side == "response" else game._threat_slots())[lane])
	return card

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts")
	root.get_texture().get_image().save_png("res://tests/artifacts/" + name + ".png")

func run() -> void:
	var scene = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.presentation.automated_choice = 0
	game = scene
	director = game.run_director
	game.set_process(false)
	director.persistence.discard()
	director.show_title()
	await capture("notes4_title")
	director.start_character(0)
	await capture("notes4_vertical_map")
	var canvas = director.content.find_children("*", "ScrollContainer", true, false)[0].get_child(0)
	check(canvas.point(director.rooms[0]).y > canvas.point(director.rooms[-1]).y, "map climbs from bottom to boss")
	var old_collection: Array = director.collection.duplicate(true)
	director.add_collection_card(director.collection[0])
	check(director.sorted_indices(director.collection, 6, false)[0] == 12, "recent sort selects newest exact duplicate")
	check(director.collection.slice(0, 12) == old_collection, "sorting does not mutate collection")
	director.screen = ""
	director.modal.hide()
	director.battle_active = true
	game._set_phase(game.Phase.PLAYER_PLAY)
	game.energy_cap = 7
	game.preparedness = 6
	game.player_first = false
	var first = unit("First", 0)
	var second = unit("Second", 2, "brace")
	check(second in game.plans.coordination_targets(first), "nearest allies across an empty lane can coordinate with different types")
	var blocker = unit("Between", 1, "douse")
	check(second not in game.plans.coordination_targets(first), "cannot skip an intervening ally")
	check(blocker in game.plans.coordination_targets(first), "physically adjacent mixed types coordinate")
	first.add_status("strength", 1)
	check(first._atk_label.text == "4", "Strength updates visible attack immediately")
	first.add_status("barrier", 9)
	check(first.statuses.barrier == 3, "barrier cannot accumulate beyond three")
	game.plans.tokens = 2
	game.plans.arm("coordinate", [first])
	var held = unit("Held", -1)
	held.add_status("strength", 2)
	game.increase_cost(held.card_data)
	game.increase_cost(held.card_data)
	game.increase_cost(held.card_data)
	check(held.card_data.cost == 3, "tax stacking caps at two extra cost")
	var foe = unit("Enemy", 0, "fire", "disaster")
	foe.card_data.on_sacrifice = "burn"
	game.sacrifice_reward(foe)
	check(first.statuses.burn == 2, "sacrifice releases Burn without hero overflow")
	game.enemy_deck.append({"id":"fuel", "name":"Fuel", "type":"disaster", "element":"fire", "cost":0, "attack":1, "health":2})
	foe.card_data.on_sacrifice = "draw"
	game.sacrifice_reward(foe)
	check(game.enemy_hand.size() == 1, "sacrifice refunds a card from finite draw pile")
	game.enemy_deck.append({"id":"refill", "name":"Refill", "type":"disaster", "element":"fire", "cost":0, "attack":1, "health":2})
	game.major_evolution_entry(foe, 3)
	check(foe.statuses.barrier == 2 and game.enemy_hand.size() == 2, "three sacrifices gain immediate protection and draw")
	var health_before: int = first.card_data.health
	game.major_evolution_entry(foe, 4)
	check(foe.statuses.barrier == 3 and first.card_data.health == health_before - 1, "four sacrifices gain capped protection and formation damage")
	game.player_hp = 13
	game.turn = 3
	game.player_graveyard.append({"id":"lost", "name":"Lost", "type":"response", "element":"evac", "cost":1, "attack":1, "health":1, "graveyard_reason":"Destroyed", "graveyard_round":2})
	game.plans.unlock("extract")
	check(director.persistence.checkpoint(), "player-turn checkpoint writes successfully")
	check(director.persistence.has_run(), "unfinished run is available")
	game.player_hp = 1
	game.preparedness = 0
	director.coins = 0
	check(director.persistence.resume(), "continue restores saved run")
	await process_frame
	check(game.player_hp == 13 and game.preparedness == 6 and director.coins == 35, "continue restores health resources supplies")
	check(game.turn == 3 and game.phase == game.Phase.PLAYER_PLAY and game.get_hand_cards().size() == 1, "continue restores exact turn phase and hand")
	var restored = game._get_card_in_slot(game._response_slots()[0])
	check(restored.card_data.health == first.card_data.health if is_instance_valid(first) else restored.card_data.health == 6, "restore does not apply character health twice")
	check(restored.statuses.strength == 1 and restored._atk_label.text == "5",
		"restore retains live statuses, the armed plan and displayed stats")
	check(game.plans.armed.kind == "coordinate" and game.plans.armed.targets.size() == 1 and "extract" in game.plans.unlocked, "restore retains armed tactic and unlocks")
	check(game.enemy_hand.size() == 2 and game.player_graveyard.size() == 1, "restore preserves hidden hand and graveyard")
	game.turn = 4
	game.expire_tax(game.get_hand_cards()[0].card_data)
	check(game.get_hand_cards()[0].card_data.cost == 1, "temporary tax expires and original cost returns")
	check(director.persistence.checkpoint(), "subsequent checkpoint replaces save atomically")
	director.battle_active = false
	director.screen = ""
	director.show_rewards()
	var reward: Array = director.reward_stock.duplicate(true)
	check(director.persistence.checkpoint(), "pending reward checkpoints")
	check(director.persistence.resume() and director.screen == "reward" and director.reward_stock == director.persistence.normalize(reward), "continue retains exact reward offers")
	director.screen = ""
	director.show_contingency_reward("floor")
	var tactics: Array = director.buff_choices.duplicate(true)
	check(director.persistence.checkpoint() and director.persistence.resume() and director.buff_choices == tactics, "tactic unlock offers do not reroll on continue")
	director.screen = ""
	director.show_floor_buffs()
	var buffs: Array = director.buff_choices.duplicate(true)
	check(director.persistence.checkpoint() and director.persistence.resume() and director.buff_choices == buffs, "floor buff offers do not reroll")
	director.return_title()
	await process_frame
	await process_frame
	await process_frame
	game = current_scene
	director = game.run_director
	game.set_process(false)
	check(director.screen == "title" and director.persistence.has_run(), "scene reload exposes Continue without starting another run")
	director.continue_saved_run()
	check(director.screen == "floor_buff" and director.buff_choices == buffs and director.collection.size() == 13, "Continue after reload preserves pending floor reward and deck")
	director.screen = ""
	director.modal.hide()
	director.battle_active = true
	game._set_phase(game.Phase.PLAYER_PLAY)
	game.final_boss = load("res://scripts/final_boss.gd").new()
	game.add_child(game.final_boss)
	game.final_boss.setup(game)
	game.final_boss.stage = 2
	game.final_boss.pillars_spawned = true
	game.final_boss.pulse_resolved = true
	game.final_boss.spawn("Saved pillar", "pillar", 0, 0, 4, "brace")
	check(director.persistence.checkpoint() and director.persistence.resume(), "final boss turn restores")
	check(game.final_boss.stage == 2 and game.final_boss.pillars_spawned and game.final_boss.pillars().size() == 1, "boss phase and pillars survive continue")
	director.show_buff_choices()
	var adaptation: Array = director.buff_choices.duplicate(true)
	var enemy_buffs: Dictionary = game.enemy_buffs.duplicate(true)
	check(director.persistence.checkpoint() and director.persistence.resume(), "pending adaptation restores")
	check(director.screen == "buff" and director.buff_choices == adaptation and game.enemy_buffs == enemy_buffs, "adaptation offers persist without applying enemy buff twice")
	director.run_active = false
	director.show_title()
	check(director.persistence.has_run(), "returning to title retains unfinished run")
	await capture("notes4_continue")
	director.confirm_abandon()
	check(director.persistence.has_run(), "abandon preview preserves run before confirmation")
	director.abandon_run()
	check(not director.persistence.has_run() and director.screen == "title", "confirmed abandon clears saved run")
	check(game.ENERGY_MAX == 7, "Preparedness energy ceiling is seven before buffs")
	check(not game.opponent_hand.get_children().any(func(node): return node is Label3D), "hand backs have no Janitor count caption")
	if failures > 0:
		quit(1)
		return
	print("PASS: vertical map, recent-copy sorting, mixed/gapped coordination, live stats, barrier/tax limits, sacrifice refunds, atomic turn/reward/tactic/floor saves, continue and confirmed abandon")
	quit(0)
