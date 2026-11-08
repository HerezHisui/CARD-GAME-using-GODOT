extends SceneTree
## LAN_PREP_UTILITIES part 1: no-target utilities (Draw, Blast, Barrier, Herb, Tablet) and the delayed
## tactics Supply Line and Emergency Shelter, sent as host messages through lan_actions.gd.
## The flag is reached through game.lan_prep_utilities_override. With it false everything is not_supported.

const LanActions = preload("res://scripts/lan_actions.gd")
const LanView = preload("res://scripts/lan_view.gd")
const LanSession = preload("res://scripts/lan_session.gd")
const VersusMatch = preload("res://scripts/versus_match.gd")

var failures := 0
var checks := 0
var game: Node
var director: Node


func _initialize() -> void:
	call_deferred("run")


func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + label)


func run() -> void:
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	director = game.run_director
	game.presentation.automated_choice = 0
	await process_frame
	check_flag_constants()
	await check_flag_off()
	await check_simple_effects()
	await check_refusals()
	await check_tactics()
	await check_views()
	game.lan_prep_utilities_override = null
	game.set_seats("local", "local")
	game.clear_battle()
	game.queue_free()
	await process_frame
	if failures > 0:
		quit(1)
		return
	print("PASS: lan_utility_effects_smoke (%d checks)" % checks)
	quit(0)


func unit(id: String, cost: int = 1) -> Dictionary:
	return {"id": id, "name": "Unit " + id, "type": "response", "element": "evac", "cost": cost,
		"attack": 1, "health": 10}


func threat(id: String) -> Dictionary:
	return {"id": id, "name": "Threat " + id, "type": "disaster", "element": "fire", "cost": 0,
		"attack": 1, "health": 10, "tension_cost": 0}


func spell(id: String, effect: String, cost: int = 1) -> Dictionary:
	return {"id": id, "name": "Spell " + id, "type": "response", "element": "evac", "cost": cost,
		"utility": true, "effect": effect}


# Puts a card straight into a lane, like the other smoke suites do.
func put(definition: Dictionary, slot: Node3D) -> Node:
	var card: Node = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup(definition.duplicate(true))
	card.current_slot = slot
	card.in_hand = false
	return card


# A Versus Preparedness play phase on a remote seat, flag on or off.
func fixture(flag: bool) -> void:
	paused = false
	game.clear_battle()
	game.set_seats("remote", "local")
	game.encounter_kind = "versus"
	game.disaster_is_human = false
	game.disaster_seat_view = false
	game.lan_prep_utilities_override = flag
	game.player_first = true
	game.turn = 1
	game.player_hp = 20
	game.enemy_hp = 20
	game.energy_cap = 5
	game.preparedness = 5
	game.plans.tokens = 2
	game.plans.committed_round = 0
	game.plans.unlocked.assign(["brace", "coordinate", "supply", "shelter", "extract"])
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game._set_phase(game.Phase.PLAYER_PLAY)


func send(msg) -> Dictionary:
	return await LanActions.apply(game, msg, "preparedness")


func hand_ids() -> Array:
	return game.get_hand_cards().map(func(card: Node) -> String: return str(card.card_data.id))


func graveyard_ids() -> Array:
	return game.player_graveyard.map(func(entry: Dictionary) -> String: return str(entry.id))


func lane_card(lane: int) -> Node:
	return game._get_card_in_slot(game._response_slots()[lane])


func threat_card(lane: int) -> Node:
	return game._get_card_in_slot(game._threat_slots()[lane])


func check_flag_constants() -> void:
	# The flag now ships true (lan_flag_defaults_smoke checks the shipped values). PROTOCOL adds 2 for it.
	var expected := 3 + (1 if VersusMatch.LAN_EVOLUTION_PICKS else 0) + (2 if VersusMatch.LAN_PREP_UTILITIES else 0)
	expect(LanSession.PROTOCOL == expected, "flag: PROTOCOL counts the utilities flag")
	expect(game.lan_prep_utilities_override == null, "flag: override is null by default")


# Flag false (override false): every utility and the three delayed tactics are still not_supported.
func check_flag_off() -> void:
	fixture(false)
	game.add_card_to_hand(spell("s_draw", "draw"))
	game.deck.assign([unit("d1"), unit("d2")])
	for msg in [{"kind": "utility", "hand": 0, "target": -1}, {"kind": "utility", "hand": 0}]:
		var result: Dictionary = await send(msg)
		expect(not result.ok and result.reason == "not_supported", "off: utility refused as not_supported")
	for id in ["supply", "shelter", "extract"]:
		var result: Dictionary = await send({"kind": "tactic", "id": id, "lane": 0})
		expect(result.reason == "not_supported", "off: %s refused as not_supported" % id)
	expect(game.preparedness == 5 and hand_ids() == ["s_draw"] and game.deck.size() == 2, "off: nothing spent")
	expect(game.plans.tokens == 2 and game.plans.armed.is_empty(), "off: no token spent, nothing armed")
	var hint: Dictionary = LanView.build(game, "preparedness").hints[0]
	expect(hint.problem == "not_supported" and not hint.can_play and not hint.has("utility"), "off: hint unchanged")
	var tactic_hint: Dictionary = LanView.build(game, "preparedness").tactics[2]
	expect(tactic_hint.id == "supply" and not tactic_hint.available and not tactic_hint.has("no_ally"),
		"off: Supply hint unchanged")


func check_simple_effects() -> void:
	# Draw: pays once, draws, goes to the graveyard. The same message again hits a different card.
	fixture(true)
	game.add_card_to_hand(spell("s_draw", "draw"))
	game.deck.assign([unit("d1"), unit("d2"), unit("d3")])
	var result: Dictionary = await send({"kind": "utility", "hand": 0, "target": -1, "id": "s_draw"})
	expect(result.ok, "draw: cast accepted")
	expect(game.preparedness == 4, "draw: paid once")
	expect(hand_ids().size() == 2 and "s_draw" not in hand_ids(), "draw: two cards drawn, spell left the hand")
	expect(game.deck.size() == 1 and graveyard_ids() == ["s_draw"], "draw: deck shorter, spell in the graveyard")
	result = await send({"kind": "utility", "hand": 0, "target": -1, "id": "s_draw"})
	expect(not result.ok and game.preparedness == 4 and game.deck.size() == 1, "draw: repeat spends nothing")
	# Draw power adds cards. A full hand draws nothing but the spell is still spent.
	fixture(true)
	var powered := spell("s_draw_p", "draw")
	powered.utility_power = 1
	game.add_card_to_hand(powered)
	game.deck.assign([unit("d1"), unit("d2"), unit("d3"), unit("d4")])
	result = await send({"kind": "utility", "hand": 0})
	expect(result.ok and hand_ids().size() == 3 and game.deck.size() == 1, "draw: utility_power draws 3")
	# Blast: damages every threat for 2 + power.
	fixture(true)
	var blast := spell("s_blast", "blast")
	blast.utility_power = 1
	game.add_card_to_hand(blast)
	put(threat("t0"), game._threat_slots()[0])
	put(threat("t3"), game._threat_slots()[3])
	result = await send({"kind": "utility", "hand": 0, "target": -1})
	expect(result.ok and game.preparedness == 4, "blast: cast and paid")
	expect(int(threat_card(0).card_data.health) == 7 and int(threat_card(3).card_data.health) == 7, "blast: 3 damage each")
	# Barrier: Preparedness barrier and a status on every ally.
	fixture(true)
	game.add_card_to_hand(spell("s_barrier", "barrier"))
	put(unit("a0"), game._response_slots()[0])
	put(unit("a2"), game._response_slots()[2])
	result = await send({"kind": "utility", "hand": 0})
	expect(result.ok and game.player_barrier == 2, "barrier: side barrier 2")
	expect(int(lane_card(0).statuses.get("barrier", 0)) == 2 and int(lane_card(2).statuses.get("barrier", 0)) == 2,
		"barrier: every ally gets 2")
	# Herb: heals 1 and clears bleed on every ally.
	fixture(true)
	game.add_card_to_hand(spell("s_herb", "herb", 0))
	var hurt := put(unit("a1"), game._response_slots()[1])
	hurt.card_data.health = 4
	hurt.statuses["bleed"] = 2
	result = await send({"kind": "utility", "hand": 0})
	expect(result.ok and game.preparedness == 5, "herb: free to cast")
	expect(int(hurt.card_data.health) == 5 and not hurt.statuses.has("bleed"), "herb: healed 1, bleed gone")
	# Tablet: heals 2 and clears healing_reduced on every ally.
	fixture(true)
	game.add_card_to_hand(spell("s_tablet", "tablet"))
	hurt = put(unit("a3"), game._response_slots()[3])
	hurt.card_data.health = 4
	hurt.statuses["healing_reduced"] = 1
	result = await send({"kind": "utility", "hand": 0})
	expect(result.ok and int(hurt.card_data.health) == 6 and not hurt.statuses.has("healing_reduced"),
		"tablet: healed 2, healing_reduced gone")
	# Refund energy and no ally on the board still spend the spell, as the local drop does.
	fixture(true)
	var refund := spell("s_herb_r", "herb", 2)
	refund.refund_energy = 1
	game.add_card_to_hand(refund)
	result = await send({"kind": "utility", "hand": 0})
	expect(result.ok and game.preparedness == 4, "herb: refund energy applies (5 - 2 + 1)")


func check_refusals() -> void:
	fixture(true)
	game.add_card_to_hand(spell("s_draw", "draw", 1))
	game.add_card_to_hand(spell("s_dear", "draw", 9))
	var sealed := spell("s_sealed", "draw")
	sealed.locked_until = game.turn + 2
	game.add_card_to_hand(sealed)
	game.add_card_to_hand(spell("s_scout", "scout"))
	game.add_card_to_hand(unit("u_plain"))
	game.deck.assign([unit("d1"), unit("d2")])
	var before_hand := hand_ids()
	var cases: Array = [
		[{"kind": "utility", "hand": 99, "target": -1}, "bad_hand"],
		[{"kind": "utility", "hand": "0", "target": -1}, "bad_hand"],
		[{"kind": "utility", "hand": 0.0, "target": -1}, "bad_hand"],
		[{"kind": "utility", "target": -1}, "bad_hand"],
		[{"kind": "utility", "hand": 4, "target": -1}, "bad_hand"],
		[{"kind": "utility", "hand": 0, "target": 0}, "bad_target"],
		[{"kind": "utility", "hand": 0, "target": -1.0}, "bad_target"],
		[{"kind": "utility", "hand": 0, "target": "x"}, "bad_target"],
		[{"kind": "utility", "hand": 0, "id": "someone_else"}, "stale_hand"],
		[{"kind": "utility", "hand": 0, "id": 5}, "stale_hand"],
		[{"kind": "utility", "hand": 1}, "no_energy"],
		[{"kind": "utility", "hand": 2}, "sealed"],
		[{"kind": "utility", "hand": 3, "target": 0}, "bad_target"],
	]
	for case in cases:
		var result: Dictionary = await send(case[0])
		expect(not result.ok and result.reason == case[1],
			"refuse: %s as %s (got %s)" % [JSON.stringify(case[0]), case[1], result.reason])
	expect(game.preparedness == 5 and hand_ids() == before_hand and game.deck.size() == 2, "refuse: nothing spent")
	expect(game.player_graveyard.is_empty(), "refuse: nothing reached the graveyard")
	# Phase, busy pick and full lanes.
	game._set_phase(game.Phase.ENEMY)
	var result: Dictionary = await send({"kind": "utility", "hand": 0})
	expect(result.reason == "not_prep_turn", "refuse: not on the Disaster turn")
	game._set_phase(game.Phase.PLAYER_PLAY)
	game.board_input.action = {"kind": "test"}
	result = await send({"kind": "utility", "hand": 0})
	expect(result.reason == "busy", "refuse: not while a host pick is open")
	game.board_input.clear()
	for lane in 4:
		put(unit("full%d" % lane), game._response_slots()[lane])
	result = await send({"kind": "utility", "hand": 0})
	expect(result.reason == "lane_full" and game.preparedness == 5, "refuse: the local drop needs an empty lane")
	# A unit card is not a utility, and the unit play path still refuses utilities.
	var played: Dictionary = game.preparedness_actions.play_card(0, 0)
	expect(played.reason in ["not_supported", "lane_full"], "refuse: play_card keeps utilities out")


func check_tactics() -> void:
	# Supply Line: arms now, draws at combat start.
	fixture(true)
	game.deck.assign([unit("d1"), unit("d2")])
	var result: Dictionary = await send({"kind": "tactic", "id": "supply", "lane": 2})
	expect(not result.ok and result.reason == "bad_lane" and game.plans.tokens == 2, "supply: an ally lane is refused")
	result = await send({"kind": "tactic", "id": "supply"})
	expect(result.ok and game.plans.armed.get("kind", "") == "supply", "supply: armed with no ally")
	expect(game.plans.tokens == 1 and game.plans.committed_round == game.turn, "supply: one token spent")
	expect(game.deck.size() == 2 and hand_ids().is_empty(), "supply: nothing drawn yet")
	result = await send({"kind": "tactic", "id": "shelter"})
	expect(not result.ok and result.reason == "tactic_unavailable" and game.plans.tokens == 1,
		"supply: a second tactic this round is refused, no token spent")
	game.plans.apply_combat()
	expect(hand_ids().size() == 1 and game.deck.size() == 1, "supply: combat start draws one card")
	game.plans.finish_combat()
	# Supply with an empty deck is refused before spending.
	fixture(true)
	game.deck.clear()
	result = await send({"kind": "tactic", "id": "supply", "lane": -1})
	expect(not result.ok and result.reason == "tactic_unavailable" and game.plans.tokens == 2,
		"supply: empty deck refused")
	# Emergency Shelter: 3 temporary attack protection at combat start.
	fixture(true)
	result = await send({"kind": "tactic", "id": "shelter", "lane": -1})
	expect(result.ok and game.plans.armed.get("kind", "") == "shelter" and game.plans.tokens == 1, "shelter: armed")
	expect(game.plan_hero_barrier == 0, "shelter: not applied before combat")
	game.plans.apply_combat()
	expect(game.plan_hero_barrier == 3, "shelter: 3 protection at combat start")
	game.plans.finish_combat()
	expect(game.plan_hero_barrier == 0, "shelter: ends with the combat")
	# No tokens and a bad id spend nothing.
	fixture(true)
	game.plans.tokens = 0
	result = await send({"kind": "tactic", "id": "shelter"})
	expect(result.reason == "tactic_unavailable" and game.plans.armed.is_empty(), "shelter: no token, refused")
	game.plans.tokens = 2
	result = await send({"kind": "tactic", "id": "shelter", "lane": "0"})
	expect(result.reason == "bad_lane" and game.plans.tokens == 2, "shelter: a string lane is refused")
	game.plans.unlocked.assign(["brace"])
	result = await send({"kind": "tactic", "id": "shelter"})
	expect(result.reason == "bad_tactic" and game.plans.tokens == 2, "shelter: not unlocked is refused")
	# Brace still works as before.
	fixture(true)
	put(unit("a2"), game._response_slots()[2])
	result = await send({"kind": "tactic", "id": "brace", "lane": 2})
	expect(result.ok and game.plans.armed.get("kind", "") == "brace", "brace: one-ally tactic unchanged")


# Hints with the flag on, and a Disaster view that knows nothing new.
func check_views() -> void:
	fixture(true)
	game.add_card_to_hand(spell("s_draw", "draw"))
	game.add_card_to_hand(spell("s_scout", "scout"))
	game.add_card_to_hand(unit("u_plain"))
	game.deck.assign([unit("d1")])
	var prep: Dictionary = LanView.build(game, "preparedness")
	expect(prep.hints[0].can_play and prep.hints[0].utility and prep.hints[0].effect == "draw", "view: draw is castable")
	expect(prep.hints[0].lanes.is_empty() and prep.hints[0].problem == "", "view: a utility has no lanes")
	expect(prep.hints[1].can_play and prep.hints[1].problem == "", "view: scout is castable")
	expect(not prep.hints[2].has("utility") and prep.hints[2].can_play, "view: units keep their lane hint")
	var supply: Dictionary = prep.tactics[2]
	expect(supply.id == "supply" and supply.available and supply.no_ally and supply.lanes.is_empty(),
		"view: Supply needs no ally")
	var shelter: Dictionary = prep.tactics[3]
	expect(shelter.id == "shelter" and shelter.available and shelter.no_ally, "view: Shelter needs no ally")
	expect(not prep.tactics[4].available, "view: Extraction not available yet")
	var text := JSON.stringify(LanView.build(game, "disaster"))
	expect(not text.contains("s_draw") and not text.contains("no_ally") and not text.contains("\"utility\""),
		"view: the Disaster view carries nothing of it")
