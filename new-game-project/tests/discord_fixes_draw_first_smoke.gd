# Covers: DRAW A CARD FIRST (Discord fix, item 2). Disaster draw button and the Preparedness draw step refuse
# a play before the draw. A drawn Disaster card shows first; plays open only when the turn begins.
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

func definition() -> Dictionary:
	return {"id": "ember", "name": "Ember", "type": "disaster", "element": "fire",
		"cost": 0, "attack": 1, "health": 2}

func press(point: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event

func center(polygon: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for point in polygon: sum += point
	return sum / maxf(1.0, float(polygon.size()))

func versus_fixture() -> void:
	paused = false
	game.clear_battle()
	game.encounter_kind = "versus"
	game.disaster_is_human = true
	game.disaster_seat_view = true
	game.evolution_draw_choice_override = false
	game.turn = 3
	game.set_seats("local", "local")
	game.enemy_deck.assign([definition(), definition()])
	game.run_director.battle_active = true
	game.run_director.encounter = "versus"
	game.run_director.close_modal()
	game.run_director.privacy_serial = game.encounter_serial
	game.run_director.privacy_last = "disaster"
	game.run_director.privacy_screen.hide()

func empty_threat_slot() -> Node3D:
	for slot in game._threat_slots():
		if game._get_card_in_slot(slot) == null: return slot
	return null

func check_disaster() -> void:
	versus_fixture()
	var flags: Script = load("res://scripts/versus_match.gd")
	if not flags.get_script_constant_map().get("DISASTER_DRAW_BUTTON", false):
		expect(true, "Draw button flag is off: Disaster part skipped")
		return
	game._enemy_turn()
	expect(await wait_until(func(): return game.disaster_draw.waiting), "Disaster turn waits for the draw")
	game.enemy_hand.append(definition())
	var held: Dictionary = game.enemy_hand.back()
	var hand_before: int = game.enemy_hand.size()
	var refused: Dictionary = await game.disaster_actions.play_base(held, empty_threat_slot())
	expect(not refused.ok and refused.reason == "draw_first", "a play before the draw gives draw_first")
	expect(game.run_director.DISASTER_REASONS.get("draw_first", "") == "DRAW A CARD FIRST", "reason text")
	expect(game.enemy_hand.size() == hand_before, "the refused card stays in the hand")
	await frames()
	var seat: Node = game.disaster_seat
	if seat.active and not seat.cards.is_empty():
		var card: Node3D = seat.cards[0]
		var event := press(center(seat._polygon(card, false)))
		expect(seat._warn_draw_first(event), "a hand click before the draw shows the warning")
	game._on_draw_button_pressed()
	await process_frame
	expect(not game.disaster_draw.waiting, "the draw button draws")
	expect(game.enemy_hand.size() == hand_before + 1, "the drawn card is in the hand")
	await frames(2)
	# The draw and the first play never share a frame: busy holds until begin_turn().
	expect(game.disaster_actions.busy, "plays stay blocked while the drawn card shows")
	var early: Dictionary = await game.disaster_actions.play_base(held, empty_threat_slot())
	expect(not early.ok, "no play in the same moment as the draw")
	expect(await wait_until(func(): return game.disaster_waiting and not game.disaster_actions.busy),
		"plays open when the Disaster turn begins")
	expect(game.disaster_actions.actions_used == 0, "the turn starts with no action spent")
	game.disaster_actions.end_turn()
	await frames()

func check_preparedness() -> void:
	versus_fixture()
	game.disaster_is_human = false
	game.deck.assign([{"id": "scout", "name": "Scout", "type": "response", "element": "evac",
		"cost": 1, "attack": 1, "health": 2}])
	game.add_card_to_hand({"id": "medic", "name": "Medic", "type": "response", "element": "evac",
		"cost": 1, "attack": 1, "health": 2})
	game._set_phase(game.Phase.PLAYER_DRAW, "Your turn - draw a card from the deck")
	await frames(30)
	var card: Node = game.get_hand_cards()[0]
	var point := center(game.hand_card_polygon(card, true))
	expect(game.preparedness_actions.hand_problem(0) == "draw_first", "host reason before the draw is draw_first")
	expect(game.warn_draw_first(point), "Versus: a hand press before the draw shows the warning")
	root.push_input(press(point), true)
	await frames()
	expect(game.phase == game.Phase.PLAYER_DRAW and card.in_hand and not card.is_dragging,
		"the card is not played or dragged")
	game.encounter_kind = ""
	expect(not game.warn_draw_first(point), "singleplayer keeps its old silent refusal")
	game.encounter_kind = "versus"
	game._on_draw_button_pressed()
	expect(game.phase == game.Phase.PLAYER_PLAY, "after the draw the play phase opens")
	expect(not game.warn_draw_first(point), "no warning after the draw")

func run() -> void:
	root.size = Vector2i(1280, 800)
	game = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	game.run_director.persistence.enabled = false
	await check_disaster()
	await check_preparedness()
	game.clear_battle()
	if failures > 0:
		push_error("discord_fixes_draw_first_smoke: %d of %d checks failed" % [failures, checks])
		quit(1)
		return
	print("PASS: discord_fixes_draw_first_smoke (%d checks)" % checks)
	quit(0)
