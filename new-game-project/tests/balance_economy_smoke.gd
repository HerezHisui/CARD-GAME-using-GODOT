extends SceneTree

const Decks = preload("res://scripts/versus_decks.gd")
const Balance = preload("res://scripts/versus_balance.gd")
const Rules = preload("res://scripts/battle_rules.gd")
var game: Node
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + label)

func unit(definition: Dictionary, lane: int) -> Node:
	var card: Node = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup(definition.duplicate(true))
	card.place_on_slot(game._threat_slots()[lane])
	return card

func reset() -> void:
	game.clear_battle()
	game.encounter_kind = "versus"
	game.disaster_is_human = true
	game.balance_patch_override = true
	game.evolution_draw_choice_override = false
	game.run_director.battle_active = true
	game.run_director.close_modal()
	game.player_first = true
	game.phase = game.Phase.ENEMY
	game.tension = 3
	game.disaster_actions.begin_turn()

func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	expect(game.balance_patch_override == null and not game.balance_enabled(), "Default path stays off")
	reset()
	for round_number in [1, 2, 3, 4, 5, 6, 12]:
		game.turn = round_number
		game.tension = 99
		game.continue_round()
		var expected := 3 if round_number <= 2 else (4 if round_number <= 5 else 5)
		expect(game.tension == expected and game.tension_cap == expected, "Round refill without carry")
		game.presentation.cancel_coin()
	reset()
	var pool: Dictionary = Decks.pool("disaster")
	var first := unit(pool.base.ember, 0)
	var second := unit(pool.base.ember, 1)
	var evolution: Dictionary = pool.evolutions.wildfire.duplicate(true)
	game.enemy_hand.assign([evolution])
	game.tension = 0
	game.disaster_actions.actions_used = 100
	expect(game.disaster_actions.can_use(evolution), "Evolution remains available at zero tension after many actions")
	game.run_director.balance_evolution_decision.call_deferred(true)
	expect((await game.disaster_actions.evolve(evolution, [first, second], first.current_slot)).ok,
		"Legal evolution resolves at zero tension")
	expect(game.tension == 0, "Evolution has no tension payment")
	reset()
	var prep: Dictionary = Decks.pool("preparedness")
	var alarm: Dictionary = game.balance_card(prep.base.alarm_sweep)
	expect(alarm.cost == 4 and Rules.utility_text(alarm).contains("1 fixed damage"), "Alarm cost and text")
	for lane in 4: unit(pool.base.ember, lane)
	game.add_card_to_hand(alarm)
	game.preparedness = 4
	game.apply_simple_utility(game.get_hand_cards()[0], "blast")
	for lane in 4:
		expect(game._get_card_in_slot(game._threat_slots()[lane]).card_data.health == 1, "Fresh base survives Sweep")
	expect(game.preparedness == 0, "Sweep spends exactly four energy")
	game.lan_remote_disaster = true
	expect(not game.balance_enabled(), "LAN excludes balance override")
	game.lan_remote_disaster = false
	game.disaster_is_human = false
	expect(not game.balance_enabled(), "AI excludes balance override")
	game.disaster_is_human = true
	game.encounter_kind = "battle"
	expect(not game.balance_enabled(), "Singleplayer excludes balance override")
	game.clear_battle()
	game.queue_free()
	await process_frame
	print("balance_economy_smoke: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
