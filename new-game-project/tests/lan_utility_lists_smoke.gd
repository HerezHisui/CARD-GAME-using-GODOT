extends SceneTree
## LAN_PREP_UTILITIES part 3: private list picks. Tutor (own deck), Recover (own graveyard), Tax (Disaster hand,
## blind). Handles are positions in the choice's own list. Stale, forged, repeated and cancelled picks change nothing.

const LanActions = preload("res://scripts/lan_actions.gd")
const LanView = preload("res://scripts/lan_view.gd")

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
	await check_tutor()
	await check_recover()
	await check_tax()
	await check_stale_and_forged()
	game.lan_prep_utilities_override = null
	game.set_seats("local", "local")
	game.clear_battle()
	game.queue_free()
	await process_frame
	if failures > 0:
		quit(1)
		return
	print("PASS: lan_utility_lists_smoke (%d checks)" % checks)
	quit(0)


func unit(id: String, cost: int = 1) -> Dictionary:
	return {"id": id, "name": "Unit " + id, "type": "response", "element": "evac", "cost": cost,
		"attack": 1, "health": 10}


func threat(id: String, cost: int = 0) -> Dictionary:
	return {"id": id, "name": "Threat " + id, "type": "disaster", "element": "fire", "cost": cost,
		"attack": 1, "health": 10, "tension_cost": 1}


func spell(id: String, effect: String, cost: int = 2) -> Dictionary:
	return {"id": id, "name": "Spell " + id, "type": "response", "element": "evac", "cost": cost,
		"utility": true, "effect": effect}


func put(definition: Dictionary, slot: Node3D) -> Node:
	var card: Node = game.Card3DScene.instantiate()
	game.add_child(card)
	card.add_to_group("cards")
	card.setup(definition.duplicate(true))
	card.current_slot = slot
	card.in_hand = false
	return card


func fixture() -> void:
	paused = false
	game.clear_battle()
	game.set_seats("remote", "local")
	game.encounter_kind = "versus"
	game.disaster_is_human = false
	game.disaster_seat_view = false
	game.lan_prep_utilities_override = true
	game.player_first = true
	game.turn = 1
	game.player_hp = 20
	game.enemy_hp = 20
	game.energy_cap = 5
	game.preparedness = 5
	game.plans.tokens = 2
	game.plans.committed_round = 0
	director.battle_active = true
	director.screen = ""
	director.modal.hide()
	game._set_phase(game.Phase.PLAYER_PLAY)


func send(msg) -> Dictionary:
	return await LanActions.apply(game, msg, "preparedness")


func choice() -> RefCounted:
	return game.preparedness_actions.utility_choice


func pick_msg(handle, stage_override = null) -> Dictionary:
	var open: RefCounted = choice()
	return {"kind": "utility_pick", "encounter": open.encounter, "choice": open.choice,
		"stage": open.stage if stage_override == null else stage_override, "handle": handle}


func cancel_msg() -> Dictionary:
	return {"kind": "utility_cancel", "encounter": choice().encounter, "choice": choice().choice}


func hand_ids() -> Array:
	return game.get_hand_cards().map(func(card: Node) -> String: return str(card.card_data.id))


func deck_ids() -> Array:
	return game.deck.map(func(entry: Dictionary) -> String: return str(entry.id))


func candidate_ids() -> Array:
	return LanView.build(game, "preparedness").pending_choice.candidates.map(
		func(entry: Dictionary) -> String: return str(entry.card.id))


func check_tutor() -> void:
	fixture()
	game.add_card_to_hand(spell("s_tutor", "tutor"))
	var locked := unit("t_locked")
	locked.locked_until = game.turn + 2
	game.deck.assign([unit("t_a"), unit("t_b"), locked, unit("t_c")])
	var result: Dictionary = await send({"kind": "utility", "hand": 0})
	expect(result.ok and choice().stage == "deck" and choice().handles == [0, 1, 2], "tutor: sealed card is not offered")
	expect(candidate_ids() == ["t_a", "t_b", "t_c"], "tutor: the view lists the deck candidates")
	expect(game.preparedness == 5 and hand_ids() == ["s_tutor"] and deck_ids().size() == 4, "tutor: begin spends nothing")
	result = await send(pick_msg(3))
	expect(result.reason == "bad_handle" and choice().active(), "tutor: a handle past the list is refused")
	result = await send(cancel_msg())
	expect(result.ok and game.preparedness == 5 and deck_ids().size() == 4, "tutor: cancel spends nothing")
	await send({"kind": "utility", "hand": 0})
	expect(candidate_ids() == ["t_a", "t_b", "t_c"], "tutor: casting again lists the same candidates")
	result = await send(pick_msg(1))
	expect(result.ok and not choice().active(), "tutor: pick accepted")
	expect(hand_ids() == ["t_b"] and deck_ids() == ["t_a", "t_locked", "t_c"], "tutor: card moved from deck to hand")
	expect(game.preparedness == 3 and game.player_graveyard.size() == 1, "tutor: paid once, spell in the graveyard")
	result = await send(pick_msg(1))
	expect(result.reason == "no_choice" and hand_ids() == ["t_b"], "tutor: a repeated pick is refused")
	# Duplicate copies: two equal entries are two handles and one is taken.
	fixture()
	game.add_card_to_hand(spell("s_tutor", "tutor"))
	game.deck.assign([unit("t_same"), unit("t_same")])
	await send({"kind": "utility", "hand": 0})
	expect(choice().handles == [0, 1], "tutor: duplicate copies have two handles")
	result = await send(pick_msg(1))
	expect(result.ok and deck_ids() == ["t_same"] and hand_ids() == ["t_same"], "tutor: one copy taken")
	# Empty deck: no choice.
	fixture()
	game.add_card_to_hand(spell("s_tutor", "tutor"))
	game.deck.clear()
	result = await send({"kind": "utility", "hand": 0})
	expect(result.reason == "no_target" and not choice().active(), "tutor: empty deck, no choice")


func graveyard_unit(id: String, recovered: bool = false) -> void:
	var card := put(unit(id), game._response_slots()[0])
	if recovered: card.base_definition["recovered"] = true
	game.record_graveyard(card, "Destroyed")
	card.current_slot = null
	card.queue_free()


func check_recover() -> void:
	fixture()
	game.add_card_to_hand(spell("s_recover", "recover"))
	graveyard_unit("g_a")
	graveyard_unit("g_old", true)
	graveyard_unit("g_b")
	await process_frame
	var result: Dictionary = await send({"kind": "utility", "hand": 0})
	expect(result.ok and choice().stage == "grave" and choice().handles == [0, 1], "recover: two eligible units")
	expect(candidate_ids() == ["g_a", "g_b"], "recover: the view lists the graveyard candidates")
	var graveyard_before: int = game.player_graveyard.size()
	result = await send(pick_msg(0, "deck"))
	expect(result.reason == "stale_choice" and choice().active(), "recover: wrong stage is stale")
	result = await send(pick_msg(1))
	expect(result.ok and not choice().active(), "recover: pick accepted")
	expect(hand_ids() == ["g_b"] and game.get_hand_cards()[0].card_data.get("recovered", false),
		"recover: unit back in hand")
	# The graveyard lost the unit and gained the spell.
	expect(game.player_graveyard.size() == graveyard_before, "recover: unit left, spell arrived")
	expect(game.recoverable_units().map(func(e: Dictionary) -> String: return str(e.id)) == ["g_a"],
		"recover: g_a remains")
	expect(game.preparedness == 3, "recover: paid once")
	result = await send(pick_msg(1))
	expect(result.reason == "no_choice", "recover: a repeated pick is refused")
	# Nothing to recover: no choice.
	fixture()
	game.add_card_to_hand(spell("s_recover", "recover"))
	result = await send({"kind": "utility", "hand": 0})
	expect(result.reason == "no_target" and not choice().active(), "recover: empty graveyard, no choice")


func check_tax() -> void:
	fixture()
	var taxer := spell("s_tax", "tax")
	taxer.utility_power = 1
	game.add_card_to_hand(taxer)
	game.enemy_hand.assign([threat("h_a"), threat("h_b"), threat("h_c")])
	var result: Dictionary = await send({"kind": "utility", "hand": 0})
	expect(result.ok and choice().stage == "hand" and choice().handles == [0, 1, 2], "tax: one handle per Disaster card")
	var candidates: Array = LanView.build(game, "preparedness").pending_choice.candidates
	expect(candidates.size() == 3 and candidates.all(func(entry: Dictionary) -> bool: return entry.keys() == ["handle"]),
		"tax: candidates are blind handles only")
	expect(not JSON.stringify(LanView.build(game, "preparedness")).contains("h_a"), "tax: no face in the view")
	result = await send(pick_msg(1))
	expect(result.ok and not choice().active(), "tax: pick accepted")
	expect(int(game.enemy_hand[1].tension_cost) == 3 and int(game.enemy_hand[0].tension_cost) == 1
		and int(game.enemy_hand[2].tension_cost) == 1, "tax: power 1 raises only the chosen card by 2")
	expect(game.preparedness == 3 and game.player_graveyard.size() == 1, "tax: paid once")
	result = await send(pick_msg(1))
	expect(result.reason == "no_choice" and int(game.enemy_hand[1].tension_cost) == 3, "tax: a repeat changes nothing")
	# No Disaster card, no choice.
	fixture()
	game.add_card_to_hand(spell("s_tax", "tax"))
	game.enemy_hand.clear()
	result = await send({"kind": "utility", "hand": 0})
	expect(result.reason == "no_target" and not choice().active(), "tax: empty Disaster hand, no choice")


func check_stale_and_forged() -> void:
	# The deck changes between begin and pick.
	fixture()
	game.add_card_to_hand(spell("s_tutor", "tutor"))
	game.deck.assign([unit("t_a"), unit("t_b")])
	await send({"kind": "utility", "hand": 0})
	game.deck.remove_at(1)
	var result: Dictionary = await send(pick_msg(1))
	expect(not result.ok and not choice().active() and game.preparedness == 5,
		"stale: gone entry closes it, spends nothing")
	expect(hand_ids() == ["s_tutor"], "stale: the spell is still in hand")
	# The Disaster hand changes.
	fixture()
	game.add_card_to_hand(spell("s_tax", "tax"))
	game.enemy_hand.assign([threat("h_a"), threat("h_b")])
	await send({"kind": "utility", "hand": 0})
	game.enemy_hand.remove_at(0)
	result = await send(pick_msg(0))
	expect(result.reason == "stale_choice" and game.preparedness == 5, "stale: changed Disaster hand")
	# Forged shapes for a list pick.
	fixture()
	game.add_card_to_hand(spell("s_tutor", "tutor"))
	game.deck.assign([unit("t_a")])
	await send({"kind": "utility", "hand": 0})
	var cases: Array = [
		[pick_msg(-1), "bad_handle"],
		[pick_msg(1), "bad_handle"],
		[pick_msg("0"), "bad_message"],
		[pick_msg(0, "hand"), "stale_choice"],
		[pick_msg(0, "ally"), "stale_choice"],
		[{"kind": "utility_pick", "encounter": game.encounter_serial, "choice": choice().choice + 5,
			"stage": "deck", "handle": 0}, "stale_choice"],
	]
	for case in cases:
		result = await send(case[0])
		expect(not result.ok and result.reason == case[1],
			"forged: %s refused as %s (got %s)" % [JSON.stringify(case[0]), case[1], result.reason])
	expect(choice().active() and game.preparedness == 5 and deck_ids() == ["t_a"], "forged: still open, nothing changed")
	# A tutor message from the wrong seat.
	result = await LanActions.apply(game, pick_msg(0), "disaster")
	expect(not result.ok and choice().active(), "forged: the Disaster seat cannot pick")
