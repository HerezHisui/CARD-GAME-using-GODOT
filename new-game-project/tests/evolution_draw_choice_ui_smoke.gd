extends SceneTree

const Decks = preload("res://scripts/versus_decks.gd")
var checks := 0
var failures := 0
var render := false

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAILED: " + message)

func frames(count: int = 5) -> void:
	for i in count: await process_frame

func click(button: Button) -> void:
	await click_point(button.get_global_rect().get_center())

func click_point(point: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = point
	root.push_input(move, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
		await process_frame

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	await process_frame

func buttons(node: Node) -> Array:
	var result: Array = []
	if node is Button: result.append(node)
	for child in node.get_children(): result += buttons(child)
	return result

func capture(name: String) -> void:
	if not render: return
	await frames(30)
	await RenderingServer.frame_post_draw
	var path := "C:/Users/0stef/Downloads/evolution-stage1-checks/" + name + ".png"
	expect(root.get_texture().get_image().save_png(path) == OK, "Rendered capture " + name)

func run() -> void:
	render = "--render-evolution" in OS.get_cmdline_user_args()
	var game: Node = load("res://scenes/game_3d.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await frames()
	game.clear_battle()
	game.encounter_kind = "versus"
	game.disaster_is_human = true
	game.disaster_seat_view = true
	game.evolution_draw_choice_override = true
	game.presentation.automated_choice = 0
	var director: Node = game.run_director
	director.battle_active = true
	director.close_modal()
	director.privacy_serial = game.encounter_serial
	director.privacy_last = "disaster"
	game._set_phase(game.Phase.ENEMY)
	game.disaster_waiting = true
	game.tension = 6
	game.disaster_actions.begin_turn()
	var pool: Dictionary = Decks.pool("disaster")
	game.enemy_evolution_deck.assign([pool.evolutions.wildfire.duplicate(true),
		pool.evolutions.worldbreaker.duplicate(true), pool.evolutions.wildfire.duplicate(true)])
	game.enemy_draw_evolutions(1)
	var choice: RefCounted = game.evolution_choice
	choice.show_offer()
	await frames()
	expect(director.screen == "evolution_offer", "Offer screen opens")
	expect(not paused, "Offer does not pause processing")
	expect(not director.content.get_node("CancelButton").visible, "Mandatory offer has no cancel")
	await key(KEY_ESCAPE)
	expect(choice.pending() and director.modal.visible, "Esc preserves mandatory offer")
	expect(not game.disaster_actions.end_turn().ok, "Pending offer blocks End turn")
	await click(director.menu_button)
	expect(director.screen == "evolution_offer", "Mouse Menu cannot replace mandatory offer")
	await capture("evolution-offer")
	var pick: Button
	for button in buttons(director.content):
		if button.text == "Choose":
			pick = button
			break
	expect(pick != null, "Offer has real pick buttons")
	if pick != null: await click(pick)
	await frames()
	expect(choice.held.size() == 1 and not choice.pending(), "Real click accepts one physical card")
	expect(not director.modal.visible and game.enemy_hand.is_empty(), "Pick closes offer and leaves main hand empty")
	await frames(20)
	var hud: Node = director.versus_hud
	expect(hud.disaster_plans.text == "Evolution", "Host placeholder becomes Evolution")
	expect(hud.disaster_plans.visible, "Evolution button visible on Disaster host")
	await capture("evolution-host-button")
	await click(hud.disaster_plans)
	await frames()
	expect(director.modal.visible, "Evolution button opens held browser")
	expect(game.enemy_evolution_deck.size() == 2, "Browser does not draw")
	choice._preview(choice.held[0].definition)
	await frames()
	expect(game.disaster_seat.selected != null, "Browser card becomes seat preview")
	await key(KEY_ESCAPE)
	await frames()
	expect(choice.held.size() == 1 and choice.preview_id.is_empty(), "Esc returns preview without consuming")
	expect(director.modal.visible, "Cancel returns to held browser")
	director.close_modal()
	var snapshot: RefCounted = preload("res://scripts/battle_snapshot.gd").new().capture(game)
	expect(snapshot.zones.disaster.held_evolutions.size() == 1, "Snapshot captures held zone")
	var copy: RefCounted = preload("res://scripts/battle_state.gd").new()
	copy.load_snapshot(snapshot.to_dict())
	expect(copy.zones == snapshot.zones, "Detached snapshot round-trip preserves zone")
	var held_id: String = choice.held[0].id
	var definition: Dictionary = choice.definition(held_id)
	var refused: Dictionary = await game.disaster_actions.evolve(definition, [], game._threat_slots()[0], held_id)
	expect(not refused.ok and choice.held.size() == 1, "Invalid sacrifices preserve held source")
	# Host Preparedness utility completion uses an opaque held-zone address.
	game._set_phase(game.Phase.PLAYER_PLAY)
	for effect in ["tax", "seal"]:
		game.add_card_to_hand({"id": "test_" + effect, "name": "Test " + effect,
			"type": "response", "cost": 0, "utility": true, "effect": effect})
		var utility: Node = game.get_hand_cards()[-1]
		game.pending_utility = utility
		game.pending_effect = effect
		game.complete_utility_choice({"zone": "held_evolutions", "id": held_id})
		expect(game.pending_utility == null, "Host completes held " + effect)
	expect(definition.has("tax_original") and game.is_sealed(definition), "Held tax and seal both applied")
	game.add_card_to_hand({"id": "test_stale", "name": "Stale", "type": "response",
		"cost": 0, "utility": true, "effect": "tax"})
	game.pending_utility = game.get_hand_cards()[-1]
	game.pending_effect = "tax"
	var count: int = game.get_hand_cards().size()
	game.complete_utility_choice({"zone": "held_evolutions", "id": "forged"})
	expect(game.get_hand_cards().size() == count, "Stale target does not consume utility")
	game._set_phase(game.Phase.ENEMY)
	# Exercise the real action owner with an explicit held source and two sacrifices.
	definition.cost = 2
	definition.erase("locked_until")
	var base: Dictionary = pool.base.ember.duplicate(true)
	for lane in range(2):
		var unit: Node = game.Card3DScene.instantiate()
		game.add_child(unit)
		unit.setup(base.duplicate(true))
		unit.in_hand = false
		unit.current_slot = game._threat_slots()[lane]
		unit.position = unit.current_slot.position
		unit.add_to_group("cards")
	var used: int = game.disaster_actions.actions_used
	choice._preview(definition)
	await frames()
	await click_point(game.camera.unproject_position(game._threat_slots()[0].global_position))
	expect(not game.disaster_seat.evo.is_empty(), "Lane click starts held sacrifice selection")
	await click_point(game.camera.unproject_position(game._threat_slots()[1].global_position))
	for attempt in 100:
		if game.disaster_actions.actions_used > used: break
		await create_timer(0.1, true).timeout
	expect(choice.held.is_empty(), "Real lane and sacrifice clicks consume held source")
	expect(game.disaster_actions.actions_used == used + 1, "Held play counts one action")
	var landed: Node = game._get_card_in_slot(game._threat_slots()[0])
	expect(landed != null and landed.card_data.id == definition.id, "Held evolution lands in sacrifice lane")
	expect(game._get_card_in_slot(game._threat_slots()[1]) == null, "Second sacrifice removed")
	game._set_phase(game.Phase.GAME_OVER)
	expect(choice.held.is_empty() and not choice.pending(), "Match end invalidates private state")
	game.clear_battle()
	# A real opening flow must reach the mandatory choice after side selection.
	director.start_versus_match()
	director.versus_match.automated_side = "disaster"
	for attempt in 400:
		if director.privacy_screen.visible: director._hide_privacy_screen()
		if director.screen == "evolution_offer": break
		await create_timer(0.01, true).timeout
	expect(director.screen == "evolution_offer", "Real opening reaches offer after side selection")
	expect(game.enemy_evolution_deck.size() == 6, "Opening offer preserves full reserve until pick")
	expect(not game.hand_container.visible, "Preparedness hand stays hidden during Disaster opening choice")
	if choice.pending():
		var entry: Dictionary = choice.offer[0]
		choice.pick(entry.id, choice.offer_id, game.encounter_serial)
		director.close_modal()
	for attempt in 100:
		if director.privacy_screen.visible: director._hide_privacy_screen()
		if game.disaster_waiting: break
		await create_timer(0.01, true).timeout
	expect(choice.held.size() == 1 and game.disaster_waiting, "Opening pick proceeds to human Disaster turn")
	game._set_phase(game.Phase.GAME_OVER)
	game.clear_battle()
	game.queue_free()
	await frames()
	print("%s: evolution_draw_choice_ui_smoke (%d checks)" % ["FAIL" if failures else "PASS", checks])
	quit(1 if failures else 0)
