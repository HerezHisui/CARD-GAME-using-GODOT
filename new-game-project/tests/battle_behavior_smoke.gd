extends SceneTree
## Characterizes the current scene-backed rules before any extraction.

var game: Node
var director: Node
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		print("FAIL: " + message)

func definition(id: String, side: String = "response", attack: int = 2, health: int = 20) -> Dictionary:
	return {
		"id": id, "name": id, "type": side, "element": "evac" if side == "response" else "earthquake",
		"cost": 1 if side == "response" else 0, "attack": attack, "health": health,
	}

func unit(data: Dictionary, lane: int = -1) -> Node:
	var card: Node = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup(data.duplicate(true))
	if lane < 0:
		card.reparent(game.hand_parent())
		game.hand.append(card)
	else:
		var slots: Array = game._response_slots() if data.type == "response" else game._threat_slots()
		card.current_slot = slots[lane]
		card.in_hand = false
	return card

func fixture() -> void:
	paused = false
	game.clear_battle()
	game.player_run_buffs.clear()
	game.enemy_run_buffs.clear()
	game.player_hp = 20
	game.enemy_hp = 20
	game.enemy_max_hp = 20
	game.turn = 1
	game.player_first = true
	game.energy_cap = 3
	game.preparedness = 3
	game.tension_cap = 3
	game.tension = 3
	game.plan_hero_barrier = 0
	game.encounter_kind = "battle"
	game.plans.auto_save = false
	director.floor_number = 1
	director.screen = ""
	director.modal.hide()
	director.battle_active = true
	game._set_phase(game.Phase.PLAYER_PLAY)

func damage_fixture() -> void:
	fixture()
	var attacker: Node = unit(definition("attacker", "response", 3), 0)
	var defender: Node = unit(definition("defender", "disaster"), 0)
	check(game._calc_damage(attacker, defender).dmg == 6, "advantage multiplies attack before defenses")
	defender.card_data.element = "flood"
	check(game._calc_damage(attacker, defender).dmg == 1, "resisted odd attack rounds down")
	defender.card_data.element = "earthquake"
	defender.add_modifier("armored")
	defender.add_modifier("fragile")
	defender.planned_guard = 2
	defender.add_status("barrier", 2)
	game.resolve_attack(attacker, defender, true)
	check(defender.card_data.health == 18, "armor, fragile, guard and barrier resolve in current order")
	check(defender.planned_guard == 0 and defender.statuses.barrier == 0, "one-hit defenses are consumed")
	check(attacker.card_data.health == 20, "surviving defender does not immediately counterattack")
	defender.card_data.health = 1
	game.resolve_attack(attacker, defender, true)
	check(not defender.is_alive() and game.enemy_hp == 20, "blocked overkill does not spill into hero HP")
	attacker.add_modifier("piercing")
	defender = unit(definition("replacement", "disaster"), 0)
	game.resolve_attack(attacker, defender, true)
	check(defender.card_data.health == 14 and game.enemy_hp == 17, "piercing uses raw hero attack once")
	attacker.add_status("burn", 5)
	attacker.add_status("poison", 2)
	attacker.add_modifier("regenerating")
	attacker.status_upkeep()
	check(attacker.card_data.health == 14, "Burn and Poison damage precede regeneration")
	check(attacker.statuses.burn == 2 and attacker.statuses.poison == 1, "periodic stacks decay")
	attacker.add_status("bleed", 3)
	attacker.after_attack(1)
	check(attacker.card_data.health == 11 and attacker.statuses.bleed == 2, "Bleed resolves after attack")

func draw_fixture() -> void:
	fixture()
	var first: Dictionary = definition("first")
	var sealed: Dictionary = definition("sealed")
	sealed.locked_until = 3
	game.deck.assign([first, definition("last"), sealed])
	game.draw_cards(2)
	var cards: Array = game.get_hand_cards()
	check(cards.size() == 2, "draw skips sealed cards")
	check(cards[0].card_data.id == "last" and cards[1].card_data.id == "first", "draw takes last unlocked first")
	check(game.deck == [sealed], "sealed copy stays in draw pile")
	for i in range(6):
		unit(definition("held_%d" % i))
	game.deck.append(first.duplicate(true))
	game.draw_cards(1)
	check(game.get_hand_cards().size() == 8 and game.deck.size() == 2, "full hand leaves draw pile intact")
	var duplicate: Dictionary = definition("duplicate", "disaster")
	var earlier: Dictionary = duplicate.duplicate(true)
	var later: Dictionary = duplicate.duplicate(true)
	game.enemy_deck.assign([earlier, definition("middle", "disaster"), later])
	game.enemy_draw_cards(1)
	check(is_same(game.enemy_hand[0], later), "enemy draw returns the last equal dictionary")
	check(is_same(game.enemy_deck[1], later), "erase removes the first equal dictionary, retaining the last")

func utility_fixture() -> void:
	fixture()
	var data: Dictionary = definition("tutor_fixture")
	data.utility = true
	data.effect = "tutor"
	var spell: Node = unit(data)
	var selected: Dictionary = definition("chosen")
	game.deck.assign([selected, definition("other")])
	check(game.try_utility(spell, game._response_slots()[0]), "tutor opens a pending choice")
	check(game.preparedness == 3 and game.deck.size() == 2, "opening choice spends nothing")
	game.cancel_utility_choice()
	check(spell.in_hand and game.preparedness == 3, "cancel preserves spell and energy")
	game.try_utility(spell, game._response_slots()[0])
	game.complete_utility_choice(selected)
	check(game.preparedness == 2 and game.deck.size() == 1, "confirmed tutor pays once and removes selection")
	check(game.get_hand_cards().size() == 1, "selected card replaces consumed spell")
	check(game.get_hand_cards()[0].card_data.id == "chosen", "tutor delivers exact selected definition")
	check(game.player_graveyard.size() == 1, "cast Response utility is recorded once")
	var taxed: Dictionary = definition("taxed", "disaster")
	game.increase_cost(taxed)
	game.increase_cost(taxed)
	game.increase_cost(taxed)
	check(taxed.cost == 0 and taxed.tension_cost == 3, "base tax caps at two without becoming an evolution")
	game.turn = 2
	game.expire_tax(taxed)
	check(taxed.tension_cost == 3, "tax remains through next round")
	game.turn = 3
	game.expire_tax(taxed)
	check(taxed.tension_cost == 1 and not taxed.has("tax_original"), "tax restores original cost at expiry")

func round_fixture() -> void:
	fixture()
	game.player_first = false
	game.deck.append(definition("next_draw"))
	game.enemy_hand.append(definition("remaining_threat", "disaster"))
	await game._on_end_turn_pressed()
	check(game.turn == 2 and game.player_first, "End Turn increments round and swaps first side")
	check(game.energy_cap == 4 and game.preparedness == 4, "new round grows and refills Response energy")
	check(game.tension_cap == 4 and game.tension == 4, "new round grows and refills Disaster Tension")
	check(game.phase == game.Phase.PLAYER_DRAW, "next player turn awaits drawing")
	game._on_draw_button_pressed()
	game.complete_draw_choice(game.deck[0])
	check(game.phase == game.Phase.PLAYER_PLAY and game.get_hand_cards().size() == 1, "draw enters play phase")
	game.turn = 3
	check(game.enemy_action_limit() == 1, "Floor 1 normal has one action through round three")
	game.turn = 4
	check(game.enemy_action_limit() == 2, "Floor 1 normal has two actions from round four")

func sacrifice_fixture() -> void:
	fixture()
	var fuel: Dictionary = definition("draw_fuel", "disaster")
	fuel.on_sacrifice = "draw"
	var source: Node = unit(fuel, 0)
	game.enemy_deck.append(definition("sacrifice_draw", "disaster"))
	await source.sacrifice_dissolve()
	check(game.enemy_hand.size() == 1, "sacrificing draw fuel draws exactly one card")
	check(game._get_card_in_slot(game._threat_slots()[0]) == null, "sacrifice frees lane immediately")
	check(game.player_graveyard.is_empty(), "Disaster sacrifice does not enter Response graveyard")
	fuel = definition("burn_fuel", "disaster")
	fuel.on_sacrifice = "burn"
	source = unit(fuel, 1)
	var opposing: Node = unit(definition("opposing"), 1)
	await source.sacrifice_dissolve()
	check(opposing.statuses.get("burn", 0) == 2, "sacrifice Burn targets its original opposing lane")
	var evolution: Node = unit(definition("major", "disaster"), 0)
	game.major_evolution_entry(evolution, 2)
	check(evolution.statuses.is_empty(), "two sacrifices have no major evolution entry reward")
	game.enemy_deck.append(definition("entry_draw", "disaster"))
	game.major_evolution_entry(evolution, 4)
	check(evolution.statuses.get("barrier", 0) == 3, "four sacrifices grant three Barrier")
	check(game.enemy_hand.size() == 2 and opposing.card_data.health == 19, "major entry draws and shocks enemies")
	var unaffordable: Dictionary = definition("unaffordable", "disaster")
	unaffordable.cost = 2
	check(game.best_evolution_plan([evolution], [unaffordable]).is_empty(), "cannot evolve without enough sacrifices")

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	director.persistence.enabled = false
	game.presentation.automated_choice = 0
	await process_frame
	damage_fixture()
	draw_fixture()
	utility_fixture()
	await round_fixture()
	await sacrifice_fixture()
	game.clear_battle()
	await process_frame
	print("%s: battle_behavior_smoke.gd" % ("PASS" if failures == 0 else "FAIL"))
	quit(1 if failures else 0)
