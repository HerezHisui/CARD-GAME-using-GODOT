extends "res://tests/balance_synergy_smoke.gd"

func reject_preview() -> void:
	var labels: Array = game.run_director.content.find_children("*", "Label", true, false)
	var text := ""
	for label: Label in labels: text += label.text
	expect(text.contains("Matching materials: +1") and text.contains("Total Barrier: 1 / 3"),
		"Matching protection shown before confirmation")
	game.run_director.balance_evolution_decision(false)

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	reset()
	var disaster: Dictionary = Decks.pool("disaster")
	var prep: Dictionary = Decks.pool("preparedness")
	for side: String in ["preparedness", "disaster"]:
		var preset: Dictionary = Decks.preset(side)
		expect(Decks.validate(side, preset).ok, "Balanced preset is legal: " + side)
	var main: Array = Decks.preset("preparedness").main
	for pair: Array in [["steam_team", "heat_seeker"], ["shard_barrier", "last_responder"],
			["rally", "momentum_team"], ["hazmat_team", "containment_lance"], ["lane_marshal", "quick_dash"]]:
		expect(pair[0] in main and pair[1] in main, "Response enabler and payoff: " + str(pair))
	var evolutions: Array = Decks.preset("disaster").evolutions
	for id: String in ["ash_predator", "venom_surge", "aftershock", "pressure_break", "gale_force"]:
		expect(id in evolutions, "Disaster payoff/support included: " + id)
	var builder: Control = load("res://scripts/deck_builder.gd").new()
	game.run_director.root.add_child(builder)
	builder.setup("preparedness", Decks.preset("preparedness"), game.run_director)
	expect(builder.main_pool.needle_team.element == "clearance", "Builder uses updated type for filters and sorting")
	expect(builder.main_pool.alarm_sweep.blast_damage == 1, "Builder preview uses one-damage Sweep")
	builder.queue_free()
	game.run_director.show_menu()
	var help: Label = game.run_director.content.get_node("RulesScroll/Rules/Adaptations")
	expect(help.visible and help.text.contains("adaptations, run buffs, and upgrades are unavailable"),
		"Versus help explicitly excludes progression")
	game.run_director.close_modal()
	expect(game.run_director.card_rules(prep.base.alarm_sweep).contains("1 fixed damage"), "Sweep description")
	expect(not game.run_director.card_rules(prep.base.alarm_sweep).contains("Choose an empty"), "Full-board help")
	var dash := response_unit(prep.base.quick_dash, 0)
	game.apply_relocation(dash, game._response_slots()[1], null)
	var parent := VBoxContainer.new()
	game.run_director.root.add_child(parent)
	var details: RichTextLabel = game.run_director.add_dossier(parent, dash.card_data, "", dash)
	expect(details.text.contains("Temporary movement attack: +1") and not details.text.contains("Plan attack: +1"),
		"Movement bonus shown separately from Plan attack and Strength")
	var heat := response_unit(prep.base.heat_seeker, 0)
	var target := unit(disaster.base.ember, 0)
	target.add_status("burn", 1)
	details = game.run_director.add_dossier(parent, heat.card_data, "", heat)
	expect(details.text.contains("Conditional ability: ACTIVE"), "Active conditional ability highlighted")
	parent.queue_free()
	reset()
	var first := unit(disaster.base.ember, 0)
	var second := unit(disaster.base.ember, 1)
	var evolution: Dictionary = disaster.evolutions.wildfire
	game.enemy_hand.assign([evolution])
	reject_preview.call_deferred()
	var result: Dictionary = await game.disaster_actions.evolve(evolution, [first, second], first.current_slot)
	expect(not result.ok and result.reason == "cancelled", "Evolution confirmation can be canceled")
	expect(evolution in game.enemy_hand and first.is_alive() and second.is_alive(), "Cancel spends no materials")
	game.lan_remote_disaster = true
	expect(Decks.pool("preparedness").base.needle_team.element == "evac", "LAN pool retains old type")
	expect("ash_predator" not in Decks.preset("disaster").evolutions, "LAN preset retains old evolution list")
	game.lan_remote_disaster = false
	game.balance_patch_override = false
	expect(Decks.pool("preparedness").base.scout.cost == 2, "Flag false restores pool costs")
	game.clear_battle()
	game.queue_free()
	await process_frame
	print("balance_preview_smoke: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
