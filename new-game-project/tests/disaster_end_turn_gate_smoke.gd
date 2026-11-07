# Covers: audit A2. After End Turn is accepted, every later play, cast and end request is refused
# until the next turn opens the gate. Cards and resources must not change.
extends SceneTree

var checks := 0
var failures := 0
var game: Node

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + text)

func frames(count: int = 4) -> void:
	for i in count: await process_frame

func wait_until(predicate: Callable) -> bool:
	var start := Time.get_ticks_msec()
	while not predicate.call() and Time.get_ticks_msec() - start < 4000: await process_frame
	return predicate.call()

func base_card() -> Dictionary:
	return {"id": "ember", "name": "Ember", "type": "disaster", "element": "fire",
		"cost": 0, "attack": 1, "health": 2}

func spell_card() -> Dictionary:
	return {"id": "gate_spell", "name": "Gate Spell", "type": "disaster", "element": "fire",
		"cost": 0, "utility": true, "effect": "none", "tension_cost": 1}

func empty_threat_slot() -> Node3D:
	for slot in game._threat_slots():
		if game._get_card_in_slot(slot) == null: return slot
	return null

func board_count() -> int:
	var count := 0
	for slot in game._threat_slots():
		if game._get_card_in_slot(slot) != null: count += 1
	return count

func open_disaster_turn() -> void:
	paused = false
	game.clear_battle()
	game.encounter_kind = "versus"
	game.disaster_is_human = true
	game.evolution_draw_choice_override = false
	game.turn = 3
	game.set_seats("local", "local")
	game.enemy_deck.assign([base_card(), base_card()])
	game.run_director.battle_active = true
	game.run_director.encounter = "versus"
	game.run_director.close_modal()
	game._enemy_turn()
	if await wait_until(func(): return game.disaster_draw.waiting):
		game._on_draw_button_pressed()
	await wait_until(func(): return game.disaster_waiting and not game.disaster_actions.busy)

func check_gate() -> void:
	await open_disaster_turn()
	var actions: RefCounted = game.disaster_actions
	expect(game.disaster_waiting and not actions.turn_closed, "the turn is open before End Turn")
	game.enemy_hand.append(base_card())
	game.enemy_hand.append(spell_card())
	var base: Dictionary = game.enemy_hand[game.enemy_hand.size() - 2]
	var spell: Dictionary = game.enemy_hand.back()
	var slot := empty_threat_slot()
	var open_play: bool = actions._base_problem(base, slot).is_empty()
	expect(open_play, "before End Turn the base card could be played")
	var hand_before: int = game.enemy_hand.size()
	var board_before := board_count()
	var tension_before: int = game.tension
	var used_before: int = actions.actions_used
	var ended: Dictionary = actions.end_turn()
	expect(ended.ok and actions.turn_closed, "End Turn is accepted and closes the gate")
	# Same frame: the enemy phase is still ENEMY, so only the gate can refuse these.
	expect(game.phase == game.Phase.ENEMY, "the phase is still the Disaster phase")
	var late_base: Dictionary = await actions.play_base(base, slot)
	expect(not late_base.ok and late_base.reason == "turn_ended", "a late base play is refused")
	var late_cast: Dictionary = await actions.cast(spell, null)
	expect(not late_cast.ok and late_cast.reason == "turn_ended", "a late cast is refused")
	var late_evolve: Dictionary = await actions.evolve(base, [], slot)
	expect(not late_evolve.ok and late_evolve.reason == "turn_ended", "a late evolution is refused")
	var late_end: Dictionary = actions.end_turn()
	expect(not late_end.ok and late_end.reason == "turn_ended", "a second End Turn is refused")
	expect(not actions.card_problem(base).is_empty(), "hand rows are dimmed after End Turn")
	expect(game.enemy_hand.size() == hand_before, "the hand is unchanged")
	expect(board_count() == board_before, "the board is unchanged")
	expect(game.tension == tension_before, "tension is unchanged")
	expect(actions.actions_used == used_before, "no action was spent")
	# The next turn opens the gate again.
	await wait_until(func(): return game.phase != game.Phase.ENEMY)
	actions.begin_turn()
	expect(not actions.turn_closed, "begin_turn opens the gate")

func run() -> void:
	root.size = Vector2i(1280, 800)
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	game.run_director.persistence.enabled = false
	await check_gate()
	game.clear_battle()
	if failures > 0:
		push_error("disaster_end_turn_gate_smoke: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: disaster_end_turn_gate_smoke (%d checks)" % checks)
	quit(0)
