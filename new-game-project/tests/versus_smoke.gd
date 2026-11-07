# Covers: Versus deck rules (versus_decks.gd): presets, deck size, copies, evolutions, tactics, unknown ids.
# Also covers the Versus match (versus_match.gd): encounter kind, run_active, saves untouched, state restored.
extends SceneTree

const Decks = preload("res://scripts/versus_decks.gd")
const VersusMatch = preload("res://scripts/versus_match.gd")

var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + label)

# A deck must fail and the error list must not be empty.
func rejects(side: String, deck: Dictionary, label: String) -> void:
	var result: Dictionary = Decks.validate(side, deck)
	expect(not result.ok and not result.errors.is_empty(), label)

func run() -> void:
	var prep: Dictionary = Decks.preset(Decks.SIDE_PREP)
	var disaster: Dictionary = Decks.preset(Decks.SIDE_DISASTER)
	var prep_result: Dictionary = Decks.validate(Decks.SIDE_PREP, prep)
	var disaster_result: Dictionary = Decks.validate(Decks.SIDE_DISASTER, disaster)
	expect(prep_result.ok, "Preparedness preset passes: " + str(prep_result.errors))
	expect(disaster_result.ok, "Disaster preset passes: " + str(disaster_result.errors))
	check_pools()
	check_prep_failures(prep)
	check_disaster_failures(disaster)
	check_prematch_logic()
	await check_versus_match()
	if failures > 0:
		push_error("versus_smoke: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: versus_smoke (%d checks)" % checks)
	quit(0)

func check_pools() -> void:
	var prep_pool: Dictionary = Decks.pool(Decks.SIDE_PREP)
	var disaster_pool: Dictionary = Decks.pool(Decks.SIDE_DISASTER)
	expect(prep_pool.base.has("supply_cache") and prep_pool.base.has("emergency_exit"), "Prep pool has utilities")
	expect(prep_pool.base.has("quick_dash") and prep_pool.base.has("needle_team"), "Prep pool has json cards")
	expect(disaster_pool.base.has("ember") and disaster_pool.base.has("cinder_cloud"), "Disaster base cards")
	expect(disaster_pool.evolutions.has("wildfire") and disaster_pool.evolutions.has("worldbreaker"), "Evolutions")
	expect(disaster_pool.spells.has("blocked_exit") and disaster_pool.spells.has("red_tape"), "Disaster spells")

# A small fake singleplayer save: version 1 and a collection of 5 cards (the minimum read_save accepts).
func fake_save_text() -> String:
	var collection: Array = []
	for i in 5: collection.append({"id": "quick_dash", "name": "Quick Dash"})
	var data := {"version": 1, "director": {"collection": collection, "floor_number": 2}}
	return JSON.stringify(data)

# Starts a Versus match and checks the start state, then ends it and checks the save and the run state.
func play_versus(game: Node, director: Node, prep_wins: bool, save_path: String, save_text: String) -> void:
	var label := "win" if prep_wins else "loss"
	game.clear_battle()
	director.start_versus_match()
	expect(game.encounter_kind == "versus", "Versus %s: encounter_kind is versus" % label)
	expect(director.encounter == "versus", "Versus %s: director encounter is versus" % label)
	expect(not director.run_active, "Versus %s: run_active is false" % label)
	expect(director.battle_active, "Versus %s: battle is active" % label)
	expect(game.deck.size() == 24 and game.enemy_deck.size() == 24, "Versus %s: decks are not trimmed" % label)
	expect(game.enemy_evolution_deck.size() == 6, "Versus %s: 6 evolutions" % label)
	expect(game.plans.unlocked == ["brace", "coordinate", "medicine"], "Versus %s: preset tactics" % label)
	expect(game.player_run_buffs.is_empty() and game.enemy_run_buffs.is_empty(), "Versus %s: no run buffs" % label)
	game.tension = 5
	expect(game.enemy_action_limit() == 5, "Versus %s: Disaster action limit is the tension" % label)
	game.tension = 8
	expect(game.enemy_action_limit() == 8, "Versus %s: action limit grows with tension" % label)
	director.battle_finished(prep_wins)
	expect(FileAccess.file_exists(save_path), "Versus %s: fake save still exists" % label)
	expect(FileAccess.get_file_as_string(save_path) == save_text, "Versus %s: fake save is unchanged" % label)
	expect(not director.run_active, "Versus %s: run_active is false after the match" % label)
	expect(director.versus_match.winner == ("preparedness" if prep_wins else "disaster"), "Versus %s: winner" % label)

func check_versus_match() -> void:
	var game: Node = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.presentation.automated_choice = 0
	await process_frame
	var director: Node = game.run_director
	expect(not director.persistence.enabled, "Test save path is the disposable one")
	var save_path: String = director.persistence.save_path()
	var save_text := fake_save_text()
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	file.store_string(save_text)
	file.close()
	# Singleplayer state that the match must put back.
	game.plans.unlocked.assign(["brace", "coordinate", "supply"])
	game.player_run_buffs = {"energy": 1}
	game.enemy_run_buffs = {"attack": 2}
	game.player_hp = 17
	director.selected_character = 1
	play_versus(game, director, true, save_path, save_text)
	check_run_state_restored("win", game, director)
	play_versus(game, director, false, save_path, save_text)
	check_run_state_restored("loss", game, director)
	await check_disaster_actions(game, director)
	await check_disaster_choices(game, director)
	await check_evolution_choices(game, director)
	await check_ai_uses_actions(game, director)
	await check_disaster_turn_switch(game, director)
	await check_disaster_panel(game, director)
	await check_disaster_picking(game, director)
	await check_disaster_evolve_picking(game, director)
	await check_disaster_hand_tuck(game, director)
	await check_privacy_logic(game, director)
	await check_privacy_screen_ui(game, director)
	await check_disaster_seat(game, director)
	await check_prematch_flow(game, director)
	await check_flip_screens(game, director)
	game.clear_battle()
	DirAccess.remove_absolute(save_path)
	game.queue_free()
	await process_frame

func check_run_state_restored(label: String, game: Node, director: Node) -> void:
	expect(game.plans.unlocked == ["brace", "coordinate", "supply"], "Versus %s: unlocked restored" % label)
	expect(game.player_run_buffs == {"energy": 1}, "Versus %s: player run buffs restored" % label)
	expect(game.enemy_run_buffs == {"attack": 2}, "Versus %s: enemy run buffs restored" % label)
	expect(game.player_hp == 17, "Versus %s: player_hp restored" % label)
	expect(director.selected_character == 1, "Versus %s: selected_character restored" % label)

func test_base(id: String) -> Dictionary:
	return {"id": id, "name": "Test " + id, "type": "disaster", "element": "fire",
		"cost": 0, "attack": 1, "health": 3, "tension_cost": 1}

# An empty Versus board with the Disaster to move. No match flow runs, so nothing else changes the hand.
func start_disaster_turn(game: Node, director: Node, tension: int) -> void:
	game.clear_battle()
	game.encounter_kind = "versus"
	# A real match sets this from DISASTER_IS_HUMAN. These fixtures choose the Disaster themselves.
	game.disaster_is_human = false
	# These fixtures use the panel. The seat checks switch the seat view on themselves.
	game.disaster_seat_view = false
	director.battle_active = true
	game._set_phase(game.Phase.ENEMY)
	game.tension = tension
	game.disaster_actions.begin_turn()

func reason_of(result: Dictionary) -> String:
	return "ok" if result.ok else str(result.reason)

# Every Disaster action has one place that checks it. Checks the reasons and that a refused action changes nothing.
func check_disaster_actions(game: Node, director: Node) -> void:
	start_disaster_turn(game, director, 5)
	var actions = game.disaster_actions
	var lane: Node3D = game._threat_slots()[0]
	var base := test_base("t_base")
	var evolution := {"id": "t_evo", "name": "Test Evo", "type": "disaster", "element": "fire",
		"cost": 2, "attack": 3, "health": 4}
	var sealed := test_base("t_sealed")
	sealed.locked_until = game.turn + 2
	var seal_spell := {"id": "t_seal", "name": "Test Seal", "type": "disaster", "element": "fire",
		"utility": true, "effect": "seal", "tension_cost": 1}
	game.enemy_hand.assign([base, evolution, sealed, seal_spell])
	expect(actions.action_limit == 5 and actions.actions_left() == 5, "Disaster actions: limit is 5 with 5 tension")
	var stray_slot := Node3D.new()
	var rejected := {
		"not_in_hand": await actions.play_base(test_base("t_other"), lane),
		"sealed": await actions.play_base(sealed, lane),
		"not_base": await actions.play_base(evolution, lane),
		"bad_slot": await actions.play_base(base, stray_slot),
		"bad_target": await actions.cast(seal_spell, null),
		"not_spell": await actions.cast(base, null),
		"not_evolution": await actions.evolve(base, [], lane),
		"bad_sacrifice": await actions.evolve(evolution, [], lane),
	}
	stray_slot.free()
	for reason: String in rejected:
		var got := reason_of(rejected[reason])
		expect(got == reason, "Disaster actions: %s is refused (got %s)" % [reason, got])
	expect(game.enemy_hand.size() == 4 and game.tension == 5 and actions.actions_used == 0,
		"Disaster actions: a refused action changes nothing")
	game._set_phase(game.Phase.PLAYER_PLAY)
	expect(reason_of(await actions.play_base(base, lane)) == "not_disaster_turn",
		"Disaster actions: only on the Disaster turn")
	expect(reason_of(actions.end_turn()) == "not_disaster_turn", "Disaster actions: end_turn only on the Disaster turn")
	game._set_phase(game.Phase.ENEMY)
	game.tension = 0
	expect(reason_of(await actions.play_base(base, lane)) == "no_tension", "Disaster actions: no tension, no action")
	game.tension = 5
	expect(reason_of(await actions.play_base(base, lane)) == "ok", "Disaster actions: base card is played")
	expect(game._get_card_in_slot(lane) != null and base not in game.enemy_hand,
		"Disaster actions: card is on the lane")
	expect(game.tension == 4 and actions.actions_used == 1, "Disaster actions: tension and action count")
	var second := test_base("t_second")
	game.enemy_hand.append(second)
	expect(reason_of(await actions.play_base(second, lane)) == "lane_full", "Disaster actions: a full lane is refused")
	expect(reason_of(await actions.play_base(second, game._threat_slots()[1])) == "ok", "Disaster actions: second lane")
	var one_card: Array = [game._get_card_in_slot(lane)]
	expect(reason_of(await actions.evolve(evolution, one_card, lane)) == "bad_sacrifice",
		"Disaster actions: cost needs 2")
	var two_cards: Array = [game._get_card_in_slot(lane), game._get_card_in_slot(game._threat_slots()[1])]
	expect(reason_of(await actions.evolve(evolution, two_cards, game._threat_slots()[2])) == "bad_slot",
		"Disaster actions: evolve lane must be a sacrificed lane")
	expect(reason_of(await actions.evolve(evolution, two_cards, lane)) == "ok", "Disaster actions: evolve works")
	expect(game._get_card_in_slot(lane).card_data.id == "t_evo", "Disaster actions: evolution is on the lane")
	expect(actions.actions_used == 3 and actions.actions_left() == 3, "Disaster actions: three used, three left")
	# No fixed cap: two more actions fit in the 5 tension the turn started with.
	var fourth := test_base("t_fourth")
	var fifth := test_base("t_fifth")
	game.enemy_hand.append_array([fourth, fifth, base])
	expect(reason_of(await actions.play_base(fourth, game._threat_slots()[1])) == "ok",
		"Disaster actions: a 4th action is allowed")
	expect(reason_of(await actions.play_base(fifth, game._threat_slots()[2])) == "ok",
		"Disaster actions: a 5th action is allowed")
	expect(actions.actions_used == 5 and actions.actions_left() == 1, "Disaster actions: five used, one left")
	expect(reason_of(await actions.play_base(base, game._threat_slots()[3])) == "ok",
		"Disaster actions: the 6th action is allowed after an evolution")
	var seventh := test_base("t_seventh")
	game.enemy_hand.append(seventh)
	expect(reason_of(await actions.play_base(seventh, game._threat_slots()[3])) == "action_limit",
		"Disaster actions: the next play is refused after the allowance is spent")
	expect(reason_of(actions.end_turn()) == "ok", "Disaster actions: end_turn works on the Disaster turn")
	# Seal and tax need a card in the Response hand.
	start_disaster_turn(game, director, 5)
	game.enemy_hand.assign([seal_spell])
	var response_card := {"id": "t_resp", "name": "Test Resp", "type": "response", "element": "evac",
		"cost": 1, "attack": 1, "health": 1}
	game.add_card_to_hand(response_card)
	var target: Node = game.get_hand_cards()[0]
	expect(reason_of(await actions.cast(seal_spell, null)) == "bad_target", "Disaster actions: seal needs a target")
	expect(reason_of(await actions.cast(seal_spell, target)) == "ok", "Disaster actions: seal works")
	expect(game.is_sealed(target.card_data) and game.tension == 4, "Disaster actions: target sealed, tension paid")

func test_spell(id: String, effect: String) -> Dictionary:
	return {"id": id, "name": "Test " + id, "type": "disaster", "element": "fire",
		"utility": true, "effect": effect, "tension_cost": 1}

# The helpers that list legal lanes and targets must agree with what play_base and cast accept.
func check_disaster_choices(game: Node, director: Node) -> void:
	start_disaster_turn(game, director, 5)
	var actions = game.disaster_actions
	var lanes: Array = game._threat_slots()
	var base := test_base("t_choice")
	var first := test_base("t_first")
	var evolution := {"id": "t_evo2", "name": "Test Evo", "type": "disaster", "element": "fire",
		"cost": 2, "attack": 3, "health": 4}
	var seal_spell := test_spell("t_seal2", "seal")
	var tax_spell := test_spell("t_tax2", "tax")
	game.enemy_hand.assign([base, first, evolution, seal_spell, tax_spell])
	expect(actions.legal_lanes(base).size() == 4, "Disaster choices: an empty board offers all 4 lanes")
	expect(reason_of(await actions.play_base(first, lanes[1])) == "ok", "Disaster choices: fill lane 2")
	var offered: Array = actions.legal_lanes(base)
	expect(offered.size() == 3 and lanes[1] not in offered, "Disaster choices: a full lane is not offered")
	var accepted: Array = []
	for lane in lanes:
		var problem: String = actions._base_problem(base, lane)
		if problem.is_empty(): accepted.append(lane)
	expect(accepted == offered, "Disaster choices: offered lanes are the lanes play_base accepts")
	expect(actions.legal_lanes(evolution).is_empty() and not actions.can_use(evolution),
		"Disaster choices: evolution not usable")
	# Spell targets: seal skips a sealed card, tax takes any.
	expect(actions.legal_targets(seal_spell).is_empty() and not actions.can_use(seal_spell),
		"Disaster choices: seal with an empty Response hand is not usable")
	game.add_card_to_hand({"id": "t_r1", "name": "Test R1", "type": "response", "element": "evac",
		"cost": 1, "attack": 1, "health": 1})
	game.add_card_to_hand({"id": "t_r2", "name": "Test R2", "type": "response", "element": "evac",
		"cost": 1, "attack": 1, "health": 1})
	var cards: Array = game.get_hand_cards()
	cards[1].card_data.locked_until = game.turn + 2
	var seal_targets: Array = actions.legal_targets(seal_spell)
	expect(seal_targets == [cards[0]], "Disaster choices: seal offers only the unsealed card")
	expect(actions.legal_targets(tax_spell).size() == 2, "Disaster choices: tax offers every hand card")
	for card in cards:
		var seal_ok: bool = actions._cast_problem(seal_spell, card).is_empty()
		expect(seal_ok == (card in seal_targets), "Disaster choices: seal targets match cast")
	expect(actions.can_use(seal_spell) and actions.can_use(tax_spell) and actions.can_use(base),
		"Disaster choices: usable cards")
	# Cards that must be dimmed.
	var sealed := test_base("t_sealed2")
	sealed.locked_until = game.turn + 2
	game.enemy_hand.append(sealed)
	expect(not actions.can_use(sealed) and actions.card_problem(sealed) == "sealed",
		"Disaster choices: sealed card dimmed")
	var costly := test_base("t_costly")
	costly.tension_cost = 9
	game.enemy_hand.append(costly)
	expect(actions.card_problem(costly) == "no_tension" and not actions.can_use(costly),
		"Disaster choices: too dear dimmed")
	actions.actions_used = actions.action_limit
	expect(actions.card_problem(base) == "action_limit" and not actions.can_use(base),
		"Disaster choices: action limit dims")
	actions.actions_used = 0
	game.tension = 0
	expect(actions.card_problem(base) == "no_tension", "Disaster choices: no tension dims")
	game.clear_battle()

# The helper that lists sacrifices must agree with evolve, and can_use must follow it.
func check_evolution_choices(game: Node, director: Node) -> void:
	start_disaster_turn(game, director, 5)
	var actions = game.disaster_actions
	var lanes: Array = game._threat_slots()
	var evolution := {"id": "t_evo3", "name": "Test Evo", "type": "disaster", "element": "fire",
		"cost": 2, "attack": 3, "health": 4}
	var base := test_base("t_evo_base")
	game.enemy_hand.assign([evolution, base, test_base("t_evo_a"), test_base("t_evo_b")])
	expect(actions.legal_sacrifices(evolution).is_empty() and not actions.can_use(evolution),
		"Disaster evolution: no cards on the board, no sacrifices")
	expect(actions.legal_sacrifices(base).is_empty(), "Disaster evolution: a base has no sacrifices")
	expect(reason_of(await actions.play_base(game.enemy_hand[2], lanes[0])) == "ok", "Disaster evolution: first card")
	var one: Array = actions.legal_sacrifices(evolution)
	expect(one == [game._get_card_in_slot(lanes[0])], "Disaster evolution: one card, one sacrifice")
	expect(not actions.can_use(evolution), "Disaster evolution: one card is too few for cost 2")
	expect(reason_of(await actions.play_base(game.enemy_hand[2], lanes[2])) == "ok", "Disaster evolution: second card")
	var two: Array = actions.legal_sacrifices(evolution)
	expect(two.size() == 2 and actions.can_use(evolution), "Disaster evolution: enough cards, usable")
	for card in two:
		expect(actions._sacrifice_problem([card], card.current_slot).is_empty(),
			"Disaster evolution: offered cards are accepted by evolve")
	var spell := test_spell("t_evo_spell", "seal")
	expect(actions.legal_sacrifices(spell).is_empty(), "Disaster evolution: a spell has no sacrifices")
	game.tension = 0
	expect(not actions.can_use(evolution), "Disaster evolution: no tension, not usable")
	game.clear_battle()

# In Versus the AI turn goes through the same actions and ends the same way as a singleplayer turn.
func check_ai_uses_actions(game: Node, director: Node) -> void:
	start_disaster_turn(game, director, 1)
	game.turn = 3
	game.enemy_deck.clear()
	game.enemy_evolution_deck.clear()
	game.enemy_hand.assign([test_base("t_ai")])
	await game._enemy_turn()
	var placed: Array = game._threat_slots().filter(func(slot): return game._get_card_in_slot(slot) != null)
	expect(placed.size() == 1 and game.enemy_hand.is_empty(), "Versus AI: played its card once through the actions")
	expect(game.tension == 0 and game.disaster_actions.actions_used == 1, "Versus AI: tension and action count")

## Runs one Disaster turn and sets done[0] when it ends.
func run_enemy_turn(game: Node, done: Array) -> void:
	await game._enemy_turn()
	done[0] = true

# A human Disaster turn waits for end_turn(). With the flag off the AI turn plays as before.
func check_disaster_turn_switch(game: Node, director: Node) -> void:
	start_disaster_turn(game, director, 1)
	game.turn = 3
	game.enemy_deck.clear()
	game.enemy_evolution_deck.clear()
	game.enemy_hand.assign([test_base("t_human")])
	game.disaster_is_human = true
	var done := [false]
	run_enemy_turn(game, done)
	# The turn waits 0.5s before it starts listening, so give it longer than that.
	await create_timer(0.8, false).timeout
	expect(not done[0], "Human Disaster turn: waits until end_turn")
	expect(game.enemy_hand.size() == 1 and game.tension == 1, "Human Disaster turn: the AI plays nothing")
	expect(game.disaster_actions.end_turn().ok, "Human Disaster turn: end_turn is accepted")
	await create_timer(0.7, false).timeout
	expect(done[0], "Human Disaster turn: finishes after end_turn")
	game.disaster_is_human = false
	await check_ai_uses_actions(game, director)

# A human Disaster turn with 3 tension, 2 evolutions and one card in hand, waiting for End.
func start_human_turn(game: Node, director: Node, done: Array) -> void:
	start_disaster_turn(game, director, 3)
	game.turn = 3
	game.enemy_deck.clear()
	game.enemy_evolution_deck.assign([test_base("t_evo_a"), test_base("t_evo_b")])
	game.enemy_hand.assign([test_base("t_panel")])
	game.disaster_is_human = true
	done[0] = false
	run_enemy_turn(game, done)

# The Disaster panel only shows on a human Disaster turn. A battle that ends frees a waiting turn.
func check_disaster_panel(game: Node, director: Node) -> void:
	var panel: Control = director.disaster_panel
	# The earlier match results screen may still be open.
	director.modal.visible = false
	start_disaster_turn(game, director, 3)
	await process_frame
	expect(panel != null and not panel.visible, "Disaster panel: hidden when the Disaster is the AI")
	# End with nobody waiting does nothing bad.
	game.enemy_hand.assign([test_base("t_idle")])
	expect(not game.disaster_waiting, "Disaster panel: nobody waits before a human turn")
	expect(game.disaster_actions.end_turn().ok and game.enemy_hand.size() == 1 and game.tension == 3,
		"Disaster panel: end_turn with nobody waiting changes nothing")
	var done := [false]
	start_human_turn(game, director, done)
	await create_timer(0.2, false).timeout
	await process_frame
	expect(panel.visible and panel.get_node("%EndButton").disabled, "Disaster panel: End is off before the turn waits")
	await create_timer(0.6, false).timeout
	await process_frame
	expect(panel.visible and not done[0], "Disaster panel: shown on a human Disaster turn")
	expect(panel.get_node("%Tension").text == "Tension: 3 / %d" % game.tension_cap, "Disaster panel: tension")
	expect(panel.get_node("%Evolutions").text == "Evolutions: 2", "Disaster panel: evolution count")
	expect(panel.get_node("%Actions").text == "Actions left: 3", "Disaster panel: actions left")
	expect(panel.get_node("%HandList").get_child_count() == 1, "Disaster panel: one card in the hand list")
	expect(not panel.get_node("%EndButton").disabled, "Disaster panel: End is on while the turn waits")
	game.clear_battle()
	await create_timer(0.1, false).timeout
	expect(done[0] and game.phase == game.Phase.SETUP, "Disaster panel: clear_battle frees the waiting turn")
	start_human_turn(game, director, done)
	await create_timer(0.8, false).timeout
	expect(not done[0], "Disaster panel: second turn waits")
	game._set_phase(game.Phase.GAME_OVER)
	await create_timer(0.1, false).timeout
	expect(done[0] and game.phase == game.Phase.GAME_OVER, "Disaster panel: a finished battle frees the waiting turn")
	await process_frame
	expect(not panel.visible, "Disaster panel: hidden when the battle is over")
	game.disaster_is_human = false

func hand_rows(director: Node) -> Array:
	return director.disaster_panel.get_node("%HandList").get_children()

# A human Disaster turn waiting for input, with the given hand. Waits longer than the turn's own 0.5 s pause.
func wait_human_turn(game: Node, director: Node, hand: Array) -> Array:
	var done := [false]
	start_human_turn(game, director, done)
	game.enemy_hand.assign(hand)
	await create_timer(0.8, false).timeout
	await process_frame
	# The Disaster player has pressed "I am ready" on the privacy screen.
	director._hide_privacy_screen()
	await process_frame
	return done

# The panel picks a lane or a target, calls the same actions as the AI, and cancels itself when it goes stale.
func check_disaster_picking(game: Node, director: Node) -> void:
	var panel: Control = director.disaster_panel
	var box: Control = panel.get_node("%PickBox")
	director.modal.visible = false
	var base := test_base("t_pick")
	var done := await wait_human_turn(game, director, [base])
	var rows := hand_rows(director)
	expect(rows.size() == 1 and rows[0] is Button and not rows[0].disabled,
		"Disaster picking: a playable base is a button")
	rows[0].pressed.emit()
	await process_frame
	await process_frame
	expect(director.disaster_pick.get("kind", "") == "lane" and box.visible, "Disaster picking: pick mode starts")
	expect(hand_rows(director)[0].disabled, "Disaster picking: hand rows are off while picking")
	var lanes: Array = game._threat_slots()
	expect(not box.get_node("Lane1").disabled and not box.get_node("Lane4").disabled, "Disaster picking: free lanes on")
	# Cancel button, then pick again and play into lane 2.
	box.get_node("CancelPick").pressed.emit()
	await process_frame
	expect(director.disaster_pick.is_empty() and not box.visible, "Disaster picking: Cancel leaves pick mode")
	await process_frame
	hand_rows(director)[0].pressed.emit()
	await process_frame
	await process_frame
	box.get_node("Lane2").pressed.emit()
	await create_timer(1.0, false).timeout
	expect(game._get_card_in_slot(lanes[1]) != null and game.enemy_hand.is_empty(), "Disaster picking: base card played")
	expect(game.disaster_actions.actions_used == 1 and director.disaster_pick.is_empty(),
		"Disaster picking: action counted")
	# End of turn cancels a pick.
	game.enemy_hand.assign([test_base("t_pick2")])
	await process_frame
	await process_frame
	hand_rows(director)[0].pressed.emit()
	await process_frame
	expect(director.disaster_pick.get("kind", "") == "lane", "Disaster picking: pick mode starts again")
	game.disaster_actions.end_turn()
	await process_frame
	await process_frame
	expect(director.disaster_pick.is_empty() and not box.visible, "Disaster picking: cancels on end_turn")
	await create_timer(0.7, false).timeout
	# clear_battle cancels a pick.
	done = await wait_human_turn(game, director, [test_base("t_pick3")])
	hand_rows(director)[0].pressed.emit()
	await process_frame
	expect(director.disaster_pick.get("kind", "") == "lane", "Disaster picking: pick mode for clear_battle")
	game.clear_battle()
	await process_frame
	await process_frame
	expect(director.disaster_pick.is_empty() and not box.visible, "Disaster picking: cancels on clear_battle")
	# A refused action shows its reason and changes nothing.
	done = await wait_human_turn(game, director, [test_base("t_pick4")])
	hand_rows(director)[0].pressed.emit()
	await process_frame
	game.tension = 0
	director._disaster_pick_lane(0)
	await process_frame
	expect(panel.get_node("%Reason").text == "Not enough Tension.", "Disaster picking: a refused action shows its reason")
	expect(game._get_card_in_slot(lanes[0]) == null and game.enemy_hand.size() == 1 and game.tension == 0,
		"Disaster picking: a refused action changes nothing")
	game.disaster_actions.end_turn()
	await create_timer(0.7, false).timeout
	await check_disaster_target_pick(game, director)
	game.disaster_is_human = false

# A fixture match for the privacy screen: Versus, human Disaster, the given phase. No turn code runs.
func privacy_fixture(game: Node, director: Node, phase: int) -> void:
	start_disaster_turn(game, director, 3)
	game.disaster_is_human = true
	game.disaster_waiting = false
	game._set_phase(phase)
	director.modal.visible = false
	await privacy_frames()

func privacy_frames() -> void:
	await process_frame
	await process_frame

# Puts the fixture into the Disaster's wait, or out of it.
func privacy_disaster_wait(game: Node, waiting: bool) -> void:
	game.disaster_waiting = waiting
	game._set_phase(game.Phase.ENEMY if waiting else game.Phase.COMBAT)
	await privacy_frames()

# The cover goes up when the laptop changes hands, and never at the start, in singleplayer or with an AI Disaster.
func check_privacy_logic(game: Node, director: Node) -> void:
	var screen: CanvasLayer = director.privacy_screen
	# The first Preparedness turn needs no hand-over.
	await privacy_fixture(game, director, game.Phase.PLAYER_PLAY)
	expect(not screen.visible, "Privacy: not raised at match start")
	# Preparedness ends its turn, the Disaster waits.
	await privacy_disaster_wait(game, true)
	expect(screen.visible and director.privacy_side == "disaster", "Privacy: raised when the Disaster wait starts")
	director._hide_privacy_screen()
	await privacy_frames()
	expect(not screen.visible, "Privacy: stays down once closed")
	# The Disaster ends its turn, Preparedness plays again.
	await privacy_disaster_wait(game, false)
	expect(not screen.visible, "Privacy: not raised during combat")
	game._set_phase(game.Phase.PLAYER_PLAY)
	await privacy_frames()
	expect(screen.visible and director.privacy_side == "prep", "Privacy: raised when the Preparedness turn starts")
	director._hide_privacy_screen()
	# The Disaster plays twice in a row (it moved first next round): same player, no hand-over.
	await privacy_disaster_wait(game, true)
	director._hide_privacy_screen()
	await privacy_disaster_wait(game, false)
	await privacy_disaster_wait(game, true)
	expect(not screen.visible, "Privacy: not raised when the same side plays again")
	# Cleared by clear_battle, and by game over.
	await privacy_disaster_wait(game, false)
	game._set_phase(game.Phase.PLAYER_PLAY)
	await privacy_frames()
	expect(screen.visible, "Privacy: raised again before clearing")
	game.clear_battle()
	await privacy_frames()
	expect(not screen.visible, "Privacy: cleared by clear_battle")
	await privacy_fixture(game, director, game.Phase.PLAYER_PLAY)
	await privacy_disaster_wait(game, true)
	expect(screen.visible, "Privacy: raised before game over")
	game.disaster_waiting = false
	game._set_phase(game.Phase.GAME_OVER)
	await privacy_frames()
	expect(not screen.visible, "Privacy: cleared by game over")
	# The Disaster moves first in a new match: the cover goes up.
	await privacy_fixture(game, director, game.Phase.SETUP)
	await privacy_disaster_wait(game, true)
	expect(screen.visible and director.privacy_side == "disaster", "Privacy: Disaster-first match is covered")
	# The battle ends: no cover on the result screen.
	director.battle_active = false
	await privacy_frames()
	expect(not screen.visible, "Privacy: cleared when the battle ends")
	# An open modal blocks a new cover.
	await privacy_fixture(game, director, game.Phase.PLAYER_PLAY)
	director.modal.visible = true
	await privacy_disaster_wait(game, true)
	expect(not screen.visible, "Privacy: not raised under a modal")
	director.modal.visible = false
	# An AI Disaster and singleplayer never raise it.
	await privacy_fixture(game, director, game.Phase.PLAYER_PLAY)
	game.disaster_is_human = false
	await privacy_disaster_wait(game, true)
	game._set_phase(game.Phase.PLAYER_PLAY)
	await privacy_frames()
	expect(not screen.visible, "Privacy: not raised with an AI Disaster")
	await privacy_fixture(game, director, game.Phase.PLAYER_PLAY)
	game.encounter_kind = "battle"
	await privacy_disaster_wait(game, true)
	game._set_phase(game.Phase.PLAYER_PLAY)
	await privacy_frames()
	expect(not screen.visible, "Privacy: not raised in singleplayer")
	game.disaster_waiting = false
	game.disaster_is_human = false
	game.clear_battle()

func privacy_key(keycode: int) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = keycode
	key.pressed = true
	return key

# A left click at a point, sent through the real GUI input path.
func privacy_click(point: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = point
	move.global_position = point
	root.push_input(move, true)
	await privacy_frames()
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = point
		click.global_position = point
		click.pressed = pressed
		root.push_input(click, true)
	await privacy_frames()

# The scene itself: texts, layer, mouse and key blocking, and the real "I am ready" button.
func check_privacy_screen_ui(game: Node, director: Node) -> void:
	var screen: CanvasLayer = director.privacy_screen
	var ready_button: Button = screen.get_node("%ReadyButton")
	var cover: Control = screen.get_node("Cover")
	expect(screen.layer == 30 and screen.layer > game.presentation.layer and screen.layer > director.layer,
		"Privacy UI: its own layer above the coin screen, banners and the director")
	expect(cover.mouse_filter == Control.MOUSE_FILTER_STOP, "Privacy UI: the cover stops the mouse")
	expect(screen.get_node("Cover/Box/Title").text == "PASS THE LAPTOP", "Privacy UI: heading")
	expect(ready_button.text == "I am ready", "Privacy UI: button text")
	# Preparedness hands over to the Disaster.
	await privacy_fixture(game, director, game.Phase.PLAYER_PLAY)
	await privacy_disaster_wait(game, true)
	expect(screen.visible and screen.get_node("%SideLine").text == "DISASTER, it is your turn",
		"Privacy UI: Disaster line")
	expect(ready_button.has_focus(), "Privacy UI: the button has focus, so Enter and Space work")
	# Esc and other keys do nothing while it is up.
	director._input(privacy_key(KEY_ESCAPE))
	director._input(privacy_key(KEY_P))
	director._input(privacy_key(KEY_D))
	await privacy_frames()
	expect(screen.visible and not director.modal.visible, "Privacy UI: Esc and hotkeys do nothing")
	# A click on the End button under the cover does nothing.
	var ends := [0]
	var count_end := func(): ends[0] += 1
	game.disaster_actions.turn_ended.connect(count_end)
	var end_button: Button = director.disaster_panel.get_node("%EndButton")
	await privacy_click(end_button.get_global_rect().get_center())
	expect(ends[0] == 0 and screen.visible, "Privacy UI: a click under the cover is blocked")
	# The real button closes it, and the Disaster panel works.
	ready_button.pressed.emit()
	await privacy_frames()
	expect(not screen.visible, "Privacy UI: the button closes the cover")
	expect(director.disaster_panel.visible and not end_button.disabled, "Privacy UI: the Disaster panel is usable")
	await privacy_click(end_button.get_global_rect().get_center())
	expect(ends[0] == 1, "Privacy UI: the same click works once the cover is closed")
	game.disaster_actions.turn_ended.disconnect(count_end)
	# The Disaster hands back to Preparedness: Enter closes it, the hand comes back.
	await privacy_disaster_wait(game, false)
	game._set_phase(game.Phase.PLAYER_PLAY)
	await privacy_frames()
	expect(screen.visible and screen.get_node("%SideLine").text == "PREPAREDNESS, it is your turn",
		"Privacy UI: Preparedness line")
	director._input(privacy_key(KEY_ENTER))
	await create_timer(0.5, false).timeout
	expect(not screen.visible, "Privacy UI: Enter closes the cover")
	expect(not game.is_hand_tucked and not director.privacy_screen.visible, "Privacy UI: the hand is back")
	# Space closes it too, and nothing else happens.
	await privacy_disaster_wait(game, true)
	expect(screen.visible, "Privacy UI: raised once more")
	director._input(privacy_key(KEY_SPACE))
	await privacy_frames()
	expect(not screen.visible and game.phase == game.Phase.ENEMY, "Privacy UI: Space closes it without ending a turn")
	game.disaster_waiting = false
	game.clear_battle()

# A mouse move, press or release at a point, pushed through the real input path.
func seat_mouse(point: Vector2, kind: String) -> void:
	if kind == "move":
		var move := InputEventMouseMotion.new()
		move.position = point
		move.global_position = point
		root.push_input(move, true)
	else:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = kind == "down"
		button.position = point
		button.global_position = point
		root.push_input(button, true)
	await process_frame

# The centre of a seat card where it rests, and of a threat lane, on screen.
func seat_card_point(game: Node, index: int) -> Vector2:
	var seat: Node = game.disaster_seat
	var card: Node3D = seat.cards[index]
	return game.camera.unproject_position(seat.seat_hand.global_transform * card.get_meta("seat_pos"))

func seat_lane_point(game: Node, lane: int) -> Vector2:
	return game.camera.unproject_position(game._threat_slots()[lane].global_position)

func seat_popups(game: Node) -> Array:
	var texts := []
	for child in game.get_children():
		if child is Label3D: texts.append(child.text)
	return texts

# A human Disaster turn with the seat view on and the given hand.
func seat_turn(game: Node, director: Node, hand: Array) -> Array:
	director.modal.visible = false
	var done := await wait_human_turn(game, director, hand)
	game.disaster_seat_view = true
	await create_timer(0.6, false).timeout
	return done

# The Disaster seat: the camera flips, real cards show, a Base card is played by drag or by two clicks.
func check_disaster_seat(game: Node, director: Node) -> void:
	var seat: Node = game.disaster_seat
	var view_before: int = game.view_mode
	var done := await seat_turn(game, director, [test_base("t_seat")])
	expect(game.disaster_seat_on and seat.active, "Disaster seat: on for a human Disaster turn")
	expect(game.camera.global_position.z < -3.0, "Disaster seat: the camera is on the far side of the table")
	expect(not director.disaster_panel.visible, "Disaster seat: the panel is hidden")
	expect(not game.opponent_hand.visible, "Disaster seat: the Janitor is hidden")
	expect(game._view_forward_btn.disabled and game._view_back_btn.disabled, "Disaster seat: view buttons are off")
	game.set_view(game.View.BOARD)
	expect(game.view_mode == view_before, "Disaster seat: the view cannot change on this turn")
	expect(seat.cards.size() == 1 and seat.cards[0].card_data.get("id", "") == "t_seat",
		"Disaster seat: the hand is a real card")
	expect(not game._end_turn_btn.disabled, "Disaster seat: End turn is on")
	expect(seat.cards[0].get_meta("seat_pos").y <= game.HAND_Y - 0.25, "Disaster seat: the hand sits below the lanes")
	expect(not director.prep.get_parent().visible and not director.graveyard_button.visible,
		"Disaster seat: no Preparedness gauge or Graveyard button")
	var visible_area: Rect2 = root.get_visible_rect()
	var card_point := seat_card_point(game, 0)
	var lane_point := seat_lane_point(game, 1)
	expect(visible_area.has_point(card_point) and visible_area.has_point(lane_point),
		"Disaster seat: the card and the lane are on screen")
	# Drag the card onto lane 2 with the mouse.
	await seat_mouse(card_point, "move")
	await seat_mouse(card_point, "down")
	await seat_mouse(lane_point, "move")
	await seat_mouse(lane_point, "move")
	expect(seat.dragging and game._threat_slots()[1].visible, "Disaster seat: dragging lights the open lanes")
	await seat_mouse(lane_point, "up")
	await create_timer(1.2, false).timeout
	expect(game._get_card_in_slot(game._threat_slots()[1]) != null and game.enemy_hand.is_empty(),
		"Disaster seat: a Base card dragged onto a lane is played")
	expect(game.disaster_actions.actions_used == 1 and seat.cards.is_empty(),
		"Disaster seat: action counted, hand shown empty")
	expect(not game._threat_slots()[1].visible, "Disaster seat: lanes stop glowing")
	var landed: Node3D = game._get_card_in_slot(game._threat_slots()[1])
	expect(landed != null and absf(absf(landed.rotation.y) - PI) < 0.05,
		"Disaster seat: the board card is turned upright")
	# The normal End turn button ends the turn and the camera flips back.
	var end_point: Vector2 = game._end_turn_btn.get_global_rect().get_center()
	await privacy_click(end_point)
	await create_timer(1.0, false).timeout
	expect(done[0] and not game.disaster_waiting, "Disaster seat: the End turn button ends the turn")
	expect(not game.disaster_seat_on and game.camera.global_position.z > 3.0, "Disaster seat: the camera flips back")
	expect(game.opponent_hand.visible and game.view_mode == view_before, "Disaster seat: Janitor and view are back")
	expect(not game._view_forward_btn.disabled or view_before == game.View.WIDE, "Disaster seat: view buttons are back")
	await create_timer(0.3, false).timeout
	var all_back := true
	for card: Node in get_nodes_in_group("cards"):
		if not is_instance_valid(card) or card.in_hand or card.current_slot == null: continue
		if absf(card.rotation.y) >= 0.05: all_back = false
	expect(all_back, "Disaster seat: board cards turn back when the seat closes")
	expect(director.prep.get_parent().visible and director.graveyard_button.visible,
		"Disaster seat: Preparedness gauge and Graveyard button are back")
	await check_disaster_seat_click(game, director)
	await check_disaster_seat_refusals(game, director)
	game.disaster_seat_view = false
	game.disaster_is_human = false
	game.clear_battle()

# Click a card, then click a lane.
func check_disaster_seat_click(game: Node, director: Node) -> void:
	var seat: Node = game.disaster_seat
	await seat_turn(game, director, [test_base("t_click")])
	var card_point := seat_card_point(game, 0)
	await seat_mouse(card_point, "move")
	await seat_mouse(card_point, "down")
	await seat_mouse(card_point, "up")
	expect(seat.selected == seat.cards[0] and game.enemy_hand.size() == 1, "Disaster seat: a click picks the card")
	var lane_point := seat_lane_point(game, 2)
	expect(seat.selected != null and game._threat_slots()[2].visible, "Disaster seat: a picked card lights the lanes")
	await seat_mouse(lane_point, "move")
	await seat_mouse(lane_point, "down")
	await seat_mouse(lane_point, "up")
	await create_timer(1.2, false).timeout
	expect(game._get_card_in_slot(game._threat_slots()[2]) != null and game.enemy_hand.is_empty(),
		"Disaster seat: a click on a lane plays the picked card")
	game.disaster_actions.end_turn()
	await create_timer(1.0, false).timeout

# A full lane and a spell are refused, the card stays in the hand and a note floats up.
func check_disaster_seat_refusals(game: Node, director: Node) -> void:
	var seat: Node = game.disaster_seat
	await seat_turn(game, director, [test_base("t_full_a"), test_base("t_full_b")])
	await game.disaster_actions.play_base(game.enemy_hand[0], game._threat_slots()[0])
	await create_timer(0.8, false).timeout
	var card_point := seat_card_point(game, 0)
	var lane_point := seat_lane_point(game, 0)
	await seat_mouse(card_point, "move")
	await seat_mouse(card_point, "down")
	await seat_mouse(lane_point, "move")
	await seat_mouse(lane_point, "move")
	await seat_mouse(lane_point, "up")
	await process_frame
	expect(game.enemy_hand.size() == 1 and seat.cards.size() == 1 and seat.cards[0].visible,
		"Disaster seat: a full lane keeps the card in the hand")
	expect("That lane is full." in seat_popups(game), "Disaster seat: the refusal shows its reason")
	expect(game.disaster_actions.actions_used == 1, "Disaster seat: a refused drop costs no action")
	# A spell that needs a Response target is refused when there is none.
	game.enemy_hand.assign([test_spell("t_seat_spell", "tax")])
	await create_timer(0.6, false).timeout
	card_point = seat_card_point(game, 0)
	lane_point = seat_lane_point(game, 2)
	await seat_mouse(card_point, "move")
	await seat_mouse(card_point, "down")
	await seat_mouse(lane_point, "move")
	await seat_mouse(lane_point, "move")
	await seat_mouse(lane_point, "up")
	await process_frame
	expect(game.enemy_hand.size() == 1 and "That target is not allowed." in seat_popups(game),
		"Disaster seat: a spell with no target is refused")
	# Singleplayer and the AI never use the seat, even with the flag on.
	game.encounter_kind = "battle"
	await create_timer(0.3, false).timeout
	expect(not game.disaster_seat_on and game.camera.global_position.z > 3.0, "Disaster seat: not used in singleplayer")
	game.encounter_kind = "versus"
	game.disaster_actions.end_turn()
	await create_timer(1.0, false).timeout
	await check_disaster_seat_spells(game, director)

# Drag a spell onto the board, or click it and then a lane. A spell with a target opens the popup first.
func check_disaster_seat_spells(game: Node, director: Node) -> void:
	var seat: Node = game.disaster_seat
	# A spell with no target, by drag onto the board. It costs tension and one action.
	await seat_turn(game, director, [test_spell("t_seat_plain", "none")])
	var card_point := seat_card_point(game, 0)
	var lane_point := seat_lane_point(game, 3)
	await seat_mouse(card_point, "move")
	await seat_mouse(card_point, "down")
	await seat_mouse(lane_point, "move")
	await seat_mouse(lane_point, "move")
	expect(seat.dragging and not game._threat_slots()[3].visible, "Disaster seat: a spell does not light the lanes")
	await seat_mouse(lane_point, "up")
	await create_timer(0.8, false).timeout
	expect(game.enemy_hand.is_empty() and game.tension == 2 and game.disaster_actions.actions_used == 1,
		"Disaster seat: a spell dragged onto the board is cast, with tension and the action counted")
	# A spell with no target, by two clicks.
	game.enemy_hand.assign([test_spell("t_seat_click", "none")])
	await create_timer(0.6, false).timeout
	card_point = seat_card_point(game, 0)
	await seat_mouse(card_point, "move")
	await seat_mouse(card_point, "down")
	await seat_mouse(card_point, "up")
	expect(seat.selected == seat.cards[0] and game.enemy_hand.size() == 1, "Disaster seat: a click picks the spell")
	await seat_mouse(lane_point, "move")
	await seat_mouse(lane_point, "down")
	await seat_mouse(lane_point, "up")
	await create_timer(0.8, false).timeout
	expect(game.enemy_hand.is_empty() and game.disaster_actions.actions_used == 2,
		"Disaster seat: click then click casts the spell")
	# No tension left: the spell is refused with the panel's text and costs nothing.
	game.tension = 0
	game.enemy_hand.assign([test_spell("t_seat_poor", "none")])
	await create_timer(0.6, false).timeout
	card_point = seat_card_point(game, 0)
	await seat_mouse(card_point, "move")
	await seat_mouse(card_point, "down")
	await seat_mouse(lane_point, "move")
	await seat_mouse(lane_point, "move")
	await seat_mouse(lane_point, "up")
	await process_frame
	expect(game.enemy_hand.size() == 1 and "Not enough Tension." in seat_popups(game)
		and game.disaster_actions.actions_used == 2, "Disaster seat: a spell without tension is refused")
	game.tension = 3
	# A spell with a target: the drop opens the popup, Cancel changes nothing.
	game.add_card_to_hand({"id": "t_seat_r", "name": "Test SeatR", "type": "response", "element": "evac",
		"cost": 1, "attack": 1, "health": 1})
	game.enemy_hand.assign([test_spell("t_seat_seal", "seal")])
	await create_timer(0.6, false).timeout
	var target: Node = game.get_hand_cards()[0]
	card_point = seat_card_point(game, 0)
	await seat_mouse(card_point, "move")
	await seat_mouse(card_point, "down")
	await seat_mouse(lane_point, "move")
	await seat_mouse(lane_point, "move")
	await seat_mouse(lane_point, "up")
	await process_frame
	await process_frame
	expect(director.disaster_pick.get("kind", "") == "target" and director.modal.visible,
		"Disaster seat: a spell with a target opens the target popup")
	director.action_cancel.call()
	await process_frame
	expect(director.disaster_pick.is_empty() and not director.modal.visible and game.enemy_hand.size() == 1
		and game.disaster_actions.actions_used == 2, "Disaster seat: Cancel in the popup changes nothing")
	# Again, and press the real Choose button.
	await seat_mouse(card_point, "move")
	await seat_mouse(card_point, "down")
	await seat_mouse(card_point, "up")
	await seat_mouse(lane_point, "move")
	await seat_mouse(lane_point, "down")
	await seat_mouse(lane_point, "up")
	await process_frame
	await process_frame
	var tiles: Array = director.content.get_node("Cards/Row").get_children()
	expect(tiles.size() == 1 and director.modal.visible, "Disaster seat: the popup lists the Response hand card")
	tiles[0].get_node("Box/ActionButton").pressed.emit()
	await create_timer(0.8, false).timeout
	expect(game.is_sealed(target.card_data) and game.enemy_hand.is_empty() and game.disaster_actions.actions_used == 3,
		"Disaster seat: the chosen target is sealed and the action is counted")
	expect(not director.modal.visible, "Disaster seat: the popup closes after the cast")
	game.disaster_actions.end_turn()
	await create_timer(1.0, false).timeout
	await check_disaster_seat_cancels(game, director)
	await check_disaster_seat_evolve(game, director)
	game.disaster_seat_view = false
	game.disaster_is_human = false
	game.clear_battle()

func seat_escape() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	root.push_input(key, true)
	await process_frame

# True when no threat lane glows and the first seat card is back at its place in the hand.
func seat_at_rest(game: Node) -> bool:
	var seat: Node = game.disaster_seat
	for lane in game._threat_slots():
		if lane.visible: return false
	var card: Node3D = seat.cards[0]
	return card.visible and card.position.distance_to(card.get_meta("seat_pos")) < 0.05

# Click-pick a card, then a click on a lane must not play it.
func seat_click_lane_plays_nothing(game: Node, label: String) -> void:
	var lane_point := seat_lane_point(game, 1)
	await seat_mouse(lane_point, "move")
	await seat_mouse(lane_point, "down")
	await seat_mouse(lane_point, "up")
	await create_timer(0.6, false).timeout
	expect(game.enemy_hand.size() == 1 and game.disaster_actions.actions_used == 0, label)

# Esc, right click, a modal and the popup's Cancel button all put a picked or dragged card back.
func check_disaster_seat_cancels(game: Node, director: Node) -> void:
	var seat: Node = game.disaster_seat
	# Click-pick, then Esc: the card drops back and the menu stays shut.
	await seat_turn(game, director, [test_base("t_esc_a")])
	var card_point := seat_card_point(game, 0)
	await seat_mouse(card_point, "move")
	await seat_mouse(card_point, "down")
	await seat_mouse(card_point, "up")
	expect(seat.selected == seat.cards[0], "Disaster seat cancel: a click picks the card")
	await seat_escape()
	await seat_mouse(Vector2(20, 20), "move")
	await create_timer(0.6, false).timeout
	expect(seat.selected == null and seat_at_rest(game) and not director.modal.visible,
		"Disaster seat cancel: Esc drops the picked card and does not open the menu")
	await seat_click_lane_plays_nothing(game, "Disaster seat cancel: a lane click after Esc plays nothing")
	await seat_escape()
	await process_frame
	expect(director.modal.visible and director.screen == "menu",
		"Disaster seat cancel: Esc with nothing picked opens the menu")
	director.close_modal()
	# Click-pick, then a right click.
	card_point = seat_card_point(game, 0)
	await seat_mouse(card_point, "move")
	await seat_mouse(card_point, "down")
	await seat_mouse(card_point, "up")
	expect(seat.selected == seat.cards[0], "Disaster seat cancel: a click picks the card again")
	await seat_mouse(card_point, "move")
	await seat_right_click(card_point)
	await seat_mouse(Vector2(20, 20), "move")
	await create_timer(0.6, false).timeout
	expect(seat.selected == null and seat_at_rest(game), "Disaster seat cancel: a right click drops the picked card")
	await seat_click_lane_plays_nothing(game, "Disaster seat cancel: a lane click after a right click plays nothing")
	var lane_point := seat_lane_point(game, 1)
	game.disaster_actions.end_turn()
	await create_timer(1.0, false).timeout
	# A spell with a target: the real Cancel button of the popup casts nothing.
	await seat_turn(game, director, [test_spell("t_esc_seal", "seal")])
	game.tension = 3
	game.add_card_to_hand({"id": "t_esc_r", "name": "Test EscR", "type": "response", "element": "evac",
		"cost": 1, "attack": 1, "health": 1})
	await create_timer(0.6, false).timeout
	card_point = seat_card_point(game, 0)
	await seat_mouse(card_point, "move")
	await seat_mouse(card_point, "down")
	await seat_mouse(lane_point, "move")
	await seat_mouse(lane_point, "move")
	await seat_mouse(lane_point, "up")
	await process_frame
	await process_frame
	expect(director.disaster_pick.get("kind", "") == "target" and director.modal.visible,
		"Disaster seat cancel: the target popup opens")
	director.content.get_node("CancelButton").pressed.emit()
	await create_timer(0.6, false).timeout
	expect(not director.modal.visible and director.disaster_pick.is_empty() and game.enemy_hand.size() == 1
		and game.disaster_actions.actions_used == 0 and game.tension == 3 and seat.cards.size() == 1,
		"Disaster seat cancel: the popup's Cancel button casts nothing and the spell stays in the hand")
	game.disaster_actions.end_turn()
	await create_timer(1.0, false).timeout

func test_evo(id: String, cost: int) -> Dictionary:
	return {"id": id, "name": "Test " + id, "type": "disaster", "element": "fire",
		"cost": cost, "attack": 3, "health": 4}

func seat_right_click(point: Vector2) -> void:
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_RIGHT
	button.pressed = true
	button.position = point
	button.global_position = point
	root.push_input(button, true)
	await process_frame

# Waits until the action counter reaches a number, at most 8 seconds.
func wait_for_actions(game: Node, count: int) -> void:
	var waited := 0.0
	while game.disaster_actions.actions_used < count and waited < 8.0:
		await create_timer(0.1, false).timeout
		waited += 0.1
	await create_timer(0.4, false).timeout

# A seat turn with Base cards already on the first lanes and one evolution left in the hand.
func seat_evo_turn(game: Node, director: Node, base_count: int, evolution: Dictionary) -> void:
	var hand: Array = []
	for i in base_count: hand.append(test_base("t_evb%d" % i))
	hand.append(evolution)
	await seat_turn(game, director, hand)
	for i in base_count:
		await game.disaster_actions.play_base(game.enemy_hand[0], game._threat_slots()[i])
	await create_timer(0.8, false).timeout
	game.tension = 5
	game.disaster_actions.action_limit = 5

# Drag the first seat card onto a lane and let go.
func seat_drag_to_lane(game: Node, lane: int) -> void:
	var card_point := seat_card_point(game, 0)
	var lane_point := seat_lane_point(game, lane)
	await seat_mouse(card_point, "move")
	await seat_mouse(card_point, "down")
	await seat_mouse(lane_point, "move")
	await seat_mouse(lane_point, "move")
	await seat_mouse(lane_point, "up")
	await process_frame

# Evolutions in the seat: cost 1 at once, cost 2 asks for another card, cancel and refusals change nothing.
func check_disaster_seat_evolve(game: Node, director: Node) -> void:
	var seat: Node = game.disaster_seat
	var lanes: Array = game._threat_slots()
	# Cost 1: dropped on a lane with a Base card, the Base card is the sacrifice.
	await seat_evo_turn(game, director, 1, test_evo("t_evo1", 1))
	var old_card: Node = game._get_card_in_slot(lanes[0])
	var used_before: int = game.disaster_actions.actions_used
	await seat_drag_to_lane(game, 0)
	await wait_for_actions(game, used_before + 1)
	var landed: Node = game._get_card_in_slot(lanes[0])
	expect(landed != null and landed.card_data.get("id", "") == "t_evo1" and not is_instance_valid(old_card),
		"Disaster seat evolve: cost 1 replaces the card on the dropped lane")
	expect(game.disaster_actions.actions_used == used_before + 1 and game.enemy_hand.is_empty() and seat.evo.is_empty(),
		"Disaster seat evolve: cost 1 counts one action and needs no pick")
	expect(landed != null and absf(absf(landed.rotation.y) - PI) < 0.05,
		"Disaster seat evolve: the evolved card is turned upright")
	game.disaster_actions.end_turn()
	await create_timer(1.0, false).timeout
	# Cost 2: the drop starts the pick, a click on the second card finishes it.
	await seat_evo_turn(game, director, 2, test_evo("t_evo2", 2))
	var first: Node = game._get_card_in_slot(lanes[1])
	var second: Node = game._get_card_in_slot(lanes[0])
	used_before = game.disaster_actions.actions_used
	await seat_drag_to_lane(game, 1)
	await process_frame
	expect(not seat.evo.is_empty() and game.enemy_hand.size() == 1 and used_before == game.disaster_actions.actions_used,
		"Disaster seat evolve: cost 2 waits for a second card")
	expect(lanes[0].visible and not lanes[1].visible, "Disaster seat evolve: only the other card's lane glows")
	expect("Pick 1 more card to sacrifice" in seat_popups(game), "Disaster seat evolve: the pick shows its prompt")
	var lane_point := seat_lane_point(game, 0)
	await seat_mouse(lane_point, "move")
	await seat_mouse(lane_point, "down")
	await seat_mouse(lane_point, "up")
	await wait_for_actions(game, used_before + 1)
	landed = game._get_card_in_slot(lanes[1])
	expect(landed != null and landed.card_data.get("id", "") == "t_evo2" and game._get_card_in_slot(lanes[0]) == null
		and not is_instance_valid(first) and not is_instance_valid(second),
		"Disaster seat evolve: cost 2 lands on the dropped lane and both sacrifices are gone")
	expect(seat.evo.is_empty() and game.disaster_actions.actions_used == used_before + 1,
		"Disaster seat evolve: the pick ends and one action is counted")
	game.disaster_actions.end_turn()
	await create_timer(1.0, false).timeout
	# Cancel with a right click: nothing changes, the card is back in the hand.
	await seat_evo_turn(game, director, 2, test_evo("t_evo2c", 2))
	used_before = game.disaster_actions.actions_used
	await seat_drag_to_lane(game, 1)
	expect(not seat.evo.is_empty(), "Disaster seat evolve: the pick is on before the cancel")
	await seat_right_click(seat_lane_point(game, 3))
	await process_frame
	expect(seat.evo.is_empty() and seat.cards.size() == 1 and seat.cards[0].visible and game.enemy_hand.size() == 1,
		"Disaster seat evolve: a right click gives the card back")
	expect(game._get_card_in_slot(lanes[0]) != null and game._get_card_in_slot(lanes[1]) != null
		and game.disaster_actions.actions_used == used_before and not lanes[0].visible,
		"Disaster seat evolve: a cancel changes nothing and clears the glow")
	# A pick is cleared by End turn, glow too.
	await seat_drag_to_lane(game, 1)
	expect(not seat.evo.is_empty(), "Disaster seat evolve: the pick is on before End turn")
	await privacy_click(game._end_turn_btn.get_global_rect().get_center())
	await create_timer(1.0, false).timeout
	var any_lit := false
	for lane: Node3D in lanes:
		if lane.visible: any_lit = true
	expect(seat.evo.is_empty() and not any_lit, "Disaster seat evolve: End turn clears the pick and the glow")
	# Too few threat cards: refused with the panel's text, no pick.
	await seat_evo_turn(game, director, 1, test_evo("t_evo2r", 2))
	used_before = game.disaster_actions.actions_used
	await seat_drag_to_lane(game, 0)
	expect(seat.evo.is_empty() and game.enemy_hand.size() == 1 and seat.cards[0].visible
		and "Pick different threat cards to sacrifice." in seat_popups(game)
		and game.disaster_actions.actions_used == used_before,
		"Disaster seat evolve: too few threat cards is refused without a pick")
	game.disaster_actions.end_turn()
	await create_timer(1.0, false).timeout

# The Response hand is tucked away while a human Disaster waits, and comes back on every way out.
func check_disaster_hand_tuck(game: Node, director: Node) -> void:
	director.modal.visible = false
	game.in_board_view = false
	await wait_human_turn(game, director, [test_base("t_tuck")])
	await create_timer(0.2, false).timeout
	expect(game.disaster_waiting and game.is_hand_tucked, "Disaster tuck: hand is tucked while the Disaster waits")
	game.disaster_actions.end_turn()
	await create_timer(1.0, false).timeout
	expect(not game.disaster_waiting and not game.is_hand_tucked, "Disaster tuck: hand is back after end_turn")
	# The battle is cleared mid-turn.
	await wait_human_turn(game, director, [test_base("t_tuck2")])
	await create_timer(0.2, false).timeout
	expect(game.is_hand_tucked, "Disaster tuck: tucked again on the next human turn")
	game.clear_battle()
	await create_timer(0.3, false).timeout
	expect(not game.is_hand_tucked, "Disaster tuck: hand is back after clear_battle")
	# The battle ends (game over) mid-turn.
	await wait_human_turn(game, director, [test_base("t_tuck3")])
	await create_timer(0.2, false).timeout
	expect(game.is_hand_tucked, "Disaster tuck: tucked before game over")
	game._set_phase(game.Phase.GAME_OVER)
	await create_timer(0.3, false).timeout
	expect(not game.is_hand_tucked, "Disaster tuck: hand is back after game over")
	# An AI Disaster and singleplayer never tuck for this reason, even if a wait flag were set.
	game.clear_battle()
	start_disaster_turn(game, director, 3)
	game.disaster_is_human = false
	game.disaster_waiting = true
	await create_timer(0.2, false).timeout
	expect(not game.is_hand_tucked, "Disaster tuck: an AI Disaster does not tuck")
	game.disaster_is_human = true
	game.encounter_kind = "battle"
	await create_timer(0.2, false).timeout
	expect(not game.is_hand_tucked, "Disaster tuck: singleplayer does not tuck")
	game.disaster_waiting = false
	game.disaster_is_human = false
	game.clear_battle()

# A human turn with base cards already on the first lanes and only the evolution in hand.
func evolve_turn(game: Node, director: Node, evolution: Dictionary, lane_count: int) -> void:
	await wait_human_turn(game, director, [test_base("t_sac_0"), test_base("t_sac_1")])
	var actions = game.disaster_actions
	for i in lane_count:
		await actions.play_base(game.enemy_hand[0], game._threat_slots()[i])
	actions.actions_used = 0
	game.tension = 5
	game.enemy_hand.assign([evolution])
	await process_frame
	await process_frame

func press_lane(director: Node, number: int) -> void:
	director.disaster_panel.get_node("%PickBox").get_node("Lane%d" % number).pressed.emit()
	await process_frame
	await process_frame

# Evolving from the panel: pick the sacrifices, then the lane, through the real buttons.
func check_disaster_evolve_picking(game: Node, director: Node) -> void:
	var panel: Control = director.disaster_panel
	var box: Control = panel.get_node("%PickBox")
	var lanes: Array = game._threat_slots()
	var evolution := {"id": "t_evo4", "name": "Test Evo", "type": "disaster", "element": "fire",
		"cost": 2, "attack": 3, "health": 4}
	# Too few cards: the row is dimmed.
	await evolve_turn(game, director, evolution, 1)
	expect(hand_rows(director)[0].disabled, "Disaster evolve: row is off with too few sacrifices")
	game.disaster_actions.end_turn()
	await create_timer(0.7, false).timeout
	# Cancel at step 1.
	await evolve_turn(game, director, evolution, 2)
	expect(not hand_rows(director)[0].disabled, "Disaster evolve: row is on with enough sacrifices")
	hand_rows(director)[0].pressed.emit()
	await process_frame
	await process_frame
	expect(director.disaster_pick.get("kind", "") == "sacrifice" and box.visible, "Disaster evolve: sacrifice pick starts")
	expect(not panel.get_node("%HandList").visible, "Disaster evolve: hand is hidden while picking")
	expect(not box.get_node("Lane1").disabled and not box.get_node("Lane2").disabled
		and box.get_node("Lane3").disabled and box.get_node("Lane4").disabled, "Disaster evolve: only card lanes on")
	expect(box.get_node("Lane1").text == "Test t_sac_0" and box.get_node("Lane3").text == "Lane 3",
		"Disaster evolve: sacrifice buttons show the card name")
	expect(box.get_node("Prompt").text == "Sacrifice 1 of 2", "Disaster evolve: prompt counts the sacrifices")
	box.get_node("CancelPick").pressed.emit()
	await process_frame
	expect(director.disaster_pick.is_empty() and not box.visible, "Disaster evolve: Cancel at step 1 leaves the pick")
	expect(game._get_card_in_slot(lanes[0]) != null and game._get_card_in_slot(lanes[1]) != null
		and game.enemy_hand.size() == 1 and game.disaster_actions.actions_used == 0,
		"Disaster evolve: Cancel at step 1 spends nothing")
	# Cancel at step 2.
	await process_frame
	hand_rows(director)[0].pressed.emit()
	await process_frame
	await press_lane(director, 1)
	expect(box.get_node("Lane1").disabled and not box.get_node("Lane2").disabled
		and box.get_node("Prompt").text == "Sacrifice 2 of 2", "Disaster evolve: a chosen lane is off")
	await press_lane(director, 1)
	expect(director.disaster_pick.chosen.size() == 1, "Disaster evolve: a chosen lane cannot be chosen again")
	await press_lane(director, 3)
	expect(director.disaster_pick.chosen.size() == 1, "Disaster evolve: a lane with no card cannot be chosen")
	await press_lane(director, 2)
	expect(director.disaster_pick.get("kind", "") == "evo_lane", "Disaster evolve: second sacrifice asks for the lane")
	expect(not box.get_node("Lane1").disabled and not box.get_node("Lane2").disabled
		and box.get_node("Lane3").disabled and box.get_node("Lane1").text == "Lane 1",
		"Disaster evolve: only the sacrificed lanes are offered")
	expect(box.get_node("Prompt").text == "Lane for Test Evo:", "Disaster evolve: lane prompt")
	box.get_node("CancelPick").pressed.emit()
	await process_frame
	expect(director.disaster_pick.is_empty() and game._get_card_in_slot(lanes[0]) != null
		and game._get_card_in_slot(lanes[1]) != null and game.enemy_hand.size() == 1
		and game.disaster_actions.actions_used == 0, "Disaster evolve: Cancel at step 2 spends nothing")
	# Esc leaves the pick too.
	await process_frame
	hand_rows(director)[0].pressed.emit()
	await process_frame
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	director._input(esc)
	await process_frame
	expect(director.disaster_pick.is_empty(), "Disaster evolve: Esc leaves the sacrifice pick")
	# Full flow: lane 1, lane 2, then the evolution goes to lane 2.
	await process_frame
	hand_rows(director)[0].pressed.emit()
	await process_frame
	await press_lane(director, 1)
	await press_lane(director, 2)
	await press_lane(director, 2)
	await create_timer(2.5, false).timeout
	var landed = game._get_card_in_slot(lanes[1])
	expect(landed != null and landed.card_data.id == "t_evo4", "Disaster evolve: the evolution is on lane 2")
	expect(game._get_card_in_slot(lanes[0]) == null, "Disaster evolve: the other sacrificed card is gone")
	expect(game.enemy_hand.is_empty() and game.disaster_actions.actions_used == 1 and director.disaster_pick.is_empty(),
		"Disaster evolve: card spent, one action counted")
	game.disaster_actions.end_turn()
	await create_timer(0.7, false).timeout
	# Cost 1: one sacrifice press, no second step.
	var small := evolution.duplicate()
	small.id = "t_evo5"
	small.cost = 1
	await evolve_turn(game, director, small, 2)
	hand_rows(director)[0].pressed.emit()
	await process_frame
	await process_frame
	expect(box.get_node("Prompt").text == "Sacrifice 1 of 1", "Disaster evolve: cost 1 asks for one sacrifice")
	await press_lane(director, 2)
	await create_timer(2.5, false).timeout
	landed = game._get_card_in_slot(lanes[1])
	expect(landed != null and landed.card_data.id == "t_evo5" and game._get_card_in_slot(lanes[0]) != null,
		"Disaster evolve: cost 1 evolves in the pressed lane")
	game.disaster_actions.end_turn()
	await create_timer(0.7, false).timeout
	game.disaster_is_human = false

# A seal spell asks for a Response hand card in the choose_card popup. Cancel and a finished turn close it.
func check_disaster_target_pick(game: Node, director: Node) -> void:
	var seal_spell := test_spell("t_seal3", "seal")
	var done := await wait_human_turn(game, director, [seal_spell])
	expect(hand_rows(director)[0] is Button and hand_rows(director)[0].disabled, "Disaster picking: no target, row is off")
	game.add_card_to_hand({"id": "t_r3", "name": "Test R3", "type": "response", "element": "evac",
		"cost": 1, "attack": 1, "health": 1})
	await process_frame
	await process_frame
	expect(not hand_rows(director)[0].disabled, "Disaster picking: a target turns the spell row on")
	hand_rows(director)[0].pressed.emit()
	await process_frame
	await process_frame
	expect(director.disaster_pick.get("kind", "") == "target" and director.modal.visible,
		"Disaster picking: target popup opens")
	director.action_cancel.call()
	await process_frame
	expect(director.disaster_pick.is_empty() and not director.modal.visible, "Disaster picking: Cancel closes the popup")
	await process_frame
	hand_rows(director)[0].pressed.emit()
	await process_frame
	game.disaster_actions.end_turn()
	await process_frame
	await process_frame
	expect(director.disaster_pick.is_empty() and not director.modal.visible, "Disaster picking: end_turn closes the popup")
	await create_timer(0.7, false).timeout
	# Choosing the target casts the spell.
	done = await wait_human_turn(game, director, [seal_spell])
	game.add_card_to_hand({"id": "t_r4", "name": "Test R4", "type": "response", "element": "evac",
		"cost": 1, "attack": 1, "health": 1})
	await process_frame
	await process_frame
	var target: Node = game.get_hand_cards()[0]
	hand_rows(director)[0].pressed.emit()
	await process_frame
	await process_frame
	# Press the real Choose button on the popup tile, the same path a player uses.
	var tiles: Array = director.content.get_node("Cards/Row").get_children()
	expect(tiles.size() == 1, "Disaster picking: the popup lists the Response hand card")
	tiles[0].get_node("Box/ActionButton").pressed.emit()
	await create_timer(0.5, false).timeout
	expect(game.is_sealed(target.card_data) and game.enemy_hand.is_empty(), "Disaster picking: target is sealed")
	game.disaster_actions.end_turn()
	await create_timer(0.7, false).timeout

func check_prep_failures(prep: Dictionary) -> void:
	var short: Dictionary = prep.duplicate(true)
	short.main.pop_back()
	rejects(Decks.SIDE_PREP, short, "Preparedness with 23 cards fails")
	var long_deck: Dictionary = prep.duplicate(true)
	long_deck.main.append("herb")
	rejects(Decks.SIDE_PREP, long_deck, "Preparedness with 25 cards fails")
	var triple: Dictionary = prep.duplicate(true)
	triple.main[triple.main.size() - 1] = "quick_dash"
	triple.main[triple.main.size() - 2] = "quick_dash"
	rejects(Decks.SIDE_PREP, triple, "Preparedness with 3 copies fails")
	var few_tactics: Dictionary = prep.duplicate(true)
	few_tactics.tactics = ["brace", "coordinate"]
	rejects(Decks.SIDE_PREP, few_tactics, "Preparedness with 2 tactics fails")
	var many_tactics: Dictionary = prep.duplicate(true)
	many_tactics.tactics = ["brace", "coordinate", "medicine", "supply"]
	rejects(Decks.SIDE_PREP, many_tactics, "Preparedness with 4 tactics fails")
	var no_brace: Dictionary = prep.duplicate(true)
	no_brace.tactics = ["coordinate", "medicine", "supply"]
	rejects(Decks.SIDE_PREP, no_brace, "Preparedness without Brace fails")
	var unknown: Dictionary = prep.duplicate(true)
	unknown.main[0] = "not_a_card"
	rejects(Decks.SIDE_PREP, unknown, "Preparedness with unknown card id fails")

func check_disaster_failures(disaster: Dictionary) -> void:
	var short: Dictionary = disaster.duplicate(true)
	short.main.pop_back()
	rejects(Decks.SIDE_DISASTER, short, "Disaster with 23 cards fails")
	var long_deck: Dictionary = disaster.duplicate(true)
	long_deck.main.append("gust")
	rejects(Decks.SIDE_DISASTER, long_deck, "Disaster with 25 cards fails")
	var triple: Dictionary = disaster.duplicate(true)
	triple.main[triple.main.size() - 1] = "ember"
	triple.main[triple.main.size() - 2] = "ember"
	rejects(Decks.SIDE_DISASTER, triple, "Disaster with 3 copies fails")
	var five: Dictionary = disaster.duplicate(true)
	five.evolutions.pop_back()
	rejects(Decks.SIDE_DISASTER, five, "Disaster with 5 evolutions fails")
	var seven: Dictionary = disaster.duplicate(true)
	seven.evolutions.append("worldbreaker")
	rejects(Decks.SIDE_DISASTER, seven, "Disaster with 7 evolutions fails")
	var unknown: Dictionary = disaster.duplicate(true)
	unknown.main[0] = "not_a_card"
	rejects(Decks.SIDE_DISASTER, unknown, "Disaster with unknown card id fails")
	var unknown_evolution: Dictionary = disaster.duplicate(true)
	unknown_evolution.evolutions[0] = "not_a_card"
	rejects(Decks.SIDE_DISASTER, unknown_evolution, "Disaster with unknown evolution id fails")

# Pre-match coin flip: winner from call and result, sides for the winner, who goes first.
func check_prematch_logic() -> void:
	expect(VersusMatch.resolve_winner(0, 0) == 1, "Prematch: call Heads, lands Heads, Player 1 wins")
	expect(VersusMatch.resolve_winner(0, 1) == 2, "Prematch: call Heads, lands Tails, Player 2 wins")
	expect(VersusMatch.resolve_winner(1, 1) == 1, "Prematch: call Tails, lands Tails, Player 1 wins")
	expect(VersusMatch.resolve_winner(1, 0) == 2, "Prematch: call Tails, lands Heads, Player 2 wins")
	var prep := Decks.SIDE_PREP
	var disaster := Decks.SIDE_DISASTER
	expect(VersusMatch.assign_sides(1, prep) == {1: prep, 2: disaster}, "Prematch: Player 1 wins, picks Preparedness")
	expect(VersusMatch.assign_sides(1, disaster) == {1: disaster, 2: prep}, "Prematch: Player 1 wins, picks Disaster")
	expect(VersusMatch.assign_sides(2, prep) == {1: disaster, 2: prep}, "Prematch: Player 2 wins, picks Preparedness")
	expect(VersusMatch.assign_sides(2, disaster) == {1: prep, 2: disaster}, "Prematch: Player 2 wins, picks Disaster")
	expect(VersusMatch.prep_goes_first(prep), "Prematch: Preparedness picked goes first")
	expect(not VersusMatch.prep_goes_first(disaster), "Prematch: Disaster picked goes first")

func coin_logs(game: Node) -> int:
	var count := 0
	for line: String in game.battle_log:
		if line.contains("Coin:"): count += 1
	return count

# Waits in frames (the tree may be paused) until the side wait starts, at most 8 seconds.
func wait_side_ready(versus_node: Node) -> bool:
	var start := Time.get_ticks_msec()
	while not versus_node.prematch_active and Time.get_ticks_msec() - start < 8000:
		await process_frame
	return versus_node.prematch_active

# Waits in frames until the coin line is logged, at most 8 seconds.
func wait_coin_log(game: Node) -> void:
	var start := Time.get_ticks_msec()
	while coin_logs(game) == 0 and Time.get_ticks_msec() - start < 8000:
		await process_frame

func sides_match(versus_node: Node, winner_side: String) -> bool:
	var sides: Dictionary = VersusMatch.assign_sides(versus_node.coin_winner, winner_side)
	return versus_node.player1_side == sides[1] and versus_node.player2_side == sides[2]

# The real match start: one flip, then the side wait, then one round start.
func check_prematch_flow(game: Node, director: Node) -> void:
	var versus_node: Node = director.versus_match
	game.presentation.automated_choice = 0
	versus_node.automated_side = ""
	game.clear_battle()
	director.start_versus_match()
	var epoch: int = game.presentation.coin_epoch
	expect(await wait_side_ready(versus_node), "Prematch flow: waits for the side after the toss")
	expect(game.presentation.coin_epoch == epoch + 1, "Prematch flow: one flip")
	var winner: int = VersusMatch.resolve_winner(0, game.coin_result)
	expect(versus_node.coin_call == 0 and versus_node.coin_winner == winner, "Prematch flow: winner from the call")
	expect(coin_logs(game) == 0, "Prematch flow: no round before the side choice")
	versus_node.choose_side(Decks.SIDE_PREP)
	expect(game.player_first and coin_logs(game) == 1, "Prematch flow: Preparedness picked goes first, one round")
	expect(sides_match(versus_node, Decks.SIDE_PREP), "Prematch flow: sides assigned for Preparedness")
	versus_node.choose_side(Decks.SIDE_DISASTER)
	await process_frame
	expect(game.player_first and coin_logs(game) == 1 and sides_match(versus_node, Decks.SIDE_PREP),
		"Prematch flow: a repeated choice is ignored")
	expect(game.presentation.coin_epoch == epoch + 1, "Prematch flow: still one flip after the choice")
	director.battle_finished(true)
	expect(not versus_node.prematch_active and versus_node.coin_winner == 0 and versus_node.player1_side == "",
		"Prematch flow: finish clears the coin state")
	versus_node.choose_side(Decks.SIDE_DISASTER)
	await process_frame
	expect(coin_logs(game) == 1 and game.player_first, "Prematch flow: a late choice is ignored")
	# The automated hook picks Disaster: the Disaster goes first.
	game.clear_battle()
	versus_node.automated_side = Decks.SIDE_DISASTER
	director.start_versus_match()
	await wait_coin_log(game)
	versus_node.automated_side = ""
	expect(not game.player_first and coin_logs(game) == 1, "Prematch flow: Disaster picked goes first")
	expect(sides_match(versus_node, Decks.SIDE_DISASTER), "Prematch flow: sides assigned for Disaster")
	game.clear_battle()
	director.battle_finished(false)
	await check_prematch_restart(game, director)

# A restart while the side wait is open leaves no old continuation behind.
func check_prematch_restart(game: Node, director: Node) -> void:
	var versus_node: Node = director.versus_match
	game.clear_battle()
	director.start_versus_match()
	expect(await wait_side_ready(versus_node), "Prematch restart: waiting for the side")
	game.clear_battle()
	versus_node.choose_side(Decks.SIDE_PREP)
	await process_frame
	expect(coin_logs(game) == 0, "Prematch restart: a choice after clear_battle starts no round")
	director.battle_finished(true)
	# Finish while waiting, then a new match: only the new wait starts a round.
	game.clear_battle()
	director.start_versus_match()
	expect(await wait_side_ready(versus_node), "Prematch restart: waiting again")
	director.battle_finished(true)
	expect(not versus_node.prematch_active, "Prematch restart: finish ends the wait")
	game.clear_battle()
	director.start_versus_match()
	expect(await wait_side_ready(versus_node), "Prematch restart: the new match waits")
	versus_node.choose_side(Decks.SIDE_PREP)
	await process_frame
	await process_frame
	expect(coin_logs(game) == 1 and game.player_first, "Prematch restart: one choice starts one round")
	game.clear_battle()
	director.battle_finished(true)

# Waits in frames until the condition is true, at most 8 seconds.
func wait_until(condition: Callable) -> bool:
	var start := Time.get_ticks_msec()
	while not condition.call() and Time.get_ticks_msec() - start < 8000:
		await process_frame
	return condition.call()

# All label texts under a node, one per line.
func screen_texts(node: Node) -> String:
	var words := ""
	for label in node.find_children("*", "Label", true, false): words += label.text + "\n"
	return words

# A key press and release through the real input path.
func flip_key_tap(keycode: int) -> void:
	root.push_input(privacy_key(keycode))
	var release := privacy_key(keycode)
	release.pressed = false
	root.push_input(release)

# Esc, L, P, D, G and M, and Space when asked, through the real input path.
func flip_keys(with_space: bool) -> void:
	var keys := [KEY_ESCAPE, KEY_L, KEY_P, KEY_D, KEY_G, KEY_M]
	if with_space: keys.append(KEY_SPACE)
	for keycode: int in keys: flip_key_tap(keycode)
	await privacy_frames()

# Before round 1: no menu, no popup, no pause, still on the coin step.
func flip_keys_ok(game: Node, director: Node) -> bool:
	return not director.modal.visible and not paused and game.phase == game.Phase.SETUP and director.screen == "coin"

# A real Versus match, stopped on the coin screen with no automated call.
func start_flip_match(game: Node, director: Node) -> void:
	game.presentation.automated_choice = -1
	director.versus_match.automated_side = ""
	game.clear_battle()
	director.start_versus_match()
	await wait_until(func(): return is_instance_valid(game.presentation.coin_root))
	await privacy_frames()

# Clicks Heads or Tails so the given player wins, then waits for the side screen.
func flip_call_for(game: Node, winner: int) -> bool:
	var p: Node = game.presentation
	var pick: int = game.coin_result if winner == 1 else 1 - game.coin_result
	await privacy_click(p.choice_buttons[pick].get_global_rect().get_center())
	var line := "Player %d wins the toss." % winner
	var named: bool = await wait_until(func(): return is_instance_valid(p.coin_root) \
		and screen_texts(p.coin_root).contains(line))
	var hidden_in_fade: bool = not game.hand_container.visible
	await wait_until(func(): return is_instance_valid(p.side_root))
	await privacy_frames()
	return named and hidden_in_fade and not game.hand_container.visible

# The coin flip screens with real clicks and keys: coin, toss cover, side choice, first-turn cover.
func check_flip_screens(game: Node, director: Node) -> void:
	await check_flip_player2_prep(game, director)
	await check_flip_player1_disaster(game, director)
	await check_flip_restore(game, director)
	check_flip_singleplayer_coin(game)
	game.presentation.automated_choice = 0

# Complete the mandatory opening choice before checking normal first-turn privacy.
func pick_opening_evolution(game: Node, director: Node, check_cover: bool = false) -> void:
	var cover: CanvasLayer = director.privacy_screen
	await wait_until(func(): return cover.visible)
	if check_cover:
		expect(cover.visible and cover.get_node("%SideLine").text == "DISASTER, choose an evolution"
			and game.phase == game.Phase.SETUP and not game.hand_container.visible,
			"Flip UI: opening evolution cover appears first and hides the Preparedness hand")
	if not cover.visible: return
	await privacy_click(cover.get_node("%ReadyButton").get_global_rect().get_center())
	if not await wait_until(func(): return director.screen == "evolution_offer"): return
	# Restore the original first-turn fixture history after the separate choice cover.
	director.privacy_last = ""
	for button in director.content.find_children("*", "Button", true, false):
		if button.text == "Choose" and button.is_visible_in_tree():
			await privacy_click(button.get_global_rect().get_center())
			break
	await wait_until(func(): return not game.evolution_choice.pending() and game.phase != game.Phase.SETUP)
	await privacy_frames()

func check_flip_player2_prep(game: Node, director: Node) -> void:
	var p: Node = game.presentation
	var cover: CanvasLayer = director.privacy_screen
	var versus_node: Node = director.versus_match
	await start_flip_match(game, director)
	var coin_words := screen_texts(p.coin_root)
	expect(coin_words.contains("PLAYER 1, CALL THE TOSS") and not coin_words.contains("Janitor"),
		"Flip UI: the coin screen asks Player 1 to call")
	expect(not game.hand_container.visible and game.get_hand_cards().size() > 0, "Flip UI: hand hidden on the coin")
	await flip_keys(true)
	expect(flip_keys_ok(game, director) and not p.coin_busy, "Flip UI: keys do nothing on the coin screen")
	expect(await flip_call_for(game, 2), "Flip UI: the result names Player 2, the hand stays hidden")
	expect(is_instance_valid(p.side_root) and p.side_root.get_parent() == p and p.layer > director.layer
		and cover.layer > p.layer, "Flip UI: side screen above the director, the cover above it")
	expect(cover.visible and cover.get_node("%SideLine").text == "PLAYER 2, you won the toss",
		"Flip UI: the cover hands the laptop to Player 2")
	await flip_keys(false)
	expect(flip_keys_ok(game, director) and cover.visible and versus_node.prematch_active,
		"Flip UI: keys do nothing on the toss cover")
	await privacy_click(p.side_buttons[0].get_global_rect().get_center())
	expect(versus_node.prematch_active and cover.visible, "Flip UI: a click behind the cover picks no side")
	flip_key_tap(KEY_SPACE)
	await privacy_frames()
	expect(not cover.visible and versus_node.prematch_active and is_instance_valid(p.side_root),
		"Flip UI: Space closes the toss cover and presses nothing behind it")
	expect(not game.hand_container.visible, "Flip UI: hand hidden on the side screen")
	var side_words := screen_texts(p.side_root)
	expect(side_words.contains("PLAYER 2, PICK A SIDE") and p.side_buttons[0].text == "Preparedness"
		and p.side_buttons[1].text == "Disaster", "Flip UI: the side screen asks Player 2")
	await flip_keys(true)
	expect(flip_keys_ok(game, director) and versus_node.prematch_active, "Flip UI: keys do nothing on the side screen")
	await privacy_click(p.side_buttons[0].get_global_rect().get_center())
	expect(not versus_node.prematch_active and game.player_first and versus_node.player2_side == Decks.SIDE_PREP
		and coin_logs(game) == 1 and game.turn == 1, "Flip UI: Player 2 picks Preparedness, it goes first")
	expect(not is_instance_valid(p.side_root) and not p.blocking, "Flip UI: the side screen closes")
	await pick_opening_evolution(game, director, true)
	await privacy_frames()
	expect(cover.visible and cover.get_node("%SideLine").text == "PLAYER 2 - PREPAREDNESS, it is your turn",
		"Flip UI: the first-turn cover names Player 2")
	expect(not game.hand_container.visible, "Flip UI: hand hidden under the first-turn cover")
	await flip_keys(false)
	expect(cover.visible and not director.modal.visible and not paused, "Flip UI: keys do nothing on the first cover")
	var turn_phase: int = game.phase
	flip_key_tap(KEY_SPACE)
	await privacy_frames()
	expect(not cover.visible and game.phase == turn_phase and turn_phase in [game.Phase.PLAYER_DRAW,
		game.Phase.PLAYER_PLAY], "Flip UI: Space closes the first cover and does not end the turn")
	expect(game.hand_container.visible, "Flip UI: the hand shows after the first player's Ready")
	game.clear_battle()
	director.battle_finished(true)

func check_flip_player1_disaster(game: Node, director: Node) -> void:
	var p: Node = game.presentation
	var cover: CanvasLayer = director.privacy_screen
	var versus_node: Node = director.versus_match
	await start_flip_match(game, director)
	expect(await flip_call_for(game, 1), "Flip UI: the result names Player 1, the hand stays hidden")
	expect(not cover.visible and screen_texts(p.side_root).contains("PLAYER 1, PICK A SIDE"),
		"Flip UI: no toss cover when Player 1 wins")
	await privacy_click(p.side_buttons[1].get_global_rect().get_center())
	expect(not game.player_first and versus_node.player1_side == Decks.SIDE_DISASTER,
		"Flip UI: Player 1 picks Disaster, it goes first")
	await pick_opening_evolution(game, director)
	expect(await wait_until(func(): return cover.visible), "Flip UI: the Disaster-first cover goes up")
	expect(game.disaster_waiting and cover.get_node("%SideLine").text == "PLAYER 1 - DISASTER, it is your turn",
		"Flip UI: the Disaster-first cover names Player 1")
	expect(not game.hand_container.visible, "Flip UI: hand hidden under the Disaster-first cover")
	await flip_keys(false)
	expect(cover.visible and not director.modal.visible and not paused, "Flip UI: keys do nothing on that cover")
	await privacy_click(cover.get_node("%ReadyButton").get_global_rect().get_center())
	expect(not cover.visible and game.hand_container.visible, "Flip UI: Ready closes the Disaster-first cover")
	await privacy_frames()
	await privacy_frames()
	expect(not cover.visible and game.is_hand_tucked, "Flip UI: the cover is raised once, the Preparedness hand is tucked")
	game.clear_battle()
	director.battle_finished(true)

# The hand comes back on a restart and when the match ends on the side screen.
func check_flip_restore(game: Node, director: Node) -> void:
	var p: Node = game.presentation
	await start_flip_match(game, director)
	expect(not game.hand_container.visible, "Flip restore: hand hidden on the coin")
	game.clear_battle()
	expect(game.hand_container.visible and not game.versus_hand_hidden, "Flip restore: a restart shows the hand")
	director.battle_finished(true)
	await start_flip_match(game, director)
	await flip_call_for(game, 2)
	director.battle_finished(true)
	await privacy_frames()
	expect(game.hand_container.visible and not is_instance_valid(p.side_root) and not p.blocking
		and not director.privacy_screen.visible, "Flip restore: the match ending on the side screen cleans up")
	game.clear_battle()

# Singleplayer keeps its coin words, and never hides the hand.
func check_flip_singleplayer_coin(game: Node) -> void:
	var p: Node = game.presentation
	game.clear_battle()
	game.encounter_kind = "battle"
	p.choose_coin(0)
	var words := screen_texts(p.coin_root)
	expect(words.contains("CALL THE COIN") and words.contains("Choose a side. Match the toss to take the first turn.")
		and not words.contains("PLAYER"), "Flip singleplayer: coin words unchanged")
	expect(game.hand_container.visible and not game.versus_hand_hidden, "Flip singleplayer: hand not hidden")
	p.cancel_coin()
