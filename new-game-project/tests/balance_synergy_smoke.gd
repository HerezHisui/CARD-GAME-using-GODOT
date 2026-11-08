extends "res://tests/balance_economy_smoke.gd"

func response_unit(definition: Dictionary, lane: int) -> Node:
	var card: Node = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup(game.balance_card(definition))
	card.place_on_slot(game._response_slots()[lane])
	return card

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	reset()
	var disaster: Dictionary = Decks.pool("disaster", false)
	var prep: Dictionary = Decks.pool("preparedness", false)
	for id: String in Balance.OVERRIDES:
		if not Balance.OVERRIDES[id].has("tension_cost"): continue
		var source: Dictionary = disaster.base.get(id, disaster.spells.get(id, {}))
		var definition: Dictionary = game.balance_card(source)
		expect(definition.tension_cost == Balance.OVERRIDES[id].tension_cost, "Deployment price " + id)
		expect(int(definition.get("cost", 0)) == int(source.get("cost", 0)), "Sacrifice classification " + id)
	var costly: Dictionary = game.balance_card(disaster.base.cinder_cloud)
	game.enemy_hand.assign([costly])
	expect((await game.disaster_actions.play_base(costly, game._threat_slots()[0])).ok, "Two-tension base deploys")
	expect(game.tension == 1, "Deployment spends two tension")
	reset()
	for id: String in Balance.THRESHOLDS:
		var source: Dictionary = disaster.base.get(id, disaster.evolutions.get(id, prep.base.get(id, {})))
		# Some source thresholds now match the balance value, so check balance_card does not write to the source.
		var source_threshold := int(source.condition.threshold)
		var definition: Dictionary = game.balance_card(source)
		var condition: Dictionary = definition.condition
		var status := str(condition.status)
		if status == "any": status = "poison"
		var below := {status: int(condition.threshold) - 1}
		var enough := {status: int(condition.threshold)}
		expect(not game.condition_met(condition, {}, below), "Below threshold " + id)
		expect(game.condition_met(condition, {}, enough), "Exact threshold " + id)
		expect(int(source.condition.threshold) == source_threshold, "Source data unchanged " + id)
		expect(int(definition.condition.threshold) == int(Balance.THRESHOLDS[id]), "Balance threshold used " + id)
	for pair: Array in [["ember", "wildfire"], ["tremor", "fissure"],
			["rising_tide", "flash_flood"], ["gust", "gale_force"]]:
		var base: Dictionary = disaster.base[pair[0]]
		var evolution: Dictionary = disaster.evolutions[pair[1]]
		expect(Balance.matching_barrier(evolution, [base, base]) == 1, "Matching material " + pair[1])
		expect(Balance.matching_barrier(evolution, [base, disaster.base.cinder_cloud]) == 0,
			"Special material excluded " + pair[1])
	var materials: Array = []
	for lane in 4: materials.append(unit(disaster.base.tremor, lane))
	var worldbreaker: Dictionary = disaster.evolutions.worldbreaker
	# The entry Barrier nerf (on by default) gives 1 less. The old rule is needed to reach the cap of three.
	game.entry_barrier_nerf_override = false
	expect(game.matching_material_barrier(worldbreaker, materials) == 1, "Bonus awarded once")
	expect(await game.disaster_evolve(worldbreaker, materials, game._threat_slots()[0]), "Worldbreaker evolves")
	var evolved: Node = game._get_card_in_slot(game._threat_slots()[0])
	expect(evolved.statuses.get("barrier", 0) == 3, "Entry and matching protection cap at three")
	reset()
	var target := response_unit(prep.base.heavy_loader, 0)
	var cinder := unit(disaster.base.cinder_cloud, 0)
	game.sacrifice_reward(cinder)
	expect(target.statuses.get("burn", 0) == 2, "Cinder sacrifice still applies two Burn")
	var glass := unit(disaster.base.glass_quake, 1)
	game.enemy_deck.assign([disaster.base.gust])
	game.sacrifice_reward(glass)
	expect(game.enemy_hand.size() == 1 and game.enemy_hand[0].id == "gust", "Glass sacrifice draws base pile")
	reset()
	var dash := response_unit(prep.base.quick_dash, 0)
	game.apply_relocation(dash, game._response_slots()[0], null)
	expect(dash.effective_attack() == 2, "Invalid same-lane move grants nothing")
	game.apply_relocation(dash, game._response_slots()[1], null)
	expect(dash.effective_attack() == 3 and dash.statuses.get("strength", 0) == 0, "Move grants temporary attack")
	game.apply_relocation(dash, game._response_slots()[2], null)
	game.plans.preview_attack()
	expect(dash.effective_attack() == 3, "Second move and preview do not stack")
	game.plans.finish_combat()
	expect(dash.effective_attack() == 2, "Movement attack expires after combat")
	game.apply_relocation(dash, game._response_slots()[1], null)
	expect(dash.effective_attack() == 2, "Same round cannot reactivate after combat")
	game.turn += 1
	game.apply_relocation(dash, game._response_slots()[0], null)
	expect(dash.effective_attack() == 3, "Next round can activate again")
	game.clear_battle()
	game.queue_free()
	await process_frame
	print("balance_synergy_smoke: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
