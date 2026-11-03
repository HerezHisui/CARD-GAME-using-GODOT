# Covers: Versus deck rules (versus_decks.gd): presets, deck size, copies, evolutions, tactics, unknown ids.
# Also covers the Versus match (versus_match.gd): encounter kind, run_active, saves untouched, state restored.
extends SceneTree

const Decks = preload("res://scripts/versus_decks.gd")

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
	expect(game.enemy_action_limit() == 3, "Versus %s: fixed Disaster action limit" % label)
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
	await check_ai_uses_actions(game, director)
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
	expect(actions.action_limit == 3 and actions.actions_left() == 3, "Disaster actions: limit is 3 with 5 tension")
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
	expect(actions.actions_used == 3 and actions.actions_left() == 0, "Disaster actions: three actions used")
	game.enemy_hand.append(base)
	expect(reason_of(await actions.play_base(base, game._threat_slots()[3])) == "action_limit",
		"Disaster actions: the 4th action is refused")
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
