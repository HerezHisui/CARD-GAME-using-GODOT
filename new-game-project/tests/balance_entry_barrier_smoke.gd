extends "res://tests/balance_economy_smoke.gd"
## Stage 2B: the Versus Disaster entry Barrier nerf (DISASTER_ENTRY_BARRIER_NERF), tested through its override.
## On: 3 sacrifices gain 0 Barrier and 4 or more gain 1. The draw and the 1-damage shock stay.
## With the balance patch on, the matching-material +1 still comes on top (3 sacrifices 1, 4 or more 2).
## Singleplayer, the Warden (boss) and Response units keep the old numbers (1 and 2).

func evolution_card() -> Node:
	var card: Node = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup({"id": "eb_evo", "name": "EB Evo", "type": "disaster", "element": "fire", "cost": 3,
		"attack": 1, "health": 8, "tension_cost": 0})
	return card

func entry(kind: String, sacrifices: int, nerf: Variant) -> Dictionary:
	reset()
	game.encounter_kind = kind
	game.entry_barrier_nerf_override = nerf
	var card := evolution_card()
	game.enemy_deck.append({"id": "eb_draw", "name": "EB Draw", "type": "disaster", "element": "fire", "cost": 0,
		"attack": 1, "health": 2})
	var victim: Node = game.Card3DScene.instantiate()
	game.add_child(victim)
	victim.add_to_group("cards")
	victim.setup({"id": "eb_victim", "name": "EB Victim", "type": "response", "element": "evac", "cost": 1,
		"attack": 1, "health": 10})
	victim.place_on_slot(game._response_slots()[0])
	var hand_before: int = game.enemy_hand.size()
	game.major_evolution_entry(card, sacrifices)
	return {"barrier": int(card.statuses.get("barrier", 0)), "drew": game.enemy_hand.size() - hand_before,
		"shock": 10 - int(victim.card_data.health)}

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	var VersusMatch = preload("res://scripts/versus_match.gd")
	expect(game.entry_barrier_nerf_override == null, "Override is null by default")
	# The const decides when no override is set (currently false, see versus_match.gd).
	var by_const: Dictionary = await entry("versus", 3, null)
	expect(by_const.barrier == (0 if VersusMatch.DISASTER_ENTRY_BARRIER_NERF else 1), "Const decides: 3 sacrifices")
	# Nerf on, Versus.
	var three: Dictionary = await entry("versus", 3, true)
	expect(three.barrier == 0 and three.drew == 1 and three.shock == 0, "On: 3 sacrifices 0 Barrier, draw 1, no shock")
	var four: Dictionary = await entry("versus", 4, true)
	expect(four.barrier == 1 and four.drew == 1 and four.shock == 1, "On: 4 sacrifices 1 Barrier, draw 1, shock 1")
	var five: Dictionary = await entry("versus", 5, true)
	expect(five.barrier == 1 and five.drew == 1 and five.shock == 1, "On: 5 sacrifices 1 Barrier, draw 1, shock 1")
	var two: Dictionary = await entry("versus", 2, true)
	expect(two.barrier == 0 and two.drew == 0, "On: 2 sacrifices still gain nothing")
	# Nerf off, Versus: today's numbers.
	var old_three: Dictionary = await entry("versus", 3, false)
	var old_four: Dictionary = await entry("versus", 4, false)
	expect(old_three.barrier == 1 and old_three.drew == 1, "Off: 3 sacrifices 1 Barrier and draw")
	expect(old_four.barrier == 2 and old_four.drew == 1 and old_four.shock == 1, "Off: 4 sacrifices 2 Barrier")
	# Singleplayer and the Warden keep today's numbers even with the override on.
	for kind in ["battle", "elite", "boss"]:
		var sp_three: Dictionary = await entry(kind, 3, true)
		var sp_four: Dictionary = await entry(kind, 4, true)
		expect(sp_three.barrier == 1 and sp_four.barrier == 2, "Unchanged outside Versus: " + kind)
	# The nerf test of the helper itself.
	reset()
	game.entry_barrier_nerf_override = true
	expect(game.entry_barrier_nerf_on(), "Versus, override on")
	game.encounter_kind = "battle"
	expect(not game.entry_barrier_nerf_on(), "Battle never counts")
	# Matching material on top, through the real evolve path. Ember is a base of Wildfire.
	var pool: Dictionary = Decks.pool("disaster")
	# Cases: [all materials match, sacrifices, nerf on, wanted Barrier].
	for case in [[true, 3, true, 1], [true, 4, true, 2], [true, 4, false, 3], [true, 3, false, 2],
			[false, 3, true, 0], [false, 4, true, 1]]:
		reset()
		game.entry_barrier_nerf_override = case[2]
		var evolution: Dictionary = game.balance_card(pool.evolutions.worldbreaker)
		var materials: Array = []
		# Cinder Cloud is a special material, so it never matches: no bonus.
		var material: Dictionary = pool.base.tremor if case[0] else pool.base.cinder_cloud
		for lane in int(case[1]): materials.append(unit(material, lane))
		var matching: int = game.matching_material_barrier(evolution, materials)
		evolution.cost = int(case[1])
		expect(matching == (1 if case[0] else 0), "Matching bonus for " + str(case))
		expect(await game.disaster_evolve(evolution, materials, game._threat_slots()[0]), "Evolves " + str(case))
		var evolved: Node = game._get_card_in_slot(game._threat_slots()[0])
		var got := int(evolved.statuses.get("barrier", 0))
		expect(got == int(case[3]), "Barrier %d for %s (got %d)" % [int(case[3]), str(case), got])
	# The card text follows the flag.
	var text_old: String = Rules.special_text({"type": "disaster", "cost": 3})
	var text_new: String = Rules.special_text({"type": "disaster", "cost": 3}, true)
	var four_old: String = Rules.special_text({"type": "disaster", "cost": 4})
	var four_new: String = Rules.special_text({"type": "disaster", "cost": 4}, true)
	expect(text_old.contains("gain 1 Barrier and draw 1"), "Text off: 3 sacrifices says 1 Barrier")
	expect(text_new.contains("On evolution: draw 1.") and not text_new.contains("Barrier"), "Text on: no Barrier at 3")
	expect(four_old.contains("gain 2 Barrier") and four_new.contains("gain 1 Barrier and draw 1"), "Text 4 sacrifices")
	game.entry_barrier_nerf_override = null
	game.balance_patch_override = null
	game.clear_battle()
	game.queue_free()
	await process_frame
	print("balance_entry_barrier_smoke: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
