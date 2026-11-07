extends "res://tests/balance_utility_smoke.gd"

var prep: Dictionary
var disaster: Dictionary

func full_board() -> void:
	reset()
	game.phase = game.Phase.PLAYER_PLAY
	game.energy_cap = 30
	game.preparedness = 30
	for lane in 4: response_unit(prep.base.heavy_loader, lane)

func cast(id: String) -> bool:
	return game.try_utility(hand_card(prep.base[id]), null)

func clear_confirmation() -> void:
	game.clear_battle()
	game.run_director.close_modal()

func rules_stage() -> void:
	reset()
	game.disaster_actions.actions_used = 100
	var base: Dictionary = disaster.base.ember.duplicate(true)
	game.enemy_hand.assign([base])
	expect((await game.disaster_actions.play_base(base, game._threat_slots()[0])).ok,
		"Arbitrary action count does not cap a legal resource-funded play")
	expect(game.tension == 2, "Only resources pay for base play")
	var threat: Node = game._get_card_in_slot(game._threat_slots()[0])
	game.turn = 7
	game._apply_round_modifiers()
	expect(threat.modifiers.is_empty(), "Singleplayer round upgrades are excluded")
	reset()
	var first := unit(disaster.base.ember, 0)
	var second := unit(disaster.base.ember, 1)
	var evolution: Dictionary = disaster.evolutions.wildfire.duplicate(true)
	game.enemy_hand.assign([evolution])
	clear_confirmation.call_deferred()
	var result: Dictionary = await game.disaster_actions.evolve(evolution, [first, second], first.current_slot)
	expect(not result.ok, "Encounter teardown releases pending confirmation")
	reset()
	var director: Node = game.run_director
	game.player_run_buffs = {"cadet": 1}
	game.enemy_run_buffs = {"cadet": 1}
	director.selected_character = 1
	director.start_versus_match()
	expect(game.player_run_buffs.is_empty() and game.enemy_run_buffs.is_empty(), "Actual match clears run bonuses")
	expect(game.player_buffs.is_empty() and game.enemy_buffs.is_empty(), "Actual match has no adaptations")
	var ids: Array = game.versus_master.preparedness.map(func(card): return card.id)
	expect("rally" in ids and "momentum_team" in ids, "Actual match receives paired preset")
	for card: Dictionary in game.versus_master.preparedness + game.versus_master.disaster:
		expect(int(card.get("upgrades", 0)) == 0, "Actual match uses unupgraded card: " + str(card.id))
	director.versus_match.finish(true)
	expect(game.player_run_buffs == {"cadet": 1}, "Match restores the saved singleplayer bonuses")
	game.player_run_buffs.clear()
	game.enemy_run_buffs.clear()
	reset()

func protection_stage() -> void:
	for first_side: bool in [true, false]:
		reset()
		game.player_first = first_side
		game.phase = game.Phase.PLAYER_PLAY
		game.preparedness = 4
		game.energy_cap = 4
		var armored: Dictionary = disaster.base.ember.duplicate(true)
		armored.modifier = "armored"
		armored.armor_value = 2
		var guard := unit(armored, 0)
		var protected := unit(disaster.base.ember, 1)
		protected.add_status("barrier", 1)
		var wounded := unit(disaster.base.ember, 2)
		wounded.card_data.health = 1
		var fresh := unit(disaster.base.ember, 3)
		var player_before: int = game.player_hp
		var enemy_before: int = game.enemy_hp
		expect(cast("alarm_sweep"), "Sweep casts in either first-player order")
		expect(guard.card_data.health == 1, "Sweep retains Armored minimum damage")
		expect(protected.card_data.health == 2 and protected.statuses.barrier == 0, "Barrier absorbs Sweep")
		expect(not wounded.is_alive() and fresh.card_data.health == 1, "Sweep cleans wounded bases only")
		expect(game.player_hp == player_before and game.enemy_hp == enemy_before, "Sweep has no hero damage")
	reset()
	var needle := response_unit(prep.base.needle_team, 0)
	var armored: Dictionary = disaster.base.ember.duplicate(true)
	armored.modifier = "armored"
	armored.health = 10
	armored.armor_value = 3
	var blocker := unit(armored, 0)
	blocker.add_status("barrier", 1)
	var hp: int = game.enemy_hp
	game.resolve_single_strike(needle, blocker, true)
	expect(blocker.card_data.health == 9, "Piercing ignores armor reduction while Barrier still applies")
	expect(game.enemy_hp == hp, "Armored blocks Piercing hero damage")
	blocker.modifiers.erase("armored")
	game.resolve_single_strike(needle, blocker, true)
	expect(game.enemy_hp == hp - 2, "Piercing hero damage remains unchanged without Armored")

func conditional_stage() -> void:
	reset()
	var target := response_unit(prep.base.heavy_loader, 0)
	target.card_data.health = 30
	target.max_health = 30
	var ash := unit(disaster.evolutions.ash_predator, 0)
	var cinder := unit(disaster.base.cinder_cloud, 1)
	cinder.current_slot = game._threat_slots()[0]
	game.sacrifice_reward(cinder)
	expect(game.attack_strikes(ash, target) == 2, "Cinder's two Burn enables Ash Predator")
	game.resolve_attack(ash, target, false)
	expect(target.card_data.health == 24, "Double strike resolves twice before upkeep")
	target.status_upkeep()
	expect(target.statuses.burn == 1 and game.attack_strikes(ash, target) == 1,
		"Burn decay can turn off Ash Predator before next combat")
	var toxic := unit(disaster.base.toxic_runoff, 2)
	game.resolve_single_strike(toxic, target, false)
	expect(target.statuses.poison == 2, "Toxic Runoff retains two Poison")
	target.status_upkeep()
	var venom := unit(disaster.evolutions.venom_surge, 3)
	expect(target.statuses.poison == 1 and game.conditional_attack_bonus(venom, target) == 2,
		"Venom payoff survives normal Poison upkeep")
	reset()
	var momentum := response_unit(prep.base.momentum_team, 0)
	game.apply_utility_pick("rally", momentum, 0)
	expect(game.attack_strikes(momentum, null) == 2, "Rally still enables Momentum Team")
	var pressure := unit(disaster.evolutions.pressure_break, 0)
	expect(game.attack_strikes(pressure, null) == 1, "Pressure Break still needs three Strength")
	var choir := unit(disaster.evolutions.aftershock, 1)
	game.apply_formation_effect(choir)
	expect(game.attack_strikes(pressure, null) == 2, "Aftershock Choir still enables Pressure Break")
	reset()
	var heat := response_unit(prep.base.heat_seeker, 0)
	var steam := response_unit(prep.base.steam_team, 1)
	var enemy := unit(disaster.base.tremor, 0)
	enemy.card_data.health = 30
	enemy.max_health = 30
	game.resolve_single_strike(steam, enemy, true)
	enemy.status_upkeep()
	expect(enemy.statuses.burn == 1 and game.conditional_attack_bonus(heat, enemy) == 3,
		"Steam Team still enables Heat Seeker after Burn decay")
	var last := response_unit(prep.base.last_responder, 2)
	enemy.statuses.clear()
	last.add_status("bleed", 3)
	expect(game.conditional_attack_bonus(last, enemy) == 0, "Last Responder never uses its own Bleed")
	enemy.add_status("bleed", 1)
	expect(game.conditional_attack_bonus(last, enemy) == 2, "Enemy one Bleed enables Last Responder")
	var lance := response_unit(prep.base.containment_lance, 3)
	enemy.add_status("poison", 1)
	expect(game.conditional_attack_bonus(lance, enemy) == 2, "Two combined harmful stacks enable Lance")
	expect(lance.card_data.ignore_taunt, "Lance retains Taunt bypass")

func utility_stage() -> void:
	full_board()
	var ally: Node = game._get_card_in_slot(game._response_slots()[0])
	ally.card_data.health = 1
	ally.add_status("bleed", 2)
	expect(cast("herb"), "Healing casts on full board")
	expect(ally.card_data.health == 2 and not ally.statuses.has("bleed"), "Herb keeps heal and cleanse")
	ally.add_status("healing_reduced", 2)
	expect(cast("tablet"), "Tablet casts on full board")
	expect(ally.card_data.health == 4 and not ally.statuses.has("healing_reduced"), "Tablet retains healing")
	expect(cast("barrier"), "Protection casts on full board")
	expect(ally.statuses.barrier == 2, "Protection retains two Barrier")
	ally.add_status("poison", 2)
	expect(cast("cleanse"), "Cleanse opens targets on full board")
	game.complete_utility_choice(ally)
	expect(not ally.statuses.has("poison"), "Targeted cleanse resolves")
	game.deck.assign([prep.base.quick_dash])
	expect(cast("tutor"), "Tutor opens targets on full board")
	game.complete_utility_choice(game.deck[0])
	expect(game.get_hand_cards().any(func(card): return card.card_data.id == "quick_dash"), "Tutor resolves")
	var grave: Dictionary = prep.base.field_medic.duplicate(true)
	grave.graveyard_reason = "Destroyed"
	grave.recovery = prep.base.field_medic.duplicate(true)
	game.player_graveyard.assign([grave])
	expect(cast("recovery_detail"), "Recovery opens targets on full board")
	game.complete_utility_choice(grave)
	expect(grave not in game.player_graveyard, "Recovery removes the chosen graveyard copy")
	var recovered: Array = game.get_hand_cards().filter(func(card): return card.card_data.id == "field_medic")
	expect(recovered.size() == 1 and recovered[0].card_data.get("recovered", false),
		"Recovery returns the unit with its recovery marker")
	game.deck.assign([prep.base.quick_dash])
	var draw := hand_card(prep.base.supply_cache)
	expect(game.try_utility(draw, null), "Draw utility casts on full board")
	var move := hand_card(prep.base.emergency_exit)
	var energy: int = game.preparedness
	expect(not game.try_utility(move, null), "Movement still requires an empty destination")
	expect(move in game.get_hand_cards() and energy == game.preparedness, "Invalid movement spends nothing")

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	reset()
	prep = Decks.pool("preparedness")
	disaster = Decks.pool("disaster")
	await rules_stage()
	protection_stage()
	conditional_stage()
	utility_stage()
	game.clear_battle()
	game.queue_free()
	await process_frame
	print("balance_stages_smoke: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
